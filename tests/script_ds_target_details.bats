#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_details.sh help includes input-json options" {
    run "${BIN_DIR}/ds_target_details.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}

@test "ds_target_details.sh runs from input-json" {
    local sample_json="${BATS_TEST_TMPDIR}/target_details_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetarget.oc1..t1","display-name":"c1_cdb01_CDB$ROOT","lifecycle-state":"ACTIVE","database-details":{"service-name":"cdb01_srv","listener-port":1521}},
  {"id":"ocid1.datasafetarget.oc1..t2","display-name":"c1_cdb01_pdb1","lifecycle-state":"NEEDS_ATTENTION","database-details":{"service-name":"pdb1_srv","listener-port":1522}}
]}
JSON

    run "${BIN_DIR}/ds_target_details.sh" --input-json "$sample_json" -f json
    [ "$status" -eq 0 ]
    [[ "$output" == *"c1_cdb01_CDB\$ROOT"* ]]
    [[ "$output" == *"c1_cdb01_pdb1"* ]]
}
