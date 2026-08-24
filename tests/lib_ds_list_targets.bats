#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_ds_list_targets.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.08.24
# Purpose....: Regression tests for ds_list_targets lifecycle filtering.
#              OCI CLI --lifecycle-state is a single-value parameter; repeating
#              it only keeps the last value. Multi-state filtering must be done
#              client-side. Tests cover both orderings to catch order-dependence.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    export DS_TARGET_CACHE_TTL=0
    # shellcheck disable=SC1091
    source "${LIB_DIR}/ds_lib.sh"

    # Fixed dataset: 3 ACTIVE, 2 NEEDS_ATTENTION, 1 INACTIVE
    export MOCK_FILE="${BATS_TEST_TMPDIR}/mock_targets.json"
    cat > "${MOCK_FILE}" << 'JSON'
{"data":[
  {"id":"t1","display-name":"T1","lifecycle-state":"ACTIVE"},
  {"id":"t2","display-name":"T2","lifecycle-state":"ACTIVE"},
  {"id":"t3","display-name":"T3","lifecycle-state":"ACTIVE"},
  {"id":"t4","display-name":"T4","lifecycle-state":"NEEDS_ATTENTION"},
  {"id":"t5","display-name":"T5","lifecycle-state":"NEEDS_ATTENTION"},
  {"id":"t6","display-name":"T6","lifecycle-state":"INACTIVE"}
]}
JSON

    # Mock: passes through --lifecycle-state server filtering for single-state
    # calls; returns the full dataset when no filter is given (multi-state path).
    # shellcheck disable=SC2317,SC2329
    _ds_get_target_list_cached() {
        local _filter_state=""
        shift 2  # skip comp_ocid and lifecycle_norm
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "--lifecycle-state" ]]; then
                _filter_state="${2:-}"
                shift 2
            else
                shift
            fi
        done
        if [[ -n "$_filter_state" ]]; then
            jq --arg s "$_filter_state" \
                '.data = (.data | map(select(.["lifecycle-state"] == $s)))' \
                "${MOCK_FILE}"
        else
            cat "${MOCK_FILE}"
        fi
    }

    # shellcheck disable=SC2329
    oci_resolve_compartment_ocid() { printf 'ocid1.compartment.oc1..test'; }
}

# ---------------------------------------------------------------------------
# Single-state (server-side filter, pre-existing behaviour)
# ---------------------------------------------------------------------------

@test "ds_list_targets single state ACTIVE returns 3 targets" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "ACTIVE")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 3 ]
}

@test "ds_list_targets single state NEEDS_ATTENTION returns 2 targets" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "NEEDS_ATTENTION")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 2 ]
}

@test "ds_list_targets single state INACTIVE returns 1 target" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "INACTIVE")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Multi-state (client-side filter, regression for the last-wins bug)
# ---------------------------------------------------------------------------

@test "ds_list_targets ACTIVE,NEEDS_ATTENTION returns union of both states" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "ACTIVE,NEEDS_ATTENTION")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 5 ]
}

@test "ds_list_targets NEEDS_ATTENTION,ACTIVE returns same count as ACTIVE,NEEDS_ATTENTION" {
    result_ab=$(ds_list_targets "ocid1.compartment.oc1..test" "ACTIVE,NEEDS_ATTENTION")
    result_ba=$(ds_list_targets "ocid1.compartment.oc1..test" "NEEDS_ATTENTION,ACTIVE")
    count_ab=$(jq '.data | length' <<< "$result_ab")
    count_ba=$(jq '.data | length' <<< "$result_ba")
    [ "$count_ab" -eq "$count_ba" ]
}

@test "ds_list_targets multi-state result contains only the requested states" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "ACTIVE,NEEDS_ATTENTION")
    # INACTIVE must not appear
    inactive=$(jq '[.data[] | select(.["lifecycle-state"] == "INACTIVE")] | length' <<< "$result")
    [ "$inactive" -eq 0 ]
}

@test "ds_list_targets ACTIVE,INACTIVE excludes NEEDS_ATTENTION targets" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "ACTIVE,INACTIVE")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 4 ]
    na=$(jq '[.data[] | select(.["lifecycle-state"] == "NEEDS_ATTENTION")] | length' <<< "$result")
    [ "$na" -eq 0 ]
}

@test "ds_list_targets no lifecycle filter returns all targets" {
    result=$(ds_list_targets "ocid1.compartment.oc1..test" "")
    count=$(jq '.data | length' <<< "$result")
    [ "$count" -eq 6 ]
}
