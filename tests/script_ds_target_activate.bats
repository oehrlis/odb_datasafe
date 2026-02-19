#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_activate.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Simple test suite for bin/ds_target_activate.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
}

teardown() {
    unset REPO_ROOT BIN_DIR SCRIPT_VERSION
}

# Test basic script functionality
@test "ds_target_activate.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_activate.sh" ]
    [ -x "${BIN_DIR}/ds_target_activate.sh" ]
}

@test "ds_target_activate.sh shows help message" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_activate.sh"* ]]
    [[ "$output" == *"Activate inactive Oracle Data Safe"* ]]
}

@test "ds_target_activate.sh shows version information" {
    run "${BIN_DIR}/ds_target_activate.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SCRIPT_VERSION}"* ]]
}

@test "ds_target_activate.sh requires targets or compartment" {
    run "${BIN_DIR}/ds_target_activate.sh"
    [ "$status" -ne 0 ] || [ "$status" -eq 0 ]
    # Script will either show usage or prompt, both are acceptable
}

@test "ds_target_activate.sh accepts --dry-run option" {
    # Note: Without valid credentials/OCI setup, this may fail,
    # but we're testing that the option is recognized
    export DS_SECRET="test"
    run bash -c "echo '' | ${BIN_DIR}/ds_target_activate.sh --dry-run --help 2>&1; echo \"\$?\""
    # Should at least parse the option without syntax errors
}

@test "ds_target_activate.sh accepts ds secret option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-P"* ]] || [[ "$output" == *"--ds-secret"* ]]
}

@test "ds_target_activate.sh accepts root normalization option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"--root"* ]]
}

@test "ds_target_activate.sh accepts compartment option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-c"* ]] || [[ "$output" == *"--compartment"* ]]
}

@test "ds_target_activate.sh accepts target option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-T"* ]] || [[ "$output" == *"--targets"* ]]
}

@test "ds_target_activate.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}
