#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_activate.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.10
# Purpose....: Test suite for ds_target_activate.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    
    # Create test environment in REPO_ROOT so init_config can find it
    export TEST_ENV_FILE="${REPO_ROOT}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
DS_USER="DS_ADMIN"
DS_CDB_USER="C##DS_ADMIN"
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
    *"data-safe target-database list"*"--lifecycle-state INACTIVE"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "test-target-1",
      "lifecycle-state": "INACTIVE"
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2", 
      "display-name": "test-target-2_CDBROOT",
      "lifecycle-state": "INACTIVE",
      "freeform-tags": {
        "DBSec.Container": "CDBROOT"
      }
    }
  ]
}
JSON
        ;;
    *"data-safe target-database get"*"target1"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target1",
    "display-name": "test-target-1",
    "lifecycle-state": "INACTIVE",
    "freeform-tags": {}
  }
}
JSON
        ;;
    *"data-safe target-database get"*"target2"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target2",
    "display-name": "test-target-2_CDBROOT",
    "lifecycle-state": "INACTIVE",
    "freeform-tags": {
      "DBSec.Container": "CDBROOT"
    }
  }
}
JSON
        ;;
    *"data-safe target-database update"*"--credentials"*)
        echo '{"opc-work-request-id": "ocid1.workrequest.oc1..work123"}'
        ;;
    *"iam compartment list"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.compartment.oc1..test-root",
      "name": "test-compartment"
    }
  ]
}
JSON
        ;;
    *"os ns get"*)
        echo '{"data":"test-namespace"}'
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Mock jq
    cat > "${TEST_TEMP_DIR}/bin/jq" << 'EOF'
#!/usr/bin/env bash
# Simple jq mock for basic operations
exec /usr/bin/jq "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
    
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    # Clean up sensitive data and test .env
    unset DS_PASSWORD DS_CDB_PASSWORD CONFIG_FILE
    rm -f "${REPO_ROOT}/.env" 2>/dev/null || true
}

# Test basic script functionality
@test "ds_target_activate.sh shows help message" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_activate.sh"* ]]
    [[ "$output" == *"Activate inactive Oracle Data Safe"* ]]
    [[ "$output" == *"PDB Credentials"* ]]
    [[ "$output" == *"ROOT Credentials"* ]]
}

@test "ds_target_activate.sh shows version information" {
    run "${BIN_DIR}/ds_target_activate.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SCRIPT_VERSION}"* ]]
}

@test "ds_target_activate.sh requires password" {
    run "${BIN_DIR}/ds_target_activate.sh" -c "ocid1.compartment.oc1..test-root" -T "test-target-1"
    [ "$status" -ne 0 ]
}

# Test dry-run mode
@test "ds_target_activate.sh dry-run mode with explicit password" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"test-target-1"* ]]
}

@test "ds_target_activate.sh detects CDB ROOT targets by name" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-2_CDBROOT" -c "ocid1.compartment.oc1..test-root" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"ROOT"* ]]
    [[ "$output" == *"C##DS_ADMIN"* ]]
}

@test "ds_target_activate.sh uses PDB credentials for non-CDB targets" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" -c "ocid1.compartment.oc1..test-root" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"PDB"* ]]
    [[ "$output" == *"DS_ADMIN"* ]]
}

# Test credential handling
@test "ds_target_activate.sh accepts PDB password via -P" {
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -P "testpass" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh accepts CDB password via --cdb-password" {
    export DS_PASSWORD="testpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --cdb-password "testcdbpass" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh accepts custom PDB user via -U" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -U "CUSTOM_USER" -T "test-target-1" -c "ocid1.compartment.oc1..test-root" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"CUSTOM_USER"* ]]
}

@test "ds_target_activate.sh accepts custom CDB user via --cdb-user" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --cdb-user "C##CUSTOM_USER" -T "test-target-2_CDBROOT" -c "ocid1.compartment.oc1..test-root" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"C##CUSTOM_USER"* ]]
}

# Test target selection
@test "ds_target_activate.sh can activate specific targets by name" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

@test "ds_target_activate.sh can activate specific targets by OCID" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "ocid1.datasafetarget.oc1..target1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh can activate multiple targets" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1,test-target-2_CDBROOT" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

# Test compartment-wide activation
@test "ds_target_activate.sh can activate all INACTIVE targets in compartment" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Discovering targets"* ]]
    [[ "$output" == *"INACTIVE"* ]]
}

# Test lifecycle state filtering
@test "ds_target_activate.sh filters by lifecycle state" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -L "INACTIVE" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INACTIVE"* ]]
}

# Test wait options
@test "ds_target_activate.sh supports --wait option" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --wait -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh supports --no-wait option (default)" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --no-wait -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test OCI options
@test "ds_target_activate.sh accepts --oci-profile option" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --oci-profile "TEST_PROFILE" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh accepts --oci-region option" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --oci-region "us-ashburn-1" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

@test "ds_target_activate.sh accepts --oci-config option" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run --oci-config "/path/to/config" -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
}

# Test verbose and debug modes
@test "ds_target_activate.sh supports verbose mode" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -v -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]]
}

@test "ds_target_activate.sh supports debug mode" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -d -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TRACE"* ]] || [[ "$output" == *"DEBUG"* ]]
}

# Test summary output
@test "ds_target_activate.sh shows activation summary" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" -c "ocid1.compartment.oc1..test-root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Activation Summary"* ]]
    [[ "$output" == *"Total targets"* ]]
    [[ "$output" == *"Successful"* ]]
}

# Test positional arguments
@test "ds_target_activate.sh accepts positional target arguments" {
    export DS_PASSWORD="testpass123"
    export DS_CDB_PASSWORD="testcdbpass123"
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -c "ocid1.compartment.oc1..test-root" test-target-1
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

# Test error handling
@test "ds_target_activate.sh requires oci command" {
    # Remove mock oci from PATH temporarily
    PATH_BACKUP="$PATH"
    export PATH="/usr/bin:/bin"
    
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" 2>&1 || true
    
    export PATH="$PATH_BACKUP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"oci"* ]]
}

@test "ds_target_activate.sh requires jq command" {
    # Remove mock jq from PATH
    mv "${TEST_TEMP_DIR}/bin/jq" "${TEST_TEMP_DIR}/bin/jq.bak" 2>/dev/null || true
    PATH_BACKUP="$PATH"
    export PATH="/usr/bin:/bin:${TEST_TEMP_DIR}/bin"
    
    run "${BIN_DIR}/ds_target_activate.sh" --dry-run -T "test-target-1" 2>&1 || true
    
    export PATH="$PATH_BACKUP"
    mv "${TEST_TEMP_DIR}/bin/jq.bak" "${TEST_TEMP_DIR}/bin/jq" 2>/dev/null || true
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"jq"* ]]
}
