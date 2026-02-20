#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_audit_trail.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
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
: "${LIFECYCLE:=ACTIVE}"
: "${AUDIT_TYPE:=UNIFIED_AUDIT}"
: "${START_TIME:=now}"
: "${AUTO_PURGE:=true}"
: "${RETENTION_DAYS:=90}"
: "${UPDATE_LAST_ARCHIVE:=true}"
: "${COLLECTION_FREQUENCY:=DAILY}"
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
    -v, --verbose                   Enable verbose output
    -d, --debug                     Enable debug output
        --log-file FILE             Log to file

  OCI:
        --oci-profile PROFILE       OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION         OCI region
        --oci-config FILE           OCI config file

  Target Selection (choose one):
    -T, --targets LIST              Comma-separated target names/OCIDs
    -c, --compartment COMP          Compartment OCID or name (scan all targets)

  Filtering:
    -L, --lifecycle STATES          Lifecycle state filter (default: ACTIVE)
                                    Use comma-separated values: ACTIVE,NEEDS_ATTENTION

  Audit Configuration:
        --audit-type TYPE           UNIFIED_AUDIT|DATABASE_VAULT|OS_AUDIT (default: UNIFIED_AUDIT)
        --start-time TIME           Start time (RFC3339 or 'now', default: now)
        --auto-purge true|false     Enable auto-purge (default: true)
        --retention-days N          Retention days (default: 90)
        --update-archive true|false Update last archive time (default: true)
        --collection-freq FREQ      DAILY|WEEKLY|MONTHLY (default: DAILY)

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
    parse_common_opts "$@"

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
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE="$2"
                shift 2
                ;;
            --audit-type)
                need_val "$1" "${2:-}"
                AUDIT_TYPE="$2"
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
            --retention-days)
                need_val "$1" "${2:-}"
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --update-archive)
                need_val "$1" "${2:-}"
                UPDATE_LAST_ARCHIVE="$2"
                shift 2
                ;;
            --collection-freq)
                need_val "$1" "${2:-}"
                COLLECTION_FREQUENCY="$2"
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

    # Must have either targets or compartment
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        die "Must specify either -T/--targets or -c/--compartment"
    fi

    # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
    COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment"
    log_debug "Resolved compartment: $COMPARTMENT"

    # Validate audit type
    case "${AUDIT_TYPE^^}" in
        UNIFIED_AUDIT | DATABASE_VAULT | OS_AUDIT) AUDIT_TYPE="${AUDIT_TYPE^^}" ;;
        *) die "Invalid audit type: $AUDIT_TYPE. Use: UNIFIED_AUDIT, DATABASE_VAULT, OS_AUDIT" ;;
    esac

    # Validate collection frequency
    case "${COLLECTION_FREQUENCY^^}" in
        DAILY | WEEKLY | MONTHLY) COLLECTION_FREQUENCY="${COLLECTION_FREQUENCY^^}" ;;
        *) die "Invalid collection frequency: $COLLECTION_FREQUENCY. Use: DAILY, WEEKLY, MONTHLY" ;;
    esac

    # Validate boolean flags
    for flag in AUTO_PURGE UPDATE_LAST_ARCHIVE; do
        local val_var="${!flag}"
        case "${val_var,,}" in
            true | false) : ;;
            *) die "Invalid $flag value: $val_var. Use: true or false" ;;
        esac
    done

    log_info "Audit trail configuration:"
    log_info "  Type: $AUDIT_TYPE"
    log_info "  Start time: $START_TIME"
    log_info "  Auto-purge: $AUTO_PURGE"
    log_info "  Retention: $RETENTION_DAYS days"
    log_info "  Collection frequency: $COLLECTION_FREQUENCY"
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

    if [[ -n "$TARGETS" ]]; then
        # Explicit targets provided: resolve by name or use as OCID
        local -a target_array
        IFS=',' read -ra target_array <<< "$TARGETS"

        for target in "${target_array[@]}"; do
            target=$(echo "$target" | xargs) # trim whitespace
            [[ -z "$target" ]] && continue

            log_debug "  Resolving: $target"
            local target_ocid
            # Use COMPARTMENT (already resolved in validate_inputs)
            target_ocid=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || {
                log_warn "Failed to resolve target: $target"
                failed_count=$((failed_count + 1))
                continue
            }
            RESOLVED_TARGETS+=("$target_ocid")
        done
    else
        # Compartment mode: list all targets with lifecycle filter
        log_debug "  Scanning compartment: $COMPARTMENT with lifecycle: $LIFECYCLE"
        local target_data
        target_data=$(ds_list_targets "$COMPARTMENT" "$LIFECYCLE") || {
            log_error "Failed to list targets in compartment"
            return 1
        }

        # Extract target IDs from JSON array
        while IFS= read -r target_ocid; do
            [[ -z "$target_ocid" ]] && continue
            RESOLVED_TARGETS+=("$target_ocid")
        done < <(echo "$target_data" | jq -r '.[] | .id // empty')
    fi

    log_info "Found ${#RESOLVED_TARGETS[@]} target(s) for audit trail start"
    return 0
}

# ------------------------------------------------------------------------------
# Function: start_audit_trails
# Purpose.: Start audit trails for resolved targets
# Args....: None
# Returns.: 0 on partial/full success, 1 on all failures
# Output..: Log messages and error counters
# ------------------------------------------------------------------------------
start_audit_trails() {
    log_info "Starting audit trails for targets..."

    started_count=0
    failed_count=0

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        log_debug "  Processing: $target_ocid"

        # Fetch target details for logging
        local target_name
        target_name=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_ocid" \
            --query 'data."display-name"' \
            --raw-output 2> /dev/null || echo "$target_ocid")

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Start audit trail for: $target_name (${target_ocid})"
            started_count=$((started_count + 1))
            continue
        fi

        # Start audit trail via OCI
        if oci_exec data-safe audit-trail start \
            --target-database-id "$target_ocid" \
            --is-auto-queries-enabled "$AUTO_PURGE" \
            --update-last-archive-timestamp "$UPDATE_LAST_ARCHIVE" \
            --audit-collection-start-time "$START_TIME" \
            --audit-trail-type "$AUDIT_TYPE" \
            --collection-frequency "$COLLECTION_FREQUENCY" > /dev/null 2>&1; then
            log_info "Started audit trail for: $target_name"
            started_count=$((started_count + 1))
        else
            log_error "Failed to start audit trail for: $target_name"
            failed_count=$((failed_count + 1))
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
            die 1 "${failed_count} audit trail(s) failed to start"
        fi
    else
        die 1 "No targets available for audit trail start"
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

main "$@"
