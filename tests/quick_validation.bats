#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland  
# ------------------------------------------------------------------------------
# Test Suite.: quick_validation.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Quick validation tests to ensure basic framework functionality
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
}

# Basic script validation
@test "framework has all required scripts" {
    [ -x "${BIN_DIR}/ds_target_list.sh" ]
    [ -x "${BIN_DIR}/ds_target_refresh.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_tags.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_credentials.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_connector.sh" ]
    [ -x "${BIN_DIR}/ds_target_update_service.sh" ]
    [ -x "${BIN_DIR}/ds_tg_report.sh" ]
}

@test "framework has required libraries" {
    [ -f "${LIB_DIR}/common.sh" ]
    [ -f "${LIB_DIR}/oci_helpers.sh" ]
    [ -f "${LIB_DIR}/ds_lib.sh" ]
}

@test "all scripts are syntactically correct" {
    for script in "${BIN_DIR}"/*.sh; do
        run bash -n "$script"
        [ "$status" -eq 0 ]
    done
}

@test "all libraries are syntactically correct" {
    for lib in "${LIB_DIR}"/*.sh; do
        run bash -n "$lib"
        [ "$status" -eq 0 ]
    done
}

@test "scripts show help without crashing" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    
    run "${BIN_DIR}/ds_target_update_tags.sh" --help  
    [ "$status" -eq 0 ]
    
    run "${BIN_DIR}/ds_target_update_credentials.sh" --help
    [ "$status" -eq 0 ]
}

@test "scripts show version correctly" {
    run "${BIN_DIR}/ds_target_list.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SCRIPT_VERSION}"* ]]
}

@test "libraries can be sourced without errors" {
    run bash -c "source '${LIB_DIR}/common.sh'"
    [ "$status" -eq 0 ]
    
    run bash -c "source '${LIB_DIR}/common.sh' && source '${LIB_DIR}/oci_helpers.sh'"
    [ "$status" -eq 0 ]
    
    run bash -c "source '${LIB_DIR}/ds_lib.sh'"
    [ "$status" -eq 0 ]
}

@test "basic logging functions work" {
    run bash -c "source '${LIB_DIR}/ds_lib.sh' && log_info 'test message'"
    [ "$status" -eq 0 ]
}

@test "OCID validation works" {
    run bash -c "source '${LIB_DIR}/ds_lib.sh' && is_ocid 'ocid1.compartment.oc1..test'"
    [ "$status" -eq 0 ]
    
    run bash -c "source '${LIB_DIR}/ds_lib.sh' && is_ocid 'invalid'"
    [ "$status" -eq 1 ]
}

@test "error handling is configured" {
    run bash -c "source '${LIB_DIR}/ds_lib.sh' && setup_error_handling"
    [ "$status" -eq 0 ]
}