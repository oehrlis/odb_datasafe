#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: datasafe_env.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.16
# Version....: v0.11.0
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
    _ds_env_script_path="$(eval 'printf "%s" "${.sh.file:-}"' 2> /dev/null)"
fi
if [ -z "${_ds_env_script_path}" ]; then
    _ds_env_script_path="$0"
fi

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

# Export base directory for standalone usage
export DATASAFE_BASE="${DATASAFE_BASE:-${DATASAFE_BASE_DEFAULT}}"
export DATASAFE_SCRIPT_BIN="${DATASAFE_SCRIPT_BIN:-${DATASAFE_SCRIPT_BIN_DEFAULT}}"

# Add bin directory to PATH once (append at end)
case ":${PATH}:" in
    *":${DATASAFE_SCRIPT_BIN}:"*) ;;
    *) export PATH="${PATH}:${DATASAFE_SCRIPT_BIN}" ;;
esac

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------
# Customize aliases below to fit personal workflow.
# ------------------------------------------------------------------------------
# Convenience aliases
alias ds='cd "${DATASAFE_BASE}"'
alias cdds='cd "${DATASAFE_BASE}"'
alias dshelp='odb_datasafe_help.sh'
alias dsversion='ds_version.sh'

# Cleanup internal variables
unset _ds_env_script_path _ds_env_script_name _ds_env_script_dir _ds_env_base_dir
unset _ds_env_script_version _ds_env_is_sourced

# EOF --------------------------------------------------------------------------
