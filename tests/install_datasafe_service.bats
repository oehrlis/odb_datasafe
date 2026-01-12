#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# BATS tests for install_datasafe_service.sh
# ------------------------------------------------------------------------------

load 'test_helper'

setup() {
    export TEST_DIR="${BATS_TEST_TMPDIR}/datasafe_test"
    export CONNECTOR_BASE="$TEST_DIR/connectors"
    export TEST_CONNECTOR="test-connector-001"
    export SCRIPT_PATH="${BATS_TEST_DIRNAME}/../bin/install_datasafe_service.sh"
    
    # Create test connector structure
    mkdir -p "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/bin"
    mkdir -p "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/network/admin"
    mkdir -p "$CONNECTOR_BASE/$TEST_CONNECTOR/log"
    
    # Create mock cmctl
    cat > "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/bin/cmctl" << 'EOF'
#!/bin/bash
echo "Mock cmctl: $*"
exit 0
EOF
    chmod +x "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/bin/cmctl"
    
    # Create mock cman.ora
    cat > "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/network/admin/cman.ora" << EOF
test_cman = (CONFIGURATION =
  (ADDRESS = (PROTOCOL=tcp)(HOST=localhost)(PORT=1630))
)
EOF
    
    # Create mock Java
    export JAVA_HOME="$TEST_DIR/jdk"
    mkdir -p "$JAVA_HOME/bin"
    cat > "$JAVA_HOME/bin/java" << 'EOF'
#!/bin/bash
echo "Mock Java"
exit 0
EOF
    chmod +x "$JAVA_HOME/bin/java"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "install_datasafe_service.sh exists and is executable" {
    [[ -x "$SCRIPT_PATH" ]]
}

@test "install_datasafe_service.sh shows help" {
    run "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"install_datasafe_service.sh"* ]]
}

@test "install_datasafe_service.sh shows version in help" {
    run "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.0.0"* ]] || [[ "$output" == *"Version"* ]]
}

@test "install_datasafe_service.sh supports --no-color flag" {
    run "$SCRIPT_PATH" --no-color --help
    [ "$status" -eq 0 ]
    # Should not contain ANSI color codes
    ! [[ "$output" =~ $'\033' ]]
}

@test "install_datasafe_service.sh test mode works without root" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST"* ]] || [[ "$output" == *"test"* ]]
}

@test "install_datasafe_service.sh dry-run mode works without root" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --dry-run \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"dry-run"* ]]
}

@test "install_datasafe_service.sh validates connector existence" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "nonexistent-connector" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "install_datasafe_service.sh detects CMAN name from cman.ora" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes \
        --verbose
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_cman"* ]]
}

@test "install_datasafe_service.sh generates service file in test mode" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"[Unit]"* ]]
    [[ "$output" == *"Description"* ]]
    [[ "$output" == *"ExecStart"* ]]
}

@test "install_datasafe_service.sh shows configuration in test mode" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user testuser \
        --group testgroup \
        --test \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"testuser"* ]]
    [[ "$output" == *"testgroup"* ]]
    [[ "$output" == *"$TEST_CONNECTOR"* ]]
}

@test "install_datasafe_service.sh skip-sudo flag works" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --skip-sudo \
        --test \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip"* ]] || ! [[ "$output" == *"sudoers"* ]]
}

@test "install_datasafe_service.sh handles missing cmctl" {
    rm -f "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/bin/cmctl"
    
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"cmctl"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "install_datasafe_service.sh handles missing cman.ora" {
    rm -f "$CONNECTOR_BASE/$TEST_CONNECTOR/oracle_cman_home/network/admin/cman.ora"
    
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"cman.ora"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "install_datasafe_service.sh handles missing Java" {
    rm -f "$JAVA_HOME/bin/java"
    
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --test \
        --yes
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"Java"* ]] || [[ "$output" == *"JAVA_HOME"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "install_datasafe_service.sh verbose mode provides extra output" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --verbose \
        --test \
        --yes
    
    [ "$status" -eq 0 ]
    # Verbose output should include CMAN instance name
    [[ "$output" == *"test_cman"* ]]
}
