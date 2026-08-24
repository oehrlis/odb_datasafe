#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: ds_lib.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.02
# Version....: v0.19.1
# Purpose....: Convenience loader for Data Safe v4 library
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Guard against multiple sourcing
[[ -n "${DS_LIB_SH_LOADED:-}" ]] && return 0

# Determine library directory
_DS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load modules in order
# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/common.sh" || {
    echo "ERROR: Failed to load common.sh" >&2
    exit 1
}

# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/oci_helpers.sh" || {
    echo "ERROR: Failed to load oci_helpers.sh" >&2
    exit 1
}

# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/ssh_helpers.sh" || {
    echo "ERROR: Failed to load ssh_helpers.sh" >&2
    exit 1
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
        lifecycle_norm="${lifecycle_input^^}"
        lifecycle_norm="${lifecycle_norm// /}"
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
# Function: ds_filter_targets_by_tags
# Purpose.: Filter a targets JSON blob by one or more OCI tag expressions.
#           Each expression is applied as an AND condition.
# Args....: $1 - targets JSON object {"data": [...]}
#           $2 - tag filter string (newline-separated expressions)
# Expression formats:
#   key=value       freeform tag key equals value
#   key             freeform tag key is present (any value)
#   ns/key=value    defined tag namespace ns, key equals value
#   ns/key          defined tag namespace ns, key is present
# Returns.: 0 on success
# Output..: filtered {"data": [...]} blob
# ------------------------------------------------------------------------------
ds_filter_targets_by_tags() {
    local targets_json="$1"
    local tag_filter="${2:-}"

    if [[ -z "$tag_filter" ]]; then
        printf '%s' "$targets_json"
        return 0
    fi

    local result="$targets_json"
    local expr=""
    while IFS= read -r expr; do
        [[ -z "$expr" ]] && continue

        if [[ "$expr" == *"/"* ]]; then
            # Defined tag: namespace/key=value or namespace/key
            local ns="${expr%%/*}"
            local rest="${expr#*/}"
            if [[ "$rest" == *"="* ]]; then
                local dk="${rest%%=*}"
                local dv="${rest#*=}"
                result=$(printf '%s' "$result" \
                    | jq --arg ns "$ns" --arg k "$dk" --arg v "$dv" \
                        '.data = (.data | map(select(."defined-tags"[$ns][$k] == $v)))')
            else
                result=$(printf '%s' "$result" \
                    | jq --arg ns "$ns" --arg k "$rest" \
                        '.data = (.data | map(select(."defined-tags"[$ns] | type == "object" and has($k))))')
            fi
        elif [[ "$expr" == *"="* ]]; then
            # Freeform tag: key=value
            local fk="${expr%%=*}"
            local fv="${expr#*=}"
            result=$(printf '%s' "$result" \
                | jq --arg k "$fk" --arg v "$fv" \
                    '.data = (.data | map(select(."freeform-tags"[$k] == $v)))')
        else
            # Freeform tag presence: key
            result=$(printf '%s' "$result" \
                | jq --arg k "$expr" \
                    '.data = (.data | map(select(."freeform-tags" | type == "object" and has($k))))')
        fi
    done <<< "$tag_filter"

    printf '%s' "$result"
}

# ------------------------------------------------------------------------------
# Function: oci_lookup_pdb_connection
# Purpose.: Look up an OCI PDB by name and return its service name and port
#           parsed from the pdb-default connection string.
# Args....: $1 - PDB name (as in pdb-name field, case-sensitive)
#           $2 - Compartment OCID to search in
# Returns.: 0 on success, 1 if PDB not found or no connection string
# Output..: "<service>|<port>" to stdout (e.g. "pdb01_PAAS.example.com|1521")
# Notes...: Uses oci_exec_ro so honours DRY_RUN flag transparently.
#           Skips TERMINATED PDBs. Returns first match when multiple exist.
# ------------------------------------------------------------------------------
oci_lookup_pdb_connection() {
    local pdb_name="$1"
    local compartment_ocid="$2"

    [[ -z "$pdb_name" || -z "$compartment_ocid" ]] && {
        log_error "oci_lookup_pdb_connection: pdb_name and compartment_ocid are required"
        return 1
    }

    log_debug "Looking up OCI PDB connection: name='$pdb_name' compartment='$compartment_ocid'"

    local pdbs_json
    pdbs_json=$(oci_exec_ro db pluggable-database list \
        --compartment-id "$compartment_ocid" --all 2> /dev/null) || {
        log_debug "  PDB list call failed or returned empty"
        return 1
    }

    # Find PDB by name (exclude TERMINATED), extract pdb-default connection string
    local conn_str
    conn_str=$(printf '%s' "$pdbs_json" | jq -r \
        --arg name "$pdb_name" \
        '.data[] | select(."pdb-name" == $name and ."lifecycle-state" != "TERMINATED")
                 | ."connection-strings"."pdb-default" // empty' \
        | head -n1)

    if [[ -z "$conn_str" ]]; then
        log_debug "  No connection string found for PDB '$pdb_name'"
        return 1
    fi

    log_debug "  PDB connection string: $conn_str"

    # Parse "host:port/service" format
    local host_port service port
    host_port="${conn_str%%/*}"
    service="${conn_str#*/}"
    port="${host_port#*:}"

    [[ -z "$service" || -z "$port" ]] && {
        log_debug "  Failed to parse connection string: $conn_str"
        return 1
    }

    printf '%s|%s' "$service" "$port"
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
#           $7 - tag filter string (optional; newline-separated expressions)
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
    local tag_filter="${7:-}"
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
        targets_json=$(ds_filter_targets_by_tags "$targets_json" "$tag_filter") || return 1
    else
        targets_json=$(ds_collect_targets "$compartment_input" "$targets_input" "$lifecycle_input" "$target_filter" "$tag_filter") || return 1
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
    local tag_filter="${5:-}"
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

    targets_json=$(ds_filter_targets_json "$targets_json" "$target_filter") || return 1
    ds_filter_targets_by_tags "$targets_json" "$tag_filter"
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
        if cache_mtime=$(_ds_file_mtime "$cache_file"); then
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
        local -i match_count=0
        local _match_line
        while IFS= read -r _match_line; do
            [[ -n "$_match_line" ]] && match_count=$((match_count + 1))
        done <<< "$matches"

        if [[ "$match_count" -eq 1 ]]; then
            result="${matches#*|}"
            log_info "Target '$input' not found by exact name; using partial match: ${matches%%|*}"
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

    # If target name is pre-resolved, return it directly without OCI call
    if [[ -n "${2:-}" ]]; then
        echo "$2"
        return 0
    fi

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
    local prefetched_json="${3:-}"

    # Fast path: name ends with _CDBROOT
    if [[ "$target_name" =~ _CDBROOT$ ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (name pattern)"
        return 0
    fi

    # Slow path: check freeform tag DBSec.Container
    log_debug "Checking tags for CDB\$ROOT detection: $target_name"
    local target_json
    if [[ -n "$prefetched_json" ]]; then
        target_json="$prefetched_json"
    else
        target_json=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_ocid" \
            --query 'data' 2> /dev/null) || {
            log_debug "Failed to get target details for tag check"
            return 1
        }
    fi
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
        printf -v "${prefix}_OCID" '%s' "$input"
        printf -v "${prefix}_NAME" '%s' "$resolved_comp_name"
        log_debug "Resolved compartment OCID to name: $resolved_comp_name"
    else
        # User provided name, resolve to OCID
        local comp_ocid
        comp_ocid=$(oci_resolve_compartment_ocid "$input") || {
            log_error "Cannot resolve compartment name '$input' to OCID"
            return 1
        }
        printf -v "${prefix}_NAME" '%s' "$input"
        printf -v "${prefix}_OCID" '%s' "$comp_ocid"
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
        printf -v "${prefix}_OCID" '%s' "$input"
        printf -v "${prefix}_NAME" '%s' "$target_name"
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
        printf -v "${prefix}_NAME" '%s' "$input"
        printf -v "${prefix}_OCID" '%s' "$target_ocid"
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

    # Build OCI command based on wait state
    local -a refresh_cmd=(oci data-safe target-database refresh --target-database-id "$target_ocid")

    if [[ -n "${WAIT_STATE:-}" ]]; then
        refresh_cmd+=(--wait-for-state "${WAIT_STATE}")
        log_info "[$current/$total] Refreshing: $target_name (waiting for ${WAIT_STATE}...)"
    else
        log_info "[$current/$total] Refreshing: $target_name (async)"
    fi

    [[ -n "${OCI_CLI_CONFIG_FILE}" ]] && refresh_cmd+=(--config-file "${OCI_CLI_CONFIG_FILE}")
    [[ -n "${OCI_CLI_PROFILE}" ]] && refresh_cmd+=(--profile "${OCI_CLI_PROFILE}")
    [[ -n "${OCI_CLI_REGION}" ]] && refresh_cmd+=(--region "${OCI_CLI_REGION}")

    log_trace "OCI command: $(_oci_redact_cmd "${refresh_cmd[@]}")"

    local stderr_file
    stderr_file=$(mktemp) || {
        log_error "Failed to allocate temp file"
        return 1
    }

    local stdout exit_code=0
    stdout=$("${refresh_cmd[@]}" 2> "$stderr_file") || exit_code=$?

    local stderr=""
    [[ -s "$stderr_file" ]] && stderr=$(< "$stderr_file")
    rm -f "$stderr_file"

    if [[ $exit_code -ne 0 ]]; then
        local combined_lc
        combined_lc="${stdout}${stderr}"
        combined_lc="${combined_lc,,}"
        if [[ "$combined_lc" == *"conflict"* ]] && [[ "$combined_lc" == *"already in progress"* ]]; then
            log_warn "[$current/$total] Skipping refresh for $target_name: operation already in progress"
            return 2
        fi
        log_error "OCI command failed (exit ${exit_code}): $(_oci_redact_cmd "${refresh_cmd[@]}")"
        [[ -n "$stdout" ]] && log_trace "OCI stdout: $stdout"
        [[ -n "$stderr" ]] && log_trace "OCI stderr: $stderr"
        return "$exit_code"
    fi

    [[ -n "$stderr" ]] && log_trace "OCI stderr (non-fatal): $stderr"

    # Handle output based on log level and log file
    if [[ -n "$stdout" ]]; then
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "$stdout" >> "${LOG_FILE}"
        fi

        # Show on stdout only in debug mode
        if [[ $(_log_level_num "${LOG_LEVEL:-INFO}") -le 1 ]]; then
            echo "$stdout"
        fi
    fi

    return 0
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

    # Write password to secure temp file to avoid exposure on argv (visible in ps)
    local pwd_file
    local prev_umask
    prev_umask=$(umask)
    umask 077
    pwd_file=$(mktemp)
    umask "$prev_umask"
    echo "$password" > "$pwd_file"
    # shellcheck disable=SC2064
    trap 'rm -f "$pwd_file"' RETURN

    # Generate bundle - returns work request
    oci_exec data-safe on-prem-connector generate-on-prem-connector-configuration \
        --on-prem-connector-id "$connector_ocid" \
        --password "file://$pwd_file" \
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

# ------------------------------------------------------------------------------
# Function: is_valid_bundle_key
# Purpose.: Validate bundle key against OCI complexity requirements
# Args....: $1 - Key candidate
# Returns.: 0 if valid, 1 if invalid
# Notes...: OCI requires 12-30 chars with at least one uppercase, lowercase,
#           numeric, and special character.
# ------------------------------------------------------------------------------
is_valid_bundle_key() {
    local bundle_key="$1"

    [[ ${#bundle_key} -ge 12 ]] || return 1
    [[ ${#bundle_key} -le 30 ]] || return 1
    [[ "$bundle_key" =~ [[:upper:]] ]] || return 1
    [[ "$bundle_key" =~ [[:lower:]] ]] || return 1
    [[ "$bundle_key" =~ [[:digit:]] ]] || return 1
    [[ "$bundle_key" =~ [^[:alnum:]] ]] || return 1

    return 0
}

# ------------------------------------------------------------------------------
# Function: generate_bundle_key
# Purpose.: Generate a random OCI-compliant connector bundle key
# Args....: None
# Returns.: 0 on success
# Output..: 20-character random bundle key to stdout
# Notes...: OCI requires 12-30 chars with upper, lower, digit, special char.
#           Allowed specials are intentionally shell-safe.
# ------------------------------------------------------------------------------
generate_bundle_key() {
    local candidate
    local special_set='!@#%^*_+=:,.?-'

    local max_attempts=50
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        candidate="$(openssl rand -base64 64 | tr -dc "A-Za-z0-9${special_set}" | head -c 20)"
        if is_valid_bundle_key "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done
    log_error "generate_bundle_key: failed to generate a unique key after ${max_attempts} attempts"
    return 1
}

# ------------------------------------------------------------------------------
# Function: ds_create_connector
# Purpose.: Create a new Data Safe on-premises connector in OCI
# Args....: $1 - Compartment OCID
#           $2 - Display name
#           $3 - Description (optional; pass "" to omit)
# Returns.: 0 on success (connector OCID to stdout), 1 on error
# Output..: Connector OCID
# ------------------------------------------------------------------------------
ds_create_connector() {
    local comp_ocid="$1"
    local display_name="$2"
    local description="${3:-}"

    if ! is_ocid "$comp_ocid"; then
        die "Invalid compartment OCID: $comp_ocid"
    fi

    if [[ -z "$display_name" ]]; then
        die "Connector display name is required"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create connector: $display_name in $comp_ocid"
        echo "ocid1.datasafeonpremconnector.oc1..DRY_RUN"
        return 0
    fi

    local -a cmd=(data-safe on-prem-connector create
        --compartment-id "$comp_ocid"
        --display-name "$display_name")

    [[ -n "$description" ]] && cmd+=(--description "$description")

    local result
    result=$(oci_exec "${cmd[@]}") || die "Failed to create connector: $display_name"

    local connector_ocid
    connector_ocid=$(echo "$result" | jq -r '.data.id // empty')

    if [[ -z "$connector_ocid" || "$connector_ocid" == "null" ]]; then
        die "Connector created but OCID not found in response"
    fi

    log_info "Connector created: $display_name ($connector_ocid)"
    echo "$connector_ocid"
}

# =============================================================================
# AUDIT TRAIL AND AUDIT PROFILE OPERATIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: ds_list_audit_trails
# Purpose.: List all Data Safe audit trails in a compartment subtree
# Args....: $1 - Compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON object {"data":{"items":[...]}} on stdout
# Notes...: One bulk call instead of one call per target. Audit trails carry two
#           independent state fields: "lifecycle-state" (ACTIVE, NEEDS_ATTENTION,
#           FAILED, ...) and "status" (NOT_STARTED, COLLECTING, IDLE, STOPPED,
#           ...). Both are needed to judge a trail; see ds_trail_effective_state.
# ------------------------------------------------------------------------------
ds_list_audit_trails() {
    local compartment="$1"

    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing audit trails in compartment subtree: $comp_ocid"

    oci_exec_ro data-safe audit-trail list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --all
}

# ------------------------------------------------------------------------------
# Function: ds_list_audit_profiles
# Purpose.: List all Data Safe audit profiles in a compartment subtree
# Args....: $1 - Compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON object {"data":{"items":[...]}} on stdout
# Notes...: The audit profile holds the collected audit volume and is the handle
#           required by "audit-profile discover-audit-trails".
# ------------------------------------------------------------------------------
ds_list_audit_profiles() {
    local compartment="$1"

    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing audit profiles in compartment subtree: $comp_ocid"

    oci_exec_ro data-safe audit-profile list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --all
}

# ------------------------------------------------------------------------------
# Function: ds_trail_items
# Purpose.: Normalize an OCI audit-trail/audit-profile list payload to an array
# Args....: $1 - JSON payload as returned by the OCI CLI
# Returns.: 0 on success
# Output..: JSON array on stdout (empty array when the payload has no items)
# Notes...: The CLI returns {"data":{"items":[...]}} for paginated list calls but
#           {"data":[...]} in some versions and for --from-json replays.
# ------------------------------------------------------------------------------
ds_trail_items() {
    local payload="${1:-}"

    [[ -z "$payload" ]] && {
        printf '[]'
        return 0
    }

    printf '%s' "$payload" | jq -c '
        if (.data | type) == "object" then (.data.items // [])
        elif (.data | type) == "array" then .data
        elif type == "array" then .
        else []
        end
    ' 2> /dev/null || printf '[]'
}

# ------------------------------------------------------------------------------
# Function: ds_trail_effective_state
# Purpose.: Collapse an audit trail's lifecycle-state and status into one state
# Args....: $1 - lifecycle-state (may be empty)
#           $2 - status (may be empty)
# Returns.: 0 always
# Output..: Normalized state on stdout
# Notes...: A trail that is broken reports it in lifecycle-state, everything else
#           about collection lives in status. Reporting lifecycle-state alone
#           (the pre-1.1.0 behaviour) can never show NOT_STARTED.
# ------------------------------------------------------------------------------
ds_trail_effective_state() {
    local lifecycle="${1:-}"
    local status="${2:-}"

    lifecycle="${lifecycle^^}"
    status="${status^^}"

    case "$lifecycle" in
        NEEDS_ATTENTION | FAILED)
            printf 'NEEDS_ATTENTION'
            return 0
            ;;
        DELETING | DELETED)
            printf '%s' "$lifecycle"
            return 0
            ;;
    esac

    case "$status" in
        STOPPED_NEEDS_ATTN | STOPPED_FAILED)
            printf 'NEEDS_ATTENTION'
            return 0
            ;;
    esac

    if [[ -n "$status" ]]; then
        printf '%s' "$status"
    elif [[ -n "$lifecycle" ]]; then
        printf '%s' "$lifecycle"
    else
        printf 'UNKNOWN'
    fi
}

# ------------------------------------------------------------------------------
# Function: ds_trail_is_collecting
# Purpose.: Test whether an audit trail is already collecting or on its way there
# Args....: $1 - Normalized state (see ds_trail_effective_state)
# Returns.: 0 if the trail must not be started again, 1 otherwise
# Output..: None
# ------------------------------------------------------------------------------
ds_trail_is_collecting() {
    case "${1^^}" in
        COLLECTING | STARTING | RESUMING | RECOVERING | RETRYING | IDLE) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: ds_trail_is_startable
# Purpose.: Test whether an audit trail can be started by an automated run
# Args....: $1 - Normalized state (see ds_trail_effective_state)
# Returns.: 0 if startable, 1 otherwise
# Output..: None
# Notes...: NEEDS_ATTENTION is deliberately not startable - it is reported only.
# ------------------------------------------------------------------------------
ds_trail_is_startable() {
    case "${1^^}" in
        NOT_STARTED) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: ds_collect_trail_items
# Purpose.: Run a bulk audit list function over several compartments and merge
# Args....: $1 - list function (ds_list_audit_trails|ds_list_audit_profiles)
#           $@ - compartment OCIDs or names
# Returns.: 0 on success
# Output..: Merged, de-duplicated JSON array on stdout
# Notes...: A failing compartment is logged and skipped so a single missing
#           permission does not void the whole report.
# ------------------------------------------------------------------------------
ds_collect_trail_items() {
    local list_fn="$1"
    shift

    local scope payload items acc_file rc=0

    acc_file=$(mktemp) || {
        log_error "Cannot create temp file to accumulate ${list_fn} results"
        printf '[]'
        return 1
    }

    for scope in "$@"; do
        payload=$("$list_fn" "$scope" 2> /dev/null) || {
            log_warn "Failed to list via ${list_fn} in compartment: $scope"
            continue
        }
        items=$(ds_trail_items "$payload")
        # One JSON array per line, merged in a single pass below. The previous
        # version re-serialized a growing accumulator through jq's argv on every
        # iteration: with 600 prod targets that exceeded ARG_MAX ("Argument list
        # too long") and the cost was quadratic in the number of compartments.
        printf '%s\n' "$items" >> "$acc_file"
    done

    jq -c -s 'add // [] | unique_by(.id)' < "$acc_file" || rc=$?
    rm -f "$acc_file"
    return $rc
}

# ------------------------------------------------------------------------------
# Variable: DS_TRAIL_JQ_PRELUDE
# Purpose.: jq function library mirroring ds_trail_effective_state for bulk work
# Notes...: Building 1390 rows with a bash loop costs one fork per field. The jq
#           implementation must stay in sync with ds_trail_effective_state and
#           ds_trail_is_collecting; tests/script_ds_trail_report.bats pins that.
#           Provides: trail_effective_state, trail_state_rank, target_environment,
#           target_container_type.
# ------------------------------------------------------------------------------
DS_TRAIL_JQ_PRELUDE='
def trail_effective_state(t):
  ((t["lifecycle-state"] // "") | ascii_upcase) as $lc
  | ((t["status"] // "") | ascii_upcase) as $st
  | if ($lc == "NEEDS_ATTENTION" or $lc == "FAILED") then "NEEDS_ATTENTION"
    elif ($lc == "DELETING" or $lc == "DELETED") then $lc
    elif ($st == "STOPPED_NEEDS_ATTN" or $st == "STOPPED_FAILED") then "NEEDS_ATTENTION"
    elif ($st != "") then $st
    elif ($lc != "") then $lc
    else "UNKNOWN"
    end;

def trail_state_rank($s):
  {"NEEDS_ATTENTION":0,"NOT_STARTED":1,"STOPPED":2,"STOPPING":3,"INACTIVE":4,
   "DELETING":5,"DELETED":6,"RETRYING":7,"RECOVERING":8,"RESUMING":9,
   "STARTING":10,"IDLE":11,"COLLECTING":12}[$s] // 7;

def target_environment(t; $ns):
  (t["defined-tags"][$ns]["Environment"] // "") as $env
  | (t["defined-tags"][$ns]["ContainerStage"] // "") as $stage
  | if ($env | length) > 0 and ($env | ascii_downcase) != "undef" then ($env | ascii_downcase)
    elif ($stage | length) > 0 and ($stage | test("-")) then ($stage | ascii_downcase | split("-") | last)
    else "undef"
    end;

def target_container_type(t; $ns):
  (t["defined-tags"][$ns]["ContainerType"] // "") as $ct
  | if ((t["display-name"] // "") | test("_CDBROOT$")) then "cdbroot"
    elif ($ct | length) > 0 and ($ct | ascii_downcase) != "undef" then ($ct | ascii_downcase)
    else "pdb"
    end;

def target_stage(t; $ns):
  (t["defined-tags"][$ns]["ContainerStage"] // "");
'
# shellcheck disable=SC2034  # consumed by bin/ds_trail_report.sh and bin/ds_audit_reconcile.sh
readonly DS_TRAIL_JQ_PRELUDE

# ------------------------------------------------------------------------------
# Function: ds_discover_audit_trails
# Purpose.: Trigger audit trail rediscovery for an audit profile
# Args....: $1 - Audit profile OCID
#           $2 - Target name for log messages (optional)
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# Notes...: There is no create operation for audit trails - Data Safe discovers
#           them. This is asynchronous: the trail object appears after the work
#           request completes and is started by a later reconcile run.
# ------------------------------------------------------------------------------
ds_discover_audit_trails() {
    local profile_ocid="$1"
    local target_name="${2:-$1}"

    if ! is_ocid "$profile_ocid"; then
        log_error "Invalid audit profile OCID: $profile_ocid"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would discover audit trails for: $target_name ($profile_ocid)"
        return 0
    fi

    log_info "Discovering audit trails for: $target_name"
    oci_exec data-safe audit-profile discover-audit-trails \
        --audit-profile-id "$profile_ocid" > /dev/null
}

# ------------------------------------------------------------------------------
# Function: ds_format_bytes
# Purpose.: Render a byte count as a short human readable string
# Args....: $1 - Byte count (may be empty or non-numeric)
# Returns.: 0 always
# Output..: Formatted size on stdout, "-" when the input is not a number
# ------------------------------------------------------------------------------
ds_format_bytes() {
    local bytes="${1:-}"

    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        printf '%s' "-"
        return 0
    fi

    local -a units=(B KB MB GB TB PB)
    local idx=0
    local value="$bytes"

    while [[ $value -ge 1024 && $idx -lt 5 ]]; do
        value=$((value / 1024))
        idx=$((idx + 1))
    done

    if [[ $idx -eq 0 ]]; then
        printf '%s%s' "$value" "${units[$idx]}"
        return 0
    fi

    # One decimal place via integer math: scale the pre-division value by 10
    local divisor=1
    local i
    for ((i = 0; i < idx; i++)); do
        divisor=$((divisor * 1024))
    done
    local scaled=$((bytes * 10 / divisor))

    printf '%s.%s%s' "$((scaled / 10))" "$((scaled % 10))" "${units[$idx]}"
}

# ------------------------------------------------------------------------------
# Function: ds_build_trail_rows
# Purpose.: Join targets, audit trails and audit profiles into one row per target
# Args....: $1 - targets JSON {"data":[...]}
#           $2 - audit trail items JSON array
#           $3 - audit profile items JSON array
#           $4 - tag namespace (default: DBSec)
#           $5 - trail state filter, comma separated (optional)
# Returns.: 0 on success, 1 on jq error
# Output..: JSON array of row objects on stdout
# Notes...: Targets with several trails report the most actionable state, i.e.
#           the one with the lowest trail_state_rank. A target without any trail
#           object reports NO_TRAIL - that is not an OCI state, it means Data
#           Safe has not discovered a trail for this target yet.
# ------------------------------------------------------------------------------
ds_build_trail_rows() {
    local targets_json="$1"
    local trail_items="${2:-[]}"
    local profile_items="${3:-[]}"
    local tag_ns="${4:-DBSec}"
    local state_filter="${5:-}"

    # Trails, profiles and targets are passed through temp files, not argv.
    # A 600-target prod compartment produces arrays well past ARG_MAX and jq
    # fails with "Argument list too long". --slurpfile wraps each file in an
    # array, hence the [0] unwrapping in the program below.
    local trails_file profiles_file rc=0
    trails_file=$(mktemp) || {
        log_error "Cannot create temp file for trail items"
        return 1
    }
    profiles_file=$(mktemp) || {
        log_error "Cannot create temp file for profile items"
        rm -f "$trails_file"
        return 1
    }
    printf '%s' "$trail_items" > "$trails_file"
    printf '%s' "$profile_items" > "$profiles_file"

    jq -c \
        --slurpfile trails_in "$trails_file" \
        --slurpfile profiles_in "$profiles_file" \
        --arg ns "$tag_ns" \
        --arg states "$state_filter" \
        "${DS_TRAIL_JQ_PRELUDE}"'
        ($trails_in[0]   // []) as $trails
      | ($profiles_in[0] // []) as $profiles
      | ($trails   | group_by(.["target-id"]) | map({key: .[0]["target-id"], value: .}) | from_entries) as $trail_map
      | ($profiles | group_by(.["target-id"]) | map({key: .[0]["target-id"], value: .[0]}) | from_entries) as $profile_map
      | ($states | ascii_upcase | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $state_list
      | [ .data[]
          | . as $t
          | ($trail_map[$t.id] // []) as $tr
          | ($profile_map[$t.id] // null) as $pr
          | ($tr | map(trail_effective_state(.))) as $tr_states
          | (if ($tr | length) == 0 then "NO_TRAIL"
             else ($tr_states | sort_by(trail_state_rank(.)) | first)
             end) as $state
          | (if ($tr | length) == 0 then "-"
             elif ($tr | all(.["is-auto-purge-enabled"] == true)) then "yes"
             elif ($tr | all(.["is-auto-purge-enabled"] != true)) then "no"
             else "mixed"
             end) as $purge
          | {
              target:            ($t["display-name"] // $t.id),
              "target-id":       $t.id,
              environment:       target_environment($t; $ns),
              type:              target_container_type($t; $ns),
              stage:             (target_stage($t; $ns) | if length == 0 then "-" else . end),
              "target-state":    ($t["lifecycle-state"] // "-"),
              "trail-state":     $state,
              "trail-count":     ($tr | length),
              "auto-purge":      $purge,
              "volume-bytes":    ($pr["audit-collected-volume"] // null),
              "audit-profile-id": ($pr.id // null),
              "compartment-id":  ($t["compartment-id"] // null)
            }
        ]
      | if ($state_list | length) > 0
        then map(select(.["trail-state"] as $s | $state_list | index($s) != null))
        else .
        end
      | sort_by(.environment, .type, .target)
    ' <<< "$targets_json" || rc=$?

    rm -f "$trails_file" "$profiles_file"
    return $rc
}

# ------------------------------------------------------------------------------
# Function: ds_trail_summary_json
# Purpose.: Aggregate trail rows per environment, plus a TOTAL row
# Args....: $1 - rows JSON array from ds_build_trail_rows
# Returns.: 0 on success, 1 on jq error
# Output..: JSON array of summary objects on stdout
# ------------------------------------------------------------------------------
ds_trail_summary_json() {
    local rows_json="${1:-[]}"

    jq -c '
        def bucket($s):
          if ($s == "COLLECTING" or $s == "IDLE" or $s == "RECOVERING"
               or $s == "STARTING" or $s == "RESUMING" or $s == "RETRYING") then "collecting"
          elif $s == "NOT_STARTED" then "not_started"
          elif $s == "NEEDS_ATTENTION" then "needs_attention"
          elif $s == "NO_TRAIL" then "no_trail"
          else "other"
          end;

        def agg($env; $rows):
          {
            environment: $env,
            targets: ($rows | length),
            collecting:      ($rows | map(select(bucket(.["trail-state"]) == "collecting"))      | length),
            not_started:     ($rows | map(select(bucket(.["trail-state"]) == "not_started"))     | length),
            needs_attention: ($rows | map(select(bucket(.["trail-state"]) == "needs_attention")) | length),
            no_trail:        ($rows | map(select(bucket(.["trail-state"]) == "no_trail"))        | length),
            other:           ($rows | map(select(bucket(.["trail-state"]) == "other"))           | length),
            "volume-bytes":  ($rows | map(.["volume-bytes"] // 0) | add // 0)
          };

        . as $all
        | ($all | group_by(.environment) | map(agg(.[0].environment; .)))
          + (if ($all | length) > 0 then [agg("TOTAL"; $all)] else [] end)
    ' <<< "$rows_json"
}

readonly DS_LIB_SH_LOADED=1
# Library loaded successfully (v4.0.0)
