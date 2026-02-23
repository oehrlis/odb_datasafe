#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    BIN_DIR="${REPO_ROOT}/bin"
    SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    ODB_DATASAFE_BASE="${BATS_TEST_TMPDIR}/odb_datasafe"
    export REPO_ROOT BIN_DIR SCRIPT_VERSION ODB_DATASAFE_BASE
    mkdir -p "${ODB_DATASAFE_BASE}/log"
}

@test "ds_target_list.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_list.sh" ]
    [ -x "${BIN_DIR}/ds_target_list.sh" ]
}

@test "ds_target_list.sh shows help message" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "ds_target_list.sh accepts all-target option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-A"* ]] || [[ "$output" == *"--all"* ]]
}

@test "ds_target_list.sh accepts overview option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--overview"* ]]
}

@test "ds_target_list.sh accepts overview-no-members option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-members"* ]]
}

@test "ds_target_list.sh accepts overview-truncate-members option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--truncate-members"* ]]
}

@test "ds_target_list.sh accepts health overview option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--mode MODE"* ]]
}

@test "ds_target_list.sh accepts health details option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--issue-view VIEW"* ]]
}

@test "ds_target_list.sh accepts output-group option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--mode MODE"* ]]
}

@test "ds_target_list.sh accepts simplified health option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--mode MODE"* ]] && [[ "$output" == *"health|problems"* ]]
}

@test "ds_target_list.sh accepts health issue drill-down option" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--issue ISSUE"* ]]
}

@test "ds_target_list.sh help includes report and json replay options" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--mode MODE"* ]]
    [[ "$output" == *"details|count|overview|health|problems|report"* ]]
    [[ "$output" == *"--report"* ]]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}

@test "ds_target_list.sh help includes short mode aliases" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-C, --count"* ]]
    [[ "$output" == *"-H, --health"* ]]
    [[ "$output" == *"-P, --problems"* ]]
    [[ "$output" == *"-R, --report"* ]]
}

@test "ds_target_list.sh report mode works from input json" {
    local sample_json="${BATS_TEST_TMPDIR}/ds_target_list_sample.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"display-name":"clusterA_cdb01_CDB$ROOT","lifecycle-state":"ACTIVE","lifecycle-details":""},
  {"display-name":"clusterA_cdb01_app1","lifecycle-state":"ACTIVE","lifecycle-details":""},
  {"display-name":"clusterA_cdb01_app2","lifecycle-state":"NEEDS_ATTENTION","lifecycle-details":"ORA-01017: invalid username/password"},
  {"display-name":"clusterB_cdb02_CDB$ROOT","lifecycle-state":"NEEDS_ATTENTION","lifecycle-details":"failed to connect login timeout"},
  {"display-name":"badname","lifecycle-state":"INACTIVE","lifecycle-details":""}
]}
JSON

    run "${BIN_DIR}/ds_target_list.sh" --input-json "$sample_json" --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"Data Safe Target Report (High-Level)"* ]]
    [[ "$output" == *"Run ID"* ]]
    [[ "$output" == *"Coverage Metrics:"* ]]
    [[ "$output" == *"SID->CDB coverage"* ]]
    [[ "$output" == *"Issue summary (severity/count/SIDs):"* ]]
    [[ "$output" == *"SID %"* ]]
    [[ "$output" == *"NEEDS_ATTENTION breakdown"* ]]
    [[ "$output" == *"Top affected SIDs (top 10 by issue count):"* ]]
    [[ "$output" == *"Delta vs previous run:"* ]]
}

@test "ds_target_list.sh report mode simplifies empty issue sections" {
    local sample_json="${BATS_TEST_TMPDIR}/ds_target_list_no_issues.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"display-name":"clusterX_cdb01_CDB$ROOT","lifecycle-state":"ACTIVE","lifecycle-details":""},
  {"display-name":"clusterX_cdb01_app1","lifecycle-state":"ACTIVE","lifecycle-details":""},
  {"display-name":"clusterX_cdb01_app2","lifecycle-state":"ACTIVE","lifecycle-details":""}
]}
JSON

    run "${BIN_DIR}/ds_target_list.sh" --input-json "$sample_json" --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"NEEDS_ATTENTION breakdown: none"* ]]
    [[ "$output" == *"Issue summary: none"* ]]
    [[ "$output" == *"Top affected SIDs: none"* ]]
}
