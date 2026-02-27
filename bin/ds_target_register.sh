#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_register.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose....: Register a database as Oracle Data Safe target
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Purpose:
#   Register a single database (PDB or CDB$ROOT) as a Data Safe target without
#   requiring SSH access. Uses OCI CLI to create target with JSON payload.
#
# Usage:
#   ds_target_register.sh --host <host> --sid <sid> --pdb <pdb> [options]
#   ds_target_register.sh --host <host> --sid <sid> --root [options]
#
# Options:
#   -H, --host HOST             Database host (required)
#   --sid SID                   Database SID (required)
#   --pdb PDB                   PDB name (required unless --root)
#   --root                      Register CDB$ROOT instead of PDB
#   -c, --compartment COMP      Target compartment (required)
#   --connector CONN            On-premises connector name or OCID (required)
#   --port PORT                 Listener port (default: 1521)
#   --service SERVICE           Service name (default: auto-derived)
#   --ds-user USER              Data Safe user (default: DS_ADMIN)
#   --ds-secret VALUE           Data Safe secret (required)
#   --secret-file FILE          Base64 secret file (optional)
#   -N, --display-name NAME     Display name (default: auto-generated)
#   --description DESC          Description
#   --cluster CLUSTER           VM Cluster name or OCID (optional)
#   --check                     Only check if target exists
#   -n, --dry-run               Show plan without registering
#   -h, --help                  Show help
#
# Exit Codes:
#   0 = Success
#   1 = Input validation error
#   2 = Registration error
# ------------------------------------------------------------------------------

# Bootstrap - locate library files (must be before version check)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Script identification
SCRIPT_NAME="ds_target_register"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"

# Load framework libraries
if [[ ! -f "${LIB_DIR}/ds_lib.sh" ]]; then
    echo "[ERROR] Cannot find ds_lib.sh in ${LIB_DIR}" >&2
    exit 1
fi
source "${LIB_DIR}/ds_lib.sh"

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
HOST=""
SID=""
PDB=""
RUN_ROOT=false
COMPARTMENT=""
CONNECTOR=""
CONNECTOR_COMPARTMENT=""
LISTENER_PORT="1521"
SERVICE_NAME=""
DS_USER="DS_ADMIN"
DS_SECRET="${DATASAFE_SECRET:-}"
DATASAFE_SECRET_FILE="${DATASAFE_SECRET_FILE:-}"
COMMON_USER_PREFIX="${COMMON_USER_PREFIX:-C##}"
DISPLAY_NAME=""
DESCRIPTION=""
CLUSTER=""
CHECK_ONLY=false
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime
COMP_OCID=""
CONNECTOR_OCID=""
CLUSTER_OCID=""
PLUGGABLE_DB_OCID=""

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Args....: $1 - Exit code (optional, default: 0)
# Returns.: Exits with specified code
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    local exit_code=${1:-0}
    cat << EOF
Usage: ${SCRIPT_NAME} [options]

DESCRIPTION:
    Register a database (PDB or CDB\$ROOT) as an Oracle Data Safe target.
    Requires on-premises connector for cloud-at-customer deployments.

SCOPE (choose one):
    --pdb PDB                           Register a specific PDB
    --root                              Register CDB\$ROOT (named CDBROOT)

REQUIRED OPTIONS:
    -H, --host HOST                     Database host name (required with --cluster as alternative)
        --cluster CLUSTER               VM Cluster name or OCID (required with --host as alternative)
        --sid SID                       Database SID
    -c, --compartment COMP              Target compartment (name or OCID)
                                        Default: resource compartment from --host/--cluster,
                                        then DS_REGISTER_COMPARTMENT or DS_ROOT_COMP
        --connector CONN                On-premises connector (name or OCID)
                                        Default: ONPREM_CONNECTOR(_OCID) or random from
                                        ONPREM_CONNECTOR_LIST / DS_ONPREM_CONNECTOR_LIST
    -P, --ds-secret VALUE               Data Safe secret (plain or base64)
        --secret-file FILE              Base64 secret file (optional)

SECRET FILE SUPPORT:
    - Uses DATASAFE_SECRET_FILE if set
    - Otherwise looks for <ds-user>_pwd.b64 in ORADBA_ETC or $ODB_DATASAFE_BASE/etc

CONNECTION:
        --port PORT                     Listener port (default: 1521)
        --service SERVICE               Service name (default: auto-derived from PDB/SID)
        --ds-user USER                  Data Safe user (default: DS_ADMIN)
        --connector-compartment COMP    Compartment to search for connector (default: same as -c)

METADATA:
    -N, --display-name NAME             Display name (default: <cluster>_<sid>_<pdb|CDBROOT>)
        --description DESC              Free text description

MODES:
        --check                         Only check if target already exists
    -n, --dry-run                       Show registration plan without executing
    -h, --help                          Show this help

EXAMPLES:
    # Register a PDB
    ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \\
    -c prod-compartment --connector my-connector --ds-secret <secret>
    
    # Register CDB\$ROOT
    ds_target_register.sh -H db01 --sid cdb01 --root \\
    -c prod-compartment --connector my-connector --ds-secret <secret>
    
    # Check if target exists
    ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \\
    -c prod-compartment --connector my-connector --check

EXIT CODES:
    0 = Success
    1 = Input validation error
    2 = Registration error

EOF
    exit "$exit_code"
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success
# Output..: None (sets global variables)
# ------------------------------------------------------------------------------
parse_args() {
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -H | --host)
                HOST="$2"
                shift 2
                ;;
            --sid)
                SID="$2"
                shift 2
                ;;
            --pdb)
                PDB="$2"
                shift 2
                ;;
            --root)
                RUN_ROOT=true
                shift
                ;;
            -c | --compartment)
                COMPARTMENT="$2"
                shift 2
                ;;
            --connector)
                CONNECTOR="$2"
                shift 2
                ;;
            --connector-compartment)
                CONNECTOR_COMPARTMENT="$2"
                shift 2
                ;;
            --port)
                LISTENER_PORT="$2"
                shift 2
                ;;
            --service)
                SERVICE_NAME="$2"
                shift 2
                ;;
            --ds-user)
                DS_USER="$2"
                shift 2
                ;;
            -P | --ds-secret)
                DS_SECRET="$2"
                shift 2
                ;;
            --secret-file)
                DATASAFE_SECRET_FILE="$2"
                shift 2
                ;;
            -N | --display-name)
                DISPLAY_NAME="$2"
                shift 2
                ;;
            --description)
                DESCRIPTION="$2"
                shift 2
                ;;
            --cluster)
                CLUSTER="$2"
                shift 2
                ;;
            --check)
                CHECK_ONLY=true
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --oci-config)
                export OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            --oci-profile)
                export OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            -h | --help)
                usage 0
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Function: trim_whitespace
# Purpose.: Trim leading/trailing whitespace from a string
# Args....: $1 - input string
# Returns.: 0
# Output..: trimmed string
# ------------------------------------------------------------------------------
trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# ------------------------------------------------------------------------------
# Function: collect_search_compartment_ocids
# Purpose.: Build candidate compartment OCID list for OCI resource discovery
# Args....: None (uses COMP_OCID/COMPARTMENT/DS_REGISTER_COMPARTMENT/DS_ROOT_COMP)
# Returns.: 0
# Output..: newline-separated compartment OCIDs
# ------------------------------------------------------------------------------
collect_search_compartment_ocids() {
    local scopes=""
    local candidate
    local resolved

    for candidate in "${COMP_OCID:-}" "${COMPARTMENT:-}" "${DS_REGISTER_COMPARTMENT:-}" "${DS_ROOT_COMP:-}"; do
        [[ -z "$candidate" ]] && continue
        if is_ocid "$candidate"; then
            resolved="$candidate"
        else
            resolved=$(oci_resolve_compartment_ocid "$candidate" 2> /dev/null || true)
        fi
        [[ -z "$resolved" ]] && continue
        if ! grep -Fqx "$resolved" <<< "$scopes"; then
            scopes+="${resolved}"$'\n'
        fi
    done

    if [[ -z "$scopes" ]]; then
        resolved=$(get_root_compartment_ocid 2> /dev/null || true)
        if [[ -n "$resolved" ]]; then
            scopes+="${resolved}"$'\n'
        fi
    fi

    printf '%s' "$scopes"
}

# ------------------------------------------------------------------------------
# Function: resolve_default_connector
# Purpose.: Resolve default connector when --connector is not provided
# Args....: None
# Returns.: 0 on success, 1 on failure
# Output..: connector name/OCID on stdout
# Notes...: Precedence: ONPREM_CONNECTOR_OCID -> ONPREM_CONNECTOR ->
#           ONPREM_CONNECTOR_LIST/DS_ONPREM_CONNECTOR_LIST (random pick)
# ------------------------------------------------------------------------------
resolve_default_connector() {
    if [[ -n "${ONPREM_CONNECTOR_OCID:-}" ]]; then
        printf '%s' "${ONPREM_CONNECTOR_OCID}"
        return 0
    fi

    if [[ -n "${ONPREM_CONNECTOR:-}" ]]; then
        printf '%s' "${ONPREM_CONNECTOR}"
        return 0
    fi

    local connector_list="${ONPREM_CONNECTOR_LIST:-${DS_ONPREM_CONNECTOR_LIST:-}}"
    if [[ -z "$connector_list" ]]; then
        return 1
    fi

    local -a raw_connectors=()
    local -a connectors=()
    local raw_connector

    IFS=',' read -r -a raw_connectors <<< "$connector_list"
    for raw_connector in "${raw_connectors[@]}"; do
        local connector_value
        connector_value="$(trim_whitespace "$raw_connector")"
        [[ -n "$connector_value" ]] && connectors+=("$connector_value")
    done

    if [[ ${#connectors[@]} -eq 0 ]]; then
        return 1
    fi

    local selected_index=$((RANDOM % ${#connectors[@]}))
    log_debug "Selecting connector randomly from configured list (${#connectors[@]} entries)"
    printf '%s' "${connectors[$selected_index]}"
}

# ------------------------------------------------------------------------------
# Function: resolve_compartment_from_cluster
# Purpose.: Resolve compartment OCID from VM cluster reference
# Args....: $1 - cluster name or OCID
# Returns.: 0 on success, 1 on failure
# Output..: compartment OCID to stdout
# ------------------------------------------------------------------------------
resolve_compartment_from_cluster() {
    local cluster_ref="$1"

    [[ -z "$cluster_ref" ]] && return 1

    local vm_cluster_ocid
    vm_cluster_ocid=$(resolve_vm_cluster_ocid 2> /dev/null || true)
    [[ -z "$vm_cluster_ocid" ]] && return 1

    resolve_vm_cluster_compartment_ocid "$vm_cluster_ocid"
}

# ------------------------------------------------------------------------------
# Function: resolve_compartment_from_host
# Purpose.: Resolve compartment OCID from DB host name
# Args....: $1 - host name
# Returns.: 0 on success, 1 on failure
# Output..: compartment OCID to stdout
# ------------------------------------------------------------------------------
resolve_compartment_from_host() {
    local host_name="$1"
    [[ -z "$host_name" ]] && return 1

    local esc
    esc="${host_name//\'/\'\\\'}"

    local out
    local resolved_comp
    out=$(oci_structured_search_query "query DbNode resources where displayName = '${esc}'" 10 2> /dev/null || true)
    resolved_comp=$(jq -r '
        (.data.items // [])
        | map(."compartment-id" // .compartmentId // empty)
        | first // empty
    ' <<< "$out")
    if [[ -n "$resolved_comp" && "$resolved_comp" != "null" ]]; then
        printf '%s\n' "$resolved_comp"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: resolve_vm_cluster_ocid
# Purpose.: Resolve VM cluster OCID from explicit cluster or host fallback
# Args....: None (uses CLUSTER/HOST/COMP_OCID globals)
# Returns.: 0 on success, 1 on failure
# Output..: VM cluster OCID to stdout
# ------------------------------------------------------------------------------
resolve_vm_cluster_ocid() {
    local cluster_ref="${CLUSTER:-}"

    if [[ -n "$cluster_ref" ]]; then
        if [[ "$cluster_ref" =~ ^ocid1\.(cloudvmcluster|vmcluster)\. ]]; then
            printf '%s' "$cluster_ref"
            return 0
        fi

        local resolved_cluster
        local cluster_esc
        cluster_esc="${cluster_ref//\'/\'\\\'}"
        local search_out
        search_out=$(oci_structured_search_query "query all resources where displayName = '${cluster_esc}'" 50 2> /dev/null || true)
        resolved_cluster=$(jq -r '
            (.data.items // [])
            | map(.identifier // .id // empty)
            | map(select(test("^ocid1\\.(vmcluster|cloudvmcluster)\\.")))
            | first // empty
        ' <<< "$search_out")
        if [[ -n "$resolved_cluster" && "$resolved_cluster" != "null" ]]; then
            printf '%s' "$resolved_cluster"
            return 0
        fi

        # Fallback for environments without OCI Search permissions:
        # try classic DB list calls only in configured/known scopes.
        local scope_ocids
        scope_ocids=$(collect_search_compartment_ocids)
        local scope_comp
        while IFS= read -r scope_comp; do
            [[ -z "$scope_comp" ]] && continue

            local vm_clusters_json
            vm_clusters_json=$(oci_exec_ro db vm-cluster list \
                --compartment-id "$scope_comp" \
                --all 2> /dev/null || true)
            if [[ -n "$vm_clusters_json" ]]; then
                resolved_cluster=$(echo "$vm_clusters_json" | jq -r --arg cluster "$cluster_ref" '
                    .data[]
                    | select((."display-name" // "") == $cluster)
                    | .id
                ' | head -n1)
                if [[ -n "$resolved_cluster" && "$resolved_cluster" != "null" ]]; then
                    printf '%s' "$resolved_cluster"
                    return 0
                fi
            fi

            local cloud_vm_clusters_json
            cloud_vm_clusters_json=$(oci_exec_ro db cloud-vm-cluster list \
                --compartment-id "$scope_comp" \
                --all 2> /dev/null || true)
            if [[ -n "$cloud_vm_clusters_json" ]]; then
                resolved_cluster=$(echo "$cloud_vm_clusters_json" | jq -r --arg cluster "$cluster_ref" '
                    .data[]
                    | select((."display-name" // "") == $cluster)
                    | .id
                ' | head -n1)
                if [[ -n "$resolved_cluster" && "$resolved_cluster" != "null" ]]; then
                    printf '%s' "$resolved_cluster"
                    return 0
                fi
            fi
        done <<< "$scope_ocids"
    fi

    if [[ -n "${HOST:-}" ]]; then
        local host_esc
        host_esc="${HOST//\'/\'\\\'}"
        local search_out
        local resolved_from_host

        search_out=$(oci_structured_search_query "query DbNode resources where displayName = '${host_esc}'" 10 2> /dev/null || true)
        resolved_from_host=$(jq -r '
            (.data.items // [])
            | map(.additionalDetails // ."additional-details" // {})
            | map(.vmClusterId // ."vm-cluster-id" // .cloudVmClusterId // ."cloud-vm-cluster-id" // empty)
            | first // empty
        ' <<< "$search_out")
        if [[ -n "$resolved_from_host" && "$resolved_from_host" != "null" ]]; then
            printf '%s' "$resolved_from_host"
            return 0
        fi
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: resolve_vm_cluster_compartment_ocid
# Purpose.: Resolve compartment OCID from VM cluster OCID
# Args....: $1 - VM cluster OCID
# Returns.: 0 on success, 1 on failure
# Output..: compartment OCID
# ------------------------------------------------------------------------------
resolve_vm_cluster_compartment_ocid() {
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

# ------------------------------------------------------------------------------
# Function: resolve_pluggable_db_ocid
# Purpose.: Resolve pluggable database OCID for PDB scope
# Args....: None (uses PDB/SID/COMP_OCID/CLUSTER_OCID globals)
# Returns.: 0 on success, 1 on failure
# Output..: Pluggable database OCID to stdout
# ------------------------------------------------------------------------------
resolve_pluggable_db_ocid() {
    [[ -z "${PDB:-}" ]] && return 1

    local databases_json
    databases_json=$(oci_exec_ro db database list \
        --compartment-id "$COMP_OCID" \
        --all 2> /dev/null || true)
    [[ -n "$databases_json" ]] || return 1

    local database_id
    database_id=$(echo "$databases_json" | jq -r \
        --arg sid "${SID:-}" \
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

    echo "$pdbs_json" | jq -r --arg pdb "$PDB" '
        .data[]
        | select(
            ((."pdb-name" // "" | ascii_downcase) == ($pdb | ascii_downcase))
            or ((."pdb-name" // "" | ascii_downcase) == (($pdb | ascii_downcase) + "_"))
            or ((."display-name" // "" | ascii_downcase) == ($pdb | ascii_downcase))
        )
        | .id
    ' | head -n1
}

# Function: resolve_ds_user
# Purpose.: Resolve Data Safe username for scope
# Args....: $1 - Scope label (PDB or ROOT)
# Returns.: 0 on success
# Output..: Username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user() {
    local scope="$1"
    local base_user="$DS_USER"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_user" == ${COMMON_USER_PREFIX}* ]]; then
        base_user="${base_user#${COMMON_USER_PREFIX}}"
    fi

    if [[ "$scope" == "ROOT" ]]; then
        if [[ -n "$COMMON_USER_PREFIX" ]]; then
            printf '%s' "${COMMON_USER_PREFIX}${base_user}"
            return 0
        fi
    fi

    printf '%s' "$base_user"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line inputs and resolve OCIDs
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Info messages about resolved resources
# Notes...: Sets COMP_OCID, COMP_NAME, CONNECTOR_OCID, SERVICE_NAME, DISPLAY_NAME,
#           CLUSTER_OCID, PLUGGABLE_DB_OCID
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Required fields
    [[ -z "$HOST" && -z "$CLUSTER" ]] && die "Missing resource identifier. Specify --host or --cluster"
    [[ -z "$SID" ]] && die "Missing required option: --sid"

    if CLUSTER_OCID=$(resolve_vm_cluster_ocid 2> /dev/null || true); then
        if [[ -n "$CLUSTER_OCID" ]]; then
            log_debug "Resolved VM cluster OCID from host/cluster input: ${CLUSTER_OCID}"
            if [[ -z "$COMPARTMENT" ]]; then
                local vm_cluster_compartment
                vm_cluster_compartment=$(resolve_vm_cluster_compartment_ocid "$CLUSTER_OCID" 2> /dev/null || true)
                if [[ -n "$vm_cluster_compartment" && "$vm_cluster_compartment" != "null" ]]; then
                    COMPARTMENT="$vm_cluster_compartment"
                    log_info "Using compartment derived from VM cluster: ${COMPARTMENT}"
                fi
            fi
        fi
    fi

    if [[ -z "$COMPARTMENT" ]]; then
        local derived_compartment=""

        if [[ -n "$HOST" ]]; then
            derived_compartment=$(resolve_compartment_from_host "$HOST" 2> /dev/null || true)
            if [[ -n "$derived_compartment" ]]; then
                COMPARTMENT="$derived_compartment"
                log_info "Using compartment derived from host '$HOST': $COMPARTMENT"
            fi
        fi

        if [[ -z "$COMPARTMENT" && -n "$CLUSTER" ]]; then
            derived_compartment=$(resolve_compartment_from_cluster "$CLUSTER" 2> /dev/null || true)
            if [[ -n "$derived_compartment" ]]; then
                COMPARTMENT="$derived_compartment"
                log_info "Using compartment derived from cluster '$CLUSTER': $COMPARTMENT"
            fi
        fi

        if [[ -z "$COMPARTMENT" ]]; then
            COMPARTMENT="${DS_REGISTER_COMPARTMENT:-${DS_ROOT_COMP:-}}"
            [[ -n "$COMPARTMENT" ]] || die "Missing target compartment. Use --compartment or provide resolvable --host/--cluster"
            log_warn "Could not derive compartment from resource; using configured default: $COMPARTMENT"
        fi
    fi

    if [[ -z "$CONNECTOR" ]]; then
        CONNECTOR="$(resolve_default_connector)" || die "Missing connector. Use --connector or configure ONPREM_CONNECTOR(_OCID) / ONPREM_CONNECTOR_LIST"
        log_info "Using default connector: $CONNECTOR"
    fi

    # Scope validation
    if [[ -z "$PDB" && "$RUN_ROOT" != "true" ]]; then
        die "Specify scope: --pdb <name> OR --root"
    fi

    if [[ -n "$PDB" && "$RUN_ROOT" == "true" ]]; then
        die "Choose exactly one scope: --pdb OR --root (not both)"
    fi

    if [[ "$RUN_ROOT" == "true" ]]; then
        DS_USER="$(resolve_ds_user "ROOT")"
    else
        DS_USER="$(resolve_ds_user "PDB")"
    fi

    if [[ "$CHECK_ONLY" != "true" && -n "$DS_SECRET" ]]; then
        local is_b64="false"
        if is_base64_string "$DS_SECRET"; then
            is_b64="true"
        fi
        DS_SECRET=$(normalize_secret_value "$DS_SECRET") || die "Failed to decode base64 secret"
        [[ -n "$DS_SECRET" ]] || die "Decoded secret is empty"
        if [[ "$is_b64" == "true" ]]; then
            log_info "Decoded Data Safe secret from base64 input"
        fi
    fi

    # Resolve secret from file if needed (explicit file or <user>_pwd.b64)
    if [[ "$CHECK_ONLY" != "true" && -z "$DS_SECRET" ]]; then
        local secret_file=""
        if secret_file=$(find_password_file "$DS_USER" "${DATASAFE_SECRET_FILE:-}"); then
            require_cmd base64
            DS_SECRET=$(decode_base64_file "$secret_file") || die "Failed to decode base64 secret file: $secret_file"
            DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")
            [[ -n "$DS_SECRET" ]] || die "Secret file is empty: $secret_file"
            log_info "Loaded Data Safe secret from file: $secret_file"
        fi
    fi

    # Secret required unless check-only
    if [[ "$CHECK_ONLY" != "true" && -z "$DS_SECRET" ]]; then
        die "Missing required option: --ds-secret (not needed with --check)"
    fi

    # Resolve compartment using helper function (accepts name or OCID)
    resolve_compartment_to_vars "$COMPARTMENT" "COMP" \
        || die "Failed to resolve compartment: $COMPARTMENT"
    log_info "Target compartment: ${COMP_NAME} (${COMP_OCID})"

    if [[ -z "$CLUSTER_OCID" ]]; then
        if CLUSTER_OCID=$(resolve_vm_cluster_ocid); then
            log_info "Resolved VM cluster OCID: ${CLUSTER_OCID}"
        else
            if [[ "$RUN_ROOT" == "true" ]]; then
                if [[ "${DRY_RUN:-false}" == "true" ]]; then
                    log_warn "Dry-run: unable to resolve VM cluster OCID. Payload will omit vmClusterId and create would fail until cluster is resolved."
                    log_warn "Provide --cluster <ocid1.vmcluster...|ocid1.cloudvmcluster...> or ensure lookup permissions/scope."
                else
                    die "Failed to resolve VM cluster OCID. Provide a valid --cluster (name or OCID) or ensure host lookup is possible."
                fi
            fi
            log_warn "Could not resolve VM cluster OCID for PDB scope; will rely on pluggable DB lookup"
        fi
    else
        log_info "Resolved VM cluster OCID: ${CLUSTER_OCID}"
    fi

    if [[ "$RUN_ROOT" != "true" ]]; then
        if PLUGGABLE_DB_OCID=$(resolve_pluggable_db_ocid); then
            log_info "Resolved pluggable DB OCID: ${PLUGGABLE_DB_OCID}"
        else
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                log_warn "Dry-run: unable to resolve pluggable database OCID for SID '${SID}' and PDB '${PDB}'."
            else
                die "Failed to resolve pluggable database OCID for SID '${SID}' and PDB '${PDB}'"
            fi
        fi
    fi

    # Resolve connector OCID (accept name or OCID)
    if [[ "$CONNECTOR" =~ ^ocid1\.datasafeonpremconnector\. ]]; then
        CONNECTOR_OCID="$CONNECTOR"
        log_debug "Connector OCID provided directly"
    else
        # Determine which compartment to search for connector
        local connector_search_comp
        if [[ -n "${CONNECTOR_COMPARTMENT:-}" ]]; then
            # Use explicit connector compartment
            if is_ocid "$CONNECTOR_COMPARTMENT"; then
                connector_search_comp="$CONNECTOR_COMPARTMENT"
            else
                connector_search_comp=$(oci_resolve_compartment_ocid "$CONNECTOR_COMPARTMENT") \
                    || die "Failed to resolve connector compartment: $CONNECTOR_COMPARTMENT"
            fi
            log_debug "Using explicit connector compartment: $CONNECTOR_COMPARTMENT"
        else
            # Use helper function (DS_CONNECTOR_COMP -> DS_ROOT_COMP -> target compartment)
            connector_search_comp=$(get_connector_compartment_ocid 2> /dev/null || echo "$COMP_OCID")
            log_debug "Using default connector compartment"
        fi

        # Try to find connector by name using read-only operation
        log_debug "Resolving connector name: ${CONNECTOR}"
        local connectors_json
        connectors_json=$(oci_exec_ro data-safe on-prem-connector list \
            --compartment-id "$connector_search_comp" \
            --compartment-id-in-subtree true \
            --all) || die "Failed to list connectors"

        CONNECTOR_OCID=$(echo "$connectors_json" | jq -r ".data[] | select(.\"display-name\" == \"$CONNECTOR\") | .id" | head -n1)

        if [[ -z "$CONNECTOR_OCID" ]]; then
            die "Connector not found: $CONNECTOR in compartment"
        fi
        log_debug "Resolved connector: ${CONNECTOR} -> ${CONNECTOR_OCID}"
    fi
    log_info "On-premises connector: ${CONNECTOR} (${CONNECTOR_OCID})"

    # Derive service name if not provided
    if [[ -z "$SERVICE_NAME" ]]; then
        if [[ "$RUN_ROOT" == "true" ]]; then
            SERVICE_NAME="${SID}"
        else
            SERVICE_NAME="${PDB}"
        fi
        log_info "Auto-derived service name: $SERVICE_NAME"
    fi

    # Generate display name if not provided
    if [[ -z "$DISPLAY_NAME" ]]; then
        local scope_name
        if [[ "$RUN_ROOT" == "true" ]]; then
            scope_name="CDBROOT"
        else
            scope_name="$PDB"
        fi

        if [[ -n "$CLUSTER" ]]; then
            DISPLAY_NAME="${CLUSTER}_${SID}_${scope_name}"
        else
            DISPLAY_NAME="${HOST}_${SID}_${scope_name}"
        fi
        log_info "Auto-generated display name: $DISPLAY_NAME"
    fi

    log_info "Registration plan validated"
}

# ------------------------------------------------------------------------------
# Function: check_target_exists
# Purpose.: Check if a target with the display name already exists
# Args....: None
# Returns.: 0 if target exists, 1 if not found
# Output..: Info messages about target existence
# ------------------------------------------------------------------------------
check_target_exists() {
    log_info "Checking if target already exists..."

    local targets_json
    targets_json=$(ds_list_targets "$COMP_OCID") || die "Failed to list targets"

    local existing_target
    existing_target=$(echo "$targets_json" | jq -r ".data[] | select(.\"display-name\" == \"$DISPLAY_NAME\") | .id" | head -n1)

    if [[ -n "$existing_target" ]]; then
        log_info "Target already exists: $DISPLAY_NAME ($existing_target)"
        return 0
    else
        log_info "Target does not exist: $DISPLAY_NAME"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function: show_registration_plan
# Purpose.: Display the registration plan summary
# Args....: None
# Returns.: 0 on success
# Output..: Registration plan details to log
# ------------------------------------------------------------------------------
show_registration_plan() {
    local scope
    if [[ "$RUN_ROOT" == "true" ]]; then
        scope="CDB\$ROOT (CDBROOT)"
    else
        scope="PDB: $PDB"
    fi

    log_info "Registration Plan:"
    log_info "  Scope:         $scope"
    log_info "  Host:          $HOST"
    log_info "  SID:           $SID"
    log_info "  Service:       $SERVICE_NAME"
    log_info "  Port:          $LISTENER_PORT"
    log_info "  Display Name:  $DISPLAY_NAME"
    log_info "  Compartment:   $COMP_OCID"
    log_info "  Connector:     $CONNECTOR_OCID"
    log_info "  DS User:       $DS_USER"
    log_info "  DS Secret:     [hidden]"

    if [[ -n "$CLUSTER" ]]; then
        log_info "  Cluster:       $CLUSTER"
    fi
    if [[ -n "$CLUSTER_OCID" ]]; then
        log_info "  VM Cluster ID: ${CLUSTER_OCID}"
    fi
    if [[ -n "$PLUGGABLE_DB_OCID" ]]; then
        log_info "  PDB OCID:      ${PLUGGABLE_DB_OCID}"
    fi

    if [[ -n "$DESCRIPTION" ]]; then
        log_info "  Description:   $DESCRIPTION"
    fi
}

# ------------------------------------------------------------------------------
# Function: register_target
# Purpose.: Register the target database in Data Safe
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Success/error messages
# Notes...: Creates JSON payload and executes OCI CLI command
# ------------------------------------------------------------------------------
register_target() {
    log_info "Creating Data Safe target registration..."

    # Create JSON payload
    local json_file="${TMPDIR:-/tmp}/ds_target_${DISPLAY_NAME//[^a-zA-Z0-9]/_}.json"
    local pdb_name

    if [[ "$RUN_ROOT" == "true" ]]; then
        pdb_name="CDBROOT"
    else
        pdb_name="$PDB"
    fi

    local desc="${DESCRIPTION:-PDB ${pdb_name} on Database ${SID} at ${HOST}}"

    # Build database details JSON
    local db_details
    db_details=$(jq -n \
        --arg dbType "DATABASE_CLOUD_SERVICE" \
        --arg infra "CLOUD_AT_CUSTOMER" \
        --argjson port "$LISTENER_PORT" \
        --arg svc "$SERVICE_NAME" \
        --arg vmClusterId "$CLUSTER_OCID" \
        --arg pluggableDatabaseId "$PLUGGABLE_DB_OCID" \
        --arg runRoot "$RUN_ROOT" '
        {
            databaseType: $dbType,
            infrastructureType: $infra,
            listenerPort: $port,
            serviceName: $svc
        }
        | if ($vmClusterId != "") then . + {vmClusterId: $vmClusterId} else . end
        | if ($runRoot != "true" and $pluggableDatabaseId != "") then . + {pluggableDatabaseId: $pluggableDatabaseId} else . end
    ')

    # Create full payload
    jq -n \
        --arg comp "$COMP_OCID" \
        --arg name "$DISPLAY_NAME" \
        --arg desc "$desc" \
        --arg user "$DS_USER" \
        --arg pass "$DS_SECRET" \
        --arg conn "$CONNECTOR_OCID" \
        --argjson dbd "$db_details" \
        '{
            compartmentId: $comp,
            displayName: $name,
            description: $desc,
            credentials: {
                userName: $user,
                password: $pass
            },
            connectionOption: {
                connectionType: "ONPREM_CONNECTOR",
                onPremConnectorId: $conn
            },
            databaseDetails: $dbd
        }' > "$json_file"

    log_debug "JSON payload created: $json_file"
    if [[ "${DEBUG:-false}" == "true" || "${TRACE:-false}" == "true" ]]; then
        jq '.' "$json_file" | while IFS= read -r line; do
            log_debug "PAYLOAD: $line"
        done
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY-RUN: Would execute:"
        log_info "  oci data-safe target-database create --from-json file://$json_file"
        cat "$json_file" | jq '.' | while IFS= read -r line; do
            log_debug "  $line"
        done
        rm -f "$json_file"
        return 0
    fi

    # Execute registration using oci_exec (respects dry-run)
    local result
    result=$(oci_exec data-safe target-database create \
        --from-json "file://$json_file" \
        --wait-for-state SUCCEEDED \
        --wait-for-state FAILED) || {
        log_error "Registration failed"
        log_error "$result"
        log_warn "Keeping failed registration payload for analysis: $json_file"
        die "Target registration failed" 2
    }

    local target_id
    target_id=$(echo "$result" | jq -r '.data.id // empty')

    if [[ -n "$target_id" ]]; then
        log_info "Successfully registered target: $DISPLAY_NAME"
        log_info "Target OCID: $target_id"
    else
        log_warn "Registration command completed but could not extract target ID"
    fi

    rm -f "$json_file"
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, 1-2 on error
# Output..: Execution status and results
# ------------------------------------------------------------------------------
main() {
    # Initialize framework and parse arguments
    init_config
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
    parse_args "$@"

    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Show registration plan
    show_registration_plan

    # Handle check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        if check_target_exists; then
            exit 0
        else
            exit 1
        fi
    fi

    # Check if target already exists
    if check_target_exists; then
        log_warn "Target already exists. Use a different display name or remove existing target first."
        exit 0
    fi

    # Register target
    register_target

    log_info "Registration completed successfully"
}

# Run the script
main "$@"
