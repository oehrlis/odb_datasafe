#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: ds_tag_namespace.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.10.06
# Purpose....: ds_tag_namespace.sh against a fake oci - every starting state
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# The fake oci answers from $FAKE_STATE (a directory): namespaces.json is the
# list answer, tag_<Name>.json the get answer per key (missing file = 404).
# Every call that is not a list/get is appended to $FAKE_STATE/writes.

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    SCRIPT="${REPO_ROOT}/bin/ds_tag_namespace.sh"
    export FAKE_STATE="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${FAKE_STATE}" "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
    # The framework's init_config may resolve the object storage namespace.
    "os ns get"*) echo '{"data": "testns"}' ;;
    "iam tag-namespace list"*) cat "${FAKE_STATE}/namespaces.json" ;;
    "iam tag list"*)
        jq -n '{data: [inputs | .data | {name}]}' "${FAKE_STATE}"/tag_*.json 2> /dev/null \
            || echo '{"data": []}' ;;
    "iam tag get"*)
        name=$(sed -E 's/.*--tag-name ([^ ]+).*/\1/' <<< "$args")
        if [[ -f "${FAKE_STATE}/tag_${name}.json" ]]; then
            cat "${FAKE_STATE}/tag_${name}.json"
        else
            echo "ServiceError: NotAuthorizedOrNotFound" >&2; exit 1
        fi ;;
    "iam tag-namespace create"*) echo "$args" >> "${FAKE_STATE}/writes"; echo "ocid1.tagnamespace.new" ;;
    *) echo "$args" >> "${FAKE_STATE}/writes"; echo '{}' ;;
esac
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/oci"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export OCI_TENANCY_OCID="ocid1.tenancy.oc1..test"
    export OCI_CLI_PROFILE="TEST"

    DEF="${BATS_TEST_TMPDIR}/def.json"
    cat > "${DEF}" << 'EOF'
{"namespace": {"name": "DBSec", "description": "ns desc"},
 "tags": [{"name": "Environment", "description": "env", "validator": ["test", "qs", "prod"]},
          {"name": "Owner", "description": "owner", "validator": null}]}
EOF
}

ns_present() {
    local retired="${1:-false}" desc="${2:-ns desc}"
    jq -n --argjson r "${retired}" --arg d "${desc}" \
        '{data: [{id: "ocid1.tagnamespace.x", name: "DBSec", description: $d, "is-retired": $r}]}' \
        > "${FAKE_STATE}/namespaces.json"
}

tag_present() {
    # $1 name, $2 description, $3 validator values as JSON (or null), $4 retired
    jq -n --arg n "$1" --arg d "$2" --argjson v "$3" --argjson r "${4:-false}" \
        '{data: {name: $n, description: $d, "is-retired": $r, "is-cost-tracking": false,
                 validator: (if $v == null then null else {"validator-type": "ENUM", values: $v} end)}}' \
        > "${FAKE_STATE}/tag_$1.json"
}

@test "in sync: nothing to do, no writes" {
    ns_present
    tag_present Environment env '["prod","qs","test"]'
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to create, 0 to update, 3 in sync, 0 skipped"* ]]
    [ ! -f "${FAKE_STATE}/writes" ] || { cat "${FAKE_STATE}/writes"; false; }
}

@test "namespace missing: plan lists namespace and every key, writes nothing" {
    echo '{"data": []}' > "${FAKE_STATE}/namespaces.json"
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CREATE namespace DBSec"* ]]
    [[ "$output" == *"CREATE DBSec.Environment - ENUM test,qs,prod"* ]]
    [[ "$output" == *"CREATE DBSec.Owner - free text"* ]]
    [ ! -f "${FAKE_STATE}/writes" ] || { cat "${FAKE_STATE}/writes"; false; }
}

@test "namespace retired with other description: reactivated and aligned" {
    ns_present true "old desc"
    tag_present Environment env '["test","qs","prod"]'
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    grep -q "tag-namespace update.*--is-retired false" "${FAKE_STATE}/writes"
    grep -q "tag-namespace update.*--description ns desc" "${FAKE_STATE}/writes"
}

@test "key missing: created with ENUM validator" {
    ns_present
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    grep -q 'iam tag create .*--name Environment.*"validatorType":"ENUM","values":\["test","qs","prod"\]' \
        "${FAKE_STATE}/writes"
}

@test "key retired: reactivated" {
    ns_present
    tag_present Environment env '["test","qs","prod"]' true
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    grep -q "iam tag update .*--tag-name Environment.*--is-retired false" "${FAKE_STATE}/writes"
}

@test "ENUM shrink without --allow-shrink: skipped, named, exit 3 on apply" {
    ns_present
    tag_present Environment env '["test","qs","prod","undef"]'
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 3 ]
    [[ "$output" == *"SKIP DBSec.Environment - validator would drop ENUM value(s) undef"* ]]
    [ ! -f "${FAKE_STATE}/writes" ] || { cat "${FAKE_STATE}/writes"; false; }
}

@test "ENUM shrink with --allow-shrink: applied" {
    ns_present
    tag_present Environment env '["test","qs","prod","undef"]'
    tag_present Owner owner null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply --allow-shrink
    [ "$status" -eq 0 ]
    grep -q 'iam tag update .*--tag-name Environment.*--validator' "${FAKE_STATE}/writes"
}

@test "ENUM grow needs no flag, ENUM to free text sets DEFAULT validator" {
    ns_present
    tag_present Environment env '["test","prod"]'
    tag_present Owner owner '["a","b"]'
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    grep -q 'tag-name Environment.*"values":\["test","qs","prod"\]' "${FAKE_STATE}/writes"
    grep -q 'tag-name Owner.*"validatorType":"DEFAULT"' "${FAKE_STATE}/writes"
}

@test "key in tenancy but not in definition: reported, left alone" {
    ns_present
    tag_present Environment env '["test","qs","prod"]'
    tag_present Owner owner null
    tag_present Legacy legacy null
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"left unchanged: Legacy"* ]]
    [ ! -f "${FAKE_STATE}/writes" ] || { cat "${FAKE_STATE}/writes"; false; }
}

@test "duplicate key in definition is rejected" {
    jq '.tags += [.tags[0]]' "${DEF}" > "${DEF}.dup"
    run "${SCRIPT}" --oci-profile TEST -f "${DEF}.dup"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Duplicate tag names in definition: Environment"* ]]
}
