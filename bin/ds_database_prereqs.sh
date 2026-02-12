#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_database_prereqs.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.12
# Version....: v0.9.0
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

SCRIPT_VERSION="0.9.0"
readonly SCRIPT_VERSION

# =============================================================================
# LOGGING
# =============================================================================

: "${LOG_LEVEL:=INFO}"
: "${LOG_FILE:=}"

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

log_trace() { log TRACE "$@"; }
log_debug() { log DEBUG "$@"; }
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_fatal() { log FATAL "$@"; }

is_verbose() {
    [[ "${LOG_LEVEL^^}" == "DEBUG" || "${LOG_LEVEL^^}" == "TRACE" ]]
}

die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# =============================================================================
# HELPERS
# =============================================================================

need_val() {
    local flag="$1"
    local val="${2:-}"
    if [[ -z "$val" || "$val" == -* ]]; then
        die "Option ${flag} requires a value"
    fi
}

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

find_password_file() {
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
: "${DATASAFE_PASSWORD:=}"
: "${DATASAFE_PASSWORD_FILE:=}"
: "${DS_PROFILE:=DS_USER_PROFILE}"
: "${DS_FORCE:=false}"
: "${DS_GRANT_TYPE:=GRANT}"
: "${DS_GRANT_MODE:=ALL}"
: "${COMMON_USER_PREFIX:=C##}"

TEMP_FILES=()

# =============================================================================
# FUNCTIONS
# =============================================================================

cleanup() {
    local file=""
    for file in "${TEMP_FILES[@]:-}"; do
        [[ -n "$file" && -e "$file" ]] && rm -rf "$file"
    done
}

has_embedded_sql() {
    grep -q '^__PAYLOAD_BEGINS__$' "$SCRIPT_PATH"
}

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
  -U, --ds-user USER      Data Safe user (default: ${DATASAFE_USER})
  -P, --ds-password PASS  Data Safe password (or via password file)
  --password-file FILE    Base64 password file (optional)
  --ds-profile PROFILE    Database profile (default: ${DS_PROFILE})
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

Modes:
  --check                 Verify user/privileges only (no changes)
  -n, --dry-run           Show actions without executing

Common:
  -h, --help              Show this help
  -V, --version           Show version
  -v, --verbose           Enable verbose output
  -d, --debug             Enable debug output
  -q, --quiet             Quiet mode
  --log-file FILE         Log to file
  --no-color              Disable colored output

Examples:
  ${SCRIPT_NAME} --root -P mySecret
    ${SCRIPT_NAME} --pdb APP1PDB -P mySecret
    ${SCRIPT_NAME} --pdb APP1PDB,APP2PDB --force
  ${SCRIPT_NAME} --all --force -P mySecret
  ${SCRIPT_NAME} --root --check

EOF
    exit 0
}

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
            -P | --ds-password)
                need_val "$1" "${2:-}"
                DATASAFE_PASSWORD="$2"
                shift 2
                ;;
            --password-file)
                need_val "$1" "${2:-}"
                DATASAFE_PASSWORD_FILE="$2"
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
# Function....: resolve_sql_dir
# Purpose.....: Determine SQL directory if not explicitly set
# Returns.....: 0 on success, exits on error
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

generate_password() {
    require_cmd openssl tr

    local rand
    rand="$(openssl rand -base64 18 | tr -d '=+/')"
    printf '%s' "${rand}Aa1!"
}

password_file_path() {
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

resolve_password() {
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return 0
    fi

    if [[ -n "$DATASAFE_PASSWORD" ]]; then
        return 0
    fi

    local password_file=""
    if password_file=$(find_password_file "$DATASAFE_USER" "$DATASAFE_PASSWORD_FILE"); then
        require_cmd base64
        DATASAFE_PASSWORD=$(decode_base64_file "$password_file") || die "Failed to decode password file: $password_file"
        [[ -n "$DATASAFE_PASSWORD" ]] || die "Password file is empty: $password_file"
        log_info "Loaded Data Safe password from file: $password_file"
        return 0
    fi

    DATASAFE_PASSWORD="$(generate_password)"
    local output_file
    output_file="$(password_file_path "$DATASAFE_USER")"
    mkdir -p "$(dirname -- "$output_file")"
    umask 077
    printf '%s' "$DATASAFE_PASSWORD" | base64 > "$output_file"
    log_info "Generated Data Safe password and wrote: $output_file"
}

validate_inputs() {
    log_debug "Validating inputs..."

    log_debug "Options: run_all=${RUN_ALL}, run_root=${RUN_ROOT}, pdbs=${PDBS:-}"
    log_debug "SQL_DIR=${SQL_DIR} prereq=${PREREQ_SQL} user_sql=${USER_SQL} grants=${GRANTS_SQL}"
    log_debug "DS user=${DATASAFE_USER} profile=${DS_PROFILE} force=${DS_FORCE}"

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

    resolve_sql_dir
    [[ -f "${SQL_DIR}/${PREREQ_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${PREREQ_SQL} (use --sql-dir)"
    [[ -f "${SQL_DIR}/${USER_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${USER_SQL} (use --sql-dir)"
    [[ -f "${SQL_DIR}/${GRANTS_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${GRANTS_SQL} (use --sql-dir)"

    resolve_password
}

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
    run_sql_local "${SQL_DIR%/}/${USER_SQL}" "${ds_user}" "${DATASAFE_PASSWORD}" "${ds_profile}" "${force_arg}"
    run_sql_local "${SQL_DIR%/}/${GRANTS_SQL}" "${ds_user}" "${DS_GRANT_TYPE}" "${DS_GRANT_MODE}"
}

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
SwUGAAAAAAMAAwAiAQAAZzsAAAAA
__PAYLOAD_END__
