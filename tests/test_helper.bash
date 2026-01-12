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
