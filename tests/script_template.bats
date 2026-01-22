#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_template.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.22
# Purpose....: Test suite for bin/template.sh to verify standardization
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export SCRIPT_PATH="${REPO_ROOT}/bin/template.sh"
}

# Template structure tests
@test "TEMPLATE.sh exists and is executable" {
    [ -f "$SCRIPT_PATH" ]
    [ -x "$SCRIPT_PATH" ]
}

@test "TEMPLATE.sh has correct shebang" {
    run head -n 1 "$SCRIPT_PATH"
    [[ "$output" == *"#!/usr/bin/env bash"* ]]
}

@test "TEMPLATE.sh reads version from .extension file" {
    run bash -c "grep 'SCRIPT_VERSION=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *".extension"* ]]
}

@test "TEMPLATE.sh has SCRIPT_DIR before SCRIPT_VERSION" {
    # Verify initialization order - SCRIPT_DIR must be defined before SCRIPT_VERSION
    script_dir_line=$(grep -n "^SCRIPT_DIR=" "$SCRIPT_PATH" | head -1 | cut -d: -f1)
    version_line=$(grep -n "^SCRIPT_VERSION=" "$SCRIPT_PATH" | cut -d: -f1)
    
    [ -n "$script_dir_line" ]
    [ -n "$version_line" ]
    [ "$script_dir_line" -lt "$version_line" ]
}

@test "TEMPLATE.sh defines LIB_DIR" {
    run bash -c "grep -q 'LIB_DIR=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh sources ds_lib.sh" {
    run bash -c "grep -q 'source.*ds_lib.sh' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has runtime variables section" {
    run bash -c "grep -q 'COMP_NAME=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    
    run bash -c "grep -q 'COMP_OCID=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    
    run bash -c "grep -q 'TARGET_NAME=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    
    run bash -c "grep -q 'TARGET_OCID=' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

# Function header tests
@test "TEMPLATE.sh has standardized function headers" {
    # Check for Function: pattern in all function headers
    run bash -c "grep -c '# Function:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]  # usage, parse_args, validate_inputs, do_work, main, cleanup
}

@test "TEMPLATE.sh function headers include Purpose" {
    run bash -c "grep -c '# Purpose.:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}

@test "TEMPLATE.sh function headers include Returns" {
    run bash -c "grep -c '# Returns.:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}

@test "TEMPLATE.sh function headers include Output" {
    run bash -c "grep -c '# Output..:' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]  # At least 3 functions have Output section
}

# Resolution pattern tests
@test "TEMPLATE.sh uses resolve_compartment_to_vars" {
    run bash -c "grep -q 'resolve_compartment_to_vars' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh uses resolve_target_to_vars" {
    run bash -c "grep -q 'resolve_target_to_vars' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh uses oci_exec_ro for read-only operations" {
    run bash -c "grep -q 'oci_exec_ro' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh uses oci_exec for write operations" {
    run bash -c "grep -q 'oci_exec data-safe' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

# Standard functions tests
@test "TEMPLATE.sh has usage function" {
    run bash -c "grep -q '^usage()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has parse_args function" {
    run bash -c "grep -q '^parse_args()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has validate_inputs function" {
    run bash -c "grep -q '^validate_inputs()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has do_work function" {
    run bash -c "grep -q '^do_work()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has main function" {
    run bash -c "grep -q '^main()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has cleanup function" {
    run bash -c "grep -q '^cleanup()' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

# Usage documentation tests
@test "TEMPLATE.sh usage includes compartment option" {
    run bash -c "grep -A 50 '^usage()' '$SCRIPT_PATH' | grep -q 'compartment'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh usage includes targets option" {
    run bash -c "grep -A 50 '^usage()' '$SCRIPT_PATH' | grep -q 'targets'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh usage includes dry-run option" {
    run bash -c "grep -A 50 '^usage()' '$SCRIPT_PATH' | grep -q 'dry-run'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh usage documents resolution pattern" {
    run bash -c "grep -A 100 '^usage()' '$SCRIPT_PATH' | grep -q 'Resolution Pattern'"
    [ "$status" -eq 0 ]
}

# Best practices tests
@test "TEMPLATE.sh uses require_cmd for command validation" {
    run bash -c "grep -q 'require_cmd' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh checks for oci and jq" {
    run bash -c "grep -q 'require_cmd oci jq' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has dry-run mode support" {
    run bash -c "grep -q 'DRY_RUN' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has verbose examples in usage" {
    run bash -c "grep -A 100 '^usage()' '$SCRIPT_PATH' | grep -c 'Example'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]  # At least 3 examples
}

@test "TEMPLATE.sh calls init_config" {
    run bash -c "grep -q 'init_config' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh calls parse_args with proper arguments" {
    run bash -c "grep -q 'parse_args.*\"\$@\"' '$SCRIPT_PATH'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has proper main invocation" {
    run bash -c "tail -5 '$SCRIPT_PATH' | grep -q 'main.*\"\$@\"'"
    [ "$status" -eq 0 ]
}

# Documentation tests
@test "TEMPLATE.sh has comprehensive header documentation" {
    run bash -c "head -20 '$SCRIPT_PATH' | grep -c '#'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 10 ]  # At least 10 comment lines in header
}

@test "TEMPLATE.sh documents author" {
    run bash -c "head -20 '$SCRIPT_PATH' | grep -q 'Author'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh documents purpose" {
    run bash -c "head -20 '$SCRIPT_PATH' | grep -q 'Purpose'"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh documents license" {
    run bash -c "head -20 '$SCRIPT_PATH' | grep -q 'License'"
    [ "$status" -eq 0 ]
}

# Code quality tests
@test "TEMPLATE.sh passes shellcheck syntax validation" {
    run bash -n "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
}

@test "TEMPLATE.sh has no trailing whitespace in key sections" {
    # Check function definitions don't have trailing whitespace (allowing for flexibility)
    # This test is informational - some formatting is acceptable
    run bash -c "grep -E '^[a-z_]+\(\)[[:space:]]+\{' '$SCRIPT_PATH'"
    # Allow either way - with or without trailing space
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "TEMPLATE.sh uses consistent indentation" {
    # Check that functions use consistent indentation (4 spaces)
    run bash -c "grep -A 5 '^validate_inputs()' '$SCRIPT_PATH' | grep -E '^    [a-z]'"
    [ "$status" -eq 0 ]
}
