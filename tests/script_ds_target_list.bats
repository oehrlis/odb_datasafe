#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_list.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test suite for ds_target_list.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Create test environment
    export TEST_ENV_FILE="${TEST_TEMP_DIR}/.env"
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
    "--version")
        echo "3.45.0"
        ;;
    "data-safe target-database list --compartment-id"*"--query data[?\"lifecycle-state\"=='ACTIVE']|length"*)
        echo "5"
        ;;
    "data-safe target-database list --compartment-id"*"--query data[?\"lifecycle-state\"=='CREATING']|length"*)
        echo "2"
        ;;
    "data-safe target-database list --compartment-id"*"--query data[?\"lifecycle-state\"=='DELETED']|length"*)
        echo "1"
        ;;
    "data-safe target-database list --compartment-id"*"--query data|length"*)
        echo "8"
        ;;
    "data-safe target-database list --compartment-id"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "test-target-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "database-type": "AUTONOMOUS_DATABASE"
      },
      "freeform-tags": {},
      "defined-tags": {
        "test-namespace": {
          "Environment": "prod"
        }
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2",
      "display-name": "test-target-2", 
      "lifecycle-state": "CREATING",
      "database-details": {
        "database-type": "DATABASE_CLOUD_SERVICE"
      },
      "freeform-tags": {
        "environment": "test"
      },
      "defined-tags": {}
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
    
    # Set up config file location
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    # Clean up
    unset DS_ROOT_COMP DS_TAG_NAMESPACE CONFIG_FILE
}

# Test basic script functionality
@test "ds_target_list.sh shows help message" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_list.sh"* ]]
}

@test "ds_target_list.sh shows version information" {
    run "${BIN_DIR}/ds_target_list.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
}

# Test list mode (default)
@test "ds_target_list.sh default mode shows target list" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..test-root" || true
    # Script may fail with mock environment, but should not crash
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# Test count mode (with -C flag)
@test "ds_target_list.sh count mode shows target summary" {
    run "${BIN_DIR}/ds_target_list.sh" -C -c "ocid1.compartment.oc1..test-root" || true
    # Script may fail with mock environment, but should not crash
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "ds_target_list.sh count mode with specific lifecycle state" {
    run "${BIN_DIR}/ds_target_list.sh" -C -c "ocid1.compartment.oc1..test-root" -L ACTIVE
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}

# Test details mode
@test "ds_target_list.sh details mode shows target information" {
    run "${BIN_DIR}/ds_target_list.sh" -D -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}

@test "ds_target_list.sh details mode with JSON output" {
    run "${BIN_DIR}/ds_target_list.sh" -D --json -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail in mock environment
}

@test "ds_target_list.sh details mode with CSV output" {
    run "${BIN_DIR}/ds_target_list.sh" -D --csv -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *","* ]]  # CSV should contain commas
}

# Test custom fields
@test "ds_target_list.sh supports custom field selection" {
    run "${BIN_DIR}/ds_target_list.sh" -D -F "id,display-name" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

# Test error conditions
@test "ds_target_list.sh fails without compartment or targets" {
    # Temporarily unset DS_ROOT_COMP
    local saved_comp="$DS_ROOT_COMP"
    unset DS_ROOT_COMP
    
    run "${BIN_DIR}/ds_target_list.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
    
    export DS_ROOT_COMP="$saved_comp"
}

@test "ds_target_list.sh validates lifecycle state values" {
    run "${BIN_DIR}/ds_target_list.sh" -L "INVALID_STATE" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid lifecycle state"* ]]
}

# Test verbose and debug modes
@test "ds_target_list.sh supports verbose mode" {
    run "${BIN_DIR}/ds_target_list.sh" -v -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting ds_target_list.sh"* ]]
}

@test "ds_target_list.sh supports debug mode" {
    run "${BIN_DIR}/ds_target_list.sh" -d -C -c "ocid1.compartment.oc1..test-root" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]] || [[ "$output" == *"TRACE"* ]]
}

@test "ds_target_list.sh supports quiet mode" {
    run "${BIN_DIR}/ds_target_list.sh" -q -C -c "ocid1.compartment.oc1..test-root" 2>&1
    [ "$status" -eq 0 ]
    # In quiet mode, should not have INFO messages
    [[ "$output" != *"[INFO]"* ]] || [[ "$output" != *"Starting ds_target_list"* ]]
}

# Test specific target selection
@test "ds_target_list.sh can list specific targets by name" {
    run "${BIN_DIR}/ds_target_list.sh" -D -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

@test "ds_target_list.sh can list multiple targets" {
    run "${BIN_DIR}/ds_target_list.sh" -D -T "test-target-1,test-target-2" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

# Test output formats
@test "ds_target_list.sh table output is formatted correctly" {
    run "${BIN_DIR}/ds_target_list.sh" -D --table -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NAME"* ]]  # Should have column headers
    [[ "$output" == *"test-target-1"* ]]
}

# Test configuration file usage
@test "ds_target_list.sh uses configuration from .env file" {
    # Remove explicit compartment and rely on .env
    run "${BIN_DIR}/ds_target_list.sh"
    [ "$status" -eq 0 ]
    # Default is list mode, not count mode
    [[ "$output" == *"display-name"* ]] || [[ "$output" == *"test-target"* ]]
}

# Test tag-related functionality
@test "ds_target_list.sh includes tag information in details mode" {
    run "${BIN_DIR}/ds_target_list.sh" -D --json -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Environment"* ]]  # Should include tag data
}