#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_prereqs.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.9.0
# Purpose....: Copy SQL prereq scripts to DB host and run them for one scope
# Notes......: DEPRECATED - use ds_database_prereqs.sh for local execution
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
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION

# Avoid auto error handling from environment overrides
export AUTO_ERROR_HANDLING=false

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

# Initialize configuration
init_config

# =============================================================================
# DEFAULTS
# =============================================================================

: "${HOST:=}"
: "${SID:=}"
: "${PDB:=}"
: "${RUN_ROOT:=false}"

: "${SSH_USER:=opc}"
: "${SSH_PORT:=22}"
: "${ORACLE_USER:=oracle}"

: "${SQL_DIR:=${SCRIPT_DIR}/../sql}"
: "${REMOTE_DIR:=/tmp/datasafe_prereq}"
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

: "${CHECK_ONLY:=false}"

TEMP_FILES=()

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: cleanup
# Purpose.: Remove temporary files
# Args....: None
# Returns.: 0 on success
# Output..: None
# ------------------------------------------------------------------------------
cleanup() {
    local file=""
    for file in "${TEMP_FILES[@]:-}"; do
        [[ -n "$file" && -f "$file" ]] && rm -f "$file"
    done
}

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# Args....: None
# Returns.: Exits the script
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Copy SQL scripts to a database host and execute prerequisites, user creation,
  and Data Safe grants for a single scope (PDB or CDB\$ROOT).

Deprecated:
    This script is deprecated. Prefer ds_database_prereqs.sh for local execution.

Scope (choose one):
  --pdb PDB               Target a single PDB by name
  --root                  Target CDB\$ROOT

Required:
  -H, --host HOST         Target DB host
  --sid SID               Database SID

SSH:
  -u, --ssh-user USER     SSH user (default: ${SSH_USER})
  -p, --ssh-port PORT     SSH port (default: ${SSH_PORT})
  -o, --oracle-user USER  Remote Oracle OS user (default: ${ORACLE_USER})

SQL:
  --sql-dir DIR           Local SQL dir (default: ${SQL_DIR})
  --remote-dir DIR        Remote drop zone (default: ${REMOTE_DIR})
  --prereq FILE           Prereq SQL filename (default: ${PREREQ_SQL})
  --user-sql FILE          Create-user SQL filename (default: ${USER_SQL})
  --grants-sql FILE       Grants SQL filename (default: ${GRANTS_SQL})

Data Safe:
  -U, --ds-user USER      Data Safe user (default: ${DATASAFE_USER})
  -P, --ds-password PASS  Data Safe password (or via password file)
  --password-file FILE    Base64 password file (optional)
  --ds-profile PROFILE    Database profile (default: ${DS_PROFILE})
  --force                 Force recreate user if exists
  --grant-type TYPE       Grant type (default: ${DS_GRANT_TYPE})
  --grant-mode MODE       Grant mode (default: ${DS_GRANT_MODE})

Modes:
  --check                 Verify user/privileges only (no changes)
  -n, --dry-run            Show actions without executing

Common:
  -h, --help              Show this help
  -V, --version           Show version
  -v, --verbose           Enable verbose output
  -d, --debug             Enable debug output
  -q, --quiet             Quiet mode
  --log-file FILE         Log to file
  --no-color              Disable colored output

Examples:
  ${SCRIPT_NAME} -H db01 --sid cdb01 --pdb APP1PDB -P mySecret
  ${SCRIPT_NAME} -H db01 --sid cdb01 --root --check

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - command-line arguments
# Returns.: 0 on success
# Output..: Sets global variables based on arguments
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"

    local -a remaining=()
    set -- "${ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H | --host)
                need_val "$1" "${2:-}"
                HOST="$2"
                shift 2
                ;;
            --sid)
                need_val "$1" "${2:-}"
                SID="$2"
                shift 2
                ;;
            --pdb)
                need_val "$1" "${2:-}"
                PDB="$2"
                shift 2
                ;;
            --root)
                RUN_ROOT=true
                shift
                ;;
            -u | --ssh-user)
                need_val "$1" "${2:-}"
                SSH_USER="$2"
                shift 2
                ;;
            -p | --ssh-port)
                need_val "$1" "${2:-}"
                SSH_PORT="$2"
                shift 2
                ;;
            -o | --oracle-user)
                need_val "$1" "${2:-}"
                ORACLE_USER="$2"
                shift 2
                ;;
            --sql-dir)
                need_val "$1" "${2:-}"
                SQL_DIR="$2"
                shift 2
                ;;
            --remote-dir)
                need_val "$1" "${2:-}"
                REMOTE_DIR="$2"
                shift 2
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
            -U | --ds-user | -ds-user)
                need_val "$1" "${2:-}"
                DATASAFE_USER="$2"
                shift 2
                ;;
            -P | --ds-password | -ds-password)
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
# Function: validate_inputs
# Purpose.: Validate required inputs and resolve defaults
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    ssh_require_tools
    require_cmd mktemp

    [[ -z "$HOST" ]] && die "Missing required option: --host"
    [[ -z "$SID" ]] && die "Missing required option: --sid"

    if [[ -z "$PDB" && "$RUN_ROOT" != "true" ]]; then
        die "Specify scope: --pdb <name> OR --root"
    fi

    if [[ -n "$PDB" && "$RUN_ROOT" == "true" ]]; then
        die "Choose exactly one scope: --pdb OR --root"
    fi

    [[ -f "${SQL_DIR}/${PREREQ_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${PREREQ_SQL}"
    [[ -f "${SQL_DIR}/${USER_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${USER_SQL}"
    [[ -f "${SQL_DIR}/${GRANTS_SQL}" ]] || die "Missing SQL file: ${SQL_DIR}/${GRANTS_SQL}"

    if [[ "$CHECK_ONLY" != "true" && -z "$DATASAFE_PASSWORD" ]]; then
        local password_file=""
        if password_file=$(find_password_file "$DATASAFE_USER" "$DATASAFE_PASSWORD_FILE"); then
            require_cmd base64
            DATASAFE_PASSWORD=$(decode_base64_file "$password_file") || die "Failed to decode password file: $password_file"
            [[ -n "$DATASAFE_PASSWORD" ]] || die "Password file is empty: $password_file"
            log_info "Loaded Data Safe password from file: $password_file"
        fi
    fi

    if [[ "$CHECK_ONLY" != "true" && -z "$DATASAFE_PASSWORD" ]]; then
        die "Missing required option: --ds-password (not needed with --check)"
    fi

    if [[ "$RUN_ROOT" == "true" && -n "$COMMON_USER_PREFIX" ]]; then
        if [[ "$DATASAFE_USER" != ${COMMON_USER_PREFIX}* ]]; then
            log_info "ROOT scope: adding common user prefix '${DATASAFE_USER}' -> '${COMMON_USER_PREFIX}${DATASAFE_USER}'"
            DATASAFE_USER="${COMMON_USER_PREFIX}${DATASAFE_USER}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_ds_profile
# Purpose.: Resolve profile name for root vs PDB scope
# Args....: $1 - scope label
# Returns.: 0 on success
# Output..: Resolved profile name to stdout
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
# Function: build_temp_sql_script
# Purpose.: Create a temporary SQL*Plus script for execution
# Args....: $1 - base name
#           $2 - sqlspec (path or @INLINE)
#           $@ - extra args passed to SQL file
# Returns.: 0 on success
# Output..: Path to temp SQL file
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
        echo "set echo on"
        echo "set termout on"
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
                printf '@"%s/%s" %s\n' "${REMOTE_DIR%/}" "$base" "$joined"
            else
                printf '@"%s/%s"\n' "${REMOTE_DIR%/}" "$base"
            fi
        fi

        printf 'exit;%s' $'\n'
        echo
    } > "$tmp_sql"

    printf '%s\n' "$tmp_sql"
}

# ------------------------------------------------------------------------------
# Function: build_env_cmd
# Purpose.: Build environment sourcing command for remote execution
# Args....: None
# Returns.: 0 on success
# Output..: Command snippet to stdout
# ------------------------------------------------------------------------------
build_env_cmd() {
    printf '%s' "export ORAENV_ASK=NO ORACLE_SID='%s'; if command -v oraenv >/dev/null 2>&1; then . oraenv >/dev/null 2>&1; fi" "$SID"
}

# ------------------------------------------------------------------------------
# Function: ssh_run_sql
# Purpose.: Copy a temp SQL script to remote and execute via sqlplus
# Args....: $1 - sqlspec (path or @INLINE)
#           $@ - extra args passed to SQL file
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
ssh_run_sql() {
    local sqlspec="$1"
    shift || true

    local seq
    seq="$(date +%s)"
    local tmp_sql
    tmp_sql="$(build_temp_sql_script "${SCRIPT_NAME}_${SID}_${seq}" "$sqlspec" "$@")"

    local remote_sql="${REMOTE_DIR%/}/__${SCRIPT_NAME}_${SID}_${seq}.sql"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: would copy ${tmp_sql} to ${SSH_USER}@${HOST}:${remote_sql}"
        log_info "DRY-RUN: would run sqlplus as ${ORACLE_USER} on ${HOST}"
        return 0
    fi

    ssh_exec "$HOST" "$SSH_USER" "$SSH_PORT" "mkdir -p '${REMOTE_DIR}' && chmod 777 '${REMOTE_DIR}'"
    ssh_scp_to "$tmp_sql" "$HOST" "$SSH_USER" "$SSH_PORT" "$remote_sql"

    local env_cmd
    env_cmd="$(build_env_cmd)"

    local exec_cmd
    exec_cmd="${env_cmd}; sqlplus -s -L / as sysdba @\"${remote_sql}\" </dev/null"

    ssh_exec "$HOST" "$SSH_USER" "$SSH_PORT" "sudo -u ${ORACLE_USER} bash -lc $(printf %q "$exec_cmd")"
    ssh_exec "$HOST" "$SSH_USER" "$SSH_PORT" "rm -f '${remote_sql}'" > /dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# Function: copy_sql_files
# Purpose.: Copy SQL files to remote host
# Args....: None
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
copy_sql_files() {
    log_info "Copy SQL files to ${HOST}:${REMOTE_DIR}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: would copy ${PREREQ_SQL}, ${USER_SQL}, ${GRANTS_SQL}"
        return 0
    fi

    ssh_exec "$HOST" "$SSH_USER" "$SSH_PORT" "mkdir -p '${REMOTE_DIR}' && chmod 777 '${REMOTE_DIR}'"
    ssh_scp_to "${SQL_DIR}/${PREREQ_SQL}" "$HOST" "$SSH_USER" "$SSH_PORT" "${REMOTE_DIR%/}/"
    ssh_scp_to "${SQL_DIR}/${USER_SQL}" "$HOST" "$SSH_USER" "$SSH_PORT" "${REMOTE_DIR%/}/"
    ssh_scp_to "${SQL_DIR}/${GRANTS_SQL}" "$HOST" "$SSH_USER" "$SSH_PORT" "${REMOTE_DIR%/}/"
}

# ------------------------------------------------------------------------------
# Function: run_prereqs
# Purpose.: Execute prereq, user, and grant scripts
# Args....: None
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
run_prereqs() {
    log_info "Running Data Safe prerequisites"

    copy_sql_files

    local force_arg="FALSE"
    if [[ "$DS_FORCE" == "true" ]]; then
        force_arg="TRUE"
    fi

    local scope_label="PDB"
    if [[ "$RUN_ROOT" == "true" ]]; then
        scope_label="ROOT"
    fi

    local ds_profile
    ds_profile="$(resolve_ds_profile "$scope_label")"

    ssh_run_sql "${REMOTE_DIR%/}/${PREREQ_SQL}" "${ds_profile}"
    ssh_run_sql "${REMOTE_DIR%/}/${USER_SQL}" "${DATASAFE_USER}" "${DATASAFE_PASSWORD}" "${ds_profile}" "${force_arg}"
    ssh_run_sql "${REMOTE_DIR%/}/${GRANTS_SQL}" "${DATASAFE_USER}" "${DS_GRANT_TYPE}" "${DS_GRANT_MODE}"
}

# ------------------------------------------------------------------------------
# Function: run_checks
# Purpose.: Verify user and privileges only
# Args....: None
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
run_checks() {
    log_info "Checking Data Safe setup"

    local check_user="@INLINE SELECT username FROM dba_users WHERE username=UPPER('${DATASAFE_USER}');"
    ssh_run_sql "$check_user"

    local check_roles="@INLINE SELECT grantee, granted_role FROM dba_role_privs WHERE grantee=UPPER('${DATASAFE_USER}') ORDER BY 2;"
    ssh_run_sql "$check_roles"

    local check_privs="@INLINE SELECT grantee, privilege FROM dba_sys_privs WHERE grantee=UPPER('${DATASAFE_USER}') ORDER BY 2;"
    ssh_run_sql "$check_privs"
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - command-line arguments
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    log_warn "DEPRECATED: Use ds_database_prereqs.sh for local execution"

    setup_error_handling
    parse_args "$@"
    validate_inputs

    if ! ssh_check "$HOST" "$SSH_USER" "$SSH_PORT"; then
        die "SSH connectivity check failed for ${SSH_USER}@${HOST}:${SSH_PORT}"
    fi

    if [[ "$CHECK_ONLY" == "true" ]]; then
        run_checks
    else
        run_prereqs
    fi

    log_info "Done"
}

if [[ $# -eq 0 ]]; then
    usage
fi

main "$@"
