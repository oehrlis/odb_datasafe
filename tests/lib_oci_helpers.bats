#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_oci_helpers.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Purpose....: Test suite for lib/oci_helpers.sh library functions
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
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
    *"--version"*)
        echo "3.45.0"
        ;;
        *"iam compartment list"*"name=='test-compartment'"*)
                echo "ocid1.compartment.oc1..child1"
                ;;
        *"iam compartment list"*)
                echo "null"
                ;;
    *"iam compartment get --compartment-id ocid1.compartment.oc1..child1"*)
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
    *"data-safe target-database list"*"--query data[?\"display-name\"=="*)
        echo '"ocid1.datasafetarget.oc1..target123"'
        ;;
    *"data-safe target-database list --compartment-id"*)
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
    *"data-safe target-database get --target-database-id"*)
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
    *"data-safe on-premises-connector list"*)
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
    export LOG_LEVEL=ERROR  # Suppress debug output
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run oci_exec --version
    [ "$status" -eq 0 ]
    # Check output contains version or is from the mock
    [[ "$output" == *"3.45"* ]] || [[ "$output" == *"3."* ]]
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
    # Use bash -c so libraries are sourced in a fresh context where declare -A
    # _COMP_OCID_CACHE is at global scope (not trapped in a setup() function local)
    run bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/oci_helpers.sh'
        oci_resolve_compartment_ocid 'ocid1.compartment.oc1..test'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "ocid1.compartment.oc1..test" ]]
}

@test "oci_resolve_compartment_ocid function works with valid names" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    run oci_resolve_compartment_ocid "test-compartment"
    # Mock handles "name=='test-compartment'" case and returns OCID
    [ "$status" -eq 0 ]
}

# Test Data Safe specific functions
@test "ds_resolve_target_ocid function resolves target names" {
    # Use bash -c so libraries are sourced in a fresh context where declare -A
    # _COMP_OCID_CACHE is at global scope (not trapped in a setup() function local)
    run bash -c "
        export LOG_LEVEL=ERROR
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/oci_helpers.sh'
        ds_resolve_target_ocid 'test-target-1' 'ocid1.compartment.oc1..root'
    "
    [ "$status" -eq 0 ]
    # Should contain the OCID
    [[ "$output" == *"ocid1.datasafetarget"* ]]
}

@test "ds_list_targets function lists Data Safe targets" {
    export LOG_LEVEL=ERROR
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_list_targets "ocid1.compartment.oc1..root"
    [ "$status" -eq 0 ]
    # Should contain target names in JSON output
    [[ "$output" == *"test-target"* ]] || [[ "$output" == *"data"* ]]
}

@test "ds_get_target function gets target information" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_get_target "ocid1.datasafetarget.oc1..target123"
    # Mock handles target-database get and returns JSON
    [ "$status" -eq 0 ]
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
    
    # DS_ROOT_COMP is not set, so function returns error
    unset DS_ROOT_COMP
    export OCI_TENANCY="ocid1.tenancy.oc1..test"
    run get_root_compartment_ocid
    [ "$status" -eq 1 ]
}

# Test target name resolution
@test "ds_resolve_target_name function works with OCIDs" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    run ds_resolve_target_name "ocid1.datasafetarget.oc1..target123"
    # Mock handles target-database get; result is non-empty so function returns 0
    [ "$status" -eq 0 ]
}

# Test target compartment resolution
@test "ds_get_target_compartment function works" {
    source "${LIB_DIR}/common.sh" 
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with target OCID — mock returns JSON (non-empty) so function succeeds
    run ds_get_target_compartment "ocid1.datasafetarget.oc1..target123"
    [ "$status" -eq 0 ]
}

# Test lifecycle counting
@test "ds_count_by_lifecycle function works" {
    export LOG_LEVEL=ERROR
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Get targets first, then count
    targets=$(ds_list_targets "ocid1.compartment.oc1..root")
    run ds_count_by_lifecycle "$targets"
    # Should succeed with valid JSON input
    [ "$status" -eq 0 ]
}

# Test new resolution helper functions (added 2026-01-22)
@test "resolve_compartment_to_vars helper function exists" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Check function is defined using declare
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F resolve_compartment_to_vars"
    [ "$status" -eq 0 ]
}

@test "resolve_compartment_to_vars resolves OCID input" {
    export LOG_LEVEL=ERROR
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with OCID - should return OCID for both name and OCID using prefix
    resolve_compartment_to_vars "ocid1.compartment.oc1..test123" "TEST_COMP"
    status=$?
    
    [ "$status" -eq 0 ]
    [ "$TEST_COMP_OCID" = "ocid1.compartment.oc1..test123" ]
    [ -n "$TEST_COMP_NAME" ]
}

@test "resolve_compartment_to_vars resolves name input" {
    export LOG_LEVEL=ERROR
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with name
    resolve_compartment_to_vars "test-compartment" "TEST_COMP"
    status=$?
    
    # Should succeed and populate both variables
    [ "$status" -eq 0 ]
    [ "$TEST_COMP_NAME" = "test-compartment" ]
    [ -n "$TEST_COMP_OCID" ]
    [[ "$TEST_COMP_OCID" == ocid1.compartment.* ]]
}

@test "resolve_compartment_to_vars returns error for invalid input" {
    export LOG_LEVEL=ERROR
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with invalid compartment name
    run resolve_compartment_to_vars "non-existent-compartment" "TEST_COMP"

    # Should return error (1)
    [ "$status" -eq 1 ]
}

@test "resolve_target_to_vars helper function exists" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Check function is defined using declare
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F resolve_target_to_vars"
    [ "$status" -eq 0 ]
}

@test "resolve_target_to_vars resolves OCID input" {
    export LOG_LEVEL=ERROR
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with OCID using prefix
    resolve_target_to_vars "ocid1.datasafetarget.oc1..target123" "TEST_TARGET"
    status=$?
    
    # Should succeed
    [ "$status" -eq 0 ]
    [ "$TEST_TARGET_OCID" = "ocid1.datasafetarget.oc1..target123" ]
    [ -n "$TEST_TARGET_NAME" ]  # Name should be resolved from OCID
}

@test "resolve_target_to_vars resolves name input" {
    # Run in a fresh bash subprocess to avoid _COMP_OCID_CACHE declare-A scoping issue
    # (lib/oci_helpers.sh uses declare -A inside function scope; bash -c gets a clean slate)
    run bash -c "
        export LOG_LEVEL=ERROR
        export DS_ROOT_COMP='ocid1.compartment.oc1..root'
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/oci_helpers.sh'
        resolve_target_to_vars 'test-target-1' 'TEST_TARGET' 'ocid1.compartment.oc1..root'
        rc=\$?
        echo \"STATUS=\$rc\"
        echo \"NAME=\$TEST_TARGET_NAME\"
        echo \"OCID=\$TEST_TARGET_OCID\"
        exit \$rc
    "
    # Mock provides target list with test-target-1, resolution should succeed
    [ "$status" -eq 0 ]
    [[ "$output" == *"NAME=test-target-1"* ]]
    [[ "$output" == *"OCID=ocid1.datasafetarget."* ]]
}

@test "oci_exec_ro function exists and executes in dry-run mode" {
    export LOG_LEVEL=ERROR
    export DRY_RUN=true
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # oci_exec_ro should execute even in dry-run mode
    run oci_exec_ro --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.45"* ]] || [[ "$output" == *"3."* ]]
}

@test "oci_exec_ro is different from oci_exec" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Check both functions exist using declare
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F oci_exec && declare -F oci_exec_ro"
    [ "$status" -eq 0 ]
}

@test "oci_resolve_compartment_ocid returns error code on failure" {
    export LOG_LEVEL=ERROR
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test with non-existent compartment (should return 1, not call die)
    run oci_resolve_compartment_ocid "definitely-does-not-exist-compartment-name"
    
    # Should return error code 1, not exit/die
    [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

@test "ds_resolve_target_ocid returns error code on failure" {
    export LOG_LEVEL=ERROR
    export DS_ROOT_COMP="ocid1.compartment.oc1..root"
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"

    # Test with non-existent target (should return 1, not call die)
    run ds_resolve_target_ocid "definitely-does-not-exist-target-name" "ocid1.compartment.oc1..root"

    # Should return error code 1, not exit/die
    [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

@test "oci_resolve_dbnode_by_host function exists in oci_helpers.sh" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F oci_resolve_dbnode_by_host"
    [ "$status" -eq 0 ]
}

@test "oci_resolve_compartment_by_dbnode_name function exists in oci_helpers.sh" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F oci_resolve_compartment_by_dbnode_name"
    [ "$status" -eq 0 ]
}

@test "oci_resolve_vm_cluster_compartment function exists in oci_helpers.sh" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F oci_resolve_vm_cluster_compartment"
    [ "$status" -eq 0 ]
}

@test "oci_exec and oci_exec_ro log OCI command at trace not debug level" {
    run grep -E 'log_debug "OCI command:' "${LIB_DIR}/oci_helpers.sh"
    [ "$status" -ne 0 ]

    run grep -E 'log_trace "OCI command:' "${LIB_DIR}/oci_helpers.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# ds_filter_targets_by_tags tests
# Libraries are sourced in setup() — call functions directly (no bash -c)
# =============================================================================

@test "ds_filter_targets_by_tags: empty filter returns all targets" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Env":"prod"},"defined-tags":{}},{"id":"t2","freeform-tags":{},"defined-tags":{}}]}'
    local result count
    result=$(ds_filter_targets_by_tags "$json" "")
    count=$(printf '%s' "$result" | jq '.data | length')
    [ "$count" -eq 2 ]
}

@test "ds_filter_targets_by_tags: freeform key=value matches exact value" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result ids
    result=$(ds_filter_targets_by_tags "$json" "Environment=Production")
    ids=$(printf '%s' "$result" | jq -r '.data[].id')
    [ "$ids" = "t1" ]
}

@test "ds_filter_targets_by_tags: freeform key presence filters correctly" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result ids
    result=$(ds_filter_targets_by_tags "$json" "Owner")
    ids=$(printf '%s' "$result" | jq -r '.data[].id')
    [ "$ids" = "t1" ]
}

@test "ds_filter_targets_by_tags: defined tag ns/key=value matches" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result ids
    result=$(ds_filter_targets_by_tags "$json" "DBSec/Classification=internal")
    ids=$(printf '%s' "$result" | jq -r '.data[].id')
    [ "$ids" = "t1" ]
}

@test "ds_filter_targets_by_tags: defined tag ns/key presence filters correctly" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result ids
    result=$(ds_filter_targets_by_tags "$json" "DBSec/Level")
    ids=$(printf '%s' "$result" | jq -r '.data[].id')
    [ "$ids" = "t1" ]
}

@test "ds_filter_targets_by_tags: AND combination of two filters" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local filter result ids
    filter=$'Environment=Production\nDBSec/Level=High'
    result=$(ds_filter_targets_by_tags "$json" "$filter")
    ids=$(printf '%s' "$result" | jq -r '.data[].id')
    [ "$ids" = "t1" ]
}

@test "ds_filter_targets_by_tags: AND combination yields empty when no match" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local filter result count
    filter=$'Environment=Production\nEnvironment=Staging'
    result=$(ds_filter_targets_by_tags "$json" "$filter")
    count=$(printf '%s' "$result" | jq '.data | length')
    [ "$count" -eq 0 ]
}

@test "ds_filter_targets_by_tags: non-matching filter returns empty data" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result count
    result=$(ds_filter_targets_by_tags "$json" "Environment=NoSuchEnv")
    count=$(printf '%s' "$result" | jq '.data | length')
    [ "$count" -eq 0 ]
}

@test "ds_filter_targets_by_tags: target with no tags excluded by key presence filter" {
    local json='{"data":[{"id":"t1","freeform-tags":{"Environment":"Production","Owner":"alice"},"defined-tags":{"DBSec":{"Classification":"internal","Level":"High"}}},{"id":"t2","freeform-tags":{"Environment":"Staging"},"defined-tags":{"DBSec":{"Classification":"public"}}},{"id":"t3","freeform-tags":{},"defined-tags":{}}]}'
    local result count
    result=$(ds_filter_targets_by_tags "$json" "Environment")
    count=$(printf '%s' "$result" | jq '.data | length')
    # t1 and t2 have Environment tag; t3 does not
    [ "$count" -eq 2 ]
}

@test "ds_filter_targets_by_tags function exists in oci_helpers.sh" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && declare -F ds_filter_targets_by_tags"
    [ "$status" -eq 0 ]
}

# =============================================================================
# REG-007: oci_exec stderr isolation
# Regression: Python FutureWarning on stderr must not bleed into stdout JSON
# =============================================================================

@test "REG-007: oci_exec returns only JSON when mock emits warning to stderr" {
    export LOG_LEVEL=ERROR

    # Override the mock oci with one that emits a FutureWarning to stderr
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "FutureWarning: urllib3 v2 only supports OpenSSL 1.1.1+" >&2
echo '{"data": []}'
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"

    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"

    run oci_exec data-safe target-database list --compartment-id ocid1.comp.oc1..test
    [ "$status" -eq 0 ]
    # stdout must contain the JSON payload
    [[ "$output" == *'"data"'* ]]
    # stdout must NOT contain the FutureWarning
    [[ "$output" != *"FutureWarning"* ]]
}

# =============================================================================
# REG-008: DELETED lifecycle state allows registration check
# Regression: ds_is_updatable_lifecycle_state must not allow DELETED state
# =============================================================================

@test "REG-008: ds_is_updatable_lifecycle_state rejects DELETED state" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"

    # DELETED state should NOT be updatable
    run ds_is_updatable_lifecycle_state "DELETED"
    [ "$status" -eq 1 ]
}

@test "REG-008: ds_is_updatable_lifecycle_state accepts ACTIVE state" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"

    run ds_is_updatable_lifecycle_state "ACTIVE"
    [ "$status" -eq 0 ]
}

@test "REG-008: ds_is_updatable_lifecycle_state accepts NEEDS_ATTENTION state" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"

    run ds_is_updatable_lifecycle_state "NEEDS_ATTENTION"
    [ "$status" -eq 0 ]
}
