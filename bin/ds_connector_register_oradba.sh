#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_connector_register_oradba.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose....: Register Data Safe connector metadata in oradba_homes.conf
# Usage......: ds_connector_register_oradba.sh [OPTIONS]
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.10.2')"
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

# Default configuration
DATASAFE_ENV=""
CONNECTOR_INFO=""
DRY_RUN=false
SHOW_USAGE_ON_EMPTY_ARGS=true

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
  Register Oracle Data Safe connector metadata in OraDBA homes configuration.
  Updates the description field in oradba_homes.conf to include connector
  name or OCID for use with --datasafe-home parameter in ds_connector_update.sh.

  NOTE: This script ONLY updates oradba_homes.conf. It does not modify
        the DataSafe connector itself.

Required:
  --datasafe-home ENV       OraDBA environment name (e.g., dscon4)
  --connector INFO          Connector name or OCID to register

Options:
  Common Options:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -n, --dry-run           Show what would be changed without modifying files

Examples:
  # Register connector name
  ${SCRIPT_NAME} --datasafe-home dscon4 --connector ds-conn-ha4

  # Register connector OCID
  ${SCRIPT_NAME} --datasafe-home dscon4 --connector ocid1.datasafe...

  # Dry-run to preview changes
  ${SCRIPT_NAME} --datasafe-home dscon4 --connector ds-conn-ha4 --dry-run

Environment Variables:
  ORADBA_BASE               OraDBA installation directory (required)

Notes:
  - The script updates the description field in oradba_homes.conf
  - Format: (oci=connector_name_or_ocid)
  - A backup is created before modifications: oradba_homes.conf.bak
  - If connector metadata already exists, it will be replaced
  - The environment must exist in oradba_homes.conf before registration

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
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --datasafe-home)
                need_val "$1" "${2:-}"
                DATASAFE_ENV="$2"
                shift 2
                ;;
            --connector)
                need_val "$1" "${2:-}"
                CONNECTOR_INFO="$2"
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
# Purpose.: Validate required inputs
# Returns.: 0 on success, exits on error
# Output..: Info messages about validation
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    # Require parameters first so argument errors are reported before
    # environment checks in lightweight test environments.
    require_var DATASAFE_ENV
    require_var CONNECTOR_INFO

    # Check ORADBA_BASE is set
    if [[ -z "${ORADBA_BASE:-}" ]]; then
        log_error "ORADBA_BASE environment variable not set"
        log_error "This script requires OraDBA to be loaded"
        die "ORADBA_BASE not set"
    fi

    # Check config file exists
    local config_file="${ORADBA_BASE}/etc/oradba_homes.conf"
    if [[ ! -f "$config_file" ]]; then
        log_error "OraDBA config not found: $config_file"
        die "Configuration file not found"
    fi

    # Check environment exists in config
    if ! grep -q "^${DATASAFE_ENV}:" "$config_file"; then
        log_error "DataSafe environment '${DATASAFE_ENV}' not found in ${config_file}"
        die "Environment not found in configuration"
    fi

    # Verify it's a datasafe product
    local line
    line=$(grep "^${DATASAFE_ENV}:" "$config_file" | head -1)
    local env path product
    IFS=':' read -r env path product _ <<< "$line"

    if [[ "$product" != "datasafe" ]]; then
        log_error "Environment '${DATASAFE_ENV}' is not a DataSafe connector (product: ${product})"
        die "Invalid product type"
    fi

    log_info "Environment validated: ${DATASAFE_ENV}"
    log_info "Connector path: ${path}"
    log_info "Connector info to register: ${CONNECTOR_INFO}"
}

# ------------------------------------------------------------------------------
# Function: register_connector
# Purpose.: Register connector metadata in oradba_homes.conf
# Returns.: 0 on success, 1 on error
# Output..: Info messages about the update
# ------------------------------------------------------------------------------
register_connector() {
    local config_file="${ORADBA_BASE}/etc/oradba_homes.conf"
    local backup_file="${config_file}.bak"

    log_info "Updating oradba_homes.conf..."

    # Get current line
    local current_line
    current_line=$(grep "^${DATASAFE_ENV}:" "$config_file" | head -1)

    if [[ -z "$current_line" ]]; then
        log_error "Environment ${DATASAFE_ENV} not found (should have been caught in validation)"
        return 1
    fi

    # Parse current line
    local env path product position reserved desc version
    IFS=':' read -r env path product position reserved desc version <<< "$current_line"

    # Remove existing (oci=...) pattern if present
    desc=$(echo "$desc" | sed -E 's/\(oci=[^)]+\)//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Add new connector metadata
    local new_desc="${desc} (oci=${CONNECTOR_INFO})"
    new_desc=$(echo "$new_desc" | sed 's/^ *//;s/ *$//')

    # Build new line
    local new_line="${env}:${path}:${product}:${position}:${reserved}:${new_desc}:${version}"

    log_debug "Current line: ${current_line}"
    log_debug "New line:     ${new_line}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update line:"
        log_info "[DRY-RUN] FROM: ${current_line}"
        log_info "[DRY-RUN] TO:   ${new_line}"
        return 0
    fi

    # Create backup
    if ! cp "$config_file" "$backup_file"; then
        log_error "Failed to create backup: ${backup_file}"
        return 1
    fi
    log_debug "Created backup: ${backup_file}"

    # Update file
    if ! sed -i.tmp "s|^${DATASAFE_ENV}:.*|${new_line}|" "$config_file"; then
        log_error "Failed to update configuration file"
        log_error "Backup available at: ${backup_file}"
        return 1
    fi
    rm -f "${config_file}.tmp"

    log_info "Successfully updated ${config_file}"
    log_info "Backup created at: ${backup_file}"
    log_info "Registered connector metadata: (oci=${CONNECTOR_INFO})"

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Display banner
    log_info "OraDBA Data Safe Connector Registration (v${SCRIPT_VERSION})"
    log_info "================================================================"

    # Parse arguments
    parse_args "$@"

    # Validate inputs
    validate_inputs

    # Register connector
    if register_connector; then
        log_info ""
        log_info "Registration completed successfully!"
        log_info ""
        log_info "You can now use: ds_connector_update.sh --datasafe-home ${DATASAFE_ENV}"
        return 0
    else
        die "Registration failed"
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
