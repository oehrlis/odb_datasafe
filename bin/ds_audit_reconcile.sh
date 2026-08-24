#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_audit_reconcile.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.08.23
# Version....: v1.1.0
# Purpose....: Reconcile the desired and actual Data Safe audit state: tag
#              targets, discover missing audit trails, start trails that were
#              never started. Idempotent, dry-run by default.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
readonly BIN_DIR="${SCRIPT_DIR}"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '1.1.0')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${TAG_FILTER:=}"
: "${LIFECYCLE:=ACTIVE}"
: "${TAG_NAMESPACE:=DBSec}"
: "${STAGE_TAG:=ContainerStage}"
: "${ENV_REGEX:=${DS_ENV_COMP_REGEX:-}}"
: "${START_TIME:=now}"  # never backdated - collection starts when it is enabled
: "${AUTO_PURGE:=true}" # always on, the on-database audit trail must not grow
: "${APPLY:=false}"     # --apply; without it the run is a dry-run
: "${SKIP_TAGGING:=false}"
: "${SKIP_TRAILS:=false}"
: "${SKIP_DISCOVER:=false}"
: "${LIMIT:=0}" # 0 = unlimited
: "${REPORT_FILE:=}"
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${TRAILS_JSON:=}"
: "${PROFILES_JSON:=}"
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime globals
TARGETS_PAYLOAD_JSON=""
TRAILS_ITEMS_JSON="[]"
PROFILES_ITEMS_JSON="[]"
ROWS_JSON="[]"
BUDGET_LEFT=0
BUDGET_USED=0
GRANTED=0
TAGGED_OK=0
TAGGED_FAIL=0
DISCOVER_OK=0
DISCOVER_FAIL=0
STARTED_OK=0
STARTED_FAIL=0
DEFERRED_TAG=0
DEFERRED_DISCOVER=0
DEFERRED_START=0

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

setup_error_handling
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
    Compare the desired and the actual Data Safe audit state in a compartment
    subtree and close the gap. The run is idempotent and can be repeated any
    number of times; it is a dry-run unless --apply is given.

    Steps, in order:
      1. Collect targets, audit trails and audit profiles (three bulk calls)
      2. Targets without ${TAG_NAMESPACE}.${STAGE_TAG}: report and tag
      3. Targets without an audit trail object: report and rediscover
      4. Trails in state NOT_STARTED: report and start
      5. Trails in state NEEDS_ATTENTION: report only, never touched
      6. Print the reconcile report

    The work is delegated to the existing scripts, no logic is duplicated:
      ds_target_update_tags.sh    tagging (step 2)
      ds_target_audit_trail.sh    trail start (step 4)
      audit-profile discover-audit-trails via ds_lib (step 3)

    Fixed policy, not configurable away:
      - Collection always starts at --start-time (default: now). Audit data
        from before that point is never backfilled.
      - Auto-purge is always enabled on a started trail so the audit trail in
        the database does not grow without bound.
      - NEEDS_ATTENTION is reported, never auto-repaired.

Options:
  Common:
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
    -q, --quiet                 Quiet mode
        --log-file FILE         Log to file
        --no-color              Disable colored output

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file

  Scope:
        --compartment-id OCID   Target compartment, subtree included
    -c, --compartment COMP      Alias for --compartment-id, also accepts a name
    -A, --all                   All targets from DS_ROOT_COMP
        --target-filter REGEX   Only targets whose name matches the regex
    -r, --filter REGEX          Alias for --target-filter
        --tag-filter EXPR       Filter by OCI tag; repeatable (AND)
    -L, --lifecycle STATES      Target lifecycle filter (default: ${LIFECYCLE})

  Execution:
    -n, --dry-run               Report only, change nothing (default)
        --apply                 Actually perform the changes
        --limit N               Change at most N things in this run. Every write
                                counts as one: a tag update, a trail discovery,
                                a trail start. Shared budget across all steps,
                                consumed in step order. 0 means unlimited.
        --skip-tagging          Skip the tagging step
        --skip-trails           Skip both trail steps (discover and start)
        --skip-discover         Skip the discovery step only

  Configuration:
        --namespace NS          Tag namespace (default: ${TAG_NAMESPACE})
        --stage-tag TAG         Container stage tag key (default: ${STAGE_TAG})
        --env-regex PATTERN     Regex deriving the environment from the
                                compartment name, capture group 1 is the value.
                                Falls back to DS_ENV_COMP_REGEX.
        --start-time TIME       Collection start (RFC3339 or 'now', default: now)
        --auto-purge true|false Auto-purge on start (default: ${AUTO_PURGE})
        --report-file FILE      Write the report to FILE in addition to stdout

  Snapshots (offline rehearsal):
        --input-json FILE       Read targets from a local JSON snapshot
        --save-json FILE        Save the target payload
        --trails-json FILE      Read audit trails from a local JSON snapshot
        --profiles-json FILE    Read audit profiles from a local JSON snapshot

Examples:
  # See what a run would change - the default, nothing is written
  ${SCRIPT_NAME} --compartment-id ocid1.compartment.oc1..prod

  # First wave: at most 50 changes, then check the volume
  ${SCRIPT_NAME} --compartment-id ocid1.compartment.oc1..prod --apply --limit 50
  ${BIN_DIR##*/}/ds_trail_report.sh --compartment-id ocid1.compartment.oc1..prod --summary-only

  # Tagging only, no trail work
  ${SCRIPT_NAME} -A --apply --skip-trails --env-regex '^cmp-.*-([^-]+)-projects\$'

  # Trails only, restricted to one database family, report to file
  ${SCRIPT_NAME} -A --apply --skip-tagging --target-filter '^PRODDB0' \\
      --limit 50 --report-file wave-04.txt

Exit Codes:
  0 = Success, or dry-run completed
  1 = One or more changes failed

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables
# ------------------------------------------------------------------------------
parse_args() {
    local has_explicit_log_flag="false"
    local arg
    for arg in "$@"; do
        case "$arg" in
            -v | --verbose | -d | --debug | -q | --quiet)
                has_explicit_log_flag="true"
                break
                ;;
        esac
    done

    parse_common_opts "$@"

    if [[ "$has_explicit_log_flag" == "false" ]]; then
        # shellcheck disable=SC2034
        LOG_LEVEL=INFO
    fi

    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --compartment-id | -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            --target-filter | -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
                shift 2
                ;;
            --tag-filter)
                need_val "$1" "${2:-}"
                TAG_FILTER="${TAG_FILTER:+${TAG_FILTER}$'\n'}$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE="$2"
                shift 2
                ;;
            --apply)
                APPLY=true
                shift
                ;;
            --limit)
                need_val "$1" "${2:-}"
                LIMIT="$2"
                shift 2
                ;;
            --skip-tagging)
                SKIP_TAGGING=true
                shift
                ;;
            --skip-trails)
                SKIP_TRAILS=true
                shift
                ;;
            --skip-discover)
                SKIP_DISCOVER=true
                shift
                ;;
            --namespace)
                need_val "$1" "${2:-}"
                TAG_NAMESPACE="$2"
                shift 2
                ;;
            --stage-tag)
                need_val "$1" "${2:-}"
                STAGE_TAG="$2"
                shift 2
                ;;
            --env-regex)
                need_val "$1" "${2:-}"
                ENV_REGEX="$2"
                shift 2
                ;;
            --start-time)
                need_val "$1" "${2:-}"
                START_TIME="$2"
                shift 2
                ;;
            --auto-purge)
                need_val "$1" "${2:-}"
                AUTO_PURGE="$2"
                shift 2
                ;;
            --report-file)
                need_val "$1" "${2:-}"
                REPORT_FILE="$2"
                shift 2
                ;;
            --input-json)
                need_val "$1" "${2:-}"
                INPUT_JSON="$2"
                shift 2
                ;;
            --save-json)
                need_val "$1" "${2:-}"
                SAVE_JSON="$2"
                shift 2
                ;;
            --trails-json)
                need_val "$1" "${2:-}"
                TRAILS_JSON="$2"
                shift 2
                ;;
            --profiles-json)
                need_val "$1" "${2:-}"
                PROFILES_JSON="$2"
                shift 2
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                export OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                export OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    [[ ${#remaining[@]} -gt 0 ]] && die "Unexpected positional argument: ${remaining[0]} (use --target-filter)"

    return 0
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate arguments and resolve the reconcile scope
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    [[ "$LIMIT" =~ ^[0-9]+$ ]] || die "Invalid --limit: $LIMIT. Use a non-negative integer"

    case "${AUTO_PURGE,,}" in
        true | false) AUTO_PURGE="${AUTO_PURGE,,}" ;;
        *) die "Invalid --auto-purge value: $AUTO_PURGE. Use: true or false" ;;
    esac

    # --dry-run from parse_common_opts wins over --apply; both together is a
    # contradiction the operator should resolve, not the script.
    if [[ "${DRY_RUN}" == "true" && "$APPLY" == "true" ]]; then
        die "--dry-run and --apply are mutually exclusive"
    fi
    [[ "$APPLY" == "true" ]] || export DRY_RUN=true

    local snapshot_only="false"
    [[ -n "$INPUT_JSON" && -n "$TRAILS_JSON" ]] && snapshot_only="true"

    local f
    for f in "$INPUT_JSON" "$TRAILS_JSON" "$PROFILES_JSON"; do
        [[ -z "$f" ]] && continue
        [[ -r "$f" ]] || die "JSON snapshot not found or not readable: $f"
    done

    [[ "$snapshot_only" == "true" ]] || require_oci_cli

    if [[ -n "$INPUT_JSON" && "$APPLY" == "true" ]]; then
        die "--apply with --input-json is not allowed: a stale target snapshot must not drive writes"
    fi

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "") \
        || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with --compartment-id"

    if [[ -z "$COMPARTMENT" && -z "$INPUT_JSON" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") \
            || die "Specify --compartment-id, -A/--all, set DS_ROOT_COMP, or use --input-json"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    ds_validate_target_filter_regex "$TARGET_FILTER" \
        || die "Invalid --target-filter regex: $TARGET_FILTER"

    BUDGET_LEFT="$LIMIT"

    log_info "Mode: $([[ "$APPLY" == "true" ]] && echo APPLY || echo DRY-RUN)"
    log_info "Change budget: $([[ "$LIMIT" -eq 0 ]] && echo unlimited || echo "$LIMIT")"

    return 0
}

# ------------------------------------------------------------------------------
# Function: collect_state
# Purpose.: Fetch targets, audit trails and audit profiles for the scope
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Populates TARGETS_PAYLOAD_JSON, TRAILS_ITEMS_JSON, PROFILES_ITEMS_JSON
# Notes...: Three bulk calls regardless of the number of targets.
# ------------------------------------------------------------------------------
collect_state() {
    log_info "Collecting targets..."
    TARGETS_PAYLOAD_JSON=$(ds_collect_targets_source \
        "$COMPARTMENT" "" "$LIFECYCLE" "$TARGET_FILTER" \
        "$INPUT_JSON" "$SAVE_JSON" "$TAG_FILTER") || die "Failed to collect targets"

    local -a scopes=()
    if [[ -n "$COMPARTMENT" ]]; then
        scopes+=("$COMPARTMENT")
    else
        local comp
        while IFS= read -r comp; do
            [[ -n "$comp" ]] && scopes+=("$comp")
        done < <(jq -r '[.data[]."compartment-id" // empty] | unique | .[]' <<< "$TARGETS_PAYLOAD_JSON")
    fi

    if [[ -n "$TRAILS_JSON" ]]; then
        TRAILS_ITEMS_JSON=$(ds_trail_items "$(cat "$TRAILS_JSON")")
    else
        log_info "Collecting audit trails..."
        TRAILS_ITEMS_JSON=$(ds_collect_trail_items ds_list_audit_trails "${scopes[@]+"${scopes[@]}"}")
    fi

    if [[ -n "$PROFILES_JSON" ]]; then
        PROFILES_ITEMS_JSON=$(ds_trail_items "$(cat "$PROFILES_JSON")")
    else
        log_info "Collecting audit profiles..."
        PROFILES_ITEMS_JSON=$(ds_collect_trail_items ds_list_audit_profiles "${scopes[@]+"${scopes[@]}"}")
    fi

    ROWS_JSON=$(ds_build_trail_rows \
        "$TARGETS_PAYLOAD_JSON" "$TRAILS_ITEMS_JSON" "$PROFILES_ITEMS_JSON" \
        "$TAG_NAMESPACE" "") || die "Failed to build reconcile rows"

    log_info "Targets in scope: $(jq 'length' <<< "$ROWS_JSON")"
    return 0
}

# ------------------------------------------------------------------------------
# Function: select_rows
# Purpose.: Select the rows belonging to one reconcile bucket
# Args....: $1 - bucket name: untagged|no-trail|no-profile|not-started|
#                             attention|other|compliant
# Returns.: 0 on success
# Output..: JSON array on stdout
# Notes...: "compliant" means tagged and collecting - nothing left to do.
# ------------------------------------------------------------------------------
select_rows() {
    local bucket="$1"

    jq -c --arg bucket "$bucket" '
        def is_untagged:   (.stage == "-" or .stage == "" or (.stage | ascii_downcase) == "undef");
        def is_collecting: . as $r
                           | ["COLLECTING","IDLE","RECOVERING","STARTING","RESUMING","RETRYING"]
                           | index($r["trail-state"]) != null;
        map(select(
            if $bucket == "untagged"    then is_untagged
            elif $bucket == "no-trail"  then (.["trail-state"] == "NO_TRAIL" and .["audit-profile-id"] != null)
            elif $bucket == "no-profile" then (.["trail-state"] == "NO_TRAIL" and .["audit-profile-id"] == null)
            elif $bucket == "not-started" then (.["trail-state"] == "NOT_STARTED")
            elif $bucket == "attention" then (.["trail-state"] == "NEEDS_ATTENTION")
            elif $bucket == "other"     then ((is_collecting | not)
                                              and .["trail-state"] != "NO_TRAIL"
                                              and .["trail-state"] != "NOT_STARTED"
                                              and .["trail-state"] != "NEEDS_ATTENTION")
            elif $bucket == "compliant" then (is_collecting and (is_untagged | not))
            else false
            end
        ))
    ' <<< "$ROWS_JSON"
}

# ------------------------------------------------------------------------------
# Function: take_budget
# Purpose.: Reserve up to N units from the shared change budget
# Args....: $1 - requested number of changes
# Returns.: 0 always
# Output..: Sets the global GRANTED
# Notes...: Must not be called in a command substitution - the budget is shared
#           across all steps and a subshell would discard the decrement.
# ------------------------------------------------------------------------------
take_budget() {
    local requested="$1"

    if [[ "$LIMIT" -eq 0 ]]; then
        GRANTED="$requested"
        return 0
    fi

    GRANTED="$requested"
    [[ $GRANTED -gt $BUDGET_LEFT ]] && GRANTED="$BUDGET_LEFT"
    BUDGET_LEFT=$((BUDGET_LEFT - GRANTED))

    return 0
}

# ------------------------------------------------------------------------------
# Function: run_child
# Purpose.: Invoke a sibling script with the common OCI and logging options
# Args....: $1 - script file name in bin/
#           $@ - script specific arguments
# Returns.: exit code of the child script
# Output..: Child output is logged at debug level, errors are surfaced
# ------------------------------------------------------------------------------
run_child() {
    local script="$1"
    shift

    local -a cmd=("${BIN_DIR}/${script}" "$@")
    [[ -n "${OCI_CLI_PROFILE:-}" ]] && cmd+=(--oci-profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION:-}" ]] && cmd+=(--oci-region "${OCI_CLI_REGION}")
    [[ -n "${OCI_CLI_CONFIG_FILE:-}" ]] && cmd+=(--oci-config "${OCI_CLI_CONFIG_FILE}")

    log_debug "Running: ${cmd[*]}"

    local output rc=0
    output=$("${cmd[@]}" 2>&1) || rc=$?

    if [[ $rc -ne 0 ]]; then
        log_error "${script} exited with ${rc}"
        printf '%s\n' "$output" >&2
    else
        log_debug "$output"
    fi

    return "$rc"
}

# ------------------------------------------------------------------------------
# Function: reconcile_tagging
# Purpose.: Step 2 - tag targets that carry no container stage
# Args....: None
# Returns.: 0 on success, 1 when the tagging child failed
# Output..: Log messages, updates the counters
# Notes...: Delegates to ds_target_update_tags.sh which derives the value as
#           {cdbroot|pdb}-{env} from the compartment name and the target name.
# ------------------------------------------------------------------------------
reconcile_tagging() {
    local rows count
    rows=$(select_rows untagged)
    count=$(jq 'length' <<< "$rows")

    log_info "Step 2 - targets without ${TAG_NAMESPACE}.${STAGE_TAG}: ${count}"
    [[ "$count" -eq 0 ]] && return 0

    local granted
    take_budget "$count"
    granted="$GRANTED"
    DEFERRED_TAG=$((count - granted))
    BUDGET_USED=$((BUDGET_USED + granted))

    if [[ "$granted" -eq 0 ]]; then
        log_warn "Change budget exhausted, deferring ${count} tag update(s)"
        return 0
    fi

    local target_list
    target_list=$(jq -r --argjson n "$granted" '.[0:$n] | map(.["target-id"]) | join(",")' <<< "$rows")

    local -a args=(-T "$target_list" --namespace "$TAG_NAMESPACE" --stage-tag "$STAGE_TAG")
    [[ -n "$ENV_REGEX" ]] && args+=(--env-regex "$ENV_REGEX")

    if [[ "$APPLY" != "true" ]]; then
        log_info "[DRY-RUN] Would tag ${granted} target(s) via ds_target_update_tags.sh"
        log_info "[DRY-RUN]   ds_target_update_tags.sh ${args[*]} --apply"
        return 0
    fi

    if run_child ds_target_update_tags.sh "${args[@]}" --apply; then
        TAGGED_OK="$granted"
        log_info "Tagged ${granted} target(s)"
    else
        TAGGED_FAIL="$granted"
        log_error "Tagging failed for up to ${granted} target(s)"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: reconcile_discover
# Purpose.: Step 3 - trigger trail discovery for targets without a trail object
# Args....: None
# Returns.: 0 on success, 1 when at least one discovery failed
# Output..: Log messages, updates the counters
# Notes...: There is no create operation for an audit trail. Discovery is
#           asynchronous - the trail appears later and is started by a
#           subsequent reconcile run.
# ------------------------------------------------------------------------------
reconcile_discover() {
    local rows count
    rows=$(select_rows no-trail)
    count=$(jq 'length' <<< "$rows")

    log_info "Step 3 - targets without an audit trail object: ${count}"
    [[ "$count" -eq 0 ]] && return 0

    local granted
    take_budget "$count"
    granted="$GRANTED"
    DEFERRED_DISCOVER=$((count - granted))
    BUDGET_USED=$((BUDGET_USED + granted))

    if [[ "$granted" -eq 0 ]]; then
        log_warn "Change budget exhausted, deferring ${count} trail discovery request(s)"
        return 0
    fi

    local rc=0 name profile_id
    while IFS=$'\t' read -r name profile_id; do
        [[ -z "$profile_id" ]] && continue
        if [[ "$APPLY" != "true" ]]; then
            log_info "[DRY-RUN] Would discover audit trails for: ${name} (${profile_id})"
            continue
        fi
        if ds_discover_audit_trails "$profile_id" "$name"; then
            DISCOVER_OK=$((DISCOVER_OK + 1))
        else
            DISCOVER_FAIL=$((DISCOVER_FAIL + 1))
            rc=1
        fi
    done < <(jq -r --argjson n "$granted" \
        '.[0:$n][] | [.target, .["audit-profile-id"]] | @tsv' <<< "$rows")

    return "$rc"
}

# ------------------------------------------------------------------------------
# Function: reconcile_start
# Purpose.: Step 4 - start audit trails that were never started
# Args....: None
# Returns.: 0 on success, 1 when the start child failed
# Output..: Log messages, updates the counters
# Notes...: Delegates to ds_target_audit_trail.sh with the fixed policy: start
#           time is now (no historic data) and auto-purge is on.
# ------------------------------------------------------------------------------
reconcile_start() {
    local rows count
    rows=$(select_rows not-started)
    count=$(jq 'length' <<< "$rows")

    log_info "Step 4 - trails in state NOT_STARTED: ${count}"
    [[ "$count" -eq 0 ]] && return 0

    local granted
    take_budget "$count"
    granted="$GRANTED"
    DEFERRED_START=$((count - granted))
    BUDGET_USED=$((BUDGET_USED + granted))

    if [[ "$granted" -eq 0 ]]; then
        log_warn "Change budget exhausted, deferring ${count} trail start(s)"
        return 0
    fi

    local target_list
    target_list=$(jq -r --argjson n "$granted" '.[0:$n] | map(.["target-id"]) | join(",")' <<< "$rows")

    local -a args=(-T "$target_list" --start-time "$START_TIME" --auto-purge "$AUTO_PURGE")

    if [[ "$APPLY" != "true" ]]; then
        log_info "[DRY-RUN] Would start ${granted} audit trail(s) via ds_target_audit_trail.sh"
        log_info "[DRY-RUN]   ds_target_audit_trail.sh ${args[*]}"
        return 0
    fi

    if run_child ds_target_audit_trail.sh "${args[@]}"; then
        STARTED_OK="$granted"
        log_info "Started ${granted} audit trail(s)"
    else
        STARTED_FAIL="$granted"
        log_error "Trail start failed for up to ${granted} target(s)"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: print_rows
# Purpose.: Print a labelled list of report rows, truncated for readability
# Args....: $1 - rows JSON array
#           $2 - maximum number of lines (0 = all)
# Returns.: 0 on success
# Output..: Indented target list to stdout
# ------------------------------------------------------------------------------
print_rows() {
    local rows="$1"
    local max="${2:-0}"

    local total
    total=$(jq 'length' <<< "$rows")
    [[ "$total" -eq 0 ]] && return 0

    local shown="$total"
    [[ "$max" -gt 0 && "$shown" -gt "$max" ]] && shown="$max"

    jq -r --argjson n "$shown" \
        '.[0:$n][] | "    \(.target)  [\(.environment)/\(.type)]  \(.["trail-state"])"' <<< "$rows"

    [[ "$shown" -lt "$total" ]] && printf '    ... and %s more\n' "$((total - shown))"
    return 0
}

# ------------------------------------------------------------------------------
# Function: render_report
# Purpose.: Print the reconcile report
# Args....: None
# Returns.: 0 on success
# Output..: Report to stdout
# ------------------------------------------------------------------------------
render_report() {
    local untagged no_trail no_profile not_started attention other compliant
    untagged=$(select_rows untagged)
    no_trail=$(select_rows no-trail)
    no_profile=$(select_rows no-profile)
    not_started=$(select_rows not-started)
    attention=$(select_rows attention)
    other=$(select_rows other)
    compliant=$(select_rows compliant)

    local n_attention n_no_profile
    n_attention=$(jq 'length' <<< "$attention")
    n_no_profile=$(jq 'length' <<< "$no_profile")

    printf 'Data Safe Audit Reconcile Report\n'
    printf 'Generated: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    [[ -n "$COMPARTMENT" ]] && printf 'Compartment: %s\n' "$COMPARTMENT"
    printf 'Mode: %s\n' "$([[ "$APPLY" == "true" ]] && echo "APPLY" || echo "DRY-RUN (no changes made)")"
    printf 'Limit: %s\n' "$([[ "$LIMIT" -eq 0 ]] && echo "unlimited" || echo "$LIMIT change(s) per run")"
    printf 'Start time: %s\n' "$START_TIME"
    printf 'Auto-purge: %s\n' "$AUTO_PURGE"
    printf 'Targets in scope: %s\n' "$(jq 'length' <<< "$ROWS_JSON")"

    printf '\nAlready correct\n'
    printf '  Tagged and collecting: %s\n' "$(jq 'length' <<< "$compliant")"

    printf '\nStep 2 - Tagging%s\n' "$([[ "$SKIP_TAGGING" == "true" ]] && echo " (skipped)")"
    printf '  Missing %s.%s: %s\n' "$TAG_NAMESPACE" "$STAGE_TAG" "$(jq 'length' <<< "$untagged")"
    print_rows "$untagged" 20
    printf '  Tagged in this run: %s\n' "$TAGGED_OK"
    printf '  Failed: %s\n' "$TAGGED_FAIL"
    printf '  Deferred by --limit: %s\n' "$DEFERRED_TAG"

    printf '\nStep 3 - Trail discovery%s\n' \
        "$([[ "$SKIP_TRAILS" == "true" || "$SKIP_DISCOVER" == "true" ]] && echo " (skipped)")"
    printf '  Targets without a trail object: %s\n' "$(jq 'length' <<< "$no_trail")"
    print_rows "$no_trail" 20
    printf '  Discovery requested: %s\n' "$DISCOVER_OK"
    printf '  Failed: %s\n' "$DISCOVER_FAIL"
    printf '  Deferred by --limit: %s\n' "$DEFERRED_DISCOVER"

    printf '\nStep 4 - Trail start%s\n' "$([[ "$SKIP_TRAILS" == "true" ]] && echo " (skipped)")"
    printf '  Trails NOT_STARTED: %s\n' "$(jq 'length' <<< "$not_started")"
    print_rows "$not_started" 20
    printf '  Started in this run: %s\n' "$STARTED_OK"
    printf '  Failed: %s\n' "$STARTED_FAIL"
    printf '  Deferred by --limit: %s\n' "$DEFERRED_START"

    printf '\nStep 5 - Needs manual attention\n'
    printf '  Trails NEEDS_ATTENTION: %s\n' "$n_attention"
    print_rows "$attention" 0
    printf '  No trail and no audit profile: %s\n' "$n_no_profile"
    print_rows "$no_profile" 0
    printf '  Other non-collecting states: %s\n' "$(jq 'length' <<< "$other")"
    print_rows "$other" 20

    printf '\nSummary\n'
    printf '  Changes made: %s\n' "$((TAGGED_OK + DISCOVER_OK + STARTED_OK))"
    printf '  Changes failed: %s\n' "$((TAGGED_FAIL + DISCOVER_FAIL + STARTED_FAIL))"
    printf '  Deferred to the next run: %s\n' "$((DEFERRED_TAG + DEFERRED_DISCOVER + DEFERRED_START))"
    printf '  Needs manual attention: %s\n' "$((n_attention + n_no_profile))"

    if [[ "$APPLY" != "true" ]]; then
        printf '\nDry-run: nothing was changed. Re-run with --apply to execute.\n'
    fi

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, 1 when at least one change failed
# Output..: Reconcile report to stdout and optionally to --report-file
# ------------------------------------------------------------------------------
main() {
    setup_error_handling
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    parse_args "$@"
    validate_inputs
    collect_state

    local rc=0

    if [[ "$SKIP_TAGGING" == "true" ]]; then
        log_info "Step 2 - tagging skipped (--skip-tagging)"
    else
        reconcile_tagging || rc=1
    fi

    if [[ "$SKIP_TRAILS" == "true" ]]; then
        log_info "Steps 3 and 4 - trail handling skipped (--skip-trails)"
    else
        if [[ "$SKIP_DISCOVER" == "true" ]]; then
            log_info "Step 3 - trail discovery skipped (--skip-discover)"
        else
            reconcile_discover || rc=1
        fi
        reconcile_start || rc=1
    fi

    if [[ -n "$REPORT_FILE" ]]; then
        render_report | tee "$REPORT_FILE"
        log_info "Report written to: $REPORT_FILE"
    else
        render_report
    fi

    if [[ $rc -ne 0 ]]; then
        die "Reconcile completed with failures" 1
    fi

    log_info "${SCRIPT_NAME} completed successfully"
    return 0
}

main "$@"
