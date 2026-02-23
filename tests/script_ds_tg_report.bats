#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_tg_report.sh help includes input-json options" {
    run "${BIN_DIR}/ds_tg_report.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}

@test "ds_tg_report.sh runs from input-json" {
    local sample_json="${BATS_TEST_TMPDIR}/tg_report_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"ACTIVE","defined-tags":{"DBSec":{"Environment":"prod","ContainerStage":"app","ContainerType":"db","Classification":"internal"}}},
  {"id":"ocid1.datasafetarget.oc1..t2","display-name":"db2","lifecycle-state":"ACTIVE","defined-tags":{}}
]}
JSON

    run "${BIN_DIR}/ds_tg_report.sh" --input-json "$sample_json" -r missing -f table
    [ "$status" -eq 0 ]
    [[ "$output" == *"db2"* ]]
}
