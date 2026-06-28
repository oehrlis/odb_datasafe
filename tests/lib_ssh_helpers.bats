#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_ssh_helpers.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.06.28
# Purpose....: Test suite for lib/ssh_helpers.sh library functions
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"

    # Load libraries under test
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/ssh_helpers.sh"
}

teardown() {
    unset SSH_CONNECT_TIMEOUT SSH_SERVER_ALIVE_INTERVAL SSH_SERVER_ALIVE_COUNT_MAX
    unset SSH_STRICT_HOST_KEY_CHECKING SSH_KNOWN_HOSTS_FILE SSH_EXTRA_OPTS
}

# =============================================================================
# Library loading
# =============================================================================

@test "ssh_helpers.sh can be loaded without errors" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/ssh_helpers.sh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "ssh_helpers.sh is idempotent (double source does not error)" {
    run bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/ssh_helpers.sh'
        source '${LIB_DIR}/ssh_helpers.sh'
        echo 'loaded twice'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded twice"* ]]
}

@test "ssh_helpers.sh requires common.sh to be loaded first" {
    run bash -c "source '${LIB_DIR}/ssh_helpers.sh'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# ssh_require_tools
# =============================================================================

@test "ssh_require_tools function exists" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/ssh_helpers.sh' && declare -F ssh_require_tools"
    [ "$status" -eq 0 ]
}

@test "ssh_require_tools succeeds when ssh and scp are available" {
    # ssh and scp are standard tools available on any developer machine
    run ssh_require_tools
    [ "$status" -eq 0 ]
}

# =============================================================================
# ssh_exec
# =============================================================================

@test "ssh_exec function exists" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/ssh_helpers.sh' && declare -F ssh_exec"
    [ "$status" -eq 0 ]
}

@test "ssh_exec fails to connect to non-routable host" {
    # 192.0.2.1 is TEST-NET-1 (RFC 5737) — guaranteed non-routable
    export SSH_CONNECT_TIMEOUT=2
    export SSH_STRICT_HOST_KEY_CHECKING=no
    run ssh_exec "192.0.2.1" "testuser" "22" "true"
    # Should fail — connection refused or timeout
    [ "$status" -ne 0 ]
}

@test "ssh_exec builds ConnectTimeout option from SSH_CONNECT_TIMEOUT" {
    # Replace ssh with a mock that records arguments
    local mock_bin="${TEST_TEMP_DIR}/ssh_mock_bin"
    mkdir -p "$mock_bin"
    cat > "${mock_bin}/ssh" << 'MOCK'
#!/usr/bin/env bash
echo "$@"
exit 0
MOCK
    chmod +x "${mock_bin}/ssh"

    export SSH_CONNECT_TIMEOUT=5
    export SSH_STRICT_HOST_KEY_CHECKING=no
    unset SSH_KNOWN_HOSTS_FILE SSH_EXTRA_OPTS

    PATH="${mock_bin}:${PATH}" run ssh_exec "myhost" "myuser" "2222" "echo hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ConnectTimeout=5"* ]]
    [[ "$output" == *"myuser@myhost"* ]]
}

@test "ssh_exec includes StrictHostKeyChecking option" {
    local mock_bin="${TEST_TEMP_DIR}/ssh_hk_mock_bin"
    mkdir -p "$mock_bin"
    cat > "${mock_bin}/ssh" << 'MOCK'
#!/usr/bin/env bash
echo "$@"
exit 0
MOCK
    chmod +x "${mock_bin}/ssh"

    export SSH_STRICT_HOST_KEY_CHECKING=accept-new
    unset SSH_KNOWN_HOSTS_FILE SSH_EXTRA_OPTS

    PATH="${mock_bin}:${PATH}" run ssh_exec "host1" "user1" "22" "date"
    [ "$status" -eq 0 ]
    [[ "$output" == *"StrictHostKeyChecking=accept-new"* ]]
}

# =============================================================================
# ssh_scp_to
# =============================================================================

@test "ssh_scp_to function exists" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/ssh_helpers.sh' && declare -F ssh_scp_to"
    [ "$status" -eq 0 ]
}

@test "ssh_scp_to fails to connect to non-routable host" {
    local src_file="${TEST_TEMP_DIR}/src_test.txt"
    printf 'test content\n' > "$src_file"

    export SSH_CONNECT_TIMEOUT=2
    export SSH_STRICT_HOST_KEY_CHECKING=no
    run ssh_scp_to "$src_file" "192.0.2.1" "testuser" "22" "/tmp/dst.txt"
    # Should fail — connection refused or timeout
    [ "$status" -ne 0 ]
}

@test "ssh_scp_to builds correct scp command with ConnectTimeout" {
    local mock_bin="${TEST_TEMP_DIR}/scp_mock_bin"
    mkdir -p "$mock_bin"
    cat > "${mock_bin}/scp" << 'MOCK'
#!/usr/bin/env bash
echo "$@"
exit 0
MOCK
    chmod +x "${mock_bin}/scp"

    local src_file="${TEST_TEMP_DIR}/payload.txt"
    printf 'content\n' > "$src_file"

    export SSH_CONNECT_TIMEOUT=3
    export SSH_STRICT_HOST_KEY_CHECKING=no
    unset SSH_KNOWN_HOSTS_FILE SSH_EXTRA_OPTS

    PATH="${mock_bin}:${PATH}" run ssh_scp_to "$src_file" "remotehost" "remoteuser" "2222" "/remote/path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-P 2222"* ]]
    [[ "$output" == *"ConnectTimeout=3"* ]]
    [[ "$output" == *"remoteuser@remotehost:/remote/path"* ]]
}

# =============================================================================
# ssh_check
# =============================================================================

@test "ssh_check function exists" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/ssh_helpers.sh' && declare -F ssh_check"
    [ "$status" -eq 0 ]
}

@test "ssh_check fails for non-routable host" {
    export SSH_CONNECT_TIMEOUT=2
    export SSH_STRICT_HOST_KEY_CHECKING=no
    run ssh_check "192.0.2.1" "testuser" "22"
    # Should fail — connection refused or timeout
    [ "$status" -ne 0 ]
}

@test "ssh_check produces no output on failure" {
    export SSH_CONNECT_TIMEOUT=2
    export SSH_STRICT_HOST_KEY_CHECKING=no
    run ssh_check "192.0.2.1" "testuser" "22"
    # ssh_check redirects all output to /dev/null
    [ -z "$output" ]
}

# =============================================================================
# Default variable values
# =============================================================================

@test "SSH_CONNECT_TIMEOUT default is 10" {
    run bash -c "
        source '${LIB_DIR}/common.sh'
        unset SSH_CONNECT_TIMEOUT
        source '${LIB_DIR}/ssh_helpers.sh'
        echo \"\$SSH_CONNECT_TIMEOUT\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "SSH_STRICT_HOST_KEY_CHECKING default is accept-new" {
    run bash -c "
        source '${LIB_DIR}/common.sh'
        unset SSH_STRICT_HOST_KEY_CHECKING
        source '${LIB_DIR}/ssh_helpers.sh'
        echo \"\$SSH_STRICT_HOST_KEY_CHECKING\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "accept-new" ]
}
