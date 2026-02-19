#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_tg_report.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Generate reports for Oracle Data Safe targets and tags
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

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${REPORT_TYPE:=all}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${TAG_NAMESPACE:=DBSec}"

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
# Purpose.: Display usage information and help message
# Returns.: 0 (exits after display)
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Generate reports for Oracle Data Safe targets and their tags.
  Shows tag status, environment distribution, and missing tags.

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
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP from \$ODB_DATASAFE_BASE/.env)

  Report Options:
    -r, --report TYPE       Report type: all|tags|env|missing|undef (default: ${REPORT_TYPE})
    -f, --format FMT        Output format: table|json|csv (default: ${OUTPUT_FORMAT})
    --namespace NS          Tag namespace (default: ${TAG_NAMESPACE})

Report Types:
  all       - All reports
  tags      - All targets with tags
  env       - Environment distribution
  missing   - Targets missing tags
  undef     - Targets with undefined tag values

Examples:
  # Show all reports for DS_ROOT_COMP
  ${SCRIPT_NAME}

  # Show environment distribution
  ${SCRIPT_NAME} -r env

  # Show targets with undefined tags
  ${SCRIPT_NAME} -r undef

  # Export all target tags as CSV
  ${SCRIPT_NAME} -r tags -f csv > targets_tags.csv

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on invalid arguments
# Notes...: Sets global variables for script configuration
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

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
            -r | --report)
                need_val "$1" "${2:-}"
                REPORT_TYPE="$2"
                shift 2
                ;;
            -f | --format)
                need_val "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --namespace)
                need_val "$1" "${2:-}"
                TAG_NAMESPACE="$2"
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

    # Validate report type
    case "$REPORT_TYPE" in
        all | tags | env | missing | undef) : ;;
        *) die "Invalid report type: $REPORT_TYPE. Use all, tags, env, missing, or undef" ;;
    esac

    # Validate output format
    case "$OUTPUT_FORMAT" in
        table | json | csv) : ;;
        *) die "Invalid format: $OUTPUT_FORMAT. Use table, json, or csv" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and dependencies
# Returns.: 0 on success, exits on validation failure
# Notes...: Checks for required commands and sets default compartment if needed
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Resolve compartment using new pattern: explicit -c > DS_ROOT_COMP > error
    if [[ -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi
}

# ------------------------------------------------------------------------------
# Function: get_targets_with_tags
# Purpose.: Get all targets with their tag information
# Returns.: 0 on success, 1 on error
# Output..: JSON array of targets with tags to stdout
# ------------------------------------------------------------------------------
get_targets_with_tags() {
    local comp_ocid
    comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT") || return 1

    log_debug "Fetching targets with tags from compartment: $comp_ocid"

    ds_list_targets "$comp_ocid"
}

# ------------------------------------------------------------------------------
# Function: report_all_tags
# Purpose.: Show all targets with their tags
# Returns.: 0 on success
# Output..: Formatted report to stdout based on OUTPUT_FORMAT setting
# ------------------------------------------------------------------------------
report_all_tags() {
    log_info "All Data Safe targets with ${TAG_NAMESPACE} tags"
    echo

    local targets_json
    targets_json=$(get_targets_with_tags)

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo "$targets_json" | jq -r "
            .data[] | 
            [
                .\"display-name\",
                .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.Classification // \"unset\"
            ] | 
            @tsv
        " | {
            printf "%-50s %-15s %-15s %-15s %-15s\n" \
                "Display Name" "Environment" "ContainerStage" "ContainerType" "Classification"
            printf "%-50s %-15s %-15s %-15s %-15s\n" \
                "$(printf '%.50s' '--------------------------------------------------')" \
                "$(printf '%.15s' '---------------')" \
                "$(printf '%.15s' '---------------')" \
                "$(printf '%.15s' '---------------')" \
                "$(printf '%.15s' '---------------')"

            while IFS=$'\t' read -r name env stage type class; do
                printf "%-50s %-15s %-15s %-15s %-15s\n" \
                    "${name:0:48}" "$env" "$stage" "$type" "$class"
            done
        }
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "Display Name,Environment,ContainerStage,ContainerType,Classification"
        echo "$targets_json" | jq -r "
            .data[] | 
            [
                .\"display-name\",
                .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.Classification // \"unset\"
            ] | 
            @csv
        "
    else # json
        echo "$targets_json" | jq ".data[] | {
            \"display-name\": .\"display-name\",
            \"environment\": .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\",
            \"container-stage\": .\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\",
            \"container-type\": .\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\",
            \"classification\": .\"defined-tags\".${TAG_NAMESPACE}.Classification // \"unset\"
        }"
    fi
    echo
}

# ------------------------------------------------------------------------------
# Function: report_environment_distribution
# Purpose.: Show environment distribution summary
# Returns.: 0 on success
# Output..: Environment distribution statistics to stdout
# ------------------------------------------------------------------------------
report_environment_distribution() {
    log_info "Environment distribution summary"
    echo

    local targets_json
    targets_json=$(get_targets_with_tags)

    # Count by environment
    local counts
    counts=$(echo "$targets_json" | jq -r "
        .data[] | 
        .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\"
    " | sort | uniq -c | sort -rn)

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        printf "%-15s %10s\n" "Environment" "Count"
        printf "%-15s %10s\n" "---------------" "----------"

        local total=0
        while read -r count env; do
            printf "%-15s %10d\n" "$env" "$count"
            total=$((total + count))
        done <<< "$counts"

        printf "%-15s %10s\n" "---------------" "----------"
        printf "%-15s %10d\n" "TOTAL" "$total"
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "Environment,Count"
        while read -r count env; do
            echo "$env,$count"
        done <<< "$counts"
    else # json
        echo "$counts" | jq -Rs '
            split("\n") | 
            map(select(length > 0)) | 
            map(split(" ") | {environment: .[1], count: .[0] | tonumber})
        '
    fi
    echo
}

# ------------------------------------------------------------------------------
# Function: report_undefined_tags
# Purpose.: Show targets with undefined tag values
# Returns.: 0 on success
# Output..: List of targets with undefined tags to stdout
# ------------------------------------------------------------------------------
report_undefined_tags() {
    log_info "Targets with undefined (undef) tag values"
    echo

    local targets_json
    targets_json=$(get_targets_with_tags)

    # Filter targets with any "undef" tag values
    local undef_targets
    undef_targets=$(echo "$targets_json" | jq "
        .data[] | 
        select(
            (.\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\") == \"undef\" or
            (.\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\") == \"undef\" or
            (.\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\") == \"undef\" or
            (.\"defined-tags\".${TAG_NAMESPACE}.Classification // \"unset\") == \"undef\"
        )
    ")

    if [[ -z "$undef_targets" || "$undef_targets" == "null" ]]; then
        log_info "No targets found with undefined tag values"
        return 0
    fi

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo "$undef_targets" | jq -r "
            [
                .\"display-name\",
                .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\"
            ] | 
            @tsv
        " | {
            printf "%-50s %-15s %-15s %-15s\n" \
                "Display Name" "Environment" "ContainerStage" "ContainerType"
            printf "%-50s %-15s %-15s %-15s\n" \
                "$(printf '%.50s' '--------------------------------------------------')" \
                "$(printf '%.15s' '---------------')" \
                "$(printf '%.15s' '---------------')" \
                "$(printf '%.15s' '---------------')"

            while IFS=$'\t' read -r name env stage type; do
                printf "%-50s %-15s %-15s %-15s\n" \
                    "${name:0:48}" "$env" "$stage" "$type"
            done
        }
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "Display Name,Environment,ContainerStage,ContainerType"
        echo "$undef_targets" | jq -r "
            [
                .\"display-name\",
                .\"defined-tags\".${TAG_NAMESPACE}.Environment // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerStage // \"unset\",
                .\"defined-tags\".${TAG_NAMESPACE}.ContainerType // \"unset\"
            ] | 
            @csv
        "
    else # json
        echo "$undef_targets"
    fi
    echo
}

# ------------------------------------------------------------------------------
# Function: report_missing_tags
# Purpose.: Show targets missing tag namespace or specific tags
# Returns.: 0 on success
# Output..: List of targets missing tags to stdout
# ------------------------------------------------------------------------------
report_missing_tags() {
    log_info "Targets missing ${TAG_NAMESPACE} tags"
    echo

    local targets_json
    targets_json=$(get_targets_with_tags)

    # Filter targets without the tag namespace
    local missing_targets
    missing_targets=$(echo "$targets_json" | jq "
        .data[] | 
        select(.\"defined-tags\".${TAG_NAMESPACE} == null)
    ")

    if [[ -z "$missing_targets" || "$missing_targets" == "null" ]]; then
        log_info "No targets found missing ${TAG_NAMESPACE} tag namespace"
        return 0
    fi

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo "$missing_targets" | jq -r '.["display-name"]' | {
            printf "%-50s\n" "Display Name"
            printf "%-50s\n" "$(printf '%.50s' '--------------------------------------------------')"

            while read -r name; do
                printf "%-50s\n" "${name:0:48}"
            done
        }
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "Display Name"
        echo "$missing_targets" | jq -r '.["display-name"]'
    else # json
        echo "$missing_targets"
    fi
    echo
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrates report generation
# Returns.: 0 on success
# Output..: Report output based on REPORT_TYPE setting
# Notes...: Dispatches to appropriate report function based on REPORT_TYPE
# ------------------------------------------------------------------------------
do_work() {
    case "$REPORT_TYPE" in
        all)
            report_all_tags
            report_environment_distribution
            report_undefined_tags
            report_missing_tags
            ;;
        tags)
            report_all_tags
            ;;
        env)
            report_environment_distribution
            ;;
        undef)
            report_undefined_tags
            ;;
        missing)
            report_missing_tags
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Returns.: 0 on success, 1 on error
# Notes...: Initializes configuration, validates inputs, and executes work
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Execute main work
    do_work

    log_info "Report completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_tg_report.sh ---------------------------------------------------
