#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name : ds_target_register.sh
# Description : Register a database as Oracle Data Safe target
# Version     : 0.3.1
# Author      : Migrated to odb_datasafe v0.2.0 framework
# 
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
#   --ds-password PASS          Data Safe password (required)
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

# Script identification
SCRIPT_NAME="ds_target_register"
SCRIPT_VERSION="0.3.1"

# Bootstrap - locate library files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

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
LISTENER_PORT="1521"
SERVICE_NAME=""
DS_USER="DS_ADMIN"
DS_PASSWORD=""
DISPLAY_NAME=""
DESCRIPTION=""
CLUSTER=""
CHECK_ONLY=false

# Runtime
COMP_OCID=""
CONNECTOR_OCID=""
# shellcheck disable=SC2034  # CLUSTER_OCID reserved for future cluster discovery feature
CLUSTER_OCID=""

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

Usage() {
  local exit_code=${1:-0}
  cat << EOF
USAGE: ${SCRIPT_NAME} [options]

DESCRIPTION:
  Register a database (PDB or CDB\$ROOT) as an Oracle Data Safe target.
  Requires on-premises connector for cloud-at-customer deployments.

SCOPE (choose one):
  --pdb PDB                   Register a specific PDB
  --root                      Register CDB\$ROOT (named CDBROOT)

REQUIRED OPTIONS:
  -H, --host HOST             Database host name
  --sid SID                   Database SID
  -c, --compartment COMP      Target compartment (name or OCID)
  --connector CONN            On-premises connector (name or OCID)
  --ds-password PASS          Data Safe user password

CONNECTION:
  --port PORT                 Listener port (default: 1521)
  --service SERVICE           Service name (default: auto-derived from PDB/SID)
  --ds-user USER              Data Safe user (default: DS_ADMIN)

METADATA:
  -N, --display-name NAME     Display name (default: <cluster>_<sid>_<pdb|CDBROOT>)
  --description DESC          Free text description
  --cluster CLUSTER           VM Cluster name or OCID (optional)

MODES:
  --check                     Only check if target already exists
  -n, --dry-run               Show registration plan without executing
  -h, --help                  Show this help

EXAMPLES:
  # Register a PDB
  ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \\
    -c prod-compartment --connector my-connector --ds-password <password>
  
  # Register CDB\$ROOT
  ds_target_register.sh -H db01 --sid cdb01 --root \\
    -c prod-compartment --connector my-connector --ds-password <password>
  
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

parse_args() {
    local remaining=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -H|--host)
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
            -c|--compartment)
                COMPARTMENT="$2"
                shift 2
                ;;
            --connector)
                CONNECTOR="$2"
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
            --ds-password)
                DS_PASSWORD="$2"
                shift 2
                ;;
            -N|--display-name)
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
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --oci-config)
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            --oci-profile)
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            -h|--help)
                Usage 0
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done
}

validate_inputs() {
    log_debug "Validating inputs..."
    
    require_cmd oci jq
    
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
    
    # Password required unless check-only
    if [[ "$CHECK_ONLY" != "true" && -z "$DS_PASSWORD" ]]; then
        die "Missing required option: --ds-password (not needed with --check)"
    fi
    
    # Resolve compartment OCID
    COMP_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || die "Failed to resolve compartment: $COMPARTMENT"
    log_info "Target compartment: $COMPARTMENT ($COMP_OCID)"
    
    # Resolve connector OCID
    if [[ "$CONNECTOR" =~ ^ocid1\.datasafeonpremconnector\. ]]; then
        CONNECTOR_OCID="$CONNECTOR"
    else
        # Try to find connector by name
        local connectors_json
        connectors_json=$(oci data-safe on-prem-connector list \
            --compartment-id "$COMP_OCID" \
            --all \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" 2>/dev/null) || die "Failed to list connectors"
        
        CONNECTOR_OCID=$(echo "$connectors_json" | jq -r ".data[] | select(.\"display-name\" == \"$CONNECTOR\") | .id" | head -n1)
        
        if [[ -z "$CONNECTOR_OCID" ]]; then
            die "Connector not found: $CONNECTOR"
        fi
    fi
    log_info "On-premises connector: $CONNECTOR ($CONNECTOR_OCID)"
    
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

check_target_exists() {
    log_info "Checking if target already exists..."
    
    local targets_json
    targets_json=$(oci data-safe target-database list \
        --compartment-id "$COMP_OCID" \
        --compartment-id-in-subtree true \
        --all \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" 2>/dev/null) || die "Failed to list targets"
    
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
    [[ -n "$CLUSTER" ]] && log_info "  Cluster:       $CLUSTER"
    [[ -n "$DESCRIPTION" ]] && log_info "  Description:   $DESCRIPTION"
}

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
        --arg pass "$DS_PASSWORD" \
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
    
    # Execute registration
    local result
    result=$(oci data-safe target-database create \
        --from-json "file://$json_file" \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" \
        --wait-for-state ACTIVE \
        --wait-for-state FAILED 2>&1) || {
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
