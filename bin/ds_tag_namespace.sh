#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_tag_namespace.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.06
# Version....: v1.2.0
# Purpose....: Create or align a defined-tag namespace from a JSON definition
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Purpose:
#   Brings a tag namespace and its tag keys to the state described in a JSON
#   definition file - regardless of the current state: namespace missing,
#   present or retired; key missing, present with another description or
#   validator, or retired.
#
#   Default is PLAN: every difference is printed, nothing is changed. Changes
#   need --apply. Nothing is ever deleted - deleting a namespace is
#   asynchronous and blocks the name, and a retired key keeps its values on
#   resources. Keys in the tenancy that the definition does not list are
#   reported and left alone.
#
#   Removing values from an ENUM validator needs --allow-shrink: resources may
#   carry the removed values, and OCI does not re-validate them. Without the
#   flag the change is skipped and named, never applied silently.
#
# Definition file:
#   {"namespace": {"name": "DBSec", "description": "..."},
#    "tags": [{"name": "Environment", "description": "...",
#              "validator": ["test", "qs", "prod"]},       <- ENUM
#             {"name": "Owner", "description": "...", "validator": null}]}
#   Optional per tag: "is_cost_tracking": true|false (default false).
#
# Exit Codes:
#   0 = in sync, or plan printed
#   1 = input validation error
#   2 = OCI command error
#   3 = --apply left differences (skipped shrink)
# ------------------------------------------------------------------------------

# Bootstrap - locate library files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

SCRIPT_NAME="ds_tag_namespace"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '1.2.0')"

if [[ ! -f "${LIB_DIR}/ds_lib.sh" ]]; then
    echo "[ERROR] Cannot find ds_lib.sh in ${LIB_DIR}" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh"

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
DEFINITION_FILE=""
TENANCY_OCID="${OCI_TENANCY_OCID:-}"
APPLY=false
ALLOW_SHRINK=false

# Runtime
NS_NAME=""
NS_OCID=""
CNT_CREATED=0
CNT_UPDATED=0
CNT_OK=0
CNT_SKIPPED=0

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display usage information and exit
# ------------------------------------------------------------------------------
# shellcheck disable=SC2329  # called by parse_common_opts on -h/--help
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME}.sh -f DEFINITION.json [OPTIONS]    (v${SCRIPT_VERSION})

Description:
  Create or align a defined-tag namespace and its keys from a JSON definition.
  Prints a plan by default; changes only with --apply. Never deletes.

Options:
  -f, --file FILE         Definition file (JSON) [required]
  --apply                 Apply the changes (default: plan only)
  --allow-shrink          Allow removing values from an ENUM validator
  --tenancy OCID          Tenancy OCID (default: OCI_TENANCY_OCID, then the
                          tenancy of the OCI config profile)
  --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
  --oci-region REGION     OCI region
  --oci-config FILE       OCI config file
  -v, --verbose | -d, --debug | -q, --quiet | -h, --help

Required IAM (tenancy level, for --apply):
  manage tag-namespaces in tenancy    (includes the tag definitions)
  The plan needs read access: inspect tag-namespaces in tenancy.

Examples:
  ${SCRIPT_NAME}.sh -f etc/dbsec_tag_namespace.json --oci-profile VW
  ${SCRIPT_NAME}.sh -f etc/dbsec_tag_namespace.json --oci-profile ADMIN --apply
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# ------------------------------------------------------------------------------
parse_args() {
    parse_common_opts "$@"
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f | --file)
                need_val "$1" "${2:-}"
                DEFINITION_FILE="$2"
                shift 2
                ;;
            --apply)
                APPLY=true
                shift
                ;;
            --allow-shrink)
                ALLOW_SHRINK=true
                shift
                ;;
            --tenancy)
                need_val "$1" "${2:-}"
                TENANCY_OCID="$2"
                shift 2
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            "") shift ;;
            *) die "Unknown option: $1 (use --help for usage)" ;;
        esac
    done

    # Plan is the default. The framework's DRY_RUN makes oci_exec print
    # instead of execute - the same switch, inverted on purpose.
    if [[ "${APPLY}" == "true" ]]; then
        DRY_RUN=false
    else
        DRY_RUN=true
    fi
    export DRY_RUN
}

# ------------------------------------------------------------------------------
# Function: resolve_tenancy
# Purpose.: Take the tenancy from the OCI config profile if not given
# ------------------------------------------------------------------------------
resolve_tenancy() {
    [[ -n "${TENANCY_OCID}" ]] && return 0
    local cfg="${OCI_CLI_CONFIG_FILE:-${HOME}/.oci/config}"
    local profile="${OCI_CLI_PROFILE:-DEFAULT}"
    TENANCY_OCID=$(awk -v p="[${profile}]" '
        $0 == p {inp=1; next}
        /^\[/ {inp=0}
        inp && /^[[:space:]]*tenancy[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/, ""); print; exit}
    ' "${cfg}" 2> /dev/null || true)
    [[ -n "${TENANCY_OCID}" ]] || die "Tenancy unknown - use --tenancy or OCI_TENANCY_OCID"
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Check tools and the definition file
# ------------------------------------------------------------------------------
validate_inputs() {
    require_oci_cli
    command -v jq > /dev/null || die "jq not found"
    [[ -n "${DEFINITION_FILE}" ]] || die "Definition file missing (-f FILE)"
    [[ -f "${DEFINITION_FILE}" ]] || die "Definition file not found: ${DEFINITION_FILE}"
    jq -e '.namespace.name and (.tags | type == "array")' "${DEFINITION_FILE}" > /dev/null \
        || die "Definition must contain .namespace.name and a .tags array"
    local dup
    dup=$(jq -r '[.tags[].name] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "${DEFINITION_FILE}")
    [[ -z "${dup}" ]] || die "Duplicate tag names in definition: ${dup}"
    NS_NAME=$(jq -r '.namespace.name' "${DEFINITION_FILE}")
    resolve_tenancy
}

# ------------------------------------------------------------------------------
# Function: say
# Purpose.: Plan/result line on stdout - visible regardless of the log level
# Args....: $1 - action (CREATE, UPDATE, OK, SKIP, INFO), $2 - object, $3 - text
# ------------------------------------------------------------------------------
say() {
    printf '%s %s%s\n' "$1" "$2" "${3:+ - $3}"
}

# ------------------------------------------------------------------------------
# Function: validator_json
# Purpose.: CLI validator argument for a definition validator (array or null)
# Args....: $1 - validator as JSON (array or null)
# ------------------------------------------------------------------------------
validator_json() {
    jq -c 'if . == null then {validatorType: "DEFAULT"}
           else {validatorType: "ENUM", values: .} end' <<< "$1"
}

# ------------------------------------------------------------------------------
# Function: ensure_namespace
# Purpose.: Create, reactivate or align the namespace; sets NS_OCID
# ------------------------------------------------------------------------------
ensure_namespace() {
    local want_desc ns_json
    want_desc=$(jq -r '.namespace.description // ""' "${DEFINITION_FILE}")

    ns_json=$(oci_exec_ro iam tag-namespace list --compartment-id "${TENANCY_OCID}" \
        --all --include-subcompartments false 2> /dev/null) \
        || die "Cannot list tag namespaces in ${TENANCY_OCID}" 2
    # Not "${ns_json:-{}}": bash closes the expansion at the first "}" and
    # appends the second to every non-empty value.
    [[ -n "${ns_json}" ]] || ns_json='{}'
    ns_json=$(jq -c --arg n "${NS_NAME}" '[.data[]? | select(.name == $n)] | .[0] // empty' <<< "${ns_json}")

    if [[ -z "${ns_json}" ]]; then
        say CREATE "namespace ${NS_NAME}" "${want_desc}"
        CNT_CREATED=$((CNT_CREATED + 1))
        if [[ "${APPLY}" == "true" ]]; then
            NS_OCID=$(oci_exec iam tag-namespace create --compartment-id "${TENANCY_OCID}" \
                --name "${NS_NAME}" --description "${want_desc}" --query 'data.id' --raw-output) \
                || die "Namespace create failed" 2
        fi
        return 0
    fi

    NS_OCID=$(jq -r '.id' <<< "${ns_json}")
    local changed=false
    if [[ "$(jq -r '."is-retired"' <<< "${ns_json}")" == "true" ]]; then
        say UPDATE "namespace ${NS_NAME}" "retired -> active"
        oci_exec iam tag-namespace update --tag-namespace-id "${NS_OCID}" --is-retired false --force > /dev/null \
            || die "Namespace reactivate failed" 2
        changed=true
    fi
    if [[ "$(jq -r '.description // ""' <<< "${ns_json}")" != "${want_desc}" ]]; then
        say UPDATE "namespace ${NS_NAME}" "description -> ${want_desc}"
        oci_exec iam tag-namespace update --tag-namespace-id "${NS_OCID}" --description "${want_desc}" --force > /dev/null \
            || die "Namespace update failed" 2
        changed=true
    fi
    if [[ "${changed}" == "true" ]]; then
        CNT_UPDATED=$((CNT_UPDATED + 1))
    else
        say OK "namespace ${NS_NAME}" "${NS_OCID}"
        CNT_OK=$((CNT_OK + 1))
    fi
}

# ------------------------------------------------------------------------------
# Function: ensure_tag
# Purpose.: Create, reactivate or align one tag key
# Args....: $1 - tag definition as compact JSON
# ------------------------------------------------------------------------------
ensure_tag() {
    local def="$1" name want_desc want_val want_cost obj cur
    name=$(jq -r '.name' <<< "${def}")
    want_desc=$(jq -r '.description // ""' <<< "${def}")
    want_val=$(jq -c '.validator // null' <<< "${def}")
    want_cost=$(jq -r '.is_cost_tracking // false' <<< "${def}")
    obj="${NS_NAME}.${name}"

    # Namespace only exists in the plan: every key is new.
    if [[ -z "${NS_OCID}" ]]; then
        say CREATE "${obj}" "$(jq -r 'if . == null then "free text" else "ENUM " + join(",") end' <<< "${want_val}")"
        CNT_CREATED=$((CNT_CREATED + 1))
        return 0
    fi

    cur=$(oci_exec_ro iam tag get --tag-namespace-id "${NS_OCID}" --tag-name "${name}" 2> /dev/null || true)
    [[ -n "${cur}" ]] || cur='{}'
    cur=$(jq -c '.data // empty' <<< "${cur}")

    if [[ -z "${cur}" ]]; then
        say CREATE "${obj}" "$(jq -r 'if . == null then "free text" else "ENUM " + join(",") end' <<< "${want_val}")"
        CNT_CREATED=$((CNT_CREATED + 1))
        local -a args=(iam tag create --tag-namespace-id "${NS_OCID}" --name "${name}"
            --description "${want_desc}" --is-cost-tracking "${want_cost}")
        [[ "${want_val}" != "null" ]] && args+=(--validator "$(validator_json "${want_val}")")
        oci_exec "${args[@]}" > /dev/null || die "Create ${obj} failed" 2
        return 0
    fi

    local -a upd=()
    local -a what=()
    if [[ "$(jq -r '."is-retired"' <<< "${cur}")" == "true" ]]; then
        upd+=(--is-retired false)
        what+=("retired -> active")
    fi
    if [[ "$(jq -r '.description // ""' <<< "${cur}")" != "${want_desc}" ]]; then
        upd+=(--description "${want_desc}")
        what+=("description")
    fi
    if [[ "$(jq -r '."is-cost-tracking"' <<< "${cur}")" != "${want_cost}" ]]; then
        upd+=(--is-cost-tracking "${want_cost}")
        what+=("cost-tracking -> ${want_cost}")
    fi

    # Validator: compare as sets - a different order is not a change.
    local have_val removed
    have_val=$(jq -c 'if .validator == null or .validator."validator-type" != "ENUM"
                      then null else .validator.values end' <<< "${cur}")
    if [[ "$(jq -c 'if . == null then null else sort end' <<< "${have_val}")" != "$(jq -c 'if . == null then null else sort end' <<< "${want_val}")" ]]; then
        # Values a resource may carry that the new validator no longer allows.
        removed=$(jq -rn --argjson h "${have_val}" --argjson w "${want_val}" \
            'if $h == null or $w == null then "" else ($h - $w) | join(",") end')
        if [[ -n "${removed}" && "${ALLOW_SHRINK}" != "true" ]]; then
            say SKIP "${obj}" "validator would drop ENUM value(s) ${removed} - rerun with --allow-shrink"
            CNT_SKIPPED=$((CNT_SKIPPED + 1))
        else
            upd+=(--validator "$(validator_json "${want_val}")")
            what+=("validator $(jq -r 'if . == null then "free text" else "ENUM " + join(",") end' <<< "${have_val}")"
            " -> $(jq -r 'if . == null then "free text" else "ENUM " + join(",") end' <<< "${want_val}")")
            if [[ "${have_val}" == "null" ]]; then
                log_warn "${obj}: ENUM on a free-text key - existing values outside the list stay on resources"
            fi
        fi
    fi

    if [[ ${#upd[@]} -eq 0 ]]; then
        say OK "${obj}" ""
        CNT_OK=$((CNT_OK + 1))
        return 0
    fi
    say UPDATE "${obj}" "$(printf '%s' "${what[*]}")"
    CNT_UPDATED=$((CNT_UPDATED + 1))
    oci_exec iam tag update --tag-namespace-id "${NS_OCID}" --tag-name "${name}" "${upd[@]}" --force > /dev/null \
        || die "Update ${obj} failed" 2
}

# ------------------------------------------------------------------------------
# Function: report_unlisted
# Purpose.: Name keys the tenancy has but the definition does not
# ------------------------------------------------------------------------------
report_unlisted() {
    [[ -n "${NS_OCID}" ]] || return 0
    local have unlisted
    have=$(oci_exec_ro iam tag list --tag-namespace-id "${NS_OCID}" --all 2> /dev/null || echo '{}')
    unlisted=$(jq -rn --argjson h "$(jq -c '[.data[]?.name]' <<< "${have}")" \
        --argjson w "$(jq -c '[.tags[].name]' "${DEFINITION_FILE}")" '($h - $w) | join(", ")')
    if [[ -n "${unlisted}" ]]; then
        say INFO "${NS_NAME}" "not in the definition, left unchanged: ${unlisted}"
    fi
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Plan or apply, then summarise
# ------------------------------------------------------------------------------
do_work() {
    log_info "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    if [[ "${APPLY}" == "true" ]]; then
        echo "APPLY - namespace ${NS_NAME} in ${TENANCY_OCID}"
    else
        echo "PLAN - namespace ${NS_NAME} in ${TENANCY_OCID} (nothing is changed, use --apply)"
    fi

    ensure_namespace
    local def
    while IFS= read -r def; do
        ensure_tag "${def}"
    done < <(jq -c '.tags[]' "${DEFINITION_FILE}")
    report_unlisted

    echo "Summary: ${CNT_CREATED} to create, ${CNT_UPDATED} to update, ${CNT_OK} in sync, ${CNT_SKIPPED} skipped"
    if [[ "${APPLY}" == "true" && ${CNT_SKIPPED} -gt 0 ]]; then
        echo "Not in sync: ${CNT_SKIPPED} change(s) skipped, see SKIP lines above" >&2
        return 3
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function: main
# ------------------------------------------------------------------------------
main() {
    setup_error_handling
    init_config "${SCRIPT_NAME}.conf"
    parse_args "$@"
    validate_inputs
    local rc=0
    do_work || rc=$?
    exit "${rc}"
}

main "$@"

# ------------------------------------------------------------------------------
# EOF
# ------------------------------------------------------------------------------
