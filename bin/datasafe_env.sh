#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: datasafe_env.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.15.0
# Purpose....: Sourceable standalone shell environment for odb_datasafe
# Usage......: source /path/to/odb_datasafe/bin/datasafe_env.sh
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP
# =============================================================================

# Determine script path for bash/ksh and convert to absolute directory.
# - bash: uses BASH_SOURCE[0]
# - ksh93: uses .sh.file
# - fallback: uses $0
_ds_env_script_path=""
if [ -n "${BASH_VERSION:-}" ]; then
    _ds_env_script_path="${BASH_SOURCE[0]}"
fi
if [ -z "${_ds_env_script_path}" ]; then
    _ds_env_script_path="$(eval 'printf "%s" "${.sh.file}"' 2> /dev/null)"
fi
if [ -z "${_ds_env_script_path}" ]; then
    _ds_env_script_path="$0"
fi

# If only a command name is available, resolve it to an absolute path.
case "${_ds_env_script_path}" in
    */*) ;;
    *)
        _ds_env_resolved_path="$(command -v -- "${_ds_env_script_path}" 2> /dev/null || true)"
        if [ -n "${_ds_env_resolved_path}" ]; then
            _ds_env_script_path="${_ds_env_resolved_path}"
        fi
        ;;
esac

_ds_env_script_name="$(basename "${_ds_env_script_path}")"
_ds_env_script_dir="$(cd "$(dirname "${_ds_env_script_path}")" && pwd)"
_ds_env_base_dir="$(cd "${_ds_env_script_dir}/.." && pwd)"
_ds_env_script_version="$(tr -d '\n' < "${_ds_env_base_dir}/VERSION" 2> /dev/null || echo 'unknown')"

# =============================================================================
# CUSTOMIZATION
# =============================================================================
# Customize user-facing environment behavior here.
# Keep variable names stable if referenced from docs or other scripts.

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
# DATASAFE_BASE:
#   Base path used by aliases and standalone operations.
#   Default: parent directory of this script.
#
# DATASAFE_SCRIPT_BIN:
#   Command directory appended to PATH.
#   Default: directory containing this script (bin).
# ------------------------------------------------------------------------------
DATASAFE_BASE_DEFAULT="${_ds_env_base_dir}"
DATASAFE_SCRIPT_BIN_DEFAULT="${_ds_env_script_dir}"

# This file must be sourced, not executed.
_ds_env_is_sourced=0
(return 0 2> /dev/null) && _ds_env_is_sourced=1
if [ "${_ds_env_is_sourced}" -ne 1 ]; then
    echo "ERROR: This script must be sourced, not executed." >&2
    echo "Use: source ${0}  # (${_ds_env_script_name} ${_ds_env_script_version})" >&2
    exit 1
fi

# Export base directory defaults for hooks (can be overridden in env.sh)
export ODB_DATASAFE_BASE="${ODB_DATASAFE_BASE:-${_ds_env_base_dir}}"
export DATASAFE_BASE="${DATASAFE_BASE:-${DATASAFE_BASE_DEFAULT}}"
export DATASAFE_SCRIPT_BIN="${DATASAFE_SCRIPT_BIN:-${DATASAFE_SCRIPT_BIN_DEFAULT}}"

# Load extension hook files when available.
_ds_env_hook_env="${_ds_env_base_dir}/etc/env.sh"
_ds_env_hook_aliases="${_ds_env_base_dir}/etc/aliases.sh"

if [ -f "${_ds_env_hook_env}" ]; then
    # shellcheck disable=SC1090
    . "${_ds_env_hook_env}"
else
    # Fallback: keep minimal PATH behavior if hook file is absent
    if [ ! -d "${DATASAFE_SCRIPT_BIN}" ]; then
        if [ -d "${DATASAFE_BASE}/bin" ]; then
            DATASAFE_SCRIPT_BIN="${DATASAFE_BASE}/bin"
        else
            DATASAFE_SCRIPT_BIN="${DATASAFE_SCRIPT_BIN_DEFAULT}"
        fi
        export DATASAFE_SCRIPT_BIN
    fi

    case ":${PATH}:" in
        *":${DATASAFE_SCRIPT_BIN}:"*) ;;
        *)
            if [ -n "${PATH:-}" ]; then
                export PATH="${PATH}:${DATASAFE_SCRIPT_BIN}"
            else
                export PATH="${DATASAFE_SCRIPT_BIN}"
            fi
            ;;
    esac
fi

if [ -f "${_ds_env_hook_aliases}" ]; then
    # shellcheck disable=SC1090
    . "${_ds_env_hook_aliases}"
else
    # Fallback aliases when hook file is absent
    alias ds='cd "${DATASAFE_BASE}"'
    alias cdds='cd "${DATASAFE_BASE}"'
    alias dshelp='odb_datasafe_help.sh'
    alias dsversion='ds_version.sh'
fi

# Cleanup internal variables
unset _ds_env_script_path _ds_env_script_name _ds_env_script_dir _ds_env_base_dir
unset _ds_env_script_version _ds_env_is_sourced
unset _ds_env_resolved_path
unset _ds_env_hook_env _ds_env_hook_aliases

# EOF --------------------------------------------------------------------------
