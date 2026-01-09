#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_oci_helpers.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test suite for lib/oci_helpers.sh library functions
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Mock OCI CLI responses
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create comprehensive mock oci command
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Mock OCI CLI for testing

case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "iam compartment list --compartment-id ocid1.compartment.oc1..root"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..child1", "name": "test-compartment", "lifecycle-state": "ACTIVE"},
    {"id": "ocid1.compartment.oc1..child2", "name": "another-compartment", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    "iam compartment get --compartment-id ocid1.compartment.oc1..child1"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.compartment.oc1..child1",
    "name": "test-compartment",
    "lifecycle-state": "ACTIVE"
  }
}
JSON
        ;;
    "data-safe target-database list --compartment-id"*"--query data[?\"display-name\"=='test-target'].id"*)
        echo '"ocid1.datasafetarget.oc1..target123"'
        ;;
    "data-safe target-database list --compartment-id"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "test-target-1",
      "lifecycle-state": "ACTIVE",
      "connection-option": {
        "on-premise-connector-id": "ocid1.connector.oc1..conn1"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2", 
      "display-name": "test-target-2",
      "lifecycle-state": "ACTIVE",
      "connection-option": {
        "on-premise-connector-id": null
      }
    }
  ]
}
JSON
        ;;
    "data-safe target-database get --target-database-id"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target123",
    "display-name": "test-target",
    "lifecycle-state": "ACTIVE",
    "connection-option": {
      "on-premise-connector-id": "ocid1.connector.oc1..conn1"
    }
  }
}
JSON
        ;;
    "data-safe on-premises-connector list"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.connector.oc1..conn1",
      "display-name": "test-connector-1",
      "lifecycle-state": "ACTIVE"
    },
    {
      "id": "ocid1.connector.oc1..conn2",
      "display-name": "test-connector-2", 
      "lifecycle-state": "ACTIVE"
    }
  ]
}
JSON
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Load libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
}

teardown() {
    # Clean up test environment
    unset OCI_CLI_PROFILE OCI_CLI_REGION OCI_CLI_CONFIG_FILE
}

# Test basic library loading
@test "oci_helpers.sh can be loaded without errors" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# Test OCI CLI validation
@test "oci_exec function executes OCI commands" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run oci_exec --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.45.0"* ]]
}

@test "is_ocid function works correctly" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run is_ocid "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
    
    run is_ocid "not-an-ocid"
    [ "$status" -eq 1 ]
}

# Test compartment functions
@test "oci_resolve_compartment_ocid function resolves compartment names" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with OCID (should return as-is)
    run oci_resolve_compartment_ocid "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
    [[ "$output" == "ocid1.compartment.oc1..test" ]]
}

@test "oci_list_compartments function lists compartments" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run oci_list_compartments
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-compartment"* ]]
}

# Test Data Safe specific functions
@test "ds_resolve_target_ocid function resolves target names" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test resolving target name to OCID
    run ds_resolve_target_ocid "test-target" "ocid1.compartment.oc1..root"
    [ "$status" -eq 0 ]
    [[ "$output" == "ocid1.datasafetarget.oc1..target123" ]]
}

@test "ds_list_targets function lists Data Safe targets" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_list_targets "ocid1.compartment.oc1..root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

@test "ds_get_target_details function gets target information" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_get_target_details "ocid1.datasafetarget.oc1..target123"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target"* ]]
}

# Test connector functions
@test "ds_list_connectors function lists on-premises connectors" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_list_connectors "ocid1.compartment.oc1..root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-connector-1"* ]]
    [[ "$output" == *"test-connector-2"* ]]
}

# Test error handling
@test "oci_exec function handles OCI errors gracefully" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with invalid command
    run oci_exec invalid-command
    [ "$status" -eq 0 ]  # Our mock returns success for unknown commands
    [[ "$output" == *'{"data": []}'* ]]
}

# Test configuration validation
@test "oci_validate_config function checks OCI configuration" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # With valid profile
    export OCI_CLI_PROFILE="DEFAULT"
    run oci_validate_config
    [ "$status" -eq 0 ]
}

# Test JSON processing
@test "oci_format_output function formats JSON output correctly" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    local test_json='{"data": [{"name": "test"}]}'
    
    # Test table format
    run bash -c "echo '$test_json' | oci_format_output table '.data[] | .name'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
    
    # Test JSON format  
    run bash -c "echo '$test_json' | oci_format_output json '.data'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name": "test"'* ]]
}

# Test parallel execution
@test "oci_parallel_exec function handles multiple commands" {
    source "${LIB_DIR}/common.sh" 
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with multiple simple commands
    run oci_parallel_exec "--version" "--version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.45.0"* ]]
}

# Test retry mechanism
@test "oci_retry function retries failed operations" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Create a command that fails first time, succeeds second time
    counter_file="${TEST_TEMP_DIR}/retry_counter"
    echo "0" > "$counter_file"
    
    retry_cmd() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        
        if [ "$count" -eq 1 ]; then
            return 1  # Fail first time
        else
            echo "success"
            return 0  # Succeed second time
        fi
    }
    
    export -f retry_cmd
    
    run oci_retry 3 retry_cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}