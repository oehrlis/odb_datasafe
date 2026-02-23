#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_update_credentials.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_update_credentials.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_credentials.sh" ]
}

@test "ds_target_update_credentials.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"--ds-user"* ]]
    [[ "$output" == *"--ds-secret"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

@test "ds_target_update_credentials.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

@test "ds_target_update_credentials.sh accepts force option" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--force"* ]]
}

@test "ds_target_update_credentials.sh blocks apply from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/update_credentials_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE"}]}
JSON

    run "${BIN_DIR}/ds_target_update_credentials.sh" --input-json "$sample_json" --apply -U testuser -P testpass
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-stale-selection"* ]]
}
