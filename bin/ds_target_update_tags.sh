#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_tags.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v0.2.0
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
readonly SCRIPT_VERSION="0.2.0"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${APPLY_CHANGES:=false}"
: "${TAG_NAMESPACE:=DBSec}"
: "${ENVIRONMENT_TAG:=Environment}"
: "${CONTAINER_STAGE_TAG:=ContainerStage}"
: "${CONTAINER_TYPE_TAG:=ContainerType}"
: "${CLASSIFICATION_TAG:=Classification}"

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

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)

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

validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq

    # If no scope specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    # Show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi
}

# ------------------------------------------------------------------------------
# Function....: get_env_from_compartment_name
# Purpose.....: Derive environment from compartment name pattern
# Parameters..: $1 - compartment name
# Returns.....: Environment string (test|qs|prod|undef)
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
# Function....: get_compartment_name
# Purpose.....: Get compartment name from OCID
# Parameters..: $1 - compartment OCID
# Returns.....: Compartment name
# ------------------------------------------------------------------------------
get_compartment_name() {
    local comp_id="$1"

    oci_exec iam compartment get \
        --compartment-id "$comp_id" \
        --query 'data.name' \
        --raw-output 2> /dev/null || echo "unknown"
}

# ------------------------------------------------------------------------------
# Function....: build_tag_update_json
# Purpose.....: Build JSON for tag updates
# Parameters..: $1 - environment
#               $2 - container stage
#               $3 - container type
#               $4 - classification
# Returns.....: JSON string
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
# Function....: update_target_tags
# Purpose.....: Update tags for a single target
# Parameters..: $1 - target OCID
#               $2 - target name
#               $3 - target compartment OCID
# ------------------------------------------------------------------------------
update_target_tags() {
    local target_ocid="$1"
    local target_name="$2"
    local target_comp="$3"

    log_debug "Processing target: $target_name ($target_ocid)"

    # Get compartment name and derive environment
    local comp_name
    comp_name=$(get_compartment_name "$target_comp")

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

        if oci_exec data-safe target-database update \
            --target-database-id "$target_ocid" \
            --defined-tags "$update_json" > /dev/null; then
            log_info "  ✅ Tags updated successfully"
            return 0
        else
            log_error "  ❌ Failed to update tags"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
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

    log_debug "Listing targets in compartment: $comp_ocid"

    oci_exec data-safe target-database list \
        --compartment-id "$comp_ocid" \
        --compartment-id-in-subtree true \
        --all
}

# ------------------------------------------------------------------------------
# Function....: do_work
# Purpose.....: Main work function
# ------------------------------------------------------------------------------
do_work() {
    local json_data success_count=0 error_count=0

    # Collect target data
    if [[ -n "$TARGETS" ]]; then
        # Process specific targets
        log_info "Processing specific targets..."

        local -a target_list
        IFS=',' read -ra target_list <<< "$TARGETS"

        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces

            if is_ocid "$target"; then
                # Get target details
                local target_data
                if target_data=$(oci_exec data-safe target-database get \
                    --target-database-id "$target" \
                    --query 'data' 2> /dev/null); then

                    local target_name target_comp
                    target_name=$(echo "$target_data" | jq -r '."display-name"')
                    target_comp=$(echo "$target_data" | jq -r '."compartment-id"')

                    if update_target_tags "$target" "$target_name" "$target_comp"; then
                        success_count=$((success_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                else
                    log_error "Failed to get details for target: $target"
                    error_count=$((error_count + 1))
                fi
            else
                log_error "Target name resolution not implemented yet: $target"
                error_count=$((error_count + 1))
            fi
        done
    else
        # Process targets from compartment
        log_info "Processing targets from compartment..."
        json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"

        local total_count
        total_count=$(echo "$json_data" | jq '.data | length')
        log_info "Found $total_count targets to process"

        if [[ $total_count -eq 0 ]]; then
            log_warn "No targets found"
            return 0
        fi

        local current=0
        while read -r target_ocid target_name target_comp; do
            current=$((current + 1))
            log_info "[$current/$total_count] Processing: $target_name"

            if update_target_tags "$target_ocid" "$target_name" "$target_comp"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name", ."compartment-id"] | @tsv')
    fi

    # Summary
    log_info "Tag update completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
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
    if do_work; then
        log_info "Tag update completed successfully"
    else
        die "Tag update failed with errors"
    fi
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_update_tags.sh ------------------------------------------
