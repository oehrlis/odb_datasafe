#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_fleet_assessment_stats.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.11.24
# Version....: v1.3.2
# Purpose....: Read-only fleet aggregates from Data Safe LATEST user and security
#              assessments (counts, shares, medians - no identifiers on stdout)
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '1.3.2')"
readonly SCRIPT_VERSION
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${IDLE_DAYS:=90}"
: "${DBA_THRESHOLD:=5}"
: "${TOP_K:=10}"
: "${KEEP_WORKDIR:=false}"
: "${WORKDIR:=}"
: "${TARGETS_TOTAL:=0}"
: "${UA_TOTAL:=0}"
: "${UA_FAILED:=0}"

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

setup_error_handling
# Initialize configuration
init_config

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display script usage information
# Args....: None
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Read-only fleet aggregates from the LATEST Data Safe user and security
  assessments in a compartment subtree: target lifecycle counts, accounts,
  DBA role holders, expired / idle / never-logged-in accounts, account-status
  breakdown, top HIGH security assessment findings and the snapshot range.
  Output is counts, shares and medians only - never user names, target names
  or OCIDs. Raw JSON stays in a temp workdir that is removed at exit.

Options:
  Common:
    -h, --help                          Show this help message
    -V, --version                       Show version
    -v, --verbose                       Enable verbose output
    -d, --debug                         Enable debug output
    -q, --quiet                         Suppress INFO messages (warnings/errors only)
    -n, --dry-run                       Accepted for consistency (script is read-only anyway)
    --log-file FILE                     Log to file

  OCI:
    --oci-profile PROFILE               OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION                 OCI region
    --oci-config FILE                   OCI config file (default: ${OCI_CLI_CONFIG_FILE:-~/.oci/config})

  Selection:
    -c, --compartment ID                Compartment OCID or name (default: DS_ROOT_COMP)
                                        Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf

  Thresholds:
        --idle-days N                   Idle if last login is older than N days (default: ${IDLE_DAYS})
        --dba-threshold N               Count targets with more than N DBA role holders (default: ${DBA_THRESHOLD})
        --top N                         Top N HIGH findings by affected targets (default: ${TOP_K})

  Workdir:
        --keep-workdir                  Keep the temp workdir with raw JSON (contains identifiers!)

Examples:
    # Fleet aggregates for DS_ROOT_COMP
    ${SCRIPT_NAME}

    # Other profile, 180 days idle, targets with more than 3 DBA holders, top 5 findings
    ${SCRIPT_NAME} --oci-profile MYPROFILE --idle-days 180 --dba-threshold 3 --top 5

    # Keep raw JSON for follow-up (delete it afterwards)
    ${SCRIPT_NAME} -c my-compartment --keep-workdir

Notes:
  - WARN lines on stderr report failed list-users calls and missing fields;
    figures then cover the remaining data only - never silently.
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Remove the temp workdir unless --keep-workdir was given
# Args....: None
# Returns.: 0
# Output..: Hint with workdir path on stderr when kept
# ------------------------------------------------------------------------------
cleanup() {
    if [[ -n "${WORKDIR}" && -d "${WORKDIR}" ]]; then
        if [[ "${KEEP_WORKDIR}" == "true" ]]; then
            echo "Workdir kept (contains identifiers, delete when done): ${WORKDIR}" >&2
        else
            rm -rf "${WORKDIR}"
        fi
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables based on arguments
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    set -- ${ARGS[@]+"${ARGS[@]}"}

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            --idle-days)
                need_val "$1" "${2:-}"
                IDLE_DAYS="$2"
                shift 2
                ;;
            --dba-threshold)
                need_val "$1" "${2:-}"
                DBA_THRESHOLD="$2"
                shift 2
                ;;
            --top)
                need_val "$1" "${2:-}"
                TOP_K="$2"
                shift 2
                ;;
            --keep-workdir)
                KEEP_WORKDIR=true
                shift
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                die "Unexpected argument: $1 (use --help for usage)"
                ;;
        esac
    done

    local opt val
    for opt in IDLE_DAYS DBA_THRESHOLD TOP_K; do
        val="${!opt}"
        [[ "$val" =~ ^[0-9]+$ ]] || die "Invalid value for ${opt}: '${val}' (expected a non-negative integer)"
    done
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Check OCI CLI, resolve compartment, create workdir
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Sets COMPARTMENT (OCID) and WORKDIR
# ------------------------------------------------------------------------------
validate_inputs() {
    require_oci_cli
    COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") \
        || die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help) or use -c/--compartment"
    [[ -n "$COMPARTMENT" ]] || die "Compartment resolved to an empty value"

    if [[ -z "$WORKDIR" ]]; then
        WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ds_fleet_stats.XXXXXX")" || die "Cannot create workdir"
    else
        mkdir -p "$WORKDIR"
    fi
    chmod 700 "$WORKDIR"
}

# ------------------------------------------------------------------------------
# Function: iso_days_ago
# Purpose.: Timestamp (UTC, ISO without zone) N days ago, BSD and GNU date
# Args....: $1 - days
# Returns.: 0
# Output..: YYYY-MM-DDTHH:MM:SS
# ------------------------------------------------------------------------------
iso_days_ago() {
    date -u -v-"$1"d +%Y-%m-%dT%H:%M:%S 2> /dev/null \
        || date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%S
}

# ------------------------------------------------------------------------------
# Function: report_targets
# Purpose.: Target lifecycle counts
# Args....: None
# Returns.: 0
# Output..: Counts to stdout; sets TARGETS_TOTAL
# ------------------------------------------------------------------------------
report_targets() {
    if ! oci_exec_ro data-safe target-database list "${SUB_ARGS[@]}" > "${WORKDIR}/targets.json"; then
        log_warn "target-database list failed - target counts missing"
        echo "targets total: n/a"
        return 0
    fi
    TARGETS_TOTAL=$(jq -r '(.data // []) | length' "${WORKDIR}/targets.json")
    echo "targets total: ${TARGETS_TOTAL}"
    jq -r '(.data // []) | group_by(."lifecycle-state" // "UNKNOWN")[] | "  \(.[0]."lifecycle-state" // "UNKNOWN"): \(length)"' \
        "${WORKDIR}/targets.json"
}

# ------------------------------------------------------------------------------
# Function: snapshot_range
# Purpose.: Oldest/newest assessment date of a LATEST assessment list
# Args....: $1 - label, $2 - JSON file
# Returns.: 0
# Output..: One line to stdout, WARN for assessments without date
# ------------------------------------------------------------------------------
snapshot_range() {
    local label="$1" file="$2"
    jq -r --arg l "$label" '
        (.data // []) as $d
        | ($d | map(."time-last-assessed" // ."time-updated" // ."time-created" // empty | .[0:10])) as $t
        | if ($t | length) == 0 then "\($l): \($d | length) assessments, no assessment dates found"
          else "\($l): \($d | length) assessments, oldest \($t | min), newest \($t | max)" end' "$file"
    local missing
    missing=$(jq -r '(.data // []) | map(select((."time-last-assessed" // ."time-updated" // ."time-created") == null)) | length' "$file")
    if [[ "$missing" -gt 0 ]]; then
        log_warn "${label}: ${missing} assessment(s) without a date field - not part of the snapshot range"
    fi
}

# ------------------------------------------------------------------------------
# Function: collect_users
# Purpose.: list-users per LATEST user assessment into users.jsonl (+ ok list)
# Args....: None
# Returns.: 0
# Output..: WARN on failures (stderr); sets UA_TOTAL, UA_FAILED
# ------------------------------------------------------------------------------
collect_users() {
    : > "${WORKDIR}/users.jsonl"
    : > "${WORKDIR}/ua_ok.jsonl"
    UA_TOTAL=0
    UA_FAILED=0
    local ua n=0
    while IFS= read -r ua; do
        [[ -n "$ua" ]] || continue
        n=$((n + 1))
        log_info "list-users ${n}"
        if oci_exec_ro data-safe user-assessment list-users --user-assessment-id "$ua" --all > "${WORKDIR}/lu.json" \
            && jq -e '(.data // null) | type == "array"' "${WORKDIR}/lu.json" > /dev/null 2>&1; then
            jq -c --arg ua "$ua" '.data[] | {ua: $ua, st: ."account-status", roles: ."admin-roles",
                last: ."time-last-login", has_last: has("time-last-login")}' "${WORKDIR}/lu.json" \
                >> "${WORKDIR}/users.jsonl"
            jq -n --arg ua "$ua" '$ua' >> "${WORKDIR}/ua_ok.jsonl"
        else
            UA_FAILED=$((UA_FAILED + 1))
            log_warn "list-users failed or returned no data array for assessment #${n} - not counted"
        fi
    done < <(jq -r '(.data // [])[].id // empty' "${WORKDIR}/ua.json")
    UA_TOTAL=$n
    rm -f "${WORKDIR}/lu.json"
}

# ------------------------------------------------------------------------------
# Function: report_users
# Purpose.: Aggregate users.jsonl into counts, shares and medians
# Args....: None
# Returns.: 0
# Output..: Aggregates to stdout, field WARNs to stderr
# ------------------------------------------------------------------------------
report_users() {
    local cutoff
    cutoff=$(iso_days_ago "$IDLE_DAYS")

    local nusers
    nusers=$(wc -l < "${WORKDIR}/users.jsonl" | tr -d ' ')
    if [[ "$nusers" -eq 0 ]]; then
        log_warn "no user records collected - account figures not available"
        echo "accounts total: n/a"
        return 0
    fi

    # Missing-field warnings (never silent)
    local miss_st miss_roles miss_last
    miss_st=$(jq -s 'map(select(.st == null)) | length' "${WORKDIR}/users.jsonl")
    miss_roles=$(jq -s 'map(select(.roles == null)) | length' "${WORKDIR}/users.jsonl")
    miss_last=$(jq -s 'map(select(.has_last | not)) | length' "${WORKDIR}/users.jsonl")
    if [[ "$miss_st" -gt 0 ]]; then
        log_warn "${miss_st} user record(s) without account-status - listed as UNKNOWN"
    fi
    if [[ "$miss_roles" -gt 0 ]]; then
        log_warn "${miss_roles} user record(s) without admin-roles - not counted as DBA holders"
    fi
    if [[ "$miss_last" -gt 0 ]]; then
        log_warn "${miss_last} user record(s) without time-last-login field - counted as never logged in"
    fi

    jq -rs --arg cut "$cutoff" --argjson idle "$IDLE_DAYS" --argjson thr "$DBA_THRESHOLD" \
        --slurpfile ok "${WORKDIR}/ua_ok.jsonl" '
        def median: sort | if length == 0 then null elif length % 2 == 1 then .[length/2|floor]
            else (.[length/2-1] + .[length/2]) / 2 end;
        def pct(a; b): if b == 0 then "n/a" else ((a * 1000 / b | round) / 10 | tostring) + "%" end;
        def num(x): if x == null then "n/a" else (x | tostring) end;
        . as $u | ($u | length) as $tot
        | ($u | group_by(.ua) | map({key: .[0].ua, value: .}) | from_entries) as $by
        | ($ok | map(. as $id | ($by[$id] // []) | map(select((.roles // []) | any(. == "DBA"))) | length)) as $dba
        | ($ok | length) as $dbs
        | ($u | map(select((.st // "") | test("EXPIRED"))) | length) as $exp
        | ($u | map(select(.last != null and .last < $cut)) | length) as $idl
        | ($u | map(select(.last == null)) | length) as $never
        | ($dba | map(select(. > $thr)) | length) as $over
        | "databases with user data: \($dbs)",
          "accounts total: \($tot)",
          "DBA role holders total: \($dba | add // 0), median per target: \(num($dba | median)), targets with more than \($thr): \($over) (\(pct($over; $dbs)))",
          "expired accounts: \($exp) (\(pct($exp; $tot)))",
          "idle \($idle)+ days: \($idl) (\(pct($idl; $tot)))",
          "never logged in: \($never) (\(pct($never; $tot)))",
          "account-status breakdown:",
          ($u | group_by(.st // "UNKNOWN")[] | "  \(.[0].st // "UNKNOWN"): \(length) (\(pct(length; $tot)))")
        ' "${WORKDIR}/users.jsonl"
}

# ------------------------------------------------------------------------------
# Function: report_findings
# Purpose.: Top-K HIGH findings by number of affected targets
# Args....: None
# Returns.: 0
# Output..: "<targets> <share> <finding key> <title>" lines to stdout
# ------------------------------------------------------------------------------
report_findings() {
    if ! oci_exec_ro data-safe security-assessment list-finding-analytics "${SUB_ARGS[@]}" \
        --group-by findingKeyAndSeverity --severity HIGH > "${WORKDIR}/sa_high.json"; then
        log_warn "list-finding-analytics failed - HIGH findings not available"
        echo "top HIGH findings: n/a"
        return 0
    fi

    local parsed=""
    parsed=$(jq -r --argjson k "$TOP_K" --argjson tt "$TARGETS_TOTAL" '
        ((.data.items? // .data? // []) | if type == "array" then . else [] end) as $items
        | $items
        | map({n: (.metric?."targets-count" // ."targets-count" // .metric?.count // .count),
               key: (.dimensions?."finding-key" // .dimension?."finding-key" // ."finding-key" // .key),
               title: (.dimensions?.title // .dimension?.title // .title // "")})
        | "ITEMS\t\(length)\t\(map(select(.n == null)) | length)\t\(map(select(.key == null)) | length)",
          (map(select(.n != null)) | sort_by(-.n) | .[:$k][]
           | "\(.n)\t\(if $tt > 0 then (((.n * 1000 / $tt) | round) / 10 | tostring) + "%" else "n/a" end)\t\(.key // "?")\t\(.title)")
        ' "${WORKDIR}/sa_high.json" 2> /dev/null) || parsed=""

    if [[ -z "$parsed" ]]; then
        log_warn "HIGH findings response could not be parsed - check OCI call shape"
        echo "top HIGH findings: n/a"
        return 0
    fi

    local items no_count no_key
    IFS=$'\t' read -r _ items no_count no_key <<< "$(sed -n '1p' <<< "$parsed")"
    if [[ "${items:-0}" -eq 0 ]]; then
        log_warn "no HIGH finding items found in response - check OCI call shape"
    fi
    if [[ "${no_count:-0}" -gt 0 ]]; then
        log_warn "${no_count} finding item(s) without a targets count - skipped"
    fi
    if [[ "${no_key:-0}" -gt 0 ]]; then
        log_warn "${no_key} finding item(s) without a finding key"
    fi

    echo "top ${TOP_K} HIGH findings by affected targets (targets, share of all targets, key, title):"
    sed '1d' <<< "$parsed" | sed 's/^/  /'
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Run all collections and print the report
# Args....: None
# Returns.: 0
# Output..: Aggregates to stdout
# ------------------------------------------------------------------------------
do_work() {
    SUB_ARGS=(--compartment-id "$COMPARTMENT" --compartment-id-in-subtree true --access-level ACCESSIBLE --all)

    echo "snapshot: $(date -u +%Y-%m-%dT%H:%MZ)"
    report_targets

    # LATEST assessments (one per target)
    if oci_exec_ro data-safe user-assessment list "${SUB_ARGS[@]}" --type LATEST --lifecycle-state SUCCEEDED \
        > "${WORKDIR}/ua.json"; then
        snapshot_range "user assessments (LATEST, succeeded)" "${WORKDIR}/ua.json"
    else
        log_warn "user-assessment list failed - user figures not available"
        echo '{"data":[]}' > "${WORKDIR}/ua.json"
    fi
    if oci_exec_ro data-safe security-assessment list "${SUB_ARGS[@]}" --type LATEST --lifecycle-state SUCCEEDED \
        > "${WORKDIR}/sa.json"; then
        snapshot_range "security assessments (LATEST, succeeded)" "${WORKDIR}/sa.json"
    else
        log_warn "security-assessment list failed - snapshot range for security assessments missing"
    fi

    collect_users
    if [[ "$UA_FAILED" -gt 0 ]]; then
        log_warn "list-users failed for ${UA_FAILED} of ${UA_TOTAL} assessments - user figures cover the rest only"
        echo "user assessments without data: ${UA_FAILED} of ${UA_TOTAL}"
    fi
    report_users
    report_findings
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: None
# Returns.: 0 on success
# Output..: Aggregates to stdout
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    validate_inputs
    do_work
    log_info "Completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_fleet_assessment_stats.sh --------------------------------------
