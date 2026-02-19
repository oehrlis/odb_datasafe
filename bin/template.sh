#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: template.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Template for new Data Safe scripts using standardized patterns
# Usage......: Copy this template and modify for your needs
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
: "${COMPARTMENT:=}"     # Compartment name or OCID
: "${TARGETS:=}"         # Comma-separated target names/OCIDs
: "${LIFECYCLE_STATE:=}" # Filter by lifecycle (e.g., ACTIVE,NEEDS_ATTENTION)
: "${DRY_RUN:=false}"    # Dry-run mode (set by --dry-run flag)

# Script-specific defaults (add your own here)
# : "${MY_CUSTOM_OPTION:=default_value}"

# Runtime variables (populated during execution)
COMP_NAME="" # Resolved compartment name
COMP_OCID="" # Resolved compartment OCID
# shellcheck disable=SC2034  # Used in derived scripts
TARGET_NAME="" # Resolved target name
# shellcheck disable=SC2034  # Used in derived scripts
TARGET_OCID="" # Resolved target OCID

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
Usage: ${SCRIPT_NAME} [OPTIONS] [TARGETS...]

Description:
  [Describe what your script does here]

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

  Script-Specific Options:
    -c, --compartment ID    Compartment OCID or name
    -T, --targets LIST      Comma-separated target names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state
    
    [Add your script-specific options here]

Examples:
  # Example 1: Process all targets in compartment
  ${SCRIPT_NAME} -c MyCompartment

  # Example 2: Process specific targets with dry-run
  ${SCRIPT_NAME} -T target1,target2 --dry-run

  # Example 3: Filter by lifecycle state with verbose logging
  ${SCRIPT_NAME} -c MyCompartment -L ACTIVE -v

Environment:
  OCI_CLI_PROFILE         Default OCI profile
  OCI_CLI_REGION          Default OCI region
  DS_ROOT_COMP_OCID       Default compartment OCID

Config Files (loaded in order):
  1. ${SCRIPT_DIR}/../.env
  2. ${SCRIPT_DIR}/../etc/datasafe.conf
  3. ${SCRIPT_DIR}/../etc/\${SCRIPT_NAME}.conf (if exists)

Resolution Pattern:
  Compartments and targets accept both names and OCIDs. The script will:
  1. Accept input as provided (name or OCID)
  2. Resolve to both NAME and OCID internally
  3. Use OCID for API calls
  4. Use NAME for user-friendly messages

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
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
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
            # Add your custom options here
            # --my-option)
            #     need_val "$1" "${2:-}"
            #     MY_OPTION="$2"
            #     shift 2
            #     ;;
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                # Positional argument (e.g., target name)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Handle positional arguments (e.g., treat as targets)
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}" # Convert spaces to commas
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and resolve compartment/target OCIDs
# Returns.: 0 on success, exits on error
# Output..: Info messages about resolved resources
# Notes...: Sets COMP_NAME, COMP_OCID, TARGET_NAME, TARGET_OCID as needed
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    # Check required commands
    require_oci_cli

    # Check required variables (uncomment as needed)
    # require_var COMPARTMENT
    # require_var TARGETS

    # Custom validation logic
    if [[ -z "$COMPARTMENT" && -z "$TARGETS" ]]; then
        die "Either --compartment or --targets must be specified"
    fi

    # Example: Resolve compartment (accepts name or OCID)
    if [[ -n "$COMPARTMENT" ]]; then
        resolve_compartment_to_vars "$COMPARTMENT" "COMP" \
            || die "Failed to resolve compartment: $COMPARTMENT"
        log_info "Compartment: ${COMP_NAME} (${COMP_OCID})"
    fi

    # Example: Resolve target (accepts name or OCID)
    # if [[ -n "$TARGETS" ]]; then
    #     resolve_target_to_vars "$TARGETS" "TARGET" "$COMP_OCID" \
    #         || die "Failed to resolve target: $TARGETS"
    #     log_info "Target: ${TARGET_NAME} (${TARGET_OCID})"
    # fi

    # Add your validation here
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - implement your logic here
# Returns.: 0 on success, exits on error
# Output..: Work progress and results
# Notes...: Use oci_exec() for write operations, oci_exec_ro() for reads
# ------------------------------------------------------------------------------
do_work() {
    log_info "Starting work..."

    # Show dry-run message if applicable
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY-RUN MODE: No changes will be made"
    fi

    # Example 1: List targets using read-only operation
    if [[ -n "$COMPARTMENT" ]]; then
        log_info "Listing targets in compartment: ${COMP_NAME}"

        # Use oci_exec_ro() for read-only operations (works even in dry-run)
        local targets_json
        targets_json=$(ds_list_targets "$COMP_OCID" "$LIFECYCLE_STATE") || die "Failed to list targets"

        # Process targets
        local count
        count=$(echo "$targets_json" | jq '.data | length')
        log_info "Found $count targets"

        # Example: iterate over targets
        echo "$targets_json" | jq -r '.data[] | "\(.id)|\(."display-name")"' | while IFS='|' read -r target_ocid target_name; do
            log_info "Processing: ${target_name} (${target_ocid})"

            # Example: Do write operation (respects dry-run)
            # oci_exec data-safe target-database refresh \
            #     --target-database-id "$target_ocid" || log_warn "Failed to refresh $target_name"
        done
    fi

    # Example 2: Process specific targets
    if [[ -n "$TARGETS" ]]; then
        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            log_info "Processing target: $target"

            # Resolve to both name and OCID
            resolve_target_to_vars "$target" "TGT" "$COMP_OCID" \
                || die "Failed to resolve target: $target"

            log_info "Resolved: ${TGT_NAME} (${TGT_OCID})"

            # Do something with the target
            # Use oci_exec_ro() for reads, oci_exec() for writes
            # oci_exec data-safe target-database refresh \
            #     --target-database-id "$tgt_ocid" || log_warn "Failed to refresh $tgt_name"
        done
    fi

    log_info "Work completed successfully"
}

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Cleanup function called on exit
# Returns.: 0
# Output..: Debug message
# Notes...: Override the default cleanup from common.sh if needed
# ------------------------------------------------------------------------------
cleanup() {
    # Add cleanup logic here (temp files, etc.)
    log_debug "Cleanup completed"
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
