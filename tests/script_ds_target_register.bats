#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
}

@test "ds_target_register.sh exists and is executable" {
    [ -f "${BIN_DIR}/ds_target_register.sh" ]
    [ -x "${BIN_DIR}/ds_target_register.sh" ]
}

@test "ds_target_register.sh shows help message" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"--ds-secret"* ]]
    [[ "$output" == *"--secret-file"* ]]
}

@test "ds_target_register.sh defaults to help without arguments" {
    run "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"USAGE:"* ]]
}

@test "ds_target_register.sh help includes default connector and compartment hints" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"DS_REGISTER_COMPARTMENT"* ]]
    [[ "$output" == *"ONPREM_CONNECTOR_LIST"* ]]
}

@test "ds_target_register.sh help documents host or cluster requirement" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Specify --host or --cluster"* ]] || [[ "$output" == *"required with --host as alternative"* ]]
}

@test "ds_target_register.sh polls ds_list_targets for ACTIVE state after registration" {
    # --wait-for-state mixes OCI CLI progress output into stdout (via 2>&1 in oci_exec),
    # corrupting the JSON result. The script uses a poll loop instead.
    run bash -c "grep -E -- '--wait-for-state' '${BIN_DIR}/ds_target_register.sh' | grep -v '^[[:space:]]*#'"
    [ "$status" -ne 0 ]

    run grep -E 'ds_list_targets|lifecycle-state.*ACTIVE' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses die message before exit code" {
    run grep -E -- 'die "Target registration failed" 2' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh payload includes vmClusterId for cloud-at-customer" {
    run grep -E -- 'vmClusterId' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh resolves pluggableDatabaseId for PDB scope" {
    run grep -E -- 'pluggableDatabaseId|resolve_pluggable_db_ocid' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh uses single DbNode call for host-based derivation" {
    # HOST block should call oci_resolve_dbnode_by_host (combined compartment+cluster)
    run grep 'oci_resolve_dbnode_by_host' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

@test "ds_target_register.sh delegates compartment/cluster functions to library" {
    # Both local functions should be thin wrappers, not reimplementing OCI calls
    run grep 'oci_resolve_compartment_by_dbnode_name' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]

    run grep 'oci_resolve_vm_cluster_compartment' "${BIN_DIR}/ds_target_register.sh"
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------------
# --type exacc|compute|onprem - payload and flag validation against a fake oci
# ------------------------------------------------------------------------------

_fake_oci_setup() {
    export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${TEST_BIN_DIR}"
    export PATH="${TEST_BIN_DIR}:${PATH}"
    # keep the host's ORADBA_ETC/datasafe.conf and OCI defaults out of the test
    export ORADBA_ETC="${BATS_TEST_TMPDIR}/etc"
    mkdir -p "${ORADBA_ETC}"
    unset DS_ROOT_COMP DS_REGISTER_COMPARTMENT DS_CONNECTOR_COMP ONPREM_CONNECTOR \
        ONPREM_CONNECTOR_OCID ONPREM_CONNECTOR_LIST DS_ONPREM_CONNECTOR_LIST DATASAFE_SECRET
    export OCI_LOG="${BATS_TEST_TMPDIR}/oci.log"
    : > "${OCI_LOG}"
    cat > "${TEST_BIN_DIR}/oci" << 'EOF'
#!/usr/bin/env bash
echo "$*" >> "${OCI_LOG}"
case "$*" in
    *"os ns get"*) echo '{"data":"ns"}' ;;
    *"on-prem-connector list"*)
        echo '{"data":[{"display-name":"demo-conn","id":"ocid1.datasafeonpremconnector.oc1..conn"}]}' ;;
    *"data-safe target-database create"*) echo "unexpected create" >&2; exit 9 ;;
    *) echo '{"data":[]}' ;;
esac
EOF
    chmod +x "${TEST_BIN_DIR}/oci"
    COMP="ocid1.compartment.oc1..demo"
    INST="ocid1.instance.oc1.eu-zurich-1.demo"
}

@test "ds_target_register: --type compute dry-run builds INSTALLED_DATABASE / ORACLE_CLOUD payload" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type compute \
        -H demovm.sub.vcn.oraclevcn.com --sid CDB19 --pdb PDB1 --instance-id "$INST" \
        --host-ip 10.0.1.10 -c "$COMP" --connector demo-conn -P secret123 --dry-run
    [ "$status" -eq 0 ]
    [ "$(jq -r '.databaseDetails.databaseType' <<< "$output")" = "INSTALLED_DATABASE" ]
    [ "$(jq -r '.databaseDetails.infrastructureType' <<< "$output")" = "ORACLE_CLOUD" ]
    [ "$(jq -r '.databaseDetails.instanceId' <<< "$output")" = "$INST" ]
    [ "$(jq -c '.databaseDetails.ipAddresses' <<< "$output")" = '["10.0.1.10"]' ]
    [ "$(jq -r '.databaseDetails.listenerPort' <<< "$output")" = "1521" ]
    [ "$(jq -r '.databaseDetails.serviceName' <<< "$output")" = "PDB1" ]
    [ "$(jq -r '.databaseDetails | has("vmClusterId")' <<< "$output")" = "false" ]
    [ "$(jq -r '.connectionOption.connectionType' <<< "$output")" = "ONPREM_CONNECTOR" ]
    [ "$(jq -r '.connectionOption.onPremConnectorId' <<< "$output")" = "ocid1.datasafeonpremconnector.oc1..conn" ]
    [ "$(jq -r '.credentials.password' <<< "$output")" = "****" ]
    [ "$(jq -r '.displayName' <<< "$output")" = "demovm_CDB19_PDB1" ]
    [ "$(jq -r '.definedTags.DBSec.ContainerType' <<< "$output")" = "pdb" ]
    [[ "$stderr" == *"skipping VM cluster and pluggable DB lookup"* ]]
    # no DB node / VM cluster / PDB lookup for installed databases
    grep -q 'on-prem-connector list' "${OCI_LOG}"
    run grep -Eq 'db-node|vm-cluster|pluggable-database|database list|resource-query|search' "${OCI_LOG}"
    [ "$status" -ne 0 ]
}

@test "ds_target_register: --type onprem dry-run builds ON_PREMISES payload without instanceId" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type onprem -H dbhost01 \
        --sid CDB01 --root --host-ip 192.168.1.20,dbhost01.example.com --port 1522 \
        --service CDB01.example.com -c "$COMP" \
        --connector ocid1.datasafeonpremconnector.oc1..direct -P secret123 -n
    [ "$status" -eq 0 ]
    [ "$(jq -r '.databaseDetails.databaseType' <<< "$output")" = "INSTALLED_DATABASE" ]
    [ "$(jq -r '.databaseDetails.infrastructureType' <<< "$output")" = "ON_PREMISES" ]
    [ "$(jq -r '.databaseDetails | has("instanceId")' <<< "$output")" = "false" ]
    [ "$(jq -c '.databaseDetails.ipAddresses' <<< "$output")" = '["192.168.1.20","dbhost01.example.com"]' ]
    [ "$(jq -r '.databaseDetails.listenerPort' <<< "$output")" = "1522" ]
    [ "$(jq -r '.databaseDetails.serviceName' <<< "$output")" = "CDB01.example.com" ]
    [ "$(jq -r '.connectionOption.onPremConnectorId' <<< "$output")" = "ocid1.datasafeonpremconnector.oc1..direct" ]
    [ "$(jq -r '.displayName' <<< "$output")" = "dbhost01_CDB01_CDBROOT" ]
    [ "$(jq -r '.credentials.userName' <<< "$output")" = 'C##DS_ADMIN' ]
    [ "$(jq -r '.definedTags.DBSec.ContainerType' <<< "$output")" = "cdbroot" ]
}

@test "ds_target_register: compute/onprem display name parses as <host>_<sid>_<pdb>" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type onprem -H my_db_host.example.com \
        --sid CDB01 --pdb APP1 --host-ip 10.1.1.1 -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [ "$(jq -r '.displayName' <<< "$output")" = "my-db-host_CDB01_APP1" ]
    [[ "$stderr" == *"contains '_'"* ]]
    IFS='_' read -r h s p <<< "$(jq -r '.displayName' <<< "$output")"
    [ "$h" = "my-db-host" ] && [ "$s" = "CDB01" ] && [ "$p" = "APP1" ]
}

@test "ds_target_register: compute/onprem without -H falls back to local hostname, with a message" {
    _fake_oci_setup
    local short
    short="$(hostname)"
    short="${short%%.*}"
    short="${short//_/-}"
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type onprem --sid CDB01 --pdb APP1 \
        --host-ip 10.1.1.1 -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [ "$(jq -r '.displayName' <<< "$output")" = "${short}_CDB01_APP1" ]
    [[ "$stderr" == *"No -H/--host given; using local hostname"* ]]
}

@test "ds_target_register: explicit -N display name is kept for compute" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type compute -N demo_CDB26_FREEPDB1 \
        --sid CDB26 --pdb FREEPDB1 --instance-id "$INST" --host-ip 10.0.1.10 -c "$COMP" \
        --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [ "$(jq -r '.displayName' <<< "$output")" = "demo_CDB26_FREEPDB1" ]
}

@test "ds_target_register: --type compute without --instance-id fails before any OCI call" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --type compute -H demovm --sid CDB19 --pdb PDB1 \
        --host-ip 10.0.1.10 -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required option for --type compute: --instance-id OCID"* ]]
    [ ! -s "${OCI_LOG}" ]
}

@test "ds_target_register: --type compute rejects a non-instance OCID" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --type compute -H demovm --sid CDB19 --pdb PDB1 \
        --instance-id ocid1.vmcluster.oc1..x --host-ip 10.0.1.10 -c "$COMP" --connector demo-conn -P s -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"expected a compute instance OCID"* ]]
}

@test "ds_target_register: --type compute|onprem without --host-ip fails" {
    _fake_oci_setup
    local t
    for t in compute onprem; do
        run "${BIN_DIR}/ds_target_register.sh" --type "$t" -H demovm --sid CDB19 --pdb PDB1 \
            --instance-id "$INST" -c "$COMP" --connector demo-conn -P secret123 -n
        [ "$status" -eq 1 ]
        [[ "$output" == *"Missing required option for --type ${t}: --host-ip IP"* ]]
    done
}

@test "ds_target_register: --type onprem without connector names the fix" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --type onprem -H dbhost01 --sid CDB01 --pdb APP1 \
        --host-ip 10.1.1.1 -c "$COMP" -P secret123 -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing connector. Use --connector"* ]]
}

@test "ds_target_register: --type onprem without -c and without defaults fails" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --type onprem -H dbhost01 --sid CDB01 --pdb APP1 \
        --host-ip 10.1.1.1 --connector demo-conn -P secret123 -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing compartment for --type onprem"* ]]
}

@test "ds_target_register: invalid --type and non-numeric --port are rejected" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --type adb -H x --sid CDB01 --pdb APP1 -P s -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid --type 'adb'. Use one of: exacc, compute, onprem"* ]]

    run "${BIN_DIR}/ds_target_register.sh" --type onprem -H x --sid CDB01 --pdb APP1 \
        --host-ip 10.1.1.1 --port abc -P s -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid --port 'abc'"* ]]
}

@test "ds_target_register: --cluster with --type onprem is ignored with a warning" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type onprem -H dbhost01 --cluster vmc01 \
        --sid CDB01 --pdb APP1 --host-ip 10.1.1.1 -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Ignoring --cluster 'vmc01': only used with --type exacc"* ]]
    [ "$(jq -r '.displayName' <<< "$output")" = "dbhost01_CDB01_APP1" ]
}

@test "ds_target_register: default type stays exacc (DATABASE_CLOUD_SERVICE / CLOUD_AT_CUSTOMER)" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" -H db01 --sid cdb01 --root \
        --cluster ocid1.vmcluster.oc1..vmc -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [ "$(jq -r '.databaseDetails.databaseType' <<< "$output")" = "DATABASE_CLOUD_SERVICE" ]
    [ "$(jq -r '.databaseDetails.infrastructureType' <<< "$output")" = "CLOUD_AT_CUSTOMER" ]
    [ "$(jq -r '.databaseDetails.vmClusterId' <<< "$output")" = "ocid1.vmcluster.oc1..vmc" ]
    [ "$(jq -r '.databaseDetails | has("ipAddresses") or has("instanceId")' <<< "$output")" = "false" ]
    [ "$(jq -r '.displayName' <<< "$output")" = "ocid1.vmcluster.oc1..vmc_cdb01_CDBROOT" ]
}

@test "ds_target_register: exacc without --host/--cluster keeps the original error" {
    _fake_oci_setup
    run "${BIN_DIR}/ds_target_register.sh" --sid cdb01 --pdb APP1 -P secret123 -n
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing resource identifier. Specify --host or --cluster"* ]]
}

@test "ds_target_register: exacc ignores --host-ip/--instance-id with a warning" {
    _fake_oci_setup
    run --separate-stderr "${BIN_DIR}/ds_target_register.sh" --type exacc -H db01 --sid cdb01 --root \
        --cluster ocid1.vmcluster.oc1..vmc --host-ip 10.0.0.1 --instance-id "$INST" \
        -c "$COMP" --connector demo-conn -P secret123 -n
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Ignoring --host-ip"* ]]
    [[ "$stderr" == *"Ignoring --instance-id"* ]]
    [ "$(jq -r '.databaseDetails | has("ipAddresses")' <<< "$output")" = "false" ]
}

@test "ds_target_register: help documents --type, --instance-id and --host-ip" {
    run "${BIN_DIR}/ds_target_register.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--type TYPE"* ]]
    [[ "$output" == *"--instance-id OCID"* ]]
    [[ "$output" == *"--host-ip IP"* ]]
    [[ "$output" == *"<host>_<sid>_<pdb|CDBROOT>"* ]]
}
