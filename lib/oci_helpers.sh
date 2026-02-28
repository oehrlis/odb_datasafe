#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: oci_helpers.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose.: OCI CLI wrapper functions for Oracle Data Safe operations
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
: "${DS_TARGET_CACHE_TTL:=300}"

# Global cache for resolved root compartment OCID
_DS_ROOT_COMP_OCID_CACHE=""
# Cache for target listings to avoid repeated full-list calls per compartment
_DS_TARGET_CACHE_COMP_OCID=""
_DS_TARGET_CACHE_LIFECYCLE=""
_DS_TARGET_CACHE_JSON=""
_DS_TARGET_CACHE_FILE=""

# Global cache for OCI CLI authentication check
_OCI_CLI_AUTH_CHECKED=""

# ----------------------------------------------------------------------------
# Function: _ds_target_cache_file_path
# Purpose.: Deterministic cache path for target lists
# Args....: $1 - Compartment OCID
#           $2 - Lifecycle filter (may be empty)
# Returns.: Echoes cache file path
# Notes...: Stable path allows reuse across subshells/command substitutions
# ----------------------------------------------------------------------------
_ds_target_cache_file_path() {
    local comp_ocid="$1"
    local lifecycle="$2"

    # Use cksum to build a stable, portable hash (works on macOS and Linux)
    local cache_hash
    cache_hash=$(printf '%s|%s' "$comp_ocid" "$lifecycle" | cksum | awk '{print $1}')

    local cache_dir
    cache_dir="${TMPDIR:-/tmp}/datasafe_target_cache"
    mkdir -p "$cache_dir"

    echo "${cache_dir}/targets_${cache_hash}.json"
}

# ----------------------------------------------------------------------------
# Function: _ds_cache_mtime
# Purpose.: Get mtime (epoch seconds) for a file (macOS/Linux)
# Args....: $1 - File path
# Returns.: 0 on success, 1 on failure
# Output..: Epoch seconds to stdout
# ----------------------------------------------------------------------------
_ds_cache_mtime() {
    local file="$1"

    if stat -f '%m' "$file" > /dev/null 2>&1; then
        stat -f '%m' "$file"
        return 0
    fi

    if stat -c '%Y' "$file" > /dev/null 2>&1; then
        stat -c '%Y' "$file"
        return 0
    fi

    return 1
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: is_ocid
# Purpose.: Check if string is an OCID
# Args....: $1 - String to check
# Returns.: 0 if OCID, 1 otherwise
# ------------------------------------------------------------------------------
is_ocid() {
    local str="$1"
    [[ "$str" =~ ^ocid1\. ]]
}

# ------------------------------------------------------------------------------
# Function: check_oci_cli_auth
# Purpose.: Verify OCI CLI is authenticated and working
# Args....: None
# Returns.: 0 if authenticated, 1 if not
# Output..: Error message to stderr if authentication fails
# Notes...: Uses 'oci os ns get' as a lightweight test command
#           Results are cached to avoid repeated checks
# ------------------------------------------------------------------------------
check_oci_cli_auth() {
    # Return cached result if available
    if [[ -n "$_OCI_CLI_AUTH_CHECKED" ]]; then
        [[ "$_OCI_CLI_AUTH_CHECKED" == "success" ]] && return 0 || return 1
    fi

    log_debug "Checking OCI CLI authentication..."

    # Build test command with OCI config options
    local -a cmd=(oci os ns get)
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")

    # Try to execute authentication test
    local output
    local exit_code=0

    if output=$("${cmd[@]}" 2>&1); then
        log_debug "OCI CLI authentication successful"
        _OCI_CLI_AUTH_CHECKED="success"
        return 0
    else
        exit_code=$?
        log_error "OCI CLI authentication failed (exit ${exit_code})"
        log_trace "Test command: ${cmd[*]}"
        log_trace "Error output: $output"

        # Provide helpful error messages
        if [[ "$output" =~ "ConfigFileNotFound" ]]; then
            log_error "OCI config file not found: ${OCI_CLI_CONFIG_FILE}"
            log_error "Run 'oci setup config' to create it"
        elif [[ "$output" =~ "ProfileNotFound" ]]; then
            log_error "OCI profile '${OCI_CLI_PROFILE}' not found in config"
            log_error "Available profiles: $(grep '^\[' "${OCI_CLI_CONFIG_FILE}" 2> /dev/null | tr -d '[]' | tr '\n' ' ' || echo 'none')"
        elif [[ "$output" =~ "NotAuthenticated" ]] || [[ "$output" =~ "InvalidKeyFile" ]]; then
            log_error "OCI authentication credentials are invalid or expired"
            log_error "Check your API key configuration in ${OCI_CLI_CONFIG_FILE}"
        else
            log_error "OCI CLI test command failed. Ensure proper authentication setup."
        fi

        _OCI_CLI_AUTH_CHECKED="failed"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function: require_oci_cli
# Purpose.: Check OCI CLI availability and authentication
# Args....: None
# Returns.: 0 if all checks pass, exits with error otherwise
# Notes...: Combines tool existence check and authentication test
#           This is the recommended function for scripts to use
# ------------------------------------------------------------------------------
require_oci_cli() {
    # Check if oci command exists
    require_cmd oci jq

    # Check authentication
    if ! check_oci_cli_auth; then
        die "OCI CLI is not properly authenticated. Please run 'oci setup config' or check your credentials."
    fi
}

# ------------------------------------------------------------------------------
# Function: get_root_compartment_ocid
# Purpose.: Get root compartment OCID (resolves name if needed)
# Args....: None
# Returns.: Root compartment OCID on stdout
# Notes...: Uses DS_ROOT_COMP (can be name or OCID)
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

# ------------------------------------------------------------------------------
# Function: get_connector_compartment_ocid
# Purpose.: Get connector compartment OCID (resolves name if needed)
# Args....: None
# Returns.: Connector compartment OCID on stdout
# Notes...: Uses DS_CONNECTOR_COMP (falls back to DS_ROOT_COMP)
#           Defaults to DS_ROOT_COMP if DS_CONNECTOR_COMP not set
# ------------------------------------------------------------------------------
get_connector_compartment_ocid() {
    # Return cached value if available
    if [[ -n "${_DS_CONNECTOR_COMP_OCID_CACHE:-}" ]]; then
        echo "$_DS_CONNECTOR_COMP_OCID_CACHE"
        return 0
    fi

    # Use DS_CONNECTOR_COMP if set, otherwise fall back to DS_ROOT_COMP
    local connector_comp="${DS_CONNECTOR_COMP:-${DS_ROOT_COMP:-}}"

    if [[ -z "$connector_comp" ]]; then
        log_error "Neither DS_CONNECTOR_COMP nor DS_ROOT_COMP is set"
        return 1
    fi

    # If already an OCID, use it directly
    if is_ocid "$connector_comp"; then
        log_debug "Connector compartment is already an OCID: $connector_comp"
        _DS_CONNECTOR_COMP_OCID_CACHE="$connector_comp"
        echo "$connector_comp"
        return 0
    fi

    # It's a name, resolve it
    log_debug "Resolving connector compartment name to OCID: $connector_comp"
    local resolved
    resolved=$(oci_resolve_compartment_ocid "$connector_comp") || {
        log_error "Failed to resolve connector compartment: $connector_comp"
        return 1
    }

    if [[ -z "$resolved" ]]; then
        log_error "Connector compartment not found: $connector_comp"
        return 1
    fi

    log_debug "Resolved connector compartment '$connector_comp' to OCID: $resolved"
    _DS_CONNECTOR_COMP_OCID_CACHE="$resolved"
    echo "$resolved"
    return 0
}

# =============================================================================
# OCI CLI WRAPPER
# =============================================================================

# ------------------------------------------------------------------------------
# Function: oci_exec
# Purpose.: Execute OCI CLI with standard options and error handling
# Args....: $@ - OCI command and arguments
# Returns.: 0 on success, non-zero on error
# Output..: Command output to stdout
# Notes...: Handles profile, region, config file, dry-run, and error logging
#           For read-only operations in dry-run mode, use oci_exec_ro
# ------------------------------------------------------------------------------
oci_exec() {
    # Build command with subcommand first, global options afterwards (matches user expectation)
    local -a cmd=(oci "$@")

    # Append global options after subcommand
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")

    # Log command at trace level (raw command detail belongs at trace, not debug)
    log_trace "OCI command: ${cmd[*]}"

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
        log_trace "Output: $output"
        return $exit_code
    fi
}

# ------------------------------------------------------------------------------
# Function: oci_exec_ro
# Purpose.: Execute read-only OCI CLI (always runs, even in dry-run)
# Args....: $@ - OCI command and arguments
# Returns.: 0 on success, non-zero on error
# Output..: Command output to stdout
# Notes...: Use for lookups/queries that don't modify resources
# ------------------------------------------------------------------------------
oci_exec_ro() {
    # Build command with subcommand first, global options afterwards (matches user expectation)
    local -a cmd=(oci "$@")

    # Append global options after subcommand
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")

    # Log command at trace level (raw command detail belongs at trace, not debug)
    log_trace "OCI command: ${cmd[*]}"

    # Execute command (always, even in dry-run)
    local output
    local exit_code=0

    if output=$("${cmd[@]}" 2>&1); then
        log_trace "OCI command successful"
        echo "$output"
        return 0
    else
        exit_code=$?
        log_error "OCI command failed (exit ${exit_code}): ${cmd[*]}"
        log_trace "Output: $output"
        return $exit_code
    fi
}

# ------------------------------------------------------------------------------
# Function: oci_structured_search_query
# Purpose.: Execute OCI structured search query
# Args....: $1 - query text
#           $2 - limit (optional, default: 25)
# Returns.: 0 on success, non-zero on error
# Output..: JSON result
# ------------------------------------------------------------------------------
oci_structured_search_query() {
    local query_text="$1"
    local limit="${2:-25}"

    if [[ -z "$query_text" ]]; then
        return 1
    fi

    oci_exec_ro search resource structured-search \
        --query-text "$query_text" \
        --limit "$limit"
}

# ------------------------------------------------------------------------------
# Function: oci_resolve_ocid_by_name
# Purpose.: Resolve resource OCID from display name using structured search
# Args....: $1 - kind alias (vmcluster|compartment|database|dbnode)
#           $2 - name or OCID
#           $3 - region (optional, currently ignored)
#           $4 - OCID prefix filter (optional, e.g. ocid1.vmcluster.)
# Returns.: 0
# Output..: OCID or empty string
# ------------------------------------------------------------------------------
oci_resolve_ocid_by_name() {
    local kind_in="$1"
    local name_or_id="$2"
    local _region="${3:-}"
    local prefix="${4:-}"

    [[ -n "$kind_in" && -n "$name_or_id" ]] || {
        printf '%s\n' ""
        return 0
    }

    if is_ocid "$name_or_id"; then
        printf '%s\n' "$name_or_id"
        return 0
    fi

    local kind
    case "${kind_in,,}" in
        vmcluster | vm_cluster) kind="VmCluster" ;;
        cloudvmcluster | cloud-vm-cluster) kind="CloudVmCluster" ;;
        compartment) kind="Compartment" ;;
        dbnode | db_node) kind="DbNode" ;;
        database | db) kind="Database" ;;
        *) kind="" ;;
    esac

    local esc
    esc="${name_or_id//\'/\'\\\'}"

    local out=""
    local ocid=""

    if [[ -n "$kind" ]]; then
        out=$(oci_structured_search_query "query ${kind} resources where displayName = '${esc}'" 25 2> /dev/null || true)
        ocid=$(jq -r '(.data.items // []) | map(.identifier // .id // empty) | first // empty' <<< "$out")
        [[ "$ocid" == "null" ]] && ocid=""
    fi

    if [[ -z "$ocid" ]]; then
        out=$(oci_structured_search_query "query all resources where displayName = '${esc}'" 25 2> /dev/null || true)
        ocid=$(jq -r --arg kind "$kind" '
            (.data.items // [])
            | (if ($kind == "") then . else map(select((."resource-type" // .resourceType // "") == $kind)) end)
            | map(.identifier // .id // empty)
            | first // empty
        ' <<< "$out")
        [[ "$ocid" == "null" ]] && ocid=""
    fi

    if [[ -n "$prefix" && -n "$ocid" && "$ocid" != "$prefix"* ]]; then
        ocid=""
    fi

    printf '%s\n' "${ocid:-}"
}

# ------------------------------------------------------------------------------
# Function: oci_get_compartment_of_ocid
# Purpose.: Resolve compartment OCID for a given resource OCID via search
# Args....: $1 - resource OCID
# Returns.: 0
# Output..: compartment OCID or empty string
# ------------------------------------------------------------------------------
oci_get_compartment_of_ocid() {
    local resource_ocid="$1"

    if [[ -z "$resource_ocid" ]]; then
        printf '%s\n' ""
        return 0
    fi

    local esc
    esc="${resource_ocid//\'/\'\\\'}"

    local out
    local comp_ocid
    out=$(oci_structured_search_query "query all resources where identifier = '${esc}'" 1 2> /dev/null || true)
    comp_ocid=$(jq -r '
        (.data.items // [])
        | map(."compartment-id" // .compartmentId // empty)
        | first // empty
    ' <<< "$out")
    [[ "$comp_ocid" == "null" ]] && comp_ocid=""

    printf '%s\n' "${comp_ocid:-}"
}

# ------------------------------------------------------------------------------
# Function: oci_resolve_dbnode_by_host
# Purpose.: Search for a DbNode by display name (hostname) and return raw JSON
# Args....: $1 - DbNode display name (hostname)
# Returns.: 0; raw structured-search JSON to stdout (may be empty on no result)
# Notes...: Returns at most 1 result (--limit 1). Callers extract specific fields.
#           Use oci_resolve_compartment_by_dbnode_name() for compartment lookup.
# ------------------------------------------------------------------------------
oci_resolve_dbnode_by_host() {
    local host_name="$1"
    [[ -z "$host_name" ]] && return 1
    local esc="${host_name//\'/\'\\\'}"
    oci_exec_ro search resource structured-search \
        --query-text "query DbNode resources where displayName = '${esc}'" \
        --limit 1 2> /dev/null || true
}

# ------------------------------------------------------------------------------
# Function: oci_resolve_compartment_by_dbnode_name
# Purpose.: Resolve compartment OCID from DbNode display name (hostname)
# Args....: $1 - DbNode display name (hostname)
# Returns.: 0 on success; compartment OCID to stdout
# ------------------------------------------------------------------------------
oci_resolve_compartment_by_dbnode_name() {
    local host_name="$1"
    [[ -z "$host_name" ]] && return 1
    local esc="${host_name//\'/\'\\\'}"
    local out
    out=$(oci_exec_ro search resource structured-search \
        --query-text "query DbNode resources where displayName = '${esc}'" \
        --limit 10 2> /dev/null || true)
    local resolved_comp
    resolved_comp=$(jq -r '
        (.data.items // [])
        | map(."compartment-id" // .compartmentId // empty)
        | first // empty
    ' <<< "$out")
    [[ "$resolved_comp" == "null" ]] && resolved_comp=""
    if [[ -n "$resolved_comp" ]]; then
        printf '%s\n' "$resolved_comp"
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Function: oci_resolve_vm_cluster_compartment
# Purpose.: Resolve compartment OCID from VM cluster OCID
# Args....: $1 - VM cluster OCID (vmcluster or cloudvmcluster)
# Returns.: 0 on success; compartment OCID to stdout
# Notes...: Type-dispatches by OCID prefix for direct API call; falls back to
#           generic structured search via oci_get_compartment_of_ocid().
# ------------------------------------------------------------------------------
oci_resolve_vm_cluster_compartment() {
    local vm_cluster_ocid="$1"
    [[ -z "$vm_cluster_ocid" ]] && return 1

    if [[ "$vm_cluster_ocid" =~ ^ocid1\.vmcluster\. ]]; then
        oci_exec_ro db vm-cluster get \
            --vm-cluster-id "$vm_cluster_ocid" \
            --query 'data."compartment-id"' \
            --raw-output 2> /dev/null
        return $?
    fi

    if [[ "$vm_cluster_ocid" =~ ^ocid1\.cloudvmcluster\. ]]; then
        oci_exec_ro db cloud-vm-cluster get \
            --cloud-vm-cluster-id "$vm_cluster_ocid" \
            --query 'data."compartment-id"' \
            --raw-output 2> /dev/null
        return $?
    fi

    oci_get_compartment_of_ocid "$vm_cluster_ocid"
}

# =============================================================================
# COMPARTMENT OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: oci_resolve_compartment_ocid
# Purpose.: Resolve compartment name to OCID, or validate OCID
# Args....: $1 - Compartment name or OCID
# Returns.: 0 on success, 1 on error; OCID on stdout
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
    result=$(oci_exec_ro iam compartment list \
        --all \
        --compartment-id-in-subtree true \
        --query "data[?name=='${input}'].id | [0]" \
        --raw-output)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "Compartment not found: $input"
        return 1
    fi

    log_debug "Resolved compartment: $input -> $result"
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function: oci_resolve_compartment_name
# Purpose.: Resolve compartment OCID to name
# Args....: $1 - Compartment OCID
# Returns.: Name on stdout
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

# ------------------------------------------------------------------------------
# Function: oci_get_compartment_name
# Purpose.: Get name for compartment or tenancy OCID
# Args....: $1 - Compartment or tenancy OCID
# Returns.: Name on stdout (or original OCID if resolution fails)
# Notes...: Handles both compartment and tenancy OCIDs gracefully
# ------------------------------------------------------------------------------
oci_get_compartment_name() {
    local ocid="$1"

    if ! is_ocid "$ocid"; then
        echo "$ocid"
        return 0
    fi

    # Check if it's a tenancy OCID
    if [[ "$ocid" =~ ^ocid1\.tenancy\. ]]; then
        log_debug "Resolving tenancy OCID: $ocid"
        local result
        result=$(oci_exec iam tenancy get \
            --tenancy-id "$ocid" \
            --query 'data.name' \
            --raw-output 2> /dev/null) || {
            log_debug "Failed to resolve tenancy name, using OCID"
            echo "$ocid"
            return 0
        }
        echo "$result"
    else
        # It's a compartment OCID
        oci_resolve_compartment_name "$ocid" 2> /dev/null || {
            log_debug "Failed to resolve compartment name, using OCID"
            echo "$ocid"
            return 0
        }
    fi
}

# =============================================================================
# DATA SAFE TARGET OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: ds_list_targets
# Purpose.: List Data Safe targets in compartment
# Args....: $1 - Compartment OCID or name
#           $2 - Lifecycle filter (optional, e.g., "ACTIVE,NEEDS_ATTENTION")
# Returns.: JSON array of targets
# ------------------------------------------------------------------------------
ds_list_targets() {
    local compartment="$1"
    local lifecycle_input="${2:-}"

    # Normalize lifecycle (remove spaces, uppercase) and build CLI options (supports comma-separated states)
    local lifecycle_norm=""
    local -a lifecycle_opts=()
    local -a __states=()
    local __state=""

    if [[ -n "$lifecycle_input" ]]; then
        lifecycle_norm=$(echo "$lifecycle_input" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
        IFS=',' read -ra __states <<< "$lifecycle_norm"
        for __state in "${__states[@]}"; do
            [[ -n "$__state" ]] && lifecycle_opts+=(--lifecycle-state "$__state")
        done
    fi

    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment")

    log_debug "Listing Data Safe targets in compartment: $comp_ocid (lifecycle: ${lifecycle_norm:-none})"

    # Bash 4.2 compatibility: safe array expansion with nounset
    _ds_get_target_list_cached "$comp_ocid" "$lifecycle_norm" ${lifecycle_opts[@]+"${lifecycle_opts[@]}"}
}

# ------------------------------------------------------------------------------
# Function: ds_validate_target_filter_regex
# Purpose.: Validate target-name regex syntax for jq test()
# Args....: $1 - Regex string
# Returns.: 0 if valid (or empty), 1 if invalid
# Output..: None
# ------------------------------------------------------------------------------
ds_validate_target_filter_regex() {
    local target_filter="${1:-}"

    if [[ -z "$target_filter" ]]; then
        return 0
    fi

    jq -n --arg re "$target_filter" '"probe" | test($re)' > /dev/null 2>&1
}

# ------------------------------------------------------------------------------
# Function: ds_filter_targets_json
# Purpose.: Filter target list JSON by display-name regex
# Args....: $1 - Targets JSON object with .data array
#           $2 - Regex string (optional)
# Returns.: 0 on success, 1 on jq error
# Output..: Filtered targets JSON object
# ------------------------------------------------------------------------------
ds_filter_targets_json() {
    local targets_json="$1"
    local target_filter="${2:-}"

    if [[ -z "$target_filter" ]]; then
        printf '%s' "$targets_json"
        return 0
    fi

    printf '%s' "$targets_json" | jq --arg re "$target_filter" '.data = (.data | map(select((."display-name" // "") | test($re))))'
}

# ------------------------------------------------------------------------------
# Function: ds_load_targets_json_file
# Purpose.: Load targets JSON from file and normalize to object with .data array
# Args....: $1 - input JSON file path
# Returns.: 0 on success, 1 on validation/parse error
# Output..: normalized JSON object with .data array
# ------------------------------------------------------------------------------
ds_load_targets_json_file() {
    local input_file="$1"

    if [[ -z "$input_file" ]]; then
        log_error "Input JSON file path is required"
        return 1
    fi

    if [[ ! -r "$input_file" ]]; then
        log_error "Input JSON file not found or unreadable: $input_file"
        return 1
    fi

    if ! jq -e . "$input_file" > /dev/null 2>&1; then
        log_error "Invalid JSON in file: $input_file"
        return 1
    fi

    if jq -e 'type == "array"' "$input_file" > /dev/null 2>&1; then
        jq '{data: .}' "$input_file"
        return 0
    fi

    if jq -e 'type == "object" and (.data | type == "array")' "$input_file" > /dev/null 2>&1; then
        jq '.' "$input_file"
        return 0
    fi

    log_error "Unsupported input JSON structure in $input_file. Expected array or object with .data array"
    return 1
}

# ------------------------------------------------------------------------------
# Function: ds_save_targets_json_file
# Purpose.: Save normalized targets JSON payload to output file
# Args....: $1 - JSON payload
#           $2 - output file path
# Returns.: 0 on success, 1 on write error
# Output..: writes JSON file
# ------------------------------------------------------------------------------
ds_save_targets_json_file() {
    local targets_json="$1"
    local output_file="$2"
    local output_dir=""

    if [[ -z "$output_file" ]]; then
        log_error "Output file path is required"
        return 1
    fi

    output_dir=$(dirname "$output_file")
    [[ "$output_dir" == "." ]] || mkdir -p "$output_dir"

    if ! printf '%s' "$targets_json" | jq '.' > "$output_file"; then
        log_error "Failed to write JSON payload to: $output_file"
        return 1
    fi

    log_info "Saved selected target JSON to: $output_file"
}

# ------------------------------------------------------------------------------
# Function: ds_collect_targets_source
# Purpose.: Collect targets from OCI or local input JSON with optional filtering
# Args....: $1 - compartment OCID/name (optional)
#           $2 - explicit target list (optional)
#           $3 - lifecycle filter (optional; comma-separated supported)
#           $4 - target display-name regex filter (optional)
#           $5 - input JSON file path (optional)
#           $6 - save JSON output file path (optional)
# Returns.: 0 on success, 1 on error
# Output..: JSON object with .data array
# ------------------------------------------------------------------------------
ds_collect_targets_source() {
    local compartment_input="${1:-}"
    local targets_input="${2:-}"
    local lifecycle_input="${3:-}"
    local target_filter="${4:-}"
    local input_json="${5:-}"
    local save_json="${6:-}"
    local targets_json=""

    if [[ -n "$input_json" ]]; then
        targets_json=$(ds_load_targets_json_file "$input_json") || return 1

        if [[ -n "$lifecycle_input" ]]; then
            targets_json=$(printf '%s' "$targets_json" | jq --arg states "$lifecycle_input" '
                ($states
                    | split(",")
                    | map(gsub("^\\s+|\\s+$"; ""))
                    | map(select(length > 0))) as $state_list
                | .data = (.data | map(select(
                    ((."lifecycle-state" // "") as $target_state
                        | ($state_list | length) == 0
                        or ($state_list | index($target_state) != null))
                )))
            ') || return 1
        fi

        targets_json=$(ds_filter_targets_json "$targets_json" "$target_filter") || return 1
    else
        targets_json=$(ds_collect_targets "$compartment_input" "$targets_input" "$lifecycle_input" "$target_filter") || return 1
    fi

    if [[ -n "$save_json" ]]; then
        ds_save_targets_json_file "$targets_json" "$save_json" || return 1
    fi

    printf '%s' "$targets_json"
}

# ------------------------------------------------------------------------------
# Function: _ds_file_mtime
# Purpose.: Get file modification time as epoch seconds (macOS/Linux)
# Args....: $1 - file path
# Returns.: 0 on success, 1 on error
# Output..: mtime epoch seconds
# ------------------------------------------------------------------------------
_ds_file_mtime() {
    local file_path="$1"

    if stat -f '%m' "$file_path" > /dev/null 2>&1; then
        stat -f '%m' "$file_path"
        return 0
    fi

    if stat -c '%Y' "$file_path" > /dev/null 2>&1; then
        stat -c '%Y' "$file_path"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: _ds_duration_to_seconds
# Purpose.: Convert duration string to seconds
# Args....: $1 - duration (e.g. 24h, 30m, 900, 2d)
# Returns.: 0 on success, 1 on parse error
# Output..: duration in seconds
# ------------------------------------------------------------------------------
_ds_duration_to_seconds() {
    local duration_input="$1"

    if [[ "$duration_input" =~ ^([0-9]+)([smhd]?)$ ]]; then
        local value="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            s | "") echo "$value" ;;
            m) echo $((value * 60)) ;;
            h) echo $((value * 3600)) ;;
            d) echo $((value * 86400)) ;;
            *) return 1 ;;
        esac
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: ds_validate_input_json_freshness
# Purpose.: Enforce max age safeguard for input JSON snapshots
# Args....: $1 - input JSON file path
#           $2 - max age string (e.g. 24h, 30m, 3600, 0/off/none to disable)
# Returns.: 0 if fresh/disabled, 1 if stale or invalid max-age
# Output..: log messages on failure
# ------------------------------------------------------------------------------
ds_validate_input_json_freshness() {
    local input_file="$1"
    local max_age_input="${2:-24h}"
    local now=""
    local file_mtime=""
    local max_age_seconds=""
    local snapshot_age=""

    case "${max_age_input,,}" in
        "" | 0 | off | none)
            return 0
            ;;
    esac

    max_age_seconds=$(_ds_duration_to_seconds "$max_age_input") || {
        log_error "Invalid --max-snapshot-age value: $max_age_input (use 900, 30m, 24h, 2d, or off)"
        return 1
    }

    now=$(date +%s)
    file_mtime=$(_ds_file_mtime "$input_file") || {
        log_error "Cannot read mtime for input JSON: $input_file"
        return 1
    }

    snapshot_age=$((now - file_mtime))

    if ((snapshot_age > max_age_seconds)); then
        log_error "Input JSON snapshot is too old (${snapshot_age}s > ${max_age_seconds}s): $input_file"
        log_error "Use a newer snapshot, increase --max-snapshot-age, or set --max-snapshot-age off"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: ds_collect_targets
# Purpose.: Collect targets via explicit list or compartment+lifecycle filters
# Args....: $1 - Compartment OCID/name (optional)
#           $2 - Comma-separated targets (names or OCIDs, optional)
#           $3 - Lifecycle filter (optional)
#           $4 - Target name regex filter (optional)
# Returns.: 0 on success, 1 on error
# Output..: JSON object with .data array of target objects
# Notes...: Explicit target mode resolves names to OCIDs and fetches full target
#           objects; compartment mode uses ds_list_targets.
# ------------------------------------------------------------------------------
ds_collect_targets() {
    local compartment_input="${1:-}"
    local targets_input="${2:-}"
    local lifecycle_input="${3:-}"
    local target_filter="${4:-}"
    local targets_json=""

    if ! ds_validate_target_filter_regex "$target_filter"; then
        log_error "Invalid filter regex: $target_filter"
        return 1
    fi

    if [[ -n "$targets_input" ]]; then
        local -a target_list=()
        local -a target_objects=()
        local valid_target_count=0
        local target=""
        local target_ocid=""
        local target_data=""
        local lookup_compartment=""

        IFS=',' read -ra target_list <<< "$targets_input"

        for target in "${target_list[@]}"; do
            target="${target#"${target%%[![:space:]]*}"}"
            target="${target%"${target##*[![:space:]]}"}"
            [[ -z "$target" ]] && continue
            valid_target_count=$((valid_target_count + 1))

            if is_ocid "$target"; then
                target_ocid="$target"
            else
                if [[ -z "$lookup_compartment" ]]; then
                    lookup_compartment=$(resolve_compartment_for_operation "$compartment_input") || return 1
                fi
                target_ocid=$(ds_resolve_target_ocid "$target" "$lookup_compartment") || return 1
            fi

            target_data=$(ds_get_target "$target_ocid" | jq -c '.data') || return 1
            target_objects+=("$target_data")
        done

        if [[ $valid_target_count -eq 0 ]]; then
            log_error "No valid targets specified in explicit target list"
            return 1
        fi

        # Bash 4.2 compatibility: safe array length check with nounset
        # Array is initialized above, but double-check for safety
        # shellcheck disable=SC2128  # Intentional array concatenation for existence check
        if [[ -n "${target_objects[*]+x}" ]] && [[ ${#target_objects[@]} -gt 0 ]]; then
            targets_json=$(printf '%s\n' "${target_objects[@]}" | jq -s '{data: .}') || return 1
        else
            targets_json='{"data":[]}'
        fi
    else
        local resolved_compartment=""
        resolved_compartment=$(resolve_compartment_for_operation "$compartment_input") || return 1
        targets_json=$(ds_list_targets "$resolved_compartment" "$lifecycle_input") || return 1
    fi

    ds_filter_targets_json "$targets_json" "$target_filter"
}

# ------------------------------------------------------------------------------
# Function: ds_get_target
# Purpose.: Get details for a single Data Safe target
# Args....: $1 - Target OCID
# Returns.: JSON object with target details
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

# ----------------------------------------------------------------------------
# Function: _ds_get_target_list_cached
# Purpose.: Fetch target list with caching per compartment+lifecycle
# Args....: $1 - Compartment OCID
#           $2 - Lifecycle filter (optional)
# Returns.: JSON of target list to stdout
# Notes...: Internal helper used by ds_list_targets and ds_resolve_target_ocid
# ----------------------------------------------------------------------------
_ds_get_target_list_cached() {
    local comp_ocid="$1"
    local lifecycle="$2"
    shift 2
    local -a lifecycle_opts=("$@")

    local cache_file
    cache_file=$(_ds_target_cache_file_path "$comp_ocid" "$lifecycle")

    # Reuse cache if compartment and lifecycle match and cache enabled
    if [[ "${DS_TARGET_CACHE_TTL}" != "0" && -n "$_DS_TARGET_CACHE_JSON" &&
        "$_DS_TARGET_CACHE_COMP_OCID" == "$comp_ocid" &&
        "$_DS_TARGET_CACHE_LIFECYCLE" == "$lifecycle" ]]; then
        log_debug "Using cached target list for compartment: $comp_ocid (lifecycle: ${lifecycle:-none}) [memory]"
        printf '%s' "$_DS_TARGET_CACHE_JSON"
        return 0
    fi

    if [[ "${DS_TARGET_CACHE_TTL}" != "0" && -f "$cache_file" ]]; then
        local now cache_mtime cache_age
        now=$(date +%s)
        if cache_mtime=$(_ds_cache_mtime "$cache_file"); then
            cache_age=$((now - cache_mtime))
            if [[ $cache_age -le $DS_TARGET_CACHE_TTL ]]; then
                log_debug "Using cached target list for compartment: $comp_ocid (lifecycle: ${lifecycle:-none}) [file] age=${cache_age}s"
                _DS_TARGET_CACHE_COMP_OCID="$comp_ocid"
                _DS_TARGET_CACHE_LIFECYCLE="$lifecycle"
                _DS_TARGET_CACHE_FILE="$cache_file"
                _DS_TARGET_CACHE_JSON=$(cat "$cache_file")
                printf '%s' "$_DS_TARGET_CACHE_JSON"
                return 0
            fi
        fi
    fi

    log_debug "Fetching target list for compartment: $comp_ocid (lifecycle: ${lifecycle:-none})"

    local -a cmd=(
        data-safe target-database list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )

    # Bash 4.2 compatibility: safe array length check with nounset
    # Use ${array[*]+x} to test if array is set and non-empty
    # shellcheck disable=SC2128  # Intentional array concatenation for existence check
    if [[ -n "${lifecycle_opts[*]+x}" ]] && [[ ${#lifecycle_opts[@]} -gt 0 ]]; then
        cmd+=("${lifecycle_opts[@]}")
    fi

    local targets_json
    if ! targets_json=$(oci_exec_ro "${cmd[@]}"); then
        log_error "Failed to list targets for compartment: $comp_ocid"
        return 1
    fi

    _DS_TARGET_CACHE_COMP_OCID="$comp_ocid"
    _DS_TARGET_CACHE_LIFECYCLE="$lifecycle"
    _DS_TARGET_CACHE_FILE="$cache_file"
    _DS_TARGET_CACHE_JSON="$targets_json"

    printf '%s' "$targets_json" > "$cache_file"
    printf '%s' "$targets_json"
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_target_ocid
# Purpose.: Resolve target name to OCID
# Args....: $1 - Target name or OCID
#           $2 - Compartment OCID or name (optional, for name resolution)
# Returns.: 0 on success, 1 on error; OCID on stdout
# ------------------------------------------------------------------------------
ds_resolve_target_ocid() {
    local input="$1"
    local compartment="${2:-}"

    # Already an OCID?
    if is_ocid "$input"; then
        echo "$input"
        return 0
    fi

    # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
    if [[ -z "$compartment" ]]; then
        compartment=$(resolve_compartment_for_operation "") || return 1
    else
        compartment=$(oci_resolve_compartment_ocid "$compartment") || return 1
    fi

    log_debug "Resolving target name: $input (compartment: $compartment)"

    # Retrieve targets JSON once per compartment (and lifecycle) and cache to reduce repeated large downloads
    # Populate cache (suppress stdout to avoid polluting command substitution in callers)
    if ! _ds_get_target_list_cached "$compartment" "" > /dev/null; then
        log_error "Failed to list targets for resolution: $input"
        return 1
    fi

    local targets_json
    if [[ -n "$_DS_TARGET_CACHE_JSON" ]]; then
        targets_json="$_DS_TARGET_CACHE_JSON"
    elif [[ -n "$_DS_TARGET_CACHE_FILE" && -f "$_DS_TARGET_CACHE_FILE" ]]; then
        targets_json=$(cat "$_DS_TARGET_CACHE_FILE")
    else
        log_error "Target cache unavailable after fetch for: $input"
        return 1
    fi

    # First try case-sensitive exact match, then case-insensitive
    local result
    result=$(echo "$targets_json" | jq -r --arg name "$input" '
        .data[] | select(."display-name" == $name) | .id' | head -n1)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_debug "Exact match not found for target: $input (case-sensitive). Trying case-insensitive match."

        result=$(echo "$targets_json" | jq -r --arg name "$input" '
            .data[] | select((."display-name" | ascii_downcase) == ($name | ascii_downcase)) | .id' | head -n1)
    fi

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_debug "No exact match found for target: $input. Trying partial (substring) match."

        local matches
        matches=$(echo "$targets_json" | jq -r --arg name "$input" '
            .data[] | select((."display-name" | ascii_downcase) | contains($name | ascii_downcase)) | ."display-name" + "|" + .id')

        if [[ -z "$matches" ]]; then
            log_error "Target not found: $input"
            return 1
        fi

        # If exactly one partial match, use it; otherwise ask to disambiguate
        local match_count
        match_count=$(echo "$matches" | wc -l | tr -d ' ')

        if [[ "$match_count" -eq 1 ]]; then
            result=$(echo "$matches" | cut -d'|' -f2)
            log_info "Target '$input' not found by exact name; using partial match: $(echo "$matches" | cut -d'|' -f1)"
        else
            log_error "Target not found or ambiguous: $input"
            log_error "Candidates (partial match):"
            echo "$matches" | while IFS='|' read -r disp ocid; do
                log_error "  ${disp} -> ${ocid}"
            done
            return 1
        fi
    fi

    log_debug "Resolved target: $input -> $result"
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_target_name
# Purpose.: Resolve target OCID to name
# Args....: $1 - Target OCID
# Returns.: 0 on success (name on stdout), 1 on error (message on stderr)
# ------------------------------------------------------------------------------
ds_resolve_target_name() {
    local ocid="$1"

    if ! is_ocid "$ocid"; then
        log_error "Invalid target OCID: $ocid" >&2
        return 1
    fi

    log_debug "Resolving target OCID: $ocid"

    local result
    result=$(oci_exec data-safe target-database get \
        --target-database-id "$ocid" \
        --query 'data."display-name"' \
        --raw-output 2> /dev/null)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "Target not found: $ocid" >&2
        return 1
    fi

    echo "$result"
    return 0
}

# ------------------------------------------------------------------------------
# Function: ds_get_target_compartment
# Purpose.: Get compartment OCID for a target
# Args....: $1 - Target OCID
# Returns.: Compartment OCID on stdout
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

# ------------------------------------------------------------------------------
# Function: ds_is_updatable_lifecycle_state
# Purpose.: Check whether a target lifecycle state supports credential/config updates
# Args....: $1 - Lifecycle state string
# Returns.: 0 if updatable (ACTIVE or NEEDS_ATTENTION), 1 otherwise
# Output..: None
# ------------------------------------------------------------------------------
ds_is_updatable_lifecycle_state() {
    local lifecycle_state="$1"
    case "$lifecycle_state" in
        ACTIVE | NEEDS_ATTENTION) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: ds_is_cdb_root_target
# Purpose.: Detect if a Data Safe target represents a CDB$ROOT scope
# Args....: $1 - Target display name
#           $2 - Target OCID
# Returns.: 0 if CDB$ROOT, 1 if PDB or unknown
# Notes...: Checks name pattern first (fast), then freeform tag (slower OCI call)
# ------------------------------------------------------------------------------
ds_is_cdb_root_target() {
    local target_name="$1"
    local target_ocid="$2"

    # Fast path: name ends with _CDBROOT
    if [[ "$target_name" =~ _CDBROOT$ ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (name pattern)"
        return 0
    fi

    # Slow path: check freeform tag DBSec.Container
    log_debug "Checking tags for CDB\$ROOT detection: $target_name"
    local target_json
    target_json=$(oci_exec_ro data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data' 2> /dev/null) || {
        log_debug "Failed to get target details for tag check"
        return 1
    }
    local container_tag
    container_tag=$(printf '%s' "$target_json" | jq -r '."freeform-tags"."DBSec.Container" // ""')
    if [[ "${container_tag^^}" == "CDBROOT" ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (tag DBSec.Container)"
        return 0
    fi

    # Also check DBSec.ContainerType tag (alternate tagging convention)
    local container_type_tag
    container_type_tag=$(printf '%s' "$target_json" | jq -r '."freeform-tags"."DBSec.ContainerType" // ""')
    if [[ "${container_type_tag^^}" == "CDBROOT" ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (tag DBSec.ContainerType)"
        return 0
    fi

    log_debug "Target '$target_name' identified as PDB (default)"
    return 1
}

# =============================================================================
# COMMON RESOLUTION HELPERS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: resolve_compartment_to_vars
# Purpose.: Resolve compartment (name or OCID) to both NAME and OCID variables
# Args....: $1 - Compartment name or OCID
#           $2 - Variable name prefix (e.g., "COMPARTMENT" for COMPARTMENT_NAME/COMPARTMENT_OCID)
# Returns.: 0 on success, 1 on error
# Output..: Sets ${prefix}_NAME and ${prefix}_OCID global variables
# Notes...: Use with eval or declare -g in calling function
# ------------------------------------------------------------------------------
resolve_compartment_to_vars() {
    local input="$1"
    local prefix="$2"

    if is_ocid "$input"; then
        # User provided OCID, resolve to name
        local resolved_comp_name
        resolved_comp_name=$(oci_get_compartment_name "$input" 2> /dev/null) || resolved_comp_name="$input"
        eval "${prefix}_OCID=\"$input\""
        eval "${prefix}_NAME=\"$resolved_comp_name\""
        log_debug "Resolved compartment OCID to name: $resolved_comp_name"
    else
        # User provided name, resolve to OCID
        local comp_ocid
        comp_ocid=$(oci_resolve_compartment_ocid "$input") || {
            log_error "Cannot resolve compartment name '$input' to OCID"
            return 1
        }
        eval "${prefix}_NAME=\"$input\""
        eval "${prefix}_OCID=\"$comp_ocid\""
        log_debug "Resolved compartment name to OCID: $comp_ocid"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: resolve_target_to_vars
# Purpose.: Resolve target (name or OCID) to both name and OCID variables
# Args....: $1 - Target name or OCID
#           $2 - Variable name prefix (e.g., "TARGET" for TARGET_NAME/TARGET_OCID)
#           $3 - Compartment OCID for name resolution (optional if input is OCID)
# Returns.: 0 on success, 1 on error
# Output..: Sets ${prefix}_NAME and ${prefix}_OCID global variables
# ------------------------------------------------------------------------------
resolve_target_to_vars() {
    local input="$1"
    local prefix="$2"
    local compartment="${3:-}"

    if is_ocid "$input"; then
        # User provided OCID, resolve to name
        local target_name
        target_name=$(ds_resolve_target_name "$input" 2> /dev/null) || target_name="$input"
        eval "${prefix}_OCID=\"$input\""
        eval "${prefix}_NAME=\"$target_name\""
        log_debug "Resolved target OCID to name: $target_name"
    else
        # User provided name, need compartment to resolve
        if [[ -z "$compartment" ]]; then
            log_error "Compartment required to resolve target name: $input"
            return 1
        fi

        local target_ocid
        target_ocid=$(ds_resolve_target_ocid "$input" "$compartment") || {
            log_error "Cannot resolve target name '$input' to OCID"
            return 1
        }
        eval "${prefix}_NAME=\"$input\""
        eval "${prefix}_OCID=\"$target_ocid\""
        log_debug "Resolved target name to OCID: $target_ocid"
    fi

    return 0
}

# =============================================================================
# DATA SAFE TARGET MODIFICATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: ds_refresh_target
# Purpose.: Refresh a Data Safe target
# Args....: $1 - Target OCID
# Returns.: 0 on success, 2 when refresh is already in progress (skip), non-zero on error
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
    local -a refresh_cmd=(oci data-safe target-database refresh --target-database-id "$target_ocid")

    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        refresh_cmd+=(--wait-for-state SUCCEEDED --wait-for-state FAILED)
        log_info "[$current/$total] Refreshing: $target_name (waiting for completion...)"
    else
        log_info "[$current/$total] Refreshing: $target_name (async)"
    fi

    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && refresh_cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && refresh_cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && refresh_cmd+=(--region "${OCI_CLI_REGION}")

    log_trace "OCI command: ${refresh_cmd[*]}"

    local output=""
    local exit_code=0
    local output_lc=""
    if output=$("${refresh_cmd[@]}" 2>&1); then
        exit_code=0
    else
        exit_code=$?
        output_lc=$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')
        if [[ "$output_lc" == *"conflict"* ]] && [[ "$output_lc" == *"already in progress"* ]]; then
            log_warn "[$current/$total] Skipping refresh for $target_name: operation already in progress"
            return 2
        fi
        log_error "OCI command failed (exit ${exit_code}): ${refresh_cmd[*]}"
        log_trace "Output: $output"
    fi

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
# Function: ds_update_target_tags
# Purpose.: Update freeform and/or defined tags on a target
# Args....: $1 - Target OCID
#           $2 - Freeform tags JSON (optional)
#           $3 - Defined tags JSON (optional)
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
        [[ -n "$freeform_tags" ]] && log_trace "Freeform tags: $freeform_tags"
        [[ -n "$defined_tags" ]] && log_trace "Defined tags: $defined_tags"
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
# Function: ds_update_target_service
# Purpose.: Update service name for a target
# Args....: $1 - Target OCID
#           $2 - New service name
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
# Function: ds_delete_target
# Purpose.: Delete a Data Safe target
# Args....: $1 - Target OCID
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
# Function: ds_count_by_lifecycle
# Purpose.: Count targets by lifecycle state
# Args....: $1 - Targets JSON (from ds_list_targets)
# Returns.: Summary string
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

# ------------------------------------------------------------------------------
# Function: resolve_compartment_for_operation
# Purpose.: Resolve compartment for target operations following standard pattern:
#           - If compartment param provided: use it
#           - Else if DS_ROOT_COMP set: use it
#           - Else error
# Args....: $1 - compartment (can be name or OCID, can be empty)
# Returns.: 0 on success (sets resolved compartment OCID), 1 on error
# Output..: Resolved OCID to stdout
# Notes...: Follows pattern: -c flag overrides DS_ROOT_COMP
# ------------------------------------------------------------------------------
resolve_compartment_for_operation() {
    local compartment="${1:-}"

    if [[ -n "$compartment" ]]; then
        # Explicit compartment provided: resolve and use it
        oci_resolve_compartment_ocid "$compartment" || return 1
    elif [[ -n "${DS_ROOT_COMP:-}" ]]; then
        # Use DS_ROOT_COMP as fallback (resolve name to OCID if needed)
        oci_resolve_compartment_ocid "$DS_ROOT_COMP" || return 1
    else
        # Neither provided: error
        log_error "Compartment required. Use -c/--compartment or set DS_ROOT_COMP environment variable"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_all_targets_scope
# Purpose.: Resolve all-target selection scope from DS_ROOT_COMP
# Args....: $1 - select_all flag (true/false)
#           $2 - compartment input (optional)
#           $3 - targets input (optional)
# Returns.: 0 on success, 1 on invalid option combination or missing DS_ROOT_COMP
# Output..: Effective compartment value to stdout
# Notes...: --all is mutually exclusive with explicit --compartment and --targets
# ------------------------------------------------------------------------------
ds_resolve_all_targets_scope() {
    local select_all="${1:-false}"
    local compartment_input="${2:-}"
    local targets_input="${3:-}"

    if [[ "$select_all" != "true" ]]; then
        printf '%s' "$compartment_input"
        return 0
    fi

    if [[ -n "$targets_input" ]]; then
        log_error "--all cannot be combined with -T/--targets"
        return 1
    fi

    if [[ -n "$compartment_input" ]]; then
        log_error "--all cannot be combined with -c/--compartment"
        return 1
    fi

    if [[ -z "${DS_ROOT_COMP:-}" ]]; then
        log_error "DS_ROOT_COMP must be set when using --all"
        return 1
    fi

    printf '%s' "$DS_ROOT_COMP"
}

# =============================================================================
# ON-PREMISES CONNECTOR OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: ds_list_connectors
# Purpose.: List all on-premises connectors in a compartment
# Args....: $1 - Compartment OCID
# Returns.: 0 on success, connector list JSON on stdout
# ------------------------------------------------------------------------------
ds_list_connectors() {
    local compartment_ocid="$1"

    if ! is_ocid "$compartment_ocid"; then
        die "Invalid compartment OCID: $compartment_ocid"
    fi

    log_debug "Listing connectors in compartment: $compartment_ocid"

    oci_exec_ro data-safe on-prem-connector list \
        --compartment-id "$compartment_ocid" \
        --all
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_connector_ocid
# Purpose.: Resolve connector name to OCID
# Args....: $1 - Connector name or OCID
#           $2 - Compartment OCID (required if $1 is a name)
# Returns.: 0 on success (OCID on stdout), 1 on error
# ------------------------------------------------------------------------------
ds_resolve_connector_ocid() {
    local input="$1"
    local compartment="${2:-}"

    # If already an OCID, return it
    if is_ocid "$input"; then
        log_debug "Input is already a connector OCID: $input"
        echo "$input"
        return 0
    fi

    # It's a name, need compartment to resolve
    if [[ -z "$compartment" ]]; then
        log_error "Compartment required to resolve connector name: $input"
        return 1
    fi

    log_debug "Resolving connector name: $input"

    # List connectors and find by display-name
    local connectors_json
    connectors_json=$(ds_list_connectors "$compartment") || {
        log_error "Failed to list connectors"
        return 1
    }

    # Try exact match first (case-sensitive)
    local result
    result=$(echo "$connectors_json" | jq -r --arg name "$input" '
        .data[] | select(."display-name" == $name) | .id' | head -n1)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_info "Exact match not found for connector: $input. Trying case-insensitive match."

        result=$(echo "$connectors_json" | jq -r --arg name "$input" '
            .data[] | select((."display-name" | ascii_downcase) == ($name | ascii_downcase)) | .id' | head -n1)
    fi

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "Connector not found: $input"
        return 1
    fi

    log_debug "Resolved connector: $input -> $result"
    echo "$result"
    return 0
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_connector_name
# Purpose.: Resolve connector OCID to name
# Args....: $1 - Connector OCID
# Returns.: 0 on success (name on stdout), 1 on error
# ------------------------------------------------------------------------------
ds_resolve_connector_name() {
    local ocid="$1"

    if ! is_ocid "$ocid"; then
        log_error "Invalid connector OCID: $ocid"
        return 1
    fi

    log_debug "Resolving connector OCID to name: $ocid"

    local result
    result=$(oci_exec_ro data-safe on-prem-connector get \
        --on-prem-connector-id "$ocid" \
        --query 'data."display-name"' \
        --raw-output 2> /dev/null)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "Connector not found: $ocid"
        return 1
    fi

    echo "$result"
    return 0
}

# ------------------------------------------------------------------------------
# Function: ds_get_connector_details
# Purpose.: Get connector details
# Args....: $1 - Connector OCID
# Returns.: 0 on success, connector details JSON on stdout
# ------------------------------------------------------------------------------
ds_get_connector_details() {
    local connector_ocid="$1"

    if ! is_ocid "$connector_ocid"; then
        die "Invalid connector OCID: $connector_ocid"
    fi

    log_debug "Getting connector details: $connector_ocid"

    oci_exec_ro data-safe on-prem-connector get \
        --on-prem-connector-id "$connector_ocid"
}

# ------------------------------------------------------------------------------
# Function: ds_build_connector_map
# Purpose.: Populate caller's CONNECTOR_MAP associative array (ocid -> name)
# Args....: $1 - Compartment OCID
#           $2 - Include subtree (true|false, default: false)
# Returns.: 0 on success (partial results on OCI failure)
# Output..: Fills CONNECTOR_MAP in calling scope; logs count
# Notes...: CONNECTOR_MAP must be declared as associative array by caller
# ------------------------------------------------------------------------------
ds_build_connector_map() {
    local compartment_ocid="$1"
    local use_subtree="${2:-false}"

    log_debug "Building connector map for compartment"
    local args=(data-safe on-prem-connector list --compartment-id "$compartment_ocid" --all)
    [[ "$use_subtree" == "true" ]] && args+=(--compartment-id-in-subtree true)

    local connectors_json
    connectors_json=$(oci_exec_ro "${args[@]}") || {
        log_warn "Failed to list on-prem connectors; connector names may show as OCIDs"
        return 0
    }
    while IFS=$'\t' read -r ocid name; do
        [[ -n "$ocid" ]] && CONNECTOR_MAP["$ocid"]="${name:-Unknown}"
    done < <(printf '%s' "$connectors_json" | jq -r '.data[]? | [.id, (."display-name" // "")] | @tsv')
    log_debug "Loaded ${#CONNECTOR_MAP[@]} connectors"
}

# ------------------------------------------------------------------------------
# Function: ds_write_cred_json_file
# Purpose.: Write a Data Safe credential JSON file (userName + password)
# Args....: $1 - Output file path
#           $2 - Username
#           $3 - Password
# Returns.: 0 on success, 1 on jq error
# Output..: Writes JSON to $1
# ------------------------------------------------------------------------------
ds_write_cred_json_file() {
    local output_path="$1"
    local user_name="$2"
    local password="$3"
    jq -n --arg user "$user_name" --arg pass "$password" \
        '{userName: $user, password: $pass}' > "$output_path"
}

# ------------------------------------------------------------------------------
# Function: ds_resolve_user_for_scope
# Purpose.: Resolve Data Safe username for PDB or ROOT (CDB) scope
# Args....: $1 - Scope: "PDB" or "ROOT"
#           $2 - Base username (e.g. DS_USER or DATASAFE_USER)
#           $3 - Common user prefix (e.g. "C##", optional)
# Returns.: 0 on success
# Output..: Resolved username to stdout
# Notes...: ROOT scope prepends prefix; PDB scope strips prefix if present
# ------------------------------------------------------------------------------
ds_resolve_user_for_scope() {
    local scope="$1"
    local base_user="$2"
    local prefix="${3:-}"

    # Strip prefix from base user if present
    [[ -n "$prefix" && "$base_user" == ${prefix}* ]] && base_user="${base_user#${prefix}}"

    if [[ "$scope" == "ROOT" && -n "$prefix" ]]; then
        printf '%s' "${prefix}${base_user}"
        return 0
    fi
    printf '%s' "$base_user"
}

# ------------------------------------------------------------------------------
# Function: ds_generate_connector_bundle
# Purpose.: Generate on-premises connector installation bundle
# Args....: $1 - Connector OCID
#           $2 - Bundle password
#           $3 - Output file path for generated connector configuration
# Returns.: 0 on success, 1 on error
# Output..: Work request details JSON
# Notes...: This operation is asynchronous. The bundle generation happens
#           via a work request. Use ds_wait_for_work_request to monitor.
# ------------------------------------------------------------------------------
ds_generate_connector_bundle() {
    local connector_ocid="$1"
    local password="$2"
    local output_file="${3:-}"

    if ! is_ocid "$connector_ocid"; then
        die "Invalid connector OCID: $connector_ocid"
    fi

    if [[ -z "$password" ]]; then
        die "Bundle password is required"
    fi

    if [[ -z "$output_file" ]]; then
        die "Output file path is required for bundle generation"
    fi

    local connector_name
    connector_name=$(ds_resolve_connector_name "$connector_ocid" 2> /dev/null) || connector_name="$connector_ocid"

    log_info "Generating connector installation bundle for: $connector_name"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would generate bundle for: $connector_name"
        return 0
    fi

    # Generate bundle - returns work request
    oci_exec data-safe on-prem-connector generate-on-prem-connector-configuration \
        --on-prem-connector-id "$connector_ocid" \
        --password "$password" \
        --file "$output_file"
}

# ------------------------------------------------------------------------------
# Function: ds_download_connector_bundle
# Purpose.: Download connector installation bundle to file
# Args....: $1 - Connector OCID
#           $2 - Output file path
# Returns.: 0 on success, 1 on error
# Notes...: Downloads the pre-generated connector bundle. Run
#           ds_generate_connector_bundle first.
# ------------------------------------------------------------------------------
ds_download_connector_bundle() {
    local connector_ocid="$1"
    local output_file="$2"

    if ! is_ocid "$connector_ocid"; then
        die "Invalid connector OCID: $connector_ocid"
    fi

    if [[ -z "$output_file" ]]; then
        die "Output file path is required"
    fi

    local connector_name
    connector_name=$(ds_resolve_connector_name "$connector_ocid" 2> /dev/null) || connector_name="$connector_ocid"

    log_info "Downloading connector bundle for: $connector_name"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would download bundle to: $output_file"
        return 0
    fi

    # Download bundle
    oci_exec data-safe on-prem-connector download \
        --on-prem-connector-id "$connector_ocid" \
        --file "$output_file"
}
