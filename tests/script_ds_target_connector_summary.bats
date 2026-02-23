#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
}

@test "ds_target_connector_summary.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_connector_summary.sh" ]
    [ -x "${BIN_DIR}/ds_target_connector_summary.sh" ]
}

@test "ds_target_connector_summary.sh shows help message" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}
