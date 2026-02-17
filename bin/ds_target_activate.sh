#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_activate.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Activate inactive Oracle Data Safe target databases
# Usage......: ds_target_activate.sh [OPTIONS] [TARGETS...]
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/ds_lib.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${LIFECYCLE_STATE:=INACTIVE}"
: "${DRY_RUN:=false}"
: "${APPLY_CHANGES:=false}"
: "${WAIT_FOR_STATE:=}"
: "${DS_SECRET:=${DATASAFE_SECRET:-${DS_PASSWORD:-}}}"
: "${DS_USER:=DS_ADMIN}"
: "${DATASAFE_SECRET_FILE:=${DATASAFE_PASSWORD_FILE:-}}"
: "${RUN_ROOT:=false}"
: "${COMMON_USER_PREFIX:=C##}"
: "${NO_PROMPT:=false}"

# Counters
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Temporary credential files
TMP_CRED_JSON=""
TMP_CDB_CRED_JSON=""

# Resolved users by scope
DS_USER_PDB=""
DS_USER_ROOT=""

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
Usage: ${SCRIPT_NAME} [OPTIONS] [TARGETS...]

Description:
  Activate inactive Oracle Data Safe target databases by updating their
    credentials. Uses one Data Safe user/secret model with scope normalization.
  
    Provide either explicit targets or a compartment to activate INACTIVE targets.

Options:
  Common:
    -h, --help              Show this help message
    -V, --version           Show version
    -v, --verbose           Enable verbose output
    -d, --debug             Enable debug output
    --log-file FILE         Log to file

  OCI:
    --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE})
    --oci-region REGION     OCI region
    --oci-config FILE       OCI config file (default: ${OCI_CLI_CONFIG_FILE})

  Target Selection:
    -c, --compartment ID    Compartment OCID or name
    -T, --targets LIST      Comma-separated target names or OCIDs
    -L, --lifecycle STATE   Filter by lifecycle state (default: INACTIVE)

  Execution:
    --apply                 Apply changes (default: dry-run only)
    -n, --dry-run           Dry-run mode (show what would be done)
    --wait-for-state STATE  Wait for operation completion with state (e.g., ACCEPTED)
                            Default: async (no wait)

  Credentials:
    -U, --ds-user USER      Data Safe database user (default: DS_ADMIN)
    -P, --ds-secret VALUE   Data Safe secret (plain or base64)
    --secret-file FILE      Base64 secret file (optional)
    --root                  Root normalization hint (common user with ${COMMON_USER_PREFIX})

Credential Sources (in order of precedence):
    1. Command-line options (-P/--ds-secret, --secret-file)
    2. Environment variables (DS_SECRET/DATASAFE_SECRET)
    3. Secret file (<user>_pwd.b64 in ORADBA_ETC or $ODB_DATASAFE_BASE/etc)
    4. Interactive prompt

CDB\$ROOT Detection:
  Targets are identified as CDB\$ROOT using (in order):
  1. Target name ending with "_CDBROOT" (e.g., exa101r04c01_cdb10b01_CDBROOT)
  2. Tag "DBSec.Container: CDBROOT"
  3. Tag "DBSec.ContainerType: cdbroot"

Examples:
    # Activate all INACTIVE targets (will prompt for secret)
  ${SCRIPT_NAME}

    # Activate with secret from command line
    ${SCRIPT_NAME} -P 'my_secret'

  # Activate specific compartment
    ${SCRIPT_NAME} -c MyCompartment -P 'my_secret'

  # Activate specific targets (dry-run)
    ${SCRIPT_NAME} -T target1,target2 -P 'my_secret' --dry-run

    # Use root normalization hint for common user naming
    ${SCRIPT_NAME} --root -U DS_ADMIN -P 'my_secret' -T mydb_CDBROOT

  # Activate with progress monitoring
    ${SCRIPT_NAME} --wait -P 'my_secret'

  # Use environment variables
    export DS_SECRET='my_secret'
  ${SCRIPT_NAME}

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
            --apply)
                APPLY_CHANGES=true
                DRY_RUN=false
                shift
                ;;
            -U | --ds-user)
                need_val "$1" "${2:-}"
                DS_USER="$2"
                shift 2
                ;;
            -P | --ds-secret | --ds-password)
                need_val "$1" "${2:-}"
                DS_SECRET="$2"
                if [[ "$1" == "--ds-password" ]]; then
                    log_warn "Option --ds-password is deprecated, use --ds-secret"
                fi
                shift 2
                ;;
            --secret-file)
                need_val "$1" "${2:-}"
                DATASAFE_SECRET_FILE="$2"
                shift 2
                ;;
            --root)
                RUN_ROOT=true
                shift
                ;;
            --wait-for-state)
                need_val "$1" "${2:-}"
                WAIT_FOR_STATE="$2"
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
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Positional args become targets
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args: ${remaining[*]}"
        fi
    fi
}

# Function: resolve_ds_user
# Purpose.: Resolve Data Safe username for scope
# Args....: $1 - Scope label (PDB or ROOT)
# Returns.: 0 on success
# Output..: Username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user() {
    local scope="$1"
    local base_user="$DS_USER"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_user" == ${COMMON_USER_PREFIX}* ]]; then
        base_user="${base_user#${COMMON_USER_PREFIX}}"
    fi

    if [[ "$scope" == "ROOT" ]]; then
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
# Notes...: Checks for required commands and resolves secret sources
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_cmd oci jq

    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        usage
    fi

    DS_USER_PDB="$(resolve_ds_user "PDB")"
    DS_USER_ROOT="$(resolve_ds_user "ROOT")"

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
        local primary_user="$DS_USER_PDB"
        local secondary_user="$DS_USER_ROOT"

        if [[ "$RUN_ROOT" == "true" ]]; then
            primary_user="$DS_USER_ROOT"
            secondary_user="$DS_USER_PDB"
        fi

        if secret_file=$(find_password_file "$primary_user" "${DATASAFE_SECRET_FILE:-}"); then
            require_cmd base64
            DS_SECRET=$(decode_base64_file "$secret_file") || die "Failed to decode base64 secret file: $secret_file"
            DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")
            [[ -n "$DS_SECRET" ]] || die "Secret file is empty: $secret_file"
            log_info "Loaded Data Safe secret from file: $secret_file"
        elif [[ -z "${DATASAFE_SECRET_FILE:-}" ]] && secret_file=$(find_password_file "$secondary_user"); then
            require_cmd base64
            DS_SECRET=$(decode_base64_file "$secret_file") || die "Failed to decode base64 secret file: $secret_file"
            DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")
            [[ -n "$DS_SECRET" ]] || die "Secret file is empty: $secret_file"
            log_info "Loaded Data Safe secret from alternate user file: $secret_file"
        fi
    fi

    if [[ -z "$DS_SECRET" ]]; then
        if [[ "${NO_PROMPT}" == "true" ]]; then
            die "Data Safe secret not provided and prompting is disabled. Use -P/--ds-secret, --secret-file, or DS_SECRET."
        fi

        local prompt_user="$DS_USER_PDB"
        if [[ "$RUN_ROOT" == "true" ]]; then
            prompt_user="$DS_USER_ROOT"
        fi
        log_info "Data Safe secret not provided, prompting..."
        echo -n "Enter secret for user '$prompt_user': " >&2
        read -rs DS_SECRET
        echo >&2
        DS_SECRET=$(trim_trailing_crlf "$DS_SECRET")

        [[ -n "$DS_SECRET" ]] || die "Data Safe secret cannot be empty"
    fi

    log_info "Using credentials - PDB user: $DS_USER_PDB, CDB\$ROOT user: $DS_USER_ROOT"
}

# ------------------------------------------------------------------------------
# Function: create_temp_cred_json
# Purpose.: Create temporary JSON credential files for PDB and CDB
# Returns.: 0 on success
# Notes...: Sets TMP_CRED_JSON and TMP_CDB_CRED_JSON global variables
# ------------------------------------------------------------------------------
create_temp_cred_json() {
    # Create PDB credentials file
    TMP_CRED_JSON=$(mktemp)
    jq -n \
        --arg user "$DS_USER_PDB" \
        --arg pass "$DS_SECRET" \
        '{userName: $user, password: $pass}' > "$TMP_CRED_JSON"
    log_debug "Created PDB credentials file: $TMP_CRED_JSON"

    # Create CDB credentials file
    TMP_CDB_CRED_JSON=$(mktemp)
    jq -n \
        --arg user "$DS_USER_ROOT" \
        --arg pass "$DS_SECRET" \
        '{userName: $user, password: $pass}' > "$TMP_CDB_CRED_JSON"
    log_debug "Created CDB credentials file: $TMP_CDB_CRED_JSON"
}

# ------------------------------------------------------------------------------
# Function: cleanup_temp_files
# Purpose.: Clean up temporary credential files
# Returns.: 0 on success
# ------------------------------------------------------------------------------
cleanup_temp_files() {
    if [[ -n "$TMP_CRED_JSON" && -f "$TMP_CRED_JSON" ]]; then
        log_debug "Cleaning up PDB credentials file"
        rm -f "$TMP_CRED_JSON"
        TMP_CRED_JSON=""
    fi

    if [[ -n "$TMP_CDB_CRED_JSON" && -f "$TMP_CDB_CRED_JSON" ]]; then
        log_debug "Cleaning up CDB credentials file"
        rm -f "$TMP_CDB_CRED_JSON"
        TMP_CDB_CRED_JSON=""
    fi
}

# ------------------------------------------------------------------------------
# Function: is_cdb_root
# Purpose.: Detect if target is a CDB$ROOT target
# Args....: $1 - target name
#           $2 - target OCID
# Returns.: 0 if CDB$ROOT, 1 if PDB
# Notes...: Checks name first (fast), then tags (slower)
# ------------------------------------------------------------------------------
is_cdb_root() {
    local target_name="$1"
    local target_ocid="$2"

    # First check: name ends with _CDBROOT (fast)
    if [[ "$target_name" =~ _CDBROOT$ ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (name pattern)"
        return 0
    fi

    # Fallback: check tags (slower)
    log_debug "Checking tags for target: $target_name"
    local target_json
    target_json=$(oci_exec_ro data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data' 2> /dev/null) || {
        log_debug "Failed to get target details for tag check"
        return 1
    }

    # Check for DBSec.Container: CDBROOT
    local container_tag
    container_tag=$(echo "$target_json" | jq -r '."freeform-tags"."DBSec.Container" // ""')
    if [[ "${container_tag^^}" == "CDBROOT" ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (tag DBSec.Container)"
        return 0
    fi

    # Check for DBSec.ContainerType: cdbroot
    local container_type_tag
    container_type_tag=$(echo "$target_json" | jq -r '."freeform-tags"."DBSec.ContainerType" // ""')
    if [[ "${container_type_tag^^}" == "CDBROOT" ]]; then
        log_debug "Target '$target_name' identified as CDB\$ROOT (tag DBSec.ContainerType)"
        return 0
    fi

    log_debug "Target '$target_name' identified as PDB (default)"
    return 1
}

# ------------------------------------------------------------------------------
# Function: activate_single_target
# Purpose.: Activate a single Data Safe target database
# Args....: $1 - Target OCID
#           $2 - Current target number (optional, default: 1)
#           $3 - Total targets (optional, default: 1)
# Returns.: 0 on success, 1 on error
# Output..: Progress and status messages to stdout/stderr
# Notes...: Updates SUCCESS_COUNT or FAILED_COUNT counters
# ------------------------------------------------------------------------------
activate_single_target() {
    local target_ocid="$1"
    local current="${2:-1}"
    local total="${3:-1}"
    local target_name

    target_name=$(ds_resolve_target_name "$target_ocid" 2> /dev/null) || {
        log_error "Failed to resolve target name: $target_ocid"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    }

    # Detect if this is a CDB$ROOT target
    local cred_file
    local cred_type
    if is_cdb_root "$target_name" "$target_ocid"; then
        cred_file="$TMP_CDB_CRED_JSON"
        cred_type="CDB\$ROOT"
    else
        cred_file="$TMP_CRED_JSON"
        cred_type="PDB"
    fi

    if [[ "${APPLY_CHANGES}" != "true" ]]; then
        log_info "[$current/$total] [DRY-RUN] Would activate $cred_type: $target_name (user: $(jq -r '.userName' "$cred_file"))"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    fi

    log_info "[$current/$total] Activating $cred_type: $target_name (user: $(jq -r '.userName' "$cred_file"))"

    # Update credentials
    local -a cmd=(
        data-safe target-database update
        --target-database-id "$target_ocid"
        --credentials "file://${cred_file}"
        --force
    )

    if [[ -n "$WAIT_FOR_STATE" ]]; then
        cmd+=(--wait-for-state "$WAIT_FOR_STATE")
    fi

    if oci_exec "${cmd[@]}" > /dev/null 2>&1; then
        log_debug "✓ Successfully activated: $target_name"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        log_error "✗ Failed to activate: $target_name"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - discovers and activates target databases
# Returns.: 0 on success, exits with error if targets fail
# Output..: Progress messages and summary statistics to stdout/stderr
# Notes...: Orchestrates target discovery, activation operations, and reporting
# ------------------------------------------------------------------------------
do_work() {
    local -a target_ocids=()

    if [[ "${APPLY_CHANGES}" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
    fi

    # Create credential files
    create_temp_cred_json

    # Setup cleanup trap
    trap cleanup_temp_files EXIT

    # Collect target OCIDs
    if [[ -n "$TARGETS" ]]; then
        # Process explicit targets
        IFS=',' read -ra target_list <<< "$TARGETS"
        for target in "${target_list[@]}"; do
            target="${target// /}" # trim spaces

            if is_ocid "$target"; then
                target_ocids+=("$target")
            else
                if [[ -z "$COMPARTMENT" ]]; then
                    die "Target name '$target' requires --compartment for resolution"
                fi
                # Resolve name to OCID using resolved compartment
                log_debug "Resolving target name: $target"
                local resolved
                resolved=$(ds_resolve_target_ocid "$target" "$COMPARTMENT") || die "Failed to resolve target: $target"

                if [[ -z "$resolved" ]]; then
                    die "Target not found: $target"
                fi

                target_ocids+=("$resolved")
            fi
        done
    elif [[ -n "$COMPARTMENT" ]]; then
        # List targets from compartment
        log_info "Discovering targets in compartment: $COMPARTMENT (lifecycle: $LIFECYCLE_STATE)"

        local comp_ocid
        comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT")

        local targets_json
        targets_json=$(ds_list_targets "$comp_ocid" "$LIFECYCLE_STATE")

        # Extract OCIDs
        mapfile -t target_ocids < <(echo "$targets_json" | jq -r '.data[].id')

        local count=${#target_ocids[@]}
        if [[ $count -eq 0 ]]; then
            log_warn "No targets found matching criteria"
            return 0
        fi

        log_info "Found $count targets to activate"
    fi

    # Activate each target
    local total=${#target_ocids[@]}
    local current=0

    for target_ocid in "${target_ocids[@]}"; do
        current=$((current + 1))
        activate_single_target "$target_ocid" "$current" "$total"
    done

    # Print summary
    echo ""
    log_info "====== Activation Summary ======"
    log_info "Total targets:    $total"
    log_info "Successful:       $SUCCESS_COUNT"
    log_info "Failed:           $FAILED_COUNT"
    log_info "Skipped:          $SKIPPED_COUNT"
    log_info "================================"

    # Exit with error if any failed
    if [[ $FAILED_COUNT -gt 0 ]]; then
        die "Some targets failed to activate" 10
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
# Notes...: Initializes configuration, validates inputs, and executes work
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    init_config "${SCRIPT_NAME}.conf"
    if [[ $# -eq 0 ]]; then
        usage
    fi
    parse_args "$@"
    validate_inputs
    do_work

    log_info "Activation completed successfully"
}

# Handle --help before setting up error traps (to avoid trap issues with exit)
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        usage
    fi
done

# Setup error handling before main execution
setup_error_handling

main "$@"

# Explicit exit to prevent spurious error trap
exit 0
