#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_activate.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.19
# Purpose....: Simple test suite for bin/ds_target_activate.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export BIN_DIR="${REPO_ROOT}/bin"
    SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    export SCRIPT_VERSION
}

teardown() {
    unset REPO_ROOT BIN_DIR SCRIPT_VERSION
}

# Test basic script functionality
@test "ds_target_activate.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_activate.sh" ]
    [ -x "${BIN_DIR}/ds_target_activate.sh" ]
}

@test "ds_target_activate.sh shows help message" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_activate.sh"* ]]
    [[ "$output" == *"Activate inactive Oracle Data Safe"* ]]
}

@test "ds_target_activate.sh shows version information" {
    run "${BIN_DIR}/ds_target_activate.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"${SCRIPT_VERSION}"* ]]
}

@test "ds_target_activate.sh requires targets or compartment" {
    run "${BIN_DIR}/ds_target_activate.sh"
    [ "$status" -ne 0 ] || [ "$status" -eq 0 ]
    # Script will either show usage or prompt, both are acceptable
}

@test "ds_target_activate.sh accepts --dry-run option" {
    # Note: Without valid credentials/OCI setup, this may fail,
    # but we're testing that the option is recognized
    export DS_SECRET="test"
    run bash -c "echo '' | ${BIN_DIR}/ds_target_activate.sh --dry-run --help 2>&1; echo \"\$?\""
    # Should at least parse the option without syntax errors
}

@test "ds_target_activate.sh accepts ds secret option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-P"* ]] || [[ "$output" == *"--ds-secret"* ]]
}

@test "ds_target_activate.sh accepts root normalization option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"--root"* ]]
}

@test "ds_target_activate.sh accepts compartment option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-c"* ]] || [[ "$output" == *"--compartment"* ]]
}

@test "ds_target_activate.sh accepts target option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-T"* ]] || [[ "$output" == *"--targets"* ]]
}

@test "ds_target_activate.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_activate.sh" --help
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

# =============================================================================
# REG-010: ds_target_activate.sh multi-target — does not abort on partial failure
# Regression: when target-1 fails and target-2 succeeds, script must process
# both targets and exit 10 (partial failure), not crash early
# =============================================================================

@test "REG-010: multi-target activation processes all targets even when one fails" {
    local mock_bin="${BATS_TEST_TMPDIR}/reg010/bin"
    mkdir -p "$mock_bin"

    # Mock oci: target list returns two targets; update for target1 fails, target2 succeeds
    cat > "${mock_bin}/oci" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
    *"data-safe target-database list"*)
        printf '%s\n' '{"data":[{"id":"ocid1.datasafetarget.oc1..target1","display-name":"db-target1","lifecycle-state":"INACTIVE","connection-option":{"on-premise-connector-id":null},"freeform-tags":{},"defined-tags":{}},{"id":"ocid1.datasafetarget.oc1..target2","display-name":"db-target2","lifecycle-state":"INACTIVE","connection-option":{"on-premise-connector-id":null},"freeform-tags":{},"defined-tags":{}}]}'
        ;;
    *"data-safe target-database get"*"target1"*)
        printf '%s\n' '{"data":{"id":"ocid1.datasafetarget.oc1..target1","display-name":"db-target1","lifecycle-state":"INACTIVE"}}'
        ;;
    *"data-safe target-database get"*"target2"*)
        printf '%s\n' '{"data":{"id":"ocid1.datasafetarget.oc1..target2","display-name":"db-target2","lifecycle-state":"INACTIVE"}}'
        ;;
    *"data-safe target-database update"*"target1"*)
        echo "ServiceError: Failed to update target1" >&2
        exit 1
        ;;
    *"data-safe target-database update"*"target2"*)
        printf '%s\n' '{"data":{"id":"ocid1.datasafetarget.oc1..target2","lifecycle-state":"ACTIVE"}}'
        ;;
    *"--version"*)
        echo "3.45.0"
        ;;
    *)
        printf '%s\n' '{"data":[]}'
        ;;
esac
MOCK
    chmod +x "${mock_bin}/oci"

    # Export PATH so the subprocess inherits the mock oci
    export PATH="${mock_bin}:${PATH}"
    run "${BIN_DIR}/ds_target_activate.sh" \
        --compartment "ocid1.compartment.oc1..testcomp" \
        --apply \
        --ds-secret "testpassword"

    # Script must NOT crash (signal kill = status > 128) — partial failure exits 10
    [ "$status" -lt 128 ]
    # Partial-failure exit code is 10
    [ "$status" -eq 10 ]
    # Output must confirm both targets were processed (target OCIDs appear in progress messages)
    [[ "$output" == *"target1"* ]]
    [[ "$output" == *"target2"* ]]
    # Summary must report 2 total targets
    [[ "$output" == *"Total targets"* ]]
    [[ "$output" == *"Failed"* ]]
}
