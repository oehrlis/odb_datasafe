#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
}

# ---------------------------------------------------------------------------
# Help / usage
# ---------------------------------------------------------------------------

@test "ds_target_move.sh --help exits 0 and shows scope flags" {
    run "${BIN_DIR}/ds_target_move.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
    [[ "$output" == *"--filter"* ]]
}

# ---------------------------------------------------------------------------
# Required flag validation
# ---------------------------------------------------------------------------

@test "ds_target_move.sh requires -D/--dest-compartment" {
    run "${BIN_DIR}/ds_target_move.sh" -T some-target
    [ "$status" -ne 0 ]
    [[ "$output" == *"-D"* || "$output" == *"dest"* || "$output" == *"Destination"* ]]
}

# ---------------------------------------------------------------------------
# Mutually-exclusive flag validation (no OCI mock needed)
# ---------------------------------------------------------------------------

@test "ds_target_move.sh --all and -c are mutually exclusive" {
    run "${BIN_DIR}/ds_target_move.sh" --all -c some-compartment -D dest-comp
    [ "$status" -ne 0 ]
}

@test "ds_target_move.sh --all and -T are mutually exclusive" {
    run "${BIN_DIR}/ds_target_move.sh" --all -T some-target -D dest-comp
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Filter regex validation (no OCI mock needed)
# ---------------------------------------------------------------------------

@test "ds_target_move.sh rejects invalid --filter regex" {
    run "${BIN_DIR}/ds_target_move.sh" -T some-target -D dest-comp --filter '[invalid'
    [ "$status" -ne 0 ]
}
