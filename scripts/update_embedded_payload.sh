#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script.....: update_embedded_payload.sh
# Purpose....: Rebuild embedded SQL payload in ds_database_prereqs.sh
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly SCRIPT_DIR
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BASE_DIR

readonly DEFAULT_TARGET_SCRIPT="${BASE_DIR}/bin/ds_database_prereqs.sh"

readonly SQL_FILE_1="sql/create_ds_admin_prerequisites.sql"
readonly SQL_FILE_2="sql/create_ds_admin_user.sql"
readonly SQL_FILE_3="sql/datasafe_privileges.sql"

# ------------------------------------------------------------------------------
# Function: show_usage
# Purpose.: Display script usage information
# Returns.: 0
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Rebuild embedded SQL payload in ds_database_prereqs.sh.

Options:
    -t, --target FILE       Target script (default: ${DEFAULT_TARGET_SCRIPT})
    -n, --dry-run           Validate inputs and print actions only
    -h, --help              Show this help
EOF
}

# ------------------------------------------------------------------------------
# Function: require_cmd
# Purpose.: Ensure required command exists
# Args....: $1 - Command name
# Returns.: 0 on success, 1 on error
# Output..: Error text to stderr on failure
# ------------------------------------------------------------------------------
require_cmd() {
    local command_name="$1"

    if ! command -v "${command_name}" > /dev/null 2>&1; then
        echo "Error: Required command not found: ${command_name}" >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: require_file
# Purpose.: Ensure required file exists
# Args....: $1 - File path
# Returns.: 0 on success, 1 on error
# Output..: Error text to stderr on failure
# ------------------------------------------------------------------------------
require_file() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        echo "Error: Required file not found: ${file_path}" >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: rebuild_payload
# Purpose.: Build zip/base64 payload and rewrite payload block
# Args....: $1 - Target script path
# Returns.: 0 on success, 1 on error
# Output..: Status text to stdout/stderr
# ------------------------------------------------------------------------------
rebuild_payload() {
    local target_script="$1"
    local zip_file=""
    local payload_b64=""
    local temp_output=""

    zip_file="$(mktemp -t ds_sql.XXXXXX).zip"
    payload_b64="$(mktemp -t ds_sql.XXXXXX).b64"
    temp_output="$(mktemp -t ds_prereqs.XXXXXX).sh"

    trap 'rm -f "${zip_file}" "${payload_b64}" "${temp_output}"' RETURN

    (
        cd "${BASE_DIR}"
        zip -j "${zip_file}" \
            "${SQL_FILE_1}" \
            "${SQL_FILE_2}" \
            "${SQL_FILE_3}" > /dev/null
    )

    base64 "${zip_file}" > "${payload_b64}"

    awk -v payload="${payload_b64}" '
            /^[[:space:]]*__PAYLOAD_BEGINS__[[:space:]]*$/ {
        print
        print ": << '__PAYLOAD_END__'"
        while ((getline line < payload) > 0) print line
        close(payload)
        print "__PAYLOAD_END__"
        in_payload=1
        next
      }

            in_payload && /^[[:space:]]*__PAYLOAD_END__[[:space:]]*$/ {
        in_payload=0
        next
      }

      in_payload { next }
      { print }
    ' "${target_script}" > "${temp_output}"

    mv "${temp_output}" "${target_script}"
    chmod 755 "${target_script}"

    echo "Updated embedded payload in ${target_script}"

    "${target_script}" --help > /dev/null
    echo "Sanity check passed: ${target_script} --help"

    return 0
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Parse arguments and execute payload rebuild
# Returns.: 0 on success, 1 on error
# Output..: Status and error text
# ------------------------------------------------------------------------------
main() {
    local target_script="${DEFAULT_TARGET_SCRIPT}"
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -t | --target)
                [[ -z "${2:-}" ]] && {
                    echo "Error: --target requires a value" >&2
                    return 1
                }
                target_script="${2}"
                shift 2
                ;;
            -n | --dry-run)
                dry_run="true"
                shift
                ;;
            -h | --help)
                show_usage
                return 0
                ;;
            *)
                echo "Error: Unknown option: ${1}" >&2
                show_usage
                return 1
                ;;
        esac
    done

    require_cmd zip
    require_cmd base64
    require_cmd awk
    require_file "${target_script}"
    require_file "${BASE_DIR}/${SQL_FILE_1}"
    require_file "${BASE_DIR}/${SQL_FILE_2}"
    require_file "${BASE_DIR}/${SQL_FILE_3}"

    if ! grep -Eq '^[[:space:]]*__PAYLOAD_BEGINS__[[:space:]]*$' "${target_script}"; then
        echo "Error: Target script does not contain __PAYLOAD_BEGINS__ marker" >&2
        return 1
    fi

    if [[ "${dry_run}" == "true" ]]; then
        echo "Dry run: would rebuild payload in ${target_script}"
        return 0
    fi

    rebuild_payload "${target_script}"

    return 0
}

main "$@"
