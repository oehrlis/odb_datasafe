#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_list_connector.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.22
# Version....: v0.5.3
# Purpose....: List Oracle Data Safe on-premises connectors
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '0.5.3')"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${CONNECTORS:=}"
: "${LIFECYCLE_STATE:=}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${FIELDS:=display-name,lifecycle-state,available-version}"

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

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  List Oracle Data Safe on-premises connectors with detailed information
  based on compartment and lifecycle state filters.

Options:
  Common:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -d, --debug             Enable debug output
    -q, --quiet             Suppress INFO messages (warnings/errors only)
    -n, --dry-run           Dry-run mode (show what would be done)
    --log-file FILE         Log to file

  OCI:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE:-~/.oci/config})

  Selection:
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP)
                            Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -C, --connectors LIST   Comma-separated connector names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state (ACTIVE, INACTIVE, etc.)

  Output:
    -f, --format FMT        Output format: table|json|csv (default: table)
    -F, --fields FIELDS     Comma-separated fields (default: ${FIELDS})

Available Fields:
  display-name, id, lifecycle-state, time-created, available-version,
  time-last-used, freeform-tags, defined-tags

Examples:
  # Show all connectors in DS_ROOT_COMP (default)
  ${SCRIPT_NAME}

  # Show connectors in specific compartment
  ${SCRIPT_NAME} -c MyCompartment

  # Show only ACTIVE connectors
  ${SCRIPT_NAME} -L ACTIVE

  # Show as JSON
  ${SCRIPT_NAME} -f json

  # Show specific fields as CSV
  ${SCRIPT_NAME} -f csv -F display-name,id,lifecycle-state,time-created

  # Show details for specific connectors
  ${SCRIPT_NAME} -C connector1,connector2

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables based on arguments
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    # Reset defaults (override any env/config values)
    [[ -z "${OUTPUT_FORMAT_OVERRIDE:-}" ]] && OUTPUT_FORMAT="table"
    [[ -z "${FIELDS_OVERRIDE:-}" ]] && FIELDS="display-name,lifecycle-state,available-version"

    # Parse script-specific options
    local -a remaining=()
    set -- "${ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -C | --connectors)
                need_val "$1" "${2:-}"
                CONNECTORS="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -f | --format)
                need_val "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                OUTPUT_FORMAT_OVERRIDE=true
                shift 2
                ;;
            -F | --fields)
                need_val "$1" "${2:-}"
                FIELDS="$2"
                FIELDS_OVERRIDE=true
                shift 2
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                OCI_CLI_CONFIG_FILE="$2"
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

    # Handle positional arguments (treat as connectors)
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$CONNECTORS" ]]; then
            CONNECTORS="${remaining[*]}"
            CONNECTORS="${CONNECTORS// /,}"
        else
            log_warn "Ignoring positional args, connectors already specified: ${remaining[*]}"
        fi
    fi

    # Validate output format
    case "${OUTPUT_FORMAT}" in
        table | json | csv) : ;;
        *) die "Invalid output format: '${OUTPUT_FORMAT}'. Use table, json, or csv" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate inputs and set defaults
# Returns.: 0 on success, exits on error
# Output..: Logs validation status
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq

    # If neither connectors nor compartment specified, use DS_ROOT_COMP as default
    if [[ -z "$CONNECTORS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        COMPARTMENT="$root_comp"

        # Get compartment name for display
        local comp_name
        comp_name=$(oci_get_compartment_name "$root_comp") || comp_name="<unknown>"

        log_debug "Using root compartment OCID: $COMPARTMENT"
        log_info "Using root compartment: $comp_name (includes sub-compartments)"
    fi
}

# ------------------------------------------------------------------------------
# Function: list_connectors_in_compartment
# Purpose.: List all connectors in compartment
# Args....: $1 - compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON array of connectors to stdout
# ------------------------------------------------------------------------------
list_connectors_in_compartment() {
    local compartment="$1"
    local comp_ocid

    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing connectors in compartment OCID: $comp_ocid"

    local -a cmd=(
        data-safe on-premises-connector list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )

    if [[ -n "$LIFECYCLE_STATE" ]]; then
        cmd+=(--lifecycle-state "$LIFECYCLE_STATE")
        log_debug "Filtering by lifecycle state: $LIFECYCLE_STATE"
    fi

    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function: get_connector_details
# Purpose.: Get details for specific connector
# Args....: $1 - connector OCID
# Returns.: 0 on success, 1 on error
# Output..: JSON object to stdout
# ------------------------------------------------------------------------------
get_connector_details() {
    local connector_ocid="$1"

    log_debug "Getting details for: $connector_ocid"

    oci_exec data-safe on-premises-connector get \
        --on-premises-connector-id "$connector_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function: resolve_connector_ocid
# Purpose.: Resolve connector name to OCID
# Args....: $1 - connector name or OCID
#           $2 - compartment OCID
# Returns.: 0 on success, 1 on error
# Output..: Connector OCID to stdout
# ------------------------------------------------------------------------------
resolve_connector_ocid() {
    local connector_name="$1"
    local compartment_ocid="$2"

    log_debug "Resolving connector name: $connector_name"

    local result
    result=$(oci_exec data-safe on-premises-connector list \
        --compartment-id "$compartment_ocid" \
        --compartment-id-in-subtree true \
        --all \
        --query "data[?\"display-name\"=='${connector_name}'].id | [0]" \
        --raw-output)

    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "Connector not found: $connector_name"
        return 1
    fi

    echo "$result"
}

# ------------------------------------------------------------------------------
# Function: show_details_table
# Purpose.: Display detailed connector information in table format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: Formatted table to stdout
# ------------------------------------------------------------------------------
show_details_table() {
    local json_data="$1"
    local fields="$2"

    # Convert fields to jq array format
    local -a field_array field_widths
    IFS=',' read -ra field_array <<< "$fields"

    # Set column widths (display-name gets more space)
    for field in "${field_array[@]}"; do
        if [[ "$field" == "display-name" ]]; then
            field_widths+=(50)
        else
            field_widths+=(30)
        fi
    done

    # Build jq select expression
    local jq_select="["
    for field in "${field_array[@]}"; do
        jq_select+=".[\"${field}\"],"
    done
    jq_select="${jq_select%,}]"

    # Print header
    printf "\n"
    local idx=0
    for field in "${field_array[@]}"; do
        printf "%-${field_widths[$idx]}s " "$field"
        idx=$((idx + 1))
    done
    printf "\n"

    idx=0
    for field in "${field_array[@]}"; do
        local width=${field_widths[$idx]}
        printf "%-${width}s " "$(printf "%0.s-" $(seq 1 "$width"))"
        idx=$((idx + 1))
    done
    printf "\n"

    # Print data
    echo "$json_data" | jq -r ".data[] | $jq_select | @tsv" \
        | while IFS=$'\t' read -r -a values; do
            local idx=0
            for value in "${values[@]}"; do
                local width=${field_widths[$idx]}
                local max_len=$((width - 2))

                # Truncate long values
                local display_value="${value:0:$max_len}"
                [[ ${#value} -gt $max_len ]] && display_value="${display_value}.."
                printf "%-${width}s " "$display_value"
                idx=$((idx + 1))
            done
            printf "\n"
        done

    # Print count
    local count
    count=$(echo "$json_data" | jq '.data | length')
    printf "\nTotal: %d connectors\n\n" "$count"
}

# ------------------------------------------------------------------------------
# Function: show_details_json
# Purpose.: Display detailed connector information in JSON format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: JSON output to stdout
# ------------------------------------------------------------------------------
show_details_json() {
    local json_data="$1"
    local fields="$2"

    if [[ "$fields" == "all" || -z "$fields" ]]; then
        echo "$json_data" | jq '.data[]'
    else
        # Build jq select expression for specific fields
        local jq_expr="{"
        IFS=',' read -ra field_array <<< "$fields"
        for field in "${field_array[@]}"; do
            jq_expr+="\"${field}\": .[\"${field}\"],"
        done
        jq_expr="${jq_expr%,}}"

        echo "$json_data" | jq ".data[] | $jq_expr"
    fi
}

# ------------------------------------------------------------------------------
# Function: show_details_csv
# Purpose.: Display detailed connector information in CSV format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: CSV output to stdout
# ------------------------------------------------------------------------------
show_details_csv() {
    local json_data="$1"
    local fields="$2"

    # Print header
    echo "$fields"

    # Convert fields to jq array
    local -a field_array
    IFS=',' read -ra field_array <<< "$fields"

    local jq_select="["
    for field in "${field_array[@]}"; do
        jq_select+=".[\"${field}\"],"
    done
    jq_select="${jq_select%,}]"

    # Print data
    echo "$json_data" | jq -r ".data[] | $jq_select | @csv"
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrates connector listing and display
# Returns.: 0 on success, 1 on error
# Output..: Connector information based on selected format
# ------------------------------------------------------------------------------
do_work() {
    local json_data

    # Collect connector data
    if [[ -n "$CONNECTORS" ]]; then
        # Get details for specific connectors
        log_info "Fetching details for specific connectors..."

        local -a connector_list connector_ocids
        IFS=',' read -ra connector_list <<< "$CONNECTORS"

        # Resolve connector names to OCIDs
        for connector in "${connector_list[@]}"; do
            connector="${connector// /}" # trim spaces

            if is_ocid "$connector"; then
                connector_ocids+=("$connector")
            else
                log_debug "Resolving connector name: $connector"
                local resolved

                if [[ -n "$COMPARTMENT" ]]; then
                    local comp_ocid
                    comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT") || die "Failed to resolve compartment: $COMPARTMENT"
                    resolved=$(resolve_connector_ocid "$connector" "$comp_ocid") || die "Failed to resolve connector: $connector"
                else
                    local root_comp
                    root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
                    resolved=$(resolve_connector_ocid "$connector" "$root_comp") || die "Failed to resolve connector: $connector"
                fi

                if [[ -z "$resolved" ]]; then
                    die "Connector not found: $connector"
                fi

                connector_ocids+=("$resolved")
            fi
        done

        # Fetch details for each connector and combine into array
        local -a connector_details
        for connector_ocid in "${connector_ocids[@]}"; do
            local details
            details=$(get_connector_details "$connector_ocid") || {
                log_warn "Failed to get details for: $connector_ocid"
                continue
            }
            connector_details+=("$details")
        done

        # Combine into JSON structure
        json_data="{\"data\":["
        local first=true
        for detail in "${connector_details[@]}"; do
            [[ "$first" == "true" ]] && first=false || json_data+=","
            json_data+="$detail"
        done
        json_data+="]}"

    else
        # List connectors from compartment hierarchy
        local comp_name
        comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="$COMPARTMENT"
        log_info "Listing connectors in compartment: $comp_name (includes sub-compartments)"
        json_data=$(list_connectors_in_compartment "$COMPARTMENT") || die "Failed to list connectors"
    fi

    # Display results based on format
    case "$OUTPUT_FORMAT" in
        table)
            show_details_table "$json_data" "$FIELDS"
            ;;
        json)
            show_details_json "$json_data" "$FIELDS"
            ;;
        csv)
            show_details_csv "$json_data" "$FIELDS"
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Execute main work
    do_work

    log_info "List completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# Explicit exit to prevent spurious error trap
exit 0

# --- End of ds_target_list_connector.sh ---------------------------------------
