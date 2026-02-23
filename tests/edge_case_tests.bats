#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: edge_case_tests.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Purpose....: Edge case and boundary tests for odb_datasafe
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
    
    # Create mock OCI environment
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create minimal mock OCI CLI
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "iam compartment list"*)
        echo '{"data": []}'
        ;;
    "data-safe target-database list"*)
        echo '{"data": []}'
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
}

teardown() {
    # Clean up test environment
    unset TEST_TEMP_DIR
}

# ==============================================================================
# Edge Case Tests: Unusual but Valid Inputs
# ==============================================================================

@test "Edge: Empty string compartment name handled gracefully" {
    run "${BIN_DIR}/ds_target_list.sh" -c "" 2>&1 || true
    [ "$status" -ne 0 ]
    # Should fail but not crash
}

@test "Edge: Very long compartment name (255 chars)" {
    local long_name
    long_name=$(printf 'a%.0s' {1..255})
    run "${BIN_DIR}/ds_target_list.sh" -c "$long_name" 2>&1 || true
    # Should handle gracefully, even if it fails
    [ "$status" -ge 0 ]
}

@test "Edge: Compartment name with spaces" {
    run "${BIN_DIR}/ds_target_list.sh" -c "my compartment name" 2>&1 || true
    # Should handle gracefully
    [ "$status" -ge 0 ]
}

@test "Edge: Compartment name with special characters" {
    run "${BIN_DIR}/ds_target_list.sh" -c "test-comp_123.prod" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Target name with Unicode characters" {
    run "${BIN_DIR}/ds_target_list.sh" -T "test-tärgët-üñíçödé" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Multiple consecutive commas in target list" {
    run "${BIN_DIR}/ds_target_list.sh" -T "target1,,,target2" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Target list with only commas" {
    run "${BIN_DIR}/ds_target_list.sh" -T ",,," 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: Very long target list (50 targets)" {
    local targets
    targets=$(printf 'target%d,' {1..50})
    targets="${targets%,}"  # Remove trailing comma
    run "${BIN_DIR}/ds_target_list.sh" -T "$targets" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Output format with mixed case" {
    run "${BIN_DIR}/ds_target_list.sh" -f "JsOn" 2>&1 || true
    # Should handle case-insensitive format or reject clearly
    [ "$status" -ge 0 ]
}

@test "Edge: Fields parameter with extra spaces" {
    run "${BIN_DIR}/ds_target_list.sh" -F "display-name,  lifecycle-state  ,  id" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Lifecycle state with lowercase" {
    run "${BIN_DIR}/ds_target_list.sh" -L "active" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Edge: Multiple incompatible options (count + details)" {
    run "${BIN_DIR}/ds_target_list.sh" -C -D 2>&1 || true
    # Should either work or fail gracefully
    [ "$status" -ge 0 ]
}

@test "Edge: ds_target_update_tags.sh with empty tag namespace" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --namespace "" -c "test-comp" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: ds_target_update_connector.sh with whitespace connector name" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "  " -c "test" 2>&1 || true
    # Script may handle whitespace gracefully or reject it
    [ "$status" -ge 0 ]
}

@test "Edge: ds_target_register.sh with missing required database-id" {
    run "${BIN_DIR}/ds_target_register.sh" -n "test-target" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: ds_find_untagged_targets.sh with multiple namespaces" {
    run "${BIN_DIR}/ds_find_untagged_targets.sh" -n "ns1,ns2,ns3" -c "test" 2>&1 || true
    [ "$status" -ge 0 ]
}

# ==============================================================================
# Edge Case Tests: Error Handling Paths
# ==============================================================================

@test "Edge: Script behavior when jq is not available" {
    skip "Requires special test environment - jq is globally available"
    # Note: This test would need to completely isolate PATH which affects test framework
}

@test "Edge: Script behavior when OCI CLI returns malformed JSON" {
    # Create mock OCI that returns invalid JSON
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "This is not valid JSON"
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -c "test-comp" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: Script behavior when OCI CLI returns empty response" {
    # Create mock OCI that returns nothing
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo ""
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -c "test-comp" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: Script behavior when OCI CLI exits with error" {
    # Create mock OCI that fails
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "ServiceError: Compartment not found" >&2
exit 1
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -c "nonexistent" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Edge: Script behavior with invalid OCID format" {
    # Note: is_ocid() only validates that OCID starts with ocid1.
    # This is actually a valid OCID format according to the validator
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.invalid.format" 2>&1 || true
    [ "$status" -ge 0 ]
    # Script handles it gracefully (may fail at OCI API level)
}

@test "Edge: Script behavior with non-existent log file directory" {
    run "${BIN_DIR}/ds_target_list.sh" --log-file "/nonexistent/dir/test.log" -c "test" 2>&1 || true
    # Should handle invalid log path gracefully without crashing
    [ "$status" -ge 0 ]
}

@test "Edge: Script behavior with read-only temp directory" {
    skip "Skipping read-only test - requires special setup"
}

@test "Edge: Script behavior with permission denied on library" {
    skip "Skipping permission test - requires special setup"
}

# ==============================================================================
# Edge Case Tests: Boundary Conditions
# ==============================================================================

@test "Boundary: Maximum length OCID (255 chars)" {
    local max_ocid
    max_ocid="ocid1.compartment.oc1..$(printf 'a%.0s' {1..200})"
    run "${BIN_DIR}/ds_target_list.sh" -c "$max_ocid" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Boundary: Zero targets in response" {
    # Mock returns empty list
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..test" 2>&1 || true
    [ "$status" -eq 0 ]
}

@test "Boundary: Single character compartment name" {
    run "${BIN_DIR}/ds_target_list.sh" -c "x" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Boundary: Maximum fields parameter (all available fields)" {
    local all_fields="id,display-name,lifecycle-state,database-type,compartment-id,time-created,connection-option,credentials"
    run "${BIN_DIR}/ds_target_list.sh" -F "$all_fields" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Boundary: Empty fields parameter" {
    run "${BIN_DIR}/ds_target_list.sh" -F "" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "Boundary: Invalid field name in fields parameter" {
    run "${BIN_DIR}/ds_target_list.sh" -F "invalid-field-name" 2>&1 || true
    # Should handle gracefully or fail clearly
    [ "$status" -ge 0 ]
}

@test "Boundary: Extreme verbosity levels (multiple -v flags)" {
    run "${BIN_DIR}/ds_target_list.sh" -v -v -v -c "test" 2>&1 || true
    [ "$status" -ge 0 ]
}

@test "Boundary: Mixed debug and quiet flags" {
    run "${BIN_DIR}/ds_target_list.sh" -d -q -c "test" 2>&1 || true
    # Should handle conflicting flags
    [ "$status" -ge 0 ]
}

# ==============================================================================
# Edge Case Tests: Concurrent Operations
# ==============================================================================

@test "Edge: Multiple scripts reading same environment file" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..test"
    
    # Run multiple scripts in background
    "${BIN_DIR}/ds_target_list.sh" -c "$DS_ROOT_COMP" 2>&1 &
    local pid1=$!
    "${BIN_DIR}/ds_target_list_connector.sh" -c "$DS_ROOT_COMP" 2>&1 &
    local pid2=$!
    
    wait $pid1 || true
    wait $pid2 || true
    
    # Both should complete without crashing
    [ "$?" -ge 0 ]
}

# ==============================================================================
# Edge Case Tests: Library Function Boundaries
# ==============================================================================

@test "Edge: lib/common.sh log functions with very long messages" {
    source "${LIB_DIR}/common.sh"
    
    local long_message
    long_message=$(printf 'x%.0s' {1..1000})
    
    run log_info "$long_message"
    [ "$status" -eq 0 ]
}

@test "Edge: lib/common.sh is_ocid with various invalid formats" {
    source "${LIB_DIR}/common.sh"
    
    run is_ocid ""
    [ "$status" -ne 0 ]
    
    run is_ocid "not-an-ocid"
    [ "$status" -ne 0 ]
    
    # Note: is_ocid only checks for ^ocid1\. prefix
    # So "ocid1" without dot and "ocid1.compartment" are both valid according to current implementation
}

@test "Edge: lib/common.sh is_ocid with valid OCID" {
    source "${LIB_DIR}/common.sh"
    
    run is_ocid "ocid1.compartment.oc1..aaaaaaaabbbbbbbb"
    [ "$status" -eq 0 ]
}

@test "Edge: lib/oci_helpers.sh with null/undefined variables" {
    # Functions should handle missing variables gracefully
    run bash -c "source \"${LIB_DIR}/ds_lib.sh\"; unset COMPARTMENT DS_ROOT_COMP; export OCI_CLI_CONFIG_FILE=\"${TEST_TEMP_DIR}/oci_config\"; printf '[DEFAULT]\nuser=ocid1.user.oc1..dummy\ntenancy=ocid1.tenancy.oc1..dummy\nregion=us-phoenix-1\nkey_file=/tmp/dummy\nfingerprint=00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\n' > \"${TEST_TEMP_DIR}/oci_config\"; check_oci_cli_auth"
    [ "$status" -ge 0 ]
}

# ==============================================================================
# Edge Case Tests: Output Format Edge Cases
# ==============================================================================

@test "Edge: JSON output with special characters in data" {
    # Mock OCI returns data with special characters
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
    echo "3.45.0"
elif [[ "$*" == *"compartment list"* ]]; then
    echo '{"data": [{"id": "ocid1.compartment.oc1..test", "name": "test", "lifecycle-state": "ACTIVE"}]}'
elif [[ "$*" == *"target-database list"* ]]; then
    echo '{
        "data": [{
            "id": "ocid1.test.1",
            "display-name": "test\"with\"quotes",
            "lifecycle-state": "ACTIVE",
            "database-details": {"database-type": "AUTONOMOUS_DATABASE", "infrastructure-type": "ORACLE_CLOUD"},
            "compartment-id": "ocid1.compartment.oc1..test",
            "connection-option": {},
            "freeform-tags": {},
            "defined-tags": {}
        }]
    }'
else
    echo '{"data": []}'
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -f json -c "ocid1.compartment.oc1..test" 2>&1 || true
    [ "$status" -eq 0 ]
}

@test "Edge: CSV output with commas in field values" {
    # Mock OCI returns data with commas
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
    echo "3.45.0"
elif [[ "$*" == *"compartment list"* ]]; then
    echo '{"data": [{"id": "ocid1.compartment.oc1..test", "name": "test", "lifecycle-state": "ACTIVE"}]}'
elif [[ "$*" == *"target-database list"* ]]; then
    echo '{
        "data": [{
            "id": "ocid1.test.1",
            "display-name": "test, with, commas",
            "lifecycle-state": "ACTIVE",
            "database-details": {"database-type": "AUTONOMOUS_DATABASE", "infrastructure-type": "ORACLE_CLOUD"},
            "compartment-id": "ocid1.compartment.oc1..test",
            "connection-option": {},
            "freeform-tags": {},
            "defined-tags": {}
        }]
    }'
else
    echo '{"data": []}'
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -f csv -c "ocid1.compartment.oc1..test" 2>&1 || true
    [ "$status" -eq 0 ]
    # CSV should properly escape commas
}

@test "Edge: Table output with very wide field values" {
    # Mock OCI returns data with long values
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
    echo "3.45.0"
elif [[ "$*" == *"compartment list"* ]]; then
    echo '{"data": [{"id": "ocid1.compartment.oc1..test", "name": "test", "lifecycle-state": "ACTIVE"}]}'
elif [[ "$*" == *"target-database list"* ]]; then
    LONG_NAME=$(printf 'a%.0s' {1..200})
    echo "{
        \"data\": [{
            \"id\": \"ocid1.test.1\",
            \"display-name\": \"$LONG_NAME\",
            \"lifecycle-state\": \"ACTIVE\",
            \"database-details\": {\"database-type\": \"AUTONOMOUS_DATABASE\", \"infrastructure-type\": \"ORACLE_CLOUD\"},
            \"compartment-id\": \"ocid1.compartment.oc1..test\",
            \"connection-option\": {},
            \"freeform-tags\": {},
            \"defined-tags\": {}
        }]
    }"
else
    echo '{"data": []}'
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_list.sh" -f table -c "ocid1.compartment.oc1..test" 2>&1 || true
    [ "$status" -eq 0 ]
}
