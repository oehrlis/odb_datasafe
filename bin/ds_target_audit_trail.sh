#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_audit_trail.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose....: Start Oracle Data Safe audit trails for target databases.
#              Supports single/multiple targets by name/OCID, or compartment scan.
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE:=ACTIVE}"
: "${START_TIME:=now}"
: "${AUTO_PURGE:=true}"
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime globals
RESOLVED_TARGETS=()
started_count=0
failed_count=0

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

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
    Start Data Safe audit trails for target database(s). Supports single/multiple
    targets by name/OCID, or scan entire compartment by lifecycle state.

Options:
  Common:
    -h, --help                      Show this help message
    -V, --version                   Show version
    -v, --verbose                   Enable verbose output (default for this script)
    -d, --debug                     Enable debug output
        --log-file FILE             Log to file

  OCI:
        --oci-profile PROFILE       OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION         OCI region
        --oci-config FILE           OCI config file

  Target Selection:
    -T, --targets LIST              Comma-separated target names/OCIDs
    -c, --compartment COMP          Compartment OCID or name (default: DS_ROOT_COMP)
    -A, --all                       Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -r, --filter REGEX              Filter target names by regex (substring match)

  Filtering:
    -L, --lifecycle STATES          Lifecycle state filter (default: ACTIVE)
                                    Use comma-separated values: ACTIVE,NEEDS_ATTENTION

  Audit Configuration:
        --start-time TIME           Collection start time (RFC3339 or 'now', default: now)
        --auto-purge true|false     Enable auto-purge on the audit trail (default: true)

  Execution:
    -n, --dry-run               Show plan without starting trails

Examples:
  # Start audit trail for specific target
  ${SCRIPT_NAME} -T my-target --audit-type UNIFIED_AUDIT

  # Start trails for all ACTIVE targets in compartment
  ${SCRIPT_NAME} -c my-compartment -L ACTIVE

  # Multiple targets (dry-run)
  ${SCRIPT_NAME} -T target1,target2 --dry-run

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables based on arguments
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
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
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
                TARGET_FILTER="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE="$2"
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

    # Handle positional arguments as additional targets
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
        else
            TARGETS="${TARGETS},${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error via die()
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Resolve --all to DS_ROOT_COMP (errors if combined with -c or -T)
    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") \
        || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    # If no explicit scope, fall back to DS_ROOT_COMP (consistent with ds_target_refresh.sh)
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") \
            || die "Specify -T/--targets, -c/--compartment, -A/--all, or set DS_ROOT_COMP"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    # Validate filter regex
    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid --filter regex: $TARGET_FILTER"
    fi

    # Validate boolean flag
    case "${AUTO_PURGE,,}" in
        true | false) ;;
        *) die "Invalid --auto-purge value: $AUTO_PURGE. Use: true or false" ;;
    esac

    log_info "Audit trail configuration:"
    log_info "  Start time: $START_TIME"
    log_info "  Auto-purge: $AUTO_PURGE"
}

# ------------------------------------------------------------------------------
# Function: resolve_targets
# Purpose.: Resolve target names/OCIDs to list of target OCIDs
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Populates RESOLVED_TARGETS array
# ------------------------------------------------------------------------------
resolve_targets() {
    log_debug "Resolving targets..."

    local targets_json
    targets_json=$(ds_collect_targets_source "$COMPARTMENT" "$TARGETS" "$LIFECYCLE" "$TARGET_FILTER") || return 1

    while IFS= read -r target_id; do
        [[ -n "$target_id" ]] && RESOLVED_TARGETS+=("$target_id")
    done < <(jq -r '.data[].id // empty' <<< "$targets_json")

    log_info "Found ${#RESOLVED_TARGETS[@]} target(s) for audit trail start"
    return 0
}

# ------------------------------------------------------------------------------
# Function: start_audit_trails
# Purpose.: Start audit trails for resolved targets
# Args....: None
# Returns.: 0 on partial/full success, 1 on all failures
# Output..: Log messages and error counters
# Notes...: Audit trails are started per-trail (list trails for target, then
#           start each by its audit-trail OCID). Valid start parameters:
#           --audit-collection-start-time, --is-auto-purge-enabled.
# ------------------------------------------------------------------------------
start_audit_trails() {
    log_info "Starting audit trails for targets..."

    started_count=0
    failed_count=0

    # Resolve 'now' to a proper RFC3339 UTC timestamp required by OCI CLI
    local collection_start_time
    if [[ "${START_TIME}" == "now" ]]; then
        collection_start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        collection_start_time="${START_TIME}"
    fi
    log_debug "  Collection start time: ${collection_start_time}"

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        log_debug "  Processing: $target_ocid"

        # Fetch target details (name + compartment-id) for logging and audit-trail list
        local target_json target_name target_compartment
        target_json=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_ocid" 2> /dev/null) || target_json="{}"
        target_name=$(jq -r '.data."display-name" // empty' <<< "$target_json")
        [[ -z "$target_name" ]] && target_name="$target_ocid"
        target_compartment=$(jq -r '.data."compartment-id" // empty' <<< "$target_json")
        [[ -z "$target_compartment" ]] && target_compartment="${COMPARTMENT:-${DS_ROOT_COMP:-}}"

        # List audit trails for this target (requires --compartment-id)
        local trails_json
        trails_json=$(oci_exec_ro data-safe audit-trail list \
            --compartment-id "$target_compartment" \
            --target-id "$target_ocid" \
            --all) || {
            log_error "Failed to list audit trails for: $target_name"
            failed_count=$((failed_count + 1))
            continue
        }
        # Extract id + lifecycle-state as TSV for each trail
        local trail_info
        trail_info=$(echo "$trails_json" | jq -r '(.data.items // .data)[]? | [.id, (."lifecycle-state" // "UNKNOWN")] | @tsv')

        if [[ -z "$trail_info" ]]; then
            log_warn "No audit trails found for: $target_name"
            continue
        fi

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would start audit trail(s) for: $target_name (${target_ocid})"
            started_count=$((started_count + 1))
            continue
        fi

        # Start each audit trail by its OCID; skip already-running trails
        local trail_ok=0 trail_fail=0 trail_skip=0
        while IFS=$'\t' read -r trail_ocid trail_state; do
            [[ -z "$trail_ocid" ]] && continue
            case "${trail_state^^}" in
                COLLECTING | STARTING | RESUMING)
                    log_info "Audit trail already ${trail_state} for: $target_name — skipping"
                    trail_skip=$((trail_skip + 1))
                    continue
                    ;;
            esac
            if oci_exec data-safe audit-trail start \
                --audit-trail-id "$trail_ocid" \
                --audit-collection-start-time "$collection_start_time" \
                --is-auto-purge-enabled "$AUTO_PURGE" > /dev/null; then
                trail_ok=$((trail_ok + 1))
            else
                log_error "Failed to start audit trail $trail_ocid for: $target_name"
                trail_fail=$((trail_fail + 1))
            fi
        done <<< "$trail_info"

        if [[ $trail_fail -gt 0 ]]; then
            log_error "Started $trail_ok, skipped $trail_skip, failed $trail_fail audit trail(s) for: $target_name"
            failed_count=$((failed_count + 1))
        else
            log_info "Started $trail_ok, skipped $trail_skip audit trail(s) for: $target_name"
            started_count=$((started_count + 1))
        fi
    done

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Parse arguments and validate
    parse_args "$@"
    validate_inputs

    # Resolve and start audit trails
    if resolve_targets && [[ ${#RESOLVED_TARGETS[@]} -gt 0 ]]; then
        start_audit_trails

        # Summary
        log_info "Audit trail start summary:"
        log_info "  Targets processed: ${#RESOLVED_TARGETS[@]}"
        log_info "  Successfully started: ${started_count}"
        log_info "  Failed starts: ${failed_count}"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] No actual changes were made"
        fi

        if [[ ${failed_count} -eq 0 ]]; then
            log_info "All audit trails started successfully"
            exit 0
        else
            die "${failed_count} audit trail(s) failed to start" 1
        fi
    else
        die "No targets available for audit trail start" 1
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

main "$@"
