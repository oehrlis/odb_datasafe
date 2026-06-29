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
    [[ "$output" == *"v1.1.0"* ]] || [[ "$output" == *"Version"* ]]
}

@test "install_datasafe_service.sh supports --no-color flag" {
    run "$SCRIPT_PATH" --no-color --help
    [ "$status" -eq 0 ]
    # Should not contain ANSI color codes
    ! [[ "$output" =~ $'\033' ]]
}

@test "install_datasafe_service.sh list mode works without root" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --list
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"connector"* ]]
}

@test "install_datasafe_service.sh prepare mode works without root" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --prepare \
        --dry-run \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"TEST"* ]]
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
        --prepare \
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
        --prepare \
        --yes
    
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "install_datasafe_service.sh detects CMAN name from cman.ora" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --prepare \
        --dry-run \
        --yes \
        --verbose
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_cman"* ]]
}

@test "install_datasafe_service.sh generates service file in prepare mode" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --prepare \
        --dry-run \
        --yes
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"[Unit]"* ]]
    [[ "$output" == *"Description"* ]]
    [[ "$output" == *"ExecStart"* ]]
}

@test "install_datasafe_service.sh shows configuration in prepare mode" {
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user testuser \
        --group testgroup \
        --prepare \
        --dry-run \
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

# ==============================================================================
# REG-001..REG-006 — Installer regression tests (required before M3 refactor)
# Source: doc/review/findings/testing.md "Required Regression Tests" table
#
# All 6 tests green after M3 (v0.23.0):
#   REG-001  PASS  - ORACLE_BASE auto-discovery works without --base
#   REG-002  PASS  - missing connector exits non-zero
#   REG-003  PASS  - auto-regen chown skipped in DRY_RUN mode (ARCH-008 fix)
#   REG-004  PASS  - missing sudoers warning works
#   REG-005  PASS  - missing ExecStart warning works
#   REG-006  PASS  - log dir creation reported in dry-run plan section (BASH-016/ARCH-007 fix)
# ==============================================================================

# Helper: create a connector structure at an arbitrary base path
_create_connector_at() {
    local base="$1"
    local connector="$2"
    local root="$base/$connector"
    mkdir -p "$root/oracle_cman_home/bin"
    mkdir -p "$root/oracle_cman_home/network/admin"
    mkdir -p "$root/log"
    cat > "$root/oracle_cman_home/bin/cmctl" << 'CMCTL'
#!/bin/bash
echo "Mock cmctl: $*"
exit 0
CMCTL
    chmod +x "$root/oracle_cman_home/bin/cmctl"
    cat > "$root/oracle_cman_home/network/admin/cman.ora" << CMANORA
test_cman = (CONFIGURATION =
  (ADDRESS = (PROTOCOL=tcp)(HOST=localhost)(PORT=1630))
)
CMANORA
}

# REG-001: find_connector_base auto-discovers connector via ORACLE_BASE
# Scenario: connector lives under ORACLE_BASE/product; --base is not given;
#           the script must resolve the path through ORACLE_BASE.
@test "REG-001: auto-discovers connector via ORACLE_BASE (no --base flag)" {
    local alt_oracle="$TEST_DIR/alt_oracle"
    local alt_product="$alt_oracle/product"
    _create_connector_at "$alt_product" "$TEST_CONNECTOR"

    run env ORACLE_BASE="$alt_oracle" JAVA_HOME="$JAVA_HOME" \
        "$SCRIPT_PATH" \
        --connector "$TEST_CONNECTOR" \
        --prepare --dry-run --yes --no-color

    [ "$status" -eq 0 ]
    # Script found and validated the connector
    [[ "$output" == *"$TEST_CONNECTOR"* ]]
}

# REG-002: find_connector_base returns non-zero when connector is nowhere
# Scenario: no --base given, ORACLE_BASE points to an empty dir, connector name
#           does not match any path in the candidate list.
@test "REG-002: exits non-zero when connector is not found in any candidate path" {
    local empty_base="$TEST_DIR/empty_oracle"
    mkdir -p "$empty_base"

    run env ORACLE_BASE="$empty_base" JAVA_HOME="$JAVA_HOME" \
        "$SCRIPT_PATH" \
        --connector "nonexistent-connector-xyz" \
        --prepare --dry-run --yes --no-color

    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}

# REG-003: --install warns when --user CLI arg differs from User= in prepared service file
# Scenario: --prepare runs with --user oracle; --install runs with --user datasafe;
#           script emits a WARNING; no auto-regeneration (two-phase workflow enforced).
@test "REG-003: install warns when --user differs from prepared service file User=" {
    # Prepare with user "oracle"
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --prepare --yes --no-color

    [ "$status" -eq 0 ]

    # Service file must exist and have User=oracle
    local svc_file="$CONNECTOR_BASE/$TEST_CONNECTOR/etc/systemd/oracle_datasafe_${TEST_CONNECTOR}.service"
    [[ -f "$svc_file" ]]
    grep -q "User=oracle" "$svc_file"

    # Install with a different user (dry-run to avoid requiring root)
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user datasafe \
        --install --dry-run --yes --no-color

    [ "$status" -eq 0 ]
    # Must warn about the mismatch; no auto-regeneration
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"datasafe"* ]]
    # Service file on disk must still have User=oracle (no auto-regeneration)
    grep -q "User=oracle" "$svc_file"
}

# REG-004: --install --dry-run shows consolidated sudoers plan
# Scenario: --prepare runs; --install --dry-run must show the oradba-datasafe
#           sudoers path and the would-be content (no legacy-file warning).
@test "REG-004: install dry-run shows consolidated sudoers plan" {
    # Prepare (creates service file in CONNECTOR_ETC; no local sudoers staged)
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --prepare --yes --no-color

    [ "$status" -eq 0 ]

    # --install --dry-run must show consolidated sudoers path and content
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --install --dry-run --yes --no-color

    [ "$status" -eq 0 ]
    [[ "$output" == *"oradba-datasafe"* ]]
    [[ "$output" == *"ORADBA_DATASAFE_CTL"* ]]
}

# REG-005: --install warns when ExecStart binary does not exist
# Scenario: service file is hand-crafted with ExecStart pointing to a nonexistent
#           path; --install --dry-run must emit "ExecStart binary not found".
@test "REG-005: install warns when ExecStart binary is missing" {
    # Prepare to get a valid service file scaffolding, then override ExecStart
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --prepare --yes --no-color

    [ "$status" -eq 0 ]

    local svc_file="$CONNECTOR_BASE/$TEST_CONNECTOR/etc/systemd/oracle_datasafe_${TEST_CONNECTOR}.service"
    [[ -f "$svc_file" ]]

    # Replace ExecStart with a path to a nonexistent binary
    perl -pi -e 's|^ExecStart=.*|ExecStart=/nonexistent/path/to/binary start|' "$svc_file"

    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --install --dry-run --yes --no-color

    [ "$status" -eq 0 ]
    [[ "$output" == *"ExecStart binary not found"* ]] || [[ "$output" == *"not found"* ]]
}

# REG-006: --install creates connector log directory when absent
@test "REG-006: install creates missing connector log directory" {
    # Prepare to get service files in place
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --prepare --yes --no-color

    [ "$status" -eq 0 ]

    # Remove the log directory so the installer must create it
    rm -rf "$CONNECTOR_BASE/$TEST_CONNECTOR/log"

    # dry-run: currently the log-dir creation message does NOT appear because
    # install_service() returns before that code when DRY_RUN=true.
    # This assertion will fail until M3 moves it into the plan section.
    run "$SCRIPT_PATH" \
        --base "$CONNECTOR_BASE" \
        --connector "$TEST_CONNECTOR" \
        --java-home "$JAVA_HOME" \
        --user oracle \
        --install --dry-run --yes --no-color

    [ "$status" -eq 0 ]
    [[ "$output" == *"Creating connector log directory"* ]]
}
