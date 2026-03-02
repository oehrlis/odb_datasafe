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
    # Use target OCID directly to avoid name-resolution OCI calls (no DS_ROOT_COMP in tests)
    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"target-database get"* ]] && { printf '{"data":{"id":"ocid1.datasafetargetdatabase.oc1..t1","display-name":"some-target","compartment-id":"ocid1.compartment.oc1..testcomp"}}\n'; exit 0; }
[[ "$*" == *"audit-trail list"* ]] && { printf '{"data":{"items":[]}}\n'; exit 0; }
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_audit_trail.sh" -T ocid1.datasafetargetdatabase.oc1..t1 --filter 'some'
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# --list subcommand
# ---------------------------------------------------------------------------

@test "ds_target_audit_trail.sh --help shows --list, --input-json, --format flags" {
    run "${BIN_DIR}/ds_target_audit_trail.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--list"* ]]
    [[ "$output" == *"--input-json"* ]]
    [[ "$output" == *"--format"* ]]
}

@test "ds_target_audit_trail.sh --list shows (no trail) for target without audit trail" {
    local sample_json="${BATS_TEST_TMPDIR}/targets_no_trail.json"
    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetargetdatabase.oc1..t1","display-name":"prod_cdb01_CDBROOT",
   "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..testcomp"}
]}
JSON

    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"audit-trail list"* ]] && { printf '{"data":{"items":[]}}\n'; exit 0; }
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_audit_trail.sh" --list --input-json "$sample_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no trail"* || "$output" == *"missing"* ]]
}

@test "ds_target_audit_trail.sh --list shows COLLECTING for active audit trail" {
    local sample_json="${BATS_TEST_TMPDIR}/targets_collecting.json"
    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetargetdatabase.oc1..t1","display-name":"prod_cdb01_CDBROOT",
   "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..testcomp"}
]}
JSON

    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"audit-trail list"* ]] && {
    printf '{"data":{"items":[{"id":"ocid1.audittrail.oc1..a1","lifecycle-state":"COLLECTING"}]}}\n'
    exit 0
}
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_audit_trail.sh" --list --input-json "$sample_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"COLLECTING"* ]]
}

@test "ds_target_audit_trail.sh --list --format csv outputs CSV header" {
    local sample_json="${BATS_TEST_TMPDIR}/targets_csv.json"
    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetargetdatabase.oc1..t1","display-name":"prod_cdb01_CDBROOT",
   "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..testcomp"}
]}
JSON

    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--version"* ]] && { echo "3.0.0"; exit 0; }
[[ "$*" == *"audit-trail list"* ]] && { printf '{"data":{"items":[]}}\n'; exit 0; }
printf '{"data":[]}\n'; exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_audit_trail.sh" --list --input-json "$sample_json" -f csv
    [ "$status" -eq 0 ]
    [[ "$output" == *"target,target-id,trail-state,note"* ]]
}
