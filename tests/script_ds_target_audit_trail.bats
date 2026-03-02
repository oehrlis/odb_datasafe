#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
}

# ---------------------------------------------------------------------------
# Help / usage
# ---------------------------------------------------------------------------

@test "ds_target_audit_trail.sh --help exits 0 and shows scope flags" {
    run "${BIN_DIR}/ds_target_audit_trail.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
    [[ "$output" == *"--filter"* ]]
}

# ---------------------------------------------------------------------------
# Mutually-exclusive flag validation (no OCI mock needed)
# ---------------------------------------------------------------------------

@test "ds_target_audit_trail.sh --all and -c are mutually exclusive" {
    run "${BIN_DIR}/ds_target_audit_trail.sh" --all -c some-compartment
    [ "$status" -ne 0 ]
}

@test "ds_target_audit_trail.sh --all and -T are mutually exclusive" {
    run "${BIN_DIR}/ds_target_audit_trail.sh" --all -T some-target
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Filter regex validation (no OCI mock needed)
# ---------------------------------------------------------------------------

@test "ds_target_audit_trail.sh rejects invalid --filter regex" {
    run "${BIN_DIR}/ds_target_audit_trail.sh" -T some-target --filter '[invalid'
    [ "$status" -ne 0 ]
}

@test "ds_target_audit_trail.sh accepts valid --filter regex with -T" {
    # Mock OCI: auth check passes; target-database get returns name; audit-trail list returns empty
    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"iam compartment list"* ]] && { printf '%s\n' "ocid1.compartment.oc1..testcomp"; exit 0; }
[[ "$*" == *"target-database get"* ]] && { printf '{"data":{"display-name":"test-target","compartment-id":"ocid1.compartment.oc1..testcomp"}}\n'; exit 0; }
[[ "$*" == *"target-database list"* ]] && { printf '{"data":[{"id":"ocid1.datasafetargetdatabase.oc1..t1","display-name":"test-target","lifecycle-state":"ACTIVE"}]}\n'; exit 0; }
[[ "$*" == *"audit-trail list"* ]] && { printf '{"data":{"items":[]}}\n'; exit 0; }
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_audit_trail.sh" -T some-target --filter 'some' --dry-run
    [ "$status" -eq 0 ]
}
