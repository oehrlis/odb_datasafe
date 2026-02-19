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
}

@test "ds_target_update_tags.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}
