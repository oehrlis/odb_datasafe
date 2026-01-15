# ------------------------------------------------------------------------------
# Test helper for BATS tests
# ------------------------------------------------------------------------------

# Helper function to skip tests if running as root
skip_if_root() {
    if [[ $EUID -eq 0 ]]; then
        skip "This test should run as non-root user"
    fi
}

# Helper function to skip tests if NOT running as root
skip_if_not_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "This test requires root privileges"
    fi
}

# Helper function to create a temporary test directory
create_test_dir() {
    local test_dir="${BATS_TMPDIR}/test_$$_${RANDOM}"
    mkdir -p "$test_dir"
    echo "$test_dir"
}

# Helper function to cleanup test directory
cleanup_test_dir() {
    local test_dir="$1"
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

# Helper function to skip tests if OCI CLI is not configured
# Tests requiring actual OCI CLI access should be skipped when not in a real environment
skip_if_no_oci_config() {
    # Check if OCI CLI is installed
    if ! command -v oci &>/dev/null; then
        skip "OCI CLI not installed - skipping test requiring OCI access"
    fi
    
    # Check if OCI config file exists
    local config_file="${OCI_CLI_CONFIG_FILE:-${HOME}/.oci/config}"
    if [[ ! -f "$config_file" ]]; then
        skip "OCI CLI config not found at $config_file - skipping test requiring OCI access"
    fi
    
    # Check if running in mock environment (PATH contains test temp dir)
    if [[ "$PATH" == *"${BATS_TEST_TMPDIR}"* ]] || [[ "$PATH" == *"${TEST_TEMP_DIR}"* ]]; then
        # We're in a mock environment, allow tests to run
        return 0
    fi
    
    # Try to validate OCI CLI config by checking version
    if ! oci --version &>/dev/null; then
        skip "OCI CLI not working - skipping test requiring OCI access"
    fi
}
