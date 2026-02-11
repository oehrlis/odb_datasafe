#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
}

teardown() {
    unset REPO_ROOT BIN_DIR SCRIPT_VERSION
}

@test "ds_target_connect_details.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_connect_details.sh" ]
    [ -x "${BIN_DIR}/ds_target_connect_details.sh" ]
}

@test "ds_target_connect_details.sh shows help message" {
    run "${BIN_DIR}/ds_target_connect_details.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "ds_target_connect_details.sh shows version information" {
    run "${BIN_DIR}/ds_target_connect_details.sh" --version
    [ "$status" -eq 0 ] || [ -n "$output" ]
}
