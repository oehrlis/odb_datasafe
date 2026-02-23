#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_version.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.17.0
# Purpose....: Show odb_datasafe version, metadata, and checksum-based changes
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -o pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${BASE_DIR}/lib"

if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    echo "[ERROR] Cannot find common.sh in ${LIB_DIR}" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/common.sh"

EXT_FILE="${BASE_DIR}/.extension"
VER_FILE="${BASE_DIR}/VERSION"
SUM_FILE="${BASE_DIR}/.extension.checksum"
IGNORE_FILE="${BASE_DIR}/.checksumignore"

SCRIPT_VERSION="$(awk -F':[[:space:]]*' '/^version:/ {print $2; exit}' "${EXT_FILE}" 2> /dev/null)"
SCRIPT_VERSION="${SCRIPT_VERSION:-unknown}"

CHANGES_ONLY=false

declare -a IGNORE_REGEXES=()
declare -a CHANGED_MODIFIED=()
declare -a CHANGED_MISSING=()
declare -a CHANGED_ADDITIONAL=()
declare -a CONFIG_FILES_USED=()

INTEGRITY_STATUS="unknown"
INTEGRITY_NOTE=""
CHECKED_FILE_COUNT=0

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Show odb_datasafe extension version, metadata, and integrity details.

Options:
    -h, --help              Show this help
    -V, --version           Show script version
    -c, --changes-only      Show only checksum change summary
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -V | --version)
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
                exit 0
                ;;
            -c | --changes-only)
                CHANGES_ONLY=true
                shift
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

meta_value() {
    local key="$1"
    awk -F':[[:space:]]*' -v k="$key" '$1 == k {print $2; exit}' "${EXT_FILE}" 2> /dev/null
}

meta_provides_enabled() {
    awk '
        /^provides:/ { in_provides = 1; next }
        in_provides && /^[^[:space:]]/ { in_provides = 0 }
        in_provides && /^[[:space:]]+[a-zA-Z0-9_]+:[[:space:]]*true[[:space:]]*$/ {
            gsub(/^[[:space:]]+/, "", $0)
            split($0, a, ":")
            print a[1]
        }
    ' "${EXT_FILE}" 2> /dev/null
}

glob_to_regex() {
    local pattern="$1"
    local out=""
    local i char
    for ((i = 0; i < ${#pattern}; i++)); do
        char="${pattern:i:1}"
        case "$char" in
            '*') out+=".*" ;;
            '?') out+="." ;;
            '.' | '+' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|' | '\\') out+="\\${char}" ;;
            *) out+="${char}" ;;
        esac
    done
    printf '^%s$' "$out"
}

load_ignore_patterns() {
    IGNORE_REGEXES+=('^\.extension$')
    IGNORE_REGEXES+=('^\.extension\.checksum$')
    IGNORE_REGEXES+=('^\.checksumignore$')
    IGNORE_REGEXES+=('^log/')

    [[ -f "${IGNORE_FILE}" ]] || return 0

    local line pattern regex
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim "$line")"
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        pattern="$line"
        if [[ "$pattern" == */ ]]; then
            pattern="${pattern%/}"
            regex="$(glob_to_regex "$pattern")"
            regex="${regex%\$}/.*$"
        else
            regex="$(glob_to_regex "$pattern")"
        fi
        IGNORE_REGEXES+=("$regex")
    done < "${IGNORE_FILE}"
}

is_ignored_file() {
    local file="$1"
    local rx
    for rx in "${IGNORE_REGEXES[@]}"; do
        if [[ "$file" =~ $rx ]]; then
            return 0
        fi
    done
    return 1
}

checksum_file_path() {
    local line="$1"
    local file
    file="$(awk '{print $2}' <<< "$line")"
    file="${file#\*}"
    printf '%s' "$file"
}

sha_verify_cmd() {
    if command -v sha256sum > /dev/null 2>&1; then
        VERIFY_CMD=(sha256sum -c)
        return 0
    fi
    if command -v shasum > /dev/null 2>&1; then
        VERIFY_CMD=(shasum -a 256 -c)
        return 0
    fi
    return 1
}

collect_additional_files() {
    local -A expected=()
    local line file

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        file="$(checksum_file_path "$line")"
        [[ -z "$file" ]] && continue
        is_ignored_file "$file" && continue
        expected["$file"]=1
    done < "${SUM_FILE}"

    while IFS= read -r file; do
        is_ignored_file "$file" && continue
        if [[ -z "${expected[$file]:-}" ]]; then
            CHANGED_ADDITIONAL+=("$file")
        fi
    done < <(cd "${BASE_DIR}" && find . -type f | sed 's#^\./##' | sort)
}

# ------------------------------------------------------------------------------
# Function: dedupe_array
# Purpose.: Remove duplicate entries from an array (bash 4.2 compatible)
# Args....: $1 - Name of array variable (not the array itself)
# Returns.: 0
# Output..: None (modifies the array in place)
# Notes...: Uses eval for variable indirection instead of nameref (bash 4.3+)
# ------------------------------------------------------------------------------
dedupe_array() {
    local arr_name="$1"
    local -A seen=()
    local -a deduped=()
    local item

    # Read array elements using indirect expansion
    eval "local -a arr_copy=(\"\${${arr_name}[@]}\")"

    # shellcheck disable=SC2154  # arr_copy is created dynamically via eval
    for item in "${arr_copy[@]}"; do
        [[ -z "$item" ]] && continue
        if [[ -z "${seen[$item]:-}" ]]; then
            seen["$item"]=1
            deduped+=("$item")
        fi
    done

    # Update original array using eval
    eval "${arr_name}=(\"\${deduped[@]}\")"
}

check_integrity() {
    load_ignore_patterns

    if [[ ! -f "${SUM_FILE}" ]]; then
        INTEGRITY_STATUS="not_verified"
        INTEGRITY_NOTE="Checksum file missing (${SUM_FILE})"
        return 0
    fi

    local -a VERIFY_CMD=()
    if ! sha_verify_cmd; then
        INTEGRITY_STATUS="not_verified"
        INTEGRITY_NOTE="No SHA-256 checker found (need sha256sum or shasum)"
        return 0
    fi

    local filtered
    filtered="$(mktemp)"
    local line file
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        file="$(checksum_file_path "$line")"
        [[ -z "$file" ]] && continue
        is_ignored_file "$file" && continue
        echo "$line" >> "${filtered}"
    done < "${SUM_FILE}"

    CHECKED_FILE_COUNT=$(wc -l < "${filtered}" | tr -d ' ')

    local verify_out verify_rc
    verify_out="$(
        cd "${BASE_DIR}" && "${VERIFY_CMD[@]}" "${filtered}" 2>&1
    )"
    verify_rc=$?

    if [[ ${verify_rc} -eq 0 ]]; then
        INTEGRITY_STATUS="ok"
    else
        INTEGRITY_STATUS="changed"
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            if [[ "$line" =~ ^sha256sum:[[:space:]]+(.+):[[:space:]]+No[[:space:]]+such[[:space:]]+file ]]; then
                CHANGED_MISSING+=("${BASH_REMATCH[1]}")
                continue
            fi
            if [[ "$line" =~ ^shasum:[[:space:]]+(.+):[[:space:]]+No[[:space:]]+such[[:space:]]+file ]]; then
                CHANGED_MISSING+=("${BASH_REMATCH[1]}")
                continue
            fi
            if [[ "$line" =~ ^(.+):[[:space:]]+FAILED[[:space:]]+open[[:space:]]+or[[:space:]]+read$ ]]; then
                CHANGED_MISSING+=("${BASH_REMATCH[1]}")
                continue
            fi
            if [[ "$line" =~ ^(.+):[[:space:]]+FAILED$ ]]; then
                CHANGED_MODIFIED+=("${BASH_REMATCH[1]}")
                continue
            fi
        done <<< "${verify_out}"
    fi

    collect_additional_files
    dedupe_array CHANGED_MODIFIED
    dedupe_array CHANGED_MISSING
    dedupe_array CHANGED_ADDITIONAL
    rm -f "${filtered}"
}

collect_runtime_configs() {
    local base_dir="${ODB_DATASAFE_BASE:-${BASE_DIR}}"
    local script_conf="${SCRIPT_NAME%.sh}.conf"

    CONFIG_FILES_USED=()

    if [[ -f "${base_dir}/.env" ]]; then
        CONFIG_FILES_USED+=("${base_dir}/.env")
    fi

    if [[ -n "${ORADBA_ETC:-}" && -f "${ORADBA_ETC}/datasafe.conf" ]]; then
        CONFIG_FILES_USED+=("${ORADBA_ETC}/datasafe.conf")
    fi

    if [[ -f "${base_dir}/etc/datasafe.conf" ]]; then
        CONFIG_FILES_USED+=("${base_dir}/etc/datasafe.conf")
    fi

    if [[ -n "${ORADBA_ETC:-}" && -f "${ORADBA_ETC}/${script_conf}" ]]; then
        CONFIG_FILES_USED+=("${ORADBA_ETC}/${script_conf}")
    fi

    if [[ -f "${base_dir}/etc/${script_conf}" ]]; then
        CONFIG_FILES_USED+=("${base_dir}/etc/${script_conf}")
    fi
}

print_runtime_config() {
    local oci_config oci_profile
    local config

    oci_config="${OCI_CLI_CONFIG_FILE:-${HOME}/.oci/config}"
    oci_profile="${OCI_CLI_PROFILE:-DEFAULT}"

    echo ""
    echo "Runtime Configuration:"
    echo "  Config files in use:"
    if [[ ${#CONFIG_FILES_USED[@]} -eq 0 ]]; then
        echo "    (none found)"
    else
        for config in "${CONFIG_FILES_USED[@]}"; do
            echo "    - ${config}"
        done
    fi

    echo "  OCI config file:      ${oci_config}"
    if [[ -f "${oci_config}" ]]; then
        echo "  OCI config exists:    yes"
        if grep -Fq "[${oci_profile}]" "${oci_config}"; then
            echo "  OCI profile in file:  yes"
        else
            echo "  OCI profile in file:  no"
        fi
    else
        echo "  OCI config exists:    no"
        echo "  OCI profile in file:  n/a"
    fi
    echo "  OCI profile in use:   ${oci_profile}"
}

print_header() {
    echo "OraDBA Data Safe Extension Information"
    echo "======================================"
}

print_metadata() {
    local name version description author enabled priority use_oradba_libs
    local install_path provides
    local provides_raw

    name="$(meta_value "name")"
    version="$(cat "${VER_FILE}" 2> /dev/null || meta_value "version")"
    description="$(meta_value "description")"
    author="$(meta_value "author")"
    enabled="$(meta_value "enabled")"
    priority="$(meta_value "priority")"
    use_oradba_libs="$(meta_value "uses_oradba_libs")"
    install_path="${BASE_DIR}"
    mapfile -t provides_raw < <(meta_provides_enabled)
    if [[ ${#provides_raw[@]} -gt 0 ]]; then
        provides="${provides_raw[*]}"
        provides="${provides// /, }"
    else
        provides="none"
    fi

    echo "Version:       ${version:-unknown}"
    echo "Install Path:  ${install_path}"
    echo ""
    echo "Metadata:"
    echo "  Name:            ${name:-unknown}"
    echo "  Description:     ${description:-unknown}"
    echo "  Author:          ${author:-unknown}"
    echo "  Enabled:         ${enabled:-unknown}"
    echo "  Priority:        ${priority:-unknown}"
    echo "  Uses OraDBA Lib: ${use_oradba_libs:-unknown}"
    echo "  Provides:        ${provides}"
}

print_changes() {
    local modified_count missing_count additional_count total_changes
    modified_count=${#CHANGED_MODIFIED[@]}
    missing_count=${#CHANGED_MISSING[@]}
    additional_count=${#CHANGED_ADDITIONAL[@]}
    total_changes=$((modified_count + missing_count + additional_count))

    echo ""
    echo "Extension Integrity Checks:"
    if [[ "${INTEGRITY_STATUS}" == "not_verified" ]]; then
        echo "  ⚠ Checksum not verified"
        echo "  ${INTEGRITY_NOTE}"
        return 0
    fi

    if [[ "${INTEGRITY_STATUS}" == "ok" && ${additional_count} -eq 0 ]]; then
        echo "  ✓ Extension integrity verified (${CHECKED_FILE_COUNT} files)"
        return 0
    fi

    if [[ "${INTEGRITY_STATUS}" == "ok" ]]; then
        echo "  ✓ Managed files verified (${CHECKED_FILE_COUNT} files)"
    else
        echo "  ✗ Integrity differences detected"
    fi
    echo "  Modified:   ${modified_count}"
    echo "  Missing:    ${missing_count}"
    echo "  Additional: ${additional_count}"
    echo "  Total:      ${total_changes}"

    local f
    if [[ ${modified_count} -gt 0 ]]; then
        echo ""
        echo "  Modified files:"
        for f in "${CHANGED_MODIFIED[@]}"; do
            echo "    ${f}"
        done
    fi
    if [[ ${missing_count} -gt 0 ]]; then
        echo ""
        echo "  Missing files:"
        for f in "${CHANGED_MISSING[@]}"; do
            echo "    ${f}"
        done
    fi
    if [[ ${additional_count} -gt 0 ]]; then
        echo ""
        echo "  Additional files:"
        for f in "${CHANGED_ADDITIONAL[@]}"; do
            echo "    ${f}"
        done
    fi
}

main() {
    parse_args "$@"
    init_config "${SCRIPT_NAME%.sh}.conf"
    collect_runtime_configs
    check_integrity

    if [[ "${CHANGES_ONLY}" != "true" ]]; then
        print_header
        print_metadata
        print_runtime_config
    fi
    print_changes
}

main "$@"
