#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name : ds_find_untagged_targets.sh
# Description : Find Data Safe target databases without tags in specified namespace
# Version     : 0.3.0
# Author      : Generated for odb_datasafe framework
#
# Purpose:
#   Find targets without tags in a specific namespace (default: DBSec).
#   Outputs in same format as ds_target_list.sh for consistency.
#
# Usage:
#   ds_find_untagged_targets.sh [options]
#
# Options:
#   -c, --compartment COMP      Compartment name or OCID (default: DS_ROOT_COMP)
#   -n, --namespace NS          Tag namespace to check (default: DBSec)
#   -s, --state STATE           Lifecycle state filter (default: ACTIVE)
#   -o, --output FORMAT         Output format: table, csv, json (default: table)
#   --oci-config FILE           OCI config file
#   --oci-profile PROFILE       OCI profile to use
#   -h, --help                  Show help
#
# Exit Codes:
#   0 = Success
#   1 = Input validation error
#   2 = OCI command error
# ------------------------------------------------------------------------------

# Script identification
SCRIPT_NAME="ds_find_untagged_targets"
SCRIPT_VERSION="0.3.0"

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
TAG_NAMESPACE="DBSec"
STATE_FILTERS="ACTIVE"
OUTPUT_FORMAT="table"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

Usage() {
    local exit_code=${1:-0}
    cat << EOF
USAGE: ${SCRIPT_NAME} [options]

DESCRIPTION:
  Find Data Safe target databases without tags in specified namespace.
  Outputs targets that lack tags in the given namespace using the same 
  format as ds_target_list.sh.

OPTIONS:
  -c, --compartment COMP      Compartment name or OCID (default: DS_ROOT_COMP)
  -n, --namespace NS          Tag namespace to check (default: DBSec)
  -s, --state STATE           Lifecycle state filter (default: ACTIVE)
  -o, --output FORMAT         Output format: table, csv, json (default: table)
  --oci-config FILE           OCI config file
  --oci-profile PROFILE       OCI profile to use
  -h, --help                  Show this help

EXAMPLES:
  # Find untagged targets in default namespace
  ${SCRIPT_NAME}
  
  # Find untagged in specific namespace
  ${SCRIPT_NAME} -n "Security"
  
  # CSV output for specific compartment
  ${SCRIPT_NAME} -c "prod-compartment" -o csv

EXIT CODES:
  0 = Success
  1 = Input validation error 
  2 = OCI command error

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
            -n | --namespace)
                TAG_NAMESPACE="$2"
                shift 2
                ;;
            -s | --state)
                STATE_FILTERS="$2"
                shift 2
                ;;
            -o | --output)
                OUTPUT_FORMAT="$2"
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

    # Use root compartment if none specified
    if [[ -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    # Resolve compartment OCID
    COMP_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || die "Failed to resolve compartment: $COMPARTMENT"
    log_info "Using compartment: $COMPARTMENT ($COMP_OCID)"

    # Validate tag namespace
    if [[ -z "$TAG_NAMESPACE" ]]; then
        TAG_NAMESPACE="DBSec"
        log_info "Using default tag namespace: $TAG_NAMESPACE"
    fi

    # Validate output format
    case "$OUTPUT_FORMAT" in
        table | csv | json) ;;
        *) die "Invalid output format: $OUTPUT_FORMAT. Must be: table, csv, json" ;;
    esac

    log_info "Searching for untagged targets in namespace: $TAG_NAMESPACE"
}

find_untagged_targets() {
    log_info "Retrieving targets from compartment..."

    local targets_json
    targets_json=$(oci data-safe target-database list \
        --compartment-id "$COMP_OCID" \
        --compartment-id-in-subtree true \
        --lifecycle-state "$STATE_FILTERS" \
        --all \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" 2> /dev/null) || die "Failed to list targets"

    local total_count
    total_count=$(echo "$targets_json" | jq '.data | length')
    log_info "Found $total_count total targets"

    # Find untagged targets - check if namespace has any tags
    local untagged_targets
    untagged_targets=$(echo "$targets_json" | jq --arg ns "$TAG_NAMESPACE" '
        .data[] | select(
            (.["defined-tags"][$ns] | type) != "object" or
            (.["defined-tags"][$ns] | length) == 0
        )')

    local untagged_count
    untagged_count=$(echo "$untagged_targets" | jq -s 'length')

    if [[ "$untagged_count" -eq 0 ]]; then
        log_info "No untagged targets found"
        return 0
    fi

    log_info "Found $untagged_count untagged targets"

    # Output in requested format
    case "$OUTPUT_FORMAT" in
        json)
            echo "$untagged_targets" | jq -s '.'
            ;;
        csv)
            echo "ID,Name,Display Name,Lifecycle State,Compartment,Database Type,Infrastructure Type"
            echo "$untagged_targets" | jq -r '[
                .id,
                .["database-details"]["database-name"] // "N/A",
                .["display-name"],
                .["lifecycle-state"],
                .["compartment-id"],
                .["database-details"]["database-type"] // "N/A", 
                .["database-details"]["infrastructure-type"] // "N/A"
            ] | @csv' | jq -r '.'
            ;;
        table | *)
            printf "%-60s %-25s %-15s %-15s\n" "Target ID" "Display Name" "State" "Database Type"
            printf "%-60s %-25s %-15s %-15s\n" "$(printf "%0.s-" {1..60})" "$(printf "%0.s-" {1..25})" "$(printf "%0.s-" {1..15})" "$(printf "%0.s-" {1..15})"
            echo "$untagged_targets" | jq -r '[
                .id,
                .["display-name"],
                .["lifecycle-state"], 
                .["database-details"]["database-type"] // "N/A"
            ] | @tsv' | while IFS=$'\t' read -r id name state dbtype; do
                printf "%-60s %-25s %-15s %-15s\n" "$id" "$name" "$state" "$dbtype"
            done
            ;;
    esac
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

    # Find and display untagged targets
    find_untagged_targets

    log_info "Search completed"
}

# Run the script
main "$@"
