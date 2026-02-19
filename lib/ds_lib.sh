#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: ds_lib.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Version....: v0.7.0
# Purpose....: Convenience loader for Data Safe v4 library
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Guard against multiple sourcing
[[ -n "${DS_LIB_SH_LOADED:-}" ]] && return 0

# Determine library directory
_DS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load modules in order
# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/common.sh" || {
    echo "ERROR: Failed to load common.sh" >&2
    exit 1
}

# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/oci_helpers.sh" || {
    echo "ERROR: Failed to load oci_helpers.sh" >&2
    exit 1
}

# shellcheck disable=SC1090,SC1091
source "${_DS_LIB_DIR}/ssh_helpers.sh" || {
    echo "ERROR: Failed to load ssh_helpers.sh" >&2
    exit 1
}

readonly DS_LIB_SH_LOADED=1
# Library loaded successfully (v4.0.0)
