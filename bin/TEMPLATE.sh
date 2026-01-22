#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: TEMPLATE.sh (v4.0.0)
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v4.0.0
# Purpose....: Template for new Data Safe scripts using v4 libraries
# Usage......: Copy this template and modify for your needs
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP
# =============================================================================

# Source the v4 library (handles error setup automatically)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/ds_lib.sh"

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null | tr -d '\n' || echo '0.5.3')"

# Default configuration (can be overridden by config files and CLI)
: "${COMPARTMENT:=}"     # Compartment name or OCID
: "${TARGETS:=}"         # Comma-separated target names/OCIDs
: "${LIFECYCLE_STATE:=}" # Filter by lifecycle (e.g., ACTIVE,NEEDS_ATTENTION)
: "${DRY_RUN:=false}"    # Dry-run mode (set by --dry-run flag)

# Script-specific defaults (add your own here)
# : "${MY_CUSTOM_OPTION:=default_value}"

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: usage
# Purpose.....: Display usage information
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
  # Example 1
  ${SCRIPT_NAME} -c MyCompartment

  # Example 2
  ${SCRIPT_NAME} -T target1,target2 --dry-run

  # Example 3
  ${SCRIPT_NAME} -L ACTIVE -v

Environment:
  OCI_CLI_PROFILE         Default OCI profile
  OCI_CLI_REGION          Default OCI region
  DS_ROOT_COMP_OCID       Default compartment OCID

Config Files (loaded in order):
  1. ${SCRIPT_DIR}/../.env
  2. ${SCRIPT_DIR}/../etc/datasafe.conf
  3. ${SCRIPT_DIR}/../etc/\${SCRIPT_NAME}.conf (if exists)

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function....: parse_args
# Purpose.....: Parse command-line arguments
# Parameters..: $@ - command line arguments
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
# Function....: validate_inputs
# Purpose.....: Validate required inputs and configuration
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    # Check required commands
    require_cmd oci jq

    # Check required variables (uncomment as needed)
    # require_var COMPARTMENT
    # require_var TARGETS

    # Example: Get root compartment OCID (resolves name if needed)
    # local root_comp
    # root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
    # log_debug "Using root compartment: $root_comp"

    # Custom validation logic
    if [[ -z "$COMPARTMENT" && -z "$TARGETS" ]]; then
        die "Either --compartment or --targets must be specified"
    fi

    # Add your validation here
}

# ------------------------------------------------------------------------------
# Function....: do_work
# Purpose.....: Main work function - implement your logic here
# ------------------------------------------------------------------------------
do_work() {
    log_info "Starting work..."

    # Example: List targets
    if [[ -n "$COMPARTMENT" ]]; then
        log_info "Listing targets in compartment: $COMPARTMENT"

        local comp_ocid
        comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT")

        local targets_json
        targets_json=$(ds_list_targets "$comp_ocid" "$LIFECYCLE_STATE")

        # Process targets
        local count
        count=$(echo "$targets_json" | jq '.data | length')
        log_info "Found $count targets"

        # Example: iterate over targets
        echo "$targets_json" | jq -r '.data[].id' | while read -r target_ocid; do
            local target_name
            target_name=$(ds_resolve_target_name "$target_ocid")
            log_info "Processing: $target_name"

            # Do something with each target
            # ds_refresh_target "$target_ocid"
        done
    fi

    # Example: Process specific targets
    if [[ -n "$TARGETS" ]]; then
        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            log_info "Processing target: $target"

            # Resolve to OCID if needed
            local target_ocid="$target"
            if ! is_ocid "$target"; then
                target_ocid=$(ds_resolve_target_ocid "$target" "${COMPARTMENT:-}")
            fi

            # Do something with the target
            # ds_refresh_target "$target_ocid"
        done
    fi

    log_info "Work completed successfully"
}

# ------------------------------------------------------------------------------
# Function....: cleanup (optional)
# Purpose.....: Cleanup function called on exit
# Notes.......: Override the default cleanup from common.sh if needed
# ------------------------------------------------------------------------------
cleanup() {
    # Add cleanup logic here (temp files, etc.)
    log_debug "Cleanup completed"
}

# =============================================================================
# MAIN
# =============================================================================

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
