#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_connector_update.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.17
# Version....: v0.12.1
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
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.6.1')"
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
: "${COMPARTMENT:=}"             # Compartment name or OCID for connector lookup
: "${CONNECTOR_NAME:=}"          # Connector name or OCID
: "${CONNECTOR_HOME:=}"          # Connector installation directory
: "${DATASAFE_ENV:=}"            # OraDBA environment name (alternative to connector params)
: "${DRY_RUN:=false}"            # Dry-run mode (set by --dry-run flag)
: "${SKIP_DOWNLOAD:=false}"      # Skip download step (bundle already downloaded)
: "${BUNDLE_FILE:=}"             # Path to existing bundle file (if skip-download)
: "${FORCE_NEW_BUNDLE_KEY:=false}" # Force generation of new bundle key
: "${CHECK_ONLY:=false}"         # Run version check only and exit
: "${CHECK_ALL:=false}"          # Check all connectors from oradba_homes.conf

# Runtime variables (populated during execution)
COMP_NAME=""           # Resolved compartment name
COMP_OCID=""           # Resolved compartment OCID
CONNECTOR_OCID=""      # Resolved connector OCID
CONNECTOR_DISP_NAME="" # Resolved connector display name
BUNDLE_KEY_FILE=""     # Path to bundle key file (base64 encoded)
BUNDLE_KEY=""          # Generated or loaded bundle key
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
    1. Checking local and online connector versions
    2. Generating a bundle key (or reusing existing)
    3. Downloading the connector installation bundle from OCI Data Safe
    4. Extracting the bundle in the connector directory
    5. Running setup.py update with the bundle key

REQUIRED (choose one):
  Option 1: Use OraDBA environment (simplest)
    --datasafe-home ENV   OraDBA environment name (e.g., dscon4)
                          Automatically resolves connector home and metadata
                          from ${ORADBA_BASE}/etc/oradba_homes.conf

  Option 2: Specify connector manually
    --connector NAME      Connector name or OCID
    --connector-home PATH Connector installation directory (optional, auto-detected)

    Compartment (required when connector is specified by name):
    -c, --compartment ID  Compartment OCID or name (for connector lookup)
                                                    Can be used with both --datasafe-home and --connector
      OR set DS_CONNECTOR_COMP environment variable
      OR set DS_ROOT_COMP environment variable in .env or datasafe.conf

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
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE:-~/.oci/config})

  Connector Options:
    --force-new-bundle-key  Generate new bundle key (ignore existing)
    --check-only            Run version check only and exit
    --check-all             Check all datasafe connectors in oradba_homes.conf

  Bundle Options:
    --skip-download         Skip download (use existing bundle file)
    --bundle-file PATH      Path to existing bundle zip file

Examples:
  # Update connector using OraDBA environment (recommended)
  ${SCRIPT_NAME} --datasafe-home dscon4

  # Update connector by name (using DS_ROOT_COMP from config)
  ${SCRIPT_NAME} --connector my-connector

  # Update with explicit compartment
  ${SCRIPT_NAME} --connector my-connector -c MyCompartment

  # Update with specific home directory
  ${SCRIPT_NAME} --connector my-connector --connector-home /u01/app/oracle/product/datasafe

  # Dry-run to see what would be done
  ${SCRIPT_NAME} --datasafe-home dscon4 --dry-run

  # Check versions only (no update actions)
  ${SCRIPT_NAME} --datasafe-home dscon4 --check-only

  # Check all registered datasafe connectors from OraDBA config
  ${SCRIPT_NAME} --check-all

  # Use existing bundle file (skip download)
  ${SCRIPT_NAME} --connector my-connector --skip-download --bundle-file /tmp/bundle.zip

  # Force new bundle key generation
  ${SCRIPT_NAME} --datasafe-home dscon4 --force-new-bundle-key

Environment Variables:
  OCI_CLI_PROFILE         Default OCI profile
  OCI_CLI_REGION          Default OCI region
  DS_ROOT_COMP            Default root compartment (name or OCID)
  DS_CONNECTOR_COMP       Default connector compartment (name or OCID)
                          Falls back to DS_ROOT_COMP if not set
  ORADBA_BASE             OraDBA installation directory (for --datasafe-home)

Compartment Resolution (priority order):
  1. -c/--compartment flag (highest priority)
  2. DS_ROOT_COMP environment variable (recommended)
  3. DS_CONNECTOR_COMP environment variable

Config Files (loaded in order):
  1. ${SCRIPT_DIR}/../.env
  2. ${SCRIPT_DIR}/../etc/datasafe.conf
  3. ${SCRIPT_DIR}/../etc/\${SCRIPT_NAME}.conf (if exists)

Notes:
  - During update, the connector cannot connect to target databases
  - Connection resumes after update completes
  - Bundle key is stored as base64 in etc/<connector-name>_pwd.b64
  - Existing key file is reused unless --force-new-bundle-key is specified
  - The script must be run as the connector owner (typically oracle user)
  - Version checking compares local setup.py version with online availability
  - OraDBA integration: Use ds_connector_register_oradba.sh to add connector
    metadata to oradba_homes.conf for use with --datasafe-home

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
            --datasafe-home)
                need_val "$1" "${2:-}"
                DATASAFE_ENV="$2"
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
            --force-new-bundle-key | --force-new-pass""word)
                FORCE_NEW_BUNDLE_KEY=true
                shift
                ;;
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --check-all)
                CHECK_ALL=true
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
# Function: extract_connector_from_description
# Purpose.: Extract connector name/ocid from OraDBA description field
# Args....: $1 - Description text (may contain '(oci=...)')
# Returns.: 0 on success, 1 if no connector info found
# Output..: Connector name or OCID to stdout
# ------------------------------------------------------------------------------
extract_connector_from_description() {
    local desc="$1"
    local oci_pattern='\(oci=([^)]+)\)'

    if [[ ! "$desc" =~ $oci_pattern ]]; then
        return 1
    fi

    local oci_value="${BASH_REMATCH[1]}"

    # Handle format: (oci=name,ocid) or (oci=ocid,name)
    if [[ "$oci_value" == *,* ]]; then
        local conn_name conn_ocid
        IFS=',' read -r conn_name conn_ocid <<< "$oci_value"

        if [[ "$conn_name" =~ ^ocid1\. ]]; then
            echo "$conn_ocid"
        else
            echo "$conn_name"
        fi
        return 0
    fi

    echo "$oci_value"
    return 0
}

# ------------------------------------------------------------------------------
# Function: lookup_oradba_home
# Purpose.: Lookup OraDBA datasafe home configuration
# Args....: $1 - Environment name (e.g., dscon4)
# Returns.: 0 on success, 1 on failure
# Output..: Sets CONNECTOR_HOME, CONNECTOR_NAME (if found in description)
# ------------------------------------------------------------------------------
lookup_oradba_home() {
    local env_name="$1"
    local config_file="${ORADBA_BASE}/etc/oradba_homes.conf"

    if [[ ! -f "$config_file" ]]; then
        log_error "OraDBA config not found: $config_file"
        log_error "Make sure ORADBA_BASE is set correctly"
        return 1
    fi

    # Parse config file (format: env_name:path:product:position::description:version)
    local line
    line=$(grep "^${env_name}:" "$config_file" | head -1)

    if [[ -z "$line" ]]; then
        log_error "DataSafe environment '${env_name}' not found in ${config_file}"
        return 1
    fi

    # Extract fields
    local _env path product _position _reserved desc _version
    IFS=':' read -r _env path product _position _reserved desc _version <<< "$line"

    if [[ "$product" != "datasafe" ]]; then
        log_error "Environment '${env_name}' is not a DataSafe connector (product: ${product})"
        return 1
    fi

    CONNECTOR_HOME="$path"
    log_debug "Resolved CONNECTOR_HOME from OraDBA: ${CONNECTOR_HOME}"

    # Extract connector info from description: (oci=xxx) or (oci=name,ocid)
    if CONNECTOR_NAME=$(extract_connector_from_description "$desc"); then
        log_debug "Extracted connector from description: ${CONNECTOR_NAME}"
    else
        log_warn "No (oci=...) found in description for ${env_name}"
        log_warn "You can add it using: ds_connector_register_oradba.sh --datasafe-home ${env_name} --connector <name>"
        return 1
    fi

    return 0
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

    # --check-all is a dedicated batch check mode
    if [[ "${CHECK_ALL}" == "true" ]]; then
        if [[ -n "$DATASAFE_ENV" ]] || [[ -n "$CONNECTOR_NAME" ]] || [[ -n "$CONNECTOR_HOME" ]]; then
            log_error "Cannot mix --check-all with --datasafe-home, --connector, or --connector-home"
            die "Conflicting parameters provided"
        fi

        if [[ "$SKIP_DOWNLOAD" == "true" ]] || [[ -n "$BUNDLE_FILE" ]] || [[ "$FORCE_NEW_BUNDLE_KEY" == "true" ]]; then
            log_error "Cannot use update/download options with --check-all"
            die "Conflicting parameters provided"
        fi

        if [[ -z "${ORADBA_BASE:-}" ]]; then
            log_error "ORADBA_BASE environment variable not set"
            log_error "The --check-all option requires OraDBA to be loaded"
            die "ORADBA_BASE not set"
        fi

        CHECK_ONLY=true

        # Check-all mode has its own execution path and does not require
        # single-connector parameters like CONNECTOR_NAME/CONNECTOR_HOME.
        require_oci_cli
        require_cmd python3

        # Optional compartment resolution for name-based entries in
        # oradba_homes.conf; if not set, those entries are warned/skipped.
        if [[ -n "$COMPARTMENT" ]]; then
            resolve_compartment_to_vars "$COMPARTMENT" "COMP" \
                || die "Failed to resolve compartment: $COMPARTMENT"
            log_info "Compartment: ${COMP_NAME} (${COMP_OCID})"
        elif [[ -n "${DS_ROOT_COMP:-}" ]]; then
            resolve_compartment_to_vars "$DS_ROOT_COMP" "COMP" \
                || die "Failed to resolve DS_ROOT_COMP: $DS_ROOT_COMP"
            log_info "Using DS_ROOT_COMP: ${COMP_NAME} (${COMP_OCID})"
        elif [[ -n "${DS_CONNECTOR_COMP:-}" ]]; then
            resolve_compartment_to_vars "$DS_CONNECTOR_COMP" "COMP" \
                || die "Failed to resolve DS_CONNECTOR_COMP: $DS_CONNECTOR_COMP"
            log_info "Using DS_CONNECTOR_COMP: ${COMP_NAME} (${COMP_OCID})"
        fi

        return 0
    fi

    # Parameter validation: check for conflicting parameters
    if [[ -n "$DATASAFE_ENV" ]]; then
        # Using --datasafe-home
        if [[ -n "$CONNECTOR_NAME" ]] || [[ -n "$CONNECTOR_HOME" ]]; then
            log_error "Cannot mix --datasafe-home with --connector or --connector-home"
            log_error "Use either --datasafe-home OR (--connector + optional --connector-home)"
            die "Conflicting parameters provided"
        fi

        # Check ORADBA_BASE is set
        if [[ -z "${ORADBA_BASE:-}" ]]; then
            log_error "ORADBA_BASE environment variable not set"
            log_error "The --datasafe-home option requires OraDBA to be loaded"
            die "ORADBA_BASE not set"
        fi

        # Lookup OraDBA home configuration
        lookup_oradba_home "$DATASAFE_ENV" || die "Failed to lookup OraDBA environment: $DATASAFE_ENV"
        log_info "Using OraDBA environment: ${DATASAFE_ENV}"
        log_info "Connector home: ${CONNECTOR_HOME}"
        log_info "Connector: ${CONNECTOR_NAME}"
    else
        # Using traditional --connector parameters
        # Require connector name
        require_var CONNECTOR_NAME
    fi

    # Check required commands (after parameter validation so argument errors
    # are reported even when OCI CLI is not available in test environments)
    require_oci_cli
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        require_cmd python3
    else
        require_cmd unzip python3
    fi

    # Resolve compartment for connector lookup (used for connector names in both modes)
    # Priority: -c/--compartment flag > DS_ROOT_COMP > DS_CONNECTOR_COMP
    if [[ -n "$COMPARTMENT" ]]; then
        resolve_compartment_to_vars "$COMPARTMENT" "COMP" \
            || die "Failed to resolve compartment: $COMPARTMENT"
        log_info "Compartment: ${COMP_NAME} (${COMP_OCID})"
    elif [[ -n "${DS_ROOT_COMP:-}" ]]; then
        resolve_compartment_to_vars "$DS_ROOT_COMP" "COMP" \
            || die "Failed to resolve DS_ROOT_COMP: $DS_ROOT_COMP"
        log_info "Using DS_ROOT_COMP: ${COMP_NAME} (${COMP_OCID})"
    elif [[ -n "${DS_CONNECTOR_COMP:-}" ]]; then
        resolve_compartment_to_vars "$DS_CONNECTOR_COMP" "COMP" \
            || die "Failed to resolve DS_CONNECTOR_COMP: $DS_CONNECTOR_COMP"
        log_info "Using DS_CONNECTOR_COMP: ${COMP_NAME} (${COMP_OCID})"
    fi

    # Resolve connector (name or OCID)
    if is_ocid "$CONNECTOR_NAME"; then
        CONNECTOR_OCID="$CONNECTOR_NAME"
        CONNECTOR_DISP_NAME=$(ds_resolve_connector_name "$CONNECTOR_OCID" 2> /dev/null) \
            || CONNECTOR_DISP_NAME="$CONNECTOR_OCID"
        log_info "Connector: ${CONNECTOR_DISP_NAME} (${CONNECTOR_OCID})"
    else
        CONNECTOR_DISP_NAME="$CONNECTOR_NAME"
        if [[ -z "$COMP_OCID" ]]; then
            log_error "Compartment required for connector lookup."
            log_error "Please provide one of the following:"
            log_error "  1. Use -c/--compartment option"
            log_error "  2. Set DS_ROOT_COMP environment variable in .env or datasafe.conf"
            log_error "  3. Set DS_CONNECTOR_COMP environment variable"
            die "Compartment required to resolve connector name: $CONNECTOR_NAME"
        fi
        CONNECTOR_OCID=$(ds_resolve_connector_ocid "$CONNECTOR_NAME" "$COMP_OCID") \
            || die "Failed to resolve connector: $CONNECTOR_NAME"
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
# Function: check_all_connectors
# Purpose.: Check versions for all datasafe connectors from oradba_homes.conf
# Returns.: 0 always (non-fatal warnings per connector)
# Output..: Per-connector checks and summary
# ------------------------------------------------------------------------------
check_all_connectors() {
    local config_file="${ORADBA_BASE}/etc/oradba_homes.conf"

    if [[ ! -f "$config_file" ]]; then
        die "OraDBA config not found: $config_file"
    fi

    log_info "Checking all datasafe connectors from: ${config_file}"

    local total_datasafe=0
    local checked_connectors=0
    local missing_oci=0
    local skipped_connectors=0

    local line env_name path product _position _reserved desc _version connector_info
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        IFS=':' read -r env_name path product _position _reserved desc _version <<< "$line"

        if [[ "$product" != "datasafe" ]]; then
            continue
        fi
        total_datasafe=$((total_datasafe + 1))

        if ! connector_info=$(extract_connector_from_description "$desc"); then
            log_warn "${env_name}: missing (oci=...) metadata, skipping"
            missing_oci=$((missing_oci + 1))
            continue
        fi

        CONNECTOR_HOME="$path"
        CONNECTOR_NAME="$connector_info"

        if is_ocid "$CONNECTOR_NAME"; then
            CONNECTOR_OCID="$CONNECTOR_NAME"
            CONNECTOR_DISP_NAME=$(ds_resolve_connector_name "$CONNECTOR_OCID" 2> /dev/null) \
                || CONNECTOR_DISP_NAME="$CONNECTOR_OCID"
        else
            CONNECTOR_DISP_NAME="$CONNECTOR_NAME"
            if [[ -z "$COMP_OCID" ]]; then
                log_warn "${env_name}: connector '${CONNECTOR_NAME}' requires compartment resolution; set -c/DS_ROOT_COMP/DS_CONNECTOR_COMP"
                skipped_connectors=$((skipped_connectors + 1))
                continue
            fi
            CONNECTOR_OCID=$(ds_resolve_connector_ocid "$CONNECTOR_NAME" "$COMP_OCID" 2> /dev/null) || {
                log_warn "${env_name}: failed to resolve connector name '${CONNECTOR_NAME}', skipping"
                skipped_connectors=$((skipped_connectors + 1))
                continue
            }
        fi

        checked_connectors=$((checked_connectors + 1))
        log_info ""
        log_info "── ${env_name}: ${CONNECTOR_DISP_NAME} ─────────────────────────────────────────"
        check_and_display_versions
    done < "$config_file"

    log_info ""
    log_info "Batch check summary"
    log_info "  datasafe entries: ${total_datasafe}"
    log_info "  checked: ${checked_connectors}"
    log_info "  missing (oci=...): ${missing_oci}"
    log_info "  skipped: ${skipped_connectors}"

    return 0
}

# ------------------------------------------------------------------------------
# Function: is_valid_bundle_key
# Purpose.: Validate bundle key against OCI requirements
# Args....: $1 - Key candidate
# Returns.: 0 if valid, 1 if invalid
# Output..: None
# Notes...: OCI requires 12-30 chars with at least one uppercase, lowercase,
#           numeric, and special character.
# ------------------------------------------------------------------------------
is_valid_bundle_key() {
    local bundle_key="$1"

    [[ ${#bundle_key} -ge 12 ]] || return 1
    [[ ${#bundle_key} -le 30 ]] || return 1
    [[ "$bundle_key" =~ [[:upper:]] ]] || return 1
    [[ "$bundle_key" =~ [[:lower:]] ]] || return 1
    [[ "$bundle_key" =~ [[:digit:]] ]] || return 1
    [[ "$bundle_key" =~ [^[:alnum:]] ]] || return 1

    return 0
}

# ------------------------------------------------------------------------------
# Function: generate_bundle_key
# Purpose.: Generate a random bundle key
# Returns.: Bundle key on stdout
# Output..: Random OCI-compliant bundle key
# ------------------------------------------------------------------------------
generate_bundle_key() {
    # Generate a secure random key (20 chars) and ensure OCI complexity.
    # Allowed special chars are intentionally shell-safe.
    local candidate
    local special_set='!@#%^*_+=:,.?-'

    while true; do
        candidate="$(openssl rand -base64 64 | tr -dc "A-Za-z0-9${special_set}" | head -c 20)"
        if is_valid_bundle_key "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done
}

# ------------------------------------------------------------------------------
# Function: get_or_create_bundle_key
# Purpose.: Get existing bundle key or create new one
# Returns.: 0 on success, sets BUNDLE_KEY and BUNDLE_KEY_FILE
# Output..: Info messages about key handling
# ------------------------------------------------------------------------------
get_or_create_bundle_key() {
    local etc_dir="${SCRIPT_DIR}/../etc"
    local pwd_file="${etc_dir}/${CONNECTOR_DISP_NAME}_pwd.b64"

    BUNDLE_KEY_FILE="$pwd_file"

    # Check if key file exists and we should reuse it
    if [[ -f "$pwd_file" && "$FORCE_NEW_BUNDLE_KEY" != "true" ]]; then
        log_info "Found existing key file: ${pwd_file}"

        local decoded_ok=false

        # Decode key from base64
        if BUNDLE_KEY=$(base64 -d < "$pwd_file" 2> /dev/null); then
            decoded_ok=true
            if [[ -n "$BUNDLE_KEY" ]] && is_valid_bundle_key "$BUNDLE_KEY"; then
                log_info "Reusing existing bundle key"
                return 0
            fi

            log_warn "Existing key does not meet OCI complexity requirements, generating new key"
        fi

        if [[ "$decoded_ok" != "true" ]]; then
            log_warn "Failed to decode existing key file, generating new key"
        fi
    fi

    # Generate new key
    log_info "Generating new bundle key..."
    BUNDLE_KEY=$(generate_bundle_key)

    if [[ -z "$BUNDLE_KEY" ]]; then
        die "Failed to generate bundle key"
    fi

    if ! is_valid_bundle_key "$BUNDLE_KEY"; then
        die "Generated key does not meet OCI complexity requirements"
    fi

    # Save key as base64
    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "$etc_dir"
        echo -n "$BUNDLE_KEY" | base64 > "$pwd_file"
        chmod 600 "$pwd_file"
        log_info "Bundle key saved to: ${pwd_file}"
    else
        log_info "[DRY-RUN] Would save bundle key to: ${pwd_file}"
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

    # OCI CLI writes the connector bundle directly via --file.
    log_info "Step 1/1: Generating and downloading bundle..."
    ds_generate_connector_bundle "$CONNECTOR_OCID" "$BUNDLE_KEY" "$bundle_file" || {
        die "Failed to generate connector bundle"
    }

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would download bundle to: ${bundle_file}"
        BUNDLE_FILE="$bundle_file"
        return 0
    fi

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
# Purpose.: Run setup.py update with bundle key
# Returns.: 0 on success, 1 on error
# Output..: Setup script output
# ------------------------------------------------------------------------------
run_setup_update() {
    log_info "Running setup.py update..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: python3 setup.py update"
        log_info "[DRY-RUN] Working directory: ${CONNECTOR_HOME}"
        log_info "[DRY-RUN] Would provide bundle key via stdin"
        return 0
    fi

    # Run setup.py update in connector home directory
    # Pass bundle key via stdin
    local setup_py="${CONNECTOR_HOME}/setup.py"

    log_info "Executing: python3 setup.py update"
    log_info "Working directory: ${CONNECTOR_HOME}"

    # Run setup.py and provide bundle key when prompted
    (
        cd "$CONNECTOR_HOME" || die "Failed to change directory to ${CONNECTOR_HOME}"
        echo "$BUNDLE_KEY" | python3 "$setup_py" update
    )

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Connector update completed successfully"
    else
        die "Connector update failed with exit code: $exit_code"
    fi
}

# ------------------------------------------------------------------------------
# Function: get_local_connector_version
# Purpose.: Extract version from local connector's setup.py
# Returns.: Version string on stdout, or empty if not found
# Output..: Version string (e.g., "1.2.3")
# Notes...: Parses setup.py for version information
# ------------------------------------------------------------------------------
get_local_connector_version() {
    local setup_py="${CONNECTOR_HOME}/setup.py"

    if [[ ! -f "$setup_py" ]]; then
        log_debug "setup.py not found at: $setup_py"
        return 1
    fi

    # Try to extract version from setup.py
    # Look for patterns like: version='1.2.3', version="1.2.3", __version__ = "1.2.3"
    local version
    version=$(grep -E "^\s*(version|__version__)\s*=\s*['\"]" "$setup_py" 2> /dev/null \
        | head -1 \
        | sed -E "s/.*['\"]([0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?)['\"].*/\1/")

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    # Alternative: Run setup.py version command
    version=$(cd "$CONNECTOR_HOME" && python3 setup.py version 2> /dev/null | grep -oP '(?<=version : )[0-9.]+' | head -1)

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    log_debug "Unable to determine local version from setup.py"
    return 1
}

# ------------------------------------------------------------------------------
# Function: get_online_connector_version
# Purpose.: Query OCI for the latest available connector version
# Returns.: Version string on stdout, or empty if not found
# Output..: Version string or "UNKNOWN"
# Notes...: Queries Data Safe API for connector bundle metadata
# ------------------------------------------------------------------------------
get_online_connector_version() {
    if [[ -z "${CONNECTOR_OCID:-}" ]]; then
        log_debug "Connector OCID not set, cannot query online version"
        return 1
    fi

    # Try to get version from connector metadata
    local version
    version=$(oci data-safe on-prem-connector get \
        --on-prem-connector-id "$CONNECTOR_OCID" \
        --query 'data."available-version"' \
        --raw-output 2> /dev/null || echo "")

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
        return 0
    fi

    # Alternative: Check if there's version info in lifecycle details
    version=$(oci data-safe on-prem-connector get \
        --on-prem-connector-id "$CONNECTOR_OCID" \
        --query 'data."lifecycle-details"' \
        --raw-output 2> /dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    log_debug "Unable to determine online version from OCI"
    echo "UNKNOWN"
    return 1
}

# ------------------------------------------------------------------------------
# Function: compare_versions
# Purpose.: Compare two semantic version strings
# Args....: $1 - first version (e.g., "1.2.3")
#           $2 - second version (e.g., "1.2.4")
# Returns.: 0 if equal, 1 if v1 < v2, 2 if v1 > v2
# Output..: None
# ------------------------------------------------------------------------------
compare_versions() {
    local v1="$1"
    local v2="$2"

    # Strip any pre-release identifiers (e.g., "1.2.3-beta" -> "1.2.3")
    v1="${v1%%-*}"
    v2="${v2%%-*}"

    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi

    # Split versions into arrays
    IFS='.' read -ra ver1 <<< "$v1"
    IFS='.' read -ra ver2 <<< "$v2"

    # Compare each component
    for i in 0 1 2; do
        local n1="${ver1[$i]:-0}"
        local n2="${ver2[$i]:-0}"

        if ((n1 > n2)); then
            return 2
        elif ((n1 < n2)); then
            return 1
        fi
    done

    return 0
}

# ------------------------------------------------------------------------------
# Function: check_and_display_versions
# Purpose.: Check and display local vs online connector versions
# Returns.: 0 (informational only)
# Output..: Version comparison information
# ------------------------------------------------------------------------------
check_and_display_versions() {
    log_info "Checking connector versions..."

    # Get local version
    local local_version
    if local_version=$(get_local_connector_version 2> /dev/null); then
        log_info "Local connector version: ${local_version}"
    else
        local_version="UNKNOWN"
        log_info "Local connector version: Unknown (unable to parse setup.py)"
    fi

    # Get online version
    local online_version
    if online_version=$(get_online_connector_version 2> /dev/null); then
        log_info "Available online version: ${online_version}"
    else
        online_version="UNKNOWN"
        log_info "Available online version: Unknown (unable to query OCI)"
    fi

    # Compare versions if both are known
    if [[ "$local_version" != "UNKNOWN" && "$online_version" != "UNKNOWN" ]]; then
        compare_versions "$local_version" "$online_version"
        case $? in
            0)
                log_info "Status: Local version is up to date"
                ;;
            1)
                log_info "Status: Update available (${local_version} → ${online_version})"
                ;;
            2)
                log_info "Status: Local version is newer than online (${local_version} > ${online_version})"
                ;;
        esac
    else
        log_info "Status: Cannot compare versions (insufficient version information)"
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

    # Step 0: Check and display versions
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Step 0: Version Check"
    log_info "═══════════════════════════════════════════════════════════════════"
    check_and_display_versions

    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log_info ""
        log_info "CHECK-ONLY MODE: Skipping key, download, extract, and setup update steps"
        return 0
    fi

    # Step 1: Get or create bundle key
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════════"
    log_info "Step 1: Key Management"
    log_info "═══════════════════════════════════════════════════════════════════"
    get_or_create_bundle_key

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
    log_info "Bundle key file: ${BUNDLE_KEY_FILE}"

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
    # Show usage if no arguments provided
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Initialize configuration cascade
    init_config "${SCRIPT_NAME}.conf"

    # Parse arguments
    parse_args "$@"

    # Validate inputs
    validate_inputs

    if [[ "${CHECK_ALL}" == "true" ]]; then
        check_all_connectors
        log_info "${SCRIPT_NAME} completed successfully"
        return 0
    fi

    # Do the work
    do_work

    log_info "${SCRIPT_NAME} completed successfully"
}

# Run main function
main "$@"
