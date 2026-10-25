#!/usr/bin/env bats
# shellcheck disable=SC2154
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_database_prereqs.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.25
# Purpose....: Regression tests from the LRN6087 lab against a fake sqlplus:
#              a failed user or grant step fails its scope (no silent "Done"),
#              --all continues and ends with rc 1 and a summary, temp SQL
#              files (they hold the secret) are removed, the secret is never echoed.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export SCRIPT="${REPO_ROOT}/bin/ds_database_prereqs.sh"
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${TMPDIR}"
    export ORACLE_HOME="${BATS_TEST_TMPDIR}/oh"
    export ORACLE_SID="CDB01"
    export SQLPLUS_LOG="${BATS_TEST_TMPDIR}/sqlplus.log"
    : > "${SQLPLUS_LOG}"
    unset ORADBA_ETC ODB_DATASAFE_BASE MOCK_USER_FAIL MOCK_GRANT_FAIL
    mkdir -p "${ORACLE_HOME}/bin"

    # fake sqlplus: heredoc queries get canned answers; for @<script> the
    # script is logged and MOCK_USER_FAIL / MOCK_GRANT_FAIL (comma list of
    # ROOT or PDB names) fail the user step (ORA-28003, rc 1) or the grant step
    # (ORA-44001 printed with rc 0, as datasafe_privileges.sql does)
    cat > "${ORACLE_HOME}/bin/sqlplus" << 'MOCK'
#!/usr/bin/env bash
script=""
for arg in "$@"; do
    [[ "$arg" == @* ]] && script="${arg#@}"
done
if [[ -z "$script" ]]; then
    input=$(cat)
    case "$input" in
        *"select cdb from"*) echo "YES" ;;
        *"open_mode = 'READ WRITE'"*) printf 'PDB1\nPDB2\n' ;;
        *"count(*) from v\$pdbs"*) echo "1" ;;
        *dba_dv_status*) echo "0" ;;
    esac
    exit 0
fi
body=$(cat "$script")
printf '=== %s\n%s\n' "$script" "$body" >> "${SQLPLUS_LOG}"
scope="ROOT"
[[ "$body" =~ container=([A-Za-z0-9_]+) ]] && scope="${BASH_REMATCH[1]}"
case "$body" in
    *create_ds_admin_user.sql*)
        if [[ ",${MOCK_USER_FAIL:-}," == *",${scope},"* ]]; then
            printf '%s\n' 'DECLARE' '*' 'ERROR at line 1:' \
                'ORA-28003: password verification for the specified password failed' 'ORA-06512: at line 59'
            exit 1
        fi ;;
    *datasafe_privileges.sql*)
        if [[ ",${MOCK_GRANT_FAIL:-}," == *",${scope},"* ]]; then
            printf '%s\n' 'The error code is -44001' 'ORA-44001: invalid schema'
            exit 0
        fi ;;
esac
echo "ok ${scope}"
MOCK
    chmod +x "${ORACLE_HOME}/bin/sqlplus"
    export PATH="${ORACLE_HOME}/bin:${PATH}"

    export SECRET='Lab_Secret#2026'
    export SECRET_FILE="${BATS_TEST_TMPDIR}/secret.b64"
    printf '%s' "$SECRET" | base64 > "${SECRET_FILE}"
}

# scripts sqlplus ran for a scope: grep the log blocks
_ran() {
    local sql="$1" scope="$2"
    awk -v sql="$sql" -v scope="$scope" '
        /^=== / { if (blk ~ sql && (scope == "ROOT" ? blk !~ /container=/ : blk ~ "container=" scope)) n++; blk = ""; next }
        { blk = blk "\n" $0 }
        END { if (blk ~ sql && (scope == "ROOT" ? blk !~ /container=/ : blk ~ "container=" scope)) n++; print n + 0 }
    ' "${SQLPLUS_LOG}"
}

@test "prereqs: all scopes succeed - rc 0 and Done" {
    run --separate-stderr "$SCRIPT" --all --secret-file "$SECRET_FILE" --no-color
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Done"* ]]
    [ "$(_ran datasafe_privileges.sql PDB2)" -eq 1 ]
}

@test "prereqs: a failed user step fails the scope, --all continues, rc 1 with summary" {
    export MOCK_USER_FAIL="PDB1"
    run --separate-stderr "$SCRIPT" --all --secret-file "$SECRET_FILE" --no-color
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"PDB=PDB1: create_ds_admin_user.sql failed"* ]]
    [[ "$stderr" == *"ORA-28003"* ]]
    [[ "$stderr" == *"special character"* ]]
    [[ "$stderr" == *"Failed scopes (1): PDB=PDB1"* ]]
    [[ "$stderr" != *"Done"* ]]
    # no grants without a user, the other scopes ran in full
    [ "$(_ran datasafe_privileges.sql PDB1)" -eq 0 ]
    [ "$(_ran datasafe_privileges.sql ROOT)" -eq 1 ]
    [ "$(_ran datasafe_privileges.sql PDB2)" -eq 1 ]
}

@test "prereqs: an ORA- error printed by the grant script fails the scope despite rc 0" {
    export MOCK_GRANT_FAIL="ROOT"
    run --separate-stderr "$SCRIPT" --root --secret-file "$SECRET_FILE" --no-color
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"ROOT: datasafe_privileges.sql failed (sqlplus rc=0)"* ]]
    [[ "$stderr" == *"ORA-44001: invalid schema"* ]]
    [[ "$stderr" == *"Failed scopes (1): ROOT"* ]]
}

@test "prereqs: --dry-run ends with rc 0" {
    run --separate-stderr "$SCRIPT" --all --secret-file "$SECRET_FILE" --no-color --dry-run
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Done"* ]]
}

@test "prereqs: temp SQL files (with the secret as argument) are removed" {
    run --separate-stderr "$SCRIPT" --all --secret-file "$SECRET_FILE" --no-color
    [ "$status" -eq 0 ]
    # the user script was called with the secret ...
    grep -qF -- "$SECRET" "${SQLPLUS_LOG}"
    # ... and nothing with it stays in TMPDIR
    run grep -rlF -- "$SECRET" "${TMPDIR}"
    [ "$status" -ne 0 ]
    run bash -c "ls -A '${TMPDIR}'"
    [ -z "$output" ]
}

@test "prereqs: --debug never echoes the line that passes the secret" {
    run --separate-stderr "$SCRIPT" --root --secret-file "$SECRET_FILE" --no-color --debug
    [ "$status" -eq 0 ]
    [[ "$stderr" != *"$SECRET"* ]]
    [[ "$output" != *"$SECRET"* ]]
    # echo is on for --debug, but switched off right before the user script call
    run grep -B1 'create_ds_admin_user.sql' "${SQLPLUS_LOG}"
    [[ "${lines[0]}" == "set echo off" ]]
}

@test "prereq SQL: CONTAINER=ALL only in CDB\$ROOT and only on CREATE PROFILE" {
    local sql="${REPO_ROOT}/sql/create_ds_admin_prerequisites.sql"
    # ORA-65140 in every PDB: the clause is bound to CON_NAME = CDB$ROOT ...
    grep -qE "SYS_CONTEXT\('USERENV', 'CON_NAME'\) = 'CDB\\\$ROOT'" "$sql"
    grep -qE "THEN ' CONTAINER=ALL' END" "$sql"
    # ... appended to CREATE PROFILE only, never spelled out literally
    [ "$(grep -c 'l_container' "$sql")" -eq 2 ]
    run awk '/ALTER PROFILE/,/Updated profile/' "$sql"
    [[ "$output" != *"l_container"* && "$output" != *"CONTAINER"* ]]
    run grep -nE "CONTAINER=ALL'?;" "$sql"
    [ "$status" -ne 0 ]
}
