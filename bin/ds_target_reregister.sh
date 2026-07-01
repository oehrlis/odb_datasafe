#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_reregister.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.05.05
# Version....: v0.20.0
# Purpose....: Re-register a Data Safe target after a PDB move (new cluster/host/SID)
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
#
# Purpose:
#   Update displayName, description, and databaseDetails of an existing Data Safe
#   target after the underlying PDB has been relocated (new ExaCC cluster, new host,
#   new SID, or renamed PDB). Optionally updates credentials in the same run.
#
# Usage:
#   ds_target_reregister.sh --target <name|ocid> --cluster <new> [options]
#
# Exit Codes:
#   0 = Success
#   1 = Input validation or resolution error
#   2 = Update error
# ------------------------------------------------------------------------------

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.20.0')"
readonly SCRIPT_VERSION

# =============================================================================
# DEFAULTS
# =============================================================================

# Target to update
: "${TARGET:=}"
: "${COMPARTMENT:=}"

# New connection values (empty = keep current)
: "${NEW_CLUSTER:=}"
: "${NEW_HOST:=}"
: "${NEW_PDB:=}"
: "${NEW_SID:=}"
: "${NEW_PORT:=}"
: "${NEW_SERVICE:=}"
: "${FROM_OCI:=false}"
: "${PDB_COMPARTMENT:=}"

# Metadata overrides
: "${NEW_DISPLAY_NAME:=}"
: "${NEW_DESCRIPTION:=}"

# Credentials (optional; if DS_SECRET resolves, credentials are also updated)
: "${DS_USER:=${DATASAFE_USER:-DS_ADMIN}}"
: "${DS_SECRET:=${DATASAFE_SECRET:-}}"
: "${DATASAFE_SECRET_FILE:=}"
: "${COMMON_USER_PREFIX:=${COMMON_USER_PREFIX:-C##}}"
: "${DS_TARGET_NAME_CDBROOT_REGEX:=_(CDB\$ROOT|CDBROOT)$}"

# Execution
: "${APPLY_CHANGES:=false}"
: "${WAIT_STATE:=}"

# shellcheck disable=SC2034
SHOW_USAGE_ON_EMPTY_ARGS=true

# Load framework
# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

setup_error_handling
init_config

# Re-sync credentials after config loading
: "${DS_USER:=${DATASAFE_USER:-DS_ADMIN}}"
: "${DS_SECRET:=${DATASAFE_SECRET:-}}"

# Runtime state (populated during execution)
TARGET_OCID=""
COMP_OCID=""
CLUSTER_OCID=""
PLUGGABLE_DB_OCID=""
PDB_COMPARTMENT_OCID=""
TMP_CRED_JSON=""

# Current state (loaded from OCI)
CUR_DISPLAY_NAME=""
CUR_DESCRIPTION=""
CUR_DB_DETAILS=""
CUR_CLUSTER=""
CUR_CDB=""
CUR_PDB=""

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Args....: $1 - Exit code (optional, default: 0)
# Returns.: Exits with specified code
# ------------------------------------------------------------------------------
usage() {
    local exit_code=${1:-0}
    cat << EOF
Usage: ${SCRIPT_NAME} [options]

DESCRIPTION:
    Update an existing Data Safe target after a PDB has been relocated.
    Updates displayName, description, and databaseDetails (cluster, PDB, SID,
    service name, listener port). Optionally also updates credentials.

REQUIRED:
    -t, --target NAME|OCID      Existing target name or OCID (required)

CONNECTION CHANGES (at least one required):
        --cluster CLUSTER       New VM Cluster name or OCID
    -H, --host HOST             New database host (alternative to --cluster)
        --pdb PDB               New PDB name
        --sid SID               New Oracle SID (CDB name)
        --port PORT             New listener port
        --service SERVICE       New service name (explicit)
        --from-oci              Derive service name and port from OCI PDB connection string
        --pdb-compartment COMP  Compartment for OCI PDB lookup (default: target's compartment)

METADATA:
    -N, --display-name NAME     New display name (default: auto-generated from schema)
        --description DESC      New description (default: keep current)

CREDENTIALS (optional - also update credentials if provided):
    -U, --ds-user USER          Data Safe user (default: ${DS_USER:-DS_ADMIN})
    -P, --ds-secret VALUE       Data Safe secret (plain or base64)
        --secret-file FILE      Base64 secret file

SCOPE:
    -c, --compartment COMP      Compartment to search when --target is a name
                                (default: DS_ROOT_COMP from datasafe.conf)

MODES:
        --apply                 Apply changes (default: dry-run only)
        --wait-state STATE      Poll until update reaches STATE (e.g. ACCEPTED)
    -h, --help                  Show this help

DISPLAY NAME SCHEMA:
    Auto-generated as: <cluster>_<cdb>_<pdb|CDBROOT>
    Unchanged parts are taken from the current target name.
    Example: exa01_cdb01_MYAPP → after --cluster exa02: exa02_cdb01_MYAPP

CREDENTIAL UPDATE:
    Credentials are only updated when --ds-secret (or --secret-file) is provided.
    Root targets (names ending in _CDBROOT) automatically receive the
    common-user prefix (default: ${COMMON_USER_PREFIX:-C##}).

EXAMPLES:
    # PDB moved to new cluster - dry-run (default)
    ${SCRIPT_NAME} --target exa01_cdb01_MYAPP --cluster exa02

    # PDB moved to new cluster - apply
    ${SCRIPT_NAME} --target exa01_cdb01_MYAPP --cluster exa02 --apply

    # PDB moved + new service from OCI + credential update
    ${SCRIPT_NAME} --target exa01_cdb01_MYAPP --cluster exa02 \\
        --from-oci --ds-secret <secret> --apply

    # Only rename the PDB (same cluster, new PDB name after rename)
    ${SCRIPT_NAME} --target exa01_cdb01_OLDPDB --pdb NEWPDB --apply

    # Full relocation: new cluster, new SID, new PDB
    ${SCRIPT_NAME} --target exa01_cdb01_MYAPP \\
        --cluster exa02 --sid cdb02 --pdb MYAPP \\
        --ds-secret <secret> --apply

EXIT CODES:
    0 = Success
    1 = Input validation error
    2 = Update error

EOF
    exit "$exit_code"
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success
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
            -t | --target)
                need_val "$1" "${2:-}"
                TARGET="$2"
                shift 2
                ;;
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            --cluster)
                need_val "$1" "${2:-}"
                NEW_CLUSTER="$2"
                shift 2
                ;;
            -H | --host)
                need_val "$1" "${2:-}"
                NEW_HOST="$2"
                shift 2
                ;;
            --pdb)
                need_val "$1" "${2:-}"
                NEW_PDB="$2"
                shift 2
                ;;
            --sid)
                need_val "$1" "${2:-}"
                NEW_SID="$2"
                shift 2
                ;;
            --port)
                need_val "$1" "${2:-}"
                NEW_PORT="$2"
                shift 2
                ;;
            --service)
                need_val "$1" "${2:-}"
                NEW_SERVICE="$2"
                shift 2
                ;;
            --from-oci)
                FROM_OCI=true
                shift
                ;;
            --pdb-compartment)
                need_val "$1" "${2:-}"
                PDB_COMPARTMENT="$2"
                shift 2
                ;;
            -N | --display-name)
                need_val "$1" "${2:-}"
                NEW_DISPLAY_NAME="$2"
                shift 2
                ;;
            --description)
                need_val "$1" "${2:-}"
                NEW_DESCRIPTION="$2"
                shift 2
                ;;
            -U | --ds-user)
                need_val "$1" "${2:-}"
                DS_USER="$2"
                shift 2
                ;;
            -P | --ds-secret)
                need_val "$1" "${2:-}"
                DS_SECRET="$2"
                shift 2
                ;;
            --secret-file)
                need_val "$1" "${2:-}"
                DATASAFE_SECRET_FILE="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --wait-state)
                need_val "$1" "${2:-}"
                WAIT_STATE="${2^^}"
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

    # First positional argument is the target
    if [[ ${#remaining[@]} -gt 0 && -z "$TARGET" ]]; then
        TARGET="${remaining[0]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: parse_display_name
# Purpose.: Split a target display name into cluster|cdb|pdb components
# Args....: $1 - Display name (e.g. exa01_cdb01_PDB01 or cdb01_PDB01)
# Returns.: 0 on success
# Output..: "cluster|cdb|pdb" to stdout
# Notes...: Uses DS_TARGET_NAME_REGEX / DS_TARGET_NAME_SEPARATOR if configured
# ------------------------------------------------------------------------------
parse_display_name() {
    local name="$1"
    local cluster="" cdb="" pdb=""

    if [[ -n "${DS_TARGET_NAME_REGEX:-}" ]] && [[ "$name" =~ ${DS_TARGET_NAME_REGEX} ]]; then
        cluster="${BASH_REMATCH[1]}"
        cdb="${BASH_REMATCH[2]}"
        pdb="${BASH_REMATCH[3]}"
    else
        local sep="${DS_TARGET_NAME_SEPARATOR:-_}"
        IFS="$sep" read -r cluster cdb pdb <<< "$name"
        # Two-part name: no cluster prefix
        if [[ -z "$pdb" ]]; then
            pdb="$cdb"
            cdb="$cluster"
            cluster=""
        fi
    fi

    printf '%s|%s|%s' "$cluster" "$cdb" "$pdb"
}

# ------------------------------------------------------------------------------
# Function: load_current_target
# Purpose.: Read current target state from OCI into CUR_* globals
# Args....: None (uses TARGET_OCID)
# Returns.: 0 on success, dies on error
# ------------------------------------------------------------------------------
load_current_target() {
    log_debug "Loading current target state: $TARGET_OCID"

    local target_json
    target_json=$(oci_exec_ro data-safe target-database get \
        --target-database-id "$TARGET_OCID" \
        --query 'data') || die "Failed to get target details for: $TARGET_OCID"

    CUR_DISPLAY_NAME=$(printf '%s' "$target_json" | jq -r '."display-name" // empty')
    CUR_DESCRIPTION=$(printf '%s' "$target_json" | jq -r '.description // empty')
    CUR_DB_DETAILS=$(printf '%s' "$target_json" | jq -r '."database-details" // empty')
    COMP_OCID=$(printf '%s' "$target_json" | jq -r '."compartment-id" // empty')

    [[ -n "$CUR_DISPLAY_NAME" ]] || die "Could not read display-name for target: $TARGET_OCID"
    [[ -n "$CUR_DB_DETAILS" && "$CUR_DB_DETAILS" != "null" ]] || die "Could not read database-details for target: $TARGET_OCID"

    log_debug "Current display name: $CUR_DISPLAY_NAME"
    log_debug "Current compartment: $COMP_OCID"

    local parsed
    parsed=$(parse_display_name "$CUR_DISPLAY_NAME")
    IFS='|' read -r CUR_CLUSTER CUR_CDB CUR_PDB <<< "$parsed"

    log_debug "Parsed display name: cluster='$CUR_CLUSTER' cdb='$CUR_CDB' pdb='$CUR_PDB'"
}

# ------------------------------------------------------------------------------
# Function: resolve_new_cluster_ocid
# Purpose.: Resolve OCID for the new cluster
# Args....: None (uses NEW_CLUSTER global)
# Returns.: 0 on success, 1 if not found
# Output..: Sets CLUSTER_OCID global
# ------------------------------------------------------------------------------
resolve_new_cluster_ocid() {
    [[ -z "$NEW_CLUSTER" ]] && return 1

    if [[ "$NEW_CLUSTER" =~ ^ocid1\.(cloudvmcluster|vmcluster)\. ]]; then
        CLUSTER_OCID="$NEW_CLUSTER"
        log_debug "Cluster OCID provided directly: $CLUSTER_OCID"
        return 0
    fi

    local cluster_json=""
    cluster_json=$(oci_resolve_vmcluster_by_name "$NEW_CLUSTER" || true)
    if [[ -n "$cluster_json" ]]; then
        CLUSTER_OCID=$(jq -r '.id // empty' <<< "$cluster_json")
        [[ "$CLUSTER_OCID" == "null" ]] && CLUSTER_OCID=""
    fi

    if [[ -n "$CLUSTER_OCID" ]]; then
        log_info "Resolved new cluster: $NEW_CLUSTER ($CLUSTER_OCID)"
        return 0
    fi

    log_warn "Could not resolve cluster OCID for: $NEW_CLUSTER"
    return 1
}

# ------------------------------------------------------------------------------
# Function: resolve_new_pdb_ocid
# Purpose.: Resolve pluggable database OCID for the new PDB/SID
# Args....: None (uses NEW_PDB, NEW_SID, CUR_CDB, CUR_PDB, COMP_OCID globals)
# Returns.: 0 on success, 1 on failure
# Output..: Sets PLUGGABLE_DB_OCID global
# ------------------------------------------------------------------------------
resolve_new_pdb_ocid() {
    local pdb="${NEW_PDB:-$CUR_PDB}"
    local sid="${NEW_SID:-$CUR_CDB}"

    [[ -z "$pdb" ]] && return 1
    [[ -z "$COMP_OCID" ]] && return 1

    local databases_json
    databases_json=$(oci_exec_ro db database list \
        --compartment-id "$COMP_OCID" \
        --all 2> /dev/null || true)
    [[ -n "$databases_json" ]] || return 1

    local database_id
    database_id=$(printf '%s' "$databases_json" | jq -r \
        --arg sid "$sid" \
        --arg cluster "${CLUSTER_OCID:-}" '
        .data[]
        | select(
            ((."db-name" // "" | ascii_downcase) == ($sid | ascii_downcase))
            or ((."db-unique-name" // "" | ascii_downcase) == ($sid | ascii_downcase))
          )
        | select(
            ($cluster == "")
            or ((."vm-cluster-id" // "") == $cluster)
            or ((."cloud-vm-cluster-id" // "") == $cluster)
          )
        | .id
    ' | head -n1)
    [[ -n "$database_id" && "$database_id" != "null" ]] || return 1

    local pdbs_json
    pdbs_json=$(oci_exec_ro db pluggable-database list \
        --database-id "$database_id" \
        --all 2> /dev/null || true)
    [[ -n "$pdbs_json" ]] || return 1

    PLUGGABLE_DB_OCID=$(printf '%s' "$pdbs_json" | jq -r --arg pdb "$pdb" '
        .data[]
        | select(
            ((."pdb-name" // "" | ascii_downcase) == ($pdb | ascii_downcase))
            or ((."display-name" // "" | ascii_downcase) == ($pdb | ascii_downcase))
          )
        | .id
    ' | head -n1)

    if [[ -n "$PLUGGABLE_DB_OCID" && "$PLUGGABLE_DB_OCID" != "null" ]]; then
        log_info "Resolved new PDB OCID: $PLUGGABLE_DB_OCID"
        return 0
    fi

    PLUGGABLE_DB_OCID=""
    return 1
}

# ------------------------------------------------------------------------------
# Function: is_cdbroot_target
# Purpose.: Detect if current target is a CDB$ROOT target
# Args....: None (uses CUR_DISPLAY_NAME global)
# Returns.: 0 = CDB$ROOT, 1 = PDB
# ------------------------------------------------------------------------------
is_cdbroot_target() {
    [[ "$CUR_DISPLAY_NAME" =~ $DS_TARGET_NAME_CDBROOT_REGEX ]]
}

# ------------------------------------------------------------------------------
# Function: resolve_secret
# Purpose.: Resolve and decode DS_SECRET from various sources
# Args....: None
# Returns.: 0 on success (DS_SECRET populated), 1 if no secret available
# ------------------------------------------------------------------------------
resolve_secret() {
    if [[ -n "$DS_SECRET" ]]; then
        DS_SECRET=$(normalize_secret_value "$DS_SECRET") || die "Failed to decode base64 secret"
        [[ -n "$DS_SECRET" ]] || die "Decoded secret is empty"
        return 0
    fi

    local secret_file=""
    if secret_file=$(find_password_file "$DS_USER" "${DATASAFE_SECRET_FILE:-}"); then
        require_cmd base64
        DS_SECRET=$(decode_base64_file "$secret_file") || die "Failed to decode base64 secret file: $secret_file"
        DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")
        [[ -n "$DS_SECRET" ]] || die "Secret file is empty: $secret_file"
        log_info "Loaded Data Safe secret from file: $secret_file"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: resolve_ds_user_for_target
# Purpose.: Determine the correct DS username (with or without common-user prefix)
# Args....: None (uses DS_USER, COMMON_USER_PREFIX, CUR_DISPLAY_NAME)
# Returns.: 0 on success
# Output..: username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user_for_target() {
    local base_user="$DS_USER"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_user" == ${COMMON_USER_PREFIX}* ]]; then
        base_user="${base_user#"${COMMON_USER_PREFIX}"}"
    fi

    if is_cdbroot_target && [[ -n "$COMMON_USER_PREFIX" ]]; then
        printf '%s' "${COMMON_USER_PREFIX}${base_user}"
        return 0
    fi

    printf '%s' "$base_user"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate arguments and resolve target OCID + current state
# Args....: None
# Returns.: 0 on success, dies on error
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    [[ -n "$TARGET" ]] || die "Missing required option: --target"

    # Check at least one change is requested
    if [[ -z "$NEW_CLUSTER" && -z "$NEW_HOST" && -z "$NEW_PDB" && -z "$NEW_SID" &&
        -z "$NEW_PORT" && -z "$NEW_SERVICE" && -z "$NEW_DISPLAY_NAME" &&
        -z "$NEW_DESCRIPTION" && "$FROM_OCI" == "false" ]]; then
        die "Nothing to update. Specify at least one of: --cluster, --host, --pdb, --sid, --port, --service, --from-oci, --display-name, --description"
    fi

    [[ -n "$NEW_CLUSTER" && -n "$NEW_HOST" ]] && die "Specify --cluster OR --host, not both"

    if [[ -n "$NEW_PORT" ]]; then
        [[ "$NEW_PORT" =~ ^[0-9]+$ && "$NEW_PORT" -ge 1 && "$NEW_PORT" -le 65535 ]] \
            || die "Invalid listener port: $NEW_PORT (must be 1-65535)"
    fi

    # Resolve target OCID
    if is_ocid "$TARGET"; then
        TARGET_OCID="$TARGET"
        log_debug "Target OCID provided directly: $TARGET_OCID"
    else
        log_debug "Resolving target by name: $TARGET"
        local scope="${COMPARTMENT:-${DS_ROOT_COMP:-}}"
        [[ -n "$scope" ]] || die "Cannot resolve target name without a compartment. Use --compartment or set DS_ROOT_COMP"

        local targets_json
        targets_json=$(ds_collect_targets "$scope" "$TARGET" "" "" "") \
            || die "Failed to search for target: $TARGET"

        TARGET_OCID=$(printf '%s' "$targets_json" | jq -r \
            --arg name "$TARGET" \
            '.data[] | select(."display-name" == $name) | .id' | head -n1)

        [[ -n "$TARGET_OCID" && "$TARGET_OCID" != "null" ]] \
            || die "Target not found: $TARGET (use --compartment to narrow the search scope)"

        log_info "Resolved target: $TARGET ($TARGET_OCID)"
    fi

    # Load current state
    load_current_target

    # Resolve new cluster OCID if cluster change requested
    if [[ -n "$NEW_CLUSTER" ]]; then
        if ! resolve_new_cluster_ocid; then
            if [[ "$APPLY_CHANGES" == "true" ]]; then
                die "Failed to resolve cluster OCID for: $NEW_CLUSTER"
            fi
            log_warn "Dry-run: could not resolve cluster OCID for '$NEW_CLUSTER' (OCI lookup unavailable)"
        fi
    fi

    # Resolve new PDB OCID when PDB or SID changes
    if [[ -n "$NEW_PDB" || -n "$NEW_SID" || -n "$NEW_CLUSTER" ]]; then
        if resolve_new_pdb_ocid; then
            :
        else
            local cluster_ref="${CLUSTER_OCID:-}"
            if [[ -n "$cluster_ref" ]]; then
                log_warn "Could not resolve PDB OCID — not required for ExaCC (vmClusterId + serviceName used instead)"
            else
                log_warn "Could not resolve PDB OCID for '${NEW_PDB:-$CUR_PDB}'"
            fi
        fi
    fi

    # Resolve PDB compartment for --from-oci
    if [[ "$FROM_OCI" == "true" ]]; then
        if [[ -n "$PDB_COMPARTMENT" ]]; then
            if is_ocid "$PDB_COMPARTMENT"; then
                PDB_COMPARTMENT_OCID="$PDB_COMPARTMENT"
            else
                PDB_COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$PDB_COMPARTMENT") \
                    || die "Cannot resolve --pdb-compartment: $PDB_COMPARTMENT"
            fi
        else
            PDB_COMPARTMENT_OCID="$COMP_OCID"
        fi
        log_info "OCI PDB lookup compartment: $PDB_COMPARTMENT_OCID"
    fi

    # Resolve credentials if provided
    if resolve_secret; then
        local resolved_user
        resolved_user=$(resolve_ds_user_for_target)
        log_info "Credentials provided — will also update credentials for user: $resolved_user"
    fi
}

# ------------------------------------------------------------------------------
# Function: compute_new_display_name
# Purpose.: Build the new display name using current parts + overrides
# Args....: None
# Returns.: 0 on success
# Output..: new display name to stdout
# ------------------------------------------------------------------------------
compute_new_display_name() {
    # If explicitly set, use it as-is
    if [[ -n "$NEW_DISPLAY_NAME" ]]; then
        printf '%s' "$NEW_DISPLAY_NAME"
        return 0
    fi

    # Apply overrides on current parsed components
    local cluster="${NEW_CLUSTER:-$CUR_CLUSTER}"
    local cdb="${NEW_SID:-$CUR_CDB}"
    local pdb="${NEW_PDB:-$CUR_PDB}"

    # Use short cluster name (not OCID) for display name
    if [[ "$cluster" =~ ^ocid1\. ]]; then
        cluster="$CUR_CLUSTER"
    fi

    if [[ -n "$cluster" ]]; then
        printf '%s_%s_%s' "$cluster" "$cdb" "$pdb"
    else
        printf '%s_%s' "$cdb" "$pdb"
    fi
}

# ------------------------------------------------------------------------------
# Function: compute_new_db_details
# Purpose.: Build new database-details JSON (PUT semantics: merge current + patches)
# Args....: None
# Returns.: 0 on success
# Output..: merged database-details JSON to stdout
# ------------------------------------------------------------------------------
compute_new_db_details() {
    local pdb_name="${NEW_PDB:-$CUR_PDB}"
    local patch="{}"

    # New cluster OCID — use kebab-case to match OCI response format so jq '. + $patch'
    # overwrites the existing key instead of adding a duplicate camelCase key alongside it
    if [[ -n "$CLUSTER_OCID" ]]; then
        patch=$(printf '%s' "$patch" | jq --arg v "$CLUSTER_OCID" '. + {"vm-cluster-id": $v}')
    fi

    # New PDB OCID
    if [[ -n "$PLUGGABLE_DB_OCID" ]]; then
        patch=$(printf '%s' "$patch" | jq --arg v "$PLUGGABLE_DB_OCID" '. + {"pluggable-database-id": $v}')
    fi

    # Explicit service name
    if [[ -n "$NEW_SERVICE" ]]; then
        patch=$(printf '%s' "$patch" | jq --arg v "$NEW_SERVICE" '. + {"service-name": $v}')
    fi

    # Port
    if [[ -n "$NEW_PORT" ]]; then
        patch=$(printf '%s' "$patch" | jq --argjson v "$NEW_PORT" '. + {"listener-port": $v}')
    fi

    # --from-oci: query OCI PDB for service name and port
    if [[ "$FROM_OCI" == "true" ]]; then
        local oci_result
        if oci_result=$(oci_lookup_pdb_connection "$pdb_name" "$PDB_COMPARTMENT_OCID"); then
            local oci_service oci_port
            IFS='|' read -r oci_service oci_port <<< "$oci_result"
            log_info "OCI PDB connection: service='$oci_service' port='$oci_port'"
            patch=$(printf '%s' "$patch" | jq --arg s "$oci_service" --argjson p "$oci_port" \
                '. + {"service-name": $s, "listener-port": $p}')
        else
            log_warn "OCI PDB lookup failed for '$pdb_name' — service/port unchanged"
        fi
    fi

    # Merge patch into current database-details (PUT semantics)
    printf '%s' "$CUR_DB_DETAILS" | jq --argjson patch "$patch" '. + $patch'
}

# ------------------------------------------------------------------------------
# Function: show_reregister_plan
# Purpose.: Display what will change (current vs new)
# Args....: $1 - new display name
#           $2 - new database-details JSON
# Returns.: 0
# ------------------------------------------------------------------------------
show_reregister_plan() {
    local new_display_name="$1"
    local new_db_details="$2"

    log_info "Re-register Plan for: $CUR_DISPLAY_NAME ($TARGET_OCID)"
    log_info "  Display Name:  '$CUR_DISPLAY_NAME' → '$new_display_name'"

    if [[ -n "$NEW_DESCRIPTION" ]]; then
        log_info "  Description:   '${CUR_DESCRIPTION:-(empty)}' → '$NEW_DESCRIPTION'"
    fi

    local cur_service cur_port new_service_v new_port_v
    cur_service=$(printf '%s' "$CUR_DB_DETAILS" | jq -r '."service-name" // .serviceName // "(unknown)"')
    cur_port=$(printf '%s' "$CUR_DB_DETAILS" | jq -r '."listener-port" // .listenerPort // "(unknown)"')
    new_service_v=$(printf '%s' "$new_db_details" | jq -r '."service-name" // .serviceName // "(unknown)"')
    new_port_v=$(printf '%s' "$new_db_details" | jq -r '."listener-port" // .listenerPort // "(unknown)"')

    local cur_vm_cluster new_vm_cluster
    cur_vm_cluster=$(printf '%s' "$CUR_DB_DETAILS" | jq -r '."vm-cluster-id" // .vmClusterId // "(none)"')
    new_vm_cluster=$(printf '%s' "$new_db_details" | jq -r '."vm-cluster-id" // .vmClusterId // "(none)"')

    local cur_pdb_ocid new_pdb_ocid
    cur_pdb_ocid=$(printf '%s' "$CUR_DB_DETAILS" | jq -r '."pluggable-database-id" // .pluggableDatabaseId // "(none)"')
    new_pdb_ocid=$(printf '%s' "$new_db_details" | jq -r '."pluggable-database-id" // .pluggableDatabaseId // "(none)"')

    [[ "$cur_vm_cluster" != "$new_vm_cluster" ]] \
        && log_info "  VM Cluster:    '$cur_vm_cluster' → '$new_vm_cluster'"
    [[ "$cur_pdb_ocid" != "$new_pdb_ocid" ]] \
        && log_info "  PDB OCID:      '$cur_pdb_ocid' → '$new_pdb_ocid'"
    [[ "$cur_service" != "$new_service_v" ]] \
        && log_info "  Service:       '$cur_service' → '$new_service_v'"
    [[ "$cur_port" != "$new_port_v" ]] \
        && log_info "  Port:          $cur_port → $new_port_v"

    if [[ -n "$DS_SECRET" ]]; then
        local ds_user_for_target
        ds_user_for_target=$(resolve_ds_user_for_target)
        log_info "  Credentials:   will update for user '$ds_user_for_target'"
    fi
}

# ------------------------------------------------------------------------------
# Function: cleanup_temp_files
# Purpose.: Remove temporary credential files
# Returns.: 0
# ------------------------------------------------------------------------------
cleanup_temp_files() {
    if [[ -n "$TMP_CRED_JSON" && -f "$TMP_CRED_JSON" ]]; then
        rm -f "$TMP_CRED_JSON"
        TMP_CRED_JSON=""
    fi
}

# ------------------------------------------------------------------------------
# Function: do_reregister
# Purpose.: Execute the OCI updates for database-details, display name, credentials
# Args....: $1 - new display name
#           $2 - new database-details JSON
# Returns.: 0 on success, 2 on error
# ------------------------------------------------------------------------------
do_reregister() {
    local new_display_name="$1"
    local new_db_details="$2"

    trap cleanup_temp_files EXIT

    # --- Structural update (database-details + display-name + description) ---
    local -a cmd=(
        data-safe target-database update
        --target-database-id "$TARGET_OCID"
        --display-name "$new_display_name"
        --database-details "$new_db_details"
        --force
    )

    if [[ -n "$NEW_DESCRIPTION" ]]; then
        cmd+=(--description "$NEW_DESCRIPTION")
    fi

    if [[ -n "$WAIT_STATE" ]]; then
        cmd+=(--wait-for-state "$WAIT_STATE")
    fi

    log_info "Applying structural update..."
    if oci_exec "${cmd[@]}" > /dev/null; then
        log_info "Structural update successful"
    else
        log_error "Structural update failed for: $CUR_DISPLAY_NAME"
        die "Re-registration failed" 2
    fi

    # --- Optional credential update ---
    if [[ -n "$DS_SECRET" ]]; then
        local ds_user_for_target
        ds_user_for_target=$(resolve_ds_user_for_target)

        TMP_CRED_JSON=$(mktemp)
        ds_write_cred_json_file "$TMP_CRED_JSON" "$ds_user_for_target" "$DS_SECRET"

        local -a cred_cmd=(
            data-safe target-database update
            --target-database-id "$TARGET_OCID"
            --credentials "file://${TMP_CRED_JSON}"
            --force
        )

        if [[ -n "$WAIT_STATE" ]]; then
            cred_cmd+=(--wait-for-state "$WAIT_STATE")
        fi

        log_info "Updating credentials for user: $ds_user_for_target"
        if oci_exec "${cred_cmd[@]}" > /dev/null; then
            log_info "Credentials updated successfully"
        else
            log_error "Credentials update failed for: $new_display_name"
            die "Credential update failed" 2
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Orchestrate validation, planning, and execution
# Args....: None
# Returns.: 0 on success
# ------------------------------------------------------------------------------
do_work() {
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: No changes will be applied (use --apply to apply)"
    fi

    validate_inputs

    # Compute new values
    local new_display_name
    new_display_name=$(compute_new_display_name)

    local new_db_details
    new_db_details=$(compute_new_db_details)

    # Show plan
    show_reregister_plan "$new_display_name" "$new_db_details"

    if [[ "$APPLY_CHANGES" != "true" ]]; then
        log_info "Dry-run complete — use --apply to execute"
        return 0
    fi

    do_reregister "$new_display_name" "$new_db_details"
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    setup_error_handling

    if do_work; then
        if [[ "$APPLY_CHANGES" == "true" ]]; then
            log_info "Re-registration completed successfully"
        fi
    else
        die "Re-registration failed"
    fi
}

# Parse arguments, then run
if [[ $# -eq 0 ]]; then
    usage 0
fi

parse_args "$@"
main

# --- End of ds_target_reregister.sh -------------------------------------------
