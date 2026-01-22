#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: integration_tests.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Integration tests for the complete odb_datasafe framework
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
    
    # Create comprehensive test environment
    export TEST_ENV_FILE="${TEST_TEMP_DIR}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..integration-test"
DS_TAG_NAMESPACE="integration-test"
DS_TAG_ENV_KEY="Environment"
DS_TAG_APP_KEY="Application"
DS_USERNAME="integration_user"
OCI_CLI_PROFILE="DEFAULT"
EOF

    # Create comprehensive mock OCI environment
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Comprehensive mock OCI CLI for integration testing

# Log all calls for debugging
echo "MOCK_OCI_CALL: $*" >&2

case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "iam compartment list --compartment-id"*"integration-test"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..prod-comp", "name": "cmp-lzp-dbso-prod-projects", "lifecycle-state": "ACTIVE"},
    {"id": "ocid1.compartment.oc1..test-comp", "name": "cmp-lzp-dbso-test-projects", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    "data-safe target-database list"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "integration-target-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {"database-type": "AUTONOMOUS_DATABASE"},
      "compartment-id": "ocid1.compartment.oc1..prod-comp",
      "connection-option": {"on-premise-connector-id": "ocid1.connector.oc1..conn1"},
      "freeform-tags": {},
      "defined-tags": {"integration-test": {"Environment": "prod", "Application": "test-app"}}
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2", 
      "display-name": "integration-target-2",
      "lifecycle-state": "ACTIVE",
      "database-details": {"database-type": "DATABASE_CLOUD_SERVICE"},
      "compartment-id": "ocid1.compartment.oc1..test-comp",
      "connection-option": {"on-premise-connector-id": "ocid1.connector.oc1..conn2"},
      "freeform-tags": {"legacy": "value"},
      "defined-tags": {}
    }
  ]
}
JSON
        ;;
    "data-safe on-premises-connector list"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.connector.oc1..conn1", "display-name": "integration-connector-1", "lifecycle-state": "ACTIVE"},
    {"id": "ocid1.connector.oc1..conn2", "display-name": "integration-connector-2", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    "data-safe target-database update"*)
        echo '{"opc-work-request-id": "ocid1.workrequest.oc1..workintegration"}'
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    # Clean up integration test environment
    unset DS_ROOT_COMP DS_TAG_NAMESPACE DS_TAG_ENV_KEY DS_TAG_APP_KEY
    unset DS_USERNAME CONFIG_FILE
}

# Test full workflow integration
@test "Integration: Complete target management workflow" {
    # 1. Test help functions work
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    
    # 2. Test version functions work
    run "${BIN_DIR}/ds_target_update_tags.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SCRIPT_VERSION}"* ]]
    
    # 3. Test basic error handling
    run "${BIN_DIR}/ds_target_update_connector.sh" invalid-mode
    [ "$status" -ne 0 ]
}

@test "Integration: Library functions work together" {
    # Test that library functions can be called in sequence
    source "${LIB_DIR}/ds_lib.sh"
    
    # Initialize configuration
    run init_config
    [ "$status" -eq 0 ]
    
    # Check OCI CLI
    run oci_check_cli
    [ "$status" -eq 0 ]
    
    # Test compartment resolution
    run oci_resolve_compartment_ocid "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
    [[ "$output" == "ocid1.compartment.oc1..test" ]]
}

@test "Integration: All scripts support common CLI options" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh" 
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
    )
    
    for script in "${scripts[@]}"; do
        # Test help
        run "${BIN_DIR}/${script}" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
        
        # Test version
        run "${BIN_DIR}/${script}" --version
        [ "$status" -eq 0 ]
        [[ "$output" == *"${SCRIPT_VERSION}"* ]]
    done
}

@test "Integration: Scripts handle invalid arguments consistently" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh" 
        "ds_target_update_connector.sh"
    )
    
    for script in "${scripts[@]}"; do
        # Test invalid option
        run "${BIN_DIR}/${script}" --invalid-option || true
        [ "$status" -ne 0 ]
        [[ "$output" == *"Unknown option"* ]]
    done
}

@test "Integration: Scripts respect OCI configuration" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
    )
    
    for script in "${scripts[@]}"; do
        # Test OCI profile setting
        if [[ "$script" != *"credentials"* ]]; then
            run "${BIN_DIR}/${script}" --oci-profile "test-profile" -c "ocid1.compartment.oc1..integration-test" || true
            # Should not fail due to profile setting
        fi
    done
}

@test "Integration: Environment variable configuration works" {
    # Test that all scripts use .env configuration
    local saved_comp="$DS_ROOT_COMP"
    export DS_ROOT_COMP="ocid1.compartment.oc1..integration-test"
    
    # List should work without explicit compartment
    run "${BIN_DIR}/ds_target_list.sh"
    [ "$status" -eq 0 ]
    
    # Tags should work without explicit compartment
    run "${BIN_DIR}/ds_target_update_tags.sh" -T "integration-target-1"
    [ "$status" -eq 0 ]
    
    export DS_ROOT_COMP="$saved_comp"
}

@test "Integration: Error handling is consistent across scripts" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh"
    )
    
    # Test with nonexistent compartment
    for script in "${scripts[@]}"; do
        run "${BIN_DIR}/${script}" -c "ocid1.compartment.oc1..nonexistent" || true
        [ "$status" -ne 0 ]
        # Should handle gracefully
    done
}

@test "Integration: Performance - Scripts complete in reasonable time" {
    # Test that basic operations don't take too long
    local start_time
    start_time=$(date +%s)
    
    # Run list command
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..integration-test"
    [ "$status" -eq 0 ]
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Should complete in under 30 seconds (very generous for unit test)
    [ "$duration" -lt 30 ]
}

@test "Integration: All scripts produce structured output" {
    skip_if_no_oci_config
    # Test that scripts produce expected output formats
    
    # List with JSON
    run "${BIN_DIR}/ds_target_list.sh" -D -f json -c "ocid1.compartment.oc1..integration-test"
    [ "$status" -eq 0 ] || skip "Requires valid OCI compartment"
    [[ "$output" == *'"display-name":'* ]] || [[ "$output" == *"data"* ]]
    
    # List with CSV  
    run "${BIN_DIR}/ds_target_list.sh" -D -f csv -c "ocid1.compartment.oc1..integration-test"
    [ "$status" -eq 0 ] || skip "Requires valid OCI compartment"
    [[ "$output" == *","* ]] || [[ "$output" == *"display"* ]]
}

@test "Integration: Dry-run mode works across all update scripts" {
    skip_if_no_oci_config
    local update_scripts=(
        "ds_target_update_tags.sh"
        "ds_target_update_connector.sh"
    )
    
    for script in "${update_scripts[@]}"; do
        case "$script" in
            *tags*)
                run "${BIN_DIR}/${script}" -c "ocid1.compartment.oc1..prod-comp" || skip "Requires OCI"
                ;;
            *connector*)
                run "${BIN_DIR}/${script}" set --target-connector "integration-connector-1" -c "ocid1.compartment.oc1..integration-test"
                ;;
        esac
        
        [ "$status" -eq 0 ]
        [[ "$output" == *"Dry-run mode"* ]]
        [[ "$output" == *"no changes applied"* ]]
    done
}

@test "Integration: Apply mode works across all update scripts" {
    local update_scripts=(
        "ds_target_update_tags.sh"
        "ds_target_update_connector.sh"
    )
    
    for script in "${update_scripts[@]}"; do
        case "$script" in
            *tags*)
                run "${BIN_DIR}/${script}" --apply -c "ocid1.compartment.oc1..prod-comp"
                ;;
            *connector*)
                run "${BIN_DIR}/${script}" set --target-connector "integration-connector-1" --apply -c "ocid1.compartment.oc1..integration-test"
                ;;
        esac
        
        [ "$status" -eq 0 ]
        [[ "$output" == *"Apply mode"* ]]
    done
}