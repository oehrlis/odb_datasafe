#!/usr/bin/env bats
# shellcheck disable=SC2154
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_fleet_assessment_stats.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.11.24
# Purpose....: Test suite for bin/ds_fleet_assessment_stats.sh (oci stubbed)
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export SCRIPT_PATH="${REPO_ROOT}/bin/ds_fleet_assessment_stats.sh"
    export ODB_DATASAFE_BASE="${BATS_TEST_TMPDIR}/base"
    mkdir -p "${ODB_DATASAFE_BASE}/log" "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/tmp"
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    export STUB_LOG="${BATS_TEST_TMPDIR}/oci_calls.log"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export DS_ROOT_COMP="ocid1.compartment.oc1..rootcomp"
    unset OCI_CLI_PROFILE OCI_CLI_REGION OCI_CLI_CONFIG_FILE

    cat > "${BATS_TEST_TMPDIR}/bin/oci" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG}"
case "$*" in
    *"os ns get"*)
        echo '{"data":"ns"}'
        ;;
    *"target-database list"*)
        cat << 'JSON'
{"data":[
 {"id":"ocid1.datasafetargetdatabase.oc1..tgt1","display-name":"SECRETDB_ONE","lifecycle-state":"ACTIVE"},
 {"id":"ocid1.datasafetargetdatabase.oc1..tgt2","display-name":"SECRETDB_TWO","lifecycle-state":"ACTIVE"},
 {"id":"ocid1.datasafetargetdatabase.oc1..tgt3","display-name":"SECRETDB_THREE","lifecycle-state":"NEEDS_ATTENTION"}
]}
JSON
        ;;
    *"user-assessment list-users"*"ocid1.uassess.oc1..ua1"*)
        cat << 'JSON'
{"data":[
 {"user-name":"SECRETUSER_A","account-status":"OPEN","admin-roles":["DBA","DV_OWNER"],"time-last-login":"2099-01-01T00:00:00.000Z"},
 {"user-name":"SECRETUSER_B","account-status":"EXPIRED","admin-roles":["DBA"],"time-last-login":"2020-01-01T00:00:00.000Z"},
 {"user-name":"SECRETUSER_C","account-status":"OPEN","admin-roles":[],"time-last-login":null}
]}
JSON
        ;;
    *"user-assessment list-users"*"ocid1.uassess.oc1..ua2"*)
        if [[ -n "${STUB_FAIL_UA2:-}" ]]; then
            echo "ServiceError: boom" >&2
            exit 1
        fi
        cat << 'JSON'
{"data":[
 {"user-name":"SECRETUSER_D","account-status":"EXPIRED & LOCKED","admin-roles":["DBA"],"time-last-login":"2020-06-01T00:00:00.000Z"},
 {"user-name":"SECRETUSER_E","account-status":"LOCKED","admin-roles":[],"time-last-login":"2099-01-01T00:00:00.000Z"}
]}
JSON
        ;;
    *"user-assessment list"*)
        cat << 'JSON'
{"data":[
 {"id":"ocid1.uassess.oc1..ua1","time-last-assessed":"2026-11-01T10:00:00.000Z"},
 {"id":"ocid1.uassess.oc1..ua2","time-last-assessed":"2026-11-20T10:00:00.000Z"}
]}
JSON
        ;;
    *"security-assessment list-finding-analytics"*)
        cat << 'JSON'
{"data":{"items":[
 {"dimensions":{"finding-key":"SECRETKEY.LOW","title":"Findingtitle B"},"metric":{"targets-count":1}},
 {"dimensions":{"finding-key":"SECRETKEY.TOP","title":"Findingtitle A"},"metric":{"targets-count":2}}
]}}
JSON
        ;;
    *"security-assessment list"*)
        cat << 'JSON'
{"data":[
 {"id":"ocid1.sassess.oc1..sa1","time-updated":"2026-10-15T08:00:00.000Z"},
 {"id":"ocid1.sassess.oc1..sa2","time-updated":"2026-11-22T08:00:00.000Z"}
]}
JSON
        ;;
    *)
        echo '{"data":[]}'
        ;;
esac
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/oci"
}

@test "ds_fleet_assessment_stats.sh exists and is executable" {
    [ -f "$SCRIPT_PATH" ]
    [ -x "$SCRIPT_PATH" ]
}

@test "ds_fleet_assessment_stats.sh --help lists options" {
    run bash "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--idle-days N"* ]]
    [[ "$output" == *"--dba-threshold N"* ]]
    [[ "$output" == *"--top N"* ]]
    [[ "$output" == *"--keep-workdir"* ]]
    [[ "$output" == *"--oci-profile"* ]]
}

@test "ds_fleet_assessment_stats.sh rejects unknown option and non-numeric values" {
    run bash "$SCRIPT_PATH" --bogus
    [ "$status" -ne 0 ]
    run bash "$SCRIPT_PATH" --idle-days abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"IDLE_DAYS"* ]]
}

@test "ds_fleet_assessment_stats.sh prints the fleet aggregates" {
    run --separate-stderr bash "$SCRIPT_PATH" --dba-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"targets total: 3"* ]]
    [[ "$output" == *"  ACTIVE: 2"* ]]
    [[ "$output" == *"  NEEDS_ATTENTION: 1"* ]]
    [[ "$output" == *"oldest 2026-11-01, newest 2026-11-20"* ]]
    [[ "$output" == *"oldest 2026-10-15, newest 2026-11-22"* ]]
    [[ "$output" == *"databases with user data: 2"* ]]
    [[ "$output" == *"accounts total: 5"* ]]
    [[ "$output" == *"DBA role holders total: 3, median per target: 1.5, targets with more than 1: 1 (50%)"* ]]
    [[ "$output" == *"expired accounts: 2 (40%)"* ]]
    [[ "$output" == *"idle 90+ days: 2 (40%)"* ]]
    [[ "$output" == *"never logged in: 1 (20%)"* ]]
    [[ "$output" == *"  OPEN: 2 (40%)"* ]]
    [[ "$output" == *"  EXPIRED: 1 (20%)"* ]]
    [[ "$output" == *"  EXPIRED & LOCKED: 1 (20%)"* ]]
    [[ "$output" == *"  LOCKED: 1 (20%)"* ]]
    [[ "$output" == *"SECRETKEY.TOP"* ]]
    [[ "$output" == *"Findingtitle A"* ]]
}

@test "ds_fleet_assessment_stats.sh default DBA threshold is 5" {
    run --separate-stderr bash "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"targets with more than 5: 0 (0%)"* ]]
}

@test "ds_fleet_assessment_stats.sh --idle-days changes the idle count" {
    run --separate-stderr bash "$SCRIPT_PATH" --idle-days 36500
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle 36500+ days: 0 (0%)"* ]]
}

@test "ds_fleet_assessment_stats.sh --top limits and orders the HIGH findings" {
    run --separate-stderr bash "$SCRIPT_PATH" --top 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"top 1 HIGH findings"* ]]
    [[ "$output" == *"SECRETKEY.TOP"* ]]
    [[ "$output" != *"SECRETKEY.LOW"* ]]
    [[ "$output" == *"2"$'\t'"66.7%"* ]]
}

@test "ds_fleet_assessment_stats.sh leaks no user, target name or OCID to stdout" {
    run --separate-stderr bash "$SCRIPT_PATH" --dba-threshold 1
    [ "$status" -eq 0 ]
    [[ "$output" != *"SECRETUSER"* ]]
    [[ "$output" != *"SECRETDB"* ]]
    [[ "$output" != *"ocid1."* ]]
}

@test "ds_fleet_assessment_stats.sh warns and continues when list-users fails" {
    export STUB_FAIL_UA2=1
    run --separate-stderr bash "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"WARN"* ]]
    [[ "$stderr" == *"list-users failed"* ]]
    [[ "$output" == *"user assessments without data: 1 of 2"* ]]
    [[ "$output" == *"accounts total: 3"* ]]
    [[ "$output" != *"SECRETUSER"* ]]
}

@test "ds_fleet_assessment_stats.sh warns on missing user fields" {
    cat > "${BATS_TEST_TMPDIR}/bin/oci" << 'STUB'
#!/usr/bin/env bash
case "$*" in
    *"os ns get"*) echo '{"data":"ns"}' ;;
    *"user-assessment list-users"*) echo '{"data":[{"user-name":"X"}]}' ;;
    *"user-assessment list"*) echo '{"data":[{"id":"ocid1.uassess.oc1..ua1"}]}' ;;
    *) echo '{"data":[]}' ;;
esac
STUB
    run --separate-stderr bash "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"without account-status"* ]]
    [[ "$stderr" == *"without admin-roles"* ]]
    [[ "$stderr" == *"without time-last-login"* ]]
    [[ "$stderr" == *"no HIGH finding items"* ]]
    [[ "$output" == *"accounts total: 1"* ]]
    [[ "$output" == *"  UNKNOWN: 1"* ]]
}

@test "ds_fleet_assessment_stats.sh passes the OCI profile option to oci" {
    run --separate-stderr bash "$SCRIPT_PATH" --oci-profile MYPROF
    [ "$status" -eq 0 ]
    run grep -c -- "--profile MYPROF" "$STUB_LOG"
    [ "$output" -ge 5 ]
}

@test "ds_fleet_assessment_stats.sh uses -c compartment over DS_ROOT_COMP" {
    run --separate-stderr bash "$SCRIPT_PATH" -c ocid1.compartment.oc1..explicit
    [ "$status" -eq 0 ]
    run grep -c "ocid1.compartment.oc1..explicit" "$STUB_LOG"
    [ "$output" -ge 1 ]
    run grep -c "ocid1.compartment.oc1..rootcomp" "$STUB_LOG"
    [ "$output" -eq 0 ]
}

@test "ds_fleet_assessment_stats.sh only issues read-only OCI calls" {
    run --separate-stderr bash "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
    run grep -ciE " (create|update|delete|move|activate|deactivate|refresh)" "$STUB_LOG"
    [ "$output" -eq 0 ]
}

@test "ds_fleet_assessment_stats.sh removes the workdir at exit" {
    run --separate-stderr bash "$SCRIPT_PATH"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "${TMPDIR}")" ]
}

@test "ds_fleet_assessment_stats.sh --keep-workdir keeps raw JSON and says where" {
    run --separate-stderr bash "$SCRIPT_PATH" --keep-workdir
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Workdir kept"* ]]
    run find "${TMPDIR}" -mindepth 2 -name users.jsonl
    [ -n "$output" ]
}
