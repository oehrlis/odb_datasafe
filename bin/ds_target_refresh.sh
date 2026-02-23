#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_refresh.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Refresh Oracle Data Safe target databases
# Usage......: ds_target_refresh.sh [OPTIONS] [TARGETS...]
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/ds_lib.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE_STATE:=NEEDS_ATTENTION}" # Default to NEEDS_ATTENTION
: "${DRY_RUN:=false}"
: "${WAIT_FOR_COMPLETION:=false}" # Default to no-wait for speed
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${ALLOW_STALE_SELECTION:=false}"
: "${MAX_SNAPSHOT_AGE:=24h}"

# Counters
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and help message
# Returns.: 0 (exits after display)
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [TARGETS...]

Description:
  Refresh Oracle Data Safe target databases. Updates target metadata from
  the source database.
  
  When no compartment or targets are specified, refreshes all targets in
  DS_ROOT_COMP compartment (configured in .env).

Options:
  Common:
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
    -n, --dry-run               Dry-run mode (show what would be done)
        --log-file FILE         Log to file

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE})

  Target Selection:
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                   Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex (substring match)
    -L, --lifecycle STATE       Filter by lifecycle state (default: NEEDS_ATTENTION)
                                Use ACTIVE, NEEDS_ATTENTION, etc.
        --input-json FILE       Read targets from local JSON (array or {data:[...]})
        --save-json FILE        Save selected target JSON payload
        --allow-stale-selection Allow apply/refresh from --input-json
                    (disabled by default for safety)
        --max-snapshot-age AGE  Max input-json age (default: ${MAX_SNAPSHOT_AGE})
                    Examples: 900, 30m, 24h, 2d, off
        --wait                  Wait for each refresh to complete (slower but shows status)
        --no-wait               Don't wait for completion (default, faster for bulk)

Examples:
    # Refresh all NEEDS_ATTENTION targets in DS_ROOT_COMP (fast, async)
    ${SCRIPT_NAME}

    # Explicitly select all targets from DS_ROOT_COMP
    ${SCRIPT_NAME} --all

    # Refresh with progress monitoring (slower)
    ${SCRIPT_NAME} --wait

    # Refresh specific compartment
    ${SCRIPT_NAME} -c MyCompartment

    # Refresh specific targets (dry-run)
    ${SCRIPT_NAME} -T target1,target2 --dry-run

    # Refresh all ACTIVE targets
    ${SCRIPT_NAME} -c MyCompartment -L ACTIVE

    # Refresh by positional args
    ${SCRIPT_NAME} target1 target2 target3

    # Dry-run from saved selection JSON
    ${SCRIPT_NAME} --input-json ./target_selection.json --dry-run

    # Apply refresh from saved JSON (requires explicit stale-selection override)
    ${SCRIPT_NAME} --input-json ./target_selection.json --allow-stale-selection

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on invalid arguments
# Notes...: Sets global variables for script configuration
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
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
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
            --allow-stale-selection)
                ALLOW_STALE_SELECTION=true
                shift
                ;;
            --max-snapshot-age)
                need_val "$1" "${2:-}"
                MAX_SNAPSHOT_AGE="$2"
                shift 2
                ;;
            --wait)
                WAIT_FOR_COMPLETION=true
                shift
                ;;
            --no-wait)
                WAIT_FOR_COMPLETION=false
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
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Positional args become targets
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and dependencies
# Returns.: 0 on success, exits on validation failure
# Notes...: Checks for required commands and sets default compartment if needed
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        ds_validate_input_json_freshness "$INPUT_JSON" "$MAX_SNAPSHOT_AGE" || die "Input JSON snapshot freshness check failed"

        if [[ "$DRY_RUN" != "true" && "$ALLOW_STALE_SELECTION" != "true" ]]; then
            die "Refusing apply refresh from --input-json without --allow-stale-selection (use --dry-run to preview)"
        fi

        if [[ "$SELECT_ALL" == "true" || -n "$COMPARTMENT" || -n "$TARGETS" ]]; then
            log_warn "Ignoring --all/--compartment/--targets when --input-json is provided"
        fi

        if [[ "$DRY_RUN" != "true" ]]; then
            require_oci_cli
        fi
    else
        require_oci_cli

        COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

        if [[ "$SELECT_ALL" == "true" ]]; then
            log_info "Using DS_ROOT_COMP scope via --all"
        fi

        # Resolve compartment using new pattern: explicit -c > DS_ROOT_COMP > error
        if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
            COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
            log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
        fi
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: refresh_single_target
# Purpose.: Refresh a single Data Safe target database
# Args....: $1 - Target OCID
#           $2 - Current target number (optional, default: 1)
#           $3 - Total targets (optional, default: 1)
# Returns.: 0 on success, 1 on error
# Output..: Progress and status messages to stdout/stderr
# Notes...: Updates SUCCESS_COUNT or FAILED_COUNT counters
# ------------------------------------------------------------------------------
refresh_single_target() {
    local target_ocid="$1"
    local target_name="${2:-}"
    local current="${3:-1}"
    local total="${4:-1}"

    if [[ -z "$target_name" ]]; then
        target_name=$(ds_resolve_target_name "$target_ocid" 2> /dev/null) || target_name="$target_ocid"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[$current/$total] [DRY-RUN] Would refresh: $target_name ($target_ocid)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    fi

    # Pass the counter info to ds_refresh_target
    if ds_refresh_target "$target_ocid" "$current" "$total"; then
        log_debug "✓ Successfully refreshed: $target_name"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        log_error "✗ Failed to refresh: $target_name"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - discovers and refreshes target databases
# Returns.: 0 on success, exits with error if targets fail
# Output..: Progress messages and summary statistics to stdout/stderr
# Notes...: Orchestrates target discovery, refresh operations, and reporting
# ------------------------------------------------------------------------------
do_work() {
    local -a target_rows=()

    log_info "Discovering targets (lifecycle: $LIFECYCLE_STATE)"
    local targets_json
    targets_json=$(ds_collect_targets_source "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER" "$INPUT_JSON" "$SAVE_JSON") || die "Failed to collect targets"

    mapfile -t target_rows < <(echo "$targets_json" | jq -r '.data[] | [(.id // ""), (."display-name" // "")] | @tsv')

    local count=${#target_rows[@]}
    if [[ $count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found matching criteria"
        return 0
    fi

    log_info "Found $count targets to refresh"

    # Refresh each target
    local total=${#target_rows[@]}
    local current=0
    local target_ocid target_name

    for target_row in "${target_rows[@]}"; do
        IFS=$'\t' read -r target_ocid target_name <<< "$target_row"
        [[ -z "$target_ocid" ]] && continue
        current=$((current + 1))
        refresh_single_target "$target_ocid" "$target_name" "$current" "$total"
    done

    # Print summary
    echo ""
    log_info "====== Refresh Summary ======"
    log_info "Total targets:    $total"
    log_info "Successful:       $SUCCESS_COUNT"
    log_info "Failed:           $FAILED_COUNT"
    log_info "Skipped:          $SKIPPED_COUNT"
    log_info "============================"

    # Exit with error if any failed
    if [[ $FAILED_COUNT -gt 0 ]]; then
        die "Some targets failed to refresh" 10
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, 1 on error
# Notes...: Initializes configuration, validates inputs, and executes work
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    init_config "${SCRIPT_NAME}.conf"
    parse_args "$@"
    validate_inputs
    do_work

    log_info "Refresh completed successfully"
}

# Handle --help before setting up error traps (to avoid trap issues with exit)
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        usage
    fi
done

# Setup error handling before main execution
setup_error_handling

main "$@"

# Explicit exit to prevent spurious error trap
exit 0
