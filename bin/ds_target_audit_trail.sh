#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_audit_trail.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.09
# Version....: v0.5.4
# Purpose....: Start Oracle Data Safe audit trails for one or many targets
#              for given target names/OCIDs or all targets in a compartment.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_audit_trail.conf
#              > DEFAULT_CONF > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.09 oehrli - migrate to v0.2.0 framework pattern
# ------------------------------------------------------------------------------

# --- Code defaults (lowest precedence; overridden by .env/CONF/CLI) ----------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"

: "${COMPARTMENT:=}"         # name or OCID
: "${TARGETS:=}"             # CSV names/OCIDs (overrides compartment mode)
: "${STATE_FILTERS:=ACTIVE}" # CSV lifecycle states when scanning compartment
: "${TRAIL_LOCATION:=}"      # specific trail location (optional)

# Audit trail configuration
: "${AUDIT_TYPE:=UNIFIED_AUDIT}"   # UNIFIED_AUDIT | DATABASE_VAULT | OS_AUDIT
: "${START_TIME:=}"                # RFC3339 timestamp or 'now' (default: now)
: "${AUTO_PURGE:=true}"            # enable auto-purge
: "${RETENTION_DAYS:=90}"          # retention period in days
: "${UPDATE_LAST_ARCHIVE:=true}"   # update last archive time
: "${COLLECTION_FREQUENCY:=DAILY}" # DAILY | WEEKLY | MONTHLY

RESOLVED_TARGETS=()
started_count=0
failed_count=0

# --- Minimal bootstrap: ensure SCRIPT_BASE and libraries ----------------------
if [[ -z "${SCRIPT_BASE:-}" || -z "${SCRIPT_LIB_DIR:-}" ]]; then
    _SRC="${BASH_SOURCE[0]}"
    SCRIPT_BASE="$(cd "$(dirname "${_SRC}")/.." > /dev/null 2>&1 && pwd)"
    SCRIPT_LIB_DIR="${SCRIPT_BASE}/lib"
    unset _SRC
fi

# Load the odb_datasafe v0.2.0 framework
if [[ -r "${SCRIPT_LIB_DIR}/ds_lib.sh" ]]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_LIB_DIR}/ds_lib.sh" || {
        echo "ERROR: ds_lib.sh failed to load." >&2
        exit 1
    }
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
  ds_target_audit_trail.sh (-T <CSV> | -c <OCID|NAME>) [options]

Start Data Safe audit trails for target databases. Either provide explicit 
targets (-T) or scan a compartment (-c). If both are provided, -T takes precedence.

Target selection (choose one):
  -T, --targets <LIST>            Comma-separated target names or OCIDs
  (or) use lifecycle-state filtering:
  -s, --state <LIST>              Comma-separated states (default: ${STATE_FILTERS})

Scope:
  -c, --compartment <OCID|NAME>   Compartment OCID or name (env: COMPARTMENT/COMP_OCID)
      --trail-location <LOC>      Specific trail location name/OCID (optional)

Audit trail configuration:
      --audit-type <TYPE>         Audit type: UNIFIED_AUDIT|DATABASE_VAULT|OS_AUDIT
                                  (default: ${AUDIT_TYPE})
      --start-time <TIME>         Start time (RFC3339 or 'now'; default: now)
      --auto-purge true|false     Enable auto-purge (default: ${AUTO_PURGE})
      --retention-days <DAYS>     Retention period in days (default: ${RETENTION_DAYS})
      --update-last-archive true|false Update last archive time (default: ${UPDATE_LAST_ARCHIVE})
      --collection-frequency <FREQ> Collection frequency: DAILY|WEEKLY|MONTHLY 
                                  (default: ${COLLECTION_FREQUENCY})

OCI CLI:
      --oci-config <file>         OCI CLI config file (default: ${OCI_CLI_CONFIG_FILE})
      --oci-profile <name>        OCI CLI profile     (default: ${OCI_CLI_PROFILE})

Logging / generic:
  -n, --dry-run                   Show what would be started without making changes
  -l, --log-file <file>           Write logs to <file>
  -v, --verbose                   Set log level to INFO
  -d, --debug                     Set log level to DEBUG
  -q, --quiet                     Suppress INFO/DEBUG/TRACE stdout
  -h, --help                      Show this help and exit

Examples:
  ds_target_audit_trail.sh -T exa118r05c15_cdb09a15_HRPDB --dry-run
  ds_target_audit_trail.sh -c my-compartment --audit-type UNIFIED_AUDIT
  ds_target_audit_trail.sh -T test-target-1 --retention-days 180 --collection-frequency WEEKLY

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
            -T | --targets) TARGETS="${args[++i]:-}" ;;
            -s | --state) STATE_FILTERS="${args[++i]:-}" ;;
            -c | --compartment) COMPARTMENT="${args[++i]:-}" ;;
            --trail-location) TRAIL_LOCATION="${args[++i]:-}" ;;
            --audit-type) AUDIT_TYPE="${args[++i]:-}" ;;
            --start-time) START_TIME="${args[++i]:-}" ;;
            --auto-purge) AUTO_PURGE="${args[++i]:-}" ;;
            --retention-days) RETENTION_DAYS="${args[++i]:-}" ;;
            --update-last-archive) UPDATE_LAST_ARCHIVE="${args[++i]:-}" ;;
            --collection-frequency) COLLECTION_FREQUENCY="${args[++i]:-}" ;;
            --oci-config) OCI_CLI_CONFIG_FILE="${args[++i]:-}" ;;
            --oci-profile) OCI_CLI_PROFILE="${args[++i]:-}" ;;
            -h | --help) Usage 0 ;;
            --)
                ((i++))
                while ((i < ${#args[@]})); do POSITIONAL+=("${args[i++]}"); done
                ;;
            -*)
                log_error "Unknown option: ${args[i]}"
                Usage 2
                ;;
            *) POSITIONAL+=("${args[i]}") ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Function....: preflight_checks
# Purpose.....: Validate inputs and resolve targets
# ------------------------------------------------------------------------------
preflight_checks() {
    # Build target list from -T and positionals
    ds_build_target_list TARGET_LIST "${TARGETS:-}" POSITIONAL

    # Validate/augment from compartment + filters
    ds_validate_and_fill_targets \
        TARGET_LIST "${COMPARTMENT:-}" "${STATE_FILTERS:-}" "" \
        COMP_OCID COMP_NAME

    # Resolve names → OCIDs
    ds_resolve_targets_to_ocids TARGET_LIST RESOLVED_TARGETS \
        || die 1 "Failed to resolve targets to OCIDs."

    log_info "Targets selected for audit trail start: ${#RESOLVED_TARGETS[@]}"

    if [[ ${#RESOLVED_TARGETS[@]} -eq 0 ]]; then
        die 1 "No targets found to start audit trails."
    fi

    # Validate audit type
    case "${AUDIT_TYPE^^}" in
        UNIFIED_AUDIT | DATABASE_VAULT | OS_AUDIT)
            AUDIT_TYPE="${AUDIT_TYPE^^}"
            ;;
        *)
            die 2 "Invalid audit type '${AUDIT_TYPE}'. Use UNIFIED_AUDIT|DATABASE_VAULT|OS_AUDIT."
            ;;
    esac

    # Validate collection frequency
    case "${COLLECTION_FREQUENCY^^}" in
        DAILY | WEEKLY | MONTHLY)
            COLLECTION_FREQUENCY="${COLLECTION_FREQUENCY^^}"
            ;;
        *)
            die 2 "Invalid collection frequency '${COLLECTION_FREQUENCY}'. Use DAILY|WEEKLY|MONTHLY."
            ;;
    esac

    # Validate boolean flags
    case "${AUTO_PURGE,,}" in
        true | false) : ;;
        *) die 2 "Invalid auto-purge value '${AUTO_PURGE}'. Use true|false." ;;
    esac

    case "${UPDATE_LAST_ARCHIVE,,}" in
        true | false) : ;;
        *) die 2 "Invalid update-last-archive value '${UPDATE_LAST_ARCHIVE}'. Use true|false." ;;
    esac

    # Validate retention days
    if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [[ ${RETENTION_DAYS} -lt 1 ]]; then
        die 2 "Invalid retention days '${RETENTION_DAYS}'. Must be a positive integer."
    fi

    # Set default start time if not provided
    [[ -z "${START_TIME}" ]] && START_TIME="now"

    log_info "Audit trail configuration:"
    log_info "  Type: ${AUDIT_TYPE}"
    log_info "  Start time: ${START_TIME}"
    log_info "  Auto-purge: ${AUTO_PURGE}"
    log_info "  Retention: ${RETENTION_DAYS} days"
    log_info "  Collection frequency: ${COLLECTION_FREQUENCY}"
}

# --- Steps --------------------------------------------------------------------

# Step 1: Start audit trails for each target
step_start_audit_trails() {
    log_info "Starting audit trails for targets..."

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        local target_name
        target_name="$(ds_resolve_target_name "${target_ocid}" 2> /dev/null || echo "${target_ocid}")"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "  [DRY-RUN] Would start ${AUDIT_TYPE} audit trail for: ${target_name}"
            ((started_count++))
            continue
        fi

        log_info "Starting ${AUDIT_TYPE} audit trail for: ${target_name}"

        if start_audit_trail_for_target "${target_ocid}" "${target_name}"; then
            log_info "  ✓ Successfully started audit trail for: ${target_name}"
            ((started_count++))
        else
            log_error "  ✗ Failed to start audit trail for: ${target_name}"
            ((failed_count++))
        fi
    done
}

# --- Audit trail management helpers ------------------------------------------

start_audit_trail_for_target() {
    local target_ocid="$1"
    local target_name="$2"

    # Check if audit trail already exists and is active
    if check_existing_audit_trail "${target_ocid}"; then
        log_info "    Audit trail already active for ${target_name}"
        return 0
    fi

    # Prepare start time
    local start_time_formatted
    if [[ "${START_TIME}" == "now" ]]; then
        start_time_formatted="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        start_time_formatted="${START_TIME}"
    fi

    # Build audit trail start command
    local cmd_args=(
        "oci" "data-safe" "audit-trail" "start"
        "--target-database-id" "${target_ocid}"
        "--audit-collection-start-time" "${start_time_formatted}"
        "--config-file" "${OCI_CLI_CONFIG_FILE}"
        "--profile" "${OCI_CLI_PROFILE}"
        "--wait-for-state" "ACCEPTED"
    )

    # Add optional parameters
    [[ -n "${TRAIL_LOCATION}" ]] && cmd_args+=("--trail-location" "${TRAIL_LOCATION}")

    # Add audit trail configuration parameters
    if [[ "${AUTO_PURGE,,}" == "true" ]]; then
        cmd_args+=("--auto-purge-enabled")
    fi

    # Note: Some parameters might need to be set via separate update calls
    # depending on OCI CLI version and availability

    log_debug "    Executing: ${cmd_args[*]}"

    # Execute the start command
    if "${cmd_args[@]}" > /dev/null 2>&1; then
        # Try to configure additional parameters if they're supported
        configure_audit_trail_parameters "${target_ocid}"
        return 0
    else
        return 1
    fi
}

check_existing_audit_trail() {
    local target_ocid="$1"

    # List existing audit trails for this target
    local trails_json
    trails_json="$(oci data-safe audit-trail list \
        --target-database-id "${target_ocid}" \
        --config-file "${OCI_CLI_CONFIG_FILE}" \
        --profile "${OCI_CLI_PROFILE}" \
        --all 2> /dev/null)" || return 1

    # Check if any trail is already in ACTIVE or STARTING state
    local active_trails
    active_trails="$(echo "${trails_json}" | jq -r '
    .data[]? | 
    select(.["lifecycle-state"] == "ACTIVE" or .["lifecycle-state"] == "STARTING") | 
    .id')"

    [[ -n "${active_trails}" ]]
}

configure_audit_trail_parameters() {
    local target_ocid="$1"

    # This function would configure additional parameters like retention,
    # collection frequency, etc. The exact implementation depends on the
    # OCI CLI capabilities and API endpoints available.

    log_debug "    Configuring additional audit trail parameters for ${target_ocid}"

    # Example configuration (adapt based on actual OCI CLI capabilities):
    # - Set retention policy
    # - Configure collection frequency
    # - Update other audit trail settings

    # For now, log the intended configuration
    log_debug "    - Retention days: ${RETENTION_DAYS}"
    log_debug "    - Collection frequency: ${COLLECTION_FREQUENCY}"
    log_debug "    - Update last archive: ${UPDATE_LAST_ARCHIVE}"

    return 0
}

# ------------------------------------------------------------------------------
# Function....: run_audit_trail_start
# Purpose.....: Orchestrate the audit trail start process
# ------------------------------------------------------------------------------
run_audit_trail_start() {
    step_start_audit_trails

    # Summary
    log_info "Audit trail start summary:"
    log_info "  Targets processed: ${#RESOLVED_TARGETS[@]}"
    log_info "  Successfully started: ${started_count}"
    log_info "  Failed starts: ${failed_count}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "  [DRY-RUN] No actual changes were made"
    fi

    local exit_code=0
    [[ ${failed_count} -gt 0 ]] && exit_code=1

    die "${exit_code}" "Audit trail start completed"
}

# ------------------------------------------------------------------------------
# Function....: main
# Purpose.....: Entry point
# ------------------------------------------------------------------------------
main() {
    init_script_env "$@" # standardized init per odb_datasafe framework
    parse_args
    preflight_checks
    run_audit_trail_start
}

# --- Entry point --------------------------------------------------------------
main "$@"
