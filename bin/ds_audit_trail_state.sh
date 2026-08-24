#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_audit_trail_state.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.08.24
# Version....: v1.1.1
# Purpose....: Report Data Safe audit trail states directly from the OCI
#              audit-trail list API. Trail-centric view; no target join.
#              Ideal for monitoring during or after a reconcile run.
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '1.1.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${SELECT_ALL:=false}"
: "${STATE_FILTER:=}"        # --state: comma-separated effective states to show
: "${DISPLAY_FILTER:=}"     # --filter: regex filter on display-name
: "${OUTPUT_FORMAT:=table}"  # table|csv|json
: "${SUMMARY_MODE:=both}"    # both|only|none
: "${TRAILS_JSON:=}"         # --trails-json: read from snapshot instead of OCI
: "${SAVE_TRAILS_JSON:=}"    # --save-trails-json: write raw OCI response to file
: "${REPORT_FILE:=}"         # --report-file: tee output to file
# shellcheck disable=SC2034
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime globals
TRAILS_ITEMS_JSON="[]"

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
    Report Data Safe audit trail states directly from the OCI audit-trail
    list API. Does not join target data — one bulk call per compartment.
    Useful for monitoring collection progress after ds_audit_reconcile.sh.

    Effective state combines lifecycle-state and status:
      COLLECTING / IDLE / STARTING   collection is running or on the way
      NOT_STARTED                    trail exists but was never started
      STOPPED                        collection was stopped intentionally
      NEEDS_ATTENTION                lifecycle NEEDS_ATTENTION/FAILED, or
                                     status STOPPED_NEEDS_ATTN/STOPPED_FAILED
      UNKNOWN                        status and lifecycle both absent

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
    -c, --compartment COMP      Compartment OCID or name, subtree included
    -A, --all                   All targets from DS_ROOT_COMP

  Report:
    -f, --format FMT            Output format: table|csv|json (default: ${OUTPUT_FORMAT})
    -r, --filter REGEX          Filter trail display-name by regex
        --state STATES          Only show these effective states, comma-separated
                                (e.g. NOT_STARTED,NEEDS_ATTENTION)
        --summary-only          Print the status summary only
        --no-summary            Print the detail rows only
        --report-file FILE      Tee report output to FILE

  Snapshots:
        --trails-json FILE      Read audit-trail data from a JSON snapshot
        --save-trails-json FILE Save raw audit-trail OCI response to FILE

Examples:
  ${SCRIPT_NAME} -c ocid1.compartment.oc1..prod
  ${SCRIPT_NAME} -c ocid1.compartment.oc1..prod --state NOT_STARTED,NEEDS_ATTENTION
  ${SCRIPT_NAME} -c ocid1.compartment.oc1..prod --format json --no-summary
  ${SCRIPT_NAME} -A --summary-only
  ${SCRIPT_NAME} --trails-json snapshot.json --state NEEDS_ATTENTION
  ${SCRIPT_NAME} -c ocid1.compartment.oc1..prod -r 'exa117' --state NEEDS_ATTENTION
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
    parse_common_opts "$@"

    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            -r | --filter)
                need_val "$1" "${2:-}"
                DISPLAY_FILTER="$2"
                shift 2
                ;;
            -f | --format)
                need_val "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --state)
                need_val "$1" "${2:-}"
                STATE_FILTER="$2"
                shift 2
                ;;
            --summary-only)
                SUMMARY_MODE=only
                shift
                ;;
            --no-summary)
                SUMMARY_MODE=none
                shift
                ;;
            --report-file)
                need_val "$1" "${2:-}"
                REPORT_FILE="$2"
                shift 2
                ;;
            --trails-json)
                need_val "$1" "${2:-}"
                TRAILS_JSON="$2"
                shift 2
                ;;
            --save-trails-json)
                need_val "$1" "${2:-}"
                SAVE_TRAILS_JSON="$2"
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

    [[ ${#remaining[@]} -gt 0 ]] \
        && log_warn "Ignoring unexpected positional argument(s): ${remaining[*]}"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate arguments and resolve compartment scope
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    case "${OUTPUT_FORMAT,,}" in
        table | csv | json) OUTPUT_FORMAT="${OUTPUT_FORMAT,,}" ;;
        *) die "Invalid --format: ${OUTPUT_FORMAT}. Use table, csv or json" ;;
    esac

    if [[ -n "$TRAILS_JSON" ]]; then
        [[ -r "$TRAILS_JSON" ]] || die "Trails snapshot not found or not readable: ${TRAILS_JSON}"
        return 0
    fi

    require_oci_cli

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "") \
        || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment"

    if [[ -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") \
            || die "Specify -c/--compartment, -A/--all, set DS_ROOT_COMP, or use --trails-json"
        log_info "No compartment specified, using DS_ROOT_COMP: ${COMPARTMENT}"
    fi
}

# ------------------------------------------------------------------------------
# Function: collect_trails
# Purpose.: Fetch audit trail items from OCI or a snapshot file
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Populates TRAILS_ITEMS_JSON
# ------------------------------------------------------------------------------
collect_trails() {
    if [[ -n "$TRAILS_JSON" ]]; then
        log_info "Reading audit trails from snapshot: ${TRAILS_JSON}"
        TRAILS_ITEMS_JSON=$(ds_trail_items "$(cat "$TRAILS_JSON")")
        return 0
    fi

    log_info "Collecting audit trails..."
    TRAILS_ITEMS_JSON=$(ds_collect_trail_items ds_list_audit_trails "$COMPARTMENT")

    [[ -n "$SAVE_TRAILS_JSON" ]] \
        && jq '{data:{items:.}}' <<< "$TRAILS_ITEMS_JSON" > "$SAVE_TRAILS_JSON" \
        && log_info "Audit trail snapshot saved to: ${SAVE_TRAILS_JSON}"

    log_info "Audit trails collected: $(jq 'length' <<< "$TRAILS_ITEMS_JSON")"
}

# ------------------------------------------------------------------------------
# Function: build_rows
# Purpose.: Flatten trails to report rows and apply --status filter
# Args....: None
# Returns.: 0 on success
# Output..: JSON array on stdout
# ------------------------------------------------------------------------------
build_rows() {
    local state_arg="${STATE_FILTER:-}"
    local display_arg="${DISPLAY_FILTER:-}"

    jq -c --arg state_filter "$state_arg" --arg display_filter "$display_arg" '
        def effective_state(ls; st):
            if (ls == "NEEDS_ATTENTION" or ls == "FAILED") then "NEEDS_ATTENTION"
            elif (ls == "DELETING" or ls == "DELETED") then ls
            elif (st == "STOPPED_NEEDS_ATTN" or st == "STOPPED_FAILED") then "NEEDS_ATTENTION"
            elif (st != null and st != "") then st
            elif (ls != null and ls != "") then ls
            else "UNKNOWN"
            end;
        [
            .[] |
            {
                "display-name":          .["display-name"],
                "status":                .["status"],
                "lifecycle-state":       .["lifecycle-state"],
                "effective-state":       effective_state(.["lifecycle-state"]; .["status"]),
                "lifecycle-details":     .["lifecycle-details"],
                "trail-location":        .["trail-location"],
                "target-id":             .["target-id"],
                "id":                    .["id"],
                "is-auto-purge-enabled": .["is-auto-purge-enabled"]
            }
        ] |
        if ($display_filter != "") then
            map(select(.["display-name"] | test($display_filter; "i")))
        else .
        end |
        if ($state_filter != "") then
            ($state_filter | split(",") | map(ascii_upcase)) as $states |
            map(select(.["effective-state"] | IN($states[])))
        else .
        end |
        sort_by(.["effective-state"], .["display-name"])
    ' <<< "$TRAILS_ITEMS_JSON"
}

# ------------------------------------------------------------------------------
# Function: summary_json
# Purpose.: Aggregate rows into a status-count summary
# Args....: $1 - rows JSON array
# Returns.: 0 on success
# Output..: JSON array on stdout
# ------------------------------------------------------------------------------
summary_json() {
    jq -c '
        group_by(.["effective-state"]) |
        map({
            state:  .[0]["effective-state"],
            count:  length
        }) |
        . + [{state: "TOTAL", count: ([.[].count] | add)}]
    ' <<< "$1"
}

# ------------------------------------------------------------------------------
# Function: render_detail_table
# Purpose.: Render detail rows as a fixed-width table
# Args....: $1 - rows JSON array
# Returns.: 0 on success
# Output..: Table to stdout
# ------------------------------------------------------------------------------
render_detail_table() {
    local rows="$1"
    printf '%-50s %-16s %-16s %-10s %s\n' \
        "DISPLAY-NAME" "EFFECTIVE-STATE" "LIFECYCLE-STATE" "AUTO-PURGE" "DETAILS"
    printf '%-50s %-16s %-16s %-10s %s\n' \
        "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..16})" \
        "$(printf '%0.s-' {1..16})" "$(printf '%0.s-' {1..10})" \
        "$(printf '%0.s-' {1..30})"

    local name eff_state lc_state purge details
    while IFS=$'\t' read -r name eff_state lc_state purge details; do
        [[ -z "$name" ]] && continue
        printf '%-50s %-16s %-16s %-10s %s\n' \
            "$name" "$eff_state" "$lc_state" "$purge" "${details:--}"
    done < <(jq -r '.[] | [
        .["display-name"],
        .["effective-state"],
        .["lifecycle-state"],
        (if .["is-auto-purge-enabled"] == true then "on" else "off" end),
        (.["lifecycle-details"] // "")
    ] | @tsv' <<< "$rows")
}

# ------------------------------------------------------------------------------
# Function: render_summary_table
# Purpose.: Render the status summary as a fixed-width table
# Args....: $1 - summary JSON array
# Returns.: 0 on success
# Output..: Table to stdout
# ------------------------------------------------------------------------------
render_summary_table() {
    local summary="$1"
    printf '%-20s %8s\n' "EFFECTIVE-STATE" "COUNT"
    printf '%-20s %8s\n' "$(printf '%0.s-' {1..20})" "$(printf '%0.s-' {1..8})"

    local state count
    while IFS=$'\t' read -r state count; do
        [[ -z "$state" ]] && continue
        printf '%-20s %8s\n' "$state" "$count"
    done < <(jq -r '.[] | [.state, .count] | @tsv' <<< "$summary")
}

# ------------------------------------------------------------------------------
# Function: render_report
# Purpose.: Render the full report in the requested output format
# Args....: None
# Returns.: 0 on success
# Output..: Report to stdout
# ------------------------------------------------------------------------------
render_report() {
    local rows summary
    rows=$(build_rows)
    summary=$(summary_json "$rows")

    case "$OUTPUT_FORMAT" in
        json)
            jq --argjson summary "$summary" \
                --arg generated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                --arg compartment "${COMPARTMENT:-}" \
                '{generated: $generated, compartment: $compartment, trails: length, rows: ., summary: $summary}' \
                <<< "$rows"
            ;;
        csv)
            if [[ "$SUMMARY_MODE" != "only" ]]; then
                printf 'display-name,effective-state,status,lifecycle-state,lifecycle-details,auto-purge,target-id,id\n'
                jq -r '.[] | [
                    .["display-name"],
                    .["effective-state"],
                    .["status"],
                    .["lifecycle-state"],
                    (.["lifecycle-details"] // ""),
                    .["is-auto-purge-enabled"],
                    .["target-id"],
                    .["id"]
                ] | @csv' <<< "$rows"
            fi
            if [[ "$SUMMARY_MODE" != "none" ]]; then
                [[ "$SUMMARY_MODE" == "both" ]] && printf '\n'
                printf 'effective-state,count\n'
                jq -r '.[] | [.state, .count] | @csv' <<< "$summary"
            fi
            ;;
        *)
            printf 'Data Safe Audit Trail State\n'
            printf 'Generated:   %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            [[ -n "$COMPARTMENT" ]] && printf 'Compartment: %s\n' "$COMPARTMENT"
            [[ -n "$STATE_FILTER" ]] && printf 'State:       %s\n' "$STATE_FILTER"
            [[ -n "$DISPLAY_FILTER" ]] && printf 'Filter:      %s\n' "$DISPLAY_FILTER"
            printf 'Trails:      %s\n\n' "$(jq 'length' <<< "$rows")"

            if [[ "$SUMMARY_MODE" != "only" ]]; then
                render_detail_table "$rows"
                printf '\n'
            fi
            if [[ "$SUMMARY_MODE" != "none" ]]; then
                printf 'Summary\n'
                render_summary_table "$summary"
            fi
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Report to stdout and optionally to --report-file
# ------------------------------------------------------------------------------
main() {
    setup_error_handling
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    parse_args "$@"
    validate_inputs
    collect_trails

    if [[ -n "$REPORT_FILE" ]]; then
        render_report | tee "$REPORT_FILE"
        log_info "Report written to: ${REPORT_FILE}"
    else
        render_report
    fi
}

main "$@"
