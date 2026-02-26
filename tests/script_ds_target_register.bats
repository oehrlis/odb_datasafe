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

@test "ds_target_register.sh defaults to help without arguments" {
    run "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
}

@test "ds_target_register.sh help includes default connector and compartment hints" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"DS_REGISTER_COMPARTMENT"* ]]
    [[ "$output" == *"ONPREM_CONNECTOR_LIST"* ]]
}

@test "ds_target_register.sh help documents host or cluster requirement" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Specify --host or --cluster"* ]] || [[ "$output" == *"required with --host as alternative"* ]]
}

@test "ds_target_register.sh uses valid create wait states" {
    run grep -E -- '--wait-for-state (SUCCEEDED|FAILED)' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]

    run grep -E -- '--wait-for-state ACTIVE' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -ne 0 ]
}

@test "ds_target_register.sh uses die message before exit code" {
    run grep -E -- 'die "Target registration failed" 2' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}
