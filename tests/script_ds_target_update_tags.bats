#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_update_tags.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_update_tags.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_tags.sh" ]
}

@test "ds_target_update_tags.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

@test "ds_target_update_tags.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

@test "ds_target_update_tags.sh blocks apply from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/update_tags_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE"}]}
JSON

    run "${BIN_DIR}/ds_target_update_tags.sh" --input-json "$sample_json" --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-stale-selection"* ]]
}
