#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_oci_cli_auth.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.23
# Purpose....: Test suite for OCI CLI authentication checks
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Setup PATH for mock commands
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Set test environment variables
    export OCI_CLI_CONFIG_FILE="${TEST_TEMP_DIR}/.oci/config"
    export OCI_CLI_PROFILE="TEST"
    export LOG_LEVEL=ERROR  # Suppress normal logging during tests
}

# Test teardown
teardown() {
    # Clear cache between tests
    unset _OCI_CLI_AUTH_CHECKED
}

# ==============================================================================
# Test: check_oci_cli_auth - successful authentication
# ==============================================================================
@test "check_oci_cli_auth: succeeds when OCI CLI is authenticated" {
    # Create mock oci command that succeeds
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"os ns get"*)
        echo '{"data": "test-namespace"}'
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function
    run check_oci_cli_auth
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Test: check_oci_cli_auth - failed authentication
# ==============================================================================
@test "check_oci_cli_auth: fails when OCI CLI authentication fails" {
    # Create mock oci command that fails
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "ServiceError: NotAuthenticated" >&2
exit 1
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function
    run check_oci_cli_auth
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Test: check_oci_cli_auth - config file not found
# ==============================================================================
@test "check_oci_cli_auth: fails with helpful message when config not found" {
    # Create mock oci command that reports config not found
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "ConfigFileNotFound: Could not find config file" >&2
exit 1
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function
    run check_oci_cli_auth
    [ "$status" -eq 1 ]
    [[ "$output" =~ "config file not found" ]] || [[ "$output" =~ "ConfigFileNotFound" ]]
}

# ==============================================================================
# Test: check_oci_cli_auth - profile not found
# ==============================================================================
@test "check_oci_cli_auth: fails with helpful message when profile not found" {
    # Create mock oci command that reports profile not found
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
echo "ProfileNotFound: Profile 'TEST' not found" >&2
exit 1
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Create a fake config file
    mkdir -p "${TEST_TEMP_DIR}/.oci"
    cat > "${OCI_CLI_CONFIG_FILE}" << 'CONF'
[DEFAULT]
user=ocid1.user.oc1..test
CONF
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function
    run check_oci_cli_auth
    [ "$status" -eq 1 ]
    [[ "$output" =~ "profile" ]] || [[ "$output" =~ "ProfileNotFound" ]]
}

# ==============================================================================
# Test: check_oci_cli_auth - caching works
# ==============================================================================
@test "check_oci_cli_auth: caches successful authentication result" {
    # Create mock oci command that succeeds
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Write to a file to track call count
echo "called" >> "${TEST_TEMP_DIR}/oci_calls.log"
case "$*" in
    *"os ns get"*)
        echo '{"data": "test-namespace"}'
        exit 0
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Call twice
    check_oci_cli_auth
    check_oci_cli_auth
    
    # Should only be called once due to caching
    call_count=$(wc -l < "${TEST_TEMP_DIR}/oci_calls.log" 2>/dev/null || echo "0")
    [ "$call_count" -eq 1 ]
}

# ==============================================================================
# Test: require_oci_cli - all checks pass
# ==============================================================================
@test "require_oci_cli: succeeds when oci and jq are available and authenticated" {
    # Create mock commands
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"os ns get"*)
        echo '{"data": "test-namespace"}'
        exit 0
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    cat > "${TEST_TEMP_DIR}/bin/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function
    run require_oci_cli
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Test: require_oci_cli - missing oci command
# ==============================================================================
@test "require_oci_cli: fails when oci command is not found" {
    # Don't create oci command, but create jq
    cat > "${TEST_TEMP_DIR}/bin/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function - should fail due to missing oci
    run require_oci_cli
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Missing required commands" ]] || [[ "$output" =~ "oci" ]]
}

# ==============================================================================
# Test: require_oci_cli - authentication fails
# ==============================================================================
@test "require_oci_cli: fails when authentication fails" {
    # Create mock commands - oci fails auth, jq works
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"os ns get"*)
        echo "ServiceError: NotAuthenticated" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    cat > "${TEST_TEMP_DIR}/bin/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/jq"
    
    # Source libraries
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/oci_helpers.sh"
    
    # Test the function - should fail due to auth failure
    run require_oci_cli
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not properly authenticated" ]] || [[ "$output" =~ "authentication failed" ]]
}
