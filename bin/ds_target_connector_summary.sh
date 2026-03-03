#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_connector_summary.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.02
# Version....: v0.17.4
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.18.0')"
readonly SCRIPT_VERSION
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${LIFECYCLE_STATE:=}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${SHOW_DETAILED:=false}" # Summary by default
: "${FIELDS:=display-name,lifecycle-state,infrastructure-type}"
: "${SHOW_OCID:=false}"
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${ENRICH_MISSING:=true}" # Fetch per-target details for no-connector targets

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
  List Oracle Data Safe targets grouped by on-premises connector.
  Shows summary counts by connector with lifecycle state information,
  or detailed target lists under each connector.

Options:
  Common:
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
    -q, --quiet                 Suppress INFO messages (warnings/errors only)
    -n, --dry-run               Dry-run mode (show what would be done)
        --log-file FILE         Log to file

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE:-~/.oci/config})

  Selection:
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: .env or datasafe.conf
    -L, --lifecycle STATE       Filter by lifecycle state (ACTIVE, NEEDS_ATTENTION, etc.)
                --input-json FILE       Read targets from local JSON (array or {data:[...]})
                --save-json FILE        Save selected target JSON payload

  Output:
    -S, --summary               Show summary counts (default)
    -D, --detailed              Show detailed target information per connector
    -f, --format FMT            Output format: table|json|csv (default: table)
    -F, --fields FIELDS         Comma-separated fields for detailed mode
                                (default: ${FIELDS})
        --show-ocid             Show connector OCIDs (table output)
        --no-enrich             Skip per-target enrichment; targets missing connector
                                info in list response appear as 'Cloud / Private Endpoint'
                                (useful for troubleshooting or faster output)

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

    # Run summary from saved target JSON (no target OCI list call)
    ${SCRIPT_NAME} --input-json ./target_selection.json

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

    # Reset defaults
    [[ -z "${OUTPUT_FORMAT_OVERRIDE:-}" ]] && OUTPUT_FORMAT="table"
    [[ -z "${SHOW_DETAILED_OVERRIDE:-}" ]] && SHOW_DETAILED="false"
    [[ -z "${FIELDS_OVERRIDE:-}" ]] && FIELDS="display-name,lifecycle-state,infrastructure-type"

    # Parse script-specific options
    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            "")
                shift
                ;;
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
            --input-json)
                need_val "$1" "${2:-}"
                INPUT_JSON="$2"
                shift 2
                ;;
            --save-json)
                need_val "$1" "${2:-}"
                SAVE_JSON="$2"
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
            --no-enrich)
                ENRICH_MISSING=false
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
    local -a unexpected=()
    local arg
    for arg in "${remaining[@]}"; do
        [[ -n "${arg//[[:space:]]/}" ]] && unexpected+=("$arg")
    done
    if [[ ${#unexpected[@]} -gt 0 ]]; then
        log_warn "Ignoring unexpected arguments: ${unexpected[*]}"
    fi

    # Validate output format
    case "${OUTPUT_FORMAT}" in
        table | json | csv) : ;;
        *) die "Invalid output format: '${OUTPUT_FORMAT}'. Use table, json, or csv" ;;
    esac

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

    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        if [[ -n "$COMPARTMENT" ]]; then
            log_info "Input JSON mode with optional connector name lookup from compartment: $COMPARTMENT"
        else
            log_info "Input JSON mode enabled (connector names may appear as Unknown Connector)"
        fi
    else
        require_oci_cli

        # Resolve compartment
        if [[ -z "$COMPARTMENT" ]]; then
            COMPARTMENT=$(resolve_compartment_for_operation "") \
                || die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        fi

        # Get compartment name for display
        local comp_name
        comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="<unknown>"

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
# Function: group_targets_by_connector
# Purpose.: Group targets by their on-premises connector
# Args....: $1 - connector_map JSON {ocid: display-name}
#           $2 - targets JSON data
# Returns.: 0 on success
# Output..: Grouped JSON structure to stdout
# Notes...: Uses OCID prefix to identify connector resources in
#           associated-resource-ids; no pre-fetched connector list required.
# ------------------------------------------------------------------------------
group_targets_by_connector() {
    local connector_map="$1"
    local targets_json="$2"

    echo "$targets_json" | jq --argjson conn_map "$connector_map" '
        .data | group_by(
            (."associated-resource-ids" // [] |
             map(select(startswith("ocid1.datasafeonpremconnector."))) | .[0]) //
            (."connection-option"["on-prem-connector-id"] //
             ."connection-option"["on-premise-connector-id"]) //
            "no-connector"
        ) |
        map(
            . as $group |
            (($group[0]["associated-resource-ids"] // [] |
              map(select(startswith("ocid1.datasafeonpremconnector."))) | .[0]) //
             ($group[0]["connection-option"]["on-prem-connector-id"] //
              $group[0]["connection-option"]["on-premise-connector-id"]) //
             "no-connector") as $cid |
            {
                connector_id: $cid,
                connector_name: (
                    if $cid == "no-connector" then "Cloud / Private Endpoint"
                    else ($conn_map[$cid] // "Unknown Connector")
                    end
                ),
                targets: $group
            }
        )
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
    for ((i = 0; i < connector_count; i++)); do
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
            fi
            connector_total=$((connector_total + first_count))

            # Print remaining states
            for ((j = 1; j < state_count; j++)); do
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
    for ((i = 0; i < connector_count; i++)); do
        local conn_name conn_id target_count
        conn_name=$(echo "$grouped_json" | jq -r ".[$i].connector_name")
        conn_id=$(echo "$grouped_json" | jq -r ".[$i].connector_id")
        target_count=$(echo "$grouped_json" | jq ".[$i].targets | length")

        printf "\n%s\n" "$(printf '%0.s=' {1..100})"
        printf "Connector: %s (%d targets)\n" "$conn_name" "$target_count"
        if [[ "${SHOW_OCID}" == "true" && "$conn_id" != "no-connector" ]]; then
            printf "OCID: %s\n" "$conn_id"
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
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Target and connector information based on selected format
# ------------------------------------------------------------------------------
do_work() {
    local targets_json connectors_json

    # --- Fetch / load targets ---
    if [[ -n "$INPUT_JSON" ]]; then
        log_info "Loading target databases from input JSON..."
        targets_json=$(ds_collect_targets_source "" "" "$LIFECYCLE_STATE" "" "$INPUT_JSON" "$SAVE_JSON") \
            || die "Failed to load targets from input JSON"
    else
        local comp_name
        comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="$COMPARTMENT"
        log_info "Processing compartment: $comp_name (includes sub-compartments)"
        log_info "Fetching target databases..."
        targets_json=$(ds_collect_targets_source "$COMPARTMENT" "" "$LIFECYCLE_STATE" "" "" "$SAVE_JSON") \
            || die "Failed to list targets"
    fi

    # --- Fetch connector list for name mapping ---
    connectors_json='{"data":[]}'
    if [[ -n "$COMPARTMENT" ]]; then
        log_info "Fetching on-premises connectors..."
        connectors_json=$(list_connectors_in_compartment "$COMPARTMENT") || {
            log_warn "Failed to list connectors; connector names may appear as Unknown Connector"
            connectors_json='{"data":[]}'
        }
    fi

    # --- Build connector name map {ocid: display-name} ---
    local connector_map
    connector_map=$(echo "$connectors_json" | jq '[.data[] | {(.id): ."display-name"}] | add // {}')

    # --- Per-connector get for any connector OCIDs found in targets but not in the listing ---
    # (e.g. connectors from a different compartment scope)
    local -a unknown_ocids=()
    mapfile -t unknown_ocids < <(echo "$targets_json" | jq -r --argjson cmap "$connector_map" '
        [.data[] |
            (."associated-resource-ids" // [] |
             map(select(startswith("ocid1.datasafeonpremconnector."))) | .[0]) //
            (."connection-option"["on-prem-connector-id"] //
             ."connection-option"["on-premise-connector-id"]) //
            empty
        ] | unique | .[] | select($cmap[.] == null)
    ')

    if [[ ${#unknown_ocids[@]} -gt 0 ]]; then
        log_info "Looking up ${#unknown_ocids[@]} connector(s) not in compartment listing..."
        local ocid conn_name
        for ocid in "${unknown_ocids[@]}"; do
            conn_name=$(oci_exec_ro data-safe on-prem-connector get \
                --on-prem-connector-id "$ocid" \
                --query 'data."display-name"' --raw-output 2> /dev/null) || conn_name=""
            [[ -n "$conn_name" ]] \
                && connector_map=$(echo "$connector_map" | jq --arg k "$ocid" --arg v "$conn_name" '.[$k] = $v')
        done
    fi

    # --- Initial grouping ---
    log_debug "Grouping targets by connector..."
    local grouped_json
    grouped_json=$(group_targets_by_connector "$connector_map" "$targets_json")

    # --- Post-grouping enrichment for non-DELETED targets missing connector info ---
    # The OCI target-database list API may omit connection-option for some targets.
    # Fetch individual target details only for non-DELETED targets in the no-connector group.
    # Skip when --no-enrich is set (useful for troubleshooting or faster output).
    if [[ "$ENRICH_MISSING" == "true" && -z "$INPUT_JSON" ]]; then
        local -a no_conn_active_ids=()
        mapfile -t no_conn_active_ids < <(echo "$grouped_json" | jq -r '
            .[] | select(.connector_id == "no-connector") |
            .targets[] | select(."lifecycle-state" != "DELETED") | .id
        ')

        if [[ ${#no_conn_active_ids[@]} -gt 0 ]]; then
            log_info "Enriching ${#no_conn_active_ids[@]} non-DELETED target(s) missing connector info..."

            # Build enrichment map {target-id: {connection-option, associated-resource-ids}}
            local enrichment_map='{}'
            local target_id target_detail
            local enrich_idx=0
            for target_id in "${no_conn_active_ids[@]}"; do
                enrich_idx=$((enrich_idx + 1))
                log_debug "  Fetching connector info (${enrich_idx}/${#no_conn_active_ids[@]}): ${target_id}"
                target_detail=$(oci_exec_ro data-safe target-database get \
                    --target-database-id "$target_id" 2> /dev/null \
                    | jq -c '{"connection-option": (.data["connection-option"] // null), "associated-resource-ids": (.data["associated-resource-ids"] // [])}' \
                        2> /dev/null) || target_detail='{}'
                [[ -z "$target_detail" ]] && target_detail='{}'
                enrichment_map=$(echo "$enrichment_map" | jq \
                    --arg id "$target_id" \
                    --argjson detail "$target_detail" \
                    '.[$id] = $detail')
            done

            # Merge enriched connection data back into targets_json
            targets_json=$(echo "$targets_json" | jq --argjson em "$enrichment_map" '
                .data |= map(if $em[.id] != null then . + $em[.id] else . end)
            ')

            # Look up names for any newly discovered connector OCIDs not in the map
            local -a new_conn_ocids=()
            mapfile -t new_conn_ocids < <(echo "$targets_json" | jq -r --argjson cmap "$connector_map" '
                [.data[] |
                    (."associated-resource-ids" // [] |
                     map(select(startswith("ocid1.datasafeonpremconnector."))) | .[0]) //
                    (."connection-option"["on-prem-connector-id"] //
                     ."connection-option"["on-premise-connector-id"]) //
                    empty
                ] | unique | .[] | select($cmap[.] == null)
            ')

            if [[ ${#new_conn_ocids[@]} -gt 0 ]]; then
                log_info "Looking up ${#new_conn_ocids[@]} additional connector name(s)..."
                local new_ocid new_conn_name
                for new_ocid in "${new_conn_ocids[@]}"; do
                    new_conn_name=$(oci_exec_ro data-safe on-prem-connector get \
                        --on-prem-connector-id "$new_ocid" \
                        --query 'data."display-name"' --raw-output 2> /dev/null) || new_conn_name=""
                    [[ -n "$new_conn_name" ]] \
                        && connector_map=$(echo "$connector_map" | jq --arg k "$new_ocid" --arg v "$new_conn_name" '.[$k] = $v')
                done
            fi

            # Re-group with enriched data
            log_debug "Re-grouping targets with enriched connector data..."
            grouped_json=$(group_targets_by_connector "$connector_map" "$targets_json")
        fi
    fi

    # --- Display ---
    if [[ "$SHOW_DETAILED" == "true" ]]; then
        case "$OUTPUT_FORMAT" in
            table) show_detailed_table "$grouped_json" "$FIELDS" ;;
            json) show_detailed_json "$grouped_json" "$FIELDS" ;;
            csv) show_detailed_csv "$grouped_json" "$FIELDS" ;;
        esac
    else
        case "$OUTPUT_FORMAT" in
            table) show_summary_table "$grouped_json" ;;
            json) show_summary_json "$grouped_json" ;;
            csv) show_summary_csv "$grouped_json" ;;
        esac
    fi
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
