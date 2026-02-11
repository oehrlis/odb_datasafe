#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_move.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v0.7.0
# Purpose....: Move Oracle Data Safe targets and their referencing objects
#              to another compartment for given target names/OCIDs.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_move.conf > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.09 oehrli - migrate to v0.2.0 framework pattern
# 2026.01.22 oehrli - align with standard pattern and OCI helpers
# ------------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------------------
# BOOTSTRAP
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '0.5.4')"
# shellcheck disable=SC2034  # Used by parse_common_opts for --version output
readonly SCRIPT_NAME SCRIPT_VERSION

if [[ ! -f "${LIB_DIR}/ds_lib.sh" ]]; then
    echo "[ERROR] Cannot find ds_lib.sh in ${LIB_DIR}" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh"

# ------------------------------------------------------------------------------
# DEFAULTS
# ------------------------------------------------------------------------------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"
: "${COMPARTMENT:=}"              # Source compartment name or OCID
: "${TARGETS:=}"                  # CSV names/OCIDs (overrides compartment mode)
: "${STATE_FILTERS:=ACTIVE}"      # CSV lifecycle states when scanning compartment
: "${DEST_COMPARTMENT:=}"         # Destination compartment name or OCID (required)
: "${MOVE_DEPENDENCIES:=true}"    # Move audit trails, assessments, policies
: "${CONTINUE_ON_ERROR:=true}"    # Continue processing other targets if one fails
: "${FORCE:=false}"               # Skip confirmation prompts
: "${DRY_RUN:=false}"

# Runtime
COMP_OCID=""
COMP_NAME=""
DEST_COMP_OCID=""
DEST_COMP_NAME=""
# shellcheck disable=SC2034  # Populated via helper functions
TARGET_LIST=()
RESOLVED_TARGETS=()
moved_count=0
failed_count=0

# Load configuration (env, defaults, config files)
init_config

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display command-line usage instructions and exit
# Returns.: Exits with provided code (default 0)
# ------------------------------------------------------------------------------
usage() {
        local exit_code="${1:-0}"
        cat << EOF

Usage:
    ${SCRIPT_NAME} (-T <CSV> | -c <OCID|NAME>) -D <DEST_COMP> [options]

Move Data Safe targets and their referencing objects to another compartment.
Either provide explicit targets (-T) or scan a compartment (-c).

Target selection (choose one):
    -T, --targets <LIST>            Comma-separated target names or OCIDs
    (or) use lifecycle-state filtering:
    -s, --state <LIST>              Comma-separated states (default: ${STATE_FILTERS})

Scope:
    -c, --compartment <OCID|NAME>   Source compartment OCID or name (env: COMPARTMENT/COMP_OCID)
    -D, --dest-compartment <OCID|NAME> Destination compartment OCID or name (required)

Move options:
            --move-dependencies         Move audit trails, assessments, policies (default: true)
            --no-move-dependencies      Skip moving dependencies
    -f, --force                     Skip confirmation prompts
            --continue-on-error         Continue with other targets if one fails (default: true)
            --stop-on-error             Stop processing on first failure

OCI CLI:
            --oci-config <file>         OCI CLI config file (default: ${OCI_CLI_CONFIG_FILE})
            --oci-profile <name>        OCI CLI profile     (default: ${OCI_CLI_PROFILE})

Logging / generic:
    -n, --dry-run                   Show what would be moved without making changes
    -l, --log-file <file>           Write logs to <file>
    -v, --verbose                   Set log level to INFO
    -d, --debug                     Set log level to DEBUG
    -q, --quiet                     Suppress INFO/DEBUG/TRACE stdout
    -h, --help                      Show this help and exit

Examples:
    ${SCRIPT_NAME} -T exa118r05c15_cdb09a15_HRPDB -D cmp-prod-datasafe --dry-run
    ${SCRIPT_NAME} -c cmp-test-datasafe -D cmp-prod-datasafe --no-move-dependencies
    ${SCRIPT_NAME} -T test-target-1,test-target-2 -D prod-compartment --force

EOF
        exit "${exit_code}"
}

# ------------------------------------------------------------------------------
# Function....: parse_args
# Purpose.....: Parse script-specific arguments from REM_ARGS
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    POSITIONAL=()
    local -a remaining=()
    set -- "${ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -s | --state)
                need_val "$1" "${2:-}"
                STATE_FILTERS="$2"
                shift 2
                ;;
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -D | --dest-compartment)
                need_val "$1" "${2:-}"
                DEST_COMPARTMENT="$2"
                shift 2
                ;;
            --move-dependencies)
                MOVE_DEPENDENCIES=true
                shift 1
                ;;
            --no-move-dependencies)
                MOVE_DEPENDENCIES=false
                shift 1
                ;;
            -f | --force)
                FORCE=true
                shift 1
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift 1
                ;;
            --stop-on-error)
                CONTINUE_ON_ERROR=false
                shift 1
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            -h | --help)
                usage 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    remaining+=("$1")
                    shift
                done
                ;;
            -*)
                log_error "Unknown option: $1"
                usage 2
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    POSITIONAL=("${remaining[@]}")
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Ensure required arguments are provided
# Returns.: Exits on validation error
# ------------------------------------------------------------------------------
validate_inputs() {
    if [[ -z "${DEST_COMPARTMENT}" ]]; then
        log_error "Destination compartment (-D) is required"
        usage 1
    fi

    if [[ -z "${TARGETS}" && -z "${COMPARTMENT}" && ${#POSITIONAL[@]} -eq 0 ]]; then
        log_error "Provide targets (-T) or a source compartment (-c)"
        usage 1
    fi
}

# ------------------------------------------------------------------------------
# Function....: preflight_checks
# Purpose.....: Validate inputs and resolve targets and compartments
# ------------------------------------------------------------------------------
preflight_checks() {
    # Resolve destination compartment using helper
    resolve_compartment_to_vars "${DEST_COMPARTMENT}" "DEST_COMP" \
        || die "Cannot resolve destination compartment '${DEST_COMPARTMENT}'"
    
    log_info "Destination compartment: ${DEST_COMP_NAME} (${DEST_COMP_OCID})"

    # Collect target OCIDs
    local -a target_ocids=()
    local compartment_ocid=""
    
    if [[ -n "$TARGETS" ]]; then
        # Process explicit targets
        log_info "Processing explicit targets"
        
        # Resolve compartment using standard pattern: explicit > DS_ROOT_COMP > error
        compartment_ocid=$(resolve_compartment_for_operation "$COMPARTMENT") || \
            die "Failed to resolve compartment for target resolution"
        
        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces
            [[ -z "$target" ]] && continue

            local target_ocid

            if is_ocid "$target"; then
                target_ocid="$target"
            else
                # Resolve target name to OCID using resolved compartment
                target_ocid=$(ds_resolve_target_ocid "$target" "$compartment_ocid") || {
                    log_error "Failed to resolve target: $target"
                    continue
                }
            fi

            # Optional: fetch to confirm existence and for logging
            if oci_exec_ro data-safe target-database get \
                --target-database-id "$target_ocid" \
                --query 'data.id' \
                --raw-output > /dev/null 2>&1; then
                target_ocids+=("$target_ocid")
            else
                log_error "Failed to get details for target: $target_ocid"
            fi
        done
    else
        # Scan compartment
        log_info "Scanning compartment for targets"
        
        # Resolve compartment
        if is_ocid "$COMPARTMENT"; then
            compartment_ocid="$COMPARTMENT"
        else
            compartment_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT") || \
                die "Failed to resolve compartment: $COMPARTMENT"
        fi
        
        # Get compartment name
        if is_ocid "$COMPARTMENT"; then
            COMP_NAME=$(oci_get_compartment_name "$compartment_ocid" 2>/dev/null) || COMP_NAME="$compartment_ocid"
        else
            COMP_NAME="$COMPARTMENT"
        fi
        COMP_OCID="$compartment_ocid"
        
        # List targets in compartment with state filters (comma-separated supported)
        local targets_json
        targets_json=$(ds_list_targets "$compartment_ocid" "$STATE_FILTERS") || die "Failed to list targets in compartment"
        while IFS=$'\t' read -r ocid; do
            [[ -n "$ocid" ]] && target_ocids+=("$ocid")
        done < <(echo "$targets_json" | jq -r '.data[]?.id' 2>/dev/null)
    fi
    
    # Store resolved targets
    RESOLVED_TARGETS=("${target_ocids[@]}")
    
    log_info "Targets selected for move: ${#RESOLVED_TARGETS[@]}"

    if [[ ${#RESOLVED_TARGETS[@]} -eq 0 ]]; then
        die "No targets found to move."
    fi

    # Ensure source and destination are different
    if [[ -n "${COMP_OCID}" && "${COMP_OCID}" == "${DEST_COMP_OCID}" ]]; then
        die "Source and destination compartments cannot be the same"
    fi

    # Confirmation unless force or dry-run
    if [[ "${FORCE}" != "true" && "${DRY_RUN}" != "true" ]]; then
        log_warn "This will MOVE ${#RESOLVED_TARGETS[@]} Data Safe target database(s)"
        log_warn "From: ${COMP_NAME:-"various compartments"}"
        log_warn "To: ${DEST_COMP_NAME}"
        [[ "${MOVE_DEPENDENCIES}" == "true" ]] && log_warn "Dependencies (audit trails, assessments, policies) will also be moved"
        echo -n "Continue? [y/N]: "
        read -r confirm
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
            die "Move cancelled by user."
        fi
    fi
}

# --- Steps --------------------------------------------------------------------

# Step 1: Move target dependencies
step_move_dependencies() {
    [[ "${MOVE_DEPENDENCIES}" != "true" ]] && return 0

    log_info "Step 1/2: Moving target dependencies..."

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        local target_name
        target_name="$(ds_resolve_target_name "${target_ocid}" 2> /dev/null || echo "${target_ocid}")"

        log_info "Processing dependencies for: ${target_name}"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] Would move audit trails for ${target_name}"
            log_info "  [DRY-RUN] Would move assessments for ${target_name}"
            log_info "  [DRY-RUN] Would move security policies for ${target_name}"
            continue
        fi

        # Move audit trails
        if ! move_audit_trails "${target_ocid}" "${target_name}"; then
            log_error "Failed to move audit trails for ${target_name}"
            [[ "${CONTINUE_ON_ERROR}" != "true" ]] && die 1 "Stopping on error"
        fi

        # Move assessments
        if ! move_assessments "${target_ocid}" "${target_name}"; then
            log_error "Failed to move assessments for ${target_name}"
            [[ "${CONTINUE_ON_ERROR}" != "true" ]] && die 1 "Stopping on error"
        fi

        # Move security policies
        if ! move_security_policies "${target_ocid}" "${target_name}"; then
            log_error "Failed to move security policies for ${target_name}"
            [[ "${CONTINUE_ON_ERROR}" != "true" ]] && die 1 "Stopping on error"
        fi
    done
}

# Step 2: Move targets
step_move_targets() {
    log_info "Step 2/2: Moving target databases..."

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        local target_name
        target_name="$(ds_resolve_target_name "${target_ocid}" 2> /dev/null || echo "${target_ocid}")"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] Would move target: ${target_name}"
            moved_count=$((moved_count + 1))
            continue
        fi

        log_info "Moving target: ${target_name}"

        if oci_exec data-safe target-database change-compartment \
            --target-database-id "${target_ocid}" \
            --compartment-id "${DEST_COMP_OCID}" \
            > /dev/null; then
            log_info "  ✓ Successfully moved: ${target_name}"
            moved_count=$((moved_count + 1))
        else
            log_error "  ✗ Failed to move: ${target_name}"
            failed_count=$((failed_count + 1))
            [[ "${CONTINUE_ON_ERROR}" != "true" ]] && die 1 "Stopping on error"
        fi
    done
}

# --- Dependency moving helpers -----------------------------------------------

move_audit_trails() {
    local target_ocid="$1"
    local target_name="$2"

    # List and move audit trails for this target
    local trails_json
    trails_json=$(oci_exec_ro data-safe audit-trail list \
        --target-database-id "${target_ocid}" \
        --all 2>/dev/null) || {
        log_debug "  No audit trails found for ${target_name}"
        return 0
    }

    local trail_ocids
    trail_ocids="$(echo "${trails_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${trail_ocids}" ]]; then
        log_debug "  No audit trails found for ${target_name}"
        return 0
    fi

    local count=0
    while IFS= read -r trail_ocid; do
        [[ -z "${trail_ocid}" ]] && continue
        if oci_exec data-safe audit-trail change-compartment \
            --audit-trail-id "${trail_ocid}" \
            --compartment-id "${DEST_COMP_OCID}" \
            > /dev/null; then
            ((count++))
        else
            log_error "    Failed to move audit trail: ${trail_ocid}"
        fi
    done <<< "${trail_ocids}"

    log_debug "  Moved ${count} audit trails for ${target_name}"
    return 0
}

move_assessments() {
    local target_ocid="$1"
    local target_name="$2"

    # List and move security assessments for this target
    local assessments_json
    assessments_json=$(oci_exec_ro data-safe security-assessment list \
        --target-database-id "${target_ocid}" \
        --all 2>/dev/null) || {
        log_debug "  No assessments found for ${target_name}"
        return 0
    }

    local assessment_ocids
    assessment_ocids="$(echo "${assessments_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${assessment_ocids}" ]]; then
        log_debug "  No assessments found for ${target_name}"
        return 0
    fi

    local count=0
    while IFS= read -r assessment_ocid; do
        [[ -z "${assessment_ocid}" ]] && continue
        if oci_exec data-safe security-assessment change-compartment \
            --security-assessment-id "${assessment_ocid}" \
            --compartment-id "${DEST_COMP_OCID}" \
            > /dev/null; then
            ((count++))
        else
            log_error "    Failed to move assessment: ${assessment_ocid}"
        fi
    done <<< "${assessment_ocids}"

    log_debug "  Moved ${count} assessments for ${target_name}"
    return 0
}

move_security_policies() {
    local target_ocid="$1"
    local target_name="$2"

    # List and move security policies for this target
    local policies_json
    policies_json=$(oci_exec_ro data-safe security-policy list \
        --target-database-id "${target_ocid}" \
        --all 2>/dev/null) || {
        log_debug "  No security policies found for ${target_name}"
        return 0
    }

    local policy_ocids
    policy_ocids="$(echo "${policies_json}" | jq -r '.data[]?.id // empty')"

    if [[ -z "${policy_ocids}" ]]; then
        log_debug "  No security policies found for ${target_name}"
        return 0
    fi

    local count=0
    while IFS= read -r policy_ocid; do
        [[ -z "${policy_ocid}" ]] && continue
        if oci_exec data-safe security-policy change-compartment \
            --security-policy-id "${policy_ocid}" \
            --compartment-id "${DEST_COMP_OCID}" \
            > /dev/null; then
            ((count++))
        else
            log_error "    Failed to move security policy: ${policy_ocid}"
        fi
    done <<< "${policy_ocids}"

    log_debug "  Moved ${count} security policies for ${target_name}"
    return 0
}

# ------------------------------------------------------------------------------
# Function....: run_move
# Purpose.....: Orchestrate the move steps
# ------------------------------------------------------------------------------
run_move() {
    step_move_dependencies
    step_move_targets

    # Summary
    log_info "Move summary:"
    log_info "  Targets processed: ${#RESOLVED_TARGETS[@]}"
    log_info "  Successfully moved: ${moved_count}"
    log_info "  Failed moves: ${failed_count}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "  [DRY-RUN] No actual changes were made"
    fi

    local exit_code=0
    [[ ${failed_count} -gt 0 ]] && exit_code=1

    die "${exit_code}" "Target move completed"
}

# ------------------------------------------------------------------------------
# Function....: main
# Purpose.....: Entry point
# ------------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        usage 0
    fi

    parse_args "$@"
    validate_inputs
    preflight_checks
    run_move
}

# --- Entry point --------------------------------------------------------------
main "$@"
