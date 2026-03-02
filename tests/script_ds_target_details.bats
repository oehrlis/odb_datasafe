#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
}

@test "ds_target_details.sh help includes input-json options" {
    run "${BIN_DIR}/ds_target_details.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
}

@test "ds_target_details.sh --help shows --all and --filter scope flags" {
    run "${BIN_DIR}/ds_target_details.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
    [[ "$output" == *"--filter"* ]]
}

@test "ds_target_details.sh --all and -c are mutually exclusive" {
    run "${BIN_DIR}/ds_target_details.sh" --all -c some-compartment
    [ "$status" -ne 0 ]
}

@test "ds_target_details.sh --all and -T are mutually exclusive" {
    run "${BIN_DIR}/ds_target_details.sh" --all -T some-target
    [ "$status" -ne 0 ]
}

@test "ds_target_details.sh rejects invalid --filter regex" {
    run "${BIN_DIR}/ds_target_details.sh" -T some-target --filter '[invalid'
    [ "$status" -ne 0 ]
}

@test "ds_target_details.sh --filter applies to input-json results" {
    local sample_json="${BATS_TEST_TMPDIR}/target_details_filter.json"

    cat > "$sample_json" <<'JSON'
{"data":[
  {"id":"ocid1.datasafetarget.oc1..t1","display-name":"prod_cdb01_CDBROOT","lifecycle-state":"ACTIVE","database-details":{"service-name":"cdb01_srv","listener-port":1521}},
  {"id":"ocid1.datasafetarget.oc1..t2","display-name":"dev_cdb02_CDBROOT","lifecycle-state":"ACTIVE","database-details":{"service-name":"cdb02_srv","listener-port":1521}}
]}
JSON

    run "${BIN_DIR}/ds_target_details.sh" --input-json "$sample_json" --filter 'prod' -f json
    [ "$status" -eq 0 ]
    [[ "$output" == *"prod_cdb01_CDBROOT"* ]]
    [[ "$output" != *"dev_cdb02_CDBROOT"* ]]
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
