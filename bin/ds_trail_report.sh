#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_trail_report.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.08.23
# Version....: v1.1.0
# Purpose....: Report audit trail state per Data Safe target, grouped by
#              environment. Basis for releasing the next rollout wave.
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '1.1.0')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${SELECT_ALL:=false}"
: "${TARGETS:=}"
: "${TARGET_FILTER:=}"
: "${TAG_FILTER:=}"
: "${LIFECYCLE:=ACTIVE}"
: "${TAG_NAMESPACE:=DBSec}"
: "${OUTPUT_FORMAT:=table}" # table|csv|json
: "${STATE_FILTER:=}"       # --state: only rows in these trail states
: "${SUMMARY_MODE:=both}"   # both|only|none
: "${INPUT_JSON:=}"         # targets snapshot in
: "${SAVE_JSON:=}"          # targets snapshot out
: "${TRAILS_JSON:=}"        # audit-trail snapshot in
: "${PROFILES_JSON:=}"      # audit-profile snapshot in
: "${SAVE_TRAILS_JSON:=}"   # audit-trail snapshot out
: "${SAVE_PROFILES_JSON:=}" # audit-profile snapshot out
: "${REPORT_FILE:=}"        # --report-file: tee report to file

# Runtime globals
TARGETS_PAYLOAD_JSON=""
TRAILS_ITEMS_JSON="[]"
PROFILES_ITEMS_JSON="[]"
ROWS_JSON="[]"

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
    Report the audit trail state of every Data Safe target, grouped by
    environment. Combines target-database, audit-trail and audit-profile data
    in three bulk calls, independent of the number of targets.

    Reported per target: name, environment, container type (root/pdb), trail
    state, auto-purge, and the collected audit volume from the audit profile.

    Trail state combines the trail's lifecycle-state and its status:
      COLLECTING / IDLE       collection is running
      NOT_STARTED             trail exists but was never started
      STOPPED                 collection was stopped
      NEEDS_ATTENTION         lifecycle-state NEEDS_ATTENTION/FAILED, or
                              status STOPPED_NEEDS_ATTN/STOPPED_FAILED
      NO_TRAIL                the target has no audit trail object at all

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

  Target Selection:
    -c, --compartment COMP      Compartment OCID or name, subtree included
    -A, --all                   All targets from DS_ROOT_COMP
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex
        --tag-filter EXPR       Filter by OCI tag; repeatable (AND)
    -L, --lifecycle STATES      Target lifecycle filter (default: ${LIFECYCLE})

  Report:
    -f, --format FMT            Output format: table|csv|json (default: ${OUTPUT_FORMAT})
        --state STATES          Only show these trail states, comma-separated
                                (e.g. NOT_STARTED,NO_TRAIL)
        --summary-only          Print the per-environment summary only
        --no-summary            Print the detail rows only
        --namespace NS          Tag namespace for env/type (default: ${TAG_NAMESPACE})
        --report-file FILE      Write the report to FILE in addition to stdout

  Snapshots (offline / reproducible reports):
        --input-json FILE       Read targets from a local JSON snapshot
        --save-json FILE        Save the target payload
        --trails-json FILE      Read audit trails from a local JSON snapshot
        --profiles-json FILE    Read audit profiles from a local JSON snapshot
        --save-trails-json FILE Save the audit trail payload
        --save-profiles-json FILE
                                Save the audit profile payload

Examples:
  # Full state of the prod compartment as a table
  ${SCRIPT_NAME} -c cmp-zrh-prod-lz-datasafe-01

  # Machine readable, as the gate for the next rollout wave
  ${SCRIPT_NAME} -c cmp-zrh-prod-lz-datasafe-01 -f csv > wave-03-before.csv

  # Only what still needs work
  ${SCRIPT_NAME} -A --state NOT_STARTED,NO_TRAIL,NEEDS_ATTENTION

  # Environment summary only
  ${SCRIPT_NAME} -A --summary-only

  # Snapshot now, report later without touching OCI
  ${SCRIPT_NAME} -A --save-json t.json --save-trails-json tr.json \\
      --save-profiles-json pr.json
  ${SCRIPT_NAME} --input-json t.json --trails-json tr.json --profiles-json pr.json

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
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -r | --filter)
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
            --namespace)
                need_val "$1" "${2:-}"
                TAG_NAMESPACE="$2"
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
            --save-trails-json)
                need_val "$1" "${2:-}"
                SAVE_TRAILS_JSON="$2"
                shift 2
                ;;
            --save-profiles-json)
                need_val "$1" "${2:-}"
                SAVE_PROFILES_JSON="$2"
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

    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate arguments and resolve the reporting scope
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    case "${OUTPUT_FORMAT,,}" in
        table | csv | json) OUTPUT_FORMAT="${OUTPUT_FORMAT,,}" ;;
        *) die "Invalid --format: $OUTPUT_FORMAT. Use table, csv or json" ;;
    esac

    local snapshot_only="false"
    [[ -n "$INPUT_JSON" && -n "$TRAILS_JSON" ]] && snapshot_only="true"

    local f
    for f in "$INPUT_JSON" "$TRAILS_JSON" "$PROFILES_JSON"; do
        [[ -z "$f" ]] && continue
        [[ -r "$f" ]] || die "JSON snapshot not found or not readable: $f"
    done

    if [[ "$snapshot_only" != "true" ]]; then
        require_oci_cli
    fi

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") \
        || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    if [[ -z "$TARGETS" && -z "$COMPARTMENT" && -z "$INPUT_JSON" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") \
            || die "Specify -T/--targets, -c/--compartment, -A/--all, set DS_ROOT_COMP, or use --input-json"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    ds_validate_target_filter_regex "$TARGET_FILTER" \
        || die "Invalid --filter regex: $TARGET_FILTER"
}

# ------------------------------------------------------------------------------
# Function: collect_state
# Purpose.: Fetch targets, audit trails and audit profiles for the scope
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Populates TARGETS_PAYLOAD_JSON, TRAILS_ITEMS_JSON, PROFILES_ITEMS_JSON
# Notes...: Trails and profiles are fetched once per distinct target compartment,
#           not once per target - three bulk calls for 1390 targets.
# ------------------------------------------------------------------------------
collect_state() {
    log_info "Collecting targets..."
    TARGETS_PAYLOAD_JSON=$(ds_collect_targets_source \
        "$COMPARTMENT" "$TARGETS" "$LIFECYCLE" "$TARGET_FILTER" \
        "$INPUT_JSON" "$SAVE_JSON" "$TAG_FILTER") || die "Failed to collect targets"

    local target_count
    target_count=$(jq '.data | length' <<< "$TARGETS_PAYLOAD_JSON")
    log_info "Targets in scope: ${target_count}"

    # Determine the compartments to query for trails and profiles
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
        log_info "Reading audit trails from snapshot: $TRAILS_JSON"
        TRAILS_ITEMS_JSON=$(ds_trail_items "$(cat "$TRAILS_JSON")")
    else
        log_info "Collecting audit trails..."
        TRAILS_ITEMS_JSON=$(ds_collect_trail_items ds_list_audit_trails "${scopes[@]+"${scopes[@]}"}")
    fi

    if [[ -n "$PROFILES_JSON" ]]; then
        log_info "Reading audit profiles from snapshot: $PROFILES_JSON"
        PROFILES_ITEMS_JSON=$(ds_trail_items "$(cat "$PROFILES_JSON")")
    else
        log_info "Collecting audit profiles..."
        PROFILES_ITEMS_JSON=$(ds_collect_trail_items ds_list_audit_profiles "${scopes[@]+"${scopes[@]}"}")
    fi

    # Wrapped via stdin, not --argjson: a 600-target compartment produces
    # arrays past ARG_MAX and jq fails with "Argument list too long".
    [[ -n "$SAVE_TRAILS_JSON" ]] \
        && jq '{data:{items:.}}' <<< "$TRAILS_ITEMS_JSON" > "$SAVE_TRAILS_JSON"
    [[ -n "$SAVE_PROFILES_JSON" ]] \
        && jq '{data:{items:.}}' <<< "$PROFILES_ITEMS_JSON" > "$SAVE_PROFILES_JSON"

    log_debug "Audit trails: $(jq 'length' <<< "$TRAILS_ITEMS_JSON"), audit profiles: $(jq 'length' <<< "$PROFILES_ITEMS_JSON")"
    return 0
}

# ------------------------------------------------------------------------------
# Function: build_rows
# Purpose.: Join targets, trails and profiles into one row per target
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Populates ROWS_JSON
# ------------------------------------------------------------------------------
build_rows() {
    log_debug "Building report rows..."

    ROWS_JSON=$(ds_build_trail_rows \
        "$TARGETS_PAYLOAD_JSON" "$TRAILS_ITEMS_JSON" "$PROFILES_ITEMS_JSON" \
        "$TAG_NAMESPACE" "$STATE_FILTER") || die "Failed to build report rows"

    return 0
}

# ------------------------------------------------------------------------------
# Function: render_detail_table
# Purpose.: Render the per-target detail rows as a fixed-width table
# Args....: None
# Returns.: 0 on success
# Output..: Table to stdout
# ------------------------------------------------------------------------------
render_detail_table() {
    printf '%-44s %-6s %-8s %-16s %-10s %10s\n' \
        "TARGET" "ENV" "TYPE" "TRAIL STATE" "AUTO-PURGE" "VOLUME"
    printf '%-44s %-6s %-8s %-16s %-10s %10s\n' \
        "$(printf '%0.s-' {1..44})" "$(printf '%0.s-' {1..6})" \
        "$(printf '%0.s-' {1..8})" "$(printf '%0.s-' {1..16})" \
        "$(printf '%0.s-' {1..10})" "$(printf '%0.s-' {1..10})"

    local name env type state purge volume
    while IFS=$'\t' read -r name env type state purge volume; do
        [[ -z "$name" ]] && continue
        printf '%-44s %-6s %-8s %-16s %-10s %10s\n' \
            "$name" "$env" "$type" "$state" "$purge" "$(ds_format_bytes "$volume")"
    done < <(jq -r '.[] | [.target, .environment, .type, .["trail-state"], .["auto-purge"], (.["volume-bytes"] // "")] | @tsv' <<< "$ROWS_JSON")
}

# ------------------------------------------------------------------------------
# Function: render_summary_table
# Purpose.: Render the per-environment summary as a fixed-width table
# Args....: None
# Returns.: 0 on success
# Output..: Table to stdout
# ------------------------------------------------------------------------------
render_summary_table() {
    printf '%-8s %8s %10s %12s %16s %9s %6s %10s\n' \
        "ENV" "TARGETS" "COLLECTING" "NOT_STARTED" "NEEDS_ATTENTION" "NO_TRAIL" "OTHER" "VOLUME"
    printf '%-8s %8s %10s %12s %16s %9s %6s %10s\n' \
        "$(printf '%0.s-' {1..8})" "$(printf '%0.s-' {1..8})" \
        "$(printf '%0.s-' {1..10})" "$(printf '%0.s-' {1..12})" \
        "$(printf '%0.s-' {1..16})" "$(printf '%0.s-' {1..9})" \
        "$(printf '%0.s-' {1..6})" "$(printf '%0.s-' {1..10})"

    local env total collecting not_started attention no_trail other volume
    while IFS=$'\t' read -r env total collecting not_started attention no_trail other volume; do
        [[ -z "$env" ]] && continue
        printf '%-8s %8s %10s %12s %16s %9s %6s %10s\n' \
            "$env" "$total" "$collecting" "$not_started" "$attention" "$no_trail" "$other" \
            "$(ds_format_bytes "$volume")"
    done < <(summary_json | jq -r '.[] | [.environment, .targets, .collecting, .not_started, .needs_attention, .no_trail, .other, .["volume-bytes"]] | @tsv')
}

# ------------------------------------------------------------------------------
# Function: summary_json
# Purpose.: Aggregate the report rows per environment
# Args....: None
# Returns.: 0 on success
# Output..: JSON array on stdout, one object per environment plus a TOTAL row
# ------------------------------------------------------------------------------
summary_json() {
    ds_trail_summary_json "$ROWS_JSON"
}

# ------------------------------------------------------------------------------
# Function: render_report
# Purpose.: Render the report in the requested output format
# Args....: None
# Returns.: 0 on success
# Output..: Report to stdout
# ------------------------------------------------------------------------------
render_report() {
    case "$OUTPUT_FORMAT" in
        json)
            # $ROWS_JSON arrives on stdin - as --argjson it exceeds ARG_MAX
            # on large compartments. The summary is one row per environment
            # and stays small enough for argv.
            jq --argjson summary "$(summary_json)" \
                --arg generated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                '{generated: $generated, targets: length, rows: ., summary: $summary}' \
                <<< "$ROWS_JSON"
            ;;
        csv)
            if [[ "$SUMMARY_MODE" != "only" ]]; then
                printf 'target,target-id,environment,type,stage,target-state,trail-state,trail-count,auto-purge,volume-bytes\n'
                jq -r '.[] | [.target, .["target-id"], .environment, .type, .stage,
                              .["target-state"], .["trail-state"], .["trail-count"],
                              .["auto-purge"], (.["volume-bytes"] // "")] | @csv' <<< "$ROWS_JSON"
            fi
            if [[ "$SUMMARY_MODE" != "none" ]]; then
                [[ "$SUMMARY_MODE" == "both" ]] && printf '\n'
                printf 'environment,targets,collecting,not_started,needs_attention,no_trail,other,volume-bytes\n'
                summary_json | jq -r '.[] | [.environment, .targets, .collecting, .not_started,
                                             .needs_attention, .no_trail, .other,
                                             .["volume-bytes"]] | @csv'
            fi
            ;;
        *)
            printf 'Data Safe Audit Trail Report\n'
            printf 'Generated: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            [[ -n "$COMPARTMENT" ]] && printf 'Compartment: %s\n' "$COMPARTMENT"
            printf 'Targets: %s\n\n' "$(jq 'length' <<< "$ROWS_JSON")"

            if [[ "$SUMMARY_MODE" != "only" ]]; then
                render_detail_table
                printf '\n'
            fi
            if [[ "$SUMMARY_MODE" != "none" ]]; then
                printf 'Summary by environment\n'
                render_summary_table
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
    collect_state
    build_rows

    if [[ -n "$REPORT_FILE" ]]; then
        render_report | tee "$REPORT_FILE"
        log_info "Report written to: $REPORT_FILE"
    else
        render_report
    fi

    log_info "${SCRIPT_NAME} completed successfully"
}

main "$@"
