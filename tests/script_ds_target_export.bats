#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_export.sh help includes input-json options" {
    run "${BIN_DIR}/ds_target_export.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}

@test "ds_target_export.sh runs from input-json" {
    local sample_json="${BATS_TEST_TMPDIR}/target_export_input.json"
    local out_json="${BATS_TEST_TMPDIR}/targets_export.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetarget.oc1..t1","display-name":"c1_cdb01_CDB$ROOT","lifecycle-state":"ACTIVE","database-details":{"service-name":"cdb01_srv","listener-port":1521}},
  {"id":"ocid1.datasafetarget.oc1..t2","display-name":"c1_cdb01_pdb1","lifecycle-state":"ACTIVE","database-details":{"service-name":"pdb1_srv","listener-port":1522}}
]}
JSON

    run "${BIN_DIR}/ds_target_export.sh" --input-json "$sample_json" -F json -o "$out_json"
    [ "$status" -eq 0 ]
    [ -f "$out_json" ]
    run jq -r 'length' "$out_json"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}
