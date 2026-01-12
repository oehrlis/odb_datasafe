#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# BATS tests for uninstall_all_datasafe_services.sh
# ------------------------------------------------------------------------------

load 'test_helper'

setup() {
    export SCRIPT_PATH="${BATS_TEST_DIRNAME}/../bin/uninstall_all_datasafe_services.sh"
}

@test "uninstall_all_datasafe_services.sh exists and is executable" {
    [[ -x "$SCRIPT_PATH" ]]
}

@test "uninstall_all_datasafe_services.sh shows help" {
    run "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"uninstall_all_datasafe_services.sh"* ]]
}

@test "uninstall_all_datasafe_services.sh supports --no-color flag" {
    run "$SCRIPT_PATH" --no-color --help
    [ "$status" -eq 0 ]
    # Should not contain ANSI color codes
    ! [[ "$output" =~ $'\033' ]]
}

@test "uninstall_all_datasafe_services.sh dry-run mode works without root" {
    run "$SCRIPT_PATH" --dry-run
    
    # Should work without root in dry-run mode
    # May have 0 or 1 exit status depending on whether services are found
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "uninstall_all_datasafe_services.sh handles no services gracefully" {
    run "$SCRIPT_PATH" --dry-run
    
    # Script should handle no services without error
    [[ "$output" == *"No"* ]] || [[ "$output" == *"found"* ]] || [ "$status" -eq 0 ]
}
