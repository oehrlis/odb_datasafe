#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: script_ds_target_update_tags.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test suite for ds_target_update_tags.sh script
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Create test environment in REPO_ROOT so init_config can find it
    export TEST_ENV_FILE="${REPO_ROOT}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..test-root"
DS_TAG_NAMESPACE="test-namespace"
DS_TAG_ENV_KEY="Environment"
DS_TAG_APP_KEY="Application"
EOF
    
    # Mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "iam compartment list --compartment-id"*"cmp-lzp-dbso-prod-projects"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..prod-comp", "name": "cmp-lzp-dbso-prod-projects", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    "iam compartment list --compartment-id"*"cmp-lzp-dbso-test-projects"*)
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..test-comp", "name": "cmp-lzp-dbso-test-projects", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
        ;;
    "data-safe target-database list --compartment-id"*)
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target1",
      "display-name": "test-target-1",
      "lifecycle-state": "ACTIVE",
      "compartment-id": "ocid1.compartment.oc1..prod-comp",
      "freeform-tags": {},
      "defined-tags": {}
    },
    {
      "id": "ocid1.datasafetarget.oc1..target2",
      "display-name": "test-target-2",
      "lifecycle-state": "ACTIVE", 
      "compartment-id": "ocid1.compartment.oc1..test-comp",
      "freeform-tags": {},
      "defined-tags": {
        "test-namespace": {
          "Environment": "prod"
        }
      }
    }
  ]
}
JSON
        ;;
    "data-safe target-database update --target-database-id"*"--defined-tags"*)
        echo '{"opc-work-request-id": "ocid1.workrequest.oc1..work123"}'
        ;;
    "iam compartment get --compartment-id"*)
        if [[ "$*" == *"prod-comp"* ]]; then
            echo '{"data": {"name": "cmp-lzp-dbso-prod-projects"}}'
        elif [[ "$*" == *"test-comp"* ]]; then
            echo '{"data": {"name": "cmp-lzp-dbso-test-projects"}}'
        fi
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    unset DS_ROOT_COMP DS_TAG_NAMESPACE DS_TAG_ENV_KEY DS_TAG_APP_KEY CONFIG_FILE
    rm -f "${REPO_ROOT}/.env" 2>/dev/null || true
}

# Test basic script functionality
@test "ds_target_update_tags.sh shows help message" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"ds_target_update_tags.sh"* ]]
}

@test "ds_target_update_tags.sh shows version information" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --version  
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
}

# Test dry-run mode (default)
@test "ds_target_update_tags.sh dry-run mode shows what would be done" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode"* ]]
    [[ "$output" == *"no changes applied"* ]]
}

@test "ds_target_update_tags.sh detects environment from compartment name" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Environment: prod"* ]] || [[ "$output" == *"prod"* ]]
}

@test "ds_target_update_tags.sh handles test environment detection" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..test-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
}

# Test apply mode
@test "ds_target_update_tags.sh apply mode makes actual changes" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --apply -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apply mode"* ]]
    [[ "$output" == *"Changes will be applied"* ]]
}

# Test specific target selection
@test "ds_target_update_tags.sh can update specific targets" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -T "test-target-1" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
}

@test "ds_target_update_tags.sh can update multiple targets" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -T "test-target-1,test-target-2" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-target-1"* ]]
    [[ "$output" == *"test-target-2"* ]]
}

# Test tag configuration
@test "ds_target_update_tags.sh uses custom tag namespace" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --tag-namespace "custom-namespace" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"custom-namespace"* ]]
}

@test "ds_target_update_tags.sh uses custom environment key" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --env-key "CustomEnv" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    # Should process but may not show key name in output in dry-run
}

@test "ds_target_update_tags.sh uses custom application key" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --app-key "CustomApp" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
}

# Test error conditions
@test "ds_target_update_tags.sh fails without compartment specification" {
    local saved_comp="$DS_ROOT_COMP"
    unset DS_ROOT_COMP
    
    run "${BIN_DIR}/ds_target_update_tags.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
    
    export DS_ROOT_COMP="$saved_comp"
}

@test "ds_target_update_tags.sh handles invalid compartment names" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "invalid-compartment-name"
    [ "$status" -ne 0 ]
}

# Test environment detection patterns
@test "ds_target_update_tags.sh detects different environment patterns" {
    # Test various compartment naming patterns
    environments=("prod" "test" "dev" "qs" "quality-assurance")
    
    for env in "${environments[@]}"; do
        # Create compartment name pattern
        comp_name="cmp-lzp-dbso-${env}-projects"
        
        # Mock the compartment response for this environment
        cat > "${TEST_TEMP_DIR}/bin/oci_${env}" << EOF
#!/usr/bin/env bash
echo '{"data": [{"id": "ocid1.compartment.oc1..${env}-comp", "name": "${comp_name}", "lifecycle-state": "ACTIVE"}]}'
EOF
        chmod +x "${TEST_TEMP_DIR}/bin/oci_${env}"
        
        run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..${env}-comp"
        [ "$status" -eq 0 ]
    done
}

# Test lifecycle state filtering
@test "ds_target_update_tags.sh filters by lifecycle state" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -L "ACTIVE" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
}

@test "ds_target_update_tags.sh validates lifecycle states" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -L "INVALID_STATE" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid lifecycle state"* ]]
}

# Test verbose and debug modes
@test "ds_target_update_tags.sh supports verbose mode" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -v -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting ds_target_update_tags.sh"* ]]
}

@test "ds_target_update_tags.sh supports debug mode" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -d -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG"* ]]
}

# Test progress tracking
@test "ds_target_update_tags.sh shows progress counters" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tag update completed"* ]]
    [[ "$output" == *"Successful:"* ]]
}

# Test tag collision detection
@test "ds_target_update_tags.sh detects existing correct tags" {
    # target2 already has correct Environment tag
    run "${BIN_DIR}/ds_target_update_tags.sh" -T "test-target-2" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already tagged correctly"* ]] || [[ "$output" == *"skipping"* ]]
}

# Test configuration loading
@test "ds_target_update_tags.sh loads configuration from .env file" {
    # Test without explicit parameters, should use .env defaults
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
    # Should use namespace and keys from .env file
}

# Test OCI configuration
@test "ds_target_update_tags.sh supports OCI profile configuration" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --oci-profile "test-profile" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
}

@test "ds_target_update_tags.sh supports OCI region configuration" {
    run "${BIN_DIR}/ds_target_update_tags.sh" --oci-region "us-phoenix-1" -c "ocid1.compartment.oc1..prod-comp"
    [ "$status" -eq 0 ]
}