#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: common.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Generic utilities for bash scripts - logging, error handling,
#              argument parsing helpers. Designed to be reusable across projects.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Guard against multiple sourcing
[[ -n "${COMMON_SH_LOADED:-}" ]] && return 0
readonly COMMON_SH_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Log levels: 0=TRACE, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL
: "${LOG_LEVEL:=2}"     # Default: INFO
: "${LOG_FILE:=}"       # Optional: log to file
: "${LOG_COLORS:=auto}" # auto|always|never

# Error handling
: "${SHOW_STACKTRACE:=true}" # Show stack trace on error
: "${CLEANUP_ON_EXIT:=true}" # Call cleanup function on exit

# Script metadata (set by script, not library)
: "${SCRIPT_NAME:=$(basename "${BASH_SOURCE[-1]}")}"
: "${SCRIPT_VERSION:=}"
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[-1]}")" && pwd)}"

# =============================================================================
# COLOR SETUP
# =============================================================================

_init_colors() {
    # Only use colors if: terminal + (LOG_COLORS=always OR (LOG_COLORS=auto AND tty))
    if [[ "${LOG_COLORS}" == "never" ]]; then
        COLOR_RESET="" COLOR_RED="" COLOR_GREEN="" COLOR_YELLOW=""
        COLOR_BLUE="" COLOR_CYAN="" COLOR_GRAY=""
        return
    fi

    if [[ "${LOG_COLORS}" == "always" ]] || [[ -t 2 && "${LOG_COLORS}" == "auto" ]]; then
        COLOR_RESET='\033[0m'
        COLOR_RED='\033[0;31m'
        COLOR_GREEN='\033[0;32m'
        COLOR_YELLOW='\033[0;33m'
        COLOR_BLUE='\033[0;34m'
        COLOR_CYAN='\033[0;36m'
        COLOR_GRAY='\033[0;90m'
    else
        COLOR_RESET="" COLOR_RED="" COLOR_GREEN="" COLOR_YELLOW=""
        # shellcheck disable=SC2034 # These color variables might be used in future
        COLOR_BLUE="" COLOR_CYAN="" COLOR_GRAY=""
    fi
}
_init_colors

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Get numeric log level
_log_level_num() {
    case "${1^^}" in
        TRACE) echo 0 ;;
        DEBUG) echo 1 ;;
        INFO) echo 2 ;;
        WARN) echo 3 ;;
        ERROR) echo 4 ;;
        FATAL) echo 5 ;;
        *) echo 2 ;; # default INFO
    esac
}

# ------------------------------------------------------------------------------
# Function....: log
# Purpose.....: Generic logging function with levels and colors
# Parameters..: $1 - log level (TRACE|DEBUG|INFO|WARN|ERROR|FATAL)
#               $@ - message
# Usage.......: log INFO "Processing started"
#               log ERROR "Failed to connect"
# ------------------------------------------------------------------------------
log() {
    local level="${1^^}"
    shift
    local msg="$*"

    local level_num
    level_num=$(_log_level_num "$level")
    local current_level_num
    current_level_num=$(_log_level_num "${LOG_LEVEL}")

    # Skip if below current log level
    [[ $level_num -lt $current_level_num ]] && return 0

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    local reset="${COLOR_RESET}"

    case "$level" in
        TRACE) color="${COLOR_GRAY}" ;;
        DEBUG) color="${COLOR_CYAN}" ;;
        INFO) color="${COLOR_GREEN}" ;;
        WARN) color="${COLOR_YELLOW}" ;;
        ERROR | FATAL) color="${COLOR_RED}" ;;
    esac

    local formatted="${color}[${timestamp}] [${level}]${reset} ${msg}"

    # Output all log messages to stderr to avoid contaminating command output
    echo -e "$formatted" >&2

    # Also log to file if configured
    if [[ -n "${LOG_FILE}" ]]; then
        echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"
    fi

    # Exit on FATAL
    [[ "$level" == "FATAL" ]] && exit 1

    return 0
}

# Convenience wrappers
log_trace() { log TRACE "$@"; }
log_debug() { log DEBUG "$@"; }
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_fatal() { log FATAL "$@"; }

# ------------------------------------------------------------------------------
# Function....: die
# Purpose.....: Exit with error message
# Parameters..: $1 - error message
#               $2 - exit code (optional, default 1)
# Usage.......: die "Configuration file not found"
#               die "Invalid argument" 2
# ------------------------------------------------------------------------------
die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: stacktrace
# Purpose.....: Print stack trace for debugging
# ------------------------------------------------------------------------------
stacktrace() {
    local frame=0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Stack trace:" >&2
    while caller $frame; do
        ((frame++))
    done | while read -r line func file; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]   at ${func}() in ${file}:${line}" >&2
    done
}

# ------------------------------------------------------------------------------
# Function....: error_handler
# Purpose.....: Global error trap handler
# Usage.......: trap error_handler ERR
# Notes.......: Disables ERR trap to prevent recursion
# ------------------------------------------------------------------------------
error_handler() {
    # CRITICAL: Disable ERR trap immediately to prevent infinite recursion
    trap - ERR

    local exit_code=$?
    local line_num="${BASH_LINENO[0]}"
    local script="${BASH_SOURCE[1]}"

    # Output directly to stderr to avoid triggering more errors
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Error in ${script} at line ${line_num} (exit code: ${exit_code})" >&2

    if [[ "${SHOW_STACKTRACE:-true}" == "true" ]]; then
        stacktrace
    fi

    exit "$exit_code"
}

# ------------------------------------------------------------------------------
# Function....: cleanup
# Purpose.....: Cleanup handler (override in your script)
# Usage.......: trap cleanup EXIT
# Notes.......: Scripts should define their own cleanup() if needed
# ------------------------------------------------------------------------------
cleanup() {
    # Default cleanup - override in scripts if needed
    :
}

# ------------------------------------------------------------------------------
# Function....: setup_error_handling
# Purpose.....: Initialize error handling (call in scripts)
# Usage.......: setup_error_handling
# ------------------------------------------------------------------------------
setup_error_handling() {
    set -euo pipefail
    set -E # ERR trap inherited by functions

    trap error_handler ERR

    if [[ "${CLEANUP_ON_EXIT}" == "true" ]]; then
        trap cleanup EXIT
    fi
}

# =============================================================================
# VALIDATION & REQUIREMENTS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: require_cmd
# Purpose.....: Check if required commands are available
# Parameters..: $@ - command names
# Usage.......: require_cmd oci jq curl
# ------------------------------------------------------------------------------
require_cmd() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Function....: require_var
# Purpose.....: Check if required variables are set
# Parameters..: $@ - variable names
# Usage.......: require_var OCI_PROFILE COMPARTMENT_OCID
# ------------------------------------------------------------------------------
require_var() {
    local missing=()
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required variables: ${missing[*]}"
    fi
}

# =============================================================================
# ARGUMENT PARSING HELPERS
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: need_val
# Purpose.....: Helper to ensure flag has a value
# Parameters..: $1 - flag name (for error message)
#               $2 - value (to check)
# Usage.......: [[ $# -lt 2 ]] && need_val "--output"
#               need_val "--output" "${2:-}"
# ------------------------------------------------------------------------------
need_val() {
    local flag="$1"
    local val="${2:-}"
    if [[ -z "$val" || "$val" == -* ]]; then
        die "Option ${flag} requires a value"
    fi
}

# ------------------------------------------------------------------------------
# Function....: parse_common_opts
# Purpose.....: Parse common options that most scripts share
# Parameters..: $@ - arguments to parse
# Globals.....: Sets LOG_LEVEL, DRY_RUN, VERBOSE, DEBUG
# Returns.....: Remaining args in ARGS array
# Usage.......: parse_common_opts "$@"
#               Then process remaining args: "${ARGS[@]}"
# Notes.......: Call this FIRST, then parse script-specific args
# ------------------------------------------------------------------------------
parse_common_opts() {
    ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                if declare -f usage > /dev/null 2>&1; then
                    usage
                else
                    die "Help not available"
                fi
                ;;
            -V | --version)
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION:-unknown}"
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
                export DRY_RUN=true
                shift
                ;;
            --log-file)
                need_val "$1" "${2:-}"
                LOG_FILE="$2"
                shift 2
                ;;
            --no-color)
                LOG_COLORS=never
                _init_colors
                shift
                ;;
            --)
                shift
                ARGS+=("$@")
                break
                ;;
            *)
                # Not a common option, save for script-specific parsing
                ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: load_config
# Purpose.....: Load configuration from file if exists
# Parameters..: $1 - config file path
# Usage.......: load_config "${SCRIPT_DIR}/../etc/datasafe.conf"
# Notes.......: Silently skips if file doesn't exist
# ------------------------------------------------------------------------------
load_config() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        log_debug "Loading config from: $config_file"
        # shellcheck disable=SC1090
        source "$config_file"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function....: init_config
# Purpose.....: Initialize configuration cascade (defaults → .env → configs → CLI)
# Parameters..: $1 - optional script-specific config file
# Usage.......: init_config
#               init_config "my_script.conf"
# Notes.......: Call after setting defaults, before parse_common_opts
#               .env file location: $ODB_DATASAFE_BASE/.env (extension base directory)
# ------------------------------------------------------------------------------
init_config() {
    local script_conf="${1:-}"

    # Determine extension base directory
    local base_dir="${ODB_DATASAFE_BASE:-}"
    if [[ -z "$base_dir" ]]; then
        # Auto-detect: script is in bin/, so base is parent directory
        base_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
    fi
    export ODB_DATASAFE_BASE="$base_dir"

    # Load .env from extension base directory if exists
    local env_file="${ODB_DATASAFE_BASE}/.env"
    if [[ -f "$env_file" ]]; then
        log_debug "Loading environment from: $env_file"
        load_config "$env_file"
    else
        log_debug "No .env file found at: $env_file (optional)"
    fi

    # Load generic config - check ORADBA_ETC first, then local etc/
    if [[ -n "${ORADBA_ETC:-}" && -f "${ORADBA_ETC}/datasafe.conf" ]]; then
        log_debug "Loading config from ORADBA_ETC: ${ORADBA_ETC}/datasafe.conf"
        load_config "${ORADBA_ETC}/datasafe.conf"
    fi

    local generic_conf="${SCRIPT_DIR}/../etc/datasafe.conf"
    load_config "$generic_conf"

    # Load script-specific config if provided - check ORADBA_ETC first
    if [[ -n "$script_conf" ]]; then
        if [[ -n "${ORADBA_ETC:-}" && -f "${ORADBA_ETC}/${script_conf}" ]]; then
            log_debug "Loading script config from ORADBA_ETC: ${ORADBA_ETC}/${script_conf}"
            load_config "${ORADBA_ETC}/${script_conf}"
        fi

        local specific_conf="${SCRIPT_DIR}/../etc/${script_conf}"
        load_config "$specific_conf"
    fi

    return 0
}

# =============================================================================
# UTILITIES
# =============================================================================

# ------------------------------------------------------------------------------
# Function....: confirm
# Purpose.....: Ask user for confirmation
# Parameters..: $1 - prompt message (optional)
# Returns.....: 0 if yes, 1 if no
# Usage.......: confirm "Delete all targets?" && do_delete
# ------------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Are you sure?}"
    local response

    read -r -p "${prompt} [y/N] " response
    case "$response" in
        [yY][eE][sS] | [yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function....: is_ocid
# Purpose.....: Check if string is an OCID
# Parameters..: $1 - string to check
# Returns.....: 0 if OCID, 1 if not
# Usage.......: is_ocid "$target" && echo "It's an OCID"
# ------------------------------------------------------------------------------
is_ocid() {
    [[ "$1" =~ ^ocid1\. ]]
}

# ------------------------------------------------------------------------------
# Function....: decode_base64_file
# Purpose.....: Decode base64 file content to stdout
# Parameters..: $1 - base64 file path
# Returns.....: 0 on success, 1 on decode failure
# Output......: Decoded content to stdout
# ------------------------------------------------------------------------------
decode_base64_file() {
    local file="$1"
    local decoded=""

    if decoded=$(base64 --decode < "$file" 2>/dev/null); then
        printf '%s' "$decoded"
        return 0
    fi

    if decoded=$(base64 -d < "$file" 2>/dev/null); then
        printf '%s' "$decoded"
        return 0
    fi

    if decoded=$(base64 -D < "$file" 2>/dev/null); then
        printf '%s' "$decoded"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Function....: find_password_file
# Purpose.....: Locate password file by explicit path or username pattern
# Parameters..: $1 - username
#               $2 - explicit file path (optional)
# Returns.....: 0 on success, 1 if not found
# Output......: Resolved file path to stdout
# Notes.......: Searches ORADBA_ETC first, then $ODB_DATASAFE_BASE/etc
# ------------------------------------------------------------------------------
find_password_file() {
    local username="$1"
    local explicit_file="${2:-}"
    local filename="${username}_pwd.b64"

    if [[ -n "$explicit_file" ]]; then
        [[ -f "$explicit_file" ]] && { echo "$explicit_file"; return 0; }
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

    return 1
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize error handling if not explicitly disabled
# NOTE: Scripts using --help or early exits should set AUTO_ERROR_HANDLING=false
# before sourcing this library, or call setup_error_handling() manually after
# initialization is complete.
if [[ "${AUTO_ERROR_HANDLING:-false}" == "true" ]]; then
    setup_error_handling
fi

# common.sh loaded (v4.0.0)
