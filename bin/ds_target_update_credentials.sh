#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_credentials.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Version....: v0.5.3
# Purpose....: Update Oracle Data Safe target database credentials
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null | tr -d '\n' || echo '0.5.3')"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${DS_USERNAME:=${DATASAFE_USER:-}}"
: "${DS_PASSWORD:=}"
: "${NO_PROMPT:=false}"
: "${CRED_FILE:=}"
: "${APPLY_CHANGES:=false}"

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

# Runtime variables
TMP_CRED_JSON=""

# =============================================================================
# FUNCTIONS
# =============================================================================

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Update Oracle Data Safe target database credentials (username/password).
  Supports individual targets or bulk updates with flexible credential sources.

Options:
  Common:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -d, --debug             Enable debug output
    --log-file FILE         Log to file

  OCI:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file

  Selection:
    -c, --compartment ID    Compartment OCID or name (default: DS_ROOT_COMP)
                            Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -T, --targets LIST      Comma-separated target names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state (default: ${LIFECYCLE_STATE})

  Credentials:
    -U, --username USER     Database username (default: ${DS_USERNAME:-not set})
    -P, --password PASS     Database password (use with caution)
    --cred-file FILE        JSON file with {\"userName\": \"user\", \"password\": \"pass\"}
    --no-prompt             Fail instead of prompting for missing password

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)

Credential Sources (in order of precedence):
  1. --cred-file JSON file
  2. -U/--username and -P/--password options
  3. Environment variables (DS_USERNAME/DS_PASSWORD)
  4. Interactive prompt (unless --no-prompt)

Examples:
  # Dry-run with specific username (will prompt for password)
  ${SCRIPT_NAME} -U myuser

  # Apply changes using credentials file
  ${SCRIPT_NAME} --cred-file creds.json --apply

  # Update specific targets with username/password
  ${SCRIPT_NAME} -T target1,target2 -U myuser -P mypass --apply

  # Bulk update for compartment (interactive password)
  ${SCRIPT_NAME} -c my-compartment -U dbuser --apply

EOF
    exit 0
}

parse_args() {
    parse_common_opts "$@"

    # Parse script-specific options
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
            -U | --username)
                need_val "$1" "${2:-}"
                DS_USERNAME="$2"
                shift 2
                ;;
            -P | --password)
                need_val "$1" "${2:-}"
                DS_PASSWORD="$2"
                shift 2
                ;;
            --cred-file)
                need_val "$1" "${2:-}"
                CRED_FILE="$2"
                shift 2
                ;;
            --no-prompt)
                NO_PROMPT=true
                shift
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                export OCI_CLI_PROFILE="$2"
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

    # Handle positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq base64

    # If no scope specified, use DS_ROOT_COMP as default
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        local root_comp
        root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
        COMPARTMENT="$root_comp"
        log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    # Validate credentials file if provided
    if [[ -n "$CRED_FILE" ]]; then
        [[ -f "$CRED_FILE" ]] || die "Credentials file not found: $CRED_FILE"
        [[ -r "$CRED_FILE" ]] || die "Cannot read credentials file: $CRED_FILE"

        # Validate JSON structure
        if ! jq -r '.userName // empty' "$CRED_FILE" > /dev/null 2>&1; then
            die "Invalid credentials file format. Expected JSON with userName/password fields"
        fi
    fi

    # Show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi
}

# ------------------------------------------------------------------------------
# Function....: resolve_credentials
# Purpose.....: Resolve username/password from various sources
# Returns.....: Sets DS_USERNAME and DS_PASSWORD variables
# ------------------------------------------------------------------------------
resolve_credentials() {
    log_debug "Resolving credentials..."

    # 1. Use credentials file if provided
    if [[ -n "$CRED_FILE" ]]; then
        log_debug "Loading credentials from file: $CRED_FILE"
        DS_USERNAME=$(jq -r '.userName // ""' "$CRED_FILE")
        DS_PASSWORD=$(jq -r '.password // ""' "$CRED_FILE")

        [[ -n "$DS_USERNAME" ]] || die "Username not found in credentials file"
        [[ -n "$DS_PASSWORD" ]] || die "Password not found in credentials file"

        log_info "Credentials loaded from file: $CRED_FILE"
        return 0
    fi

    # 2. Check if we have username
    [[ -n "$DS_USERNAME" ]] || die "Username not specified. Use -U/--username, --cred-file, or set DS_USERNAME"

    # 3. Resolve password if not provided
    if [[ -z "$DS_PASSWORD" ]]; then
        if [[ "$NO_PROMPT" == "true" ]]; then
            die "Password not specified and --no-prompt set. Use -P/--password, --cred-file, or set DS_PASSWORD"
        fi

        # Interactive prompt for password
        log_info "Password not provided, prompting..."
        echo -n "Enter password for user '$DS_USERNAME': " >&2
        read -rs DS_PASSWORD
        echo >&2

        [[ -n "$DS_PASSWORD" ]] || die "Password cannot be empty"
    fi

    log_info "Using credentials for user: $DS_USERNAME"
}

# ------------------------------------------------------------------------------
# Function....: create_temp_cred_json
# Purpose.....: Create temporary JSON file with credentials
# Returns.....: Sets TMP_CRED_JSON variable
# ------------------------------------------------------------------------------
create_temp_cred_json() {
    TMP_CRED_JSON=$(mktemp)

    # Create credentials JSON
    jq -n \
        --arg user "$DS_USERNAME" \
        --arg pass "$DS_PASSWORD" \
        '{userName: $user, password: $pass}' > "$TMP_CRED_JSON"

    log_debug "Created temporary credentials file: $TMP_CRED_JSON"
}

# ------------------------------------------------------------------------------
# Function....: cleanup_temp_files
# Purpose.....: Clean up temporary credential files
# ------------------------------------------------------------------------------
cleanup_temp_files() {
    if [[ -n "$TMP_CRED_JSON" && -f "$TMP_CRED_JSON" ]]; then
        log_debug "Cleaning up temporary credentials file"
        rm -f "$TMP_CRED_JSON"
        TMP_CRED_JSON=""
    fi
}

# ------------------------------------------------------------------------------
# Function....: update_target_credentials
# Purpose.....: Update credentials for a single target
# Parameters..: $1 - target OCID
#               $2 - target name
# ------------------------------------------------------------------------------
update_target_credentials() {
    local target_ocid="$1"
    local target_name="$2"

    log_debug "Processing target: $target_name ($target_ocid)"

    log_info "Target: $target_name"
    log_info "  Username: $DS_USERNAME"
    log_info "  Password: [hidden]"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating credentials..."

        # Prepare credentials JSON for API call
        local cred_json
        cred_json=$(jq -n \
            --arg user "$DS_USERNAME" \
            --arg pass "$DS_PASSWORD" \
            '{userName: $user, password: $pass}')

        if oci_exec data-safe target-database update \
            --target-database-id "$target_ocid" \
            --credentials "$cred_json" > /dev/null; then
            log_info "  ✅ Credentials updated successfully"
            return 0
        else
            log_error "  ❌ Failed to update credentials"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function....: list_targets_in_compartment
# Purpose.....: List targets in compartment
# Parameters..: $1 - compartment OCID or name
# Returns.....: JSON array of targets
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"
    local comp_ocid

    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing targets in compartment: $comp_ocid"

    local -a cmd=(
        data-safe target-database list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )

    if [[ -n "$LIFECYCLE_STATE" ]]; then
        cmd+=(--lifecycle-state "$LIFECYCLE_STATE")
    fi

    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function....: do_work
# Purpose.....: Main work function
# ------------------------------------------------------------------------------
do_work() {
    local success_count=0 error_count=0

    # Resolve and validate credentials
    resolve_credentials
    create_temp_cred_json

    # Ensure cleanup on exit
    trap cleanup_temp_files EXIT

    # Collect target data
    if [[ -n "$TARGETS" ]]; then
        # Process specific targets
        log_info "Processing specific targets..."

        local -a target_list
        IFS=',' read -ra target_list <<< "$TARGETS"

        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces

            local target_ocid target_name

            if is_ocid "$target"; then
                target_ocid="$target"
                # Get target name
                target_name=$(oci_exec data-safe target-database get \
                    --target-database-id "$target_ocid" \
                    --query 'data."display-name"' \
                    --raw-output 2> /dev/null || echo "unknown")
            else
                # Resolve target name to OCID
                log_debug "Resolving target name: $target"
                local resolved
                if [[ -n "$COMPARTMENT" ]]; then
                    resolved=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || die "Failed to resolve target: $target"
                else
                    local root_comp
                    root_comp=$(get_root_compartment_ocid) || die "Failed to get root compartment"
                    resolved=$(ds_resolve_target_ocid "$target" "$root_comp") || die "Failed to resolve target: $target"
                fi

                [[ -n "$resolved" ]] || die "Target not found: $target"
                target_ocid="$resolved"
                target_name="$target"
            fi

            if update_target_credentials "$target_ocid" "$target_name"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        done
    else
        # Process targets from compartment
        log_info "Processing targets from compartment..."
        local json_data
        json_data=$(list_targets_in_compartment "$COMPARTMENT") || die "Failed to list targets"

        local total_count
        total_count=$(echo "$json_data" | jq '.data | length')
        log_info "Found $total_count targets to process"

        if [[ $total_count -eq 0 ]]; then
            log_warn "No targets found"
            return 0
        fi

        local current=0
        while read -r target_ocid target_name; do
            current=$((current + 1))
            log_info "[$current/$total_count] Processing: $target_name"

            if update_target_credentials "$target_ocid" "$target_name"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')
    fi

    # Summary
    log_info "Credential update completed:"
    log_info "  Successful: $success_count"
    log_info "  Errors: $error_count"

    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Execute main work
    if do_work; then
        log_info "Credential update completed successfully"
    else
        die "Credential update failed with errors"
    fi
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_update_credentials.sh -----------------------------------
