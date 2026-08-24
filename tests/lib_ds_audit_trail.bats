#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: lib_ds_audit_trail.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.08.23
# Purpose....: Test suite for the audit trail and audit profile helpers in
#              lib/ds_lib.sh
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export REPO_ROOT
    export LIB_DIR="${REPO_ROOT}/lib"
    # shellcheck disable=SC1091
    source "${LIB_DIR}/ds_lib.sh"
}

# ---------------------------------------------------------------------------
# ds_trail_effective_state
# ---------------------------------------------------------------------------

@test "ds_trail_effective_state prefers status over lifecycle-state" {
    [ "$(ds_trail_effective_state ACTIVE COLLECTING)" = "COLLECTING" ]
    [ "$(ds_trail_effective_state ACTIVE NOT_STARTED)" = "NOT_STARTED" ]
    [ "$(ds_trail_effective_state ACTIVE STOPPED)" = "STOPPED" ]
}

@test "ds_trail_effective_state reports a broken lifecycle-state as NEEDS_ATTENTION" {
    [ "$(ds_trail_effective_state NEEDS_ATTENTION COLLECTING)" = "NEEDS_ATTENTION" ]
    [ "$(ds_trail_effective_state FAILED '')" = "NEEDS_ATTENTION" ]
}

@test "ds_trail_effective_state maps the stopped-with-problem statuses" {
    [ "$(ds_trail_effective_state ACTIVE STOPPED_NEEDS_ATTN)" = "NEEDS_ATTENTION" ]
    [ "$(ds_trail_effective_state ACTIVE STOPPED_FAILED)" = "NEEDS_ATTENTION" ]
}

@test "ds_trail_effective_state keeps the deletion lifecycle-states" {
    [ "$(ds_trail_effective_state DELETING '')" = "DELETING" ]
    [ "$(ds_trail_effective_state DELETED COLLECTING)" = "DELETED" ]
}

@test "ds_trail_effective_state falls back to lifecycle-state, then UNKNOWN" {
    [ "$(ds_trail_effective_state INACTIVE '')" = "INACTIVE" ]
    [ "$(ds_trail_effective_state '' '')" = "UNKNOWN" ]
}

@test "ds_trail_effective_state is case insensitive" {
    [ "$(ds_trail_effective_state active collecting)" = "COLLECTING" ]
}

# ---------------------------------------------------------------------------
# ds_trail_is_collecting / ds_trail_is_startable
# ---------------------------------------------------------------------------

@test "ds_trail_is_collecting covers every in-progress status" {
    local s
    for s in COLLECTING STARTING RESUMING RECOVERING RETRYING IDLE; do
        run ds_trail_is_collecting "$s"
        [ "$status" -eq 0 ]
    done
}

@test "ds_trail_is_collecting is false for states that need action" {
    local s
    for s in NOT_STARTED STOPPED NEEDS_ATTENTION NO_TRAIL INACTIVE; do
        run ds_trail_is_collecting "$s"
        [ "$status" -ne 0 ]
    done
}

@test "ds_trail_is_startable only accepts NOT_STARTED" {
    run ds_trail_is_startable NOT_STARTED
    [ "$status" -eq 0 ]
    local s
    for s in COLLECTING STOPPED NEEDS_ATTENTION NO_TRAIL; do
        run ds_trail_is_startable "$s"
        [ "$status" -ne 0 ]
    done
}

# ---------------------------------------------------------------------------
# ds_trail_items
# ---------------------------------------------------------------------------

@test "ds_trail_items unwraps the paginated list shape" {
    result=$(ds_trail_items '{"data":{"items":[{"id":"a"},{"id":"b"}]}}')
    [ "$(jq 'length' <<< "$result")" = "2" ]
}

@test "ds_trail_items unwraps the plain array shape" {
    result=$(ds_trail_items '{"data":[{"id":"a"}]}')
    [ "$(jq 'length' <<< "$result")" = "1" ]
}

@test "ds_trail_items returns an empty array for empty or malformed input" {
    [ "$(ds_trail_items '')" = "[]" ]
    [ "$(ds_trail_items '{"data":{}}')" = "[]" ]
}

# ---------------------------------------------------------------------------
# ds_format_bytes
# ---------------------------------------------------------------------------

@test "ds_format_bytes scales to the right unit" {
    [ "$(ds_format_bytes 0)" = "0B" ]
    [ "$(ds_format_bytes 512)" = "512B" ]
    [ "$(ds_format_bytes 1024)" = "1.0KB" ]
    [ "$(ds_format_bytes 1073741824)" = "1.0GB" ]
    [ "$(ds_format_bytes 1610612736)" = "1.5GB" ]
}

@test "ds_format_bytes returns a dash for a non-numeric input" {
    [ "$(ds_format_bytes '')" = "-" ]
    [ "$(ds_format_bytes 'null')" = "-" ]
}

# ---------------------------------------------------------------------------
# ds_build_trail_rows
# ---------------------------------------------------------------------------

@test "ds_build_trail_rows reports the most actionable state of several trails" {
    local targets trails rows
    targets='{"data":[{"id":"t1","display-name":"DB_PDB1","compartment-id":"c1","defined-tags":{"DBSec":{"ContainerStage":"pdb-prod"}}}]}'
    trails='[{"id":"a1","target-id":"t1","lifecycle-state":"ACTIVE","status":"COLLECTING"},
             {"id":"a2","target-id":"t1","lifecycle-state":"ACTIVE","status":"NOT_STARTED"}]'
    rows=$(ds_build_trail_rows "$targets" "$trails" '[]' DBSec '')
    [ "$(jq -r '.[0].["trail-state"]' <<< "$rows")" = "NOT_STARTED" ]
    [ "$(jq -r '.[0].["trail-count"]' <<< "$rows")" = "2" ]
}

@test "ds_build_trail_rows reports NO_TRAIL when the target has no trail" {
    local targets rows
    targets='{"data":[{"id":"t1","display-name":"DB_PDB1","compartment-id":"c1","defined-tags":{}}]}'
    rows=$(ds_build_trail_rows "$targets" '[]' '[]' DBSec '')
    [ "$(jq -r '.[0].["trail-state"]' <<< "$rows")" = "NO_TRAIL" ]
    [ "$(jq -r '.[0].["auto-purge"]' <<< "$rows")" = "-" ]
    [ "$(jq -r '.[0].stage' <<< "$rows")" = "-" ]
}

@test "ds_build_trail_rows reports mixed auto-purge across trails" {
    local targets trails rows
    targets='{"data":[{"id":"t1","display-name":"DB_PDB1","compartment-id":"c1","defined-tags":{}}]}'
    trails='[{"id":"a1","target-id":"t1","status":"COLLECTING","is-auto-purge-enabled":true},
             {"id":"a2","target-id":"t1","status":"COLLECTING","is-auto-purge-enabled":false}]'
    rows=$(ds_build_trail_rows "$targets" "$trails" '[]' DBSec '')
    [ "$(jq -r '.[0].["auto-purge"]' <<< "$rows")" = "mixed" ]
}

@test "ds_build_trail_rows joins the audit profile volume and OCID" {
    local targets profiles rows
    targets='{"data":[{"id":"t1","display-name":"DB_PDB1","compartment-id":"c1","defined-tags":{}}]}'
    profiles='[{"id":"p1","target-id":"t1","audit-collected-volume":4096}]'
    rows=$(ds_build_trail_rows "$targets" '[]' "$profiles" DBSec '')
    [ "$(jq -r '.[0].["volume-bytes"]' <<< "$rows")" = "4096" ]
    [ "$(jq -r '.[0].["audit-profile-id"]' <<< "$rows")" = "p1" ]
}

@test "ds_build_trail_rows applies the state filter" {
    local targets trails rows
    targets='{"data":[{"id":"t1","display-name":"A","compartment-id":"c1","defined-tags":{}},
                      {"id":"t2","display-name":"B","compartment-id":"c1","defined-tags":{}}]}'
    trails='[{"id":"a1","target-id":"t1","status":"COLLECTING"},
             {"id":"a2","target-id":"t2","status":"NOT_STARTED"}]'
    rows=$(ds_build_trail_rows "$targets" "$trails" '[]' DBSec 'NOT_STARTED')
    [ "$(jq 'length' <<< "$rows")" = "1" ]
    [ "$(jq -r '.[0].target' <<< "$rows")" = "B" ]
}

# ---------------------------------------------------------------------------
# ds_trail_summary_json
# ---------------------------------------------------------------------------

@test "ds_trail_summary_json groups by environment and appends TOTAL" {
    local rows summary
    rows='[{"environment":"prod","trail-state":"COLLECTING","volume-bytes":100},
           {"environment":"prod","trail-state":"NOT_STARTED","volume-bytes":0},
           {"environment":"qs","trail-state":"NO_TRAIL","volume-bytes":null}]'
    summary=$(ds_trail_summary_json "$rows")
    [ "$(jq -r '.[-1].environment' <<< "$summary")" = "TOTAL" ]
    [ "$(jq -r '.[-1].targets' <<< "$summary")" = "3" ]
    [ "$(jq -r '.[-1].["volume-bytes"]' <<< "$summary")" = "100" ]
    [ "$(jq -r '.[] | select(.environment=="prod") | .not_started' <<< "$summary")" = "1" ]
}

@test "ds_trail_summary_json returns an empty array for no rows" {
    [ "$(ds_trail_summary_json '[]')" = "[]" ]
}
