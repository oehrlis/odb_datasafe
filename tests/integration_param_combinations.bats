#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: integration_param_combinations.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Purpose....: Integration tests for parameter combinations and error handling
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Load test helpers
load test_helper

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    
    # Create simple mock OCI environment
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create a basic mock OCI that always succeeds with empty data
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Basic mock OCI CLI for parameter testing
case "$*" in
    *"--version"*)
        echo "3.45.0"
        ;;
    *"--help"*)
        echo "Mock OCI CLI"
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
}

teardown() {
    unset TEST_TEMP_DIR
}

# ==============================================================================
# Integration Tests: Help and Version
# ==============================================================================

@test "Integration: All main scripts support --help" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_list_connector.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_connector.sh"
        "ds_target_update_credentials.sh"
        "ds_target_register.sh"
        "ds_target_activate.sh"
        "ds_find_untagged_targets.sh"
        "ds_connector_update.sh"
        "ds_target_connector_summary.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "${BIN_DIR}/${script}" ]; then
            run "${BIN_DIR}/${script}" --help
            [ "$status" -eq 0 ]
            [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
        fi
    done
}

@test "Integration: All main scripts support --version" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_list_connector.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_connector.sh"
        "ds_target_register.sh"
        "ds_target_activate.sh"
        "ds_find_untagged_targets.sh"
        "ds_connector_update.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "${BIN_DIR}/${script}" ]; then
            run "${BIN_DIR}/${script}" --version
            [ "$status" -eq 0 ]
            [[ "$output" == *"${SCRIPT_VERSION}"* ]] || [[ "$output" == *"v"*"."* ]]
        fi
    done
}

# ==============================================================================
# Integration Tests: Invalid Arguments
# ==============================================================================

@test "Integration: Scripts reject unknown options" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh"
    )
    
    for script in "${scripts[@]}"; do
        run "${BIN_DIR}/${script}" --unknown-invalid-option 2>&1 || true
        [ "$status" -ne 0 ]
        [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"unrecognized"* ]]
    done
}

@test "Integration: Scripts reject missing required parameters" {
    # Intent-driven scripts show usage on empty args
    run "${BIN_DIR}/ds_target_update_connector.sh" 2>&1 || true
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    
    # ds_target_register.sh also shows usage on empty args
    run "${BIN_DIR}/ds_target_register.sh" 2>&1 || true
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

# ==============================================================================
# Integration Tests: Output Format Options
# ==============================================================================

@test "Integration: ds_target_list.sh supports multiple output formats" {
    local formats=("table" "json" "csv")
    
    for format in "${formats[@]}"; do
        run "${BIN_DIR}/ds_target_list.sh" -f "$format" -c "ocid1.test.invalid" 2>&1 || true
        # Should accept the format parameter (even if it fails due to invalid compartment)
        [[ "$output" != *"invalid format"* ]] && [[ "$output" != *"Unknown option"* ]]
    done
}

@test "Integration: ds_target_list.sh rejects invalid output format" {
    run "${BIN_DIR}/ds_target_list.sh" -f "invalid-format" -c "ocid1.test" 2>&1 || true
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Integration Tests: Compartment Parameter
# ==============================================================================

@test "Integration: Scripts accept compartment OCID format" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..aaa123" 2>&1 || true
    # Should accept OCID format (may fail at OCI level)
    [[ "$output" != *"invalid format"* ]]
}

@test "Integration: Scripts accept compartment name" {
    run "${BIN_DIR}/ds_target_list.sh" -c "my-compartment-name" 2>&1 || true
    # Should accept name format (may fail at resolution)
    [[ "$output" != *"invalid format"* ]]
}

@test "Integration: Scripts use DS_ROOT_COMP when no compartment specified" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..test"
    run "${BIN_DIR}/ds_target_list.sh" 2>&1 || true
    # Should use DS_ROOT_COMP
    [[ "$output" != *"compartment required"* ]] || [[ "$output" == *"DS_ROOT_COMP"* ]]
    unset DS_ROOT_COMP
}

# ==============================================================================
# Integration Tests: Dry-Run Mode
# ==============================================================================

@test "Integration: Update scripts default to dry-run mode" {
    # ds_target_update_tags.sh should default to dry-run
    run "${BIN_DIR}/ds_target_update_tags.sh" -v -c "ocid1.test" 2>&1 || true
    [[ "$output" == *"Dry-run"* ]] || [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"no changes"* ]]
}

@test "Integration: Update scripts support explicit dry-run flag" {
    run "${BIN_DIR}/ds_target_list.sh" -n -c "ocid1.test" 2>&1 || true
    # -n flag should be accepted
    [[ "$output" != *"Unknown option: -n"* ]]
}

# ==============================================================================
# Integration Tests: Verbosity Options
# ==============================================================================

@test "Integration: Scripts support verbose mode" {
    run "${BIN_DIR}/ds_target_list.sh" -v -c "ocid1.test" 2>&1 || true
    # -v flag should be accepted
    [[ "$output" != *"Unknown option: -v"* ]]
}

@test "Integration: Scripts support quiet mode" {
    run "${BIN_DIR}/ds_target_list.sh" -q -c "ocid1.test" 2>&1 || true
    # -q flag should be accepted
    [[ "$output" != *"Unknown option: -q"* ]]
}

@test "Integration: Scripts support debug mode" {
    run "${BIN_DIR}/ds_target_list.sh" -d -c "ocid1.test" 2>&1 || true
    # -d flag should be accepted
    [[ "$output" != *"Unknown option: -d"* ]]
}

# ==============================================================================
# Integration Tests: OCI Profile and Region
# ==============================================================================

@test "Integration: Scripts support custom OCI profile" {
    run "${BIN_DIR}/ds_target_list.sh" --oci-profile "CUSTOM" -c "ocid1.test" 2>&1 || true
    # --oci-profile flag should be accepted
    [[ "$output" != *"Unknown option"* ]]
}

@test "Integration: Scripts support custom OCI region" {
    run "${BIN_DIR}/ds_target_list.sh" --oci-region "us-ashburn-1" -c "ocid1.test" 2>&1 || true
    # --oci-region flag should be accepted
    [[ "$output" != *"Unknown option"* ]]
}

# ==============================================================================
# Integration Tests: Complex Parameter Combinations
# ==============================================================================

@test "Integration: Combining multiple options works" {
    run "${BIN_DIR}/ds_target_list.sh" -v -d -f json -c "ocid1.test" 2>&1 || true
    # Multiple options should be accepted
    [[ "$output" != *"Unknown option"* ]]
}

@test "Integration: Long and short options can be mixed" {
    run "${BIN_DIR}/ds_target_list.sh" -v --format json -c "ocid1.test" 2>&1 || true
    # Mix of short and long options should work
    [[ "$output" != *"Unknown option"* ]]
}

@test "Integration: ds_target_list.sh supports short mode aliases" {
    local mode_flags=("-C" "-H" "-P" "-R")

    for mode_flag in "${mode_flags[@]}"; do
        run "${BIN_DIR}/ds_target_list.sh" "$mode_flag" -c "ocid1.test" 2>&1 || true
        [[ "$output" != *"Unknown option"* ]]
    done
}

# ==============================================================================
# Integration Tests: Workflow Compatibility
# ==============================================================================

@test "Integration: Scripts can be piped together" {
    # Test that output format allows piping
    run bash -c "${BIN_DIR}/ds_target_list.sh -f json -c ocid1.test 2>/dev/null | head -1" || true
    # Should produce output that can be piped
    [ "$status" -eq 0 ]
}

@test "Integration: Scripts exit codes are consistent" {
    # Success
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    
    # Error
    run "${BIN_DIR}/ds_target_list.sh" --invalid-option 2>&1 || true
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Integration Tests: Performance
# ==============================================================================

@test "Integration: Scripts respond quickly to --help" {
    local start_time=$(date +%s)
    run "${BIN_DIR}/ds_target_list.sh" --help
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    [ "$status" -eq 0 ]
    # Help should be quick (allow boundary jitter/slow CI)
    [ "$duration" -le 3 ]
}

@test "Integration: Scripts respond quickly to --version" {
    local start_time=$(date +%s)
    run "${BIN_DIR}/ds_target_list.sh" --version
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    [ "$status" -eq 0 ]
    # Version should be quick (allow boundary jitter/slow CI)
    [ "$duration" -le 3 ]
}

# ==============================================================================
# Integration Tests: Error Messages
# ==============================================================================

@test "Integration: Scripts provide helpful error messages" {
    run "${BIN_DIR}/ds_target_list.sh" --invalid-option 2>&1 || true
    [ "$status" -ne 0 ]
    # Error message should be informative
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"Error"* ]]
}

@test "Integration: Scripts show usage on parameter errors" {
    run "${BIN_DIR}/ds_target_update_connector.sh" 2>&1 || true
    [ "$status" -eq 0 ]
    # Should show usage or helpful error
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"required"* ]] || [[ "$output" == *"ERROR"* ]]
}
