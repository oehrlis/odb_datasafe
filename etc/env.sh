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

# Determine extension base for bash and ksh.
# Prefer already exported base from caller (datasafe_env.sh / OraDBA loader).
if [ -n "${ODB_DATASAFE_BASE:-}" ]; then
    _ds_ext_base="${ODB_DATASAFE_BASE}"
else
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

    case "${_ds_env_script_path}" in
        */*) ;;
        *)
            _ds_env_resolved_path="$(command -v -- "${_ds_env_script_path}" 2> /dev/null || true)"
            if [ -n "${_ds_env_resolved_path}" ]; then
                _ds_env_script_path="${_ds_env_resolved_path}"
            fi
            ;;
    esac

    _ds_env_dir="$(cd "$(dirname "${_ds_env_script_path}")" && pwd)"
    _ds_ext_base="$(cd "${_ds_env_dir}/.." && pwd)"
fi

export ODB_DATASAFE_BASE="${ODB_DATASAFE_BASE:-${_ds_ext_base}}"
export DATASAFE_BASE="${DATASAFE_BASE:-${ODB_DATASAFE_BASE}}"
export DATASAFE_SCRIPT_BIN="${DATASAFE_SCRIPT_BIN:-${ODB_DATASAFE_BASE}/bin}"

if [ -d "${DATASAFE_SCRIPT_BIN}" ]; then
    case ":${PATH}:" in
        *":${DATASAFE_SCRIPT_BIN}:"*) ;;
        *) PATH="${DATASAFE_SCRIPT_BIN}:${PATH}" ;;
    esac
    export PATH
fi

unset _ds_env_dir _ds_ext_base
unset _ds_env_script_path _ds_env_resolved_path
