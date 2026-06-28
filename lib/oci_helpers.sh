#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: oci_helpers.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.02
# Version....: v0.19.1
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

# In-memory cache for compartment name/OCID resolution (PERF-003)
declare -A _COMP_OCID_CACHE

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


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================


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

    log_debug "OCI CLI config: file=${OCI_CLI_CONFIG_FILE} profile=${OCI_CLI_PROFILE}${OCI_CLI_REGION:+ region=${OCI_CLI_REGION}}"
    log_debug "Data Safe config: ${_DATASAFE_CONF_FILES:-(none loaded)}"
    log_debug "DS_ROOT_COMP: ${DS_ROOT_COMP:-(not set)}"
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
# Function: _oci_redact_cmd
# Purpose.: Return a shell-quoted command string with sensitive flag values masked
# Args....: $@ - command array elements (same as passed to oci_exec / oci_exec_ro)
# Returns.: Quoted string safe for log output; values after --password are ****
# Output..: Single string to stdout
# Notes...: Only --password is masked; extend the list below for other secrets
# ------------------------------------------------------------------------------
_oci_redact_cmd() {
    local -a _redacted=()
    local prev=""
    for arg in "$@"; do
        case "$prev" in
            --password | --credentials | --secret | --auth-token) _redacted+=("****") ;;
            *) _redacted+=("$arg") ;;
        esac
        prev="$arg"
    done
    printf '%q ' "${_redacted[@]}"
}

# ------------------------------------------------------------------------------
# Function: _oci_run_capture
# Purpose.: Run an OCI CLI invocation with stdout and stderr captured into
#           independent streams. Echoes stdout for the caller and logs stderr
#           (with the redacted command) only on failure or at trace level.
# Args....: $1 - Redacted command label (for log messages)
#           $@ - Full command and arguments (oci ...)
# Returns.: OCI CLI exit code
# Notes...: Never merge stderr with stdout via 2>&1 - the OCI CLI emits
#           Python warnings (urllib3 FutureWarning, deprecation notices,
#           file-permission warnings) on stderr and they would otherwise
#           contaminate JSON/OCID payloads parsed by callers.
# ------------------------------------------------------------------------------
_oci_run_capture() {
    local redacted="$1"
    shift

    local stderr_file
    stderr_file=$(mktemp 2> /dev/null) || {
        log_error "Failed to allocate temp file for OCI stderr capture"
        return 1
    }

    local stdout exit_code=0
    stdout=$("$@" 2> "$stderr_file") || exit_code=$?

    local stderr=""
    [[ -s "$stderr_file" ]] && stderr=$(< "$stderr_file")
    rm -f "$stderr_file"

    if [[ $exit_code -eq 0 ]]; then
        log_trace "OCI command successful"
        [[ -n "$stderr" ]] && log_trace "OCI stderr (non-fatal): $stderr"
        # `$()` already strips trailing newlines from $stdout; `echo` restores
        # the single terminating newline that callers (and the original
        # implementation) expect.
        echo "$stdout"
        return 0
    fi

    log_error "OCI command failed (exit ${exit_code}): ${redacted}"
    [[ -n "$stdout" ]] && log_trace "OCI stdout: $stdout"
    [[ -n "$stderr" ]] && log_trace "OCI stderr: $stderr"
    return "$exit_code"
}

# ------------------------------------------------------------------------------
# Function: oci_exec
# Purpose.: Execute OCI CLI with standard options and error handling
# Args....: $@ - OCI command and arguments
# Returns.: 0 on success, non-zero on error
# Output..: Command output to stdout
# Notes...: Handles profile, region, config file, dry-run, and error logging.
#           stderr is captured separately so Python warnings emitted by the
#           OCI CLI never bleed into the data stream returned to the caller.
#           For read-only operations in dry-run mode, use oci_exec_ro.
# ------------------------------------------------------------------------------
oci_exec() {
    # Build command with subcommand first, global options afterwards (matches user expectation)
    local -a cmd=(oci "$@")

    # Append global options after subcommand
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")

    # Log command at trace level (raw command detail belongs at trace, not debug)
    local redacted
    redacted=$(_oci_redact_cmd "${cmd[@]}")
    log_trace "OCI command: ${redacted}"

    # Dry-run: just show command
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: ${redacted}"
        return 0
    fi

    _oci_run_capture "${redacted}" "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function: oci_exec_ro
# Purpose.: Execute read-only OCI CLI (always runs, even in dry-run)
# Args....: $@ - OCI command and arguments
# Returns.: 0 on success, non-zero on error
# Output..: Command output to stdout
# Notes...: Use for lookups/queries that don't modify resources. stderr is
#           captured separately (see oci_exec for rationale).
# ------------------------------------------------------------------------------
oci_exec_ro() {
    # Build command with subcommand first, global options afterwards (matches user expectation)
    local -a cmd=(oci "$@")

    # Append global options after subcommand
    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && cmd+=(--region "${OCI_CLI_REGION}")

    # Log command at trace level (raw command detail belongs at trace, not debug)
    local redacted
    redacted=$(_oci_redact_cmd "${cmd[@]}")
    log_trace "OCI command: ${redacted}"

    # Execute command (always, even in dry-run)
    _oci_run_capture "${redacted}" "${cmd[@]}"
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
# Function: oci_resolve_vmcluster_by_name
# Purpose.: Resolve VM cluster display name to OCID + compartment-id in a single
#           structured-search call. Tries VmCluster then CloudVmCluster.
# Args....: $1 - cluster display name
# Returns.: 0 if found, 1 if not found; JSON {"id":"...","compartment-id":"..."} on stdout
# Notes...: Prefer this over a two-step name→OCID + OCID→compartment lookup to
#           avoid the extra OCI API round-trip. The structured-search response
#           already contains both .identifier (OCID) and ."compartment-id".
# ------------------------------------------------------------------------------
oci_resolve_vmcluster_by_name() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    local esc="${name//\'/\'\\\'}"

    local rtype out ocid comp
    for rtype in VmCluster CloudVmCluster; do
        log_debug "Structured search: query ${rtype} displayName='${name}'"
        out=$(oci_exec_ro search resource structured-search \
            --query-text "query ${rtype} resources where displayName = '${esc}'" \
            --limit 10 2> /dev/null || true)
        [[ -z "$out" ]] && continue

        ocid=$(jq -r '(.data.items // []) | map(.identifier // .id // empty) | first // empty' \
            <<< "$out" 2> /dev/null || true)
        [[ -z "$ocid" || "$ocid" == "null" ]] && continue

        comp=$(jq -r '(.data.items // []) | map(."compartment-id" // .compartmentId // empty) | first // empty' \
            <<< "$out" 2> /dev/null || true)
        [[ "$comp" == "null" ]] && comp=""

        log_debug "Resolved ${rtype} '${name}': ocid=${ocid} compartment=${comp:-n/a}"
        printf '{"id":"%s","compartment-id":"%s"}\n' "$ocid" "${comp:-}"
        return 0
    done
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

    # Return cached value if available
    if [[ -n "${_COMP_OCID_CACHE[$input]+_}" ]]; then
        echo "${_COMP_OCID_CACHE[$input]}"
        return 0
    fi

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
    _COMP_OCID_CACHE["$input"]="$result"
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

