#!/usr/bin/env bats

# Regression: parse_args ended on "[[ ${#remaining[@]} -gt 0 ]] && log_warn",
# returned 1 whenever no positional argument was given and tripped the ERR
# trap - every normal call aborted before validate_inputs with no reason given.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
    # keep the host's ORADBA_ETC/datasafe.conf out of the test
    export ORADBA_ETC="${BATS_TEST_TMPDIR}/etc"
    mkdir -p "${ORADBA_ETC}"
    unset DS_ROOT_COMP

    export TRAILS_FILE="${BATS_TEST_TMPDIR}/trails.json"
    cat > "${TRAILS_FILE}" <<'JSON'
{"data":{"items":[
 {"id":"ocid1.audittrail.oc1..a1","display-name":"trail1","target-id":"ocid1.datasafetargetdatabase.oc1..t1",
  "lifecycle-state":"ACTIVE","status":"COLLECTING","is-auto-purge-enabled":true},
 {"id":"ocid1.audittrail.oc1..a2","display-name":"trail2","target-id":"ocid1.datasafetargetdatabase.oc1..t2",
  "lifecycle-state":"ACTIVE","status":"NOT_STARTED","is-auto-purge-enabled":false}
]}}
JSON

    # fake oci: auth check and audit-trail list succeed, compartment is an OCID
    cat > "${TEST_BIN_DIR}/oci" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *"os ns get"*) echo '{"data":"ns"}' ;;
    *"audit-trail list"*) cat "${TRAILS_FILE}" ;;
    *) echo '{"data":[]}' ;;
esac
EOF
    chmod +x "${TEST_BIN_DIR}/oci"
}

@test "ds_audit_trail_state: snapshot run without positional args succeeds" {
    run "${BIN_DIR}/ds_audit_trail_state.sh" --trails-json "${TRAILS_FILE}" -f json
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error in"* ]]
    [[ "$output" == *'"trails": 2'* ]]
}

@test "ds_audit_trail_state: -c <compartment> reaches collect_trails" {
    run "${BIN_DIR}/ds_audit_trail_state.sh" -c ocid1.compartment.oc1..test -f json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"trails": 2'* ]]
    [[ "$output" == *'"compartment": "ocid1.compartment.oc1..test"'* ]]
}

@test "ds_audit_trail_state: empty result reports TOTAL 0, not null" {
    printf '{"data":{"items":[]}}\n' > "${TRAILS_FILE}"
    run --separate-stderr "${BIN_DIR}/ds_audit_trail_state.sh" --trails-json "${TRAILS_FILE}" -f json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.summary[] | select(.state=="TOTAL") | .count' <<< "$output")" = "0" ]
}

@test "ds_audit_trail_state: stray positional arg warns and still runs" {
    run "${BIN_DIR}/ds_audit_trail_state.sh" --trails-json "${TRAILS_FILE}" extra
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ignoring unexpected positional argument(s): extra"* ]]
}

@test "ds_audit_trail_state: ignored group-writable config names the fix" {
    printf 'DS_ROOT_COMP=ocid1.compartment.oc1..fromconf\n' > "${ORADBA_ETC}/datasafe.conf"
    chmod 664 "${ORADBA_ETC}/datasafe.conf"
    run "${BIN_DIR}/ds_audit_trail_state.sh" --trails-json "${TRAILS_FILE}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ignoring group/world-writable config file"* ]]
    [[ "$output" == *"NOT applied. Fix: chmod go-w"* ]]
}

@test "error_handler: names the failed command, not just the line" {
    run bash -c "source '${REPO_ROOT}/lib/common.sh'; setup_error_handling; f() { [[ 1 -eq 0 ]] && echo x; }; f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"(exit code: 1): [[ 1 -eq 0 ]]"* ]]
}
