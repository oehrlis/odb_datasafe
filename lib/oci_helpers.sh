#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: oci_helpers.sh (v4.0.0)
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: OCI CLI wrapper functions for Oracle Data Safe operations
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Guard against multiple sourcing
[[ -n "${OCI_HELPERS_SH_LOADED:-}" ]] && return 0
readonly OCI_HELPERS_SH_LOADED=1

# Require common.sh
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    echo "ERROR: oci_helpers.sh requires common.sh to be loaded first" >&2
    exit 1
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

: "${OCI_CLI_PROFILE:=DEFAULT}"
: "${OCI_CLI_REGION:=}"
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${DRY_RUN:=false}"

# Global cache for resolved root compartment OCID
_DS_ROOT_COMP_OCID_CACHE=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: is_ocid
# Purpose.....: Check if string is an OCID
# Parameters..: $1 - string to check
# Returns.....: 0 if OCID, 1 otherwise
# ------------------------------------------------------------------------------
is_ocid() {
    local str="$1"
    [[ "$str" =~ ^ocid1\. ]]
}

# ------------------------------------------------------------------------------
# Function....: get_root_compartment_ocid
# Purpose.....: Get root compartment OCID (resolves name if needed)
# Returns.....: Root compartment OCID on stdout
# Environment.: Uses DS_ROOT_COMP (can be name or OCID)
# Usage.......: root_comp=$(get_root_compartment_ocid) || die "Failed"
# ------------------------------------------------------------------------------
get_root_compartment_ocid() {
    # Return cached value if available
    if [[ -n "$_DS_ROOT_COMP_OCID_CACHE" ]]; then
        echo "$_DS_ROOT_COMP_OCID_CACHE"
        return 0
    fi
    
    # Check if DS_ROOT_COMP is set
    if [[ -z "${DS_ROOT_COMP:-}" ]]; then
        log_error "DS_ROOT_COMP not set. Please configure in .env or datasafe.conf"
        return 1
    fi
    
    local root_comp="$DS_ROOT_COMP"
    
    # If already an OCID, use it directly
    if is_ocid "$root_comp"; then
        log_debug "DS_ROOT_COMP is already an OCID: $root_comp"
        _DS_ROOT_COMP_OCID_CACHE="$root_comp"
        echo "$root_comp"
        return 0
    fi
    
    # It's a name, resolve it
    log_debug "Resolving DS_ROOT_COMP name to OCID: $root_comp"
    local resolved
    resolved=$(oci_resolve_compartment_ocid "$root_comp") || {
        log_error "Failed to resolve DS_ROOT_COMP: $root_comp"
        return 1
    }
    
    if [[ -z "$resolved" ]]; then
        log_error "DS_ROOT_COMP not found: $root_comp"
        return 1
    fi
    
    log_debug "Resolved DS_ROOT_COMP '$root_comp' to OCID: $resolved"
    _DS_ROOT_COMP_OCID_CACHE="$resolved"
    echo "$resolved"
    return 0
}

# =============================================================================
# OCI CLI WRAPPER
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: oci_exec
# Purpose.....: Execute OCI CLI with standard options and error handling
# Parameters..: $@ - oci command and arguments
# Usage.......: oci_exec data-safe target-database list --compartment-id "$comp"
# Notes.......: Handles profile, region, config file, dry-run, and error logging
# ------------------------------------------------------------------------------
oci_exec() {
    local -a cmd=(oci)
    
    # Add standard options
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")
    
    # Add the actual command
    cmd+=("$@")
    
    # Log command in debug mode
    log_debug "OCI command: ${cmd[*]}"
    
    # Dry-run: just show command
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: ${cmd[*]}"
        return 0
    fi
    
    # Execute command
    local output
    local exit_code=0
    
    if output=$("${cmd[@]}" 2>&1); then
        log_trace "OCI command successful"
        echo "$output"
        return 0
    else
        exit_code=$?
        log_error "OCI command failed (exit ${exit_code}): ${cmd[*]}"
        log_debug "Output: $output"
        return $exit_code
    fi
}

# =============================================================================
# COMPARTMENT OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: oci_resolve_compartment_ocid
# Purpose.....: Resolve compartment name to OCID, or validate OCID
# Parameters..: $1 - compartment name or OCID
# Returns.....: OCID on stdout
# Usage.......: comp_ocid=$(oci_resolve_compartment_ocid "MyCompartment")
# ------------------------------------------------------------------------------
oci_resolve_compartment_ocid() {
    local input="$1"
    
    # Already an OCID?
    if is_ocid "$input"; then
        echo "$input"
        return 0
    fi
    
    # Search by name
    log_debug "Resolving compartment name: $input"
    
    local result
    result=$(oci_exec iam compartment list \
        --all \
        --compartment-id-in-subtree true \
        --query "data[?name=='${input}'].id | [0]" \
        --raw-output)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        die "Compartment not found: $input"
    fi
    
    log_debug "Resolved compartment: $input -> $result"
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function....: oci_resolve_compartment_name
# Purpose.....: Resolve compartment OCID to name
# Parameters..: $1 - compartment OCID
# Returns.....: Name on stdout
# Usage.......: comp_name=$(oci_resolve_compartment_name "$ocid")
# ------------------------------------------------------------------------------
oci_resolve_compartment_name() {
    local ocid="$1"
    
    if ! is_ocid "$ocid"; then
        die "Invalid compartment OCID: $ocid"
    fi
    
    log_debug "Resolving compartment OCID: $ocid"
    
    local result
    result=$(oci_exec iam compartment get \
        --compartment-id "$ocid" \
        --query 'data.name' \
        --raw-output)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        die "Compartment not found: $ocid"
    fi
    
    echo "$result"
}

# =============================================================================
# DATA SAFE TARGET OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: ds_list_targets
# Purpose.....: List Data Safe targets in compartment
# Parameters..: $1 - compartment OCID or name
#               $2 - lifecycle filter (optional, e.g., "ACTIVE,NEEDS_ATTENTION")
# Returns.....: JSON array of targets
# Usage.......: targets=$(ds_list_targets "$comp" "ACTIVE")
# ------------------------------------------------------------------------------
ds_list_targets() {
    local compartment="$1"
    local lifecycle="${2:-}"
    
    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment")
    
    log_debug "Listing Data Safe targets in compartment: $comp_ocid"
    
    local -a cmd=(
        data-safe target-database list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )
    
    # Add lifecycle filter if provided
    if [[ -n "$lifecycle" ]]; then
        cmd+=(--lifecycle-state "$lifecycle")
    fi
    
    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function....: ds_get_target
# Purpose.....: Get details for a single Data Safe target
# Parameters..: $1 - target OCID
# Returns.....: JSON object with target details
# Usage.......: target=$(ds_get_target "$target_ocid")
# ------------------------------------------------------------------------------
ds_get_target() {
    local target_ocid="$1"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    log_debug "Getting Data Safe target: $target_ocid"
    
    oci_exec data-safe target-database get \
        --target-database-id "$target_ocid"
}

# ------------------------------------------------------------------------------
# Function....: ds_resolve_target_ocid
# Purpose.....: Resolve target name to OCID
# Parameters..: $1 - target name or OCID
#               $2 - compartment OCID or name (optional, for name resolution)
# Returns.....: OCID on stdout
# Usage.......: target_ocid=$(ds_resolve_target_ocid "my-target" "$comp")
# ------------------------------------------------------------------------------
ds_resolve_target_ocid() {
    local input="$1"
    local compartment="${2:-}"
    
    # Already an OCID?
    if is_ocid "$input"; then
        echo "$input"
        return 0
    fi
    
    # Need compartment to search by name
    if [[ -z "$compartment" ]]; then
        die "Compartment required to resolve target name: $input"
    fi
    
    log_debug "Resolving target name: $input"
    
    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment")
    
    local result
    result=$(oci_exec data-safe target-database list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --all \
        --query "data[?\"display-name\"=='${input}'].id | [0]" \
        --raw-output)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        die "Target not found: $input"
    fi
    
    log_debug "Resolved target: $input -> $result"
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function....: ds_resolve_target_name
# Purpose.....: Resolve target OCID to name
# Parameters..: $1 - target OCID
# Returns.....: Display name on stdout
# Usage.......: target_name=$(ds_resolve_target_name "$target_ocid")
# ------------------------------------------------------------------------------
ds_resolve_target_name() {
    local ocid="$1"
    
    if ! is_ocid "$ocid"; then
        die "Invalid target OCID: $ocid"
    fi
    
    log_debug "Resolving target OCID: $ocid"
    
    local result
    result=$(oci_exec data-safe target-database get \
        --target-database-id "$ocid" \
        --query 'data."display-name"' \
        --raw-output)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        die "Target not found: $ocid"
    fi
    
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function....: ds_get_target_compartment
# Purpose.....: Get compartment OCID for a target
# Parameters..: $1 - target OCID
# Returns.....: Compartment OCID on stdout
# Usage.......: comp=$(ds_get_target_compartment "$target_ocid")
# ------------------------------------------------------------------------------
ds_get_target_compartment() {
    local target_ocid="$1"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    local result
    result=$(oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data."compartment-id"' \
        --raw-output)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        die "Failed to get compartment for target: $target_ocid"
    fi
    
    echo "$result"
}

# =============================================================================
# DATA SAFE TARGET MODIFICATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: ds_refresh_target
# Purpose.....: Refresh a Data Safe target
# Parameters..: $1 - target OCID
# Usage.......: ds_refresh_target "$target_ocid"
# ------------------------------------------------------------------------------
ds_refresh_target() {
    local target_ocid="$1"
    local current="${2:-1}"
    local total="${3:-1}"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    local target_name
    target_name=$(ds_resolve_target_name "$target_ocid")
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would refresh: $target_name ($target_ocid)"
        return 0
    fi
    
    # Build OCI command based on wait flag
    local output
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        log_info "[$current/$total] Refreshing: $target_name (waiting for completion...)"
        output=$(oci_exec data-safe target-database refresh \
            --target-database-id "$target_ocid" \
            --wait-for-state SUCCEEDED \
            --wait-for-state FAILED)
    else
        log_info "[$current/$total] Refreshing: $target_name (async)"
        output=$(oci_exec data-safe target-database refresh \
            --target-database-id "$target_ocid")
    fi
    
    local exit_code=$?
    
    # Handle output based on log level and log file
    if [[ -n "$output" ]]; then
        if [[ -n "${LOG_FILE:-}" ]]; then
            # Send to log file if configured
            echo "$output" >> "${LOG_FILE}"
        fi
        
        # Show on stdout only in debug mode
        if [[ $(_log_level_num "${LOG_LEVEL:-INFO}") -le 1 ]]; then
            echo "$output"
        fi
    fi
    
    return $exit_code
}

# ------------------------------------------------------------------------------
# Function....: ds_update_target_tags
# Purpose.....: Update freeform and/or defined tags on a target
# Parameters..: $1 - target OCID
#               $2 - freeform tags JSON (optional)
#               $3 - defined tags JSON (optional)
# Usage.......: ds_update_target_tags "$ocid" '{"env":"prod"}' '{}'
# ------------------------------------------------------------------------------
ds_update_target_tags() {
    local target_ocid="$1"
    local freeform_tags="${2:-}"
    local defined_tags="${3:-}"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    local target_name
    target_name=$(ds_resolve_target_name "$target_ocid")
    
    log_info "Updating tags for target: $target_name"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would update tags: $target_name ($target_ocid)"
        [[ -n "$freeform_tags" ]] && log_debug "Freeform tags: $freeform_tags"
        [[ -n "$defined_tags" ]] && log_debug "Defined tags: $defined_tags"
        return 0
    fi
    
    local -a cmd=(
        data-safe target-database update
        --target-database-id "$target_ocid"
        --force
    )
    
    [[ -n "$freeform_tags" ]] && cmd+=(--freeform-tags "$freeform_tags")
    [[ -n "$defined_tags" ]] && cmd+=(--defined-tags "$defined_tags")
    
    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function....: ds_update_target_service
# Purpose.....: Update service name for a target
# Parameters..: $1 - target OCID
#               $2 - new service name
# Usage.......: ds_update_target_service "$ocid" "mydb_exa.domain.com"
# ------------------------------------------------------------------------------
ds_update_target_service() {
    local target_ocid="$1"
    local service_name="$2"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    if [[ -z "$service_name" ]]; then
        die "Service name is required"
    fi
    
    local target_name
    target_name=$(ds_resolve_target_name "$target_ocid")
    
    log_info "Updating service name for target: $target_name -> $service_name"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would update service: $target_name -> $service_name"
        return 0
    fi
    
    # Get current connection details
    local conn_json
    conn_json=$(oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data."connection-option"')
    
    # Update service name in connection JSON
    local updated_json
    updated_json=$(echo "$conn_json" | jq --arg svc "$service_name" \
        '.["database-connection-string"] = $svc')
    
    # Update target
    oci_exec data-safe target-database update \
        --target-database-id "$target_ocid" \
        --connection-option "$updated_json" \
        --force
}

# ------------------------------------------------------------------------------
# Function....: ds_delete_target
# Purpose.....: Delete a Data Safe target
# Parameters..: $1 - target OCID
# Usage.......: ds_delete_target "$target_ocid"
# ------------------------------------------------------------------------------
ds_delete_target() {
    local target_ocid="$1"
    
    if ! is_ocid "$target_ocid"; then
        die "Invalid target OCID: $target_ocid"
    fi
    
    local target_name
    target_name=$(ds_resolve_target_name "$target_ocid")
    
    log_warn "Deleting target: $target_name"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would delete: $target_name ($target_ocid)"
        return 0
    fi
    
    oci_exec data-safe target-database delete \
        --target-database-id "$target_ocid" \
        --force
}

# =============================================================================
# UTILITIES
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: ds_count_by_lifecycle
# Purpose.....: Count targets by lifecycle state
# Parameters..: $1 - targets JSON (from ds_list_targets)
# Returns.....: Summary string
# Usage.......: summary=$(ds_count_by_lifecycle "$targets")
# ------------------------------------------------------------------------------
ds_count_by_lifecycle() {
    local targets_json="$1"
    
    require_cmd jq
    
    echo "$targets_json" | jq -r '
        .data 
        | group_by(."lifecycle-state") 
        | map({state: .[0]."lifecycle-state", count: length}) 
        | .[] 
        | "\(.state): \(.count)"
    '
}

log_trace "oci_helpers.sh loaded (v4.0.0)"
