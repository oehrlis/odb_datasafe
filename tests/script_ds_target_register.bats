#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_register.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_register.sh" ]
    [ -x "${BIN_DIR}/ds_target_register.sh" ]
}

@test "ds_target_register.sh shows help message" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"--ds-secret"* ]]
    [[ "$output" == *"--secret-file"* ]]
}

@test "ds_target_register.sh defaults to help without arguments" {
    run "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
}

@test "ds_target_register.sh help includes default connector and compartment hints" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"DS_REGISTER_COMPARTMENT"* ]]
    [[ "$output" == *"ONPREM_CONNECTOR_LIST"* ]]
}

@test "ds_target_register.sh help documents host or cluster requirement" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Specify --host or --cluster"* ]] || [[ "$output" == *"required with --host as alternative"* ]]
}

@test "ds_target_register.sh polls ds_list_targets for ACTIVE state after registration" {
    # --wait-for-state mixes OCI CLI progress output into stdout (via 2>&1 in oci_exec),
    # corrupting the JSON result. The script uses a poll loop instead.
    run bash -c "grep -E -- '--wait-for-state' '${BIN_DIR}/ds_target_register.sh' | grep -v '^[[:space:]]*#'"
    [ "$status" -ne 0 ]

    run grep -E 'ds_list_targets|lifecycle-state.*ACTIVE' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses die message before exit code" {
    run grep -E -- 'die "Target registration failed" 2' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh payload includes vmClusterId for cloud-at-customer" {
    run grep -E -- 'vmClusterId' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh resolves pluggableDatabaseId for PDB scope" {
    run grep -E -- 'pluggableDatabaseId|resolve_pluggable_db_ocid' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses single DbNode call for host-based derivation" {
    # HOST block should call oci_resolve_dbnode_by_host (combined compartment+cluster)
    run grep 'oci_resolve_dbnode_by_host' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh delegates compartment/cluster functions to library" {
    # Both local functions should be thin wrappers, not reimplementing OCI calls
    run grep 'oci_resolve_compartment_by_dbnode_name' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]

    run grep 'oci_resolve_vm_cluster_compartment' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}
