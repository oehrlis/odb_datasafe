#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_list_connector.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_list_connector.sh" ]
    [ -x "${BIN_DIR}/ds_target_list_connector.sh" ]
}

@test "ds_target_list_connector.sh shows help message" {
    run "${BIN_DIR}/ds_target_list_connector.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}
