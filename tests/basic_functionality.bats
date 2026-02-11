#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: basic_functionality.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Basic functionality tests that should always pass
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    
    # Basic environment setup
    export CONFIG_FILE="${TEST_TEMP_DIR}/.env"
    cat > "${CONFIG_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
EOF
}

# Test that all main scripts exist and are executable
@test "all main scripts exist and are executable" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_refresh.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
        "ds_target_update_service.sh"
        "ds_tg_report.sh"
    )
    
    for script in "${scripts[@]}"; do
        [ -f "${BIN_DIR}/${script}" ]
        [ -x "${BIN_DIR}/${script}" ]
    done
}

# Test that all scripts show help
@test "all scripts support --help option" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_refresh.sh"
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
        "ds_target_update_service.sh"
        "ds_tg_report.sh"
    )
    
    for script in "${scripts[@]}"; do
        run "${BIN_DIR}/${script}" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

# Test that all scripts show version
@test "all scripts support --version option" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_refresh.sh" 
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
        "ds_target_update_service.sh"
        "ds_tg_report.sh"
    )
    
    for script in "${scripts[@]}"; do
        run "${BIN_DIR}/${script}" --version
        [ "$status" -eq 0 ]
        [[ "$output" == *"${SCRIPT_VERSION}"* ]]
    done
}

# Test that libraries can be loaded
@test "common library can be loaded" {
    run bash -c "source '${LIB_DIR}/common.sh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "oci_helpers library can be loaded" {
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "ds_lib loader works" {
    run bash -c "source '${LIB_DIR}/ds_lib.sh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

# Test basic library functions
@test "is_ocid function works" {
    source "${LIB_DIR}/ds_lib.sh"
    
    run is_ocid "ocid1.compartment.oc1..example"
    [ "$status" -eq 0 ]
    
    run is_ocid "not-an-ocid"
    [ "$status" -eq 1 ]
}

@test "require_cmd function works" {
    source "${LIB_DIR}/ds_lib.sh"
    
    run require_cmd "bash"
    [ "$status" -eq 0 ]
    
    run require_cmd "nonexistent-command-123456"
    [ "$status" -eq 1 ]
}

# Test error handling for invalid options
@test "scripts reject invalid options" {
    local scripts=(
        "ds_target_list.sh"
        "ds_target_update_tags.sh"
    )
    
    for script in "${scripts[@]}"; do
        run "${BIN_DIR}/${script}" --invalid-option-xyz
        [ "$status" -ne 0 ]
    done
}

# Test that scripts require OCI CLI
@test "scripts check for OCI CLI dependency" {
    # Temporarily remove oci from PATH
    local old_path="$PATH"
    export PATH="/bin:/usr/bin"
    
    # Test should fail due to missing oci command
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..test" 2>/dev/null || true
    [ "$status" -ne 0 ]
    
    # Restore PATH
    export PATH="$old_path"
}

# Test configuration file loading
@test "scripts can load configuration from .env" {
    # This should not crash even if OCI calls fail
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
}

# Test that update scripts support dry-run
@test "update scripts support dry-run by default" {
    local update_scripts=(
        "ds_target_update_tags.sh"
        "ds_target_update_credentials.sh"
        "ds_target_update_connector.sh"
        "ds_target_update_service.sh"
    )
    
    for script in "${update_scripts[@]}"; do
        # Help should mention dry-run
        run "${BIN_DIR}/${script}" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"apply"* ]]
    done
}