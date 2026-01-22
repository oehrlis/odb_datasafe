#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# Test Suite: ds_target_list_connector.sh
# Purpose...: Test Oracle Data Safe on-premises connector list functionality
# ------------------------------------------------------------------------------

setup() {
    # Set test environment
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export SCRIPT_UNDER_TEST="${BIN_DIR}/ds_target_list_connector.sh"
    
    # Skip tests if script doesn't exist
    if [[ ! -f "${SCRIPT_UNDER_TEST}" ]]; then
        skip "Script not found: ${SCRIPT_UNDER_TEST}"
    fi
}

# =============================================================================
# Basic Functionality Tests
# =============================================================================

@test "ds_target_list_connector.sh: Script exists and is executable" {
    [[ -f "${SCRIPT_UNDER_TEST}" ]]
    [[ -x "${SCRIPT_UNDER_TEST}" ]]
}

@test "ds_target_list_connector.sh: Help option displays usage" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "ds_target_list_connector.sh" ]]
    [[ "$output" =~ "List Oracle Data Safe on-premises connectors" ]]
}

@test "ds_target_list_connector.sh: Version option shows version" {
    run "${SCRIPT_UNDER_TEST}" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "0.5.3" ]]
}

@test "ds_target_list_connector.sh: Help shows compartment configuration info" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "DS_ROOT_COMP" ]]
    [[ "$output" =~ ".env" ]]
    [[ "$output" =~ "datasafe.conf" ]]
    [[ "$output" =~ "-c, --compartment" ]]
}

@test "ds_target_list_connector.sh: Help shows connector-specific options" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "-C, --connectors" ]]
    [[ "$output" =~ "-L, --lifecycle" ]]
    [[ "$output" =~ "-f, --format" ]]
    [[ "$output" =~ "-F, --fields" ]]
}

@test "ds_target_list_connector.sh: Help shows available output formats" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "table" ]]
    [[ "$output" =~ "json" ]]
    [[ "$output" =~ "csv" ]]
}

@test "ds_target_list_connector.sh: Help shows available fields" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "display-name" ]]
    [[ "$output" =~ "lifecycle-state" ]]
    [[ "$output" =~ "available-version" ]]
    [[ "$output" =~ "time-created" ]]
}

@test "ds_target_list_connector.sh: Help shows usage examples" {
    run "${SCRIPT_UNDER_TEST}" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Examples:" ]]
    [[ "$output" =~ "ds_target_list_connector.sh" ]]
}

# =============================================================================
# Argument Validation Tests
# =============================================================================

@test "ds_target_list_connector.sh: Invalid option produces error" {
    run "${SCRIPT_UNDER_TEST}" --invalid-option
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Unknown option" ]]
}

@test "ds_target_list_connector.sh: Invalid output format produces error" {
    skip "Requires mock OCI environment"
}

@test "ds_target_list_connector.sh: Missing option value produces error" {
    run "${SCRIPT_UNDER_TEST}" --compartment
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Structure Validation Tests
# =============================================================================

@test "ds_target_list_connector.sh: Follows standard script structure" {
    run grep -c "# BOOTSTRAP & CONFIGURATION" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" -eq 1 ]]
    
    run grep -c "# FUNCTIONS" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" -eq 1 ]]
    
    run grep -c "# MAIN" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" -eq 1 ]]
}

@test "ds_target_list_connector.sh: Has required functions" {
    run grep -E "^(usage|parse_args|validate_inputs|do_work|main)\(\)" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "usage()" ]]
    [[ "$output" =~ "parse_args()" ]]
    [[ "$output" =~ "validate_inputs()" ]]
    [[ "$output" =~ "do_work()" ]]
    [[ "$output" =~ "main()" ]]
}

@test "ds_target_list_connector.sh: Functions have proper headers" {
    run grep "^# Function:" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    
    run grep "^# Purpose.:" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Uses strict mode" {
    run grep "set -euo pipefail" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Has explicit exit 0 at end" {
    run tail -5 "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "exit 0" ]]
}

@test "ds_target_list_connector.sh: Uses correct script version from .extension" {
    run grep "SCRIPT_VERSION" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ".extension" ]]
}

@test "ds_target_list_connector.sh: Sources ds_lib.sh from correct location" {
    run grep 'source.*LIB_DIR.*ds_lib.sh' "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Connector-Specific Tests
# =============================================================================

@test "ds_target_list_connector.sh: Default output format is table" {
    run grep 'OUTPUT_FORMAT:=table' "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Default fields include display-name" {
    run grep 'FIELDS:=.*display-name' "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Has connector list function" {
    run grep "list_connectors_in_compartment()" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Uses data-safe on-prem-connector commands" {
    run grep "data-safe on-prem-connector" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Has show_details functions" {
    run grep "show_details_table()" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    
    run grep "show_details_json()" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    
    run grep "show_details_csv()" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Code Quality Tests
# =============================================================================

@test "ds_target_list_connector.sh: Uses bash not sh" {
    run head -1 "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "#!/usr/bin/env bash" ]]
    [[ ! "$output" =~ "#!/bin/sh" ]]
}

@test "ds_target_list_connector.sh: Uses readonly for constants" {
    run grep "readonly SCRIPT" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}

@test "ds_target_list_connector.sh: Has proper script header" {
    run head -15 "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "OraDBA" ]]
    [[ "$output" =~ "ds_target_list_connector.sh" ]]
    [[ "$output" =~ "Purpose" ]]
}

@test "ds_target_list_connector.sh: Version in header matches extension" {
    run grep "Version....: v0.5.3" "${SCRIPT_UNDER_TEST}"
    [[ "$status" -eq 0 ]]
}
