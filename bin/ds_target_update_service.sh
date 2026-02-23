#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose....: Update Oracle Data Safe target service names
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
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${ALLOW_STALE_SELECTION:=false}"
: "${MAX_SNAPSHOT_AGE:=24h}"
: "${DB_DOMAIN:=oradba.ch}"
: "${APPLY_CHANGES:=false}"
: "${WAIT_FOR_STATE:=}"
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

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
  Update Oracle Data Safe target service names to "<base>_exa.<domain>"
  format when they do not already end with the specified domain.

Options:
  Common:
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
        --log-file FILE         Log to file

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file

  Selection:
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                   Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex (substring match)
    -L, --lifecycle STATE       Filter by lifecycle state (default: ${LIFECYCLE_STATE})
        --input-json FILE       Read targets from local JSON (array or {data:[...]})
        --save-json FILE        Save selected target JSON payload
        --allow-stale-selection Allow --apply with --input-json
                    (disabled by default for safety)
        --max-snapshot-age AGE  Max input-json age (default: ${MAX_SNAPSHOT_AGE})
                    Examples: 900, 30m, 24h, 2d, off

  Service Update:
        --domain DOMAIN         Domain for new service names (default: ${DB_DOMAIN})
        --wait-for-state STATE  Wait for target update to reach state (e.g. ACCEPTED)
        --apply                 Apply changes (default: dry-run only)
    -n, --dry-run               Dry-run mode (show what would be done)

Service Name Rules:
    - Target format: "<base>_exa.<domain>"
    - If service already ends with domain: no change
    - Extract base name from current service (remove domain if present)
    - Apply standard naming: "{base}_exa.{domain}"

Examples:
    # Dry-run for all ACTIVE targets
    ${SCRIPT_NAME}

    # Apply changes to specific targets
    ${SCRIPT_NAME} -T target1,target2 --apply

    # Update with custom domain
    ${SCRIPT_NAME} --domain custom.example --apply

    # Process specific compartment
    ${SCRIPT_NAME} -c my-compartment --apply

    # Update only targets matching regex
    ${SCRIPT_NAME} -c my-compartment -r "cdb10b" --apply

    # Dry-run from saved target selection JSON
    ${SCRIPT_NAME} --input-json ./target_selection.json

    # Apply from saved selection JSON (requires explicit safeguard override)
    ${SCRIPT_NAME} --input-json ./target_selection.json --apply --allow-stale-selection

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

    # Parse script-specific options
    local -a remaining=()
    set -- "${ARGS[@]-}"

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
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
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
            --allow-stale-selection)
                ALLOW_STALE_SELECTION=true
                shift
                ;;
            --max-snapshot-age)
                need_val "$1" "${2:-}"
                MAX_SNAPSHOT_AGE="$2"
                shift 2
                ;;
            --domain)
                need_val "$1" "${2:-}"
                DB_DOMAIN="$2"
                shift 2
                ;;
            --wait-for-state)
                need_val "$1" "${2:-}"
                WAIT_FOR_STATE="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
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
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error via die()
# Output..: Log messages for validation steps
# Notes...: Resolves compartments and validates domain
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        ds_validate_input_json_freshness "$INPUT_JSON" "$MAX_SNAPSHOT_AGE" || die "Input JSON snapshot freshness check failed"

        if [[ "$APPLY_CHANGES" == "true" && "$ALLOW_STALE_SELECTION" != "true" ]]; then
            die "Refusing --apply with --input-json without --allow-stale-selection"
        fi

        if [[ "$SELECT_ALL" == "true" || -n "$COMPARTMENT" || -n "$TARGETS" ]]; then
            log_warn "Ignoring --all/--compartment/--targets when --input-json is provided"
        fi

        if [[ "$APPLY_CHANGES" == "true" ]]; then
            require_oci_cli
        fi
    else
        require_oci_cli

        COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

        if [[ "$SELECT_ALL" == "true" ]]; then
            log_info "Using DS_ROOT_COMP scope via --all"
        fi

        # If no scope specified, use DS_ROOT_COMP as default when available
        if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
            if [[ -n "${DS_ROOT_COMP:-}" ]]; then
                COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
                log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
            else
                usage
            fi
        fi
    fi

    # Resolve compartment if specified (accept name or OCID)
    if [[ -n "$COMPARTMENT" ]]; then
        if is_ocid "$COMPARTMENT"; then
            # User provided OCID, resolve to name
            COMPARTMENT_OCID="$COMPARTMENT"
            COMPARTMENT_NAME=$(oci_get_compartment_name "$COMPARTMENT_OCID" 2> /dev/null) || COMPARTMENT_NAME="$COMPARTMENT_OCID"
            log_debug "Resolved compartment OCID to name: $COMPARTMENT_NAME"
        else
            # User provided name, resolve to OCID
            COMPARTMENT_NAME="$COMPARTMENT"
            COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || {
                die "Cannot resolve compartment name '$COMPARTMENT' to OCID.\nVerify compartment name or use OCID directly."
            }
            log_debug "Resolved compartment name to OCID: $COMPARTMENT_OCID"
        fi
        log_info "Using compartment: $COMPARTMENT_NAME"
    fi

    # Validate domain
    [[ -n "$DB_DOMAIN" ]] || die "Domain cannot be empty"

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: compute_new_service_name
# Purpose.: Transform current service to "<base>_exa.<domain>"
# Args....: $1 - Current service name
#           $2 - Domain
# Returns.: 0 on success
# Output..: New service name to stdout
# ------------------------------------------------------------------------------
compute_new_service_name() {
    local current="$1"
    local domain="$2"

    [[ -z "$current" ]] && {
        echo ""
        return 0
    }

    # If already ends with domain, no change needed
    if [[ "$current" == *".${domain}" ]]; then
        echo "$current"
        return 0
    fi

    # Extract base name (remove existing domain if present)
    local base="${current%%.*}"

    # Handle underscore-separated names (take second part if exists)
    local token2="${base#*_}"
    local name_base
    if [[ "$token2" != "$base" && -n "$token2" ]]; then
        name_base="$token2"
    else
        name_base="$base"
    fi

    # Convert to lowercase and apply standard format
    name_base="${name_base,,}"
    echo "${name_base}_exa.${domain}"
}

# ------------------------------------------------------------------------------
# Function: update_target_service
# Purpose.: Update service name for a single target
# Args....: $1 - Target OCID
#           $2 - Target name
#           $3 - Current service name
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
update_target_service() {
    local target_ocid="$1"
    local target_name="$2"
    local current_service="$3"

    log_debug "Processing target: $target_name ($target_ocid)"
    log_debug "Current service: $current_service"

    # Compute new service name
    local new_service
    new_service=$(compute_new_service_name "$current_service" "$DB_DOMAIN")

    log_info "Target: $target_name"
    log_info "  Current service: $current_service"
    log_info "  New service: $new_service"

    # Check if change is needed
    if [[ "$current_service" == "$new_service" ]]; then
        log_info "  [OK] No change needed (already correct format)"
        return 0
    fi

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating service name..."

        local -a cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --connection-option "{\"connectionType\": \"PRIVATE_ENDPOINT\", \"datasafePrivateEndpointId\": null}"
            --database-details "{\"serviceName\": \"$new_service\"}"
        )

        if [[ -n "$WAIT_FOR_STATE" ]]; then
            cmd+=(--wait-for-state "$WAIT_FOR_STATE")
        fi

        if oci_exec "${cmd[@]}" > /dev/null; then
            log_info "  [OK] Service updated successfully"
            return 0
        else
            log_error "  [ERROR] Failed to update service name"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function: list_targets_in_compartment
# Purpose.: List targets in compartment with current service names
# Args....: $1 - Compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON array of targets to stdout
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"

    ds_list_targets "$compartment" "$LIFECYCLE_STATE"
}

# ------------------------------------------------------------------------------
# Function: get_target_details
# Purpose.: Get target details including service name
# Args....: $1 - Target OCID
# Returns.: 0 on success, 1 on error
# Output..: JSON object with target details to stdout
# ------------------------------------------------------------------------------
get_target_details() {
    local target_ocid="$1"

    log_debug "Getting details for: $target_ocid"

    oci_exec_ro data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - processes targets and updates service names
# Args....: None
# Returns.: 0 on success, 1 if any errors occurred
# Output..: Progress messages and summary statistics
# ------------------------------------------------------------------------------
do_work() {
    # Show execution mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    local success_count=0 error_count=0
    local -a target_rows=()

    log_info "Discovering targets (lifecycle: $LIFECYCLE_STATE)"

    local json_data
    json_data=$(ds_collect_targets_source "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER" "$INPUT_JSON" "$SAVE_JSON") || die "Failed to collect targets"

    mapfile -t target_rows < <(echo "$json_data" | jq -r '.data[] | [(.id // ""), (."display-name" // ""), (.databaseDetails.serviceName // ."database-details"."service-name" // "")] | @tsv')

    local total_count=${#target_rows[@]}
    log_info "Found $total_count targets to process"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found"
        return 0
    fi

    local current=0
    local target_ocid=""
    local target_row=""
    local target_data=""
    local target_name=""
    local current_service=""

    for target_row in "${target_rows[@]}"; do
        IFS=$'\t' read -r target_ocid target_name current_service <<< "$target_row"
        [[ -z "$target_ocid" ]] && continue
        current=$((current + 1))

        if [[ -z "$current_service" && -z "$INPUT_JSON" ]]; then
            if ! target_data=$(get_target_details "$target_ocid"); then
                log_error "[$current/$total_count] Failed to get details for target: $target_ocid"
                error_count=$((error_count + 1))
                continue
            fi
            target_name=$(echo "$target_data" | jq -r '."display-name"')
            current_service=$(echo "$target_data" | jq -r '.databaseDetails.serviceName // ""')
        fi

        log_info "[$current/$total_count] Processing: $target_name"
        if update_target_service "$target_ocid" "$target_name" "$current_service"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done

    # Summary
    log_info "Service update completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
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
    if do_work; then
        log_info "Service update completed successfully"
    else
        die "Service update failed with errors"
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
fi

parse_args "$@"
main

# --- End of ds_target_update_service.sh ---------------------------------------
