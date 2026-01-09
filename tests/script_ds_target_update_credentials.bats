#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_update_credentials.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test suite for ds_target_update_credentials.sh script
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
DS_USERNAME="testuser"
EOF
    
    # Create test credentials file
    export TEST_CRED_FILE="${TEST_TEMP_DIR}/creds.json"
    cat > "${TEST_CRED_FILE}" << 'EOF'
{
  "userName": "creduser",
  "password": "credpass123"
}
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
    "data-safe target-database list --compartment-id"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "test-target-1",
      "lifecycle-state": "ACTIVE"
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2", 
      "display-name": "test-target-2",
      "lifecycle-state": "ACTIVE"
    }
  ]
}
JSON
        ;;
    "data-safe target-database get --target-database-id"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target1",
    "display-name": "test-target-1",
    "lifecycle-state": "ACTIVE"
  }
}
JSON
        ;;
    "data-safe target-database update --target-database-id"*"--credentials"*)
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
    # Clean up sensitive data
    unset DS_USERNAME DS_PASSWORD CONFIG_FILE TEST_CRED_FILE
    rm -f "${TEST_CRED_FILE}" 2>/dev/null || true
}

# Test basic script functionality
@test "ds_target_update_credentials.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_update_credentials.sh"* ]]
    [[ "$output" == *"Credential Sources"* ]]
}

@test "ds_target_update_credentials.sh shows version information" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
}

# Test credential file source
@test "ds_target_update_credentials.sh uses credential file" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Credentials loaded from file"* ]]
    [[ "$output" == *"creduser"* ]]
}

@test "ds_target_update_credentials.sh validates credential file format" {
    # Create invalid JSON file
    local invalid_file="${TEST_TEMP_DIR}/invalid_creds.json"
    echo '{"invalid": "format"}' > "$invalid_file"
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "$invalid_file" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Username not found"* ]]
    
    rm -f "$invalid_file"
}

@test "ds_target_update_credentials.sh fails with missing credential file" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "/nonexistent/file.json" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# Test CLI credential source
@test "ds_target_update_credentials.sh uses CLI username and password" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" -U "cliuser" -P "clipass" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cliuser"* ]]
}

@test "ds_target_update_credentials.sh fails without username" {
    # Unset environment username
    local saved_user="$DS_USERNAME"
    unset DS_USERNAME
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" --no-prompt -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Username not specified"* ]]
    
    export DS_USERNAME="$saved_user"
}

@test "ds_target_update_credentials.sh fails without password in no-prompt mode" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" -U "testuser" --no-prompt -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Password not specified"* ]]
}

# Test environment variable source
@test "ds_target_update_credentials.sh uses environment variables" {
    export DS_PASSWORD="envpass123"
    run "${BIN_DIR}/ds_target_update_credentials.sh" --no-prompt -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"testuser"* ]]  # From .env file
    unset DS_PASSWORD
}

# Test dry-run mode (default)
@test "ds_target_update_credentials.sh dry-run mode shows what would be done" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode"* ]]
    [[ "$output" == *"no changes applied"* ]]
}

# Test apply mode
@test "ds_target_update_credentials.sh apply mode makes actual changes" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" --apply -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apply mode"* ]]
    [[ "$output" == *"Changes will be applied"* ]]
    [[ "$output" == *"Credentials updated successfully"* ]]
}

# Test specific target selection
@test "ds_target_update_credentials.sh can update specific targets by name" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

@test "ds_target_update_credentials.sh can update specific targets by OCID" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -T "ocid1.datasafetarget.oc1..target1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ocid1.datasafetarget.oc1..target1"* ]]
}

@test "ds_target_update_credentials.sh can update multiple targets" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -T "test-target-1,test-target-2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

# Test compartment-wide updates
@test "ds_target_update_credentials.sh can update all targets in compartment" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processing targets from compartment"* ]]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

# Test lifecycle state filtering
@test "ds_target_update_credentials.sh filters by lifecycle state" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -L "ACTIVE" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
}

@test "ds_target_update_credentials.sh validates lifecycle states" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -L "INVALID_STATE" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid lifecycle state"* ]]
}

# Test error handling
@test "ds_target_update_credentials.sh handles invalid target names" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -T "nonexistent-target" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Failed to resolve"* ]]
}

@test "ds_target_update_credentials.sh fails without compartment or targets" {
    local saved_comp="$DS_ROOT_COMP"
    unset DS_ROOT_COMP
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
    
    export DS_ROOT_COMP="$saved_comp"
}

# Test verbose and debug modes
@test "ds_target_update_credentials.sh supports verbose mode" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -v -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting ds_target_update_credentials.sh"* ]]
}

@test "ds_target_update_credentials.sh supports debug mode" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -d -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]]
}

# Test progress tracking
@test "ds_target_update_credentials.sh shows progress counters" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Credential update completed"* ]]
    [[ "$output" == *"Successful:"* ]]
    [[ "$output" == *"Errors:"* ]]
}

# Test credential source priority
@test "ds_target_update_credentials.sh prioritizes credential file over CLI options" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -U "ignored" -P "ignored" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"creduser"* ]]  # Should use file, not CLI
}

@test "ds_target_update_credentials.sh prioritizes CLI options over environment" {
    export DS_USERNAME="envuser"
    export DS_PASSWORD="envpass"
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" -U "cliuser" -P "clipass" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cliuser"* ]]  # Should use CLI, not environment
    
    unset DS_PASSWORD
}

# Test OCI configuration
@test "ds_target_update_credentials.sh supports OCI profile configuration" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" --oci-profile "test-profile" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_update_credentials.sh supports OCI region configuration" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" --oci-region "us-phoenix-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test security features
@test "ds_target_update_credentials.sh masks passwords in output" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -v -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[hidden]"* ]]
    [[ "$output" != *"credpass123"* ]]  # Password should not appear in output
}

@test "ds_target_update_credentials.sh cleans up temporary files" {
    # This is tested indirectly - the script should not leave temp files behind
    local temp_count_before
    temp_count_before=$(find "$TEST_TEMP_DIR" -name "*cred*" -type f | wc -l)
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" --cred-file "${TEST_CRED_FILE}" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    
    local temp_count_after
    temp_count_after=$(find "$TEST_TEMP_DIR" -name "*cred*" -type f | wc -l)
    
    # Should not have created additional temp files (only our test file should remain)
    [ "$temp_count_after" -eq "$temp_count_before" ]
}