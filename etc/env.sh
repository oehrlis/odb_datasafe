#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: env.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.17
# Revision...: 0.11.2
# Purpose....: Optional odb_datasafe environment hook
# Notes......: Sourced by OraDBA when:
#              - ORADBA_EXTENSIONS_SOURCE_ETC=true
#              - .extension contains load_env: true
#              Keep this file idempotent.
# ------------------------------------------------------------------------------

_ds_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ds_ext_base="$(cd "${_ds_env_dir}/.." && pwd)"

export ODB_DATASAFE_BASE="${ODB_DATASAFE_BASE:-${_ds_ext_base}}"
export DATASAFE_BASE="${DATASAFE_BASE:-${ODB_DATASAFE_BASE}}"
export DATASAFE_SCRIPT_BIN="${DATASAFE_SCRIPT_BIN:-${ODB_DATASAFE_BASE}/bin}"

if [[ -d "${DATASAFE_SCRIPT_BIN}" ]]; then
    case ":${PATH}:" in
        *":${DATASAFE_SCRIPT_BIN}:"*) ;;
        *) PATH="${DATASAFE_SCRIPT_BIN}:${PATH}" ;;
    esac
    export PATH
fi

unset _ds_env_dir _ds_ext_base
