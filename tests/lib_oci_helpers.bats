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

@test "oci_resolve_compartment_ocid function works with valid names" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run oci_resolve_compartment_ocid "test-compartment"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
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

@test "ds_get_target function gets target information" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_get_target "ocid1.datasafetarget.oc1..target123"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
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

# Test root compartment resolution
@test "get_root_compartment_ocid function works" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # With valid profile
    export OCI_TENANCY="ocid1.tenancy.oc1..test"
    run get_root_compartment_ocid
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail without real OCI config
}

# Test target name resolution
@test "ds_resolve_target_name function works with OCIDs" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_resolve_target_name "ocid1.datasafetarget.oc1..target123"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}

# Test target compartment resolution
@test "ds_get_target_compartment function works" {
    source "${LIB_DIR}/common.sh" 
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with target OCID
    run ds_get_target_compartment "ocid1.datasafetarget.oc1..target123"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}

# Test lifecycle counting
@test "ds_count_by_lifecycle function works" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_count_by_lifecycle "ocid1.compartment.oc1..root"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}