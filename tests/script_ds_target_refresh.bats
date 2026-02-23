#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
}

@test "ds_target_refresh.sh shows help with phase3 safeguard options" {
    run "${BIN_DIR}/ds_target_refresh.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--input-json FILE"* ]]
    [[ "$output" == *"--save-json FILE"* ]]
    [[ "$output" == *"--allow-stale-selection"* ]]
    [[ "$output" == *"--max-snapshot-age AGE"* ]]
}

@test "ds_target_refresh.sh blocks apply refresh from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/refresh_input.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"NEEDS_ATTENTION"}]}
JSON

    run "${BIN_DIR}/ds_target_refresh.sh" --input-json "$sample_json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-stale-selection"* ]]
}

@test "ds_target_refresh.sh allows dry-run from input-json without override" {
    local sample_json="${BATS_TEST_TMPDIR}/refresh_input_dryrun.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"NEEDS_ATTENTION"}]}
JSON

    run "${BIN_DIR}/ds_target_refresh.sh" --input-json "$sample_json" --dry-run
    [ "$status" -eq 0 ]
}

@test "ds_target_refresh.sh treats already-in-progress conflict as skipped" {
    local sample_json="${BATS_TEST_TMPDIR}/refresh_input_apply.json"

    cat > "$sample_json" <<'JSON'
{"data":[{"id":"ocid1.datasafetarget.oc1..t1","display-name":"db1","lifecycle-state":"NEEDS_ATTENTION"}]}
JSON

    cat > "${TEST_BIN_DIR}/oci" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
    echo "3.0.0"
    exit 0
fi

if [[ "$*" == *"target-database get"* ]]; then
    echo "db1"
    exit 0
fi

if [[ "$*" == *"target-database refresh"* ]]; then
    cat <<'ERR'
ServiceError:
{
  "code": "Conflict",
  "message": "An operation is already in progress."
}
ERR
    exit 1
fi

echo '{"data": []}'
exit 0
EOF
    chmod +x "${TEST_BIN_DIR}/oci"

    run "${BIN_DIR}/ds_target_refresh.sh" --input-json "$sample_json" --allow-stale-selection --no-wait
    [ "$status" -eq 0 ]
    [[ "$output" == *"already in progress"* ]]
}
