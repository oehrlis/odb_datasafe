#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_details.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Show/export detailed info for Oracle Data Safe target databases
#              for given target names/OCIDs or all targets in a compartment.
#              Output formats: table | json | csv.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > .env > datasafe.conf > code defaults
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.22 oehrli - Complete rewrite to use v0.2.0 framework pattern
# ------------------------------------------------------------------------------

set -euo pipefail

# Script identification
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
# shellcheck disable=SC2034  # Used by parse_common_opts --version
readonly SCRIPT_NAME SCRIPT_VERSION

# Library directory
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=ACTIVE,NEEDS_ATTENTION}"
: "${FORMAT:=table}"
: "${OUTPUT_FOLDER:=${SCRIPT_DIR}/../log}"
: "${OUTPUT_FILE:=}"
: "${TO_FILE:=false}"

# Runtime variables
DETAILS_JSON='[]'
FINAL_OUTPUT_FILE=""
declare -A CONNECTOR_MAP

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
# Args....: $1 - Exit code (optional, default: 0)
# Returns.: 0 (exits after display)
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    local exit_code="${1:-0}"
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Show/export detailed information for Oracle Data Safe target databases.
  Either provide explicit targets (-T) or scan a compartment (-c).

Options:
  Target Selection:
    -T, --targets LIST          Comma-separated target names or OCIDs
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
    -L, --lifecycle STATE       Filter by lifecycle state (default: ${LIFECYCLE_STATE})
                                Comma-separated: ACTIVE,NEEDS_ATTENTION,DELETED

  Output:
    -f, --format FMT            Output format: table|json|csv (default: ${FORMAT})
    -d, --output-dir DIR        Output directory (default: ${OUTPUT_FOLDER})
                                Creates directory if it does not exist
                                Filenames: datasafe_target_details_<TARGETS>.<format>
    -o, --output FILE           Override output filename (optional)
    -w, --to-file               Write output to file instead of stdout
                                (for table/json; csv always writes to file)

  OCI:
    --oci-profile PROFILE       OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION         OCI region
    --oci-config FILE           OCI config file

  General:
    -h, --help                  Show this help
    -V, --version               Show version
    -v, --verbose               Verbose output
    -D, --debug                 Debug output
    --log-file FILE             Log to file

CSV Columns:
  datasafe_ocid, display_name, lifecycle, created_at, infra_type, target_type,
  host, port, service_name, connector_name, compartment_id, cluster, cdb, pdb

Examples:
  # Get details for specific target (JSON to stdout)
  ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_HRPDB -f json

  # Get details for specific target and write to file
  ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_HRPDB -f json -w

  # Get all ACTIVE targets in compartment as table to file
  ${SCRIPT_NAME} -c my-compartment -L ACTIVE -f table -w

  # Get details for multiple targets as CSV (always to file)
  ${SCRIPT_NAME} -T target1,target2,target3 -f csv

  # Export all targets in compartment with custom directory
  ${SCRIPT_NAME} -c prod-compartment -d /tmp/reports -f json -w

EOF
    exit "${exit_code}"
}

# ------------------------------------------------------------------------------
# Function: need_val
# Purpose.: Check if option has a value
# Args....: $1 - option name
#           $2 - value
# Returns.: 0 on success, exits on error
# Output..: None
# ------------------------------------------------------------------------------
need_val() {
    [[ -n "${2:-}" ]] || die "Option $1 requires a value"
}

# ------------------------------------------------------------------------------
# Function: parse_arguments
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# ------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                ;;
            -V | --version)
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
                exit 0
                ;;
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
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
            -f | --format)
                need_val "$1" "${2:-}"
                FORMAT="$2"
                shift 2
                ;;
            -d | --output-dir)
                need_val "$1" "${2:-}"
                OUTPUT_FOLDER="$2"
                shift 2
                ;;
            -o | --output)
                need_val "$1" "${2:-}"
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -w | --to-file)
                TO_FILE=true
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
                export OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -v | --verbose)
                export LOG_LEVEL="INFO"
                shift
                ;;
            -D | --debug)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            --log-file)
                need_val "$1" "${2:-}"
                export LOG_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and dependencies
# Args....: None
# Returns.: 0 on success, exits on validation failure
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Validate format
    FORMAT="${FORMAT,,}"
    case "${FORMAT}" in
        table | json | csv) ;;
        *) die "Unsupported format: ${FORMAT}. Use table, json, or csv." ;;
    esac

    # Create output directory if it doesn't exist
    mkdir -p "${OUTPUT_FOLDER}" 2> /dev/null \
        || die "Cannot create output directory: ${OUTPUT_FOLDER}"
    log_debug "Output directory: ${OUTPUT_FOLDER}"

    # Require explicit target selection to avoid surprising full-tenancy scans
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        log_error "Provide targets (-T) or a compartment (-c)"
        usage 1
    fi
}

# ------------------------------------------------------------------------------
# Function: build_connector_map
# Purpose.: Build mapping of connector OCIDs to names for the compartment
# Args....: $1 - compartment OCID
# Returns.: 0 on success
# Output..: Populates CONNECTOR_MAP associative array
# ------------------------------------------------------------------------------
build_connector_map() {
    local compartment_ocid="$1"

    log_debug "Building connector mapping for compartment"

    # Query connectors in compartment
    local connectors_json
    connectors_json=$(oci_exec data-safe on-prem-connector list \
        --compartment-id "$compartment_ocid" \
        --all) || {
        log_debug "No connectors found or query failed"
        return 0
    }

    # Parse and store in map
    while IFS=$'\t' read -r ocid name; do
        if [[ -n "$ocid" ]]; then
            CONNECTOR_MAP["$ocid"]="${name:-Unknown}"
        fi
    done < <(echo "$connectors_json" | jq -r '.data[]? | [.id, (."display-name" // "")] | @tsv')

    log_debug "Mapped ${#CONNECTOR_MAP[@]} connectors"
    return 0
}

# ------------------------------------------------------------------------------
# Function: collect_target_details
# Purpose.: Fetch detailed information for target and add to DETAILS_JSON
# Args....: $1 - target OCID
# Returns.: 0 on success, 1 on error
# Output..: Updates DETAILS_JSON array
# ------------------------------------------------------------------------------
collect_target_details() {
    local target_ocid="$1"
    local target_name

    target_name=$(ds_resolve_target_name "$target_ocid" 2> /dev/null) || target_name="$target_ocid"

    log_debug "Processing: $target_name"

    # Fetch target details
    local target_json
    target_json=$(oci_exec data-safe target-database get \
        --target-database-id "$target_ocid") || {
        log_error "Failed to get details for $target_name"
        return 1
    }

    # Extract fields
    local data
    data=$(echo "$target_json" | jq -r '.data')

    local disp lcst created infra ttype host port svc compid
    disp=$(echo "$data" | jq -r '."display-name" // ""')
    lcst=$(echo "$data" | jq -r '."lifecycle-state" // ""' | tr '[:lower:]' '[:upper:]')
    created=$(echo "$data" | jq -r '."time-created" // ""')
    infra=$(echo "$data" | jq -r '."infrastructure-type" // ""')
    ttype=$(echo "$data" | jq -r '."database-type" // ""')

    # Connection details
    local conn_option
    conn_option=$(echo "$data" | jq -r '."connection-option" // {}')

    # Try to parse connection string
    local conn_string
    conn_string=$(echo "$conn_option" | jq -r '."connection-string" // empty')

    if [[ -n "$conn_string" ]]; then
        # Parse connection string format: host:port/service
        host=$(echo "$conn_string" | cut -d: -f1)
        port=$(echo "$conn_string" | cut -d: -f2 | cut -d/ -f1)
        svc=$(echo "$conn_string" | cut -d/ -f2-)
    else
        host=""
        port=""
        svc=""
    fi

    compid=$(echo "$data" | jq -r '."compartment-id" // ""')

    # Get connector info
    local conn_ocid conn_name
    conn_ocid=$(echo "$conn_option" | jq -r '."on-prem-connector-id" // empty')

    if [[ -n "$conn_ocid" && -n "${CONNECTOR_MAP[$conn_ocid]:-}" ]]; then
        conn_name="${CONNECTOR_MAP[$conn_ocid]}"
    elif [[ -n "$conn_ocid" ]]; then
        conn_name="Unknown"
    else
        conn_name="N/A"
    fi

    # Parse display name for cluster/cdb/pdb
    local cluster cdb pdb
    if [[ "$disp" =~ ^([^_]+)_([^_]+)_(.+)$ ]]; then
        cluster="${BASH_REMATCH[1]}"
        cdb="${BASH_REMATCH[2]}"
        pdb="${BASH_REMATCH[3]}"
    elif [[ "$disp" =~ ^([^_]+)_(.+)$ ]]; then
        cluster=""
        cdb="${BASH_REMATCH[1]}"
        pdb="${BASH_REMATCH[2]}"
    else
        cluster=""
        cdb="$disp"
        pdb=""
    fi

    # Build JSON record
    local record
    record=$(jq -n \
        --arg ocid "$target_ocid" \
        --arg disp "$disp" \
        --arg lcst "$lcst" \
        --arg created "$created" \
        --arg infra "$infra" \
        --arg ttype "$ttype" \
        --arg host "$host" \
        --arg port "$port" \
        --arg svc "$svc" \
        --arg conn "$conn_name" \
        --arg comp "$compid" \
        --arg cluster "$cluster" \
        --arg cdb "$cdb" \
        --arg pdb "$pdb" \
        '{
            datasafe_ocid: $ocid,
            display_name: $disp,
            lifecycle: $lcst,
            created_at: $created,
            infra_type: $infra,
            target_type: $ttype,
            host: $host,
            port: $port,
            service_name: $svc,
            connector_name: $conn,
            compartment_id: $comp,
            cluster: $cluster,
            cdb: $cdb,
            pdb: $pdb
        }')

    # Add to array
    DETAILS_JSON=$(echo "$DETAILS_JSON" | jq -c --argjson row "$record" '. + [$row]')

    return 0
}

# ------------------------------------------------------------------------------
# Function: compute_output_filename
# Purpose.: Compute output filename based on targets and format
# Args....: None (uses TARGETS, OUTPUT_FOLDER, OUTPUT_FILE, FORMAT)
# Returns.: 0 on success
# Output..: Sets FINAL_OUTPUT_FILE variable
# ------------------------------------------------------------------------------
compute_output_filename() {
    # If user specified explicit filename, use it
    if [[ -n "${OUTPUT_FILE}" ]]; then
        FINAL_OUTPUT_FILE="${OUTPUT_FILE}"
        log_debug "Using explicit output file: ${FINAL_OUTPUT_FILE}"
        return 0
    fi

    # Generate filename from targets or use summary
    local base_name="datasafe_target_details"
    local target_part=""

    if [[ -n "${TARGETS}" ]]; then
        # Use first target name or identifier for filename
        local first_target
        first_target=$(echo "${TARGETS}" | cut -d, -f1 | xargs)
        if is_ocid "${first_target}"; then
            # Extract display name from context or use OCID prefix
            target_part="$(echo "${first_target}" | cut -d. -f6-)"
        else
            target_part="${first_target}"
        fi
        # Replace spaces with underscores
        target_part="${target_part// /_}"
        base_name="${base_name}_${target_part}"
    else
        # Compartment mode, use compartment name if available
        if [[ -n "${COMPARTMENT}" ]]; then
            local comp_part
            if is_ocid "${COMPARTMENT}"; then
                comp_part="$(echo "${COMPARTMENT}" | cut -d. -f6-)"
            else
                comp_part="${COMPARTMENT}"
            fi
            comp_part="${comp_part// /_}"
            base_name="${base_name}_${comp_part}"
        else
            base_name="${base_name}_summary"
        fi
    fi

    # Append format extension
    FINAL_OUTPUT_FILE="${OUTPUT_FOLDER}/${base_name}.${FORMAT}"
    log_debug "Computed output file: ${FINAL_OUTPUT_FILE}"
    return 0
}

# ------------------------------------------------------------------------------
# Function: emit_output
# Purpose.: Output collected details in requested format
# Args....: None
# Returns.: 0 on success
# Output..: Details to stdout or file depending on format and TO_FILE flag
# Notes...: CSV always writes to file; json/table default to stdout unless TO_FILE=true
# ------------------------------------------------------------------------------
emit_output() {
    local count
    count=$(echo "$DETAILS_JSON" | jq 'length')

    case "$FORMAT" in
        json)
            if [[ "$TO_FILE" == "true" ]]; then
                echo "$DETAILS_JSON" | jq . > "${FINAL_OUTPUT_FILE}"
                log_info "Wrote $count targets as JSON to ${FINAL_OUTPUT_FILE}"
            else
                echo "$DETAILS_JSON" | jq .
                log_info "Output $count targets as JSON"
            fi
            ;;

        table)
            if [[ "$count" -eq 0 ]]; then
                log_info "No target details to display"
                return 0
            fi

            if [[ "$TO_FILE" == "true" ]]; then
                {
                    echo "$DETAILS_JSON" | jq -r '.[] | [
                        .display_name, .datasafe_ocid, .lifecycle, .created_at,
                        .infra_type, .target_type, .host, (.port // ""), .service_name,
                        .connector_name, .compartment_id, .cluster, .cdb, .pdb
                    ] | @tsv' | while IFS=$'\t' read -r \
                        disp ocid lifecycle created infra ttype host port svc conn comp cluster cdb pdb; do
                        printf "%-30s | %-50s | %-15s | %-20s | %s / %s\n" \
                            "$disp" "$ocid" "$lifecycle" "$created" "$infra" "$ttype"
                    done
                } > "${FINAL_OUTPUT_FILE}"
                log_info "Wrote $count targets as table to ${FINAL_OUTPUT_FILE}"
            else
                local i=0
                echo "$DETAILS_JSON" | jq -r '.[] | [
                    .display_name, .datasafe_ocid, .lifecycle, .created_at,
                    .infra_type, .target_type, .host, (.port // ""), .service_name,
                    .connector_name, .compartment_id, .cluster, .cdb, .pdb
                ] | @tsv' | while IFS=$'\t' read -r \
                    disp ocid lifecycle created infra ttype host port svc conn comp cluster cdb pdb; do
                    i=$((i + 1)) || true
                    printf "\n"
                    printf "== Target %d ======================================================\n" "$i"
                    printf "Display Name   : %s\n" "$disp"
                    printf "OCID           : %s\n" "$ocid"
                    printf "Lifecycle      : %s\n" "$lifecycle"
                    printf "Created        : %s\n" "$created"
                    printf "Infra/Type     : %s / %s\n" "$infra" "$ttype"
                    printf "Connection     : %s:%s/%s\n" "$host" "$port" "$svc"
                    printf "Connector      : %s\n" "$conn"
                    printf "Compartment    : %s\n" "$comp"
                    printf "Cluster/CDB/PDB: %s / %s / %s\n" "$cluster" "$cdb" "$pdb"
                done
                printf "\n"
                log_info "Displayed $count targets"
            fi
            ;;

        csv)
            {
                echo 'datasafe_ocid,display_name,lifecycle,created_at,infra_type,target_type,host,port,service_name,connector_name,compartment_id,cluster,cdb,pdb'
                echo "$DETAILS_JSON" | jq -r '.[] | [
                    .datasafe_ocid, .display_name, .lifecycle, .created_at,
                    .infra_type, .target_type, .host, (.port // ""),
                    .service_name, .connector_name, .compartment_id,
                    .cluster, .cdb, .pdb
                ] | @csv'
            } > "${FINAL_OUTPUT_FILE}"

            log_info "Wrote $count target details to ${FINAL_OUTPUT_FILE}"
            ;;
    esac

    return 0
}

# ------------------------------------------------------------------------------
# Function: list_targets_in_compartment
# Purpose.: List targets in compartment matching lifecycle state filter
# Args....: $1 - compartment OCID
# Returns.: 0 on success
# Output..: Tab-separated target OCIDs and names
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment_ocid="$1"

    log_debug "Listing targets in compartment with lifecycle filter: $LIFECYCLE_STATE"

    local targets_json
    targets_json=$(ds_list_targets "$compartment_ocid" "$LIFECYCLE_STATE") || {
        log_error "Failed to list targets in compartment"
        return 1
    }

    # Output OCID and name
    echo "$targets_json" | jq -r '.data[]? | [.id, (."display-name" // "")] | @tsv'

    return 0
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - discover targets and collect details
# Args....: None
# Returns.: 0 on success, 1 on error
# ------------------------------------------------------------------------------
do_work() {
    local -a target_ocids=()
    local compartment_ocid=""

    # Collect target OCIDs
    if [[ -n "$TARGETS" ]]; then
        # Process explicit targets
        log_info "Processing explicit targets"

        # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
        compartment_ocid=$(resolve_compartment_for_operation "$COMPARTMENT") \
            || die "Failed to resolve compartment for target resolution"

        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces

            if is_ocid "$target"; then
                target_ocids+=("$target")
            else
                # Resolve name to OCID in compartment
                local target_ocid
                target_ocid=$(ds_resolve_target_ocid "$target" "$compartment_ocid") || {
                    log_error "Failed to resolve target: $target"
                    continue
                }
                target_ocids+=("$target_ocid")
            fi
        done
    else
        # Scan compartment
        log_info "Scanning compartment for targets"

        # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
        compartment_ocid=$(resolve_compartment_for_operation "$COMPARTMENT") \
            || die "Failed to resolve compartment for target scan"

        # List targets in compartment
        local targets_data
        targets_data=$(list_targets_in_compartment "$compartment_ocid") \
            || die "Failed to list targets in compartment"

        while IFS=$'\t' read -r ocid name; do
            [[ -n "$ocid" ]] && target_ocids+=("$ocid")
        done <<< "$targets_data"
    fi

    # Check if we have targets
    if [[ ${#target_ocids[@]} -eq 0 ]]; then
        log_warn "No targets found matching criteria"
        return 0
    fi

    log_info "Found ${#target_ocids[@]} targets to process"

    # Build connector map if we have a compartment
    if [[ -n "$compartment_ocid" ]]; then
        build_connector_map "$compartment_ocid"
    fi

    # Collect details for each target
    log_info "Collecting target details..."
    DETAILS_JSON='[]'
    local success_count=0
    local error_count=0

    for target_ocid in "${target_ocids[@]}"; do
        if collect_target_details "$target_ocid"; then
            ((success_count++)) || true
        else
            ((error_count++)) || true
        fi
    done

    log_info "Collection completed: $success_count successful, $error_count errors"

    # Compute output filename and emit output
    compute_output_filename
    emit_output

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Require at least one argument to avoid accidental full scans
    if [[ $# -eq 0 ]]; then
        usage 1
    fi

    # Parse arguments
    parse_arguments "$@"

    # Validate inputs
    validate_inputs

    # Execute main work
    if do_work; then
        log_info "Target details collection completed successfully"
    else
        die "Target details collection failed"
    fi
}

main "$@"

exit 0
