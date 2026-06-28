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

@test "uninstall_all_datasafe_services.sh list mode works without root" {
    run "$SCRIPT_PATH" --list

    # Script always exits 0 in list mode — when no services found,
    # list_services returns 1 but main() calls exit 0 on that path
    [ "$status" -eq 0 ]
}

@test "uninstall_all_datasafe_services.sh default mode is list (no root needed)" {
    run "$SCRIPT_PATH"

    # Default behavior is list mode; script exits 0 regardless of service count
    [ "$status" -eq 0 ]
    [[ "$output" != *"requires root"* ]]
}

@test "uninstall_all_datasafe_services.sh dry-run mode works without root" {
    run "$SCRIPT_PATH" --list --dry-run

    # List + dry-run: script exits 0 (same exit-0 path as plain --list)
    [ "$status" -eq 0 ]
}

@test "uninstall_all_datasafe_services.sh handles no services gracefully" {
    run "$SCRIPT_PATH" --list
    
    # Script should handle no services without error
    [[ "$output" == *"No"* ]] || [[ "$output" == *"found"* ]] || [ "$status" -eq 0 ]
}
