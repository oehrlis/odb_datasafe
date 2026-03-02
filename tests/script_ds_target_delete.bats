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

@test "ds_target_delete.sh --help exits 0 and shows --filter flag" {
    run "${BIN_DIR}/ds_target_delete.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--filter"* ]]
}

# ---------------------------------------------------------------------------
# Filter regex validation (no OCI mock needed)
# ---------------------------------------------------------------------------

@test "ds_target_delete.sh rejects invalid --filter regex" {
    run "${BIN_DIR}/ds_target_delete.sh" -T some-target --filter '[invalid'
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --stop-on-error shift fix regression
# ---------------------------------------------------------------------------

@test "ds_target_delete.sh --stop-on-error does not consume following argument" {
    # If --stop-on-error was missing its shift, the arg after it would be silently
    # consumed and --dry-run would not be recognised. With the fix in place,
    # --dry-run takes effect and the script exits 0 (no targets → no deletion).
    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"iam compartment list"* ]] && { printf '%s\n' "ocid1.compartment.oc1..testcomp"; exit 0; }
[[ "$*" == *"target-database list"* ]] && { printf '{"data":[]}\n'; exit 0; }
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_delete.sh" -c some-compartment --stop-on-error --dry-run
    # Should reach the dry-run path (no targets found), not misparse --dry-run as a target
    [[ "$output" != *"Unknown option: --dry-run"* ]]
}
