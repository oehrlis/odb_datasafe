#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name : ds_target_export.sh
# Description : Export Oracle Data Safe target databases to CSV or JSON
# Version....: v0.5.3
# Author      : Migrated to odb_datasafe v0.2.0 framework
#
# Purpose:
#   Export Data Safe target information to CSV or JSON format with enriched
#   metadata including cluster/CDB/PDB parsing, connector mapping, and service details.
#
# Usage:
#   ds_target_export.sh -c <compartment> [options]
#
# Options:
#   -c, --compartment COMP      Compartment name or OCID (required)
#   -L, --lifecycle STATE       Filter by lifecycle state (e.g., ACTIVE,NEEDS_ATTENTION)
#   -D, --since-date DATE       Only targets created >= date (2025-01-01 or RFC3339)
#   -F, --format FORMAT         Export format: csv or json (default: csv)
#   -o, --output FILE           Output file path (default: ./datasafe_targets.<format>)
#   --oci-config FILE           OCI config file
#   --oci-profile PROFILE       OCI profile to use
#   -h, --help                  Show help
#
# Exit Codes:
#   0 = Success
#   1 = Input validation error
#   2 = Export error
# ------------------------------------------------------------------------------

# Script identification
SCRIPT_NAME="ds_target_export"
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
COMPARTMENT=""
LIFECYCLE=""
SINCE_DATE=""
FORMAT="csv"
OUTPUT_FILE=""

# Runtime
COMP_OCID=""
LC_FILTER=""
EXPORTED_COUNT=0
declare -A CONNECTOR_MAP

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

Usage() {
    local exit_code=${1:-0}
    cat << EOF
USAGE: ${SCRIPT_NAME} [options]

DESCRIPTION:
  Export Oracle Data Safe target databases to CSV or JSON format with enriched
  metadata including cluster/CDB/PDB information, connector mapping, and service details.

OPTIONS:
  -c, --compartment COMP      Compartment name or OCID (required)
  -L, --lifecycle STATE       Filter by lifecycle state (ACTIVE,NEEDS_ATTENTION, etc.)
  -D, --since-date DATE       Only export targets created >= date
                              Accepts: 2025-01-01, -2d, -1w, -3m, RFC3339
  -F, --format FORMAT         Export format: csv, json (default: csv)
  -o, --output FILE           Output file (default: ./datasafe_targets.<format>)
  --oci-config FILE           OCI CLI config file
  --oci-profile PROFILE       OCI CLI profile
  -h, --help                  Show this help

CSV COLUMNS:
  datasafe_ocid, display_name, cluster_name, node_name, node_list,
  cdb_name, pdb_name, onprem_connector, service_name, listener_port,
  created_at, registration_status

EXAMPLES:
  # Export all targets in compartment to CSV
  ds_target_export.sh -c prod-compartment
  
  # Export ACTIVE targets to JSON
  ds_target_export.sh -c prod-compartment -L ACTIVE -F json -o targets.json
  
  # Export targets created since date
  ds_target_export.sh -c prod-compartment -D 2025-01-01

EXIT CODES:
  0 = Success
  1 = Input validation error
  2 = Export error

EOF
    exit "$exit_code"
}

parse_args() {
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c | --compartment)
                COMPARTMENT="$2"
                shift 2
                ;;
            -L | --lifecycle)
                LIFECYCLE="$2"
                shift 2
                ;;
            -D | --since-date)
                SINCE_DATE="$2"
                shift 2
                ;;
            -F | --format)
                FORMAT="$2"
                shift 2
                ;;
            -o | --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --oci-config)
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            --oci-profile)
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            -h | --help)
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

    # Compartment is required
    if [[ -z "$COMPARTMENT" ]]; then
        die "Compartment is required. Use -c/--compartment"
    fi

    # Resolve compartment OCID
    COMP_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || die "Failed to resolve compartment: $COMPARTMENT"
    log_info "Using compartment: $COMPARTMENT ($COMP_OCID)"

    # Validate format
    case "$FORMAT" in
        csv | json) ;;
        *) die "Invalid format: $FORMAT. Must be: csv, json" ;;
    esac

    # Set default output file if not specified
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="./datasafe_targets.${FORMAT}"
    fi

    # Process lifecycle filter
    if [[ -n "$LIFECYCLE" ]]; then
        LC_FILTER="$LIFECYCLE"
        log_info "Filtering by lifecycle states: $LC_FILTER"
    fi

    # Normalize since-date if provided
    if [[ -n "$SINCE_DATE" ]]; then
        # Simple handling - accept as-is for now
        log_info "Filtering targets created since: $SINCE_DATE"
    fi

    log_info "Output format: $FORMAT -> $OUTPUT_FILE"
}

build_connector_map() {
    log_info "Building connector map..."

    local connectors_json
    connectors_json=$(oci data-safe on-prem-connector list \
        --compartment-id "$COMP_OCID" \
        --all \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" 2> /dev/null) || {
        log_warn "Failed to list on-prem connectors; connector names may show as OCID"
        return 0
    }

    # Build associative array: ocid -> name
    while IFS=$'\t' read -r ocid name; do
        [[ -n "$ocid" ]] && CONNECTOR_MAP["$ocid"]="$name"
    done < <(echo "$connectors_json" | jq -r '.data[]? | [.id, .["display-name"]] | @tsv')

    log_debug "Loaded ${#CONNECTOR_MAP[@]} connectors"
}

get_connector_name() {
    local ocid="$1"
    [[ -z "$ocid" ]] && {
        echo "N/A"
        return
    }
    echo "${CONNECTOR_MAP[$ocid]:-$ocid}"
}

parse_display_name() {
    # Parse <cluster>_<cdb>_<pdb> format
    local name="$1"
    local cluster cdb pdb

    IFS='_' read -r cluster cdb pdb <<< "$name"

    # If only 2 parts, assume no cluster
    if [[ -z "$pdb" ]]; then
        pdb="$cdb"
        cdb="$cluster"
        cluster=""
    fi

    echo "$cluster|$cdb|$pdb"
}

sanitize_csv() {
    # Escape quotes and remove newlines for CSV
    echo "${1:-N/A}" | tr -d '\n' | sed 's/"/""/g'
}

export_targets() {
    log_info "Fetching targets from compartment..."

    local targets_json
    targets_json=$(oci data-safe target-database list \
        --compartment-id "$COMP_OCID" \
        --compartment-id-in-subtree true \
        --all \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" 2> /dev/null) || die "Failed to list targets"

    local total_count
    total_count=$(echo "$targets_json" | jq '.data | length')
    log_info "Found $total_count total targets"

    # Initialize output file
    case "$FORMAT" in
        csv)
            echo "datasafe_ocid,display_name,cluster_name,node_name,node_list,cdb_name,pdb_name,onprem_connector,service_name,listener_port,created_at,registration_status" > "$OUTPUT_FILE"
            ;;
        json)
            echo "[" > "$OUTPUT_FILE"
            ;;
    esac

    local first_json=1
    local count=0

    # Process each target
    while IFS= read -r target; do
        ((count++))
        [[ -z "$target" || "$target" == "null" ]] && continue

        local target_id display_name created lcstate
        target_id=$(echo "$target" | jq -r '.id')
        display_name=$(echo "$target" | jq -r '.["display-name"]')
        created=$(echo "$target" | jq -r '.["time-created"]')
        lcstate=$(echo "$target" | jq -r '.["lifecycle-state"]')

        log_debug "Processing ($count/$total_count): $display_name"

        # Apply filters
        if [[ -n "$SINCE_DATE" && "$created" < "$SINCE_DATE" ]]; then
            log_debug "  Skipping: created $created < $SINCE_DATE"
            continue
        fi

        if [[ -n "$LC_FILTER" && ! "$lcstate" =~ $LC_FILTER ]]; then
            log_debug "  Skipping: state $lcstate not in $LC_FILTER"
            continue
        fi

        # Parse cluster/CDB/PDB from display name
        local parsed cluster cdb pdb
        parsed=$(parse_display_name "$display_name")
        IFS='|' read -r cluster cdb pdb <<< "$parsed"

        # Get connector info
        local connector_ocid connector_name
        connector_ocid=$(echo "$target" | jq -r '.["associated-resource-ids"][]? | select(startswith("ocid1.datasafeonpremconnector"))' | head -n1)
        connector_name=$(get_connector_name "$connector_ocid")

        # Get target details for service/port
        local details_json service_name listener_port
        details_json=$(oci data-safe target-database get \
            --target-database-id "$target_id" \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" 2> /dev/null) || {
            log_warn "Failed to get details for $display_name"
            service_name="N/A"
            listener_port="0"
        }

        if [[ -n "$details_json" ]]; then
            service_name=$(echo "$details_json" | jq -r '.data["database-details"]["service-name"] // "N/A"')
            listener_port=$(echo "$details_json" | jq -r '.data["database-details"]["listener-port"] // "0"')
        fi

        # Determine registration status
        local reg_status
        case "$lcstate" in
            ACTIVE | CREATING | UPDATING) reg_status="REGISTERED" ;;
            DELETED | DELETING) reg_status="DECOMMISSIONED" ;;
            FAILED | INACTIVE | NEEDS_ATTENTION) reg_status="NEEDS_ATTENTION" ;;
            *) reg_status="UNKNOWN" ;;
        esac

        # Output record
        case "$FORMAT" in
            csv)
                printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s",%s,"%s","%s"\n' \
                    "$(sanitize_csv "$target_id")" \
                    "$(sanitize_csv "$display_name")" \
                    "$(sanitize_csv "$cluster")" \
                    "$(sanitize_csv "")" \
                    "$(sanitize_csv "")" \
                    "$(sanitize_csv "$cdb")" \
                    "$(sanitize_csv "$pdb")" \
                    "$(sanitize_csv "$connector_name")" \
                    "$(sanitize_csv "$service_name")" \
                    "$listener_port" \
                    "$(sanitize_csv "$created")" \
                    "$(sanitize_csv "$reg_status")" \
                    >> "$OUTPUT_FILE"
                ;;
            json)
                local record
                record=$(jq -n \
                    --arg ds_ocid "$target_id" \
                    --arg display_name "$display_name" \
                    --arg cluster_name "$cluster" \
                    --arg cdb_name "$cdb" \
                    --arg pdb_name "$pdb" \
                    --arg onprem_connector "$connector_name" \
                    --arg service_name "$service_name" \
                    --argjson listener_port "$listener_port" \
                    --arg created_at "$created" \
                    --arg registration_status "$reg_status" \
                    '{
                      datasafe_ocid: $ds_ocid,
                      display_name: $display_name,
                      cluster_name: $cluster_name,
                      cdb_name: $cdb_name,
                      pdb_name: $pdb_name,
                      onprem_connector: $onprem_connector,
                      service_name: $service_name,
                      listener_port: $listener_port,
                      created_at: $created_at,
                      registration_status: $registration_status
                    }')

                if ((first_json)); then
                    echo "$record" >> "$OUTPUT_FILE"
                    first_json=0
                else
                    echo ",$record" >> "$OUTPUT_FILE"
                fi
                ;;
        esac

        ((EXPORTED_COUNT++))
    done < <(echo "$targets_json" | jq -c '.data[]')

    # Finalize output
    case "$FORMAT" in
        json)
            echo "]" >> "$OUTPUT_FILE"
            ;;
    esac

    if [[ $EXPORTED_COUNT -eq 0 ]]; then
        log_warn "No targets matched the selection criteria"
        rm -f "$OUTPUT_FILE"
        die 0 "Nothing exported"
    fi

    log_info "Successfully exported $EXPORTED_COUNT targets to $OUTPUT_FILE"
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

    # Build connector mapping
    build_connector_map

    # Export targets
    export_targets

    log_info "Export completed successfully"
}

# Run the script
main "$@"
