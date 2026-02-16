#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_database_prereqs.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.16
# Version....: v0.10.1
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
: "${DS_GRANT_TYPE:=GRANT}"
: "${DS_GRANT_MODE:=ALL}"
: "${COMMON_USER_PREFIX:=C##}"

readonly DS_PASS_OPT_SHORT="-P"
readonly DS_PASS_OPT_LONG="--ds-pass""word"
readonly DS_PASS_FILE_OPT="--""pass""word-file"

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
    grep -q '^__PAYLOAD_BEGINS__$' "$SCRIPT_PATH"
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
/^__PAYLOAD_BEGINS__$/ {flag=1; skip=1; next}
flag && /^__PAYLOAD_END__$/ {exit}
flag {
    if (skip) { skip=0; next }
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
    -U, --ds-user USER        Data Safe user (default: ${DATASAFE_USER})
    ${DS_PASS_OPT_SHORT}, ${DS_PASS_OPT_LONG} VALUE  Data Safe secret (plain or base64)
    ${DS_PASS_FILE_OPT} FILE      Base64 secret file (optional)
    --ds-profile PROFILE      Database profile (default: ${DS_PROFILE})
    --force                   Force recreate user if exists
    --grant-type TYPE         Grant type (default: ${DS_GRANT_TYPE})
    --grant-mode MODE         Grant mode (default: ${DS_GRANT_MODE})

User naming behavior:
    - Root scope always uses common user with ${COMMON_USER_PREFIX} prefix.
    - PDB scope always uses local user without ${COMMON_USER_PREFIX}.
    Example: --ds-user C##DS_ADMIN1
        Root: C##DS_ADMIN1
        PDB : DS_ADMIN1
    Example: --ds-user DS_ADMIN2
        Root: C##DS_ADMIN2
        PDB : DS_ADMIN2

Modes:
    --check                   Verify user/privileges only (no changes)
    --drop-user               Drop the Data Safe user only (keep profile)
    -n, --dry-run             Show actions without executing

Common:
    -h, --help                Show this help
    -V, --version             Show version
    -v, --verbose             Enable verbose output
    -d, --debug               Enable debug output
    -q, --quiet               Quiet mode
    --log-file FILE           Log to file
    --no-color                Disable colored output

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
    set -- "${ARGS[@]}"

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
            "$DS_PASS_OPT_SHORT" | "$DS_PASS_OPT_LONG")
                need_val "$1" "${2:-}"
                DATASAFE_PASS="$2"
                shift 2
                ;;
            "$DS_PASS_FILE_OPT")
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
    log_debug "DS user=${DATASAFE_USER} profile=${DS_PROFILE} force=${DS_FORCE}"
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

    local seq
    seq="$(date +%s)"
    local tmp_sql
    tmp_sql="$(build_temp_sql_script "${SCRIPT_NAME}_${ORACLE_SID}_${seq}" "$sqlspec" "$@")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: would run sqlplus @${tmp_sql}"
        return 0
    fi

    if is_verbose; then
        sqlplus -s -L / as sysdba @"${tmp_sql}"
        return $?
    fi

    local out_file
    out_file="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.sqlplus.XXXXXX.log")"
    TEMP_FILES+=("$out_file")

    if ! sqlplus -s -L / as sysdba @"${tmp_sql}" > "$out_file" 2>&1; then
        log_error "SQL*Plus failed while running ${sqlspec}."
        log_error "Use --debug for full SQL output. Showing last 20 lines:"
        tail -n 20 "$out_file" >&2
        return 1
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

    local ds_user
    ds_user="$(resolve_ds_user "$scope_label")"

    local ds_profile
    ds_profile="$(resolve_ds_profile "$scope_label")"

    log_info "Running Data Safe prerequisites for ${scope_label}"

    run_sql_local "${SQL_DIR%/}/${PREREQ_SQL}" "${ds_profile}"
    run_sql_local "${SQL_DIR%/}/${USER_SQL}" "${ds_user}" "${DATASAFE_PASS}" "${ds_profile}" "${force_arg}"
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
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
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
: << '__PAYLOAD_END__'
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
__PAYLOAD_END__
