#!/usr/bin/env bats
# shellcheck disable=SC1091
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_oci_error_summary.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.25
# Purpose....: Regression tests from the LRN6087 lab (#22): a failed OCI call
#              logs status, code and message of the service error - a 400
#              LimitExceeded showed only "OCI command failed (exit 1)" before.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    export LOG_LEVEL=ERROR
}

@test "oci error summary: ServiceError gives status, code and message" {
    source "${LIB_DIR}/ds_lib.sh"
    local err
    err=$(printf '%s\n' 'ServiceError:' '{' '    "code": "InvalidParameter",' \
        '    "message": "Invalid input",' '    "status": 400' '}')
    run _oci_service_error_summary "$err"
    [ "$status" -eq 0 ]
    [ "$output" = "400 InvalidParameter: Invalid input" ]
}

@test "oci error summary: other stderr gives its last non-empty line" {
    source "${LIB_DIR}/ds_lib.sh"
    run _oci_service_error_summary $'FutureWarning: urllib3\nError: Missing option(s) --file.\n\n'
    [ "$status" -eq 0 ]
    [ "$output" = "Error: Missing option(s) --file." ]
}

@test "oci error summary: empty stderr gives nothing" {
    source "${LIB_DIR}/ds_lib.sh"
    run _oci_service_error_summary ""
    [ "$status" -eq 1 ]
}

@test "oci_exec: a failed call logs the service error at ERROR level" {
    source "${LIB_DIR}/ds_lib.sh"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/oci" << 'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'ServiceError:' '{"code": "LimitExceeded", "message": "The limit for this tenancy has been exceeded.", "status": 400}' >&2
exit 1
MOCK
    chmod +x "${BATS_TEST_TMPDIR}/bin/oci"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    run oci_exec data-safe target-database create --from-json file:///dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"OCI error: 400 LimitExceeded: The limit for this tenancy has been exceeded."* ]]
}
