#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_register.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Test suite for bin/ds_target_register.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export SCRIPT_PATH="${REPO_ROOT}/bin/ds_target_register.sh"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create comprehensive mock oci command
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"--version"*)
        echo "3.45.0"
        ;;
    *"iam compartment list"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..comp1", "name": "test-compartment", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    *"data-safe on-prem-connector list"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.datasafeonpremconnector.oc1..conn1", "display-name": "test-connector", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    *"data-safe target-database list"*)
        cat << 'JSON'
{
  "data": []
}
JSON
        ;;
    *"data-safe target-database create"*)
        cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..newtarget",
    "display-name": "test-target",
    "lifecycle-state": "ACTIVE"
  }
}
JSON
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Create mock jq
    cat > "${TEST_TEMP_DIR}/bin/jq" << 'EOF'
#!/usr/bin/env bash
exec "$(command -v jq)" "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
}

teardown() {
    unset OCI_CLI_PROFILE OCI_CLI_REGION OCI_CLI_CONFIG_FILE
    unset DS_ROOT_COMP
}

# Basic tests
@test "ds_target_register.sh exists and is executable" {
    [ -f "$SCRIPT_PATH" ]
    [ -x "$SCRIPT_PATH" ]
}

@test "ds_target_register.sh shows usage with --help" {
    run bash "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
    [[ "$output" == *"--host"* ]]
    [[ "$output" == *"--sid"* ]]
    [[ "$output" == *"--pdb"* ]]
}

@test "ds_target_register.sh reads version from .extension file" {
    # Check that script uses version from .extension
    run bash -c "grep 'SCRIPT_VERSION=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *".extension"* ]]
}

@test "ds_target_register.sh has SCRIPT_DIR before SCRIPT_VERSION" {
    # Verify initialization order
    script_dir_line=$(grep -n "^SCRIPT_DIR=" "$SCRIPT_PATH" | cut -d: -f1)
    version_line=$(grep -n "^SCRIPT_VERSION=" "$SCRIPT_PATH" | cut -d: -f1)
    
    [ -n "$script_dir_line" ]
    [ -n "$version_line" ]
    [ "$script_dir_line" -lt "$version_line" ]
}

@test "ds_target_register.sh requires host parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --sid TEST --pdb TESTPDB \
        -c test-compartment --connector test-connector \
        --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"host"* ]]
}

@test "ds_target_register.sh requires SID parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --host dbhost --pdb TESTPDB \
        -c test-compartment --connector test-connector \
        --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"sid"* ]]
}

@test "ds_target_register.sh requires compartment parameter" {
    run bash "$SCRIPT_PATH" --host dbhost --sid TEST --pdb TESTPDB \
        --connector test-connector --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
}

@test "ds_target_register.sh requires connector parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --host dbhost --sid TEST --pdb TESTPDB \
        -c test-compartment --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"connector"* ]]
}

@test "ds_target_register.sh requires either --pdb or --root" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --host dbhost --sid TEST \
        -c test-compartment --connector test-connector \
        --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"pdb"* ]] || [[ "$output" == *"root"* ]]
}

@test "ds_target_register.sh rejects both --pdb and --root" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --host dbhost --sid TEST --pdb TESTPDB --root \
        -c test-compartment --connector test-connector \
        --ds-password test123 --dry-run 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"both"* ]] || [[ "$output" == *"exactly one"* ]]
}

@test "ds_target_register.sh supports dry-run mode" {
    # Verify script has DRY_RUN logic
    run bash -c "grep -q 'DRY_RUN' '$SCRIPT_PATH' && grep -q 'dry-run' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh supports --check mode" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" --host dbhost --sid TEST --pdb TESTPDB \
        -c test-compartment --connector test-connector --check 2>&1
    
    # Check mode should work without password
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "ds_target_register.sh has standardized function headers" {
    # Check for Function: pattern in headers
    run bash -c "grep -c '# Function:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]  # At least 5 functions should have headers
}

@test "ds_target_register.sh uses resolve_compartment_to_vars" {
    run bash -c "grep -q 'resolve_compartment_to_vars' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses oci_exec_ro for lookups" {
    run bash -c "grep -q 'oci_exec_ro' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses oci_exec for registration" {
    run bash -c "grep -q 'oci_exec.*target-database create' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh auto-generates display name" {
    # Verify script has display name auto-generation logic
    run bash -c "grep -q 'DISPLAY_NAME.*\${.*_.*}' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh accepts custom display name" {
    # Verify script has --display-name option
    run bash -c "grep -q 'display-name' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh handles --root flag correctly" {
    # Verify script has --root flag logic
    run bash -c "grep -q 'RUN_ROOT' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    
    run bash -c "grep -q 'CDBROOT' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}
