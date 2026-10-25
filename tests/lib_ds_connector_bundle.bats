#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2154
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_ds_connector_bundle.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.25
# Purpose....: Regression tests from the LRN6087 lab (#21): the bundle
#              password goes via --from-json, never on argv - the OCI CLI does
#              not expand --password file://<path> and sent the path itself
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    export TMPDIR="${BATS_TEST_TMPDIR}"
    export LOG_LEVEL=ERROR
    export DRY_RUN=false

    # fake oci: logs argv, keeps a copy of the --from-json file (deleted after the call)
    export MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    export OCI_LOG="${BATS_TEST_TMPDIR}/oci.log"
    export JSON_COPY="${BATS_TEST_TMPDIR}/from.json"
    mkdir -p "${MOCK_BIN}"
    : > "${OCI_LOG}"
    cat > "${MOCK_BIN}/oci" << 'MOCK'
#!/usr/bin/env bash
echo "$*" >> "${OCI_LOG}"
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--from-json" ]]; then
        cp "${2#file://}" "${JSON_COPY}"
        stat -c '%a' "${2#file://}" > "${JSON_COPY}.mode" 2> /dev/null \
            || stat -f '%Lp' "${2#file://}" > "${JSON_COPY}.mode"
    fi
    shift
done
echo '{"data":{}}'
MOCK
    chmod +x "${MOCK_BIN}/oci"

    # jq wrapper: logs argv, then runs the real jq
    export REAL_JQ JQ_LOG="${BATS_TEST_TMPDIR}/jq.log"
    REAL_JQ="$(command -v jq)"
    : > "${JQ_LOG}"
    cat > "${MOCK_BIN}/jq" << 'MOCK'
#!/usr/bin/env bash
echo "$*" >> "${JQ_LOG}"
exec "${REAL_JQ}" "$@"
MOCK
    chmod +x "${MOCK_BIN}/jq"
    export PATH="${MOCK_BIN}:${PATH}"

    CONN="ocid1.datasafeonpremconnector.oc1..conn"
    KEY='Bundle_Key#2026x'
}

@test "bundle: password goes in a 0600 --from-json file, not on argv" {
    source "${LIB_DIR}/ds_lib.sh"
    run ds_generate_connector_bundle "$CONN" "$KEY" "${BATS_TEST_TMPDIR}/bundle.zip"
    [ "$status" -eq 0 ]
    grep -q -- 'generate-on-prem-connector-configuration --from-json file://' "${OCI_LOG}"
    run grep -e '--password' -e "$KEY" "${OCI_LOG}"
    [ "$status" -ne 0 ]
    [ "$(jq -r '.onPremConnectorId' "${JSON_COPY}")" = "$CONN" ]
    [ "$(jq -r '.password' "${JSON_COPY}")" = "$KEY" ]
    [ "$(jq -r '.file' "${JSON_COPY}")" = "${BATS_TEST_TMPDIR}/bundle.zip" ]
    [ "$(cat "${JSON_COPY}.mode")" = "600" ]
    # not on the argv of jq either
    run grep -F -- "$KEY" "${JQ_LOG}"
    [ "$status" -ne 0 ]
}

@test "bundle: the request file is removed after the call" {
    source "${LIB_DIR}/ds_lib.sh"
    run ds_generate_connector_bundle "$CONN" "$KEY" "${BATS_TEST_TMPDIR}/bundle.zip"
    [ "$status" -eq 0 ]
    run bash -c "ls '${TMPDIR}'/ds_bundle.* 2> /dev/null"
    [ -z "$output" ]
}

@test "bundle: a password without special character is rejected with the rule" {
    source "${LIB_DIR}/ds_lib.sh"
    run ds_generate_connector_bundle "$CONN" "BundleKey2026x" "${BATS_TEST_TMPDIR}/bundle.zip"
    [ "$status" -ne 0 ]
    [[ "$output" == *"special character"* ]]
    [ ! -s "${OCI_LOG}" ]
}
