#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_connector_update.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Automate Oracle Data Safe On-Premises Connector updates
# Usage......: ds_connector_update.sh [OPTIONS]
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP (must be before version check)
# =============================================================================

# Locate script and library directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Script metadata (version read from .extension file)
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '0.6.1')"
readonly SCRIPT_VERSION

# Load framework libraries
if [[ ! -f "${LIB_DIR}/ds_lib.sh" ]]; then
    echo "[ERROR] Cannot find ds_lib.sh in ${LIB_DIR}" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh"

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

# Default configuration (can be overridden by config files and CLI)
: "${COMPARTMENT:=}"              # Compartment name or OCID for connector lookup
: "${CONNECTOR_NAME:=}"           # Connector name or OCID
: "${CONNECTOR_HOME:=}"           # Connector installation directory
: "${DRY_RUN:=false}"             # Dry-run mode (set by --dry-run flag)
: "${SKIP_DOWNLOAD:=false}"       # Skip download step (bundle already downloaded)
: "${BUNDLE_FILE:=}"              # Path to existing bundle file (if skip-download)
: "${FORCE_NEW_PASSWORD:=false}"  # Force generation of new password

# Runtime variables (populated during execution)
COMP_NAME=""           # Resolved compartment name
COMP_OCID=""           # Resolved compartment OCID
CONNECTOR_OCID=""      # Resolved connector OCID
CONNECTOR_DISP_NAME="" # Resolved connector display name
PASSWORD_FILE=""       # Path to password file (base64 encoded)
BUNDLE_PASSWORD=""     # Generated or loaded bundle password
TEMP_DIR=""            # Temporary directory for downloads

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Returns.: Exits with code 0
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Automate Oracle Data Safe On-Premises Connector updates by:
    1. Generating a bundle password (or reusing existing)
    2. Downloading the connector installation bundle from OCI Data Safe
    3. Extracting the bundle in the connector directory
    4. Running setup.py update with the bundle password

Options:
  Common Options:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output (DEBUG level)
    -d, --debug             Enable debug output (TRACE level)
    -q, --quiet             Quiet mode (WARN level only)
    -n, --dry-run           Dry-run mode (show what would be done)
    --log-file FILE         Log to file
    --no-color              Disable colored output

  OCI Options:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE})

  Connector Options:
    -c, --compartment ID    Compartment OCID or name (for connector lookup)
    --connector NAME        Connector name or OCID
    --connector-home PATH   Connector installation directory
    --force-new-password    Generate new password (ignore existing)

  Bundle Options:
    --skip-download         Skip download (use existing bundle file)
    --bundle-file PATH      Path to existing bundle zip file

Examples:
  # Update connector by name (auto-detect home directory)
  ${SCRIPT_NAME} --connector my-connector -c MyCompartment

  # Update with specific home directory
  ${SCRIPT_NAME} --connector my-connector --connector-home /u01/app/oracle/product/datasafe

  # Dry-run to see what would be done
  ${SCRIPT_NAME} --connector my-connector -c MyCompartment --dry-run

  # Use existing bundle file (skip download)
  ${SCRIPT_NAME} --connector my-connector --skip-download --bundle-file /tmp/bundle.zip

  # Force new password generation
  ${SCRIPT_NAME} --connector my-connector --force-new-password

Environment:
  OCI_CLI_PROFILE         Default OCI profile
  OCI_CLI_REGION          Default OCI region
  DS_CONNECTOR_COMP       Default connector compartment OCID

Config Files (loaded in order):
  1. ${SCRIPT_DIR}/../.env
  2. ${SCRIPT_DIR}/../etc/datasafe.conf
  3. ${SCRIPT_DIR}/../etc/\${SCRIPT_NAME}.conf (if exists)

Notes:
  - During update, the connector cannot connect to target databases
  - Connection resumes after update completes
  - Bundle password is stored as base64 in etc/<connector-name>_pwd.b64
  - Existing password file is reused unless --force-new-password is specified
  - The script must be run as the connector owner (typically oracle user)

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
    # First, parse common options (sets ARGS with remaining args)
    parse_common_opts "$@"

    # Now parse script-specific options from ARGS
    local -a remaining=()
    set -- "${ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            --connector)
                need_val "$1" "${2:-}"
                CONNECTOR_NAME="$2"
                shift 2
                ;;
            --connector-home)
                need_val "$1" "${2:-}"
                CONNECTOR_HOME="$2"
                shift 2
                ;;
            --skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --bundle-file)
                need_val "$1" "${2:-}"
                BUNDLE_FILE="$2"
                shift 2
                ;;
            --force-new-password)
                FORCE_NEW_PASSWORD=true
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
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                # Positional argument
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Handle positional arguments if any
    if [[ ${#remaining[@]} -gt 0 ]]; then
        log_warn "Ignoring positional arguments: ${remaining[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and resolve connector/compartment
# Returns.: 0 on success, exits on error
# Output..: Info messages about resolved resources
# Notes...: Sets COMP_NAME, COMP_OCID, CONNECTOR_OCID, CONNECTOR_DISP_NAME
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    # Check required commands
    require_oci_cli
    require_cmd unzip python3

    # Require connector name
    require_var CONNECTOR_NAME

    # Resolve compartment for connector lookup
    if [[ -n "$COMPARTMENT" ]]; then
        local comp_name comp_ocid
        resolve_compartment_to_vars "$COMPARTMENT" comp_name comp_ocid || \
            die "Failed to resolve compartment: $COMPARTMENT"
        COMP_NAME="$comp_name"
        COMP_OCID="$comp_ocid"
        log_info "Compartment: ${COMP_NAME} (${COMP_OCID})"
    elif [[ -n "${DS_CONNECTOR_COMP:-}" ]]; then
        # Use DS_CONNECTOR_COMP as fallback
        local comp_ocid
        comp_ocid=$(get_connector_compartment_ocid) || \
            die "Failed to resolve DS_CONNECTOR_COMP"
        COMP_OCID="$comp_ocid"
        COMP_NAME="${DS_CONNECTOR_COMP}"
        log_info "Using DS_CONNECTOR_COMP: ${COMP_NAME}"
    else
        die "Compartment required. Use -c/--compartment or set DS_CONNECTOR_COMP"
    fi

    # Resolve connector (name or OCID)
    if is_ocid "$CONNECTOR_NAME"; then
        CONNECTOR_OCID="$CONNECTOR_NAME"
        CONNECTOR_DISP_NAME=$(ds_resolve_connector_name "$CONNECTOR_OCID" 2>/dev/null) || \
            CONNECTOR_DISP_NAME="$CONNECTOR_OCID"
        log_info "Connector: ${CONNECTOR_DISP_NAME} (${CONNECTOR_OCID})"
    else
        CONNECTOR_DISP_NAME="$CONNECTOR_NAME"
        CONNECTOR_OCID=$(ds_resolve_connector_ocid "$CONNECTOR_NAME" "$COMP_OCID") || \
            die "Failed to resolve connector: $CONNECTOR_NAME"
        log_info "Connector: ${CONNECTOR_DISP_NAME} (${CONNECTOR_OCID})"
    fi

    # Validate connector home directory (auto-detect if not provided)
    if [[ -z "$CONNECTOR_HOME" ]]; then
        # Try to auto-detect from common locations
        local base_dir="${ORACLE_BASE:-/u01/app/oracle}/product"
        local potential_home="${base_dir}/${CONNECTOR_DISP_NAME}"
        
        if [[ -d "$potential_home" ]]; then
            CONNECTOR_HOME="$potential_home"
            log_info "Auto-detected connector home: ${CONNECTOR_HOME}"
        else
            die "Connector home directory not found. Use --connector-home to specify."
        fi
    fi

    # Validate connector home
    if [[ ! -d "$CONNECTOR_HOME" ]]; then
        die "Connector home directory not found: $CONNECTOR_HOME"
    fi

    # Check for setup.py
    if [[ ! -f "${CONNECTOR_HOME}/setup.py" ]]; then
        die "setup.py not found in connector home: ${CONNECTOR_HOME}"
    fi

    # Validate bundle file if skip-download is enabled
    if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
        if [[ -z "$BUNDLE_FILE" ]]; then
            die "Bundle file path required when --skip-download is used"
        fi
        if [[ ! -f "$BUNDLE_FILE" ]]; then
            die "Bundle file not found: $BUNDLE_FILE"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: generate_password
# Purpose.: Generate a random password for the bundle
# Returns.: Password on stdout
# Output..: Random 20-character password
# ------------------------------------------------------------------------------
generate_password() {
    # Generate a secure random password (20 characters, alphanumeric)
    openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20
}

# ------------------------------------------------------------------------------
# Function: get_or_create_password
# Purpose.: Get existing password or create new one
# Returns.: 0 on success, sets BUNDLE_PASSWORD and PASSWORD_FILE
# Output..: Info messages about password handling
# ------------------------------------------------------------------------------
get_or_create_password() {
    local etc_dir="${SCRIPT_DIR}/../etc"
    local pwd_file="${etc_dir}/${CONNECTOR_DISP_NAME}_pwd.b64"
    
    PASSWORD_FILE="$pwd_file"
    
    # Check if password file exists and we should reuse it
    if [[ -f "$pwd_file" && "$FORCE_NEW_PASSWORD" != "true" ]]; then
        log_info "Found existing password file: ${pwd_file}"
        
        # Decode password from base64
        if BUNDLE_PASSWORD=$(base64 -d < "$pwd_file" 2>/dev/null); then
            if [[ -n "$BUNDLE_PASSWORD" ]]; then
                log_info "Reusing existing bundle password"
                return 0
            fi
        fi
        
        log_warn "Failed to decode existing password file, generating new password"
    fi
    
    # Generate new password
    log_info "Generating new bundle password..."
    BUNDLE_PASSWORD=$(generate_password)
    
    if [[ -z "$BUNDLE_PASSWORD" ]]; then
        die "Failed to generate password"
    fi
    
    # Save password as base64
    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "$etc_dir"
        echo -n "$BUNDLE_PASSWORD" | base64 > "$pwd_file"
        chmod 600 "$pwd_file"
        log_info "Password saved to: ${pwd_file}"
    else
        log_info "[DRY-RUN] Would save password to: ${pwd_file}"
    fi
}

# ------------------------------------------------------------------------------
# Function: download_bundle
# Purpose.: Download connector installation bundle from OCI
# Returns.: 0 on success, 1 on error
# Output..: Info messages about download progress
# ------------------------------------------------------------------------------
download_bundle() {
    log_info "Downloading connector installation bundle..."
    
    # Create temporary directory for bundle
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/datasafe_update.XXXXXX")
    local bundle_file="${TEMP_DIR}/connector_bundle.zip"
    
    # Step 1: Generate bundle configuration
    log_info "Step 1/3: Generating bundle configuration..."
    local work_request_json
    work_request_json=$(ds_generate_connector_bundle "$CONNECTOR_OCID" "$BUNDLE_PASSWORD") || {
        die "Failed to generate connector bundle"
    }
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for bundle generation to complete"
        log_info "[DRY-RUN] Would download bundle to: ${bundle_file}"
        BUNDLE_FILE="$bundle_file"
        return 0
    fi
    
    # Extract work request ID
    local work_request_id
    work_request_id=$(echo "$work_request_json" | jq -r '."opc-work-request-id" // .data.id // empty')
    
    if [[ -n "$work_request_id" ]]; then
        log_info "Work request ID: ${work_request_id}"
        log_info "Waiting for bundle generation to complete (this may take a minute)..."
        
        # Wait for work request to complete (poll every 10 seconds, max 5 minutes)
        local max_wait=300
        local elapsed=0
        local status=""
        
        while [[ $elapsed -lt $max_wait ]]; do
            status=$(oci data-safe work-request get --work-request-id "$work_request_id" \
                --query 'data.status' --raw-output 2>/dev/null || echo "UNKNOWN")
            
            case "$status" in
                SUCCEEDED)
                    log_info "Bundle generation completed successfully"
                    break
                    ;;
                FAILED)
                    die "Bundle generation failed"
                    ;;
                IN_PROGRESS|ACCEPTED)
                    sleep 10
                    elapsed=$((elapsed + 10))
                    ;;
                *)
                    log_warn "Unknown work request status: $status"
                    sleep 10
                    elapsed=$((elapsed + 10))
                    ;;
            esac
        done
        
        if [[ "$status" != "SUCCEEDED" ]]; then
            die "Bundle generation timed out or failed"
        fi
    else
        log_info "Bundle generation initiated (no work request ID returned)"
        log_info "Waiting 30 seconds for bundle to be ready..."
        sleep 30
    fi
    
    # Step 2: Download the bundle
    log_info "Step 2/3: Downloading bundle..."
    ds_download_connector_bundle "$CONNECTOR_OCID" "$bundle_file" || {
        die "Failed to download connector bundle"
    }
    
    log_info "Bundle downloaded to: ${bundle_file}"
    BUNDLE_FILE="$bundle_file"
}

# ------------------------------------------------------------------------------
# Function: extract_bundle
# Purpose.: Extract bundle in connector home directory
# Returns.: 0 on success, 1 on error
# Output..: Info messages about extraction progress
# ------------------------------------------------------------------------------
extract_bundle() {
    log_info "Extracting bundle in connector home: ${CONNECTOR_HOME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would extract bundle: ${BUNDLE_FILE}"
        log_info "[DRY-RUN] Target directory: ${CONNECTOR_HOME}"
        return 0
    fi
    
    # Extract bundle (overwrite existing files)
    if ! unzip -o "$BUNDLE_FILE" -d "$CONNECTOR_HOME"; then
        die "Failed to extract bundle"
    fi
    
    log_info "Bundle extracted successfully"
}

# ------------------------------------------------------------------------------
# Function: run_setup_update
# Purpose.: Run setup.py update with bundle password
# Returns.: 0 on success, 1 on error
# Output..: Setup script output
# ------------------------------------------------------------------------------
run_setup_update() {
    log_info "Running setup.py update..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: python3 setup.py update"
        log_info "[DRY-RUN] Working directory: ${CONNECTOR_HOME}"
        log_info "[DRY-RUN] Would provide bundle password via stdin"
        return 0
    fi
    
    # Run setup.py update in connector home directory
    # Pass password via stdin
    local setup_py="${CONNECTOR_HOME}/setup.py"
    
    log_info "Executing: python3 setup.py update"
    log_info "Working directory: ${CONNECTOR_HOME}"
    
    # Run setup.py and provide password when prompted
    (
        cd "$CONNECTOR_HOME" || die "Failed to change directory to ${CONNECTOR_HOME}"
        echo "$BUNDLE_PASSWORD" | python3 "$setup_py" update
    )
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "Connector update completed successfully"
    else
        die "Connector update failed with exit code: $exit_code"
    fi
}

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Cleanup function called on exit
# Returns.: 0
# Output..: Debug message
# Notes...: Override the default cleanup from common.sh if needed
# ------------------------------------------------------------------------------
cleanup() {
    # Clean up temporary directory
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "$TEMP_DIR"
    fi
    
    log_debug "Cleanup completed"
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrate the update process
# Returns.: 0 on success, exits on error
# Output..: Work progress and results
# ------------------------------------------------------------------------------
do_work() {
    log_info "Starting Oracle Data Safe connector update..."
    
    # Show dry-run message if applicable
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY-RUN MODE: No changes will be made"
    fi
    
    # Step 1: Get or create bundle password
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Step 1: Password Management"
    log_info "═══════════════════════════════════════════════════════════════════"
    get_or_create_password
    
    # Step 2: Download bundle (unless skipped)
    if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════════"
        log_info "Step 2: Download Bundle"
        log_info "═══════════════════════════════════════════════════════════════════"
        download_bundle
    else
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════════"
        log_info "Step 2: Download Bundle (SKIPPED)"
        log_info "═══════════════════════════════════════════════════════════════════"
        log_info "Using existing bundle: ${BUNDLE_FILE}"
    fi
    
    # Step 3: Extract bundle
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Step 3: Extract Bundle"
    log_info "═══════════════════════════════════════════════════════════════════"
    extract_bundle
    
    # Step 4: Run setup.py update
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Step 4: Run setup.py update"
    log_info "═══════════════════════════════════════════════════════════════════"
    run_setup_update
    
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Update completed successfully!"
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Connector: ${CONNECTOR_DISP_NAME}"
    log_info "Home: ${CONNECTOR_HOME}"
    log_info "Password file: ${PASSWORD_FILE}"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info ""
        log_info "Next steps:"
        log_info "  1. Verify connector service is running"
        log_info "  2. Check connector logs for any issues"
        log_info "  3. Test database connections"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, 1 on error
# Output..: Execution status and results
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Initialize configuration cascade
    init_config "${SCRIPT_NAME}.conf"

    # Parse arguments
    parse_args "$@"

    # Validate inputs
    validate_inputs

    # Do the work
    do_work

    log_info "${SCRIPT_NAME} completed successfully"
}

# Run main function
main "$@"
