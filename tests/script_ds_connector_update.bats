#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# Test Suite: ds_connector_update.sh
# ------------------------------------------------------------------------------

load test_helper

# Path to script
SCRIPT="${BATS_TEST_DIRNAME}/../bin/ds_connector_update.sh"

# ------------------------------------------------------------------------------
# Setup and Teardown
# ------------------------------------------------------------------------------

setup() {
    # Create temporary test directory
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/test_$$"
    mkdir -p "${TEST_TEMP_DIR}"
    export TEST_TEMP_DIR
}

teardown() {
    # Cleanup
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# ------------------------------------------------------------------------------
# Basic Functionality Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: script exists and is executable" {
    [[ -f "${SCRIPT}" ]]
    [[ -x "${SCRIPT}" ]]
}

@test "ds_connector_update.sh: --help shows usage" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "Usage:" ]]
    [[ "${output}" =~ "ds_connector_update.sh" ]]
}

@test "ds_connector_update.sh: --version shows version" {
    run "${SCRIPT}" --version
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "ds_connector_update.sh" ]]
    [[ "${output}" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "ds_connector_update.sh: -h shows help" {
    run "${SCRIPT}" -h
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "Usage:" ]]
}

@test "ds_connector_update.sh: -V shows version" {
    run "${SCRIPT}" -V
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ------------------------------------------------------------------------------
# Argument Validation Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: fails without connector name" {
    skip_if_no_oci_config
    run "${SCRIPT}"
    [[ "${status}" -ne 0 ]]
    [[ "${output}" =~ "CONNECTOR_NAME" ]]
}

@test "ds_connector_update.sh: fails without compartment" {
    skip_if_no_oci_config
    run "${SCRIPT}" --connector test-connector
    [[ "${status}" -ne 0 ]]
    [[ "${output}" =~ "Compartment required" ]]
}

@test "ds_connector_update.sh: accepts --connector option" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--connector" ]]
}

@test "ds_connector_update.sh: accepts --connector-home option" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--connector-home" ]]
}

@test "ds_connector_update.sh: accepts --skip-download option" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--skip-download" ]]
}

@test "ds_connector_update.sh: accepts --bundle-file option" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--bundle-file" ]]
}

@test "ds_connector_update.sh: accepts --force-new-password option" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--force-new-password" ]]
}

# ------------------------------------------------------------------------------
# Dry-Run Mode Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: supports --dry-run" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--dry-run" ]]
    [[ "${output}" =~ "Dry-run mode" ]]
}

@test "ds_connector_update.sh: supports -n (dry-run)" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "-n, --dry-run" ]]
}

# ------------------------------------------------------------------------------
# Verbose/Debug Mode Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: supports --verbose" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--verbose" ]]
}

@test "ds_connector_update.sh: supports --debug" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--debug" ]]
}

@test "ds_connector_update.sh: supports --quiet" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--quiet" ]]
}

# ------------------------------------------------------------------------------
# OCI Options Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: accepts --oci-profile" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--oci-profile" ]]
}

@test "ds_connector_update.sh: accepts --oci-region" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--oci-region" ]]
}

@test "ds_connector_update.sh: accepts --oci-config" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "--oci-config" ]]
}

# ------------------------------------------------------------------------------
# ShellCheck Compliance
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi
    
    run shellcheck "${SCRIPT}"
    [[ "${status}" -eq 0 ]]
}

# ------------------------------------------------------------------------------
# Documentation Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: help includes examples" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "Examples:" ]]
}

@test "ds_connector_update.sh: help includes environment variables" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "Environment:" ]]
}

@test "ds_connector_update.sh: help includes config files" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "Config Files" ]]
}

@test "ds_connector_update.sh: help includes notes about update process" {
    run "${SCRIPT}" --help
    [[ "${status}" -eq 0 ]]
    [[ "${output}" =~ "connector cannot connect" ]]
    [[ "${output}" =~ "password is stored as base64" ]]
}

# ------------------------------------------------------------------------------
# Error Handling Tests
# ------------------------------------------------------------------------------

@test "ds_connector_update.sh: rejects unknown options" {
    run "${SCRIPT}" --unknown-option
    [[ "${status}" -ne 0 ]]
    [[ "${output}" =~ "Unknown option" ]]
}

@test "ds_connector_update.sh: validates connector name is required" {
    skip_if_no_oci_config
    # Create minimal mock environment
    export DS_CONNECTOR_COMP="ocid1.compartment.oc1..test"
    
    run "${SCRIPT}" -c test-compartment
    [[ "${status}" -ne 0 ]]
    [[ "${output}" =~ "CONNECTOR_NAME" ]]
}
