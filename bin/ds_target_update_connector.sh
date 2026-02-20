#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_connector.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Manage Oracle Data Safe on-premises connector assignments
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
: "${CONNECTOR_COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${SOURCE_CONNECTOR:=}"
: "${TARGET_CONNECTOR:=}"
: "${EXCLUDE_CONNECTORS:=}"
: "${OPERATION_MODE:=}"
: "${APPLY_CHANGES:=false}"
: "${WAIT_FOR_COMPLETION:=false}" # Default to no-wait for speed
: "${EXCLUDE_AUTO:=false}"

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
# Args....: $1 - Exit code (optional, default: 0)
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
usage() {
    local exit_code=${1:-0}
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] MODE

Description:
  Manage Oracle Data Safe on-premises connector assignments for targets.
  Supports individual target updates or bulk connector management operations.

Operation Modes:
  set                       Set specific connector for target(s)
  migrate                   Change targets from source connector to target connector
  distribute                Distribute targets across all available connectors

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
    -c, --compartment ID        Target compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                   Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex (substring match)
    -L, --lifecycle STATE       Filter by lifecycle state (default: ${LIFECYCLE_STATE})
                                Supports: ACTIVE, NEEDS_ATTENTION, CREATING, UPDATING, DELETING
                                Use comma-separated for multiple: ACTIVE,NEEDS_ATTENTION
    --include-needs-attention   Include targets needing attention (shortcut for -L ACTIVE,NEEDS_ATTENTION)
    --exclude-auto              Exclude automatically created targets

  Connector:
    --source-connector ID       Source connector OCID or name (for migrate mode)
    --target-connector ID       Target connector OCID or name (for set/migrate modes)
    --connector-compartment ID  Compartment to query connectors from (default: same as -c)
    --exclude-connectors LIST   Comma-separated connector names to exclude from distribution

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)
    --wait                  Wait for each update to complete (slower but shows status)
    --no-wait               Don't wait for completion (faster, default)

Mode Details:

1. Set Mode (set):
   Assigns a specific connector to one or more targets.
   Required: --target-connector
   Optional: -T/--targets (if not specified, processes entire compartment)

2. Migrate Mode (migrate):
   Changes all targets from source connector to target connector.
   Required: --source-connector, --target-connector
   Optional: -c/--compartment (scope the migration to specific compartment)

3. Distribute Mode (distribute):
   Distributes targets evenly across all available on-premises connectors.
   No connector options required (discovers available connectors automatically)
   Optional: -c/--compartment (target compartment, defaults to DS_ROOT_COMP)
   Optional: --connector-compartment (where to find connectors, defaults to -c)
   Optional: --exclude-connectors (ignore specific connectors)

Examples:

  # Set specific connector for target (dry-run)
  ${SCRIPT_NAME} set -T my-target --target-connector conn-prod-01

  # Apply connector to specific targets
  ${SCRIPT_NAME} set -T target1,target2 --target-connector conn-prod-02 --apply

  # Include targets needing attention
  ${SCRIPT_NAME} set --target-connector conn-prod-01 --include-needs-attention --apply

  # Work with specific lifecycle states
  ${SCRIPT_NAME} set --target-connector conn-prod-01 -L NEEDS_ATTENTION --apply

  # Migrate all targets from old to new connector in compartment
  ${SCRIPT_NAME} migrate -c my-compartment \
    --source-connector conn-old --target-connector conn-new --apply

  # Distribute targets, exclude specific connectors (dry-run)
  ${SCRIPT_NAME} distribute -c cmp-targets \
    --exclude-connectors "conn-old,conn-test"

  # Distribute using different compartments for targets and connectors
  ${SCRIPT_NAME} distribute -c cmp-targets \
    --connector-compartment cmp-connectors --apply

  # Apply distribution for entire root compartment
  ${SCRIPT_NAME} distribute --apply

EOF
    exit "$exit_code"
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
            --source-connector)
                need_val "$1" "${2:-}"
                SOURCE_CONNECTOR="$2"
                shift 2
                ;;
            --target-connector)
                need_val "$1" "${2:-}"
                TARGET_CONNECTOR="$2"
                shift 2
                ;;
            --connector-compartment)
                need_val "$1" "${2:-}"
                CONNECTOR_COMPARTMENT="$2"
                shift 2
                ;;
            --exclude-connectors)
                need_val "$1" "${2:-}"
                EXCLUDE_CONNECTORS="$2"
                shift 2
                ;;
            --include-needs-attention)
                LIFECYCLE_STATE="ACTIVE,NEEDS_ATTENTION"
                shift
                ;;
            --exclude-auto)
                EXCLUDE_AUTO=true
                shift
                ;;
            --wait)
                WAIT_FOR_COMPLETION=true
                shift
                ;;
            --no-wait)
                WAIT_FOR_COMPLETION=false
                shift
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

    # Handle mode and positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        OPERATION_MODE="${remaining[0]}"

        # Handle remaining positional args as targets if not already set
        if [[ ${#remaining[@]} -gt 1 && -z "$TARGETS" ]]; then
            local -a target_args=("${remaining[@]:1}")
            TARGETS="${target_args[*]}"
            TARGETS="${TARGETS// /,}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error via die()
# Output..: Log messages for validation steps
# Notes...: Resolves compartments and validates operation mode requirements
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    # Show help if no operation mode specified
    if [[ -z "$OPERATION_MODE" ]]; then
        usage 1
    fi

    # Validate operation mode
    case "$OPERATION_MODE" in
        set | migrate | distribute) ;;
        *) die "Invalid operation mode: $OPERATION_MODE. Use: set, migrate, or distribute" ;;
    esac

    # Validate mode-specific requirements
    case "$OPERATION_MODE" in
        set)
            [[ -n "$TARGET_CONNECTOR" ]] || die "Set mode requires --target-connector"
            ;;
        migrate)
            [[ -n "$SOURCE_CONNECTOR" ]] || die "Migrate mode requires --source-connector"
            [[ -n "$TARGET_CONNECTOR" ]] || die "Migrate mode requires --target-connector"
            [[ "$SOURCE_CONNECTOR" != "$TARGET_CONNECTOR" ]] || die "Source and target connectors must be different"
            ;;
        distribute)
            [[ -z "$SOURCE_CONNECTOR" && -z "$TARGET_CONNECTOR" ]] || log_warn "Connector options ignored in distribute mode"
            ;;
    esac

    # If no scope specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
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

    # For set mode, require either targets or compartment
    if [[ "$OPERATION_MODE" == "set" && -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        die "Set mode requires either --targets or --compartment to be specified"
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi

    log_info "Operation mode: $OPERATION_MODE"
}

# ------------------------------------------------------------------------------
# Function: resolve_connector_ocid
# Purpose.: Resolve connector name to OCID
# Args....: $1 - Connector name or OCID
# Returns.: 0 on success, 1 on error
# Output..: Connector OCID to stdout
# ------------------------------------------------------------------------------
resolve_connector_ocid() {
    local connector="$1"

    if is_ocid "$connector"; then
        echo "$connector"
        return 0
    fi

    # In dry-run mode, allow connector name to pass through
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_debug "Dry-run mode: Using connector name as-is: $connector"
        echo "$connector"
        return 0
    fi

    log_debug "Resolving connector name: $connector"

    # Use connector compartment (with fallback chain)
    local comp_ocid
    if [[ -n "${CONNECTOR_COMPARTMENT:-}" ]]; then
        # Explicit connector compartment specified
        if is_ocid "$CONNECTOR_COMPARTMENT"; then
            comp_ocid="$CONNECTOR_COMPARTMENT"
        else
            comp_ocid=$(oci_resolve_compartment_ocid "$CONNECTOR_COMPARTMENT") || return 1
        fi
    else
        # Use helper which falls back DS_CONNECTOR_COMP -> DS_ROOT_COMP
        comp_ocid=$(get_connector_compartment_ocid) || return 1
    fi

    # Search for connector by display name
    local connector_ocid
    connector_ocid=$(oci_exec data-safe on-prem-connector list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --query "data[?\"display-name\"=='$connector'].id | [0]" \
        --raw-output 2> /dev/null)

    if [[ -z "$connector_ocid" || "$connector_ocid" == "null" ]]; then
        return 1
    fi

    echo "$connector_ocid"
}

# ------------------------------------------------------------------------------
# Function: get_connector_name
# Purpose.: Get connector display name by OCID
# Args....: $1 - Connector OCID
# Returns.: 0 on success, 1 on error
# Output..: Connector display name to stdout
# ------------------------------------------------------------------------------
get_connector_name() {
    local connector_ocid="$1"

    oci_exec data-safe on-prem-connector get \
        --on-prem-connector-id "$connector_ocid" \
        --query 'data."display-name"' \
        --raw-output 2> /dev/null || echo "unknown"
}

# ------------------------------------------------------------------------------
# Function: list_available_connectors
# Purpose.: List all available on-premises connectors
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: JSON array of connectors to stdout
# ------------------------------------------------------------------------------
list_available_connectors() {
    log_debug "Listing available on-premises connectors..."

    # Determine which compartment to query for connectors
    local comp_ocid
    if [[ -n "${CONNECTOR_COMPARTMENT:-}" ]]; then
        # Use explicit connector compartment if specified
        if is_ocid "$CONNECTOR_COMPARTMENT"; then
            comp_ocid="$CONNECTOR_COMPARTMENT"
        else
            comp_ocid=$(oci_resolve_compartment_ocid "$CONNECTOR_COMPARTMENT") || return 1
        fi
        log_debug "Using explicit connector compartment: $CONNECTOR_COMPARTMENT"
    else
        # Use helper function which falls back DS_CONNECTOR_COMP -> DS_ROOT_COMP
        comp_ocid=$(get_connector_compartment_ocid) || return 1
        log_debug "Using default connector compartment"
    fi

    # Fetch connectors
    local connectors_json
    connectors_json=$(oci_exec_ro data-safe on-prem-connector list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --lifecycle-state ACTIVE \
        --all)

    # Apply exclusion filter if specified
    if [[ -n "${EXCLUDE_CONNECTORS:-}" ]]; then
        log_debug "Applying connector exclusion filter: $EXCLUDE_CONNECTORS"
        local -a exclude_list
        IFS=',' read -ra exclude_list <<< "$EXCLUDE_CONNECTORS"

        # Build jq filter to exclude connectors
        local jq_filter='.data'
        for excluded in "${exclude_list[@]}"; do
            # Trim spaces
            excluded="${excluded#"${excluded%%[![:space:]]*}"}"
            excluded="${excluded%"${excluded##*[![:space:]]}"}"
            [[ -z "$excluded" ]] && continue

            jq_filter+=" | map(select(.\"display-name\" != \"$excluded\"))"
        done

        echo "$connectors_json" | jq "{data: ($jq_filter)}"
    else
        echo "$connectors_json"
    fi
}

# ------------------------------------------------------------------------------
# Function: update_target_connector
# Purpose.: Update connector for a single target
# Args....: $1 - Target OCID
#           $2 - Target name
#           $3 - New connector OCID
#           $4 - New connector name
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
update_target_connector() {
    local target_ocid="$1"
    local target_name="$2"
    local new_connector_ocid="$3"
    local new_connector_name="$4"

    log_debug "Processing target: $target_name ($target_ocid)"

    # Get current connector
    local current_connector_ocid current_connector_name
    current_connector_ocid=$(oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data."connection-option"."on-premise-connector-id"' \
        --raw-output 2> /dev/null || echo "")

    if [[ -n "$current_connector_ocid" && "$current_connector_ocid" != "null" ]]; then
        current_connector_name=$(get_connector_name "$current_connector_ocid")
    else
        current_connector_name="none"
    fi

    log_info "  Current connector: $current_connector_name"
    log_info "  New connector: $new_connector_name"

    # Skip if already using target connector
    if [[ "$current_connector_ocid" == "$new_connector_ocid" ]]; then
        log_info "  ➤ Already using target connector - skipping"
        return 0
    fi

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating connector..."

        # Get current connection details to preserve connectionType and other fields
        local current_conn_json
        current_conn_json=$(oci_exec data-safe target-database get \
            --target-database-id "$target_ocid" \
            --query 'data."connection-option"' 2> /dev/null) || current_conn_json='{}'

        # Build new connection option - preserve existing fields, update connector
        local conn_json
        if [[ -n "$current_conn_json" && "$current_conn_json" != "null" && "$current_conn_json" != "{}" ]]; then
            # Update existing connection option with new connector
            conn_json=$(echo "$current_conn_json" | jq --arg conn "$new_connector_ocid" \
                '. + {"onPremConnectorId": $conn}')
        else
            # Create minimal connection option with ONPREM_CONNECTOR type
            conn_json="{\"connectionType\": \"ONPREM_CONNECTOR\", \"onPremConnectorId\": \"$new_connector_ocid\"}"
        fi

        # Build OCI command with optional wait
        local -a oci_cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --connection-option "$conn_json"
            --force
        )

        # Add wait-for-state if requested
        if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
            oci_cmd+=(--wait-for-state SUCCEEDED --wait-for-state FAILED)
        fi

        # Execute update
        if oci_exec "${oci_cmd[@]}" > /dev/null; then
            log_info "  [OK] Connector updated successfully"
            return 0
        else
            log_error "  [ERROR] Failed to update connector"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function: list_targets_in_compartment
# Purpose.: List targets in compartment with optional filtering
# Args....: $1 - Compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON array of targets to stdout
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"
    local json_data

    json_data=$(ds_collect_targets "$compartment" "" "$LIFECYCLE_STATE" "$TARGET_FILTER") || return 1

    # Apply additional filtering if needed
    if [[ "$EXCLUDE_AUTO" == "true" ]]; then
        json_data=$(echo "$json_data" | jq '.data = (.data | map(select(."display-name" | test("_auto$") | not)))')
    fi

    echo "$json_data"
}

# ------------------------------------------------------------------------------
# Function: do_set_mode
# Purpose.: Execute set operation mode
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
do_set_mode() {
    log_info "Executing SET mode..."

    local target_connector_ocid target_connector_name
    target_connector_ocid=$(resolve_connector_ocid "$TARGET_CONNECTOR") || die "Failed to resolve target connector: $TARGET_CONNECTOR"
    target_connector_name=$(get_connector_name "$target_connector_ocid")

    log_info "Target connector: $target_connector_name ($target_connector_ocid)"

    local success_count=0 error_count=0 matched_count=0

    local json_data
    if [[ -n "$TARGETS" ]]; then
        log_info "Processing specific targets..."
        json_data=$(ds_collect_targets "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER") || die "Failed to collect targets"
    else
        log_info "Processing targets from compartment..."
        json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"
    fi

    local total_count
    total_count=$(echo "$json_data" | jq '.data | length')
    log_info "Found $total_count targets to process"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found"
        return 0
    fi

    local current=0
    while read -r target_ocid target_name; do
        current=$((current + 1))
        log_info "[$current/$total_count] Processing: $target_name"
        matched_count=$((matched_count + 1))

        if update_target_connector "$target_ocid" "$target_name" "$target_connector_ocid" "$target_connector_name"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')

    if [[ -n "$TARGET_FILTER" && $matched_count -eq 0 ]]; then
        die "No targets matched filter regex: $TARGET_FILTER" 1
    fi

    # Summary
    log_info "SET operation completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# ------------------------------------------------------------------------------
# Function: do_migrate_mode
# Purpose.: Execute migrate operation mode
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
do_migrate_mode() {
    log_info "Executing MIGRATE mode..."

    local source_connector_ocid target_connector_ocid source_connector_name target_connector_name
    source_connector_ocid=$(resolve_connector_ocid "$SOURCE_CONNECTOR") || die "Failed to resolve source connector: $SOURCE_CONNECTOR"
    target_connector_ocid=$(resolve_connector_ocid "$TARGET_CONNECTOR") || die "Failed to resolve target connector: $TARGET_CONNECTOR"

    source_connector_name=$(get_connector_name "$source_connector_ocid")
    target_connector_name=$(get_connector_name "$target_connector_ocid")

    log_info "Source connector: $source_connector_name ($source_connector_ocid)"
    log_info "Target connector: $target_connector_name ($target_connector_ocid)"

    # Get all targets using source connector
    log_info "Finding targets using source connector..."
    local json_data
    json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"

    # Filter targets by source connector
    local filtered_data
    filtered_data=$(echo "$json_data" | jq --arg source_id "$source_connector_ocid" '
        .data = (.data | map(select(.["connection-option"]["on-premise-connector-id"] == $source_id)))
    ')

    local total_count
    total_count=$(echo "$filtered_data" | jq '.data | length')
    log_info "Found $total_count targets using source connector"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found using source connector"
        return 0
    fi

    local success_count=0 error_count=0 current=0

    while read -r target_ocid target_name; do
        current=$((current + 1))
        log_info "[$current/$total_count] Processing: $target_name"

        if update_target_connector "$target_ocid" "$target_name" "$target_connector_ocid" "$target_connector_name"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < <(echo "$filtered_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')

    # Summary
    log_info "MIGRATE operation completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# ------------------------------------------------------------------------------
# Function: do_distribute_mode
# Purpose.: Execute distribute operation mode
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
do_distribute_mode() {
    log_info "Executing DISTRIBUTE mode..."

    # Get all available connectors
    log_info "Finding available on-premises connectors..."
    local connectors_data
    connectors_data=$(list_available_connectors) || die "Failed to list connectors"

    local connector_count
    connector_count=$(echo "$connectors_data" | jq '.data | length')

    if [[ $connector_count -eq 0 ]]; then
        die "No active on-premises connectors found"
    fi

    log_info "Found $connector_count available connectors:"

    # Display available connectors
    local -a connector_ocids connector_names
    while read -r ocid name; do
        connector_ocids+=("$ocid")
        connector_names+=("$name")
        log_info "  - $name ($ocid)"
    done < <(echo "$connectors_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')

    # Get all targets that need distribution
    log_info "Finding targets to distribute..."
    local targets_data
    targets_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"

    local total_targets
    total_targets=$(echo "$targets_data" | jq '.data | length')
    log_info "Found $total_targets targets to distribute"

    if [[ $total_targets -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found for distribution"
        return 0
    fi

    local success_count=0 error_count=0 current=0

    # Distribute targets round-robin across connectors
    while read -r target_ocid target_name; do
        current=$((current + 1))
        local connector_index=$(((current - 1) % connector_count))
        local assigned_connector_ocid="${connector_ocids[$connector_index]}"
        local assigned_connector_name="${connector_names[$connector_index]}"

        log_info "[$current/$total_targets] Processing: $target_name"
        log_info "  Assigning to: $assigned_connector_name"

        if update_target_connector "$target_ocid" "$target_name" "$assigned_connector_ocid" "$assigned_connector_name"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < <(echo "$targets_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')

    # Summary
    log_info "DISTRIBUTE operation completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    # Show distribution summary
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Distribution summary:"
        for ((i = 0; i < connector_count; i++)); do
            local count=$((success_count / connector_count))
            if [[ $i -lt $((success_count % connector_count)) ]]; then
                count=$((count + 1))
            fi
            log_info "  ${connector_names[$i]}: ~$count targets"
        done
    fi

    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work orchestration function - dispatches to mode-specific handlers
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Progress messages and results from mode-specific functions
# ------------------------------------------------------------------------------
do_work() {
    # Set DRY_RUN flag and show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        DRY_RUN=false
        log_info "Apply mode: Changes will be applied"
    else
        DRY_RUN=true
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    case "$OPERATION_MODE" in
        set)
            do_set_mode
            ;;
        migrate)
            do_migrate_mode
            ;;
        distribute)
            do_distribute_mode
            ;;
        *)
            die "Unknown operation mode: $OPERATION_MODE"
            ;;
    esac
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
        log_info "Connector management completed successfully"
    else
        die "Connector management failed with errors"
    fi
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_update_connector.sh ----------------------------------
