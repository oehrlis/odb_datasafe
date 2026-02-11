#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_connector_update.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_connector_update.sh" ]
    [ -x "${BIN_DIR}/ds_connector_update.sh" ]
}

@test "ds_connector_update.sh shows help message with --help" {
    run "${BIN_DIR}/ds_connector_update.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "ds_connector_update.sh shows usage when no parameters provided" {
    run "${BIN_DIR}/ds_connector_update.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--connector NAME"* ]]
    [[ "$output" == *"REQUIRED"* ]]
}

@test "ds_connector_update.sh usage mentions compartment options" {
    run "${BIN_DIR}/ds_connector_update.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DS_ROOT_COMP"* ]]
    [[ "$output" == *"DS_CONNECTOR_COMP"* ]]
    [[ "$output" == *"-c, --compartment"* ]]
}

@test "ds_connector_update.sh usage mentions version checking" {
    run "${BIN_DIR}/ds_connector_update.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking local and online connector versions"* ]]
}

@test "ds_connector_update.sh requires connector name" {
    run "${BIN_DIR}/ds_connector_update.sh" -c test-compartment
    [ "$status" -eq 1 ]
    [[ "$output" == *"CONNECTOR_NAME"* ]] || [[ "$output" == *"connector"* ]]
}
