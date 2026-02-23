#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_find_untagged_targets.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Purpose....: Test suite for bin/ds_find_untagged_targets.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export SCRIPT_PATH="${REPO_ROOT}/bin/ds_find_untagged_targets.sh"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export REAL_JQ="$(command -v jq)"
    
    # Mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create mock oci command
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
    *"data-safe target-database list"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "tagged-target",
      "lifecycle-state": "ACTIVE",
      "defined-tags": {
        "DBSec": {
          "Environment": "Production"
        }
      },
      "database-details": {
        "database-type": "DATABASE_CLOUD_SERVICE"
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2",
      "display-name": "untagged-target",
      "lifecycle-state": "ACTIVE",
      "defined-tags": {},
      "database-details": {
        "database-type": "AUTONOMOUS_DATABASE"
      }
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
    
    # Create mock jq
    cat > "${TEST_TEMP_DIR}/bin/jq" << EOF
#!/usr/bin/env bash
exec "${REAL_JQ}" "\$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
}

teardown() {
    unset OCI_CLI_PROFILE OCI_CLI_REGION OCI_CLI_CONFIG_FILE
    unset DS_ROOT_COMP
}

# Basic tests
@test "ds_find_untagged_targets.sh exists and is executable" {
    [ -f "$SCRIPT_PATH" ]
    [ -x "$SCRIPT_PATH" ]
}

@test "ds_find_untagged_targets.sh shows usage with --help" {
    run bash "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"compartment"* ]]
    [[ "$output" == *"namespace"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}  

@test "ds_find_untagged_targets.sh reads version from .extension file" {
    # Check that script uses version from .extension
    run bash -c "grep 'SCRIPT_VERSION=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *".extension"* ]]
}

@test "ds_find_untagged_targets.sh has SCRIPT_DIR before SCRIPT_VERSION" {
    # Verify initialization order
    script_dir_line=$(grep -n "^SCRIPT_DIR=" "$SCRIPT_PATH" | cut -d: -f1)
    version_line=$(grep -n "^SCRIPT_VERSION=" "$SCRIPT_PATH" | cut -d: -f1)
    
    [ -n "$script_dir_line" ]
    [ -n "$version_line" ]
    [ "$script_dir_line" -lt "$version_line" ]
}

@test "ds_find_untagged_targets.sh uses DS_ROOT_COMP when no compartment specified" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o json 2>&1
    
    # Should use DS_ROOT_COMP
    [[ "$output" == *"DS_ROOT_COMP"* ]] || [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh accepts compartment parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -c test-compartment -o json 2>&1
    
    # Should accept compartment
    [ "$status" -eq 0 ] || [[ "$output" == *"test-compartment"* ]]
}

@test "ds_find_untagged_targets.sh supports namespace parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -n Security -o json 2>&1
    
    # Should use custom namespace
    [[ "$output" == *"Security"* ]] || [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh defaults to DBSec namespace" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o json 2>&1
    
    # Should use DBSec by default
    [[ "$output" == *"DBSec"* ]] || [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh supports table output format" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o table 2>&1
    
    # Should output table format
    [ "$status" -eq 0 ] || [[ "$output" == *"Target ID"* ]]
}

@test "ds_find_untagged_targets.sh supports csv output format" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o csv 2>&1
    
    # Should either work (with OCI access) or fail gracefully 
    # Test passes if it accepts the csv parameter (doesn't reject it as invalid)
    [[ ! "$output" == *"Invalid output format"* ]]
}

@test "ds_find_untagged_targets.sh supports json output format" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o json 2>&1
    
    # Should output valid JSON
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh rejects invalid output format" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run bash "$SCRIPT_PATH" -o invalid 2>&1
    
    # Should reject invalid format
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"format"* ]]
}

@test "ds_find_untagged_targets.sh has standardized function headers" {
    # Check for Function: pattern in headers
    run bash -c "grep -c '# Function:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]  # At least 3 functions should have headers
}

@test "ds_find_untagged_targets.sh uses resolve_compartment_to_vars" {
    run bash -c "grep -q 'resolve_compartment_to_vars' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh uses shared target source collector" {
    run bash -c "grep -q 'ds_collect_targets_source' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh stores COMP_NAME and COMP_OCID" {
    run bash -c "grep -q 'COMP_NAME=' '$SCRIPT_PATH' && grep -q 'COMP_OCID=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh supports state filter" {
    # Verify script has state filter option
    run bash -c "grep -q 'STATE_FILTERS' '$SCRIPT_PATH' && grep -q '\\-s.*state' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh handles compartment resolution" {
    # Verify script uses resolve_compartment_to_vars
    run bash -c "grep -q 'resolve_compartment_to_vars' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "ds_find_untagged_targets.sh supports input-json mode" {
    local sample_json="${BATS_TEST_TMPDIR}/untagged_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE","defined-tags":{"DBSec":{"Environment":"Production"}},"database-details":{"database-type":"AUTONOMOUS_DATABASE"}},
  {"id":"ocid1.datasafetarget.oc1..t2","display-name":"db2","lifecycle-state":"ACTIVE","defined-tags":{},"database-details":{"database-type":"DATABASE_CLOUD_SERVICE"}}
]}
JSON

    run bash "$SCRIPT_PATH" --input-json "$sample_json" -o json
    [ "$status" -eq 0 ]
    [[ "$output" == *"db2"* ]]
}
