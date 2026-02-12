#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_delete.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Delete Oracle Data Safe target databases and their dependencies
#              for given target names/OCIDs or all targets in a compartment.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_delete.conf
#              > DEFAULT_CONF > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.09 oehrli - migrate to v0.2.0 framework pattern
# ------------------------------------------------------------------------------

# --- Code defaults (lowest precedence; overridden by .env/CONF/CLI) ----------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"

: "${COMPARTMENT:=}" # name or OCID
: "${TARGETS:=}"     # CSV names/OCIDs (overrides compartment mode)
: "${STATE_FILTERS:=NEEDS_ATTENTION}"# CSV lifecycle states when scanning compartment
: "${FORCE:=false}"              # skip confirmation prompts
: "${DELETE_DEPENDENCIES:=true}" # delete audit trails, assessments, policies
: "${CONTINUE_ON_ERROR:=true}"   # continue processing other targets if one fails

# Runtime
COMP_OCID=""
RESOLVED_TARGETS=()
deleted_count=0
failed_count=0

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
# shellcheck disable=SC2034  # SCRIPT_VERSION used by framework
SCRIPT_VERSION="0.3.0"

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

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display command-line usage instructions and exit
# Args....: $1 - Exit code (optional, default: 0)
# Returns.: Exits with specified code
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    local exit_code="${1:-0}"

    cat << EOF

Usage:
  ${SCRIPT_NAME} (-T <CSV> | -c <OCID|NAME>) [options]

Delete Data Safe target databases and their dependencies. Either provide 
explicit targets (-T) or scan a compartment (-c). If both are provided, -T takes precedence.

Target selection (choose one):
  -T, --targets <LIST>            Comma-separated target names or OCIDs
  (or) use lifecycle-state filtering:  
  -s, --state <LIST>              Comma-separated states (default: ${STATE_FILTERS})

Scope:
  -c, --compartment <OCID|NAME>   Compartment OCID or name (env: COMPARTMENT/COMP_OCID)

Deletion options:
  -f, --force                     Skip confirmation prompts
      --delete-dependencies       Delete audit trails, assessments, policies (default: true)
      --no-delete-dependencies    Skip deleting dependencies
      --continue-on-error         Continue with other targets if one fails (default: true)
      --stop-on-error             Stop processing on first failure

OCI CLI:
      --oci-config <file>         OCI CLI config file (default: ${OCI_CLI_CONFIG_FILE})
      --oci-profile <name>        OCI CLI profile     (default: ${OCI_CLI_PROFILE})

Logging / generic:
  -n, --dry-run                   Show what would be deleted without making changes
  -l, --log-file <file>           Write logs to <file>
  -v, --verbose                   Set log level to INFO
  -d, --debug                     Set log level to DEBUG
  -q, --quiet                     Suppress INFO/DEBUG/TRACE stdout
  -h, --help                      Show this help and exit

Examples:
  ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_HRPDB,test-target-2 --dry-run
  ${SCRIPT_NAME} -c my-compartment -s NEEDS_ATTENTION --force
  ${SCRIPT_NAME} -T ocid1.datasafetargetdatabase... --no-delete-dependencies

EOF
    exit "${exit_code}"
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on invalid arguments
# Notes...: Sets global variables for script configuration
# ------------------------------------------------------------------------------
parse_args() {
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -T | --targets)
                TARGETS="$2"
                shift 2
                ;;
            -s | --state)
                STATE_FILTERS="$2"
                shift 2
                ;;
            -c | --compartment)
                COMPARTMENT="$2"
                shift 2
                ;;
            -f | --force)
                FORCE=true
                shift
                ;;
            --delete-dependencies)
                DELETE_DEPENDENCIES=true
                shift
                ;;
            --no-delete-dependencies)
                DELETE_DEPENDENCIES=false
                shift
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift
                ;;
            --stop-on-error)
                CONTINUE_ON_ERROR=false
                ;;
            --oci-config)
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            --oci-profile)
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            -h | --help)
                usage 0
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Handle positional arguments as additional targets
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
# Purpose.: Validate required inputs and dependencies
# Returns.: 0 on success, exits on validation failure
# Notes...: Checks for required commands, resolves compartment, builds target list
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    # At least one scope must be specified
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        die "Either -T/--targets or -c/--compartment must be specified. Use -h for help."
    fi

    # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
    COMP_OCID=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment"
    log_info "Using compartment: $COMP_OCID"

    # Build target list
    if [[ -n "$TARGETS" ]]; then
        # Resolve target names/OCIDs to OCIDs
        local -a target_inputs
        IFS=',' read -ra target_inputs <<< "$TARGETS"
        log_debug "Explicit targets specified: ${#target_inputs[@]}"

        # Get search compartment (for name resolution)
        local search_comp_ocid
        if [[ -n "$COMP_OCID" ]]; then
            search_comp_ocid="$COMP_OCID"
        else
            search_comp_ocid=$(resolve_compartment_for_operation "") || die "Failed to get search compartment"
        fi

        # Resolve each target
        for target in "${target_inputs[@]}"; do
            [[ -z "$target" ]] && continue
            local resolved
            if resolved=$(ds_resolve_target_ocid "$target" "$search_comp_ocid" 2>&1); then
                RESOLVED_TARGETS+=("$resolved")
                log_debug "Resolved target: $target -> $resolved"
            else
                die "Failed to resolve target: $target"
            fi
        done
    elif [[ -n "$COMP_OCID" ]]; then
        # Get targets from compartment by lifecycle state
        log_debug "Scanning compartment for targets with state: $STATE_FILTERS"
        local targets_json
        targets_json=$(ds_list_targets "$COMP_OCID" "$STATE_FILTERS") || die "Failed to list targets in compartment"

        mapfile -t RESOLVED_TARGETS < <(echo "$targets_json" | jq -r '.data[]?.id // empty')
    fi

    if [[ ${#RESOLVED_TARGETS[@]} -eq 0 ]]; then
        die "No targets found to delete."
    fi

    log_info "Targets selected for deletion: ${#RESOLVED_TARGETS[@]}"

    # Confirmation unless force or dry-run
    if [[ "${FORCE}" != "true" && "${DRY_RUN}" != "true" ]]; then
        log_warn "This will DELETE ${#RESOLVED_TARGETS[@]} Data Safe target database(s)"
        [[ "${DELETE_DEPENDENCIES}" == "true" ]] && log_warn "Dependencies (audit trails, assessments, policies) will also be deleted"
        echo -n "Continue? [y/N]: "
        read -r confirm
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
            log_info "Deletion cancelled by user."
            exit 0
        fi
    fi
}

# --- Steps --------------------------------------------------------------------

# Step 1: Delete target dependencies
step_delete_dependencies() {
    [[ "${DELETE_DEPENDENCIES}" != "true" ]] && return 0

    log_info "Step 1/2: Deleting target dependencies..."

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        local target_name
        target_name="$(ds_resolve_target_name "${target_ocid}" 2> /dev/null || echo "${target_ocid}")"

        log_info "Processing dependencies for: ${target_name}"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] Would delete audit trails for ${target_name}"
            log_info "  [DRY-RUN] Would delete assessments for ${target_name}"
            log_info "  [DRY-RUN] Would delete security policies for ${target_name}"
            continue
        fi

        # Delete audit trails
        delete_audit_trails "${target_ocid}" "${target_name}"

        # Delete assessments
        delete_assessments "${target_ocid}" "${target_name}"

        # Delete security policies
        delete_security_policies "${target_ocid}" "${target_name}"
    done
}

# Step 2: Delete targets
step_delete_targets() {
    log_info "Step 2/2: Deleting target databases..."

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        local target_name
        target_name="$(ds_resolve_target_name "${target_ocid}" 2> /dev/null || echo "${target_ocid}")"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] Would delete target: ${target_name}"
            deleted_count=$((deleted_count + 1)) || true
            continue
        fi

        log_info "Deleting target: ${target_name}"

        if oci data-safe target-database delete \
            --target-database-id "${target_ocid}" \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" \
            --force \
            --wait-for-state SUCCEEDED \
            > /dev/null 2>&1; then
            log_info "  ✓ Successfully deleted: ${target_name}"
            deleted_count=$((deleted_count + 1)) || true
        else
            log_error "  ✗ Failed to delete: ${target_name}"
            failed_count=$((failed_count + 1)) || true
            [[ "${CONTINUE_ON_ERROR}" != "true" ]] && die 1 "Stopping on error"
        fi
    done

    return 0
}

# --- Dependency deletion helpers ----------------------------------------------

delete_audit_trails() {
    local target_ocid="$1"
    local target_name="$2"

    # List and delete audit trails for this target
    local trails_json
    if ! trails_json="$(oci data-safe audit-trail list \
        --target-database-id "${target_ocid}" \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" \
        --all 2> /dev/null)"; then
        log_debug "  Could not list audit trails for ${target_name} (may not exist or access issue)"
        return 0 # Continue processing - listing failure is not critical
    fi

    local trail_ocids
    trail_ocids="$(echo "${trails_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${trail_ocids}" ]]; then
        log_debug "  No audit trails found for ${target_name}"
        return 0
    fi

    local count=0
    local failed=0
    while IFS= read -r trail_ocid; do
        [[ -z "${trail_ocid}" ]] && continue
        if oci data-safe audit-trail delete \
            --audit-trail-id "${trail_ocid}" \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" \
            --force \
            > /dev/null 2>&1; then
            count=$((count + 1))
        else
            failed=$((failed + 1))
            log_error "    Failed to delete audit trail: ${trail_ocid}"
        fi
    done <<< "${trail_ocids}"

    if [[ $failed -gt 0 ]]; then
        log_debug "  Deleted ${count} of $((count + failed)) audit trails for ${target_name} (${failed} failed)"
    else
        log_debug "  Deleted ${count} audit trails for ${target_name}"
    fi
    return 0 # Always return success - individual failures are logged but not critical
}

delete_assessments() {
    local target_ocid="$1"
    local target_name="$2"

    # List and delete security assessments for this target
    local assessments_json
    if ! assessments_json="$(oci data-safe security-assessment list \
        --target-database-id "${target_ocid}" \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" \
        --all 2> /dev/null)"; then
        log_debug "  Could not list security assessments for ${target_name} (may not exist or access issue)"
        return 0 # Continue processing - listing failure is not critical
    fi

    local assessment_ocids
    assessment_ocids="$(echo "${assessments_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${assessment_ocids}" ]]; then
        log_debug "  No assessments found for ${target_name}"
        return 0
    fi

    local count=0
    local failed=0
    while IFS= read -r assessment_ocid; do
        [[ -z "${assessment_ocid}" ]] && continue
        if oci data-safe security-assessment delete \
            --security-assessment-id "${assessment_ocid}" \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" \
            --force \
            > /dev/null 2>&1; then
            count=$((count + 1))
        else
            failed=$((failed + 1))
            log_error "    Failed to delete assessment: ${assessment_ocid}"
        fi
    done <<< "${assessment_ocids}"

    if [[ $failed -gt 0 ]]; then
        log_debug "  Deleted ${count} of $((count + failed)) assessments for ${target_name} (${failed} failed)"
    else
        log_debug "  Deleted ${count} assessments for ${target_name}"
    fi
    return 0 # Always return success - individual failures are logged but not critical
}

delete_security_policies() {
    local target_ocid="$1"
    local target_name="$2"

    # List and delete security policies for this target
    local policies_json
    if ! policies_json="$(oci data-safe security-policy list \
        --target-database-id "${target_ocid}" \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" \
        --all 2> /dev/null)"; then
        log_debug "  Could not list security policies for ${target_name} (may not exist or access issue)"
        return 0 # Continue processing - listing failure is not critical
    fi

    local policy_ocids
    policy_ocids="$(echo "${policies_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${policy_ocids}" ]]; then
        log_debug "  No security policies found for ${target_name}"
        return 0
    fi

    local count=0
    local failed=0
    while IFS= read -r policy_ocid; do
        [[ -z "${policy_ocid}" ]] && continue
        if oci data-safe security-policy delete \
            --security-policy-id "${policy_ocid}" \
            --config-file "${OCI_CLI_CONFIG_FILE}" \
            --profile "${OCI_CLI_PROFILE}" \
            --force \
            > /dev/null 2>&1; then
            count=$((count + 1))
        else
            failed=$((failed + 1))
            log_error "    Failed to delete security policy: ${policy_ocid}"
        fi
    done <<< "${policy_ocids}"

    if [[ $failed -gt 0 ]]; then
        log_debug "  Deleted ${count} of $((count + failed)) security policies for ${target_name} (${failed} failed)"
    else
        log_debug "  Deleted ${count} security policies for ${target_name}"
    fi
    return 0 # Always return success - individual failures are logged but not critical
}

# ------------------------------------------------------------------------------
# Function....: run_deletion
# Purpose.....: Orchestrate the deletion steps
# ------------------------------------------------------------------------------
run_deletion() {
    step_delete_dependencies
    step_delete_targets

    # Summary
    log_info "Deletion summary:"
    log_info "  Targets processed: ${#RESOLVED_TARGETS[@]}"
    log_info "  Successfully deleted: ${deleted_count}"
    log_info "  Failed deletions: ${failed_count}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "  [DRY-RUN] No actual changes were made"
    fi

    local exit_code=0
    [[ ${failed_count} -gt 0 ]] && exit_code=1

    log_info "Target deletion completed"
    exit "${exit_code}"
}

# =========================================================================================================================================================
# MAIN
# =============================================================================

main() {
    # Initialize framework and parse arguments
    init_config
    parse_common_opts "$@"
    parse_args "${ARGS[@]}"

    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Execute main work
    run_deletion

    log_info "Deletion completed successfully"
}

# Run the script
# Handle --help before any processing
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        usage 0
    fi
done

# Show usage if no arguments provided
if [[ $# -eq 0 ]]; then
    usage 0
fi

main "$@"

exit 0
