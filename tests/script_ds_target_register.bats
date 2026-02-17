#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_register.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_register.sh" ]
    [ -x "${BIN_DIR}/ds_target_register.sh" ]
}

@test "ds_target_register.sh shows help message" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"--ds-secret"* ]]
    [[ "$output" == *"--secret-file"* ]]
}
