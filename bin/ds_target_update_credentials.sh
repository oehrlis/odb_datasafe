#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_credentials.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
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

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${DS_USER:=${DATASAFE_USER:-}}"
: "${DS_SECRET:=${DATASAFE_SECRET:-}}"
: "${NO_PROMPT:=false}"
: "${CRED_FILE:=}"
: "${DATASAFE_SECRET_FILE:=}"
: "${RUN_ROOT:=false}"
: "${COMMON_USER_PREFIX:=C##}"
: "${APPLY_CHANGES:=false}"
: "${WAIT_FOR_STATE:=}" # Empty = async (no wait); "ACCEPTED" or other for sync wait

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

# Initialize configuration
init_config

# Re-sync credential defaults after config loading.
# init_config may populate DATASAFE_USER / DATASAFE_SECRET from datasafe.conf
# after initial parameter expansion above.
: "${DS_USER:=${DATASAFE_USER:-}}"
: "${DS_SECRET:=${DATASAFE_SECRET:-}}"

# Runtime variables
TMP_CRED_JSON=""

# Resolved variables (set during validation)
COMPARTMENT_OCID=""
COMPARTMENT_NAME=""

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and help message
# Returns.: 0 (exits after display)
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
    Update Oracle Data Safe target database credentials (user/secret).
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
    -A, --all               Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST      Comma-separated target names or OCIDs
    -r, --filter REGEX      Filter target names by regex (substring match)
    -L, --lifecycle STATE   Filter by lifecycle state (default: ${LIFECYCLE_STATE})

  Credentials:
    -U, --ds-user USER      Database username (default: ${DS_USER:-not set})
    -P, --ds-secret VALUE   Database secret (plain or base64)
    --secret-file FILE      Base64 secret file (optional)
    --cred-file FILE        JSON file with {\"userName\": \"user\", \"password\": \"pass\"}
    --root                  Root normalization hint (common user with ${COMMON_USER_PREFIX})
    --no-prompt             Fail instead of prompting for missing secret

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)
    --wait-for-state STATE  Wait for operation completion with state (e.g., ACCEPTED)
                            Default: async (no wait)

Credential Sources (in order of precedence):
  1. --cred-file JSON file
  2. -U/--ds-user and -P/--ds-secret options
  3. Environment variables (DS_USER/DS_SECRET)
  4. --secret-file or <user>_pwd.b64 lookup
  5. Interactive prompt (unless --no-prompt)

Examples:
  # Dry-run with specific username (will prompt for secret)
  ${SCRIPT_NAME} -U myuser

  # Apply changes using credentials file (async)
  ${SCRIPT_NAME} --cred-file creds.json --apply

  # Apply changes and wait for completion
  ${SCRIPT_NAME} --cred-file creds.json --apply --wait-for-state ACCEPTED

  # Update specific targets with username/secret
  ${SCRIPT_NAME} -T target1,target2 -U myuser -P mysecret --apply

  # Bulk update for compartment (interactive secret, wait for state)
  ${SCRIPT_NAME} -c my-compartment -U dbuser --apply --wait-for-state ACCEPTED

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on invalid arguments
# Notes...: Sets global variables for script configuration
# ------------------------------------------------------------------------------
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
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -U | --ds-user | --username)
                need_val "$1" "${2:-}"
                DS_USER="$2"
                if [[ "$1" == "--username" ]]; then
                    log_warn "Option --username is deprecated, use --ds-user"
                fi
                shift 2
                ;;
            -P | --ds-secret)
                need_val "$1" "${2:-}"
                DS_SECRET="$2"
                shift 2
                ;;
            --secret-file)
                need_val "$1" "${2:-}"
                DATASAFE_SECRET_FILE="$2"
                shift 2
                ;;
            --cred-file)
                need_val "$1" "${2:-}"
                CRED_FILE="$2"
                shift 2
                ;;
            --root)
                RUN_ROOT=true
                shift
                ;;
            --no-prompt)
                NO_PROMPT=true
                shift
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --wait-for-state)
                need_val "$1" "${2:-}"
                WAIT_FOR_STATE="$2"
                shift 2
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

# Function: resolve_ds_user
# Purpose.: Resolve Data Safe username based on root normalization hint
# Args....: None
# Returns.: 0 on success
# Output..: Username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user() {
    local base_user="$DS_USER"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_user" == ${COMMON_USER_PREFIX}* ]]; then
        base_user="${base_user#${COMMON_USER_PREFIX}}"
    fi

    if [[ "$RUN_ROOT" == "true" && -n "$COMMON_USER_PREFIX" ]]; then
        printf '%s' "${COMMON_USER_PREFIX}${base_user}"
        return 0
    fi

    printf '%s' "$base_user"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate required inputs and dependencies
# Returns.: 0 on success, exits on validation failure
# Notes...: Checks for required commands and sets defaults
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli
    require_cmd base64

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    # If neither targets nor compartment specified, show help
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" && -z "$CRED_FILE" && -z "$DS_USER" ]]; then
        usage
    fi

    # Resolve compartment if specified (accept name or OCID)
    if [[ -n "$COMPARTMENT" ]]; then
        if is_ocid "$COMPARTMENT"; then
            # User provided OCID, resolve to name
            COMPARTMENT_OCID="$COMPARTMENT"
            COMPARTMENT_NAME=$(oci_get_compartment_name "$COMPARTMENT_OCID" 2> /dev/null) || COMPARTMENT_NAME="$COMPARTMENT_OCID"
            log_debug "Resolved compartment OCID to name: $COMPARTMENT_NAME"
        else
            # User provided name, resolve to OCID
            COMPARTMENT_NAME="$COMPARTMENT"
            COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || {
                die "Cannot resolve compartment name '$COMPARTMENT' to OCID.\nVerify compartment name or use OCID directly."
            }
            log_debug "Resolved compartment name to OCID: $COMPARTMENT_OCID"
        fi
        log_info "Using compartment: $COMPARTMENT_NAME"
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

    DS_USER="$(resolve_ds_user)"

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_credentials
# Purpose.: Resolve user/secret from various sources
# Returns.: 0 on success, exits on error
# Notes...: Sets DS_USER and DS_SECRET global variables
# ------------------------------------------------------------------------------
resolve_credentials() {
    log_debug "Resolving credentials..."

    # 1. Use credentials file if provided
    if [[ -n "$CRED_FILE" ]]; then
        log_debug "Loading credentials from file: $CRED_FILE"
        DS_USER=$(jq -r '.userName // ""' "$CRED_FILE")
        DS_SECRET=$(jq -r '.password // ""' "$CRED_FILE")
        DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")

        [[ -n "$DS_USER" ]] || die "User not found in credentials file"
        [[ -n "$DS_SECRET" ]] || die "Secret not found in credentials file"

        log_info "Credentials loaded from file: $CRED_FILE"
        return 0
    fi

    # 2. Check if we have user
    [[ -n "$DS_USER" ]] || die "User not specified. Use -U/--ds-user, --cred-file, or set DS_USER"

    # 3. Resolve secret if not provided
    if [[ -n "$DS_SECRET" ]]; then
        local is_b64="false"
        if is_base64_string "$DS_SECRET"; then
            is_b64="true"
        fi
        DS_SECRET=$(normalize_secret_value "$DS_SECRET") || die "Failed to decode base64 secret"
        [[ -n "$DS_SECRET" ]] || die "Decoded secret is empty"
        if [[ "$is_b64" == "true" ]]; then
            log_info "Decoded Data Safe secret from base64 input"
        fi
    fi

    if [[ -z "$DS_SECRET" ]]; then
        local secret_file=""
        if secret_file=$(find_password_file "$DS_USER" "${DATASAFE_SECRET_FILE:-}"); then
            DS_SECRET=$(decode_base64_file "$secret_file") || die "Failed to decode base64 secret file: $secret_file"
            DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")
            [[ -n "$DS_SECRET" ]] || die "Secret file is empty: $secret_file"
            log_info "Loaded Data Safe secret from file: $secret_file"
        fi
    fi

    if [[ -z "$DS_SECRET" ]]; then
        if [[ "$NO_PROMPT" == "true" ]]; then
            die "Secret not specified and --no-prompt set. Use -P/--ds-secret, --secret-file, --cred-file, or set DS_SECRET"
        fi

        # Interactive prompt for secret
        log_info "Secret not provided, prompting..."
        echo -n "Enter secret for user '$DS_USER': " >&2
        read -rs DS_SECRET
        echo >&2
        DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")

        [[ -n "$DS_SECRET" ]] || die "Secret cannot be empty"
    fi

    log_info "Using credentials for user: $DS_USER"
}

# ------------------------------------------------------------------------------
# Function: create_temp_cred_json
# Purpose.: Create temporary JSON file with credentials
# Returns.: 0 on success
# Notes...: Sets TMP_CRED_JSON global variable
# ------------------------------------------------------------------------------
create_temp_cred_json() {
    TMP_CRED_JSON=$(mktemp)

    # Create credentials JSON
    jq -n \
        --arg user "$DS_USER" \
        --arg pass "$DS_SECRET" \
        '{userName: $user, password: $pass}' > "$TMP_CRED_JSON"

    log_debug "Created temporary credentials file: $TMP_CRED_JSON"
}

# ------------------------------------------------------------------------------
# Function: cleanup_temp_files
# Purpose.: Clean up temporary credential files
# Returns.: 0 on success
# ------------------------------------------------------------------------------
cleanup_temp_files() {
    if [[ -n "$TMP_CRED_JSON" && -f "$TMP_CRED_JSON" ]]; then
        log_debug "Cleaning up temporary credentials file"
        rm -f "$TMP_CRED_JSON"
        TMP_CRED_JSON=""
    fi
}

# ------------------------------------------------------------------------------
# Function: update_target_credentials
# Purpose.: Update credentials for a single target
# Args....: $1 - target OCID
#           $2 - target name
# Returns.: 0 on success, 1 on error
# Output..: Progress and status messages
# ------------------------------------------------------------------------------
update_target_credentials() {
    local target_ocid="$1"
    local target_name="$2"

    log_debug "Processing target: $target_name ($target_ocid)"

    log_info "Target: $target_name"
    log_info "  User: $DS_USER"
    log_info "  Secret: [hidden]"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating credentials..."

        # Prepare credentials JSON for API call
        local cred_json
        cred_json=$(jq -n \
            --arg user "$DS_USER" \
            --arg pass "$DS_SECRET" \
            '{userName: $user, password: $pass}')

        # Build OCI command
        local -a cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --credentials "$cred_json"
        )

        # Add wait-for-state if specified
        if [[ -n "$WAIT_FOR_STATE" ]]; then
            cmd+=(--wait-for-state "$WAIT_FOR_STATE")
        fi

        if oci_exec "${cmd[@]}" > /dev/null; then
            log_info "  [OK] Credentials updated successfully"
            return 0
        else
            log_error "  [ERROR] Failed to update credentials"
            return 1
        fi
    else
        log_info "  (Dry-run - no changes applied)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrates credential updates
# Returns.: 0 on success, 1 if any errors occurred
# Output..: Progress messages and summary statistics
# Notes...: Resolves credentials and processes targets
# ------------------------------------------------------------------------------
do_work() {
    local success_count=0 error_count=0 matched_count=0
    local json_data

    # Show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    # Resolve and validate credentials
    resolve_credentials
    create_temp_cred_json

    # Ensure cleanup on exit
    trap cleanup_temp_files EXIT

    if [[ -n "$TARGETS" ]]; then
        log_info "Processing specific targets..."
    else
        log_info "Processing targets from compartment scope..."
    fi

    json_data=$(ds_collect_targets "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER") || die "Failed to collect targets"

    local total_count
    total_count=$(echo "$json_data" | jq '.data | length')
    log_info "Found $total_count targets to process"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found"
        return 0
    fi

    local current=0
    while read -r target_ocid target_name; do
        current=$((current + 1))
        log_info "[$current/$total_count] Processing: $target_name"
        matched_count=$((matched_count + 1))

        if update_target_credentials "$target_ocid" "$target_name"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name"] | @tsv')

    if [[ -n "$TARGET_FILTER" && $matched_count -eq 0 ]]; then
        die "No targets matched filter regex: $TARGET_FILTER" 1
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

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Returns.: 0 on success, 1 on error
# Notes...: Initializes configuration, validates inputs, and executes work
# ------------------------------------------------------------------------------
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
