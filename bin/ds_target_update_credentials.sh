#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_credentials.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
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
: "${LIFECYCLE_STATE:=}"
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${ALLOW_STALE_SELECTION:=false}"
: "${MAX_SNAPSHOT_AGE:=24h}"
: "${DS_USER:=${DATASAFE_USER:-}}"
: "${DS_SECRET:=${DATASAFE_SECRET:-}}"
: "${NO_PROMPT:=false}"
: "${CRED_FILE:=}"
: "${DATASAFE_SECRET_FILE:=}"
: "${RUN_ROOT:=false}"
: "${COMMON_USER_PREFIX:=C##}"
: "${DS_TARGET_NAME_CDBROOT_REGEX:=_(CDB\\\$ROOT|CDBROOT)$}"
: "${APPLY_CHANGES:=false}"
: "${FORCE_UPDATE:=true}"
: "${WAIT_FOR_STATE:=}" # Empty = async (no wait); "ACCEPTED" or other for sync wait
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

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
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
        --log-file FILE         Log to file

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file

  Selection:
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                   Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex (substring match)
    -L, --lifecycle STATE       Filter by lifecycle state (default: all selected targets)
        --input-json FILE       Read targets from local JSON (array or {data:[...]})
        --save-json FILE        Save selected target JSON payload
        --allow-stale-selection Allow --apply with --input-json
                    (disabled by default for safety)
        --max-snapshot-age AGE  Max input-json age (default: ${MAX_SNAPSHOT_AGE})
                    Examples: 900, 30m, 24h, 2d, off

  Credentials:
    -U, --ds-user USER          Database username (default: ${DS_USER:-not set})
    -P, --ds-secret VALUE       Database secret (plain or base64)
        --secret-file FILE      Base64 secret file (optional)
        --cred-file FILE        JSON file with {\"userName\": \"user\", \"password\": \"pass\"}
        --root                  Force common-user prefix for all targets (${COMMON_USER_PREFIX})
                                (root targets are auto-prefixed even without --root)
        --no-prompt             Fail instead of prompting for missing secret

  Execution:
        --apply                 Apply changes (default: dry-run only)
        --force                 Pass --force to OCI update (enabled by default with --apply)
        --no-force              Disable --force (allows OCI interactive confirmation prompts)
    -n, --dry-run               Dry-run mode (show what would be done)
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
        ${SCRIPT_NAME} --cred-file creds.json --apply --force

    # Apply changes and wait for completion
        ${SCRIPT_NAME} --cred-file creds.json --apply --force --wait-for-state ACCEPTED

    # Update specific targets with username/secret
        ${SCRIPT_NAME} -T target1,target2 -U myuser -P mysecret --apply --force

    # Bulk update for compartment (interactive secret, wait for state)
    ${SCRIPT_NAME} -c my-compartment -U dbuser --apply --wait-for-state ACCEPTED

    # Dry-run from saved target selection JSON
    ${SCRIPT_NAME} --input-json ./target_selection.json -U dbuser --dry-run

    # Apply from saved target selection JSON (requires explicit safeguard override)
    ${SCRIPT_NAME} --input-json ./target_selection.json -U dbuser --apply --allow-stale-selection

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
    set -- "${ARGS[@]-}"

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
            --input-json)
                need_val "$1" "${2:-}"
                INPUT_JSON="$2"
                shift 2
                ;;
            --save-json)
                need_val "$1" "${2:-}"
                SAVE_JSON="$2"
                shift 2
                ;;
            --allow-stale-selection)
                ALLOW_STALE_SELECTION=true
                shift
                ;;
            --max-snapshot-age)
                need_val "$1" "${2:-}"
                MAX_SNAPSHOT_AGE="$2"
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
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            --no-force)
                FORCE_UPDATE=false
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
resolve_base_ds_user() {
    local base_user="$DS_USER"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_user" == ${COMMON_USER_PREFIX}* ]]; then
        base_user="${base_user#${COMMON_USER_PREFIX}}"
    fi

    printf '%s' "$base_user"
}

# ------------------------------------------------------------------------------
# Function: target_is_root
# Purpose.: Determine if target display-name represents CDB root
# Args....: $1 - target display name
# Returns.: 0 for root targets, 1 otherwise
# ------------------------------------------------------------------------------
target_is_root() {
    local target_name="$1"
    [[ "$target_name" =~ $DS_TARGET_NAME_CDBROOT_REGEX ]]
}

# ------------------------------------------------------------------------------
# Function: resolve_ds_user_for_target
# Purpose.: Resolve Data Safe username per target (auto-root aware)
# Args....: $1 - target display name
# Returns.: 0 on success
# Output..: Username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user_for_target() {
    local target_name="$1"
    local base_user
    base_user=$(resolve_base_ds_user)

    if [[ "$RUN_ROOT" == "true" ]] || target_is_root "$target_name"; then
        if [[ -n "$COMMON_USER_PREFIX" ]]; then
            printf '%s' "${COMMON_USER_PREFIX}${base_user}"
            return 0
        fi
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

    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        ds_validate_input_json_freshness "$INPUT_JSON" "$MAX_SNAPSHOT_AGE" || die "Input JSON snapshot freshness check failed"

        if [[ "$APPLY_CHANGES" == "true" && "$ALLOW_STALE_SELECTION" != "true" ]]; then
            die "Refusing --apply with --input-json without --allow-stale-selection"
        fi

        if [[ "$SELECT_ALL" == "true" || -n "$COMPARTMENT" || -n "$TARGETS" ]]; then
            log_warn "Ignoring --all/--compartment/--targets when --input-json is provided"
        fi

        if [[ "$APPLY_CHANGES" == "true" ]]; then
            require_oci_cli
        fi
    else
        require_oci_cli

        COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"
    fi
    require_cmd base64

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

    DS_USER="$(resolve_base_ds_user)"

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
    local user_name="${1:-$DS_USER}"

    if [[ -z "$TMP_CRED_JSON" || ! -f "$TMP_CRED_JSON" ]]; then
        TMP_CRED_JSON=$(mktemp)
    fi

    ds_write_cred_json_file "$TMP_CRED_JSON" "$user_name" "$DS_SECRET"
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

is_updatable_lifecycle_state() { ds_is_updatable_lifecycle_state "$@"; }

# ----------------------------------------------------------------------------
# Function: update_target_credentials
# Purpose.: Update credentials for a single target
# Args....: $1 - target OCID
#           $2 - target name
#           $3 - lifecycle state
# Returns.: 0 on success, 1 on error
# Output..: Progress and status messages
# ------------------------------------------------------------------------------
update_target_credentials() {
    local target_ocid="$1"
    local target_name="$2"
    local lifecycle_state="${3:-UNKNOWN}"
    local target_user
    target_user=$(resolve_ds_user_for_target "$target_name")

    create_temp_cred_json "$target_user"

    log_debug "Processing target: $target_name ($target_ocid)"

    log_info "Target: $target_name"
    log_info "  User: $target_user"
    log_info "  Secret: [hidden]"
    log_debug "  Lifecycle state: $lifecycle_state"

    if ! is_updatable_lifecycle_state "$lifecycle_state"; then
        log_warn "  [SKIP] Target lifecycle-state '$lifecycle_state' is not updatable (must be ACTIVE or NEEDS_ATTENTION)"
        return 2
    fi

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating credentials..."

        # Re-check current state to avoid transient failures when target state
        # changed after list collection.
        local current_state
        current_state=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_ocid" \
            --query 'data."lifecycle-state"' \
            --raw-output 2> /dev/null || echo "$lifecycle_state")

        if ! is_updatable_lifecycle_state "$current_state"; then
            log_warn "  [SKIP] Current lifecycle-state '$current_state' is not updatable (must be ACTIVE or NEEDS_ATTENTION)"
            return 2
        fi

        # Build OCI command
        local -a cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --credentials "file://${TMP_CRED_JSON}"
        )

        if [[ "$FORCE_UPDATE" == "true" ]]; then
            cmd+=(--force)
        fi

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
    local success_count=0 error_count=0 skipped_count=0 matched_count=0
    local json_data

    # Show mode
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
        [[ "$FORCE_UPDATE" == "true" ]] && log_info "Force mode enabled for OCI update"
        [[ "$FORCE_UPDATE" != "true" ]] && log_warn "Force mode disabled; OCI may prompt for confirmation"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    # Resolve and validate credentials
    resolve_credentials
    # Ensure cleanup on exit
    trap cleanup_temp_files EXIT

    if [[ -n "$TARGETS" ]]; then
        log_info "Processing specific targets..."
    else
        log_info "Processing targets from compartment scope..."
    fi

    json_data=$(ds_collect_targets_source "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER" "$INPUT_JSON" "$SAVE_JSON") || die "Failed to collect targets"

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
    while read -r target_ocid target_name lifecycle_state; do
        current=$((current + 1))
        log_info "[$current/$total_count] Processing: $target_name"
        matched_count=$((matched_count + 1))

        if update_target_credentials "$target_ocid" "$target_name" "$lifecycle_state"; then
            success_count=$((success_count + 1))
        elif [[ $? -eq 2 ]]; then
            skipped_count=$((skipped_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done < <(echo "$json_data" | jq -r '.data[] | [.id, ."display-name", (."lifecycle-state" // "UNKNOWN")] | @tsv')

    if [[ -n "$TARGET_FILTER" && $matched_count -eq 0 ]]; then
        die "No targets matched filter regex: $TARGET_FILTER" 1
    fi

    # Summary
    log_info "Credential update completed:"
    log_info "  Successful: $success_count"
    log_info "  Skipped: $skipped_count"
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
