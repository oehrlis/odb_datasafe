#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
}

@test "ds_target_list.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_list.sh" ]
    [ -x "${BIN_DIR}/ds_target_list.sh" ]
}

@test "ds_target_list.sh shows help message" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "ds_target_list.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

@test "ds_target_list.sh accepts overview option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--overview"* ]]
}

@test "ds_target_list.sh accepts overview-no-members option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--overview-no-members"* ]]
}

@test "ds_target_list.sh accepts overview-truncate-members option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--overview-truncate-members"* ]]
}
