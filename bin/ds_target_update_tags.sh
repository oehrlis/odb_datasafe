#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_tags.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Update Oracle Data Safe target database tags based on compartment
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
: "${TARGET_FILTER:=}"
: "${APPLY_CHANGES:=false}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${WAIT_FOR_STATE:=}"
: "${TAG_NAMESPACE:=DBSec}"
: "${ENVIRONMENT_TAG:=Environment}"
: "${CONTAINER_STAGE_TAG:=ContainerStage}"
: "${CONTAINER_TYPE_TAG:=ContainerType}"
: "${CLASSIFICATION_TAG:=Classification}"

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
  Update Oracle Data Safe target database tags based on compartment environment.
  Derives environment from compartment name patterns and updates target tags.

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
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP)
                            Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -T, --targets LIST      Comma-separated target names or OCIDs
        -r, --filter REGEX      Filter target names by regex (substring match)

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)
    -L, --lifecycle STATE   Lifecycle state filter (default: ${LIFECYCLE_STATE})
    --wait-for-state STATE  Wait for target update to reach state (e.g. ACCEPTED)

  Tag Configuration:
    --namespace NS          Tag namespace (default: ${TAG_NAMESPACE})
    --env-tag TAG           Environment tag key (default: ${ENVIRONMENT_TAG})
    --stage-tag TAG         Container stage tag key (default: ${CONTAINER_STAGE_TAG})
    --type-tag TAG          Container type tag key (default: ${CONTAINER_TYPE_TAG})
    --class-tag TAG         Classification tag key (default: ${CLASSIFICATION_TAG})

Tag Rules:
  - Environment derived from compartment pattern: cmp-{org}-{env}-projects
  - Supported environments: test, qs, prod
  - Default values: Environment=undef, ContainerStage=undef, etc.

Examples:
  # Dry-run for all targets in DS_ROOT_COMP
  ${SCRIPT_NAME}

  # Apply changes to specific compartment
  ${SCRIPT_NAME} -c cmp-lzp-dbso-prod-projects --apply

  # Update specific targets
  ${SCRIPT_NAME} -T target1,target2 --apply

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
            -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --namespace)
                need_val "$1" "${2:-}"
                TAG_NAMESPACE="$2"
                shift 2
                ;;
            --env-tag)
                need_val "$1" "${2:-}"
                ENVIRONMENT_TAG="$2"
                shift 2
                ;;
            --stage-tag)
                need_val "$1" "${2:-}"
                CONTAINER_STAGE_TAG="$2"
                shift 2
                ;;
            --type-tag)
                need_val "$1" "${2:-}"
                CONTAINER_TYPE_TAG="$2"
                shift 2
                ;;
            --class-tag)
                need_val "$1" "${2:-}"
                CLASSIFICATION_TAG="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            --wait-for-state)
                need_val "$1" "${2:-}"
                WAIT_FOR_STATE="$2"
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
# Notes...: Resolves compartments to both name and OCID
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # Require either targets or compartment (or DS_ROOT_COMP)
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        # Try to use DS_ROOT_COMP as fallback
        COMPARTMENT=$(resolve_compartment_for_operation "") || usage
        log_info "No scope specified, using resolved compartment: $COMPARTMENT"
    fi

    if [[ -n "$COMPARTMENT" ]]; then
        COMPARTMENT_OCID=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment"
        COMPARTMENT_NAME=$(oci_get_compartment_name "$COMPARTMENT_OCID" 2> /dev/null) || COMPARTMENT_NAME="$COMPARTMENT_OCID"
        log_info "Using compartment: $COMPARTMENT_NAME ($COMPARTMENT_OCID)"
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_target_compartment_name
# Purpose.: Resolve effective compartment name for environment derivation
# Args....: $1 - target compartment OCID
# Returns.: 0 on success
# Output..: Compartment name to stdout
# ------------------------------------------------------------------------------
resolve_target_compartment_name() {
    local target_comp_ocid="$1"

    if [[ -n "$target_comp_ocid" && "$target_comp_ocid" != "null" ]]; then
        get_compartment_name "$target_comp_ocid"
    elif [[ -n "$COMPARTMENT_NAME" ]]; then
        echo "$COMPARTMENT_NAME"
    elif [[ -n "$COMPARTMENT_OCID" ]]; then
        get_compartment_name "$COMPARTMENT_OCID"
    else
        echo "unknown"
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_target_compartment_ocid
# Purpose.: Resolve effective compartment OCID for target
# Args....: $1 - target compartment OCID from payload
# Returns.: 0 on success
# Output..: Compartment OCID to stdout
# ------------------------------------------------------------------------------
resolve_target_compartment_ocid() {
    local target_comp_ocid="$1"

    if [[ -n "$target_comp_ocid" && "$target_comp_ocid" != "null" ]]; then
        echo "$target_comp_ocid"
    elif [[ -n "$COMPARTMENT_OCID" ]]; then
        echo "$COMPARTMENT_OCID"
    else
        echo ""
    fi
}

# ------------------------------------------------------------------------------
# Function: normalize_target_payload
# Purpose.: Normalize target payload into id/name/compartment TSV tuple
# Args....: None (reads JSON object from stdin)
# Returns.: 0 on success
# Output..: TSV line: id, display-name, compartment-id
# ------------------------------------------------------------------------------
normalize_target_payload() {
    jq -r '[.id, ."display-name", (."compartment-id" // "")] | @tsv'
}

# ------------------------------------------------------------------------------
# Function: collect_targets_for_tagging
# Purpose.: Collect target payload for tag updates
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: JSON object with .data array
# ------------------------------------------------------------------------------
collect_targets_for_tagging() {
    ds_collect_targets "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER"
}

# ------------------------------------------------------------------------------
# Function: process_collected_targets
# Purpose.: Process normalized target payload for tag updates
# Args....: $1 - JSON payload with .data array
# Returns.: 0 on success, 1 if any update failed
# Output..: Log messages and summary
# ------------------------------------------------------------------------------
process_collected_targets() {
    local json_data="$1"
    local success_count=0
    local error_count=0
    local matched_count=0
    local total_count=0
    local current=0

    total_count=$(echo "$json_data" | jq '.data | length')
    log_info "Found $total_count targets to process"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found"
        return 0
    fi

    while read -r target_ocid target_name target_comp; do
        current=$((current + 1))
        log_info "[$current/$total_count] Processing: $target_name"

        local effective_comp
        effective_comp=$(resolve_target_compartment_ocid "$target_comp")

        if update_target_tags "$target_ocid" "$target_name" "$effective_comp"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi

        matched_count=$((matched_count + 1))
    done < <(echo "$json_data" | jq -c '.data[]' | normalize_target_payload)

    if [[ -n "$TARGET_FILTER" && $matched_count -eq 0 ]]; then
        die "No targets matched filter regex: $TARGET_FILTER" 1
    fi

    log_info "Tag update completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# ------------------------------------------------------------------------------
# Function: get_env_from_compartment_name
# Purpose.: Derive environment from compartment name pattern
# Args....: $1 - Compartment name
# Returns.: 0 on success
# Output..: Environment string (test|qs|prod|undef)
# ------------------------------------------------------------------------------
get_env_from_compartment_name() {
    local comp_name="$1"
    local env="undef"

    # Pattern: cmp-{org}-{env}-projects
    if [[ "$comp_name" =~ ^cmp-[^-]+-([^-]+)-projects$ ]]; then
        env="${BASH_REMATCH[1]}"
    fi

    case "$env" in
        test | qs | prod) echo "$env" ;;
        *) echo "undef" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: get_compartment_name
# Purpose.: Get compartment name from OCID
# Args....: $1 - Compartment OCID
# Returns.: 0 on success
# Output..: Compartment name to stdout
# ------------------------------------------------------------------------------
get_compartment_name() {
    local comp_id="$1"

    oci_exec iam compartment get \
        --compartment-id "$comp_id" \
        --query 'data.name' \
        --raw-output 2> /dev/null || echo "unknown"
}

# ------------------------------------------------------------------------------
# Function: build_tag_update_json
# Purpose.: Build JSON for tag updates
# Args....: $1 - Environment
#           $2 - Container stage
#           $3 - Container type
#           $4 - Classification
# Returns.: 0 on success
# Output..: JSON string to stdout
# ------------------------------------------------------------------------------
build_tag_update_json() {
    local env="$1"
    local stage="$2"
    local type="$3"
    local classification="$4"

    cat << EOF
{
  "defined-tags": {
    "${TAG_NAMESPACE}": {
      "${ENVIRONMENT_TAG}": "${env}",
      "${CONTAINER_STAGE_TAG}": "${stage}",
      "${CONTAINER_TYPE_TAG}": "${type}",
      "${CLASSIFICATION_TAG}": "${classification}"
    }
  }
}
EOF
}

# ------------------------------------------------------------------------------
# Function: update_target_tags
# Purpose.: Update tags for a single target
# Args....: $1 - Target OCID
#           $2 - Target name
#           $3 - Target compartment OCID
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
update_target_tags() {
    local target_ocid="$1"
    local target_name="$2"
    local target_comp="$3"

    log_debug "Processing target: $target_name ($target_ocid)"

    # Get compartment name and derive environment
    local comp_name
    comp_name=$(resolve_target_compartment_name "$target_comp")

    local env
    env=$(get_env_from_compartment_name "$comp_name")

    log_debug "Target compartment: $comp_name -> Environment: $env"

    # Default tag values - customize as needed
    local container_stage="undef"
    local container_type="undef"
    local classification="undef"

    # Build update JSON
    local update_json
    update_json=$(build_tag_update_json "$env" "$container_stage" "$container_type" "$classification")

    log_info "Target: $target_name"
    log_info "  Environment: $env"
    log_info "  Container Stage: $container_stage"
    log_info "  Container Type: $container_type"
    log_info "  Classification: $classification"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Applying tags..."

        local -a cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --defined-tags "$update_json"
        )

        if [[ -n "$WAIT_FOR_STATE" ]]; then
            cmd+=(--wait-for-state "$WAIT_FOR_STATE")
        fi

        if oci_exec "${cmd[@]}" > /dev/null; then
            log_info "  [OK] Tags updated successfully"
            return 0
        else
            log_error "  [ERROR] Failed to update tags"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - processes targets and updates tags
# Args....: None
# Returns.: 0 on success, 1 if any errors occurred
# Output..: Progress messages and summary statistics
# ------------------------------------------------------------------------------
do_work() {
    # Set DRY_RUN flag and show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    local json_data

    if [[ -n "$TARGETS" ]]; then
        log_info "Processing specific targets..."
    else
        log_info "Processing targets from compartment scope..."
    fi

    json_data=$(collect_targets_for_tagging) || die "Failed to collect targets"
    process_collected_targets "$json_data"
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
        log_info "Tag update completed successfully"
    else
        die "Tag update failed with errors"
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
fi

parse_args "$@"
main

# --- End of ds_target_update_tags.sh ------------------------------------------
