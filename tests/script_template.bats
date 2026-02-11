#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "template.sh exists and is executable" {
    [ -f "${BIN_DIR}/template.sh" ]
    [ -x "${BIN_DIR}/template.sh" ]
}

@test "template.sh shows help message" {
    run "${BIN_DIR}/template.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}
