#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_details.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.22
# Version....: v0.5.3
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

# Script identification
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="$(grep -E '^\s*version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' || echo 'v0.5.3')"

# Library directory
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=ACTIVE,NEEDS_ATTENTION}"
: "${OUTPUT_TYPE:=csv}"
: "${OUTPUT_FILE:=./datasafe_target_details.csv}"

# Runtime variables
DETAILS_JSON='[]'
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
# Returns.: 0 (exits after display)
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
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
    -O, --output-type TYPE      Output format: csv|json|table (default: ${OUTPUT_TYPE})
    -o, --output FILE           Output file path for csv (default: ${OUTPUT_FILE})

  OCI:
    --oci-profile PROFILE       OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION         OCI region
    --oci-config FILE           OCI config file

  General:
    -h, --help                  Show this help
    -V, --version               Show version
    -v, --verbose               Verbose output
    -d, --debug                 Debug output
    --log-file FILE             Log to file

CSV Columns:
  datasafe_ocid, display_name, lifecycle, created_at, infra_type, target_type,
  host, port, service_name, connector_name, compartment_id, cluster, cdb, pdb

Examples:
  # Get details for specific target (CSV)
  ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_HRPDB

  # Get all ACTIVE targets in compartment as JSON
  ${SCRIPT_NAME} -c my-compartment -L ACTIVE -O json

  # Get details for multiple targets as table
  ${SCRIPT_NAME} -T target1,target2,target3 -O table

  # Export all targets in compartment to custom file
  ${SCRIPT_NAME} -c prod-compartment -o /tmp/targets.csv

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: need_val
# Purpose.: Check if option has a value
# Args....: $1 - option name, $2 - value
# Returns.: 0 on success, exits on error
# ------------------------------------------------------------------------------
need_val() {
    [[ -n "${2:-}" ]] || die "Option $1 requires a value"
}

# ------------------------------------------------------------------------------
# Function: parse_arguments
# Purpose.: Parse command-line arguments
# Returns.: 0 on success, exits on error
# ------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -V|--version)
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
                exit 0
                ;;
            -T|--targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -c|--compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -L|--lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -O|--output-type)
                need_val "$1" "${2:-}"
                OUTPUT_TYPE="$2"
                shift 2
                ;;
            -o|--output)
                need_val "$1" "${2:-}"
                OUTPUT_FILE="$2"
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
                export OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="INFO"
                shift
                ;;
            -d|--debug)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --log-file)
                need_val "$1" "${2:-}"
                LOG_FILE="$2"
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
# Returns.: 0 on success, exits on validation failure
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq

    # Validate output type
    OUTPUT_TYPE="${OUTPUT_TYPE,,}"
    case "${OUTPUT_TYPE}" in
        csv|json|table) ;;
        *) die "Unsupported output type: ${OUTPUT_TYPE}. Use csv, json, or table." ;;
    esac

    # Ensure output directory exists for CSV
    if [[ "${OUTPUT_TYPE}" == "csv" ]]; then
        local output_dir
        output_dir="$(dirname "${OUTPUT_FILE}")"
        mkdir -p "${output_dir}" 2>/dev/null || true
    fi

    # If neither targets nor compartment specified, use DS_ROOT_COMP
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
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
# ------------------------------------------------------------------------------
collect_target_details() {
    local target_ocid="$1"
    local target_name

    target_name=$(ds_resolve_target_name "$target_ocid" 2>/dev/null) || target_name="$target_ocid"
    
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
# Function: emit_output
# Purpose.: Output collected details in requested format
# Returns.: 0 on success
# Output..: Details to stdout or file depending on format
# ------------------------------------------------------------------------------
emit_output() {
    local count
    count=$(echo "$DETAILS_JSON" | jq 'length')
    
    case "$OUTPUT_TYPE" in
        json)
            echo "$DETAILS_JSON" | jq .
            log_info "Output $count targets as JSON"
            ;;
            
        table)
            if [[ "$count" -eq 0 ]]; then
                log_info "No target details to display"
                return 0
            fi

            local i=0
            echo "$DETAILS_JSON" | jq -r '.[] | [
                .display_name, .datasafe_ocid, .lifecycle, .created_at,
                .infra_type, .target_type, .host, (.port // ""), .service_name,
                .connector_name, .compartment_id, .cluster, .cdb, .pdb
            ] | @tsv' | while IFS=$'\t' read -r \
                disp ocid lifecycle created infra ttype host port svc conn comp cluster cdb pdb; do
                ((i++)) || true
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
            } > "$OUTPUT_FILE"
            
            log_info "Wrote $count target details to $OUTPUT_FILE"
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
    
    # Build lifecycle filter
    local -a lifecycle_filters=()
    IFS=',' read -ra states <<< "$LIFECYCLE_STATE"
    for state in "${states[@]}"; do
        lifecycle_filters+=(--lifecycle-state "${state// /}")
    done
    
    # Query targets
    local targets_json
    targets_json=$(oci_exec data-safe target-database list \
        --compartment-id "$compartment_ocid" \
        "${lifecycle_filters[@]}" \
        --all) || {
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
# Returns.: 0 on success, 1 on error
# ------------------------------------------------------------------------------
do_work() {
    local -a target_ocids=()
    local compartment_ocid=""
    
    # Collect target OCIDs
    if [[ -n "$TARGETS" ]]; then
        # Process explicit targets
        log_info "Processing explicit targets"
        
        # Get compartment OCID for target resolution
        if [[ -n "$COMPARTMENT" ]]; then
            if is_ocid "$COMPARTMENT"; then
                compartment_ocid="$COMPARTMENT"
            else
                compartment_ocid=$(resolve_compartment_ocid "$COMPARTMENT") || \
                    die "Failed to resolve compartment: $COMPARTMENT"
            fi
        else
            # Use DS_ROOT_COMP for target resolution
            local root_comp
            root_comp=$(get_root_compartment_ocid) || die "Failed to get DS_ROOT_COMP"
            compartment_ocid="$root_comp"
        fi
        
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
        
        # Resolve compartment
        if is_ocid "$COMPARTMENT"; then
            compartment_ocid="$COMPARTMENT"
        else
            compartment_ocid=$(resolve_compartment_ocid "$COMPARTMENT") || \
                die "Failed to resolve compartment: $COMPARTMENT"
        fi
        
        # List targets in compartment
        local targets_data
        targets_data=$(list_targets_in_compartment "$compartment_ocid") || \
            die "Failed to list targets in compartment"
        
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
    
    # Emit output
    emit_output
    
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    
    # Setup error handling
    setup_error_handling
    
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
