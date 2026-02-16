#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_connect_details.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.9.0
# Purpose....: Display connection details for Oracle Data Safe target database.
#              Shows target info, listener port, service name, connection strings,
#              VM cluster hosts, and credentials.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGET:=}"
: "${FORMAT:=table}"

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

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display script usage information
# Args....: None
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Display connection details for an Oracle Data Safe target database including
  target information, listener port, service name, connection strings, and
  VM cluster hosts.

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
    -T, --target ID         Target name or OCID (mandatory)
    -c, --compartment ID    Compartment OCID or name (for name resolution)

  Output:
    -f, --format FORMAT     Output format: table|json (default: ${FORMAT})

Examples:
  # Display target connection details (table format)
  ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_MYPDB

  # Display as JSON
  ${SCRIPT_NAME} -T my-target -f json

  # Use compartment for target name resolution
  ${SCRIPT_NAME} -T my-target -c my-compartment

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables based on arguments
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    local -a remaining=()
    set -- "${ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -T | --target)
                need_val "$1" "${2:-}"
                TARGET="$2"
                shift 2
                ;;
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -f | --format)
                need_val "$1" "${2:-}"
                FORMAT="$2"
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

    # Handle positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGET" ]]; then
            TARGET="${remaining[0]}"
        else
            log_warn "Ignoring positional args, target already specified: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error via die()
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Target is mandatory
    if [[ -z "$TARGET" ]]; then
        die "Target (-T/--target) is mandatory"
    fi

    # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
    COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment"
    log_debug "Resolved compartment: $COMPARTMENT"

    # Validate format
    case "$FORMAT" in
        table | json) ;;
        *) die "Invalid format: $FORMAT. Must be: table, json" ;;
    esac

    log_info "Retrieving connection details for target: $TARGET"
}

# ------------------------------------------------------------------------------
# Function: fetch_cluster_nodes
# Purpose.: Fetch cluster node information from OCI
# Args....: $1 - VM Cluster OCID
#           $2 - DB System OCID (optional fallback)
#           $3 - Compartment OCID (required for db node list)
# Returns.: 0 always (returns empty array on error)
# Output..: JSON array of cluster nodes
# ------------------------------------------------------------------------------
fetch_cluster_nodes() {
    local vm_cluster_id="$1"
    local db_system_id="${2:-}"
    local compartment_id="${3:-}"

    if [[ -z "$vm_cluster_id" || "$vm_cluster_id" == "null" ]]; then
        echo "[]"
        return 0
    fi

    if [[ -z "$compartment_id" || "$compartment_id" == "null" ]]; then
        log_warn "Missing compartment OCID for cluster node lookup"
        echo "[]"
        return 0
    fi

    log_debug "Fetching cluster nodes for VM cluster: $vm_cluster_id"

    # Try VM cluster node list (preferred for Exadata VM clusters)
    local nodes_data=""
    if nodes_data=$(oci_exec_ro db node list \
        --vm-cluster-id "$vm_cluster_id" \
        --compartment-id "$compartment_id" \
        --all \
        --query 'data'); then
        if [[ -n "$nodes_data" && "$nodes_data" != "null" ]]; then
            echo "$nodes_data"
            return 0
        fi
    fi

    # Final fallback: db-system-id when provided
    if [[ -n "$db_system_id" && "$db_system_id" != "null" ]]; then
        log_debug "Falling back to node list for DB system: $db_system_id"
        if nodes_data=$(oci_exec_ro db node list \
            --db-system-id "$db_system_id" \
            --compartment-id "$compartment_id" \
            --all \
            --query 'data'); then
            if [[ -n "$nodes_data" && "$nodes_data" != "null" ]]; then
                echo "$nodes_data"
                return 0
            fi
        fi
    fi

    log_warn "Failed to fetch cluster nodes"
    echo "[]"
}

# ------------------------------------------------------------------------------
# Function: display_connection_details
# Purpose.: Fetch and display target connection details
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Formatted target and connection information
# ------------------------------------------------------------------------------
display_connection_details() {
    local target_ocid target_name target_data

    # Resolve target to OCID
    log_debug "Resolving target: $TARGET"
    target_ocid=$(ds_resolve_target_ocid "$TARGET" "$COMPARTMENT") || {
        log_error "Failed to resolve target: $TARGET"
        return 1
    }

    log_debug "Fetching target details for: $target_ocid"
    # Fetch target details
    target_data=$(oci_exec_ro data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data') || {
        log_error "Failed to fetch target details"
        return 1
    }

    # Extract connection details
    local target_id target_status target_comp_ocid target_comp_name
    local target_description target_details target_conn_type target_onprem_ocid
    local target_username freeform_tags
    local db_type db_listener_port db_service_name db_vm_cluster_id
    local db_system_id

    target_id=$(echo "$target_data" | jq -r '.id // ""')
    target_name=$(echo "$target_data" | jq -r '."display-name" // ""')
    target_description=$(echo "$target_data" | jq -r '.description // ""')
    target_status=$(echo "$target_data" | jq -r '."lifecycle-state" // ""')
    target_details=$(echo "$target_data" | jq -r '."lifecycle-details" // ""')
    target_comp_ocid=$(echo "$target_data" | jq -r '."compartment-id" // ""')

    # Extract connection-option first to avoid jq errors
    local conn_option
    conn_option=$(echo "$target_data" | jq -r '."connection-option" // {}')
    target_conn_type=$(echo "$conn_option" | jq -r '."connection-type" // ""')
    target_onprem_ocid=$(echo "$conn_option" | jq -r '."on-prem-connector-id" // ""')

    target_username=$(echo "$target_data" | jq -r '.credentials."user-name" // ""')
    freeform_tags=$(echo "$target_data" | jq -c '.["freeform-tags"] // {}')

    db_type=$(echo "$target_data" | jq -r '."database-details"."database-type" // ""')
    db_listener_port=$(echo "$target_data" | jq -r '."database-details"."listener-port" // ""')
    db_service_name=$(echo "$target_data" | jq -r '."database-details"."service-name" // ""')
    db_vm_cluster_id=$(echo "$target_data" | jq -r '."database-details"."vm-cluster-id" // ""')
    db_system_id=$(echo "$target_data" | jq -r '."database-details"."db-system-id" // ""')

    # Resolve compartment and connector names
    target_comp_name=$(oci_get_compartment_name "$target_comp_ocid" 2> /dev/null || echo "$target_comp_ocid")
    local target_onprem_name=""
    [[ -n "$target_onprem_ocid" && "$target_onprem_ocid" != "null" ]] \
        && target_onprem_name=$(oci_exec_ro data-safe on-prem-connector get \
            --on-prem-connector-id "$target_onprem_ocid" \
            --query 'data."display-name"' \
            --raw-output 2> /dev/null || echo "")

    # Fetch cluster nodes if VM cluster exists
    local cluster_nodes cluster_nodes_json
    cluster_nodes="[]"
    if [[ -n "$db_vm_cluster_id" && "$db_vm_cluster_id" != "null" ]]; then
        cluster_nodes=$(fetch_cluster_nodes "$db_vm_cluster_id" "$db_system_id" "$target_comp_ocid")
    fi

    # Process cluster nodes for display
    cluster_nodes_json=$(echo "$cluster_nodes" | jq -c 'map({
        id: .id,
        hostname: .hostname,
        vnic_id: ."vnic-id",
        backup_vnic_id: ."backup-vnic-id",
        lifecycle_state: ."lifecycle-state"
    })')

    # Format output
    if [[ "$FORMAT" == "json" ]]; then
        jq -n \
            --arg id "$target_id" \
            --arg name "$target_name" \
            --arg description "$target_description" \
            --arg status "$target_status" \
            --arg details "$target_details" \
            --arg comp_id "$target_comp_ocid" \
            --arg comp_name "$target_comp_name" \
            --arg conn_type "$target_conn_type" \
            --arg onprem_id "$target_onprem_ocid" \
            --arg onprem_name "$target_onprem_name" \
            --arg username "$target_username" \
            --arg db_type "$db_type" \
            --arg listener_port "$db_listener_port" \
            --arg service_name "$db_service_name" \
            --arg vm_cluster_id "$db_vm_cluster_id" \
            --arg db_system_id "$db_system_id" \
            --argjson freeform_tags "$freeform_tags" \
            --argjson cluster_nodes "$cluster_nodes_json" '{
              target: {
                id: $id,
                name: $name,
                description: $description,
                status: $status,
                details: $details,
                compartment: { id: $comp_id, name: $comp_name },
                connection: { type: $conn_type, onprem_connector: { id: $onprem_id, name: $onprem_name } },
                credentials: { user_name: $username },
                freeform_tags: $freeform_tags
              },
              database: {
                type: $db_type,
                listener_port: ($listener_port | if . == "" then null else tonumber end),
                service_name: $service_name,
                vm_cluster_id: $vm_cluster_id,
                db_system_id: (if $db_system_id == "" then null else $db_system_id end),
                cluster_nodes: $cluster_nodes
              }
            }'
    else
        # Table format
        printf '%-25s : %s\n' "Target Name" "$target_name"
        printf '%-25s : %s\n' "Target ID" "$target_id"
        printf '%-25s : %s\n' "Description" "$target_description"
        printf '%-25s : %s\n' "Status" "$target_status"
        printf '%-25s : %s\n' "Details" "$target_details"
        printf '%-25s : %s\n' "Compartment" "$target_comp_name ($target_comp_ocid)"
        printf '%-25s : %s\n' "Connection Type" "$target_conn_type"
        [[ -n "$target_onprem_name" ]] && printf '%-25s : %s\n' "On-Prem Connector" "$target_onprem_name ($target_onprem_ocid)"
        printf '%-25s : %s\n' "Username" "$target_username"
        printf '%-25s : %s\n' "Database Type" "$db_type"
        printf '%-25s : %s\n' "Listener Port" "$db_listener_port"
        printf '%-25s : %s\n' "Service Name" "$db_service_name"
        [[ -n "$db_vm_cluster_id" ]] && printf '%-25s : %s\n' "VM Cluster ID" "$db_vm_cluster_id"
        [[ -n "$db_system_id" ]] && printf '%-25s : %s\n' "DB System ID" "$db_system_id"

        # Display cluster node names only
        local node_count node_names
        node_count=$(echo "$cluster_nodes" | jq 'length')
        if [[ "$node_count" -gt 0 ]]; then
            node_names=$(echo "$cluster_nodes" | jq -r '[.[] | (.hostname // .id)] | join(", ")')
            printf '%-25s : %s\n' "Cluster Nodes" "$node_names"
        fi

        printf '%-25s : %s\n' "Freeform Tags" "$(echo "$freeform_tags" | jq -c '.')"
    fi

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info \"Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}\"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Display connection details
    if display_connection_details; then
        log_info "Connection details retrieved successfully"
    else
        die "Failed to retrieve connection details"
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
fi

parse_args "$@"
main
