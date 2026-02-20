#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_register.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
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
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime
COMP_OCID=""
CONNECTOR_OCID=""
# shellcheck disable=SC2034  # CLUSTER_OCID reserved for future cluster discovery feature
CLUSTER_OCID=""

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
  --pdb PDB                 Register a specific PDB
  --root                    Register CDB\$ROOT (named CDBROOT)

REQUIRED OPTIONS:
  -H, --host HOST           Database host name
  --sid SID                 Database SID
  -c, --compartment COMP    Target compartment (name or OCID)
  --connector CONN          On-premises connector (name or OCID)
  -P, --ds-secret VALUE     Data Safe secret (plain or base64)
  --secret-file FILE        Base64 secret file (optional)

SECRET FILE SUPPORT:
  - Uses DATASAFE_SECRET_FILE if set
  - Otherwise looks for <ds-user>_pwd.b64 in ORADBA_ETC or $ODB_DATASAFE_BASE/etc

CONNECTION:
  --port PORT               Listener port (default: 1521)
  --service SERVICE         Service name (default: auto-derived from PDB/SID)
  --ds-user USER            Data Safe user (default: DS_ADMIN)
  --connector-compartment COMP Compartment to search for connector (default: same as -c)

METADATA:
  -N, --display-name NAME   Display name (default: <cluster>_<sid>_<pdb|CDBROOT>)
  --description DESC        Free text description
  --cluster CLUSTER         VM Cluster name or OCID (optional)

MODES:
  --check                   Only check if target already exists
  -n, --dry-run             Show registration plan without executing
  -h, --help                Show this help

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
# Notes...: Sets COMP_OCID, COMP_NAME, CONNECTOR_OCID, SERVICE_NAME, DISPLAY_NAME
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Required fields
    [[ -z "$HOST" ]] && die "Missing required option: --host"
    [[ -z "$SID" ]] && die "Missing required option: --sid"
    [[ -z "$COMPARTMENT" ]] && die "Missing required option: --compartment"
    [[ -z "$CONNECTOR" ]] && die "Missing required option: --connector"

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
    [[ -n "$CLUSTER" ]] && log_info "  Cluster:       $CLUSTER"
    [[ -n "$DESCRIPTION" ]] && log_info "  Description:   $DESCRIPTION"
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
        '{
            databaseType: $dbType,
            infrastructureType: $infra,
            listenerPort: $port,
            serviceName: $svc
        }')

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
        --wait-for-state ACTIVE \
        --wait-for-state FAILED) || {
        log_error "Registration failed"
        log_error "$result"
        rm -f "$json_file"
        die 2 "Target registration failed"
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
    parse_common_opts "$@"
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
