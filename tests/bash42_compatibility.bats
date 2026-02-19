#!/usr/bin/env bats
# Test bash 4.2 compatibility issues

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export LIB_DIR="${REPO_ROOT}/lib"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "No local -n nameref usage in scripts (bash 4.2 incompatible)" {
    # Search for local -n usage which requires bash 4.3+
    run bash -c "grep -rn 'local -n' --include='*.sh' '${REPO_ROOT}/bin' '${REPO_ROOT}/lib' 2>/dev/null"
    [ "$status" -eq 1 ]  # grep should return 1 when no matches found
}

@test "Array expansions are safe with nounset in oci_helpers.sh" {
    # Test that the ds_list_targets function can be sourced without error
    # Even with strict mode enabled
    run bash -euo pipefail -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/oci_helpers.sh'
        # Function should be defined
        declare -F ds_list_targets > /dev/null
    "
    [ "$status" -eq 0 ]
}

@test "dedupe_array function works without nameref" {
    # Test the dedupe_array function extracted from ds_version.sh
    run bash -c "
        cd '${REPO_ROOT}'
        # Extract just the dedupe_array function
        func=\$(sed -n '/^dedupe_array()/,/^}/p' bin/ds_version.sh)
        eval \"\$func\"
        
        # Test deduplication
        declare -a test_array=('a' 'b' 'a' 'c' 'b' 'd')
        dedupe_array test_array
        
        # Should have 4 unique elements
        echo \${#test_array[@]}
    "
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "dedupe_array preserves order" {
    # Test that dedupe_array preserves first occurrence order
    run bash -c "
        cd '${REPO_ROOT}'
        # Extract just the dedupe_array function
        func=\$(sed -n '/^dedupe_array()/,/^}/p' bin/ds_version.sh)
        eval \"\$func\"
        
        declare -a test_array=('first' 'second' 'first' 'third')
        dedupe_array test_array
        
        # Output should be: first second third
        printf '%s\n' \"\${test_array[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "first" ]]
    [[ "${lines[1]}" == "second" ]]
    [[ "${lines[2]}" == "third" ]]
    [ "${#lines[@]}" -eq 3 ]
}

@test "Empty array handling in dedupe_array" {
    # Test that dedupe_array handles empty arrays
    run bash -c "
        cd '${REPO_ROOT}'
        # Extract just the dedupe_array function
        func=\$(sed -n '/^dedupe_array()/,/^}/p' bin/ds_version.sh)
        eval \"\$func\"
        
        declare -a test_array=()
        dedupe_array test_array
        
        echo \${#test_array[@]}
    "
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "Array with empty strings in dedupe_array" {
    # Test that dedupe_array skips empty strings
    run bash -c "
        cd '${REPO_ROOT}'
        # Extract just the dedupe_array function
        func=\$(sed -n '/^dedupe_array()/,/^}/p' bin/ds_version.sh)
        eval \"\$func\"
        
        declare -a test_array=('a' '' 'b' '' 'a')
        dedupe_array test_array
        
        # Should have 2 unique non-empty elements
        echo \${#test_array[@]}
    "
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "oci_helpers.sh has safe array expansions with nounset" {
    # Test that array expansions in oci_helpers.sh are safe with set -u
    # by checking the syntax patterns used
    run bash -c "
        cd '${REPO_ROOT}'
        # Check that lifecycle_opts expansion uses safe pattern
        grep '_ds_get_target_list_cached' lib/oci_helpers.sh | grep -q '\${lifecycle_opts\[@\]+' && echo 'SAFE_EXPANSION' || true
        # Check that array length check uses safe pattern (either [*]+ or [@]+)
        grep -A 2 'if \[\[.*lifecycle_opts' lib/oci_helpers.sh | grep -qE '\[\*\]\+|\[@\]\+' && echo 'SAFE_LENGTH' || true
        echo 'DONE'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"SAFE_EXPANSION"* ]]
    [[ "$output" == *"SAFE_LENGTH"* ]]
}

@test "ds_version.sh dedupe_array is bash 4.2 compatible (no nameref)" {
    # Test that dedupe_array function uses eval instead of nameref
    run bash -c "
        cd '${REPO_ROOT}'
        # Check the function definition doesn't use 'local -n'
        grep -A 30 '^dedupe_array()' bin/ds_version.sh | grep -q 'local -n' && exit 1
        # Check it uses eval instead
        grep -A 30 '^dedupe_array()' bin/ds_version.sh | grep -q 'eval' || exit 1
        echo 'OK'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}
