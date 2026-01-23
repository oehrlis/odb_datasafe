#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_connect_details.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.23
# Purpose....: Test suite for ds_target_connect_details.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Create test environment in REPO_ROOT so init_config can find it
    export TEST_ENV_FILE="${REPO_ROOT}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
DS_TAG_NAMESPACE="test-namespace"
EOF
    
    # Mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"--version"*)
        echo "3.45.0"
        ;;
    *"os ns get"*)
        echo '{"data": "test-namespace"}'
        ;;
    *"iam compartment get"*"test-root"*)
        echo '{"data": {"name": "test-root-compartment", "id": "ocid1.compartment.oc1..test-root"}}'
        ;;
    *"data-safe target-database list"*"--query"*"display-name"*"test-target-vm"*)
        echo '"ocid1.datasafetarget.oc1..targetvm"'
        ;;
    *"data-safe target-database list"*"--query"*"display-name"*"test-target-basic"*)
        echo '"ocid1.datasafetarget.oc1..targetbasic"'
        ;;
    *"data-safe target-database list"*"--query"*"display-name"*)
        echo "null"
        ;;
    *"data-safe target-database get"*"targetvm"*"--query"*"data"*)
        echo '{"id":"ocid1.datasafetarget.oc1..targetvm","display-name":"test-target-vm","description":"Test VM cluster target","lifecycle-state":"ACTIVE","lifecycle-details":"Target is active","compartment-id":"ocid1.compartment.oc1..test-root","connection-option":{"connection-type":"PRIVATE_ENDPOINT","on-prem-connector-id":"ocid1.onpremconnector.oc1..connector1"},"credentials":{"user-name":"datasafe_user"},"database-details":{"database-type":"INSTALLED_DATABASE","listener-port":"1521","service-name":"TESTPDB","vm-cluster-id":"ocid1.vmcluster.oc1..vmcluster1"},"freeform-tags":{"environment":"test"}}'
        ;;
    *"data-safe target-database get"*"targetbasic"*"--query"*"data"*)
        echo '{"id":"ocid1.datasafetarget.oc1..targetbasic","display-name":"test-target-basic","description":"Test basic target without connection-option","lifecycle-state":"ACTIVE","lifecycle-details":"Target is active","compartment-id":"ocid1.compartment.oc1..test-root","credentials":{"user-name":"datasafe_user"},"database-details":{"database-type":"AUTONOMOUS_DATABASE","listener-port":"1522","service-name":"AUTOPDB"},"freeform-tags":{}}'
        ;;
    *"data-safe on-prem-connector get"*"connector1"*)
        echo '"Test On-Prem Connector"'
        ;;
    *"db node list"*"vmcluster1"*"--query"*"data"*)
        echo '[{"id":"ocid1.dbnode.oc1..node1","hostname":"node1.example.com","vnic-id":"ocid1.vnic.oc1..vnic1","backup-vnic-id":"ocid1.vnic.oc1..bvnic1","lifecycle-state":"AVAILABLE"},{"id":"ocid1.dbnode.oc1..node2","hostname":"node2.example.com","vnic-id":"ocid1.vnic.oc1..vnic2","backup-vnic-id":"ocid1.vnic.oc1..bvnic2","lifecycle-state":"AVAILABLE"}]'
        ;;
    *)
        echo '{"data": []}' >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
}

teardown() {
    rm -f "${REPO_ROOT}/.env"
}

# =============================================================================
# BASIC TESTS
# =============================================================================

@test "script exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_connect_details.sh" ]
    [ -x "${BIN_DIR}/ds_target_connect_details.sh" ]
}

@test "shows help with --help" {
    run "${BIN_DIR}/ds_target_connect_details.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "shows version with --version" {
    run "${BIN_DIR}/ds_target_connect_details.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ds_target_connect_details.sh" ]]
}

@test "requires target parameter" {
    run "${BIN_DIR}/ds_target_connect_details.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

# =============================================================================
# FUNCTIONAL TESTS
# =============================================================================

@test "displays connection details in table format" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-basic
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Target Name" ]]
    [[ "$output" =~ "test-target-basic" ]]
    [[ "$output" =~ "Connection Type" ]]
}

@test "handles target without connection-option (jq error fix)" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-basic
    [ "$status" -eq 0 ]
    # Should not have jq errors
    [[ ! "$output" =~ "jq: error" ]]
    [[ "$output" =~ "test-target-basic" ]]
}

@test "displays connection details in json format" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-basic -f json
    [ "$status" -eq 0 ]
    # Verify it's valid JSON
    echo "$output" | jq . > /dev/null
}

@test "displays cluster nodes when vm-cluster-id exists" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-vm
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test-target-vm" ]]
    [[ "$output" =~ "VM Cluster ID" ]]
    [[ "$output" =~ "Cluster Nodes" ]]
    [[ "$output" =~ "node1.example.com" ]]
    [[ "$output" =~ "node2.example.com" ]]
}

@test "includes cluster nodes in json output" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-vm -f json
    [ "$status" -eq 0 ]
    # Verify cluster_nodes field exists and has 2 nodes
    node_count=$(echo "$output" | jq '.database.cluster_nodes | length')
    [ "$node_count" -eq 2 ]
    # Verify node details
    [[ $(echo "$output" | jq -r '.database.cluster_nodes[0].hostname') == "node1.example.com" ]]
    [[ $(echo "$output" | jq -r '.database.cluster_nodes[1].hostname') == "node2.example.com" ]]
}

@test "handles on-prem connector information" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-vm
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On-Prem Connector" ]]
    [[ "$output" =~ "Test On-Prem Connector" ]]
}

@test "handles targets without cluster nodes gracefully" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-basic
    [ "$status" -eq 0 ]
    # Should not show cluster nodes section for non-cluster targets
    [[ ! "$output" =~ "Cluster Nodes" ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "fails gracefully for non-existent target" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T nonexistent-target
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to resolve target" ]]
}

@test "validates format parameter" {
    run "${BIN_DIR}/ds_target_connect_details.sh" -T test-target-basic -f invalid
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid format" ]]
}
