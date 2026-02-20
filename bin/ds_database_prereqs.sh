#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_database_prereqs.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Run Data Safe prereqs locally for one database scope
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -euo pipefail

# =============================================================================
# BOOTSTRAP
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
readonly SCRIPT_PATH

SCRIPT_VERSION="0.9.1"
readonly SCRIPT_VERSION

# =============================================================================
# LOGGING
# =============================================================================

: "${LOG_LEVEL:=INFO}"
: "${LOG_FILE:=}"

# ------------------------------------------------------------------------------
# Function: _log_level_num
# Purpose.: Map log level string to numeric severity
# Args....: $1 - Log level string
# Returns.: 0 on success
# Output..: Numeric log level to stdout
# ------------------------------------------------------------------------------
_log_level_num() {
    case "${1^^}" in
        TRACE) echo 0 ;;
        DEBUG) echo 1 ;;
        INFO) echo 2 ;;
        WARN) echo 3 ;;
        ERROR) echo 4 ;;
        FATAL) echo 5 ;;
        *) echo 2 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: log
# Purpose.: Emit a formatted log line
# Args....: $1 - Log level
#           $2 - Message (remaining args)
# Returns.: 0 on success, exits on FATAL
# Output..: Log line to stderr and optional log file
# ------------------------------------------------------------------------------
log() {
    local level="${1^^}"
    shift
    local msg="$*"

    local level_num
    level_num=$(_log_level_num "$level")
    local current_level_num
    current_level_num=$(_log_level_num "$LOG_LEVEL")

    [[ $level_num -lt $current_level_num ]] && return 0

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted="[${timestamp}] [${level}] ${msg}"

    echo "$formatted" >&2
    [[ -n "$LOG_FILE" ]] && echo "$formatted" >> "$LOG_FILE"

    [[ "$level" == "FATAL" ]] && exit 1

    return 0
}

# ------------------------------------------------------------------------------
# Function: log_trace
# Purpose.: TRACE log wrapper
# Args....: $@ - Message
# Returns.: 0 on success
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_trace() { log TRACE "$@"; }

# ------------------------------------------------------------------------------
# Function: log_debug
# Purpose.: DEBUG log wrapper
# Args....: $@ - Message
# Returns.: 0 on success
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_debug() { log DEBUG "$@"; }

# ------------------------------------------------------------------------------
# Function: log_info
# Purpose.: INFO log wrapper
# Args....: $@ - Message
# Returns.: 0 on success
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_info() { log INFO "$@"; }

# ------------------------------------------------------------------------------
# Function: log_warn
# Purpose.: WARN log wrapper
# Args....: $@ - Message
# Returns.: 0 on success
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_warn() { log WARN "$@"; }

# ------------------------------------------------------------------------------
# Function: log_error
# Purpose.: ERROR log wrapper
# Args....: $@ - Message
# Returns.: 0 on success
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_error() { log ERROR "$@"; }

# ------------------------------------------------------------------------------
# Function: log_fatal
# Purpose.: FATAL log wrapper
# Args....: $@ - Message
# Returns.: Exits on FATAL
# Output..: Log line to stderr
# ------------------------------------------------------------------------------
log_fatal() { log FATAL "$@"; }

# ------------------------------------------------------------------------------
# Function: is_verbose
# Purpose.: Check for verbose logging
# Args....: None
# Returns.: 0 if verbose, 1 otherwise
# Output..: None
# ------------------------------------------------------------------------------
is_verbose() {
    [[ "${LOG_LEVEL^^}" == "DEBUG" || "${LOG_LEVEL^^}" == "TRACE" ]]
}

# ------------------------------------------------------------------------------
# Function: die
# Purpose.: Log an error and exit
# Args....: $1 - Error message
#           $2 - Exit code (optional)
# Returns.: Exits with code
# Output..: Error log to stderr
# ------------------------------------------------------------------------------
die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# =============================================================================
# HELPERS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: need_val
# Purpose.: Validate that an option value is present
# Args....: $1 - Flag name
#           $2 - Value
# Returns.: 0 on success, exits on error
# Output..: Error log on failure
# ------------------------------------------------------------------------------
need_val() {
    local flag="$1"
    local val="${2:-}"
    if [[ -z "$val" || "$val" == -* ]]; then
        die "Option ${flag} requires a value"
    fi
}

# ------------------------------------------------------------------------------
# Function: require_cmd
# Purpose.: Ensure required commands are available
# Args....: $@ - Command names
# Returns.: 0 on success, exits on error
# Output..: Error log on failure
# ------------------------------------------------------------------------------
require_cmd() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: require_var
# Purpose.: Ensure required variables are set
# Args....: $@ - Variable names
# Returns.: 0 on success, exits on error
# Output..: Error log on failure
# ------------------------------------------------------------------------------
require_var() {
    local missing=()
    local var
    for var in "$@"; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required variables: ${missing[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: parse_common_opts
# Purpose.: Parse common CLI flags
# Args....: $@ - Command-line arguments
# Returns.: 0 on success
# Output..: Usage/version text as needed
# ------------------------------------------------------------------------------
parse_common_opts() {
    ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                ;;
            -V | --version)
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
                exit 0
                ;;
            -v | --verbose)
                LOG_LEVEL=DEBUG
                shift
                ;;
            -d | --debug)
                LOG_LEVEL=TRACE
                shift
                ;;
            -q | --quiet)
                LOG_LEVEL=WARN
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --log-file)
                need_val "$1" "${2:-}"
                LOG_FILE="$2"
                shift 2
                ;;
            --no-color)
                shift
                ;;
            --)
                shift
                ARGS+=("$@")
                break
                ;;
            *)
                ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Function: decode_base64_file
# Purpose.: Decode base64 file content with compatible flags
# Args....: $1 - File path
# Returns.: 0 on success, 1 on failure
# Output..: Decoded content to stdout
# ------------------------------------------------------------------------------
decode_base64_file() {
    local file="$1"

    if base64 --decode < "$file" 2> /dev/null; then
        return 0
    fi
    if base64 -d < "$file" 2> /dev/null; then
        return 0
    fi
    if base64 -D < "$file" 2> /dev/null; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: decode_base64_string
# Purpose.: Decode base64 string content with compatible flags
# Args....: $1 - Base64 string
# Returns.: 0 on success, 1 on failure
# Output..: Decoded content to stdout
# ------------------------------------------------------------------------------
decode_base64_string() {
    local input="$1"

    if printf '%s' "$input" | base64 --decode 2> /dev/null; then
        return 0
    fi
    if printf '%s' "$input" | base64 -d 2> /dev/null; then
        return 0
    fi
    if printf '%s' "$input" | base64 -D 2> /dev/null; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function: is_base64_string
# Purpose.: Check whether a string is valid base64-encoded content
# Args....: $1 - Candidate string
# Returns.: 0 if base64, 1 otherwise
# Output..: None
# Notes...: Performs a strict round-trip (decode then re-encode) check
# ------------------------------------------------------------------------------
is_base64_string() {
    local input="$1"
    local normalized

    normalized=$(printf '%s' "$input" | tr -d '\n\r ')
    [[ -n "$normalized" ]] || return 1

    if [[ ! "$normalized" =~ ^[A-Za-z0-9+/=]+$ ]]; then
        return 1
    fi

    if ((${#normalized} % 4 != 0)); then
        return 1
    fi

    local decoded
    decoded=$(decode_base64_string "$normalized") || return 1

    local reencoded
    reencoded=$(printf '%s' "$decoded" | base64 2> /dev/null | tr -d '\n\r ')
    [[ "$reencoded" == "$normalized" ]]
}

# ------------------------------------------------------------------------------
# Function: find_pass_file
# Purpose.: Find the Data Safe secret file
# Args....: $1 - Username
#           $2 - Explicit file path (optional)
# Returns.: 0 if found, 1 otherwise
# Output..: Secret file path to stdout
# ------------------------------------------------------------------------------
find_pass_file() {
    local username="$1"
    local explicit_file="${2:-}"
    local filename="${username}_pwd.b64"

    if [[ -n "$explicit_file" ]]; then
        [[ -f "$explicit_file" ]] && {
            echo "$explicit_file"
            return 0
        }
        return 1
    fi

    if [[ -n "${ORADBA_ETC:-}" && -f "${ORADBA_ETC}/${filename}" ]]; then
        echo "${ORADBA_ETC}/${filename}"
        return 0
    fi

    if [[ -n "${ODB_DATASAFE_BASE:-}" && -f "${ODB_DATASAFE_BASE}/etc/${filename}" ]]; then
        echo "${ODB_DATASAFE_BASE}/etc/${filename}"
        return 0
    fi

    if [[ -f "${PWD}/${filename}" ]]; then
        echo "${PWD}/${filename}"
        return 0
    fi

    return 1
}

# =============================================================================
# DEFAULTS
# =============================================================================

: "${DRY_RUN:=false}"
: "${CHECK_ONLY:=false}"
: "${DROP_USER:=false}"

: "${RUN_ALL:=false}"
: "${PDB:=}"
: "${PDBS:=}"
: "${RUN_ROOT:=false}"

: "${USE_EMBEDDED:=false}"

: "${SQL_DIR:=}"
: "${PREREQ_SQL:=create_ds_admin_prerequisites.sql}"
: "${USER_SQL:=create_ds_admin_user.sql}"
: "${GRANTS_SQL:=datasafe_privileges.sql}"

: "${DATASAFE_USER:=DS_ADMIN}"
: "${DATASAFE_PASS:=}"
: "${DATASAFE_PASS_FILE:=}"
: "${DS_PROFILE:=DS_USER_PROFILE}"
: "${DS_FORCE:=false}"
: "${DS_UPDATE_SECRET:=false}"
: "${DS_GRANT_TYPE:=GRANT}"
: "${DS_GRANT_MODE:=ALL}"
: "${COMMON_USER_PREFIX:=C##}"
: "${USER_ACTION:=}"

TEMP_FILES=()

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Remove temporary files recorded during execution
# Args....: None
# Returns.: 0 on success
# Output..: None
# ------------------------------------------------------------------------------
cleanup() {
    local file=""
    for file in "${TEMP_FILES[@]:-}"; do
        [[ -n "$file" && -e "$file" ]] && rm -rf "$file"
    done
}

# ------------------------------------------------------------------------------
# Function: has_embedded_sql
# Purpose.: Detect embedded SQL payload marker
# Args....: None
# Returns.: 0 if payload exists, 1 otherwise
# Output..: None
# ------------------------------------------------------------------------------
has_embedded_sql() {
    grep -Eq '^[[:space:]]*__PAYLOAD_BEGINS__[[:space:]]*$' "$SCRIPT_PATH"
}

# ------------------------------------------------------------------------------
# Function: extract_embedded_sql
# Purpose.: Extract embedded SQL payload into a temp directory
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: None (sets SQL_DIR)
# ------------------------------------------------------------------------------
extract_embedded_sql() {
    local temp_dir=""
    local payload_file=""
    local zip_file=""

    temp_dir="$(mktemp -d)"
    payload_file="$(mktemp)"
    zip_file="$(mktemp)"

    TEMP_FILES+=("$temp_dir" "$payload_file" "$zip_file")

    awk '
/^[[:space:]]*__PAYLOAD_BEGINS__[[:space:]]*$/ {flag=1; next}
flag && /^[[:space:]]*__PAYLOAD_END__[[:space:]]*$/ {exit}
flag {
    gsub(/\r$/, "", $0)

    if ($0 ~ /^:[[:space:]]*<<[[:space:]]*["\047]?__PAYLOAD_END__["\047]?[[:space:]]*$/) {
        next
    }

    if ($0 ~ /^[[:space:]]*$/) {
        next
    }

    sub(/^[[:space:]]+/, "", $0)
    sub(/[[:space:]]+$/, "", $0)

    print
}
' "$SCRIPT_PATH" > "$payload_file"

    if [[ ! -s "$payload_file" ]]; then
        die "Embedded SQL payload not found in ${SCRIPT_NAME}."
    fi

    decode_base64_file "$payload_file" > "$zip_file" || die "Failed to decode embedded SQL payload."
    unzip -q "$zip_file" -d "$temp_dir" || die "Failed to extract embedded SQL payload."

    SQL_DIR="$temp_dir"
}

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Args....: None
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Run Data Safe prerequisites locally using the current ORACLE_HOME and
  ORACLE_SID environment. Executes prereq, user, and grant SQL scripts.

Scope (choose one):
        --all                   Target CDB\$ROOT and all OPEN READ WRITE PDBs
        --pdb PDB[,PDB...]      Target one or more PDBs (comma-separated)
        --root                  Target CDB\$ROOT

SQL:
        --sql-dir DIR           Local SQL dir (default: auto-detect)
        --embedded              Use embedded SQL payload
        --prereq FILE           Prereq SQL filename (default: ${PREREQ_SQL})
        --user-sql FILE         Create-user SQL filename (default: ${USER_SQL})
        --grants-sql FILE       Grants SQL filename (default: ${GRANTS_SQL})

Data Safe:
    -U, --ds-user USER          Data Safe user (default: ${DATASAFE_USER})
    -P, --ds-secret VALUE       Data Safe secret (plain or base64)
        --secret-file FILE      Base64 secret file (optional)
        --ds-profile PROFILE    Database profile (default: ${DS_PROFILE})
        --update-secret         Update existing user secret (no drop)
        --force                 Force recreate user if exists
        --grant-type TYPE       Grant type (default: ${DS_GRANT_TYPE})
        --grant-mode MODE       Grant mode (default: ${DS_GRANT_MODE})

User naming behavior:
    - Root scope always uses common user with ${COMMON_USER_PREFIX} prefix.
    - PDB scope always uses local user without ${COMMON_USER_PREFIX}.
    Example: --ds-user C##DS_ADMIN1
        Root: C##DS_ADMIN1
        PDB : DS_ADMIN1
    Example: --ds-user DS_ADMIN2
        Root: C##DS_ADMIN2
        PDB : DS_ADMIN2

User management behavior:
    - Create user if missing (default).
    - Update profile only when user exists (default).
    - Update secret without drop: use --update-secret.
    - Drop and recreate user: use --force.

Modes:
        --check                 Verify user/privileges only (no changes)
        --drop-user             Drop the Data Safe user only (keep profile)
    -n, --dry-run               Show actions without executing

Common:
    -h, --help                  Show this help
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
    -q, --quiet                 Quiet mode
        --log-file FILE         Log to file
        --no-color              Disable colored output

Examples:
    ${SCRIPT_NAME} --root -P "<secret>"
    ${SCRIPT_NAME} --pdb APP1PDB -P "<secret>"
    ${SCRIPT_NAME} --pdb APP1PDB,APP2PDB --force
    ${SCRIPT_NAME} --all --force -P "<secret>"
    ${SCRIPT_NAME} --root --check

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse script-specific command-line arguments
# Args....: $@ - Command-line arguments
# Returns.: 0 on success
# Output..: Warning messages for ignored args
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                RUN_ALL=true
                shift
                ;;
            --pdb)
                need_val "$1" "${2:-}"
                PDBS="$2"
                shift 2
                ;;
            --root)
                RUN_ROOT=true
                shift
                ;;
            --sql-dir)
                need_val "$1" "${2:-}"
                SQL_DIR="$2"
                shift 2
                ;;
            --embedded)
                USE_EMBEDDED=true
                shift
                ;;
            --prereq)
                need_val "$1" "${2:-}"
                PREREQ_SQL="$2"
                shift 2
                ;;
            --user-sql)
                need_val "$1" "${2:-}"
                USER_SQL="$2"
                shift 2
                ;;
            --grants-sql)
                need_val "$1" "${2:-}"
                GRANTS_SQL="$2"
                shift 2
                ;;
            -U | --ds-user)
                need_val "$1" "${2:-}"
                DATASAFE_USER="$2"
                shift 2
                ;;
            -P | --ds-secret)
                need_val "$1" "${2:-}"
                DATASAFE_PASS="$2"
                shift 2
                ;;
            --secret-file)
                need_val "$1" "${2:-}"
                DATASAFE_PASS_FILE="$2"
                shift 2
                ;;
            --ds-profile)
                need_val "$1" "${2:-}"
                DS_PROFILE="$2"
                shift 2
                ;;
            --force)
                DS_FORCE=true
                shift
                ;;
            --update-secret)
                DS_UPDATE_SECRET=true
                shift
                ;;
            --grant-type)
                need_val "$1" "${2:-}"
                DS_GRANT_TYPE="$2"
                shift 2
                ;;
            --grant-mode)
                need_val "$1" "${2:-}"
                DS_GRANT_MODE="$2"
                shift 2
                ;;
            --check)
                CHECK_ONLY=true
                shift
                ;;
            --drop-user)
                DROP_USER=true
                shift
                ;;
            --oci-profile | --oci-region | --oci-config)
                die "OCI options are not supported by this script"
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
        log_warn "Ignoring positional args: ${remaining[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_sql_dir
# Purpose.: Determine SQL directory if not explicitly set
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages for SQL source
# ------------------------------------------------------------------------------
resolve_sql_dir() {
    if [[ "$USE_EMBEDDED" == "true" ]]; then
        if has_embedded_sql; then
            extract_embedded_sql
            log_info "SQL source: embedded payload (extracted to ${SQL_DIR})"
            log_info "SQL files: prereq=${PREREQ_SQL} user=${USER_SQL} grants=${GRANTS_SQL}"
            return 0
        fi
        die "Embedded SQL payload not found in ${SCRIPT_NAME}."
    fi

    if [[ -n "$SQL_DIR" ]]; then
        log_info "SQL source: external dir (explicit) ${SQL_DIR}"
        log_info "SQL files: prereq=${PREREQ_SQL} user=${USER_SQL} grants=${GRANTS_SQL}"
        return 0
    fi

    local candidate_script_dir
    local candidate_parent_sql
    candidate_script_dir="$SCRIPT_DIR"
    candidate_parent_sql="${SCRIPT_DIR}/../sql"

    if [[ -f "${candidate_script_dir}/${PREREQ_SQL}" &&
        -f "${candidate_script_dir}/${USER_SQL}" &&
        -f "${candidate_script_dir}/${GRANTS_SQL}" ]]; then
        SQL_DIR="$candidate_script_dir"
        log_info "SQL source: external dir (script) ${SQL_DIR}"
        log_info "SQL files: prereq=${PREREQ_SQL} user=${USER_SQL} grants=${GRANTS_SQL}"
        return 0
    fi

    if [[ -f "${candidate_parent_sql}/${PREREQ_SQL}" &&
        -f "${candidate_parent_sql}/${USER_SQL}" &&
        -f "${candidate_parent_sql}/${GRANTS_SQL}" ]]; then
        SQL_DIR="$candidate_parent_sql"
        log_info "SQL source: external dir (parent) ${SQL_DIR}"
        log_info "SQL files: prereq=${PREREQ_SQL} user=${USER_SQL} grants=${GRANTS_SQL}"
        return 0
    fi

    if has_embedded_sql; then
        extract_embedded_sql
        log_info "SQL source: embedded payload (fallback, extracted to ${SQL_DIR})"
        log_info "SQL files: prereq=${PREREQ_SQL} user=${USER_SQL} grants=${GRANTS_SQL}"
        return 0
    fi

    die "Missing SQL files in ${candidate_script_dir} and ${candidate_parent_sql} (use --sql-dir)"
}

# ------------------------------------------------------------------------------
# Function: generate_pass
# Purpose.: Generate a random Data Safe secret
# Args....: None
# Returns.: 0 on success
# Output..: Secret string to stdout
# ------------------------------------------------------------------------------
generate_pass() {
    require_cmd openssl tr

    local rand
    rand="$(openssl rand -base64 18 | tr -d '=+/')"
    printf '%s' "${rand}Aa1!"
}

# ------------------------------------------------------------------------------
# Function: pass_file_path
# Purpose.: Resolve the default secret file path
# Args....: $1 - Username
# Returns.: 0 on success
# Output..: File path to stdout
# ------------------------------------------------------------------------------
pass_file_path() {
    local username="$1"
    local filename="${username}_pwd.b64"

    if [[ -n "${ORADBA_ETC:-}" ]]; then
        echo "${ORADBA_ETC}/${filename}"
        return 0
    fi

    if [[ -n "${ODB_DATASAFE_BASE:-}" ]]; then
        echo "${ODB_DATASAFE_BASE}/etc/${filename}"
        return 0
    fi

    echo "${PWD}/${filename}"
}

# ------------------------------------------------------------------------------
# Function: resolve_pass
# Purpose.: Load or generate the Data Safe secret
# Args....: None
# Returns.: 0 on success
# Output..: Log messages; writes secret file as needed
# ------------------------------------------------------------------------------
resolve_pass() {
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return 0
    fi

    if [[ -n "$DATASAFE_PASS" ]]; then
        if is_base64_string "$DATASAFE_PASS"; then
            local decoded
            decoded=$(decode_base64_string "$DATASAFE_PASS") || die "Failed to decode base64 secret"
            [[ -n "$decoded" ]] || die "Decoded secret is empty"
            DATASAFE_PASS="$decoded"
            log_info "Decoded Data Safe secret from base64 input"
        fi
        return 0
    fi

    local secret_file=""
    if secret_file=$(find_pass_file "$DATASAFE_USER" "$DATASAFE_PASS_FILE"); then
        require_cmd base64
        DATASAFE_PASS=$(decode_base64_file "$secret_file") || die "Failed to decode secret file: $secret_file"
        [[ -n "$DATASAFE_PASS" ]] || die "Secret file is empty: $secret_file"
        log_info "Loaded Data Safe secret from file: $secret_file"
        return 0
    fi

    DATASAFE_PASS="$(generate_pass)"
    local output_file
    output_file="$(pass_file_path "$DATASAFE_USER")"
    mkdir -p "$(dirname -- "$output_file")"
    umask 077
    printf '%s' "$DATASAFE_PASS" | base64 > "$output_file"
    log_info "Generated Data Safe secret and wrote: $output_file"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate inputs and resolve SQL/secret sources
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    log_debug "Options: run_all=${RUN_ALL}, run_root=${RUN_ROOT}, pdbs=${PDBS:-}"
    log_debug "SQL_DIR=${SQL_DIR} prereq=${PREREQ_SQL} user_sql=${USER_SQL} grants=${GRANTS_SQL}"
    log_debug "DS user=${DATASAFE_USER} profile=${DS_PROFILE} force=${DS_FORCE} update_secret=${DS_UPDATE_SECRET}"
    log_debug "Modes: check_only=${CHECK_ONLY} drop_user=${DROP_USER}"

    require_cmd sqlplus mktemp base64
    require_var ORACLE_SID
    log_debug "ORACLE_SID=${ORACLE_SID}"

    if [[ "$RUN_ALL" == "true" ]]; then
        if [[ -n "$PDBS" || "$RUN_ROOT" == "true" ]]; then
            die "--all is mutually exclusive with --pdb/--root"
        fi
    else
        if [[ -z "$PDBS" && "$RUN_ROOT" != "true" ]]; then
            die "Specify scope: --pdb <name> OR --root OR --all"
        fi
    fi

    if [[ -n "$PDBS" && "$RUN_ROOT" == "true" ]]; then
        die "Choose exactly one scope: --pdb OR --root"
    fi

    if [[ "$DS_FORCE" == "true" && "$DS_UPDATE_SECRET" == "true" ]]; then
        log_warn "--update-secret ignored because --force is set"
        DS_UPDATE_SECRET=false
    fi

    if [[ "$DROP_USER" == "true" ]]; then
        USER_ACTION="drop user only (keep profile)"
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        USER_ACTION="check only (no changes)"
    elif [[ "$DS_FORCE" == "true" ]]; then
        USER_ACTION="drop/recreate user"
    elif [[ "$DS_UPDATE_SECRET" == "true" ]]; then
        USER_ACTION="update secret (no drop)"
    else
        USER_ACTION="create if missing; update profile only"
    fi

    log_info "User action: ${USER_ACTION}"

    if [[ "$DROP_USER" != "true" ]]; then
        resolve_sql_dir
        [[ -f "${SQL_DIR}/${PREREQ_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${PREREQ_SQL} (use --sql-dir)"
        [[ -f "${SQL_DIR}/${USER_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${USER_SQL} (use --sql-dir)"
        [[ -f "${SQL_DIR}/${GRANTS_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${GRANTS_SQL} (use --sql-dir)"

        resolve_pass
    fi
}

# ------------------------------------------------------------------------------
# Function: build_temp_sql_script
# Purpose.: Build a temporary SQL*Plus script
# Args....: $1 - Base name
#           $2 - SQL spec (path or @INLINE)
#           $3 - SQL args (optional)
# Returns.: 0 on success
# Output..: Temp SQL file path to stdout
# ------------------------------------------------------------------------------
build_temp_sql_script() {
    local base_name="$1"
    local sqlspec="$2"
    shift 2 || true

    local tmp_sql
    tmp_sql="$(mktemp "${TMPDIR:-/tmp}/${base_name}.XXXXXX.sql")"
    TEMP_FILES+=("$tmp_sql")

    local -a args=()
    (($#)) && args=("$@")

    {
        if [[ "${LOG_LEVEL^^}" == "DEBUG" || "${LOG_LEVEL^^}" == "TRACE" ]]; then
            echo "set echo on"
            echo "set termout on"
        elif [[ "${TERMOUT_FORCE:-false}" == "true" ]]; then
            echo "set echo off"
            echo "set termout on"
        else
            echo "set echo off"
            echo "set termout off"
        fi
        echo "set serveroutput on size unlimited"
        echo "whenever sqlerror exit failure"

        if [[ "$RUN_ROOT" != "true" && -n "$PDB" ]]; then
            printf 'alter session set container=%s;%s' "$PDB" $'\n'
        fi

        echo "show con_name"
        echo

        if [[ "$sqlspec" == @INLINE* ]]; then
            local inline="${sqlspec#@INLINE}"
            [[ "$inline" == " "* ]] && inline="${inline# }"
            [[ "$inline" == $'\n'* ]] && inline="${inline#$'\n'}"
            printf '%s\n' "$inline"
        else
            local base
            base="$(basename -- "$sqlspec")"
            local joined=""
            if ((${#args[@]})); then
                printf -v joined ' %s' "${args[@]}"
                joined="${joined:1}"
            fi
            if [[ -n "$joined" ]]; then
                printf '@"%s/%s" %s\n' "${SQL_DIR%/}" "$base" "$joined"
            else
                printf '@"%s/%s"\n' "${SQL_DIR%/}" "$base"
            fi
        fi

        printf 'exit;%s' $'\n'
        echo
    } > "$tmp_sql"

    printf '%s\n' "$tmp_sql"
}

# ------------------------------------------------------------------------------
# Function: run_sql_local
# Purpose.: Execute SQL*Plus locally for a script or inline SQL
# Args....: $1 - SQL spec
#           $2 - SQL args (optional)
# Returns.: 0 on success, 1 on failure
# Output..: SQL*Plus output or error tail
# ------------------------------------------------------------------------------
run_sql_local() {
    local sqlspec="$1"
    shift || true

    local termout_force="false"
    if [[ "$sqlspec" != @INLINE* ]]; then
        local sql_base
        sql_base="$(basename -- "$sqlspec")"
        if [[ "$sql_base" == "$USER_SQL" ]]; then
            termout_force="true"
        fi
    fi

    local seq
    seq="$(date +%s)"
    local tmp_sql
    TERMOUT_FORCE="$termout_force" tmp_sql="$(build_temp_sql_script "${SCRIPT_NAME}_${ORACLE_SID}_${seq}" "$sqlspec" "$@")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: would run sqlplus @${tmp_sql}"
        return 0
    fi

    local out_file
    out_file="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.sqlplus.XXXXXX.log")"
    TEMP_FILES+=("$out_file")

    if is_verbose; then
        if ! sqlplus -s -L / as sysdba @"${tmp_sql}" 2>&1 | tee "$out_file"; then
            return 1
        fi
    elif ! sqlplus -s -L / as sysdba @"${tmp_sql}" > "$out_file" 2>&1; then
        log_error "SQL*Plus failed while running ${sqlspec}."
        log_error "Use --debug for full SQL output. Showing last 20 lines:"
        tail -n 20 "$out_file" >&2
        return 1
    fi

    if grep -q "ORA-28007" "$out_file"; then
        log_warn "Secret reuse detected (ORA-28007). Use a different secret or --force to recreate."
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: list_open_pdbs
# Purpose.: List open READ WRITE PDBs
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: PDB names to stdout
# ------------------------------------------------------------------------------
list_open_pdbs() {
    local output
    local err_file
    err_file="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.pdbs.XXXXXX.log")"
    TEMP_FILES+=("$err_file")

    local cdb_flag
    if ! cdb_flag=$(
        sqlplus -s -L / as sysdba 2> "$err_file" << 'SQL'
set pages 0 feedback off heading off verify off echo off termout off
whenever sqlerror exit failure
select cdb from v$database;
exit;
SQL
    ); then
        local err_text=""
        local out_text=""
        if [[ -s "$err_file" ]]; then
            err_text="$(tr -s ' ' < "$err_file")"
            log_debug "sqlplus stderr: ${err_text}"
        fi
        out_text="$(printf '%s' "$cdb_flag" | tr -s ' ')"
        if [[ -n "$out_text" ]]; then
            log_debug "sqlplus output: ${out_text}"
        fi
        if [[ "$err_text" == *"ORA-00904"* || "$err_text" == *"ORA-00942"* ||
            "$out_text" == *"ORA-00904"* || "$out_text" == *"ORA-00942"* ]]; then
            log_info "Legacy/non-CDB detected; no PDBs to process."
            return 0
        fi
        log_error "Failed to detect CDB status. Check ORACLE_SID/ORACLE_HOME."
        return 1
    fi

    cdb_flag="$(printf '%s' "$cdb_flag" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"

    if [[ "${cdb_flag}" != "YES" ]]; then
        log_info "Non-CDB detected; no PDBs to process."
        return 0
    fi

    if ! output=$(
        sqlplus -s -L / as sysdba 2> "$err_file" << 'SQL'
set pages 0 feedback off heading off verify off echo off termout off
whenever sqlerror exit failure
select name from v$pdbs where open_mode = 'READ WRITE' and name <> 'PDB$SEED' order by name;
exit;
SQL
    ); then
        if [[ -s "$err_file" ]]; then
            log_debug "sqlplus stderr: $(tr -s ' ' < "$err_file")"
        fi
        log_error "Failed to list PDBs. Check ORACLE_SID/ORACLE_HOME."
        return 1
    fi

    printf '%s\n' "$output" | awk 'NF==1 && $1 ~ /^[A-Za-z0-9_$#]+$/ {print $1}'
}

# ------------------------------------------------------------------------------
# Function: resolve_ds_user
# Purpose.: Resolve Data Safe username for scope
# Args....: $1 - Scope label
# Returns.: 0 on success
# Output..: Username to stdout
# ------------------------------------------------------------------------------
resolve_ds_user() {
    local scope="$1"
    local base_user="$DATASAFE_USER"

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
# Function: resolve_ds_profile
# Purpose.: Resolve Data Safe profile for scope
# Args....: $1 - Scope label
# Returns.: 0 on success
# Output..: Profile name to stdout
# ------------------------------------------------------------------------------
resolve_ds_profile() {
    local scope="$1"
    local base_profile="$DS_PROFILE"

    if [[ -n "$COMMON_USER_PREFIX" && "$base_profile" == ${COMMON_USER_PREFIX}* ]]; then
        base_profile="${base_profile#${COMMON_USER_PREFIX}}"
    fi

    if [[ "$scope" == "ROOT" ]]; then
        if [[ -n "$COMMON_USER_PREFIX" ]]; then
            printf '%s' "${COMMON_USER_PREFIX}${base_profile}"
            return 0
        fi
    fi

    printf '%s' "$base_profile"
}

# ------------------------------------------------------------------------------
# Function: run_prereqs_scope
# Purpose.: Run prereq SQL scripts for a scope
# Args....: $1 - Scope label
# Returns.: 0 on success, 1 on failure
# Output..: Log messages and SQL*Plus output
# ------------------------------------------------------------------------------
run_prereqs_scope() {
    local scope_label="$1"
    local force_arg="FALSE"
    if [[ "$DS_FORCE" == "true" ]]; then
        force_arg="TRUE"
    fi

    local update_arg="FALSE"
    if [[ "$DS_UPDATE_SECRET" == "true" ]]; then
        update_arg="TRUE"
    fi

    local ds_user
    ds_user="$(resolve_ds_user "$scope_label")"

    local ds_profile
    ds_profile="$(resolve_ds_profile "$scope_label")"

    log_info "Running Data Safe prerequisites for ${scope_label} (user action: ${USER_ACTION})"

    run_sql_local "${SQL_DIR%/}/${PREREQ_SQL}" "${ds_profile}"
    run_sql_local "${SQL_DIR%/}/${USER_SQL}" "${ds_user}" "${DATASAFE_PASS}" "${ds_profile}" "${force_arg}" "${update_arg}"
    run_sql_local "${SQL_DIR%/}/${GRANTS_SQL}" "${ds_user}" "${DS_GRANT_TYPE}" "${DS_GRANT_MODE}"
}

# ------------------------------------------------------------------------------
# Function: run_checks_scope
# Purpose.: Check user roles and privileges for a scope
# Args....: $1 - Scope label
# Returns.: 0 on success, 1 on failure
# Output..: Log messages and SQL*Plus output
# ------------------------------------------------------------------------------
run_checks_scope() {
    local scope_label="$1"
    local ds_user
    ds_user="$(resolve_ds_user "$scope_label")"

    log_info "Checking Data Safe setup for ${scope_label}"

    local check_sql
    check_sql=$(
        cat << EOF
@INLINE
set pagesize 200
set linesize 200
set trimspool on
set tab off
set feedback off
set verify off
column username format a30
column granted_role format a40
column privilege format a40

prompt === User
select username from dba_users where username=upper('${ds_user}');

prompt === Roles
select granted_role from dba_role_privs where grantee=upper('${ds_user}') order by granted_role;

prompt === Privileges
select privilege from dba_sys_privs where grantee=upper('${ds_user}') order by privilege;
EOF
    )

    run_sql_local "$check_sql"
}

# ------------------------------------------------------------------------------
# Function: run_drop_user_scope
# Purpose.: Drop the Data Safe user for a scope
# Args....: $1 - Scope label
# Returns.: 0 on success, 1 on failure
# Output..: Log messages and SQL*Plus output
# ------------------------------------------------------------------------------
run_drop_user_scope() {
    local scope_label="$1"
    local ds_user
    ds_user="$(resolve_ds_user "$scope_label")"

    log_info "Dropping Data Safe user for ${scope_label}: ${ds_user}"

    local drop_sql
    drop_sql=$(
        cat << EOF
@INLINE
set serveroutput on size unlimited
declare
    l_user varchar2(128) := upper('${ds_user}');
begin
    execute immediate 'drop user ' || l_user || ' cascade';
    dbms_output.put_line('Dropped user ' || l_user);
exception
    when others then
        if sqlcode = -1918 then
            dbms_output.put_line('User ' || l_user || ' does not exist');
        else
            raise;
        end if;
end;
/
EOF
    )

    run_sql_local "$drop_sql"
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - Command-line arguments
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    trap cleanup EXIT

    # Fast-path help/version to avoid requiring ORACLE_SID or sqlplus
    case "${1:-}" in
        -h | --help)
            usage
            ;;
        -V | --version)
            echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
            exit 0
            ;;
    esac

    parse_args "$@"
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION} (ORACLE_SID=${ORACLE_SID:-unset})"
    validate_inputs

    if [[ "$DROP_USER" == "true" ]]; then
        if [[ "$RUN_ALL" == "true" ]]; then
            RUN_ROOT=true
            PDB=""
            run_drop_user_scope "ROOT"

            local pdb
            local pdbs=""
            if pdbs=$(list_open_pdbs); then
                while IFS= read -r pdb; do
                    [[ -z "$pdb" ]] && continue
                    RUN_ROOT=false
                    PDB="$pdb"
                    run_drop_user_scope "PDB=${pdb}"
                done <<< "$pdbs"
            else
                log_warn "Skipping PDB processing; unable to list PDBs."
            fi
        elif [[ "$RUN_ROOT" == "true" ]]; then
            PDB=""
            run_drop_user_scope "ROOT"
        else
            RUN_ROOT=false
            local pdb
            local -a pdb_list=()
            IFS=',' read -r -a pdb_list <<< "${PDBS}"
            for pdb in "${pdb_list[@]}"; do
                pdb="${pdb//[[:space:]]/}"
                [[ -z "$pdb" ]] && continue
                PDB="$pdb"
                run_drop_user_scope "PDB=${pdb}"
            done
        fi

        log_info "Done"
        return 0
    fi

    if [[ "$RUN_ALL" == "true" ]]; then
        RUN_ROOT=true
        PDB=""
        if [[ "$CHECK_ONLY" == "true" ]]; then
            run_checks_scope "ROOT"
        else
            run_prereqs_scope "ROOT"
        fi

        local pdb
        local pdbs=""
        if pdbs=$(list_open_pdbs); then
            while IFS= read -r pdb; do
                [[ -z "$pdb" ]] && continue
                RUN_ROOT=false
                PDB="$pdb"
                if [[ "$CHECK_ONLY" == "true" ]]; then
                    run_checks_scope "PDB=${pdb}"
                else
                    run_prereqs_scope "PDB=${pdb}"
                fi
            done <<< "$pdbs"
        else
            log_warn "Skipping PDB processing; unable to list PDBs."
        fi
    elif [[ "$RUN_ROOT" == "true" ]]; then
        PDB=""
        if [[ "$CHECK_ONLY" == "true" ]]; then
            run_checks_scope "ROOT"
        else
            run_prereqs_scope "ROOT"
        fi
    else
        RUN_ROOT=false
        local pdb
        local -a pdb_list=()
        IFS=',' read -r -a pdb_list <<< "${PDBS}"
        for pdb in "${pdb_list[@]}"; do
            pdb="${pdb//[[:space:]]/}"
            [[ -z "$pdb" ]] && continue
            PDB="$pdb"
            if [[ "$CHECK_ONLY" == "true" ]]; then
                run_checks_scope "PDB=${pdb}"
            else
                run_prereqs_scope "PDB=${pdb}"
            fi
        done
    fi

    log_info "Done"
}

if [[ $# -eq 0 ]]; then
    usage
fi

main "$@"

exit 0

__PAYLOAD_BEGINS__
: << __PAYLOAD_END__
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
__PAYLOAD_END__
