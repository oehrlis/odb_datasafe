#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_refresh.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v0.2.0
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
readonly SCRIPT_VERSION="0.2.0"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=NEEDS_ATTENTION}"  # Default to NEEDS_ATTENTION
: "${DRY_RUN:=false}"
: "${WAIT_FOR_COMPLETION:=false}"  # Default to no-wait for speed

# Counters
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# =============================================================================
# FUNCTIONS
# =============================================================================

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [TARGETS...]

Description:
  Refresh Oracle Data Safe target databases. Updates target metadata from
  the source database.
  
  When no compartment or targets are specified, refreshes all targets in
  DS_ROOT_COMP compartment (configured in .env).

Options:
  Common:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -d, --debug             Enable debug output
    -n, --dry-run           Dry-run mode (show what would be done)
    --log-file FILE         Log to file

  OCI:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE})

  Target Selection:
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP from .env)
    -T, --targets LIST      Comma-separated target names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state (default: NEEDS_ATTENTION)
                            Use ACTIVE, NEEDS_ATTENTION, etc.
    --wait                  Wait for each refresh to complete (slower but shows status)
    --no-wait               Don't wait for completion (default, faster for bulk)

Examples:
  # Refresh all NEEDS_ATTENTION targets in DS_ROOT_COMP (fast, async)
  ${SCRIPT_NAME}

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

EOF
    exit 0
}

parse_args() {
    parse_common_opts "$@"
    
    local -a remaining=()
    set -- "${ARGS[@]}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -T|--targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -L|--lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
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

validate_inputs() {
    log_debug "Validating inputs..."
    
    require_cmd oci jq
    
    # If neither targets nor compartment specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi
}

refresh_single_target() {
    local target_ocid="$1"
    local current="${2:-1}"
    local total="${3:-1}"
    local target_name
    
    target_name=$(ds_resolve_target_name "$target_ocid" 2>/dev/null) || {
        log_error "Failed to resolve target name: $target_ocid"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    }
    
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

do_work() {
    local -a target_ocids=()
    
    # Collect target OCIDs
    if [[ -n "$TARGETS" ]]; then
        # Process explicit targets
        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            target="${target// /}"  # trim spaces
            
            if is_ocid "$target"; then
                target_ocids+=("$target")
            else
                # Resolve name to OCID
                log_debug "Resolving target name: $target"
                local resolved
                if [[ -n "$COMPARTMENT" ]]; then
                    resolved=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || die "Failed to resolve target: $target"
                else
                    local root_comp
                    root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
                    resolved=$(ds_resolve_target_ocid "$target" "$root_comp") || die "Failed to resolve target: $target"
                fi
                
                if [[ -z "$resolved" ]]; then
                    die "Target not found: $target"
                fi
                
                target_ocids+=("$resolved")
            fi
        done
    elif [[ -n "$COMPARTMENT" ]]; then
        # List targets from compartment
        log_info "Discovering targets in compartment: $COMPARTMENT (lifecycle: $LIFECYCLE_STATE)"
        
        local comp_ocid
        comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT")
        
        local targets_json
        targets_json=$(ds_list_targets "$comp_ocid" "$LIFECYCLE_STATE")
        
        # Extract OCIDs
        mapfile -t target_ocids < <(echo "$targets_json" | jq -r '.data[].id')
        
        local count=${#target_ocids[@]}
        if [[ $count -eq 0 ]]; then
            log_warn "No targets found matching criteria"
            return 0
        fi
        
        log_info "Found $count targets to refresh"
    fi
    
    # Refresh each target
    local total=${#target_ocids[@]}
    local current=0
    
    for target_ocid in "${target_ocids[@]}"; do
        current=$((current + 1))
        refresh_single_target "$target_ocid" "$current" "$total"
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
