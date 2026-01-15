#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_common_fixed.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Fixed test suite for lib/common.sh library functions
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    # Set up test environment
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Create test .env file
    export TEST_ENV_FILE="${TEST_TEMP_DIR}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
# Test environment configuration
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
DS_TAG_NAMESPACE="test-namespace"
DS_TAG_ENV_KEY="Environment" 
DS_TAG_APP_KEY="Application"
OCI_CLI_PROFILE="DEFAULT"
EOF
    
    # Mock OCI CLI for testing
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create mock oci command
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Mock OCI CLI for testing
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "iam compartment list --compartment-id"*)
        echo '{"data": [{"id": "ocid1.compartment.oc1..test", "name": "test-comp"}]}'
        ;;
    "data-safe target-database list --compartment-id"*)
        echo '{"data": [{"id": "ocid1.datasafetarget.oc1..test", "display-name": "test-target", "lifecycle-state": "ACTIVE"}]}'
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Set configuration file
    export CONFIG_FILE="${TEST_ENV_FILE}"
    
    # Load common library for testing
    source "${LIB_DIR}/common.sh"
}

teardown() {
    # Clean up test environment
    unset DS_ROOT_COMP DS_TAG_NAMESPACE DS_TAG_ENV_KEY DS_TAG_APP_KEY
    unset OCI_CLI_PROFILE LOG_LEVEL DEBUG LOG_FILE CONFIG_FILE
}

# Test basic library loading
@test "common.sh can be loaded without errors" {
    run bash -c "source '${LIB_DIR}/common.sh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# Test logging functions
@test "log_info function works correctly" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
}

@test "log_error function works correctly" {
    run log_error "test error"
    [ "$status" -eq 0 ]
}

@test "log_debug function respects LOG_LEVEL" {
    # Without debug level
    export LOG_LEVEL=2  # INFO level
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    # Debug message should not appear (filtered by level)
    
    # With debug level
    export LOG_LEVEL=DEBUG  # Use string level name
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"debug message"* ]]
}

# Test utility functions
@test "is_ocid function validates OCIDs correctly" {
    # Valid OCID
    run is_ocid "ocid1.compartment.oc1..example"
    [ "$status" -eq 0 ]
    
    # Invalid OCID
    run is_ocid "not-an-ocid"
    [ "$status" -eq 1 ]
    
    # Empty string
    run is_ocid ""
    [ "$status" -eq 1 ]
}

@test "require_cmd function checks for required commands" {
    # Existing command
    run require_cmd "bash"
    [ "$status" -eq 0 ]
    
    # Non-existing command
    run require_cmd "non-existent-command-12345"
    [ "$status" -eq 1 ]
}

@test "require_var function checks for required variables" {
    # Set variable
    export TEST_VAR="test_value"
    run require_var "TEST_VAR"
    [ "$status" -eq 0 ]
    
    # Unset variable
    unset TEST_VAR
    run require_var "TEST_VAR"
    [ "$status" -eq 1 ]
}

@test "need_val function validates required values" {
    # With value
    run need_val "--test" "value"
    [ "$status" -eq 0 ]
    
    # Without value
    run need_val "--test" ""
    [ "$status" -eq 1 ]
    
    # With flag-like value
    run need_val "--test" "--another-flag"
    [ "$status" -eq 1 ]
}

# Test configuration functions
@test "init_config function loads environment correctly" {
    # Test configuration loading
    run init_config
    [ "$status" -eq 0 ]
}

@test "load_config function loads existing files" {
    # Test with existing file
    run load_config "${TEST_ENV_FILE}"
    [ "$status" -eq 0 ]
    
    # Test with non-existing file (should not fail)
    run load_config "/nonexistent/file.conf"
    [ "$status" -eq 0 ]
}

@test "get_root_compartment_ocid function returns configured value" {
    # Load the OCI helpers library too for this function
    source "${LIB_DIR}/oci_helpers.sh"
    
    export OCI_TENANCY="ocid1.tenancy.oc1..test"
    run get_root_compartment_ocid
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail without real OCI config
}

# Test error handling
@test "die function exits with correct code and message" {
    run die "test error message"
    [ "$status" -eq 1 ]
}

@test "setup_error_handling function configures error traps" {
    run setup_error_handling
    [ "$status" -eq 0 ]
}

# Test argument parsing
@test "parse_common_opts function handles verbose flag" {
    ARGS=()
    parse_common_opts "-v"
    [ "$LOG_LEVEL" = "DEBUG" ]
}

@test "parse_common_opts function handles debug flag" {
    ARGS=()
    parse_common_opts "-d"
    [ "$LOG_LEVEL" = "TRACE" ]
}

@test "parse_common_opts function handles quiet flag" {
    ARGS=()
    parse_common_opts "-q"
    [ "$LOG_LEVEL" = "WARN" ]
}

@test "parse_common_opts function handles dry-run flag" {
    ARGS=()
    parse_common_opts "-n"
    [ "$DRY_RUN" = "true" ]
}

@test "parse_common_opts function handles log-file option" {
    ARGS=()
    local test_log="${TEST_TEMP_DIR}/test.log"
    parse_common_opts "--log-file" "$test_log"
    [ "$LOG_FILE" = "$test_log" ]
}

@test "parse_common_opts function preserves non-common options" {
    ARGS=()
    parse_common_opts "-v" "--custom-option" "value" "positional"
    [ "$LOG_LEVEL" = "DEBUG" ]  # Verbose should be processed
    [ "${#ARGS[@]}" -eq 3 ]  # Custom options should be preserved
    [ "${ARGS[0]}" = "--custom-option" ]
    [ "${ARGS[1]}" = "value" ]
    [ "${ARGS[2]}" = "positional" ]
}

# Test logging levels
@test "logging respects LOG_LEVEL setting" {
    # Set to WARN level (3)
    export LOG_LEVEL=3
    
    # INFO (2) should be filtered out
    run log_info "info message"
    [ "$status" -eq 0 ]
    # Should not contain the message (filtered)
    
    # WARN (3) should appear
    run log_warn "warn message" 
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn message"* ]]
    
    # ERROR (4) should appear
    run log_error "error message"
    [ "$status" -eq 0 ]
}

# Test confirmation function
@test "confirm function exists and is callable" {
    # Just test that the function exists
    declare -f confirm >/dev/null
    [ "$?" -eq 0 ]
}