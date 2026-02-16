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

# Locate script and base directories
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BASE_DIR

# Script version from VERSION file
SCRIPT_VERSION="$(tr -d '\n' < "${BASE_DIR}/VERSION" 2> /dev/null || echo 'unknown')"
readonly SCRIPT_VERSION

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
DATASAFE_BASE_DEFAULT="${BASE_DIR}"
DATASAFE_SCRIPT_BIN_DEFAULT="${SCRIPT_DIR}"

# This file must be sourced, not executed.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed." >&2
    echo "Use: source ${0}  # (${SCRIPT_NAME} ${SCRIPT_VERSION})" >&2
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

# EOF --------------------------------------------------------------------------
