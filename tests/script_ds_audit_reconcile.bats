#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"

    # Isolate the target list cache and disable it so each test sees the mock
    export TMPDIR="${BATS_TEST_TMPDIR}"
    export DS_TARGET_CACHE_TTL=0
    export OCI_CLI_PROFILE=""
    export OCI_CLI_REGION=""
    export OCI_CLI_CONFIG_FILE=""

    export COMP_OCID="ocid1.compartment.oc1..prod"
    export CALL_LOG="${BATS_TEST_TMPDIR}/oci_calls.log"
    export TARGETS_FILE="${BATS_TEST_TMPDIR}/targets.json"
    export TRAILS_FILE="${BATS_TEST_TMPDIR}/trails.json"
    export PROFILES_FILE="${BATS_TEST_TMPDIR}/profiles.json"

    cat > "${TARGETS_FILE}" <<'JSON'
{"data":[
 {"id":"ocid1.datasafetargetdatabase.oc1..p1","display-name":"PRODDB01_PDB1",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..prod",
  "defined-tags":{"DBSec":{"Environment":"prod","ContainerStage":"pdb-prod"}}},
 {"id":"ocid1.datasafetargetdatabase.oc1..p2","display-name":"PRODDB01_CDBROOT",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..prod",
  "defined-tags":{"DBSec":{"ContainerStage":"cdbroot-prod"}}},
 {"id":"ocid1.datasafetargetdatabase.oc1..p3","display-name":"PRODDB02_PDB9",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..prod",
  "defined-tags":{}},
 {"id":"ocid1.datasafetargetdatabase.oc1..p4","display-name":"PRODDB03_PDB1",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..prod",
  "defined-tags":{"DBSec":{"ContainerStage":"pdb-prod"}}},
 {"id":"ocid1.datasafetargetdatabase.oc1..q1","display-name":"QSDB01_PDB1",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..prod",
  "defined-tags":{"DBSec":{"Environment":"qs","ContainerStage":"pdb-qs"}}}
]}
JSON

    cat > "${TRAILS_FILE}" <<'JSON'
{"data":{"items":[
 {"id":"ocid1.audittrail.oc1..a1","target-id":"ocid1.datasafetargetdatabase.oc1..p1",
  "lifecycle-state":"ACTIVE","status":"COLLECTING","is-auto-purge-enabled":true},
 {"id":"ocid1.audittrail.oc1..a2","target-id":"ocid1.datasafetargetdatabase.oc1..p2",
  "lifecycle-state":"ACTIVE","status":"NOT_STARTED","is-auto-purge-enabled":false},
 {"id":"ocid1.audittrail.oc1..a4","target-id":"ocid1.datasafetargetdatabase.oc1..p4",
  "lifecycle-state":"ACTIVE","status":"NOT_STARTED","is-auto-purge-enabled":false},
 {"id":"ocid1.audittrail.oc1..a5","target-id":"ocid1.datasafetargetdatabase.oc1..q1",
  "lifecycle-state":"NEEDS_ATTENTION","status":"STOPPED_NEEDS_ATTN","is-auto-purge-enabled":true}
]}}
JSON

    cat > "${PROFILES_FILE}" <<'JSON'
{"data":{"items":[
 {"id":"ocid1.datasafeauditprofile.oc1..f1","target-id":"ocid1.datasafetargetdatabase.oc1..p1","audit-collected-volume":100},
 {"id":"ocid1.datasafeauditprofile.oc1..f2","target-id":"ocid1.datasafetargetdatabase.oc1..p2","audit-collected-volume":0},
 {"id":"ocid1.datasafeauditprofile.oc1..f3","target-id":"ocid1.datasafetargetdatabase.oc1..p3","audit-collected-volume":0},
 {"id":"ocid1.datasafeauditprofile.oc1..f4","target-id":"ocid1.datasafetargetdatabase.oc1..p4","audit-collected-volume":0},
 {"id":"ocid1.datasafeauditprofile.oc1..f5","target-id":"ocid1.datasafetargetdatabase.oc1..q1","audit-collected-volume":50}
]}}
JSON

    install_oci_mock
}

# Install a mock OCI CLI that serves the fixtures above and logs every call.
install_oci_mock() {
    cat > "${TEST_BIN_DIR}/oci" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CALL_LOG}"

case "$*" in
    *--version*)
        echo "3.0.0"; exit 0 ;;
    *"data-safe target-database list"*)
        cat "${TARGETS_FILE}"; exit 0 ;;
    *"data-safe audit-trail list"*)
        # Honour --target-id like the real CLI does, otherwise a per-target
        # lookup would see every trail in the compartment.
        tid=""
        prev=""
        for arg in "$@"; do
            [[ "$prev" == "--target-id" ]] && tid="$arg"
            prev="$arg"
        done
        if [[ -n "$tid" ]]; then
            jq -c --arg id "$tid" \
                '{data:{items: [.data.items[] | select(.["target-id"] == $id)]}}' "${TRAILS_FILE}"
        else
            cat "${TRAILS_FILE}"
        fi
        exit 0 ;;
    *"data-safe audit-profile list"*)
        cat "${PROFILES_FILE}"; exit 0 ;;
    *"data-safe audit-profile discover-audit-trails"*)
        printf '{"data":{"status":"ACCEPTED"}}\n'; exit 0 ;;
    *"data-safe target-database get"*)
        for arg in "$@"; do
            case "$prev" in --target-database-id) tid="$arg" ;; esac
            prev="$arg"
        done
        jq -c --arg id "$tid" '{data: (.data[] | select(.id == $id))}' "${TARGETS_FILE}"
        exit 0 ;;
    *"data-safe target-database update"*)
        printf '{"data":{"lifecycle-state":"ACTIVE"}}\n'; exit 0 ;;
    *"data-safe audit-trail start"*)
        printf '{"data":{"status":"STARTING"}}\n'; exit 0 ;;
    *"data-safe audit-trail get"*)
        printf '{"data":{"lifecycle-state":"ACTIVE","status":"STARTING"}}\n'; exit 0 ;;
    *"iam compartment list"*)
        printf '"ocid1.compartment.oc1..prod"\n'; exit 0 ;;
esac
printf '{"data":[]}\n'
exit 0
MOCK
    chmod +x "${TEST_BIN_DIR}/oci"
}

reconcile() {
    "${BIN_DIR}/ds_audit_reconcile.sh" --compartment-id "${COMP_OCID}" "$@" 2> /dev/null
}

# ---------------------------------------------------------------------------
# Help / usage
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh --help exits 0 and documents the required options" {
    run "${BIN_DIR}/ds_audit_reconcile.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--compartment-id OCID"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"--skip-tagging"* ]]
    [[ "$output" == *"--skip-trails"* ]]
    [[ "$output" == *"--limit N"* ]]
    [[ "$output" == *"--target-filter REGEX"* ]]
    [[ "$output" == *"--report-file FILE"* ]]
}

@test "ds_audit_reconcile.sh without arguments shows the usage" {
    run "${BIN_DIR}/ds_audit_reconcile.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh rejects --dry-run together with --apply" {
    run reconcile --dry-run --apply
    [ "$status" -ne 0 ]
}

@test "ds_audit_reconcile.sh rejects a non-numeric --limit" {
    run reconcile --limit abc
    [ "$status" -ne 0 ]
}

@test "ds_audit_reconcile.sh rejects an invalid --auto-purge value" {
    run reconcile --auto-purge maybe
    [ "$status" -ne 0 ]
}

@test "ds_audit_reconcile.sh rejects an invalid --target-filter regex" {
    run reconcile --target-filter '[invalid'
    [ "$status" -ne 0 ]
}

@test "ds_audit_reconcile.sh refuses --apply from a target snapshot" {
    run "${BIN_DIR}/ds_audit_reconcile.sh" --input-json "${TARGETS_FILE}" \
        --trails-json "${TRAILS_FILE}" --profiles-json "${PROFILES_FILE}" --apply
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Dry-run is the default
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh defaults to dry-run and writes nothing" {
    run reconcile
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN (no changes made)"* ]]
    [[ "$output" == *"Dry-run: nothing was changed"* ]]
    run grep -c -e "target-database update" -e "audit-trail start" -e "discover-audit-trails" "${CALL_LOG}"
    [ "$output" = "0" ]
}

@test "ds_audit_reconcile.sh classifies every target exactly once" {
    run reconcile
    [ "$status" -eq 0 ]
    [[ "$output" == *"Targets in scope: 5"* ]]
    [[ "$output" == *"Tagged and collecting: 1"* ]]
    [[ "$output" == *"Missing DBSec.ContainerStage: 1"* ]]
    [[ "$output" == *"Targets without a trail object: 1"* ]]
    [[ "$output" == *"Trails NOT_STARTED: 2"* ]]
    [[ "$output" == *"Trails NEEDS_ATTENTION: 1"* ]]
}

@test "ds_audit_reconcile.sh names the untagged target in the report" {
    run reconcile
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRODDB02_PDB9"* ]]
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh --apply tags, discovers and starts" {
    run reconcile --apply --env-regex '^ocid1\.compartment\.oc1\.\.(prod)$'
    [ "$status" -eq 0 ]
    grep -q "target-database update" "${CALL_LOG}"
    grep -q "discover-audit-trails" "${CALL_LOG}"
    grep -q "audit-trail start" "${CALL_LOG}"
}

@test "ds_audit_reconcile.sh --apply never starts a trail without auto-purge" {
    run reconcile --apply
    [ "$status" -eq 0 ]
    run grep -c -- "--is-auto-purge-enabled true" "${CALL_LOG}"
    [ "$output" -ge 1 ]
    run grep -c -- "--is-auto-purge-enabled false" "${CALL_LOG}"
    [ "$output" = "0" ]
}

@test "ds_audit_reconcile.sh --apply never backdates the collection start" {
    run reconcile --apply
    [ "$status" -eq 0 ]
    grep -q -- "--audit-collection-start-time" "${CALL_LOG}"
    # The start time must be today, not a historic timestamp
    today=$(date -u +%Y-%m-%d)
    grep -q -- "--audit-collection-start-time ${today}T" "${CALL_LOG}"
}

@test "ds_audit_reconcile.sh --apply never touches a NEEDS_ATTENTION trail" {
    run reconcile --apply
    [ "$status" -eq 0 ]
    run grep -c "ocid1.audittrail.oc1..a5" "${CALL_LOG}"
    [ "$output" = "0" ]
}

@test "ds_audit_reconcile.sh --apply is idempotent for an already correct target" {
    run reconcile --apply
    [ "$status" -eq 0 ]
    # PRODDB01_PDB1 is tagged and COLLECTING: no write must reference its trail
    run grep -c "ocid1.audittrail.oc1..a1" "${CALL_LOG}"
    [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# Limit
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh --limit caps the number of changes and defers the rest" {
    run reconcile --limit 1
    [ "$status" -eq 0 ]
    # Budget of 1 goes to the tagging step, everything else is deferred
    [[ "$output" == *"Deferred to the next run: 3"* ]]
}

@test "ds_audit_reconcile.sh --limit 0 means unlimited" {
    run reconcile --limit 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Limit: unlimited"* ]]
    [[ "$output" == *"Deferred to the next run: 0"* ]]
}

@test "ds_audit_reconcile.sh --limit consumes the budget in step order" {
    run reconcile --limit 2 --apply
    [ "$status" -eq 0 ]
    # 1 tag update + 1 discovery consume the budget, no trail start happens
    grep -q "target-database update" "${CALL_LOG}"
    grep -q "discover-audit-trails" "${CALL_LOG}"
    run grep -c "audit-trail start" "${CALL_LOG}"
    [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# Skip flags
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh --skip-tagging leaves tags alone" {
    run reconcile --apply --skip-tagging
    [ "$status" -eq 0 ]
    [[ "$output" == *"Step 2 - Tagging (skipped)"* ]]
    run grep -c "target-database update" "${CALL_LOG}"
    [ "$output" = "0" ]
}

@test "ds_audit_reconcile.sh --skip-trails leaves trails alone" {
    run reconcile --apply --skip-trails
    [ "$status" -eq 0 ]
    [[ "$output" == *"Step 4 - Trail start (skipped)"* ]]
    run grep -c -e "audit-trail start" -e "discover-audit-trails" "${CALL_LOG}"
    [ "$output" = "0" ]
}

@test "ds_audit_reconcile.sh --skip-discover still starts existing trails" {
    run reconcile --apply --skip-discover
    [ "$status" -eq 0 ]
    grep -q "audit-trail start" "${CALL_LOG}"
    run grep -c "discover-audit-trails" "${CALL_LOG}"
    [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# Filtering and report file
# ---------------------------------------------------------------------------

@test "ds_audit_reconcile.sh --target-filter narrows the scope" {
    run reconcile --target-filter '^PRODDB01'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Targets in scope: 2"* ]]
}

@test "ds_audit_reconcile.sh --report-file writes the report to disk" {
    local out="${BATS_TEST_TMPDIR}/reconcile.txt"
    run reconcile --report-file "$out"
    [ "$status" -eq 0 ]
    [ -s "$out" ]
    grep -q "Data Safe Audit Reconcile Report" "$out"
}
