#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_connector_update.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_connector_update.sh" ]
    [ -x "${BIN_DIR}/ds_connector_update.sh" ]
}

@test "ds_connector_update.sh shows help message" {
    run "${BIN_DIR}/ds_connector_update.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}
