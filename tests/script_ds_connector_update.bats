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

@test "ds_connector_update.sh usage mentions --datasafe-home option" {
    run "${BIN_DIR}/ds_connector_update.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--datasafe-home"* ]]
    [[ "$output" == *"OraDBA environment"* ]]
}

@test "ds_connector_update.sh usage mentions OraDBA integration" {
    run "${BIN_DIR}/ds_connector_update.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"oradba_homes.conf"* ]]
}

@test "ds_connector_update.sh shows error when mixing --datasafe-home with --connector" {
    run "${BIN_DIR}/ds_connector_update.sh" --datasafe-home dscon4 --connector my-connector
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot mix"* ]] || [[ "$output" == *"Conflicting"* ]]
}

@test "ds_connector_update.sh allows --datasafe-home with --compartment" {
    run "${BIN_DIR}/ds_connector_update.sh" --datasafe-home dscon4 --compartment test-comp
    [ "$status" -eq 1 ]
    [[ "$output" != *"Cannot mix --datasafe-home"* ]]
}

@test "ds_connector_register_oradba.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_connector_register_oradba.sh" ]
    [ -x "${BIN_DIR}/ds_connector_register_oradba.sh" ]
}

@test "ds_connector_register_oradba.sh shows help message with --help" {
    run "${BIN_DIR}/ds_connector_register_oradba.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "ds_connector_register_oradba.sh requires --datasafe-home parameter" {
    run "${BIN_DIR}/ds_connector_register_oradba.sh" --connector my-connector
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATASAFE_ENV"* ]] || [[ "$output" == *"datasafe-home"* ]]
}

@test "ds_connector_register_oradba.sh requires --connector parameter" {
    run "${BIN_DIR}/ds_connector_register_oradba.sh" --datasafe-home dscon4
    [ "$status" -eq 1 ]
    [[ "$output" == *"CONNECTOR_INFO"* ]] || [[ "$output" == *"connector"* ]]
}
