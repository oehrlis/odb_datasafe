#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_connector_summary.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.23
# Version....: v0.7.0
# Purpose....: List Data Safe targets grouped by on-premises connector
#              with summary counts and lifecycle state information
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '0.6.1')"
readonly SCRIPT_VERSION
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${LIFECYCLE_STATE:=}"
: "${OUTPUT_FORMAT:=table}"    # table|json|csv
: "${SHOW_DETAILED:=false}"    # Summary by default
: "${FIELDS:=display-name,lifecycle-state,infrastructure-type}"
: "${SHOW_OCID:=false}"

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
  List Oracle Data Safe targets grouped by on-premises connector.
  Shows summary counts by connector with lifecycle state information,
  or detailed target lists under each connector.

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
                            Configure in: .env or datasafe.conf
    -L, --lifecycle STATE   Filter by lifecycle state (ACTIVE, NEEDS_ATTENTION, etc.)

  Output:
    -S, --summary           Show summary counts (default)
    -D, --detailed          Show detailed target information per connector
    -f, --format FMT        Output format: table|json|csv (default: table)
    -F, --fields FIELDS     Comma-separated fields for detailed mode
                            (default: ${FIELDS})
        --show-ocid             Show connector OCIDs (table output)

Examples:
  # Show summary of targets by connector (default)
  ${SCRIPT_NAME}

  # Show summary for specific compartment
  ${SCRIPT_NAME} -c MyCompartment

  # Show detailed list of all targets under each connector
  ${SCRIPT_NAME} -D

  # Show summary with only ACTIVE targets
  ${SCRIPT_NAME} -L ACTIVE

  # Show detailed list as JSON
  ${SCRIPT_NAME} -D -f json

  # Show summary as CSV
  ${SCRIPT_NAME} -f csv

  # Quiet mode - minimal output
  ${SCRIPT_NAME} -q

EOF
    exit 0
}

parse_args() {
    parse_common_opts "$@"

    # Reset defaults
    [[ -z "${OUTPUT_FORMAT_OVERRIDE:-}" ]] && OUTPUT_FORMAT="table"
    [[ -z "${SHOW_DETAILED_OVERRIDE:-}" ]] && SHOW_DETAILED="false"
    [[ -z "${FIELDS_OVERRIDE:-}" ]] && FIELDS="display-name,lifecycle-state,infrastructure-type"

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
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -S | --summary)
                SHOW_DETAILED=false
                SHOW_DETAILED_OVERRIDE=true
                shift
                ;;
            -D | --detailed)
                SHOW_DETAILED=true
                SHOW_DETAILED_OVERRIDE=true
                shift
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
            --show-ocid)
                SHOW_OCID=true
                shift
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

    # Handle unexpected positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        log_warn "Ignoring unexpected arguments: ${remaining[*]}"
    fi

    # Validate output format
    case "${OUTPUT_FORMAT}" in
        table | json | csv) : ;;
        *) die "Invalid output format: '${OUTPUT_FORMAT}'. Use table, json, or csv" ;;
    esac
}

validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Resolve compartment
    if [[ -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") || \
            die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
    fi

    # Get compartment name for display
    local comp_name
    comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="<unknown>"

    log_debug "Using root compartment OCID: $COMPARTMENT"
    log_info "Using root compartment: $comp_name (includes sub-compartments)"
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
        data-safe on-prem-connector list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )

    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function: list_targets_in_compartment
# Purpose.: List all targets in compartment
# Args....: $1 - compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON array of targets to stdout
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"
    local comp_ocid

    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing targets in compartment OCID: $comp_ocid"

    local -a cmd=(
        data-safe target-database list
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
# Function: enrich_targets_with_connector
# Purpose.: Fetch per-target details to ensure connector IDs are present
# Args....: $1 - targets JSON data
# Returns.: 0 on success
# Output..: Enriched targets JSON to stdout
# Notes...: Falls back to per-target get when list output omits connection-option
# ------------------------------------------------------------------------------
enrich_targets_with_connector() {
    local targets_json="$1"
    local -a target_ids

    mapfile -t target_ids < <(echo "$targets_json" | jq -r '.data[].id')
    local total=${#target_ids[@]}

    if [[ $total -eq 0 ]]; then
        printf '%s' "$targets_json"
        return 0
    fi

    log_info "No connector IDs found in list output; fetching target details for $total targets (may take a while)"

    local tmp_file
    tmp_file=$(mktemp)

    echo '{"data":[' > "$tmp_file"
    local first=true
    local count=0

    for target_id in "${target_ids[@]}"; do
        count=$((count + 1))

        local detail
        detail=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_id" \
            --query 'data' 2> /dev/null) || {
            log_warn "Failed to fetch target details: $target_id"
            continue
        }

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$tmp_file"
        fi

        echo "$detail" >> "$tmp_file"

        if (( count % 200 == 0 )); then
            log_info "Fetched details for $count/$total targets"
        fi
    done

    echo ']}' >> "$tmp_file"

    cat "$tmp_file"
    rm -f "$tmp_file"
}

# ------------------------------------------------------------------------------
# Function: group_targets_by_connector
# Purpose.: Group targets by their on-premises connector
# Args....: $1 - connectors JSON data
#           $2 - targets JSON data
# Returns.: 0 on success
# Output..: Grouped JSON structure to stdout
# Notes...: Creates structure with connectors as keys and arrays of targets
# ------------------------------------------------------------------------------
group_targets_by_connector() {
    local connectors_json="$1"
    local targets_json="$2"

    # Build connector map (OCID -> display-name)
    local connector_map
    connector_map=$(echo "$connectors_json" | jq -r '
        .data | map({(.id): ."display-name"}) | add // {}
    ')

    # Build connector id list for matching associated-resource-ids
    local connector_ids
    connector_ids=$(echo "$connectors_json" | jq -r '[.data[].id]')

    # Group targets by connector using associated-resource-ids or connection-option
    echo "$targets_json" | jq --argjson conn_map "$connector_map" --argjson conn_ids "$connector_ids" '
        .data | group_by(
            (
                (."associated-resource-ids" // [] | map(select(. as $id | $conn_ids | index($id))) | .[0]) //
                (."connection-option"["on-prem-connector-id"] // ."connection-option"["on-premise-connector-id"]) //
                "no-connector"
            )
        ) |
        map({
            connector_id: (
                (.[0]["associated-resource-ids"] // [] | map(select(. as $id | $conn_ids | index($id))) | .[0]) //
                (.[0]["connection-option"]["on-prem-connector-id"] // .[0]["connection-option"]["on-premise-connector-id"]) //
                "no-connector"
            ),
            connector_name: (
                if ((.[0]["associated-resource-ids"] // [] | map(select(. as $id | $conn_ids | index($id))) | .[0]) //
                    (.[0]["connection-option"]["on-prem-connector-id"] // .[0]["connection-option"]["on-premise-connector-id"] // null)) != null
                then ($conn_map[
                    (.[0]["associated-resource-ids"] // [] | map(select(. as $id | $conn_ids | index($id))) | .[0]) //
                    (.[0]["connection-option"]["on-prem-connector-id"] // .[0]["connection-option"]["on-premise-connector-id"])
                ] // "Unknown Connector")
                else "No Connector (Cloud)"
                end
            ),
            assoc_ids: (
                . | map(."associated-resource-ids" // []) | add | unique
            ),
            targets: .
        })
    '
}

# ------------------------------------------------------------------------------
# Function: show_summary_table
# Purpose.: Display summary table grouped by connector and lifecycle state
# Args....: $1 - grouped JSON data
# Returns.: 0 on success
# Output..: Formatted summary table to stdout
# ------------------------------------------------------------------------------
show_summary_table() {
    local grouped_json="$1"

    log_info "Data Safe targets summary by on-premises connector"

    # Print header
    printf "\n%-50s %-20s %10s\n" "Connector" "Lifecycle State" "Count"
    printf "%-50s %-20s %10s\n" "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..20})" "----------"

    local grand_total=0
    local connector_count
    connector_count=$(echo "$grouped_json" | jq 'length')

    # Process each connector group
    for ((i=0; i<connector_count; i++)); do
        local conn_name conn_id
        conn_name=$(echo "$grouped_json" | jq -r ".[$i].connector_name")
        conn_id=$(echo "$grouped_json" | jq -r ".[$i].connector_id")
        
        # Get lifecycle state counts for this connector
        local state_counts
        state_counts=$(echo "$grouped_json" | jq -r "
            .[$i].targets | group_by(.\"lifecycle-state\") |
            map({state: .[0].\"lifecycle-state\", count: length}) |
            sort_by(.state) | .[]
        " | jq -s '.')

        local connector_total=0
        local state_count
        state_count=$(echo "$state_counts" | jq 'length')
        
        # Print first line with connector name
        if [[ $state_count -gt 0 ]]; then
            local first_state first_count
            first_state=$(echo "$state_counts" | jq -r '.[0].state')
            first_count=$(echo "$state_counts" | jq -r '.[0].count')
            printf "%-50s %-20s %10d\n" "$conn_name" "$first_state" "$first_count"
            if [[ "${SHOW_OCID}" == "true" && "$conn_id" != "no-connector" ]]; then
                printf "%s\n" "  OCID: ${conn_id}"
            elif [[ "${SHOW_OCID}" == "true" && "$conn_id" == "no-connector" ]]; then
                local assoc_count
                assoc_count=$(echo "$grouped_json" | jq -r ".[$i].assoc_ids | length")
                if [[ $assoc_count -gt 0 ]]; then
                    local assoc_list
                    assoc_list=$(echo "$grouped_json" | jq -r ".[$i].assoc_ids[:5] | join(\" \")")
                    printf "%s\n" "  Associated IDs: ${assoc_list}"
                    if [[ $assoc_count -gt 5 ]]; then
                        printf "%s\n" "  Associated IDs: +$((assoc_count - 5)) more"
                    fi
                else
                    printf "%s\n" "  Associated IDs: <none>"
                fi
            fi
            connector_total=$((connector_total + first_count))
            
            # Print remaining states
            for ((j=1; j<state_count; j++)); do
                local state count
                state=$(echo "$state_counts" | jq -r ".[$j].state")
                count=$(echo "$state_counts" | jq -r ".[$j].count")
                printf "%-50s %-20s %10d\n" "" "$state" "$count"
                connector_total=$((connector_total + count))
            done
        fi
        
        # Print connector subtotal
        printf "%-50s %-20s %10s\n" "" "Subtotal" "$connector_total"
        grand_total=$((grand_total + connector_total))
        
        # Separator between connectors
        [[ $i -lt $((connector_count - 1)) ]] && printf "%-50s %-20s %10s\n" "" "" ""
    done

    # Print grand total
    printf "%-50s %-20s %10s\n" "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..20})" "----------"
    printf "%-50s %-20s %10d\n" "GRAND TOTAL" "" "$grand_total"
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_summary_json
# Purpose.: Display summary in JSON format
# Args....: $1 - grouped JSON data
# Returns.: 0 on success
# Output..: JSON summary to stdout
# ------------------------------------------------------------------------------
show_summary_json() {
    local grouped_json="$1"

    echo "$grouped_json" | jq 'map({
        connector_id: .connector_id,
        connector_name: .connector_name,
        lifecycle_states: (
            .targets | group_by(.["lifecycle-state"]) |
            map({
                state: .[0]["lifecycle-state"],
                count: length
            })
        ),
        total: (.targets | length)
    })'
}

# ------------------------------------------------------------------------------
# Function: show_summary_csv
# Purpose.: Display summary in CSV format
# Args....: $1 - grouped JSON data
# Returns.: 0 on success
# Output..: CSV summary to stdout
# ------------------------------------------------------------------------------
show_summary_csv() {
    local grouped_json="$1"

    echo "connector_name,lifecycle_state,count"
    
    echo "$grouped_json" | jq -r '
        .[] | 
        (.connector_name as $conn |
        .targets | group_by(.["lifecycle-state"]) |
        map([$conn, .[0]["lifecycle-state"], length]) |
        .[] | @csv)
    '
}

# ------------------------------------------------------------------------------
# Function: show_detailed_table
# Purpose.: Display detailed targets grouped by connector in table format
# Args....: $1 - grouped JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: Formatted table to stdout
# ------------------------------------------------------------------------------
show_detailed_table() {
    local grouped_json="$1"
    local fields="$2"

    log_info "Data Safe targets by on-premises connector (detailed)"

    # Convert fields to array
    local -a field_array field_widths
    IFS=',' read -ra field_array <<< "$fields"

    # Set column widths
    for field in "${field_array[@]}"; do
        if [[ "$field" == "display-name" ]]; then
            field_widths+=(50)
        else
            field_widths+=(30)
        fi
    done

    local connector_count
    connector_count=$(echo "$grouped_json" | jq 'length')

    # Process each connector group
    for ((i=0; i<connector_count; i++)); do
        local conn_name conn_id target_count
        conn_name=$(echo "$grouped_json" | jq -r ".[$i].connector_name")
        conn_id=$(echo "$grouped_json" | jq -r ".[$i].connector_id")
        target_count=$(echo "$grouped_json" | jq ".[$i].targets | length")
        
        printf "\n%s\n" "$(printf '%0.s=' {1..100})"
        if [[ "${SHOW_OCID}" == "true" && "$conn_id" != "no-connector" ]]; then
            printf "Connector: %s (%d targets)\n" "$conn_name" "$target_count"
            printf "OCID: %s\n" "$conn_id"
        elif [[ "${SHOW_OCID}" == "true" && "$conn_id" == "no-connector" ]]; then
            printf "Connector: %s (%d targets)\n" "$conn_name" "$target_count"
            local assoc_count
            assoc_count=$(echo "$grouped_json" | jq -r ".[$i].assoc_ids | length")
            if [[ $assoc_count -gt 0 ]]; then
                local assoc_list
                assoc_list=$(echo "$grouped_json" | jq -r ".[$i].assoc_ids[:5] | join(\" \")")
                printf "Associated IDs: %s\n" "$assoc_list"
                if [[ $assoc_count -gt 5 ]]; then
                    printf "Associated IDs: +%d more\n" "$((assoc_count - 5))"
                fi
            else
                printf "Associated IDs: <none>\n"
            fi
        else
            printf "Connector: %s (%d targets)\n" "$conn_name" "$target_count"
        fi
        printf "%s\n" "$(printf '%0.s=' {1..100})"
        
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
        
        # Build jq select expression
        local jq_select="["
        for field in "${field_array[@]}"; do
            jq_select+=".[\"${field}\"],"
        done
        jq_select="${jq_select%,}]"
        
        # Print targets
        echo "$grouped_json" | jq -r ".[$i].targets[] | $jq_select | @tsv" \
            | while IFS=$'\t' read -r -a values; do
                local idx=0
                for value in "${values[@]}"; do
                    local width=${field_widths[$idx]}
                    local max_len=$((width - 2))
                    
                    local display_value="${value:0:$max_len}"
                    [[ ${#value} -gt $max_len ]] && display_value="${display_value}.."
                    printf "%-${width}s " "$display_value"
                    idx=$((idx + 1))
                done
                printf "\n"
            done
        
        printf "\n"
    done
}

# ------------------------------------------------------------------------------
# Function: show_detailed_json
# Purpose.: Display detailed targets grouped by connector in JSON format
# Args....: $1 - grouped JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: JSON output to stdout
# ------------------------------------------------------------------------------
show_detailed_json() {
    local grouped_json="$1"
    local fields="$2"

    if [[ "$fields" == "all" || -z "$fields" ]]; then
        echo "$grouped_json"
    else
        # Build jq select expression for specific fields
        local jq_expr="{"
        IFS=',' read -ra field_array <<< "$fields"
        for field in "${field_array[@]}"; do
            jq_expr+="\"${field}\": .[\"${field}\"],"
        done
        jq_expr="${jq_expr%,}}"

        echo "$grouped_json" | jq "map({
            connector_id: .connector_id,
            connector_name: .connector_name,
            targets: (.targets | map($jq_expr))
        })"
    fi
}

# ------------------------------------------------------------------------------
# Function: show_detailed_csv
# Purpose.: Display detailed targets grouped by connector in CSV format
# Args....: $1 - grouped JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: CSV output to stdout
# ------------------------------------------------------------------------------
show_detailed_csv() {
    local grouped_json="$1"
    local fields="$2"

    # Print header with connector_name prepended
    echo "connector_name,$fields"

    # Convert fields to jq array
    local -a field_array
    IFS=',' read -ra field_array <<< "$fields"

    local jq_select="["
    for field in "${field_array[@]}"; do
        jq_select+=".[\"${field}\"],"
    done
    jq_select="${jq_select%,}]"

    # Print data with connector name
    echo "$grouped_json" | jq -r "
        .[] | 
        (.connector_name as \$conn |
        .targets[] |
        [\$conn] + $jq_select | @csv)
    "
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrates listing and display
# Returns.: 0 on success, 1 on error
# Output..: Target and connector information based on selected format
# ------------------------------------------------------------------------------
do_work() {
    local connectors_json targets_json grouped_json

    # Get compartment name for display
    local comp_name
    comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="$COMPARTMENT"
    log_info "Processing compartment: $comp_name (includes sub-compartments)"

    # Fetch connectors
    log_info "Fetching on-premises connectors..."
    connectors_json=$(list_connectors_in_compartment "$COMPARTMENT") || \
        die "Failed to list connectors"

    # Fetch targets
    log_info "Fetching target databases..."
    targets_json=$(list_targets_in_compartment "$COMPARTMENT") || \
        die "Failed to list targets"

    local connector_count
    connector_count=$(echo "$connectors_json" | jq '.data | length')

    local targets_with_connector
    targets_with_connector=$(echo "$targets_json" | jq '[.data[] | select((."associated-resource-ids" // [] | length) > 0 or (."connection-option"["on-prem-connector-id"] // ."connection-option"["on-premise-connector-id"] // "") != "")] | length')

    if [[ $connector_count -gt 0 && $targets_with_connector -eq 0 ]]; then
        targets_json=$(enrich_targets_with_connector "$targets_json")
    fi

    # Group targets by connector
    log_debug "Grouping targets by connector..."
    grouped_json=$(group_targets_by_connector "$connectors_json" "$targets_json")

    # Display results based on mode
    if [[ "$SHOW_DETAILED" == "true" ]]; then
        case "$OUTPUT_FORMAT" in
            table)
                show_detailed_table "$grouped_json" "$FIELDS"
                ;;
            json)
                show_detailed_json "$grouped_json" "$FIELDS"
                ;;
            csv)
                show_detailed_csv "$grouped_json" "$FIELDS"
                ;;
        esac
    else
        case "$OUTPUT_FORMAT" in
            table)
                show_summary_table "$grouped_json"
                ;;
            json)
                show_summary_json "$grouped_json"
                ;;
            csv)
                show_summary_csv "$grouped_json"
                ;;
        esac
    fi
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

    log_info "Summary completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_connector_summary.sh ------------------------------------
