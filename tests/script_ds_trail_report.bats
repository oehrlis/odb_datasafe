#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
    export DS_TARGET_CACHE_TTL=0

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
 {"id":"ocid1.datasafetargetdatabase.oc1..q1","display-name":"QSDB01_PDB1",
  "lifecycle-state":"ACTIVE","compartment-id":"ocid1.compartment.oc1..qs",
  "defined-tags":{"DBSec":{"Environment":"qs","ContainerStage":"pdb-qs"}}}
]}
JSON

    cat > "${TRAILS_FILE}" <<'JSON'
{"data":{"items":[
 {"id":"ocid1.audittrail.oc1..a1","target-id":"ocid1.datasafetargetdatabase.oc1..p1",
  "lifecycle-state":"ACTIVE","status":"COLLECTING","is-auto-purge-enabled":true},
 {"id":"ocid1.audittrail.oc1..a2","target-id":"ocid1.datasafetargetdatabase.oc1..p2",
  "lifecycle-state":"ACTIVE","status":"NOT_STARTED","is-auto-purge-enabled":false},
 {"id":"ocid1.audittrail.oc1..a4","target-id":"ocid1.datasafetargetdatabase.oc1..q1",
  "lifecycle-state":"NEEDS_ATTENTION","status":"STOPPED_NEEDS_ATTN","is-auto-purge-enabled":true}
]}}
JSON

    cat > "${PROFILES_FILE}" <<'JSON'
{"data":{"items":[
 {"id":"ocid1.datasafeauditprofile.oc1..f1","target-id":"ocid1.datasafetargetdatabase.oc1..p1",
  "audit-collected-volume":1073741824},
 {"id":"ocid1.datasafeauditprofile.oc1..f2","target-id":"ocid1.datasafetargetdatabase.oc1..p2",
  "audit-collected-volume":0},
 {"id":"ocid1.datasafeauditprofile.oc1..f3","target-id":"ocid1.datasafetargetdatabase.oc1..p3",
  "audit-collected-volume":0},
 {"id":"ocid1.datasafeauditprofile.oc1..f4","target-id":"ocid1.datasafetargetdatabase.oc1..q1",
  "audit-collected-volume":524288000}
]}}
JSON
}

report() {
    "${BIN_DIR}/ds_trail_report.sh" \
        --input-json "${TARGETS_FILE}" \
        --trails-json "${TRAILS_FILE}" \
        --profiles-json "${PROFILES_FILE}" "$@" 2> /dev/null
}

# ---------------------------------------------------------------------------
# Help / usage
# ---------------------------------------------------------------------------

@test "ds_trail_report.sh --help exits 0 and documents the report options" {
    run "${BIN_DIR}/ds_trail_report.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--state STATES"* ]]
    [[ "$output" == *"--summary-only"* ]]
    [[ "$output" == *"--report-file"* ]]
    [[ "$output" == *"NO_TRAIL"* ]]
}

@test "ds_trail_report.sh rejects an invalid --format" {
    run report -f xml
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Trail state derivation
# ---------------------------------------------------------------------------

@test "ds_trail_report.sh reports NOT_STARTED from the status field" {
    run report -f csv --no-summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"PRODDB01_CDBROOT"'*'"NOT_STARTED"'* ]]
}

@test "ds_trail_report.sh reports NEEDS_ATTENTION from the lifecycle-state field" {
    run report -f csv --no-summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"QSDB01_PDB1"'*'"NEEDS_ATTENTION"'* ]]
}

@test "ds_trail_report.sh reports NO_TRAIL for a target without a trail object" {
    run report -f csv --no-summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"PRODDB02_PDB9"'*'"NO_TRAIL"'* ]]
}

@test "ds_trail_report.sh reports auto-purge per target" {
    run report -f json
    [ "$status" -eq 0 ]
    purge=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB01_PDB1") | .["auto-purge"]')
    [ "$purge" = "yes" ]
    purge=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB01_CDBROOT") | .["auto-purge"]')
    [ "$purge" = "no" ]
}

# ---------------------------------------------------------------------------
# Environment and container type derivation
# ---------------------------------------------------------------------------

@test "ds_trail_report.sh derives the environment from ContainerStage when Environment is absent" {
    run report -f json
    [ "$status" -eq 0 ]
    env=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB01_CDBROOT") | .environment')
    [ "$env" = "prod" ]
}

@test "ds_trail_report.sh derives cdbroot from the _CDBROOT name suffix" {
    run report -f json
    [ "$status" -eq 0 ]
    type=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB01_CDBROOT") | .type')
    [ "$type" = "cdbroot" ]
    type=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB01_PDB1") | .type')
    [ "$type" = "pdb" ]
}

@test "ds_trail_report.sh reports an untagged target as environment undef" {
    run report -f json
    [ "$status" -eq 0 ]
    env=$(echo "$output" | jq -r '.rows[] | select(.target=="PRODDB02_PDB9") | .environment')
    [ "$env" = "undef" ]
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

@test "ds_trail_report.sh summarises per environment and adds a TOTAL row" {
    run report -f json
    [ "$status" -eq 0 ]
    total=$(echo "$output" | jq -r '.summary[] | select(.environment=="TOTAL")')
    [ "$(echo "$total" | jq -r '.targets')" = "4" ]
    [ "$(echo "$total" | jq -r '.collecting')" = "1" ]
    [ "$(echo "$total" | jq -r '.not_started')" = "1" ]
    [ "$(echo "$total" | jq -r '.needs_attention')" = "1" ]
    [ "$(echo "$total" | jq -r '.no_trail')" = "1" ]
    [ "$(echo "$total" | jq -r '.["volume-bytes"]')" = "1598029824" ]
}

@test "ds_trail_report.sh --summary-only omits the detail rows" {
    run report --summary-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary by environment"* ]]
    [[ "$output" != *"PRODDB01_PDB1"* ]]
}

@test "ds_trail_report.sh --no-summary omits the summary" {
    run report --no-summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRODDB01_PDB1"* ]]
    [[ "$output" != *"Summary by environment"* ]]
}

# ---------------------------------------------------------------------------
# Filtering and output
# ---------------------------------------------------------------------------

@test "ds_trail_report.sh --state filters to the requested trail states" {
    run report -f json --state NOT_STARTED,NO_TRAIL
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows | length')" = "2" ]
    states=$(echo "$output" | jq -r '[.rows[].["trail-state"]] | sort | join(",")')
    [ "$states" = "NOT_STARTED,NO_TRAIL" ]
}

@test "ds_trail_report.sh -r filters targets by name regex" {
    run report -f json -r '^PRODDB01'
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows | length')" = "2" ]
}

@test "ds_trail_report.sh --report-file writes the report to disk" {
    local out="${BATS_TEST_TMPDIR}/report.txt"
    run report --summary-only --report-file "$out"
    [ "$status" -eq 0 ]
    [ -s "$out" ]
    grep -q "Summary by environment" "$out"
}

@test "ds_trail_report.sh fails on a missing snapshot file" {
    run "${BIN_DIR}/ds_trail_report.sh" --input-json "${BATS_TEST_TMPDIR}/nope.json"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# jq prelude must agree with the shell implementation
# ---------------------------------------------------------------------------

@test "trail_effective_state in jq matches ds_trail_effective_state in bash" {
    # shellcheck disable=SC1091
    source "${LIB_DIR}/ds_lib.sh"

    local pairs=(
        "ACTIVE|COLLECTING"
        "ACTIVE|NOT_STARTED"
        "ACTIVE|STOPPED"
        "NEEDS_ATTENTION|COLLECTING"
        "FAILED|"
        "ACTIVE|STOPPED_NEEDS_ATTN"
        "ACTIVE|STOPPED_FAILED"
        "DELETING|"
        "|"
    )

    local pair lifecycle status from_bash from_jq
    for pair in "${pairs[@]}"; do
        lifecycle="${pair%%|*}"
        status="${pair#*|}"
        from_bash=$(ds_trail_effective_state "$lifecycle" "$status")
        from_jq=$(jq -rn --arg lc "$lifecycle" --arg st "$status" \
            "${DS_TRAIL_JQ_PRELUDE} trail_effective_state({\"lifecycle-state\": \$lc, \"status\": \$st})")
        [ "$from_bash" = "$from_jq" ]
    done
}
