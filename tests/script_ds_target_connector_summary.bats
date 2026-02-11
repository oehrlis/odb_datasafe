#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_connector_summary.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Test suite for ds_target_connector_summary.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export LOG_LEVEL=ERROR
  export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    
    # Create test environment
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
      echo '{"data":"test-namespace"}'
      ;;
    *"data-safe on-prem-connector list"*)
        # Return list of connectors
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafeonpremconnector.oc1..conn1",
      "display-name": "prod-connector",
      "lifecycle-state": "ACTIVE",
      "available-version": "3.0.0"
    },
    {
      "id": "ocid1.datasafeonpremconnector.oc1..conn2",
      "display-name": "test-connector",
      "lifecycle-state": "ACTIVE",
      "available-version": "3.0.0"
    }
  ]
}
JSON
        ;;
    *"data-safe target-database list"*"--lifecycle-state ACTIVE"*)
        # Return only ACTIVE targets
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "prod-db-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn1"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2",
      "display-name": "prod-db-2",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn1"
      }
    }
  ]
}
JSON
        ;;
    *"data-safe target-database list"*)
        # Return full list of targets with various states
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "prod-db-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn1"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2",
      "display-name": "prod-db-2",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn1"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target3",
      "display-name": "test-db-1",
      "lifecycle-state": "CREATING",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn2"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target4",
      "display-name": "test-db-2",
      "lifecycle-state": "NEEDS_ATTENTION",
      "database-details": {
        "infrastructure-type": "ON_PREMISE"
      },
      "connection-option": {
        "on-prem-connector-id": "ocid1.datasafeonpremconnector.oc1..conn2"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target5",
      "display-name": "cloud-db-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "infrastructure-type": "ORACLE_CLOUD"
      },
      "connection-option": {}
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
    
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    unset DS_ROOT_COMP DS_TAG_NAMESPACE CONFIG_FILE
    rm -f "${REPO_ROOT}/.env" 2>/dev/null || true
}

# Basic functionality tests
@test "ds_target_connector_summary.sh shows help message" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_connector_summary.sh"* ]]
    [[ "$output" == *"grouped by on-premises connector"* ]]
}

@test "ds_target_connector_summary.sh shows version information" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" --version
    [ "$status" -eq 0 ]
  [[ "$output" == *"${SCRIPT_VERSION}"* ]]
}

# Summary mode tests (default)
@test "ds_target_connector_summary.sh default mode shows summary" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connector"* ]]
    [[ "$output" == *"Lifecycle State"* ]]
    [[ "$output" == *"Count"* ]]
    [[ "$output" == *"prod-connector"* ]]
    [[ "$output" == *"test-connector"* ]]
}

@test "ds_target_connector_summary.sh summary mode shows grand total" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRAND TOTAL"* ]]
}

@test "ds_target_connector_summary.sh summary shows lifecycle states" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
    [[ "$output" == *"Subtotal"* ]]
}

@test "ds_target_connector_summary.sh summary includes no-connector group" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No Connector"* ]] || [[ "$output" == *"Cloud"* ]]
}

# Detailed mode tests
@test "ds_target_connector_summary.sh detailed mode shows all targets" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"prod-db-1"* ]]
    [[ "$output" == *"prod-db-2"* ]]
    [[ "$output" == *"test-db-1"* ]]
    [[ "$output" == *"cloud-db-1"* ]]
}

@test "ds_target_connector_summary.sh detailed mode groups by connector" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connector: prod-connector"* ]]
    [[ "$output" == *"Connector: test-connector"* ]]
}

@test "ds_target_connector_summary.sh detailed mode shows target counts" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Should show target counts in connector headers
    [[ "$output" =~ [0-9]+\ targets ]]
}

# Lifecycle state filtering tests
@test "ds_target_connector_summary.sh filters by lifecycle state" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -L ACTIVE -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
    # Should not show CREATING or NEEDS_ATTENTION
    [[ "$output" != *"CREATING"* ]]
    [[ "$output" != *"NEEDS_ATTENTION"* ]]
}

# Output format tests
@test "ds_target_connector_summary.sh supports JSON output for summary" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -f json -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Validate JSON structure
    echo "$output" | jq -e '.[0].connector_name' > /dev/null
    echo "$output" | jq -e '.[0].lifecycle_states' > /dev/null
    echo "$output" | jq -e '.[0].total' > /dev/null
}

@test "ds_target_connector_summary.sh supports JSON output for detailed" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -f json -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Validate JSON structure
    echo "$output" | jq -e '.[0].connector_name' > /dev/null
    echo "$output" | jq -e '.[0].targets' > /dev/null
}

@test "ds_target_connector_summary.sh supports CSV output for summary" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -f csv -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"connector_name,lifecycle_state,count"* ]]
    [[ "$output" == *"prod-connector"* ]]
    # CSV format should have commas
    [[ "$output" == *","* ]]
}

@test "ds_target_connector_summary.sh supports CSV output for detailed" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -f csv -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"connector_name,"* ]]
    [[ "$output" == *"display-name"* ]]
    [[ "$output" == *","* ]]
}

# Field selection tests
@test "ds_target_connector_summary.sh supports custom fields in detailed mode" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -D -F "display-name,lifecycle-state" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"display-name"* ]]
    [[ "$output" == *"lifecycle-state"* ]]
}

# Error condition tests
@test "ds_target_connector_summary.sh fails without compartment" {
    rm -f "${REPO_ROOT}/.env"
    
    run "${BIN_DIR}/ds_target_connector_summary.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]] || [[ "$output" == *"DS_ROOT_COMP"* ]]
    
    # Restore .env
    cat > "${REPO_ROOT}/.env" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
DS_TAG_NAMESPACE="test-namespace"
EOF
}

@test "ds_target_connector_summary.sh validates output format" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -f invalid -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid output format"* ]]
}

# Verbose/debug/quiet mode tests
@test "ds_target_connector_summary.sh supports verbose mode" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -v -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting ds_target_connector_summary.sh"* ]]
}

@test "ds_target_connector_summary.sh supports debug mode" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -d -c "ocid1.compartment.oc1..test-root" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]] || [[ "$output" == *"TRACE"* ]] || [[ "$output" == *"Grouping targets"* ]]
}

@test "ds_target_connector_summary.sh supports quiet mode" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -q -c "ocid1.compartment.oc1..test-root" 2>&1
    [ "$status" -eq 0 ]
    # In quiet mode, should not have INFO messages
    [[ "$output" != *"[INFO]"* ]] || [[ "$output" != *"Starting ds_target_connector_summary"* ]]
}

# Configuration file usage tests
@test "ds_target_connector_summary.sh uses configuration from .env file" {
    run "${BIN_DIR}/ds_target_connector_summary.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connector"* ]]
}

# Integration tests
@test "ds_target_connector_summary.sh handles empty results gracefully" {
    # Create a mock that returns empty data
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"--version"*)
        echo "3.45.0"
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    run "${BIN_DIR}/ds_target_connector_summary.sh" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Should handle empty results without crashing
}

@test "ds_target_connector_summary.sh table output is properly formatted" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -S -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    # Check for proper table formatting (dashes for separators)
    [[ "$output" =~ ----- ]]
}
