#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2154
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_ds_target_resolve.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.25
# Purpose....: Regression tests for target name resolution (LRN6087 lab):
#              DELETED targets with the same name must not win the match (#18),
#              and a name missing from a cached list gets one fresh fetch.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    export TMPDIR="${BATS_TEST_TMPDIR}"
    export LOG_LEVEL=ERROR

    # fake oci: the target list comes from MOCK_TARGETS, every call is counted
    export MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    export MOCK_TARGETS="${BATS_TEST_TMPDIR}/targets.json"
    export OCI_LOG="${BATS_TEST_TMPDIR}/oci.log"
    mkdir -p "${MOCK_BIN}"
    : > "${OCI_LOG}"
    cat > "${MOCK_BIN}/oci" << 'MOCK'
#!/usr/bin/env bash
echo "$*" >> "${OCI_LOG}"
cat "${MOCK_TARGETS}"
MOCK
    chmod +x "${MOCK_BIN}/oci"
    export PATH="${MOCK_BIN}:${PATH}"

    COMP="ocid1.compartment.oc1..test"
}

# The library is sourced in each test body, not in setup(): sourced inside a
# function, its `declare -A` caches would be local to that function

_targets() {
    printf '{"data":[%s]}\n' "$1" > "${MOCK_TARGETS}"
}

_list_calls() {
    grep -c 'target-database list' "${OCI_LOG}" || true
}

@test "resolve: a DELETED target with the same name is skipped (#18)" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=0
    _targets '{"id":"ocid1.old","display-name":"db01_CDB26_AIPDB1","lifecycle-state":"DELETED"},
              {"id":"ocid1.new","display-name":"db01_CDB26_AIPDB1","lifecycle-state":"ACTIVE"}'
    run ds_resolve_target_ocid "db01_CDB26_AIPDB1" "$COMP"
    [ "$status" -eq 0 ]
    [ "$output" = "ocid1.new" ]
}

@test "resolve: DELETING is skipped in the case-insensitive match too" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=0
    _targets '{"id":"ocid1.old","display-name":"DB01_CDB26_AIPDB1","lifecycle-state":"DELETING"},
              {"id":"ocid1.new","display-name":"db01_cdb26_aipdb1","lifecycle-state":"NEEDS_ATTENTION"}'
    run ds_resolve_target_ocid "Db01_Cdb26_AiPdb1" "$COMP"
    [ "$status" -eq 0 ]
    [ "$output" = "ocid1.new" ]
}

@test "resolve: a unique substring match ignores deleted targets" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=0
    _targets '{"id":"ocid1.old","display-name":"db01_CDB26_AIPDB1","lifecycle-state":"DELETED"},
              {"id":"ocid1.new","display-name":"db01_CDB26_AIPDB1_v2","lifecycle-state":"ACTIVE"}'
    run ds_resolve_target_ocid "AIPDB1" "$COMP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ocid1.new" ]]
}

@test "resolve: only deleted matches says so instead of a bare 'not found'" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=0
    _targets '{"id":"ocid1.old","display-name":"db01_CDB26_AIPDB1","lifecycle-state":"DELETED"}'
    run --separate-stderr ds_resolve_target_ocid "db01_CDB26_AIPDB1" "$COMP"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"only deleted targets match"* ]]
    [[ "$stderr" == *"db01_CDB26_AIPDB1 (DELETED) -> ocid1.old"* ]]
}

@test "resolve: a name missing from a cached list triggers exactly one refresh" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=300
    _targets '{"id":"ocid1.a","display-name":"existing","lifecycle-state":"ACTIVE"}'
    run ds_resolve_target_ocid "existing" "$COMP"
    [ "$status" -eq 0 ]
    [ "$(_list_calls)" -eq 1 ]

    # target registered after the list was cached (file cache, new process)
    _targets '{"id":"ocid1.a","display-name":"existing","lifecycle-state":"ACTIVE"},
              {"id":"ocid1.b","display-name":"brand_new","lifecycle-state":"CREATING"}'
    run ds_resolve_target_ocid "brand_new" "$COMP"
    [ "$status" -eq 0 ]
    [ "$output" = "ocid1.b" ]
    [ "$(_list_calls)" -eq 2 ]
}

@test "resolve: an unknown name stops after one refresh" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=300
    _targets '{"id":"ocid1.a","display-name":"existing","lifecycle-state":"ACTIVE"}'
    run ds_resolve_target_ocid "existing" "$COMP"
    run --separate-stderr ds_resolve_target_ocid "nope" "$COMP"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Target not found: nope"* ]]
    [ "$(_list_calls)" -eq 2 ]
}

@test "resolve: a hit in the cached list does not refetch" {
    source "${LIB_DIR}/ds_lib.sh"
    export DS_TARGET_CACHE_TTL=300
    _targets '{"id":"ocid1.a","display-name":"existing","lifecycle-state":"ACTIVE"}'
    run ds_resolve_target_ocid "existing" "$COMP"
    run ds_resolve_target_ocid "existing" "$COMP"
    [ "$status" -eq 0 ]
    [ "$(_list_calls)" -eq 1 ]
}

@test "ds_invalidate_target_cache removes all cached lists and the memory copy" {
    source "${LIB_DIR}/ds_lib.sh"
    mkdir -p "${TMPDIR}/datasafe_target_cache"
    echo '{}' > "${TMPDIR}/datasafe_target_cache/targets_1.json"
    echo '{}' > "${TMPDIR}/datasafe_target_cache/targets_2.json"
    _DS_TARGET_CACHE_JSON='{"data":[]}'
    ds_invalidate_target_cache
    [ -z "$_DS_TARGET_CACHE_JSON" ]
    run bash -c "ls '${TMPDIR}/datasafe_target_cache/'targets_*.json 2> /dev/null"
    [ -z "$output" ]
}

@test "ds_delete_target invalidates the cache after a successful delete" {
    source "${LIB_DIR}/ds_lib.sh"
    mkdir -p "${TMPDIR}/datasafe_target_cache"
    echo '{}' > "${TMPDIR}/datasafe_target_cache/targets_1.json"
    _targets ""
    export DRY_RUN=false
    # shellcheck disable=SC2329
    ds_resolve_target_name() { echo "t1"; }
    run ds_delete_target "ocid1.datasafetargetdatabase.oc1..t1"
    [ "$status" -eq 0 ]
    grep -q 'target-database delete' "${OCI_LOG}"
    [ ! -e "${TMPDIR}/datasafe_target_cache/targets_1.json" ]
}
