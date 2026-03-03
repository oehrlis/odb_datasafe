#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_connector_create.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.03
# Version....: v0.18.1
# Purpose....: Create a new Oracle Data Safe On-Premises Connector:
#              1. Create the connector object in OCI Data Safe
#              2. Generate a bundle key and download the installation bundle
#              3. Create the local connector home directory
#              4. Extract the bundle
#              5. Run setup.py install with the bundle key
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.18.0')"
readonly SCRIPT_VERSION

if [[ ! -f "${LIB_DIR}/ds_lib.sh" ]]; then
    echo "[ERROR] Cannot find ds_lib.sh in ${LIB_DIR}" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

: "${COMPARTMENT:=}"               # Compartment name or OCID (required)
: "${DISPLAY_NAME:=}"              # Connector display name in OCI (required)
: "${DESCRIPTION:=}"               # Optional free-text description
: "${CONNECTOR_HOME:=}"            # Local installation directory (required)
: "${FORCE_NEW_BUNDLE_KEY:=false}" # Always generate a fresh bundle key
: "${WAIT_STATE:=ACTIVE}"          # Poll until connector reaches this state (empty = async)
: "${DRY_RUN:=false}"              # Show what would be done without making changes
: "${HA_NODE:=false}"              # Second-node HA install: skip OCI create, reuse existing connector
: "${CONNECTOR_PORT:=1521}"       # Port the connector service listens on (setup.py install --connector-port)
# shellcheck disable=SC2034
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime variables
COMP_NAME=""
COMP_OCID=""
CONNECTOR_OCID=""
BUNDLE_KEY=""
BUNDLE_KEY_FILE=""
TEMP_DIR=""

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Returns.: Exits with code 0
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Create a new Oracle Data Safe On-Premises Connector end-to-end:
    1. Create the connector object in OCI Data Safe
    2. Generate a bundle key and download the installation bundle
    3. Create the local connector home directory
    4. Extract the bundle
    5. Run setup.py install with the bundle key

REQUIRED:
  -c, --compartment ID        Compartment OCID or name for the connector
  -N, --display-name NAME     Connector display name in OCI Data Safe
      --connector-home PATH   Local installation directory (must not exist yet)

Options:
  Common:
    -h, --help                Show this help message
    -V, --version             Show version
    -v, --verbose             Verbose output (default for this script)
    -d, --debug               Debug output
    -q, --quiet               Quiet mode
    -n, --dry-run             Show what would be done without making changes
        --log-file FILE       Log to file

  OCI:
        --oci-profile PROFILE OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION   OCI region
        --oci-config FILE     OCI config file

  Connector:
        --description DESC    Free-text description for the OCI connector object
        --connector-port PORT Port the connector service listens on
                              (default: ${CONNECTOR_PORT}; passed as
                              --connector-port to setup.py install)
        --force-new-bundle-key
                              Always generate a fresh bundle key (never reuse)
        --wait-state STATE    Wait for connector to reach STATE after create
                              (default: ACTIVE; empty string = return immediately)
        --ha-node             Second-node HA install: look up the existing OCI
                              connector by display name (skip OCI create), reuse
                              the bundle key from etc/<name>_pwd.b64, and run
                              all local installation steps. The bundle key file
                              must already be present (shared etc/ or copied
                              from the first node).

  Registration (optional post-install steps):
        --register-oradba ENV Register the new connector in oradba_homes.conf
                              under the given OraDBA environment name. Requires
                              ORADBA_BASE to be set.
        --install-service     Install a systemd service for the connector.
                              Delegates to install_datasafe_service.sh (requires root).

Config:
  DS_ROOT_COMP / DS_CONNECTOR_COMP   Default compartment (name or OCID)

Examples:
  # Create connector with dry-run (shows plan)
  ${SCRIPT_NAME} -c my-compartment -N my-connector --connector-home /u01/datasafe/my-connector --dry-run

  # Create and wait until ACTIVE
  ${SCRIPT_NAME} -c my-compartment -N my-connector --connector-home /u01/datasafe/my-connector

  # Create without waiting (async)
  ${SCRIPT_NAME} -c my-compartment -N my-connector --connector-home /u01/datasafe/my-connector \\
      --wait-state ""

  # Create with all post-install steps
  ${SCRIPT_NAME} -c my-compartment -N my-connector --connector-home /u01/datasafe/my-connector \\
      --register-oradba dscon5 --install-service

  # HA: install on second node (connector already in OCI, key in shared etc/)
  ${SCRIPT_NAME} -c my-compartment -N my-connector --connector-home /u01/datasafe/my-connector \\
      --ha-node --install-service

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on invalid args
# Output..: None (sets global variables)
# ------------------------------------------------------------------------------
parse_args() {
    local has_explicit_log_flag="false"
    local arg
    for arg in "$@"; do
        case "$arg" in
            -v | --verbose | -d | --debug | -q | --quiet)
                has_explicit_log_flag="true"
                break
                ;;
        esac
    done

    parse_common_opts "$@"

    if [[ "$has_explicit_log_flag" == "false" ]]; then
        # shellcheck disable=SC2034
        LOG_LEVEL=INFO
    fi

    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -N | --display-name)
                need_val "$1" "${2:-}"
                DISPLAY_NAME="$2"
                shift 2
                ;;
            --connector-home)
                need_val "$1" "${2:-}"
                CONNECTOR_HOME="$2"
                shift 2
                ;;
            --description)
                need_val "$1" "${2:-}"
                DESCRIPTION="$2"
                shift 2
                ;;
            --connector-port)
                need_val "$1" "${2:-}"
                CONNECTOR_PORT="$2"
                shift 2
                ;;
            --force-new-bundle-key)
                FORCE_NEW_BUNDLE_KEY=true
                shift
                ;;
            --wait-state)
                need_val "$1" "${2:-}"
                WAIT_STATE="${2^^}"
                shift 2
                ;;
            --register-oradba)
                need_val "$1" "${2:-}"
                REGISTER_ORADBA_ENV="$2"
                shift 2
                ;;
            --install-service)
                INSTALL_SERVICE=true
                shift
                ;;
            --ha-node)
                HA_NODE=true
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
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#remaining[@]} -gt 0 ]]; then
        log_warn "Ignoring positional arguments: ${remaining[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs, resolve compartment, safety-check
# Returns.: 0 on success, exits on error
# Notes...: Sets COMP_NAME, COMP_OCID
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli
    require_cmd openssl unzip python3

    # Compartment
    local comp_ref="${COMPARTMENT:-${DS_ROOT_COMP:-${DS_CONNECTOR_COMP:-}}}"
    if [[ -z "$comp_ref" ]]; then
        die "Compartment required. Use -c/--compartment or set DS_ROOT_COMP in datasafe.conf"
    fi
    resolve_compartment_to_vars "$comp_ref" "COMP" \
        || die "Failed to resolve compartment: $comp_ref"
    log_info "Compartment: ${COMP_NAME} (${COMP_OCID})"

    # Display name
    [[ -z "$DISPLAY_NAME" ]] && die "Connector display name required. Use -N/--display-name"

    # Connector home — must be provided and must NOT already exist
    [[ -z "$CONNECTOR_HOME" ]] && die "Connector home directory required. Use --connector-home PATH"
    if [[ -e "$CONNECTOR_HOME" ]]; then
        die "Connector home already exists: ${CONNECTOR_HOME}. Choose a different path or remove it first."
    fi

    if [[ "${HA_NODE}" == "true" ]]; then
        # HA mode: connector must already exist in OCI — look up its OCID
        [[ "${FORCE_NEW_BUNDLE_KEY}" == "true" ]] \
            && die "--force-new-bundle-key cannot be used with --ha-node (would mismatch the deployed connector)"
        log_debug "HA mode: looking up existing connector '${DISPLAY_NAME}' in OCI..."
        local found
        found=$(oci_exec_ro data-safe on-prem-connector list \
            --compartment-id "$COMP_OCID" \
            --all 2> /dev/null \
            | jq -r ".data[]? | select(.\"display-name\" == \"${DISPLAY_NAME}\") | .id" \
            | head -1 || true)
        if [[ -z "$found" ]]; then
            die "HA mode: connector '${DISPLAY_NAME}' not found in compartment ${COMP_NAME}. Run without --ha-node on the first node first."
        fi
        CONNECTOR_OCID="$found"
        log_info "HA mode: found existing connector ${CONNECTOR_OCID}"
    else
        # Normal mode: connector must NOT exist yet
        log_debug "Checking if connector '${DISPLAY_NAME}' already exists in OCI..."
        local existing
        existing=$(oci_exec_ro data-safe on-prem-connector list \
            --compartment-id "$COMP_OCID" \
            --all 2> /dev/null \
            | jq -r ".data[]? | select(.\"display-name\" == \"${DISPLAY_NAME}\") | .id" \
            | head -1 || true)
        if [[ -n "$existing" ]]; then
            die "A connector named '${DISPLAY_NAME}' already exists in compartment ${COMP_NAME}: ${existing}. Use --ha-node to install on an additional node."
        fi
    fi

    log_info "Inputs validated."
}

# ------------------------------------------------------------------------------
# Function: show_plan
# Purpose.: Display the creation plan before executing
# Returns.: 0
# Output..: Plan details to log
# ------------------------------------------------------------------------------
show_plan() {
    if [[ "${HA_NODE}" == "true" ]]; then
        log_info "Connector HA Node Install Plan:"
        log_info "  Mode:            HA (second node — OCI create skipped)"
        log_info "  Connector OCID:  ${CONNECTOR_OCID}"
    else
        log_info "Connector Creation Plan:"
    fi
    log_info "  Display name:    ${DISPLAY_NAME}"
    log_info "  Compartment:     ${COMP_NAME} (${COMP_OCID})"
    log_info "  Connector home:  ${CONNECTOR_HOME}"
    log_info "  Connector port:  ${CONNECTOR_PORT}"
    if [[ -n "$DESCRIPTION" && "${HA_NODE}" != "true" ]]; then
        log_info "  Description:     ${DESCRIPTION}"
    fi
    if [[ -n "${WAIT_STATE:-}" ]]; then
        log_info "  Wait state:      ${WAIT_STATE}"
    else
        log_info "  Wait state:      (async — return immediately)"
    fi
    if [[ -n "${REGISTER_ORADBA_ENV:-}" ]]; then
        log_info "  OraDBA env:      ${REGISTER_ORADBA_ENV}"
    fi
    if [[ "${INSTALL_SERVICE:-false}" == "true" ]]; then
        log_info "  systemd service: yes"
    fi
}

# ------------------------------------------------------------------------------
# Function: get_or_create_bundle_key
# Purpose.: Get existing bundle key from etc/ or generate a new one
# Returns.: 0 on success; sets BUNDLE_KEY and BUNDLE_KEY_FILE
# ------------------------------------------------------------------------------
get_or_create_bundle_key() {
    local etc_dir="${SCRIPT_DIR}/../etc"
    local pwd_file="${etc_dir}/${DISPLAY_NAME}_pwd.b64"

    BUNDLE_KEY_FILE="$pwd_file"

    if [[ "${HA_NODE}" == "true" ]]; then
        # HA mode: key must already exist — the same key used on node 1 is required
        if [[ ! -f "$pwd_file" ]]; then
            die "HA mode: bundle key file not found: ${pwd_file}. Copy etc/${DISPLAY_NAME}_pwd.b64 from the first node (or from the shared etc/ directory) before running --ha-node."
        fi
        if BUNDLE_KEY=$(base64 -d < "$pwd_file" 2> /dev/null) \
            && [[ -n "$BUNDLE_KEY" ]] \
            && is_valid_bundle_key "$BUNDLE_KEY"; then
            log_info "HA mode: using existing bundle key from: ${pwd_file}"
            return 0
        fi
        die "HA mode: bundle key file exists but is invalid or unreadable: ${pwd_file}"
    fi

    if [[ -f "$pwd_file" && "$FORCE_NEW_BUNDLE_KEY" != "true" ]]; then
        log_info "Found existing key file: ${pwd_file}"
        if BUNDLE_KEY=$(base64 -d < "$pwd_file" 2> /dev/null) \
            && [[ -n "$BUNDLE_KEY" ]] \
            && is_valid_bundle_key "$BUNDLE_KEY"; then
            log_info "Reusing existing bundle key"
            return 0
        fi
        log_warn "Existing key invalid or unreadable — generating new key"
    fi

    log_info "Generating new bundle key..."
    BUNDLE_KEY=$(generate_bundle_key)
    [[ -z "$BUNDLE_KEY" ]] && die "Failed to generate bundle key"

    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "$etc_dir"
        printf '%s' "$BUNDLE_KEY" | base64 > "$pwd_file"
        chmod 600 "$pwd_file"
        log_info "Bundle key saved to: ${pwd_file}"
    else
        log_info "[DRY-RUN] Would save bundle key to: ${pwd_file}"
    fi
}

# ------------------------------------------------------------------------------
# Function: download_bundle
# Purpose.: Download the installation bundle from OCI Data Safe
# Args....: None (uses CONNECTOR_OCID, BUNDLE_KEY)
# Returns.: 0 on success; sets BUNDLE_FILE
# ------------------------------------------------------------------------------
download_bundle() {
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/datasafe_create.XXXXXX")
    local bundle_file="${TEMP_DIR}/connector_bundle.zip"

    log_info "Downloading connector installation bundle..."
    ds_generate_connector_bundle "$CONNECTOR_OCID" "$BUNDLE_KEY" "$bundle_file" \
        || die "Failed to download connector bundle"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would download bundle to: ${bundle_file}"
    else
        log_info "Bundle downloaded to: ${bundle_file}"
    fi
    BUNDLE_FILE="$bundle_file"
}

# ------------------------------------------------------------------------------
# Function: create_connector_home
# Purpose.: Create the local connector home directory
# Returns.: 0 on success
# ------------------------------------------------------------------------------
create_connector_home() {
    log_info "Creating connector home: ${CONNECTOR_HOME}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create directory: ${CONNECTOR_HOME}"
        return 0
    fi
    mkdir -p "$CONNECTOR_HOME" || die "Failed to create connector home: ${CONNECTOR_HOME}"
    log_info "Directory created: ${CONNECTOR_HOME}"
}

# ------------------------------------------------------------------------------
# Function: extract_bundle
# Purpose.: Extract the connector bundle into the connector home directory
# Returns.: 0 on success
# ------------------------------------------------------------------------------
extract_bundle() {
    log_info "Extracting bundle into: ${CONNECTOR_HOME}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would extract: ${BUNDLE_FILE} → ${CONNECTOR_HOME}"
        return 0
    fi
    unzip -o "$BUNDLE_FILE" -d "$CONNECTOR_HOME" \
        || die "Failed to extract connector bundle"
    log_info "Bundle extracted successfully"
}

# ------------------------------------------------------------------------------
# Function: run_setup_install
# Purpose.: Run setup.py install with the bundle key (non-interactive)
# Returns.: 0 on success
# Notes...: Overrides getpass.getpass to inject BUNDLE_KEY without a tty prompt.
# ------------------------------------------------------------------------------
run_setup_install() {
    local setup_py="${CONNECTOR_HOME}/setup.py"

    if [[ ! -f "$setup_py" ]]; then
        die "setup.py not found after bundle extraction: ${setup_py}"
    fi

    log_info "Running setup.py install..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: python3 setup.py install --connector-port ${CONNECTOR_PORT}"
        log_info "[DRY-RUN] Working directory: ${CONNECTOR_HOME}"
        return 0
    fi

    (
        cd "$CONNECTOR_HOME" || die "Failed to change to directory: ${CONNECTOR_HOME}"
        BUNDLE_KEY_INPUT="$BUNDLE_KEY" \
        CONNECTOR_PORT_INPUT="$CONNECTOR_PORT" \
        python3 - "$setup_py" << 'PY'
import os
import runpy
import sys
import getpass

setup_path = sys.argv[1]
bundle_key = os.environ.get("BUNDLE_KEY_INPUT", "")
connector_port = os.environ.get("CONNECTOR_PORT_INPUT", "1521")

def _bundle_key_prompt(prompt='Enter install bundle key:', stream=None):
    return bundle_key

getpass.getpass = _bundle_key_prompt
sys.argv = [setup_path, 'install', '--connector-port', connector_port]
runpy.run_path(setup_path, run_name='__main__')
PY
    ) || die "setup.py install failed"

    log_info "Connector installation completed"
}

# ------------------------------------------------------------------------------
# Function: wait_for_connector_not_creating
# Purpose.: Poll OCI until the connector leaves the CREATING state.
#           The bundle download API (generate-on-prem-connector-configuration)
#           returns 404 while the connector is still CREATING. This function
#           must be called after ds_create_connector() and before download_bundle().
# Returns.: 0 when connector has left CREATING; warns and returns 0 on timeout.
# ------------------------------------------------------------------------------
wait_for_connector_not_creating() {
    local elapsed=0
    local poll_interval=10
    local max_wait=120 # 2 minutes

    log_info "Waiting for connector to become available (leave CREATING state)..."

    while [[ $elapsed -lt $max_wait ]]; do
        local state
        state=$(oci_exec_ro data-safe on-prem-connector get \
            --on-prem-connector-id "$CONNECTOR_OCID" \
            --query 'data."lifecycle-state"' \
            --raw-output 2> /dev/null || true)

        if [[ "$state" != "CREATING" && -n "$state" ]]; then
            log_info "Connector available (state: ${state})"
            return 0
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        log_info "Connector initializing (state: ${state:-CREATING}, ${elapsed}/${max_wait}s)..."
    done

    log_warn "Connector still CREATING after ${max_wait}s — proceeding with bundle download"
}

# ------------------------------------------------------------------------------
# Function: wait_for_connector_active
# Purpose.: Poll OCI until connector reaches WAIT_STATE
# Args....: None (uses CONNECTOR_OCID, WAIT_STATE)
# Returns.: 0 on success, exits on timeout or FAILED state
# ------------------------------------------------------------------------------
wait_for_connector_active() {
    [[ -z "${WAIT_STATE:-}" ]] && return 0

    log_info "Waiting for connector to reach ${WAIT_STATE}..."

    local elapsed=0
    local poll_interval=15
    local max_wait=300 # 5 minutes

    while [[ $elapsed -lt $max_wait ]]; do
        local state
        state=$(oci_exec_ro data-safe on-prem-connector get \
            --on-prem-connector-id "$CONNECTOR_OCID" \
            --query 'data."lifecycle-state"' \
            --raw-output 2> /dev/null || true)

        if [[ "$state" == "$WAIT_STATE" ]]; then
            log_info "Connector reached ${WAIT_STATE}: ${DISPLAY_NAME}"
            return 0
        fi

        if [[ "$state" == "FAILED" ]]; then
            die "Connector creation failed (FAILED state): ${DISPLAY_NAME} (${CONNECTOR_OCID})"
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        log_info "Waiting for ${WAIT_STATE}... current: ${state:-unknown} (${elapsed}/${max_wait}s)"
    done

    log_warn "Connector did not reach ${WAIT_STATE} within ${max_wait}s"
    log_warn "Check status: oci data-safe on-prem-connector get --on-prem-connector-id ${CONNECTOR_OCID}"
}

# ------------------------------------------------------------------------------
# Function: optional_register_oradba
# Purpose.: Register connector in oradba_homes.conf if --register-oradba given
# Returns.: 0
# ------------------------------------------------------------------------------
optional_register_oradba() {
    local env_name="${REGISTER_ORADBA_ENV:-}"
    [[ -z "$env_name" ]] && return 0

    local register_script="${SCRIPT_DIR}/ds_connector_register_oradba.sh"
    if [[ ! -x "$register_script" ]]; then
        log_warn "ds_connector_register_oradba.sh not found or not executable — skipping OraDBA registration"
        return 0
    fi

    log_info "Registering connector in oradba_homes.conf as: ${env_name}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ds_connector_register_oradba.sh --datasafe-home ${env_name} --connector ${DISPLAY_NAME} --connector-home ${CONNECTOR_HOME}"
        return 0
    fi

    "$register_script" \
        --datasafe-home "$env_name" \
        --connector "$CONNECTOR_OCID" \
        --connector-home "$CONNECTOR_HOME" \
        || log_warn "OraDBA registration failed (non-fatal)"
}

# ------------------------------------------------------------------------------
# Function: optional_install_service
# Purpose.: Install systemd service if --install-service given
# Returns.: 0
# ------------------------------------------------------------------------------
optional_install_service() {
    [[ "${INSTALL_SERVICE:-false}" != "true" ]] && return 0

    local install_script="${SCRIPT_DIR}/install_datasafe_service.sh"
    if [[ ! -x "$install_script" ]]; then
        log_warn "install_datasafe_service.sh not found or not executable — skipping service install"
        return 0
    fi

    log_info "Installing systemd service for: ${DISPLAY_NAME}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: sudo install_datasafe_service.sh --install -n ${DISPLAY_NAME}"
        return 0
    fi

    sudo "$install_script" --install -n "$DISPLAY_NAME" \
        || log_warn "Service installation failed (non-fatal) — run manually: sudo ${install_script} --install -n ${DISPLAY_NAME}"
}

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Remove temporary directory on exit
# Returns.: 0
# ------------------------------------------------------------------------------
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up: ${TEMP_DIR}"
        rm -rf "$TEMP_DIR"
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Orchestrate the connector creation steps
# Returns.: 0 on success, exits on error
# ------------------------------------------------------------------------------
do_work() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY-RUN MODE: No changes will be made"
    fi

    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 1/6: OCI Connector"
    log_info "══════════════════════════════════════════════════════════════"
    if [[ "${HA_NODE}" == "true" ]]; then
        log_info "HA mode: using existing connector (OCI create skipped)"
        log_info "Connector OCID: ${CONNECTOR_OCID}"
    else
        CONNECTOR_OCID=$(ds_create_connector "$COMP_OCID" "$DISPLAY_NAME" "$DESCRIPTION") \
            || die "Failed to create connector in OCI"
        log_info "Connector OCID: ${CONNECTOR_OCID}"
        # Wait for connector to leave CREATING before the bundle download API becomes available
        wait_for_connector_not_creating
    fi

    log_info ""
    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 2/6: Bundle Key"
    log_info "══════════════════════════════════════════════════════════════"
    get_or_create_bundle_key

    log_info ""
    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 3/6: Download Installation Bundle"
    log_info "══════════════════════════════════════════════════════════════"
    download_bundle

    log_info ""
    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 4/6: Create Connector Home & Extract Bundle"
    log_info "══════════════════════════════════════════════════════════════"
    create_connector_home
    extract_bundle

    log_info ""
    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 5/6: Install Connector (setup.py install)"
    log_info "══════════════════════════════════════════════════════════════"
    run_setup_install

    log_info ""
    log_info "══════════════════════════════════════════════════════════════"
    log_info "Step 6/6: Wait for OCI Activation & Post-Install"
    log_info "══════════════════════════════════════════════════════════════"
    wait_for_connector_active
    optional_register_oradba
    optional_install_service

    log_info ""
    if [[ "${HA_NODE}" == "true" ]]; then
        log_info "Connector '${DISPLAY_NAME}' installed on HA node successfully."
    else
        log_info "Connector '${DISPLAY_NAME}' created successfully."
    fi
    log_info "  OCID:  ${CONNECTOR_OCID}"
    log_info "  Home:  ${CONNECTOR_HOME}"
    if [[ -n "$BUNDLE_KEY_FILE" ]]; then
        log_info "  Key:   ${BUNDLE_KEY_FILE}"
    fi
    log_info ""
    log_info "Next steps:"
    log_info "  - Register targets:  ds_target_register.sh --connector ${DISPLAY_NAME} ..."
    log_info "  - Update connector:  ds_connector_update.sh --connector ${DISPLAY_NAME}"
    if [[ "${INSTALL_SERVICE:-false}" != "true" ]]; then
        log_info "  - Install service:   sudo install_datasafe_service.sh --install -n ${DISPLAY_NAME}"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    init_config
    local has_explicit_log_flag="false"
    local arg
    for arg in "$@"; do
        case "$arg" in
            -v | --verbose | -d | --debug | -q | --quiet)
                has_explicit_log_flag="true"
                break
                ;;
        esac
    done

    parse_common_opts "$@"
    if [[ "$has_explicit_log_flag" == "false" ]]; then
        # shellcheck disable=SC2034
        LOG_LEVEL=INFO
    fi
    parse_args "$@"

    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    setup_error_handling

    validate_inputs
    show_plan
    do_work

    log_info "Done"
}

main "$@"
