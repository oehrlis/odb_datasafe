#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_list.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.14
# Version....: v0.5.3
# Purpose....: List Oracle Data Safe target databases with summary or details
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null | tr -d '\n' || echo '0.5.3')"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${SHOW_COUNT:=false}"    # Default to list mode
: "${FIELDS:=display-name,lifecycle-state,infrastructure-type}"

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

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
  List Oracle Data Safe target databases. Display summary counts or detailed
  information based on compartment and lifecycle state filters.

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
    -T, --targets LIST      Comma-separated target names or OCIDs (for details only)
    -L, --lifecycle STATE   Filter by lifecycle state (ACTIVE, NEEDS_ATTENTION, etc.)

  Output:
    -C, --count             Show summary count by lifecycle state
    -D, --details           Show detailed target information (default)
    -f, --format FMT        Output format: table|json|csv (default: table)
    -F, --fields FIELDS     Comma-separated fields for details (default: ${FIELDS})

Examples:
  # Show detailed list for DS_ROOT_COMP (default)
  ${SCRIPT_NAME}

  # Show count summary
  ${SCRIPT_NAME} -C

  # Show count for specific compartment
  ${SCRIPT_NAME} -C -c MyCompartment

  # Show count for NEEDS_ATTENTION only
  ${SCRIPT_NAME} -C -L NEEDS_ATTENTION

  # Show list for NEEDS_ATTENTION (quiet mode)
  ${SCRIPT_NAME} -q -L NEEDS_ATTENTION

  # Show detailed list as JSON
  ${SCRIPT_NAME} -f json

  # Show specific fields as CSV
  ${SCRIPT_NAME} -D -f csv -F display-name,id,lifecycle-state

  # Show details for specific targets
  ${SCRIPT_NAME} -D -T target1,target2

EOF
    exit 0
}

parse_args() {
    parse_common_opts "$@"

    # Reset defaults (override any env/config values)
    # These can be explicitly set via command-line options
    [[ -z "${OUTPUT_FORMAT_OVERRIDE:-}" ]] && OUTPUT_FORMAT="table"
    [[ -z "${SHOW_COUNT_OVERRIDE:-}" ]] && SHOW_COUNT="false"
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
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -C | --count)
                SHOW_COUNT=true
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            -D | --details)
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
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

    # Handle positional arguments (treat as targets)
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi

    # Validate output format
    case "${OUTPUT_FORMAT}" in
        table | json | csv) : ;;
        *) die "Invalid output format: '${OUTPUT_FORMAT}'. Use table, json, or csv" ;;
    esac
}

validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq

    # If neither targets nor compartment specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        COMPARTMENT="$root_comp"

        # Get compartment name for display
        local comp_name
        comp_name=$(oci_get_compartment_name "$root_comp") || comp_name="<unknown>"

        log_debug "Using root compartment OCID: $COMPARTMENT"
        log_info "Using root compartment: $comp_name (includes sub-compartments)"
    fi

    # Count mode doesn't work with specific targets
    if [[ "$SHOW_COUNT" == "true" && -n "$TARGETS" ]]; then
        die "Count mode (-C) cannot be used with specific targets (-T). Use --details instead."
    fi
}

# ------------------------------------------------------------------------------
# Function....: list_targets_in_compartment
# Purpose.....: List all targets in compartment
# Parameters..: $1 - compartment OCID or name
# Returns.....: JSON array of targets
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
# Function....: get_target_details
# Purpose.....: Get details for specific target
# Parameters..: $1 - target OCID
# Returns.....: JSON object
# ------------------------------------------------------------------------------
get_target_details() {
    local target_ocid="$1"

    log_debug "Getting details for: $target_ocid"

    oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function....: show_count_summary
# Purpose.....: Display count summary grouped by lifecycle state
# Parameters..: $1 - JSON data
# ------------------------------------------------------------------------------
show_count_summary() {
    local json_data="$1"

    log_info "Data Safe targets summary by lifecycle state"

    # Extract and count lifecycle states
    local counts
    counts=$(echo "$json_data" | jq -r '.data[]."lifecycle-state"' | sort | uniq -c | sort -rn)

    if [[ -z "$counts" ]]; then
        log_info "No targets found"
        return 0
    fi

    # Print table header
    printf "\n%-20s %10s\n" "Lifecycle State" "Count"
    printf "%-20s %10s\n" "-------------------" "----------"

    # Print counts
    local total=0
    while read -r count state; do
        printf "%-20s %10d\n" "$state" "$count"
        total=$((total + count))
    done <<< "$counts"

    printf "%-20s %10s\n" "-------------------" "----------"
    printf "%-20s %10d\n" "TOTAL" "$total"
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function....: show_details_table
# Purpose.....: Display detailed target information in table format
# Parameters..: $1 - JSON data
#               $2 - fields (comma-separated)
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
    printf "\nTotal: %d targets\n\n" "$count"
}

# ------------------------------------------------------------------------------
# Function....: show_details_json
# Purpose.....: Display detailed target information in JSON format
# Parameters..: $1 - JSON data
#               $2 - fields (comma-separated)
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
# Function....: show_details_csv
# Purpose.....: Display detailed target information in CSV format
# Parameters..: $1 - JSON data
#               $2 - fields (comma-separated)
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
# Function....: do_work
# Purpose.....: Main work function
# ------------------------------------------------------------------------------
do_work() {
    local json_data

    # Collect target data
    if [[ -n "$TARGETS" ]]; then
        # Get details for specific targets
        log_info "Fetching details for specific targets..."

        local -a target_list target_ocids
        IFS=',' read -ra target_list <<< "$TARGETS"

        # Resolve target names to OCIDs
        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces

            if is_ocid "$target"; then
                target_ocids+=("$target")
            else
                log_debug "Resolving target name: $target"
                local resolved
                if [[ -n "$COMPARTMENT" ]]; then
                    resolved=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || die "Failed to resolve target: $target"
                else
                    local root_comp
                    root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
                    resolved=$(ds_resolve_target_ocid "$target" "$root_comp") || die "Failed to resolve target: $target"
                fi

                if [[ -z "$resolved" ]]; then
                    die "Target not found: $target"
                fi

                target_ocids+=("$resolved")
            fi
        done

        # Fetch details for each target and combine into array
        local -a target_details
        for target_ocid in "${target_ocids[@]}"; do
            local details
            details=$(get_target_details "$target_ocid") || {
                log_warn "Failed to get details for: $target_ocid"
                continue
            }
            target_details+=("$details")
        done

        # Combine into JSON structure
        json_data="{\"data\":["
        local first=true
        for detail in "${target_details[@]}"; do
            [[ "$first" == "true" ]] && first=false || json_data+=","
            json_data+="$detail"
        done
        json_data+="]}"

    else
        # List targets from compartment hierarchy
        local comp_name
        comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="$COMPARTMENT"
        log_info "Listing targets in compartment: $comp_name (includes sub-compartments)"
        json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"
    fi

    # Display results based on mode
    if [[ "$SHOW_COUNT" == "true" ]]; then
        show_count_summary "$json_data"
    else
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

    log_info "List completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_list.sh -------------------------------------------------
