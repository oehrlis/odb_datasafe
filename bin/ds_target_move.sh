#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_move.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.09
# Version....: v0.2.0
# Purpose....: Move Oracle Data Safe targets and their referencing objects
#              to another compartment for given target names/OCIDs.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_move.conf
#              > DEFAULT_CONF > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.09 oehrli - migrate to v0.2.0 framework pattern
# ------------------------------------------------------------------------------

# --- Code defaults (lowest precedence; overridden by .env/CONF/CLI) ----------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"

: "${COMPARTMENT:=}"                 # source compartment name or OCID
: "${TARGETS:=}"                     # CSV names/OCIDs (overrides compartment mode)
: "${STATE_FILTERS:=ACTIVE}"         # CSV lifecycle states when scanning compartment
: "${DEST_COMPARTMENT:=}"            # destination compartment name or OCID (required)

: "${MOVE_DEPENDENCIES:=true}"       # move audit trails, assessments, policies
: "${CONTINUE_ON_ERROR:=true}"       # continue processing other targets if one fails
: "${FORCE:=false}"                  # skip confirmation prompts

# shellcheck disable=SC2034  # DEFAULT_CONF may be used for configuration loading in future
DEFAULT_CONF="${SCRIPT_ETC_DIR:-./etc}/ds_target_move.conf"

# Runtime
COMP_OCID=""
COMP_NAME=""
DEST_COMP_OCID=""
DEST_COMP_NAME=""
# shellcheck disable=SC2034  # TARGET_LIST may be used for target resolution in future
TARGET_LIST=()
RESOLVED_TARGETS=()
moved_count=0
failed_count=0

# --- Minimal bootstrap: ensure SCRIPT_BASE and libraries ----------------------
if [[ -z "${SCRIPT_BASE:-}" || -z "${SCRIPT_LIB_DIR:-}" ]]; then
  _SRC="${BASH_SOURCE[0]}"
  SCRIPT_BASE="$(cd "$(dirname "${_SRC}")/.." >/dev/null 2>&1 && pwd)"
  SCRIPT_LIB_DIR="${SCRIPT_BASE}/lib"
  unset _SRC
fi

# Load the odb_datasafe v0.2.0 framework
if [[ -r "${SCRIPT_LIB_DIR}/ds_lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_LIB_DIR}/ds_lib.sh" || { echo "ERROR: ds_lib.sh failed to load." >&2; exit 1; }
else
  echo "ERROR: ds_lib.sh not found (tried: ${SCRIPT_LIB_DIR}/ds_lib.sh)" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Function....: Usage
# Purpose.....: Display command-line usage instructions and exit
# ------------------------------------------------------------------------------
Usage() {
  local exit_code="${1:-0}"
  
  cat << EOF

Usage:
  ds_target_move.sh (-T <CSV> | -c <OCID|NAME>) -D <DEST_COMP> [options]

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
  ds_target_move.sh -T exa118r05c15_cdb09a15_HRPDB -D cmp-prod-datasafe --dry-run
  ds_target_move.sh -c cmp-test-datasafe -D cmp-prod-datasafe --no-move-dependencies
  ds_target_move.sh -T test-target-1,test-target-2 -D prod-compartment --force

EOF
  die "${exit_code}" ""
}

# ------------------------------------------------------------------------------
# Function....: parse_args
# Purpose.....: Parse script-specific arguments from REM_ARGS
# ------------------------------------------------------------------------------
parse_args() {
  local -a args=("${REM_ARGS[@]}")
  POSITIONAL=()

  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
      -T|--targets)               TARGETS="${args[++i]:-}" ;;
      -s|--state)                 STATE_FILTERS="${args[++i]:-}" ;;
      -c|--compartment)           COMPARTMENT="${args[++i]:-}" ;;
      -D|--dest-compartment)      DEST_COMPARTMENT="${args[++i]:-}" ;;
      --move-dependencies)        MOVE_DEPENDENCIES=true ;;
      --no-move-dependencies)     MOVE_DEPENDENCIES=false ;;
      -f|--force)                 FORCE=true ;;
      --continue-on-error)        CONTINUE_ON_ERROR=true ;;
      --stop-on-error)            CONTINUE_ON_ERROR=false ;;
      --oci-config)               OCI_CLI_CONFIG_FILE="${args[++i]:-}" ;;
      --oci-profile)              OCI_CLI_PROFILE="${args[++i]:-}" ;;
      -h|--help)                  Usage 0 ;;
      --)                         ((i++)); while ((i < ${#args[@]})); do POSITIONAL+=("${args[i++]}"); done ;;
      -*)                         log_error "Unknown option: ${args[i]}"; Usage 2 ;;
      *)                          POSITIONAL+=("${args[i]}") ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# Function....: preflight_checks
# Purpose.....: Validate inputs and resolve targets and compartments
# ------------------------------------------------------------------------------
preflight_checks() {
  # Destination compartment is required
  [[ -z "${DEST_COMPARTMENT}" ]] && die 2 "Destination compartment (-D) is required"

  # Resolve destination compartment
  if is_ocid "${DEST_COMPARTMENT}"; then
    DEST_COMP_OCID="${DEST_COMPARTMENT}"
    DEST_COMP_NAME="$(oci_resolve_compartment_name "${DEST_COMP_OCID}" 2>/dev/null || echo "${DEST_COMP_OCID}")"
  else
    DEST_COMP_NAME="${DEST_COMPARTMENT}"
    DEST_COMP_OCID="$(oci_resolve_compartment_ocid "${DEST_COMP_NAME}")" || \
      die 1 "Cannot resolve destination compartment '${DEST_COMPARTMENT}'"
  fi
  
  log_info "Destination compartment: ${DEST_COMP_NAME} (${DEST_COMP_OCID})"

  # Build target list from -T and positionals
  ds_build_target_list TARGET_LIST "${TARGETS:-}" POSITIONAL
  
  # Validate/augment from compartment + filters
  ds_validate_and_fill_targets \
    TARGET_LIST "${COMPARTMENT:-}" "${STATE_FILTERS:-}" "" \
    COMP_OCID COMP_NAME

  # Resolve names → OCIDs
  ds_resolve_targets_to_ocids TARGET_LIST RESOLVED_TARGETS || \
    die 1 "Failed to resolve targets to OCIDs."

  log_info "Targets selected for move: ${#RESOLVED_TARGETS[@]}"

  if [[ ${#RESOLVED_TARGETS[@]} -eq 0 ]]; then
    die 1 "No targets found to move."
  fi

  # Ensure source and destination are different
  if [[ -n "${COMP_OCID}" && "${COMP_OCID}" == "${DEST_COMP_OCID}" ]]; then
    die 2 "Source and destination compartments cannot be the same"
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
      die 0 "Move cancelled by user."
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
    target_name="$(ds_resolve_target_name "${target_ocid}" 2>/dev/null || echo "${target_ocid}")"
    
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
    target_name="$(ds_resolve_target_name "${target_ocid}" 2>/dev/null || echo "${target_ocid}")"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "  [DRY-RUN] Would move target: ${target_name}"
      ((moved_count++))
      continue
    fi

    log_info "Moving target: ${target_name}"
    
    if oci data-safe target-database change-compartment \
         --target-database-id "${target_ocid}" \
         --compartment-id "${DEST_COMP_OCID}" \
         --config-file "${OCI_CLI_CONFIG_FILE}" \
         --profile "${OCI_CLI_PROFILE}" \
         >/dev/null 2>&1; then
      log_info "  ✓ Successfully moved: ${target_name}"
      ((moved_count++))
    else
      log_error "  ✗ Failed to move: ${target_name}"
      ((failed_count++))
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
  trails_json="$(oci data-safe audit-trail list \
    --target-database-id "${target_ocid}" \
    --config-file "${OCI_CLI_CONFIG_FILE}" \
    --profile "${OCI_CLI_PROFILE}" \
    --all 2>/dev/null)" || return 1

  local trail_ocids
  trail_ocids="$(echo "${trails_json}" | jq -r '.data[]?.id // empty')"
  
  if [[ -z "${trail_ocids}" ]]; then
    log_debug "  No audit trails found for ${target_name}"
    return 0
  fi

  local count=0
  while IFS= read -r trail_ocid; do
    [[ -z "${trail_ocid}" ]] && continue
    if oci data-safe audit-trail change-compartment \
         --audit-trail-id "${trail_ocid}" \
         --compartment-id "${DEST_COMP_OCID}" \
         --config-file "${OCI_CLI_CONFIG_FILE}" \
         --profile "${OCI_CLI_PROFILE}" \
         >/dev/null 2>&1; then
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
  assessments_json="$(oci data-safe security-assessment list \
    --target-database-id "${target_ocid}" \
    --config-file "${OCI_CLI_CONFIG_FILE}" \
    --profile "${OCI_CLI_PROFILE}" \
    --all 2>/dev/null)" || return 1

  local assessment_ocids
  assessment_ocids="$(echo "${assessments_json}" | jq -r '.data[]?.id // empty')"
  
  if [[ -z "${assessment_ocids}" ]]; then
    log_debug "  No assessments found for ${target_name}"
    return 0
  fi

  local count=0
  while IFS= read -r assessment_ocid; do
    [[ -z "${assessment_ocid}" ]] && continue
    if oci data-safe security-assessment change-compartment \
         --security-assessment-id "${assessment_ocid}" \
         --compartment-id "${DEST_COMP_OCID}" \
         --config-file "${OCI_CLI_CONFIG_FILE}" \
         --profile "${OCI_CLI_PROFILE}" \
         >/dev/null 2>&1; then
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
  policies_json="$(oci data-safe security-policy list \
    --target-database-id "${target_ocid}" \
    --config-file "${OCI_CLI_CONFIG_FILE}" \
    --profile "${OCI_CLI_PROFILE}" \
    --all 2>/dev/null)" || return 1

  local policy_ocids
  policy_ocids="$(echo "${policies_json}" | jq -r '.data[]?.id // empty')"
  
  if [[ -z "${policy_ocids}" ]]; then
    log_debug "  No security policies found for ${target_name}"
    return 0
  fi

  local count=0
  while IFS= read -r policy_ocid; do
    [[ -z "${policy_ocid}" ]] && continue
    if oci data-safe security-policy change-compartment \
         --security-policy-id "${policy_ocid}" \
         --compartment-id "${DEST_COMP_OCID}" \
         --config-file "${OCI_CLI_CONFIG_FILE}" \
         --profile "${OCI_CLI_PROFILE}" \
         >/dev/null 2>&1; then
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
  init_script_env "$@"   # standardized init per odb_datasafe framework
  parse_args
  preflight_checks
  run_move
}

# --- Entry point --------------------------------------------------------------
main "$@"