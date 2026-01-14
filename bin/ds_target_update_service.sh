#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v0.2.0
# Purpose....: Update Oracle Data Safe target service names
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="0.2.0"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${DB_DOMAIN:=oradba.ch}"
: "${APPLY_CHANGES:=false}"

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

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

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Update Oracle Data Safe target service names to "<base>_exa.<domain>"
  format when they do not already end with the specified domain.

Options:
  Common:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -d, --debug             Enable debug output
    --log-file FILE         Log to file

  OCI:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file

  Selection:
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP from .env)
    -T, --targets LIST      Comma-separated target names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state (default: ${LIFECYCLE_STATE})

  Service Update:
    --domain DOMAIN         Domain for new service names (default: ${DB_DOMAIN})
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)

Service Name Rules:
  - Target format: "<base>_exa.<domain>"
  - If service already ends with domain: no change
  - Extract base name from current service (remove domain if present)
  - Apply standard naming: "{base}_exa.{domain}"

Examples:
  # Dry-run for all ACTIVE targets
  ${SCRIPT_NAME}

  # Apply changes to specific targets
  ${SCRIPT_NAME} -T target1,target2 --apply

  # Update with custom domain
  ${SCRIPT_NAME} --domain custom.example --apply

  # Process specific compartment
  ${SCRIPT_NAME} -c cmp-lzp-dbso-prod-projects --apply

EOF
    exit 0
}

parse_args() {
    parse_common_opts "$@"
    
    # Parse script-specific options
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
            --domain)
                need_val "$1" "${2:-}"
                DB_DOMAIN="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
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
    
    # Handle positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

validate_inputs() {
    log_debug "Validating inputs..."
    
    require_cmd oci jq
    
    # If no scope specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi
    
    # Validate domain
    [[ -n "$DB_DOMAIN" ]] || die "Domain cannot be empty"
    
    # Show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi
}

# ------------------------------------------------------------------------------
# Function....: compute_new_service_name
# Purpose.....: Transform current service to "<base>_exa.<domain>"
# Parameters..: $1 - current service name
#               $2 - domain
# Returns.....: New service name
# ------------------------------------------------------------------------------
compute_new_service_name() {
    local current="$1" 
    local domain="$2"
    
    [[ -z "$current" ]] && { echo ""; return 0; }
    
    # If already ends with domain, no change needed
    if [[ "$current" == *".${domain}" ]]; then
        echo "$current"
        return 0
    fi
    
    # Extract base name (remove existing domain if present)
    local base="${current%%.*}"
    
    # Handle underscore-separated names (take second part if exists)
    local token2="${base#*_}"
    local name_base
    if [[ "$token2" != "$base" && -n "$token2" ]]; then
        name_base="$token2"
    else
        name_base="$base"
    fi
    
    # Convert to lowercase and apply standard format
    name_base="${name_base,,}"
    echo "${name_base}_exa.${domain}"
}

# ------------------------------------------------------------------------------
# Function....: update_target_service
# Purpose.....: Update service name for a single target
# Parameters..: $1 - target OCID
#               $2 - target name
#               $3 - current service name
# ------------------------------------------------------------------------------
update_target_service() {
    local target_ocid="$1"
    local target_name="$2"
    local current_service="$3"
    
    log_debug "Processing target: $target_name ($target_ocid)"
    log_debug "Current service: $current_service"
    
    # Compute new service name
    local new_service
    new_service=$(compute_new_service_name "$current_service" "$DB_DOMAIN")
    
    log_info "Target: $target_name"
    log_info "  Current service: $current_service"
    log_info "  New service: $new_service"
    
    # Check if change is needed
    if [[ "$current_service" == "$new_service" ]]; then
        log_info "  ✅ No change needed (already correct format)"
        return 0
    fi
    
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating service name..."
        
        if oci_exec data-safe target-database update \
            --target-database-id "$target_ocid" \
            --connection-option "{\"connectionType\": \"PRIVATE_ENDPOINT\", \"datasafePrivateEndpointId\": null}" \
            --database-details "{\"serviceName\": \"$new_service\"}" >/dev/null; then
            log_info "  ✅ Service updated successfully"
            return 0
        else
            log_error "  ❌ Failed to update service name"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function....: list_targets_in_compartment
# Purpose.....: List targets in compartment with current service names
# Parameters..: $1 - compartment OCID or name
# Returns.....: JSON array of targets
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"
    local comp_ocid
    
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1
    
    log_debug "Listing targets in compartment: $comp_ocid"
    
    local -a cmd=(
        data-safe target-database list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )
    
    if [[ -n "$LIFECYCLE_STATE" ]]; then
        cmd+=(--lifecycle-state "$LIFECYCLE_STATE")
    fi
    
    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function....: get_target_details
# Purpose.....: Get target details including service name
# Parameters..: $1 - target OCID
# Returns.....: JSON object with target details
# ------------------------------------------------------------------------------
get_target_details() {
    local target_ocid="$1"
    
    log_debug "Getting details for: $target_ocid"
    
    oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function....: do_work
# Purpose.....: Main work function
# ------------------------------------------------------------------------------
do_work() {
    local success_count=0 error_count=0
    
    # Collect target data
    if [[ -n "$TARGETS" ]]; then
        # Process specific targets
        log_info "Processing specific targets..."
        
        local -a target_list
        IFS=',' read -ra target_list <<< "$TARGETS"
        
        for target in "${target_list[@]}"; do
            target="${target// /}"  # trim spaces
            
            local target_ocid target_data target_name current_service
            
            if is_ocid "$target"; then
                target_ocid="$target"
            else
                # Resolve target name to OCID
                log_debug "Resolving target name: $target"
                local resolved
                if [[ -n "$COMPARTMENT" ]]; then
                    resolved=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || die "Failed to resolve target: $target"
                else
                    local root_comp
                    root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
                    resolved=$(ds_resolve_target_ocid "$target" "$root_comp") || die "Failed to resolve target: $target"
                fi
                
                [[ -n "$resolved" ]] || die "Target not found: $target"
                target_ocid="$resolved"
            fi
            
            # Get target details
            if target_data=$(get_target_details "$target_ocid"); then
                target_name=$(echo "$target_data" | jq -r '."display-name"')
                current_service=$(echo "$target_data" | jq -r '.databaseDetails.serviceName // ""')
                
                if update_target_service "$target_ocid" "$target_name" "$current_service"; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
            else
                log_error "Failed to get details for target: $target_ocid"
                error_count=$((error_count + 1))
            fi
        done
    else
        # Process targets from compartment
        log_info "Processing targets from compartment..."
        local json_data
        json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"
        
        local total_count
        total_count=$(echo "$json_data" | jq '.data | length')
        log_info "Found $total_count targets to process"
        
        if [[ $total_count -eq 0 ]]; then
            log_warn "No targets found"
            return 0
        fi
        
        local current=0
        while read -r target_ocid target_name current_service; do
            current=$((current + 1))
            log_info "[$current/$total_count] Processing: $target_name"
            
            if update_target_service "$target_ocid" "$target_name" "$current_service"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name", .databaseDetails.serviceName // ""] | @tsv')
    fi
    
    # Summary
    log_info "Service update completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"
    
    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    
    # Setup error handling
    setup_error_handling
    
    # Validate inputs
    validate_inputs
    
    # Execute main work
    if do_work; then
        log_info "Service update completed successfully"
    else
        die "Service update failed with errors"
    fi
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_update_service.sh ---------------------------------------