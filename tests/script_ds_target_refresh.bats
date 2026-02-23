#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_refresh.sh shows help with phase3 safeguard options" {
    run "${BIN_DIR}/ds_target_refresh.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
    [[ "$output" == *"--allow-stale-selection"* ]]
    [[ "$output" == *"--max-snapshot-age AGE"* ]]
}

@test "ds_target_refresh.sh blocks apply refresh from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/refresh_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"NEEDS_ATTENTION"}]}
JSON

    run "${BIN_DIR}/ds_target_refresh.sh" --input-json "$sample_json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

@test "ds_target_refresh.sh allows dry-run from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/refresh_input_dryrun.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"NEEDS_ATTENTION"}]}
JSON

    run "${BIN_DIR}/ds_target_refresh.sh" --input-json "$sample_json" --dry-run
    [ "$status" -eq 0 ]
}
