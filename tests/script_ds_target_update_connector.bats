#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_update_connector.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test suite for ds_target_update_connector.sh script
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
EOF
    
    # Mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "data-safe on-premises-connector list --compartment-id"*"--query data[?\"display-name\"=="*)
        # Extract connector name from query
        if [[ "$*" == *"test-connector"* ]]; then
            echo '"ocid1.connector.oc1..conn123"'
        else
            echo 'null'
        fi
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
    },
    {
      "id": "ocid1.connector.oc1..conn3",
      "display-name": "test-connector-3",
      "lifecycle-state": "ACTIVE"
    }
  ]
}
JSON
        ;;
    "data-safe on-premises-connector get --on-premises-connector-id"*)
        if [[ "$*" == *"conn1"* ]]; then
            echo '{"data": {"display-name": "test-connector-1"}}'
        elif [[ "$*" == *"conn2"* ]]; then
            echo '{"data": {"display-name": "test-connector-2"}}'
        elif [[ "$*" == *"conn3"* ]]; then
            echo '{"data": {"display-name": "test-connector-3"}}'
        else
            echo '{"data": {"display-name": "unknown"}}'
        fi
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
        "on-premise-connector-id": "ocid1.connector.oc1..conn1"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target3",
      "display-name": "test-target-3",
      "lifecycle-state": "ACTIVE",
      "connection-option": {
        "on-premise-connector-id": "ocid1.connector.oc1..conn2"
      }
    }
  ]
}
JSON
        ;;
    "data-safe target-database get --target-database-id"*)
        if [[ "$*" == *"target1"* ]]; then
            cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target1",
    "display-name": "test-target-1",
    "connection-option": {
      "on-premise-connector-id": "ocid1.connector.oc1..conn1"
    }
  }
}
JSON
        else
            echo '{"data": {"display-name": "unknown", "connection-option": {"on-premise-connector-id": null}}}'
        fi
        ;;
    "data-safe target-database update --target-database-id"*"--connection-option"*)
        echo '{"opc-work-request-id": "ocid1.workrequest.oc1..work123"}'
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
    unset DS_ROOT_COMP CONFIG_FILE
}

# Test basic script functionality
@test "ds_target_update_connector.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_connector.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_update_connector.sh"* ]]
    [[ "$output" == *"Operation Modes:"* ]]
    [[ "$output" == *"set"* ]]
    [[ "$output" == *"migrate"* ]]
    [[ "$output" == *"distribute"* ]]
}

@test "ds_target_update_connector.sh shows version information" {
    run "${BIN_DIR}/ds_target_update_connector.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
}

# Test set mode
@test "ds_target_update_connector.sh set mode requires target connector" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires --target-connector"* ]]
}

@test "ds_target_update_connector.sh set mode works with specific targets" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "test-connector-2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-connector-2"* ]]
}

@test "ds_target_update_connector.sh set mode works with compartment" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processing targets from compartment"* ]]
}

@test "ds_target_update_connector.sh set mode dry-run shows changes" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "test-connector-2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode"* ]]
    [[ "$output" == *"no changes applied"* ]]
}

@test "ds_target_update_connector.sh set mode apply makes changes" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "test-connector-2" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apply mode"* ]]
    [[ "$output" == *"Connector updated successfully"* ]]
}

# Test migrate mode
@test "ds_target_update_connector.sh migrate mode requires source and target connectors" {
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires --source-connector"* ]]
}

@test "ds_target_update_connector.sh migrate mode requires target connector" {
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate --source-connector "test-connector-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires --target-connector"* ]]
}

@test "ds_target_update_connector.sh migrate mode validates different connectors" {
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate --source-connector "test-connector-1" --target-connector "test-connector-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be different"* ]]
}

@test "ds_target_update_connector.sh migrate mode finds and migrates targets" {
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate --source-connector "ocid1.connector.oc1..conn1" --target-connector "ocid1.connector.oc1..conn2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Finding targets using source connector"* ]]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

@test "ds_target_update_connector.sh migrate mode applies changes when requested" {
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate --source-connector "ocid1.connector.oc1..conn1" --target-connector "ocid1.connector.oc1..conn2" --apply -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apply mode"* ]]
}

# Test distribute mode
@test "ds_target_update_connector.sh distribute mode finds available connectors" {
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Finding available on-premises connectors"* ]]
    [[ "$output" == *"Found 3 available connectors"* ]]
    [[ "$output" == *"test-connector-1"* ]]
    [[ "$output" == *"test-connector-2"* ]]
    [[ "$output" == *"test-connector-3"* ]]
}

@test "ds_target_update_connector.sh distribute mode distributes targets evenly" {
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Finding targets to distribute"* ]]
    [[ "$output" == *"Found 3 targets to distribute"* ]]
}

@test "ds_target_update_connector.sh distribute mode applies distribution" {
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute --apply -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apply mode"* ]]
    [[ "$output" == *"Distribution summary"* ]]
}

@test "ds_target_update_connector.sh distribute mode ignores connector options" {
    # Should work even with connector options (they get ignored with warning)
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute --source-connector "ignored" --target-connector "ignored" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignored in distribute mode"* ]]
}

# Test connector resolution
@test "ds_target_update_connector.sh resolves connector names to OCIDs" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "test-connector" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Should resolve name to OCID internally
}

@test "ds_target_update_connector.sh handles OCID connectors directly" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "ocid1.connector.oc1..conn2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test error conditions
@test "ds_target_update_connector.sh fails with invalid operation mode" {
    run "${BIN_DIR}/ds_target_update_connector.sh" invalid-mode
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid operation mode"* ]]
}

@test "ds_target_update_connector.sh fails with nonexistent connector" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "nonexistent-connector" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to resolve"* ]]
}

@test "ds_target_update_connector.sh fails without compartment when needed" {
    local saved_comp="$DS_ROOT_COMP"
    unset DS_ROOT_COMP
    
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
    
    export DS_ROOT_COMP="$saved_comp"
}

# Test target selection
@test "ds_target_update_connector.sh handles multiple targets" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1,test-target-2" --target-connector "test-connector-2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

@test "ds_target_update_connector.sh handles target OCIDs" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "ocid1.datasafetarget.oc1..target1" --target-connector "test-connector-2"
    [ "$status" -eq 0 ]
}

@test "ds_target_update_connector.sh skips targets already using correct connector" {
    # Target already using connector 1, set to connector 1 again
    run "${BIN_DIR}/ds_target_update_connector.sh" set -T "test-target-1" --target-connector "ocid1.connector.oc1..conn1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already using target connector"* ]] || [[ "$output" == *"skipping"* ]]
}

# Test lifecycle state filtering
@test "ds_target_update_connector.sh filters by lifecycle state" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" -L "ACTIVE" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test verbose and debug modes
@test "ds_target_update_connector.sh supports verbose mode" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" -v -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting ds_target_update_connector.sh"* ]]
}

@test "ds_target_update_connector.sh supports debug mode" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" -d -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]]
}

# Test progress tracking
@test "ds_target_update_connector.sh shows progress counters" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"operation completed"* ]]
    [[ "$output" == *"Successful:"* ]]
    [[ "$output" == *"Errors:"* ]]
}

# Test OCI configuration
@test "ds_target_update_connector.sh supports OCI profile configuration" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" --oci-profile "test-profile" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_update_connector.sh supports OCI region configuration" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "test-connector-2" --oci-region "us-phoenix-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test edge cases
@test "ds_target_update_connector.sh handles no available connectors in distribute mode" {
    # Create mock that returns no connectors
    cat > "${TEST_TEMP_DIR}/bin/oci_no_connectors" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "data-safe on-premises-connector list"*)
        echo '{"data": []}'
        ;;
    *)
        ./oci "$@"
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci_no_connectors"
    
    # Temporarily replace oci command
    mv "${TEST_TEMP_DIR}/bin/oci" "${TEST_TEMP_DIR}/bin/oci_backup"
    mv "${TEST_TEMP_DIR}/bin/oci_no_connectors" "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_update_connector.sh" distribute -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No active on-premises connectors found"* ]]
    
    # Restore oci command
    mv "${TEST_TEMP_DIR}/bin/oci" "${TEST_TEMP_DIR}/bin/oci_no_connectors"
    mv "${TEST_TEMP_DIR}/bin/oci_backup" "${TEST_TEMP_DIR}/bin/oci"
}

@test "ds_target_update_connector.sh handles no targets found in migrate mode" {
    # Try to migrate from a connector that has no targets
    run "${BIN_DIR}/ds_target_update_connector.sh" migrate --source-connector "ocid1.connector.oc1..conn3" --target-connector "ocid1.connector.oc1..conn2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No targets found using source connector"* ]]
}