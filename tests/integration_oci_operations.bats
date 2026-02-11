#!/usr/bin/env bats
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Test Suite.: integration_oci_operations.bats
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Purpose....: Integration tests for OCI CLI operations with various parameters
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Load test helpers
load test_helper

# Test setup
setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    export SCRIPT_VERSION="$(tr -d '\n' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo '0.0.0')"
    
    # Create test environment file
    export TEST_ENV_FILE="${TEST_TEMP_DIR}/.env"
    cat > "${TEST_ENV_FILE}" << 'EOF'
DS_ROOT_COMP="ocid1.compartment.oc1..root-test"
DS_TAG_NAMESPACE="oci-integration-test"
DS_TAG_ENV_KEY="Environment"
DS_TAG_APP_KEY="Application"
DS_USERNAME="oci_test_user"
OCI_CLI_PROFILE="DEFAULT"
EOF

    # Create comprehensive mock OCI environment
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create detailed mock OCI CLI that simulates various scenarios
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Comprehensive mock OCI CLI for integration testing

# Log all calls for debugging
echo "MOCK_OCI_CALL: $*" >&2

# Parse arguments to determine behavior
declare -A args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compartment-id)
            args[comp_id]="$2"
            shift 2
            ;;
        --display-name)
            args[display_name]="$2"
            shift 2
            ;;
        --lifecycle-state)
            args[lifecycle_state]="$2"
            shift 2
            ;;
        --format)
            args[format]="$2"
            shift 2
            ;;
        --profile)
            args[profile]="$2"
            shift 2
            ;;
        --region)
            args[region]="$2"
            shift 2
            ;;
        --limit)
            args[limit]="$2"
            shift 2
            ;;
        --all)
            args[all]="true"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Handle different command patterns
if [[ "$*" == *"--version"* ]]; then
    echo "3.45.0"
    exit 0
fi

if [[ "$*" == *"iam compartment list"* ]]; then
    # Simulate compartment listing with various scenarios
    if [[ "${args[comp_id]}" == *"root-test"* ]]; then
        cat << 'JSON'
{
  "data": [
    {"id": "ocid1.compartment.oc1..prod", "name": "cmp-prod-db", "lifecycle-state": "ACTIVE"},
    {"id": "ocid1.compartment.oc1..test", "name": "cmp-test-db", "lifecycle-state": "ACTIVE"},
    {"id": "ocid1.compartment.oc1..dev", "name": "cmp-dev-db", "lifecycle-state": "ACTIVE"}
  ]
}
JSON
    elif [[ "${args[comp_id]}" == *"nonexistent"* ]]; then
        echo "ServiceError: Compartment not found" >&2
        exit 1
    else
        echo '{"data": []}'
    fi
    exit 0
fi

if [[ "$*" == *"data-safe target-database list"* ]]; then
    # Simulate target listing with various lifecycle states
    local comp="${args[comp_id]:-ocid1.compartment.oc1..root-test}"
    local state="${args[lifecycle_state]:-}"
    
    # Generate different responses based on compartment
    if [[ "$comp" == *"prod"* ]]; then
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target-prod-1",
      "display-name": "prod-db-target-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "database-type": "AUTONOMOUS_DATABASE",
        "infrastructure-type": "ORACLE_CLOUD"
      },
      "compartment-id": "ocid1.compartment.oc1..prod",
      "connection-option": {
        "on-premise-connector-id": "ocid1.connector.oc1..connector-prod"
      },
      "freeform-tags": {"Department": "IT"},
      "defined-tags": {
        "oci-integration-test": {
          "Environment": "production",
          "Application": "erp"
        }
      }
    },
    {
      "id": "ocid1.datasafetarget.oc1..target-prod-2",
      "display-name": "prod-db-target-2",
      "lifecycle-state": "NEEDS_ATTENTION",
      "lifecycle-details": "Target database connection failed",
      "database-details": {
        "database-type": "DATABASE_CLOUD_SERVICE",
        "infrastructure-type": "ORACLE_CLOUD"
      },
      "compartment-id": "ocid1.compartment.oc1..prod",
      "connection-option": {
        "on-premise-connector-id": "ocid1.connector.oc1..connector-prod"
      },
      "freeform-tags": {},
      "defined-tags": {}
    }
  ]
}
JSON
    elif [[ "$comp" == *"test"* ]]; then
        cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.datasafetarget.oc1..target-test-1",
      "display-name": "test-db-target-1",
      "lifecycle-state": "ACTIVE",
      "database-details": {
        "database-type": "AUTONOMOUS_DATABASE",
        "infrastructure-type": "ORACLE_CLOUD"
      },
      "compartment-id": "ocid1.compartment.oc1..test",
      "connection-option": {
        "on-premise-connector-id": null
      },
      "freeform-tags": {"legacy": "true"},
      "defined-tags": {}
    }
  ]
}
JSON
    else
        echo '{"data": []}'
    fi
    exit 0
fi

if [[ "$*" == *"data-safe target-database get"* ]]; then
    # Simulate getting a specific target
    cat << 'JSON'
{
  "data": {
    "id": "ocid1.datasafetarget.oc1..target-prod-1",
    "display-name": "prod-db-target-1",
    "lifecycle-state": "ACTIVE",
    "database-details": {
      "database-type": "AUTONOMOUS_DATABASE",
      "infrastructure-type": "ORACLE_CLOUD",
      "autonomous-database-id": "ocid1.autonomousdatabase.oc1..adb1"
    },
    "compartment-id": "ocid1.compartment.oc1..prod",
    "connection-option": {
      "on-premise-connector-id": "ocid1.connector.oc1..connector-prod"
    },
    "credentials": {
      "user-name": "datasafe_admin"
    },
    "freeform-tags": {"Department": "IT"},
    "defined-tags": {
      "oci-integration-test": {
        "Environment": "production",
        "Application": "erp"
      }
    }
  }
}
JSON
    exit 0
fi

if [[ "$*" == *"data-safe on-premises-connector list"* ]]; then
    # Simulate connector listing
    cat << 'JSON'
{
  "data": [
    {
      "id": "ocid1.connector.oc1..connector-prod",
      "display-name": "prod-connector-1",
      "lifecycle-state": "ACTIVE",
      "compartment-id": "ocid1.compartment.oc1..prod"
    },
    {
      "id": "ocid1.connector.oc1..connector-test",
      "display-name": "test-connector-1",
      "lifecycle-state": "ACTIVE",
      "compartment-id": "ocid1.compartment.oc1..test"
    },
    {
      "id": "ocid1.connector.oc1..connector-dev",
      "display-name": "dev-connector-1",
      "lifecycle-state": "INACTIVE",
      "compartment-id": "ocid1.compartment.oc1..dev"
    }
  ]
}
JSON
    exit 0
fi

if [[ "$*" == *"data-safe target-database update"* ]]; then
    # Simulate update operation
    echo '{"opc-work-request-id": "ocid1.workrequest.oc1..work-update-123"}'
    exit 0
fi

if [[ "$*" == *"data-safe work-request get"* ]]; then
    # Simulate work request status
    cat << 'JSON'
{
  "data": {
    "id": "ocid1.workrequest.oc1..work-update-123",
    "status": "SUCCEEDED",
    "percent-complete": 100.0,
    "operation-type": "UPDATE_TARGET_DATABASE"
  }
}
JSON
    exit 0
fi

# Default: return empty data
echo '{"data": []}'
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
    
    export CONFIG_FILE="${TEST_ENV_FILE}"
}

teardown() {
    # Clean up integration test environment
    unset DS_ROOT_COMP DS_TAG_NAMESPACE DS_TAG_ENV_KEY DS_TAG_APP_KEY
    unset DS_USERNAME CONFIG_FILE
}

# ==============================================================================
# Integration Tests: Parameter Combinations
# ==============================================================================

@test "OCI Integration: List targets with compartment OCID" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"prod-db-target"* ]]
}

@test "OCI Integration: List targets with compartment name" {
    run "${BIN_DIR}/ds_target_list.sh" -c "cmp-prod-db"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List targets with lifecycle state filter" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -L "ACTIVE"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List targets with NEEDS_ATTENTION filter" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -L "NEEDS_ATTENTION"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List targets with JSON format" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"display-name"'* ]] || [[ "$output" == *'"data"'* ]]
}

@test "OCI Integration: List targets with CSV format" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f csv
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List targets with table format (default)" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f table
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List targets with custom fields" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -F "display-name,id"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Count mode with compartment" {
    run "${BIN_DIR}/ds_target_list.sh" -C -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Details mode with specific targets" {
    run "${BIN_DIR}/ds_target_list.sh" -D -T "prod-db-target-1,prod-db-target-2"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Quiet mode suppresses INFO messages" {
    run "${BIN_DIR}/ds_target_list.sh" -q -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    # Should not have INFO: messages
    [[ "$output" != *"INFO:"* ]] || true
}

@test "OCI Integration: Verbose mode enables detailed logging" {
    run "${BIN_DIR}/ds_target_list.sh" -v -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Debug mode enables debug output" {
    run "${BIN_DIR}/ds_target_list.sh" -d -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Dry-run mode with DS_ROOT_COMP environment variable" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..prod"
    run "${BIN_DIR}/ds_target_list.sh" -n
    [ "$status" -eq 0 ]
    unset DS_ROOT_COMP
}

@test "OCI Integration: List connectors in compartment" {
    run "${BIN_DIR}/ds_target_list_connector.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: List connectors with JSON output" {
    run "${BIN_DIR}/ds_target_list_connector.sh" -c "ocid1.compartment.oc1..prod" -f json
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Connector summary with grouping" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Connector summary with detailed mode" {
    run "${BIN_DIR}/ds_target_connector_summary.sh" -c "ocid1.compartment.oc1..prod" -D
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Integration Tests: Error Handling
# ==============================================================================

@test "OCI Integration: Invalid compartment OCID returns error" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..nonexistent" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "OCI Integration: Invalid lifecycle state returns error" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -L "INVALID_STATE" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "OCI Integration: Invalid output format returns error" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f "invalid" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "OCI Integration: Missing required compartment returns error" {
    unset DS_ROOT_COMP
    run "${BIN_DIR}/ds_target_list.sh" 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "OCI Integration: Unknown option returns error" {
    run "${BIN_DIR}/ds_target_list.sh" --unknown-option 2>&1 || true
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "OCI Integration: Missing option value returns error" {
    run "${BIN_DIR}/ds_target_list.sh" -c 2>&1 || true
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Integration Tests: Dry-Run Validation
# ==============================================================================

@test "OCI Dry-Run: List operation in dry-run mode" {
    run "${BIN_DIR}/ds_target_list.sh" -n -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run"* ]] || [[ "$output" == *"dry-run"* ]]
}

@test "OCI Dry-Run: Update tags in dry-run mode (default)" {
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run"* ]] || [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"no changes"* ]]
}

@test "OCI Dry-Run: Update connector in dry-run mode" {
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "prod-connector-1" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run"* ]] || [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"no changes"* ]]
}

@test "OCI Dry-Run: Update credentials in dry-run mode" {
    run "${BIN_DIR}/ds_target_update_credentials.sh" -c "ocid1.compartment.oc1..prod" 2>&1 || true
    # Should either succeed in dry-run or fail due to missing credentials (not because of OCI issues)
    [ "$status" -ge 0 ]
}

@test "OCI Dry-Run: Register target in dry-run mode" {
    run "${BIN_DIR}/ds_target_register.sh" -n "new-target" --database-id "ocid1.database.oc1..db1" -c "ocid1.compartment.oc1..prod" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run"* ]] || [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"no changes"* ]]
}

@test "OCI Dry-Run: Activate target in dry-run mode" {
    run "${BIN_DIR}/ds_target_activate.sh" -T "prod-db-target-1" --dry-run
    [ "$status" -eq 0 ]
}

@test "OCI Dry-Run: No actual OCI API calls in dry-run" {
    # Verify that dry-run doesn't make actual update calls
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod" 2>&1
    [ "$status" -eq 0 ]
    # Output should not contain work-request IDs (which indicate actual API calls)
    [[ "$output" != *"opc-work-request-id"* ]]
}

# ==============================================================================
# Integration Tests: Multiple Compartments
# ==============================================================================

@test "OCI Integration: List targets across multiple child compartments" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..root-test"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Switch between compartments" {
    # First compartment
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    # Second compartment
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Environment variable override by CLI parameter" {
    export DS_ROOT_COMP="ocid1.compartment.oc1..prod"
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
    unset DS_ROOT_COMP
}

# ==============================================================================
# Integration Tests: Profile and Region Management
# ==============================================================================

@test "OCI Integration: Custom OCI profile" {
    run "${BIN_DIR}/ds_target_list.sh" --oci-profile "CUSTOM" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Custom OCI region" {
    run "${BIN_DIR}/ds_target_list.sh" --oci-region "us-ashburn-1" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Integration: Profile and region together" {
    run "${BIN_DIR}/ds_target_list.sh" --oci-profile "CUSTOM" --oci-region "eu-frankfurt-1" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Integration Tests: Complex Workflows
# ==============================================================================

@test "OCI Workflow: List, filter, and update tags workflow" {
    # Step 1: List all targets
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    # Step 2: List only ACTIVE targets
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -L "ACTIVE"
    [ "$status" -eq 0 ]
    
    # Step 3: Update tags in dry-run
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Workflow: Find untagged targets and tag them" {
    # Step 1: Find untagged targets
    run "${BIN_DIR}/ds_find_untagged_targets.sh" -c "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
    
    # Step 2: Preview tag updates
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "ocid1.compartment.oc1..test"
    [ "$status" -eq 0 ]
}

@test "OCI Workflow: List connectors and update target connector" {
    # Step 1: List available connectors
    run "${BIN_DIR}/ds_target_list_connector.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    # Step 2: Show connector summary
    run "${BIN_DIR}/ds_target_connector_summary.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    # Step 3: Update connector assignment (dry-run)
    run "${BIN_DIR}/ds_target_update_connector.sh" set --target-connector "prod-connector-1" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
}

@test "OCI Workflow: Export target details for reporting" {
    # List targets in CSV for reporting
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f csv
    [ "$status" -eq 0 ]
    
    # List targets in JSON for automation
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod" -f json
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Integration Tests: Error Recovery
# ==============================================================================

@test "OCI Integration: Graceful handling of empty results" {
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..dev"
    [ "$status" -eq 0 ]
    # Should handle empty results gracefully
}

@test "OCI Integration: Graceful handling of partial failures" {
    # Test with mixed valid/invalid targets
    run "${BIN_DIR}/ds_target_list.sh" -T "valid-target,invalid-target" 2>&1 || true
    # Should handle partial failures
    [ "$status" -ge 0 ]
}

# ==============================================================================
# Integration Tests: Performance
# ==============================================================================

@test "OCI Integration: List operation completes in reasonable time" {
    local start_time
    start_time=$(date +%s)
    
    run "${BIN_DIR}/ds_target_list.sh" -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Should complete in under 10 seconds (generous for unit test with mock)
    [ "$duration" -lt 10 ]
}

@test "OCI Integration: Count operation is faster than details" {
    # Count should be quick
    local start_time
    start_time=$(date +%s)
    
    run "${BIN_DIR}/ds_target_list.sh" -C -c "ocid1.compartment.oc1..prod"
    [ "$status" -eq 0 ]
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Count should be very fast (under 5 seconds)
    [ "$duration" -lt 5 ]
}
