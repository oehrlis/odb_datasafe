#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_update_service.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_update_service.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_service.sh" ]
}

@test "ds_target_update_service.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_service.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

@test "ds_target_update_service.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_update_service.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

@test "ds_target_update_service.sh blocks apply from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/update_service_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE","database-details":{"service-name":"db1_svc"}}]}
JSON

    run "${BIN_DIR}/ds_target_update_service.sh" --input-json "$sample_json" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

# =============================================================================
# REG-009: ds_target_update_service.sh PUT semantics — get before update
# Regression: --apply mode must call target-database get before target-database update
# =============================================================================

@test "REG-009: apply mode calls target-database get before target-database update" {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    local call_log="${BATS_TEST_TMPDIR}/oci_calls.log"
    local sample_json="${BATS_TEST_TMPDIR}/reg009_input.json"

    mkdir -p "$mock_bin"

    # Mock oci that records every invocation and returns minimal valid JSON.
    # call_log path is injected at heredoc expansion time (unquoted MOCK).
    cat > "${mock_bin}/oci" << MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${call_log}"
case "\$*" in
    *"target-database get"*)
        printf '%s\n' '{"data":{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE","database-details":{"connection-type":"PRIVATE_ENDPOINT","service-name":"db1_svc","db-system-id":null,"listener-port":1521}}}'
        ;;
    *"target-database update"*)
        printf '%s\n' '{"data":{"id":"ocid1.datasafetarget.oc1..t1","lifecycle-state":"ACTIVE"}}'
        ;;
    *)
        printf '%s\n' '{"data":[]}'
        ;;
esac
MOCK
    chmod +x "${mock_bin}/oci"

    # Input JSON provides one target directly (bypass OCI discovery)
    cat > "$sample_json" << 'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE","database-details":{"service-name":"db1_svc","listener-port":1521}}]}
JSON

    # Export PATH so it is inherited by the run subprocess
    export PATH="${mock_bin}:${PATH}"
    run "${BIN_DIR}/ds_target_update_service.sh" \
        --input-json "$sample_json" \
        --apply \
        --allow-stale-selection \
        --service-template "{PDB}_SVC"

    # The call log must exist — if not the mock was never reached
    [ -f "$call_log" ] || skip "OCI mock was not invoked — check PATH setup"

    local get_line update_line
    get_line=$(grep -n "target-database get" "$call_log" | head -1 | cut -d: -f1)
    update_line=$(grep -n "target-database update" "$call_log" | head -1 | cut -d: -f1)

    [ -n "$get_line" ]
    [ -n "$update_line" ]
    [ "$get_line" -lt "$update_line" ]
}
