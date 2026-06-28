# Test Suite for odb_datasafe

This directory contains a comprehensive test suite for the OraDBA Data Safe
Extension v0.24.0, built using the [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core) framework.

## 📋 Test Structure

### Test Categories

1. **Library Tests** (`lib_*.bats`)
   - `lib_common.bats` - Tests for `lib/common.sh` utility functions
   - `lib_oci_cli_auth.bats` - Tests for OCI CLI authentication helpers
   - `lib_oci_helpers.bats` - Tests for `lib/oci_helpers.sh` OCI integration functions
     - Resolution helper functions (`resolve_compartment_to_vars`, `resolve_target_to_vars`)
     - `oci_exec_ro()` function for read-only operations
     - Error handling (functions return error codes instead of die)
   - `lib_ssh_helpers.bats` - Tests for `lib/ssh_helpers.sh` SSH remote execution

2. **Script Tests** (`script_*.bats`)
   - `script_ds_connector_update.bats` - Tests for connector update functionality
   - `script_ds_find_untagged_targets.bats` - Tests for untagged target discovery
   - `script_ds_target_activate.bats` - Tests for target activation
   - `script_ds_target_audit_trail.bats` - Tests for audit trail management
   - `script_ds_target_connect_details.bats` - Tests for connection detail display
   - `script_ds_target_connector_summary.bats` - Tests for connector summary reporting
   - `script_ds_target_delete.bats` - Tests for target deletion
   - `script_ds_target_details.bats` - Tests for target detail display
   - `script_ds_target_export.bats` - Tests for target export functionality
   - `script_ds_target_list.bats` - Tests for target listing functionality
   - `script_ds_target_list_connector.bats` - Tests for connector-based target listing
   - `script_ds_target_move.bats` - Tests for target compartment move
   - `script_ds_target_refresh.bats` - Tests for target credential refresh
   - `script_ds_target_register.bats` - Tests for target registration
   - `script_ds_target_update_connector.bats` - Tests for connector management
   - `script_ds_target_update_credentials.bats` - Tests for credential updates
   - `script_ds_target_update_service.bats` - Tests for service configuration update
   - `script_ds_target_update_tags.bats` - Tests for tag management
   - `script_ds_tg_report.bats` - Tests for target group reporting
   - `script_template.bats` - Tests for TEMPLATE.sh standardization compliance

3. **Integration Tests** (`integration_*.bats`)
   - `integration_tests.bats` - End-to-end workflow and cross-component tests
   - `integration_param_combinations.bats` - Parameter combinations and error handling tests

4. **Edge Case Tests**
   - `edge_case_tests.bats` - Edge cases, boundary conditions, and unusual inputs

5. **Installer Tests**
   - `install_datasafe_service.bats` - Installer regression tests (REG-001..REG-006)
   - `uninstall_all_datasafe_services.bats` - Uninstaller tests

6. **Compatibility Tests**
   - `bash42_compatibility.bats` - Bash 4.2+ compatibility checks

7. **Utility Tests**
   - `template_helpers.bats` - Build and framework validation tests
   - `basic_functionality.bats` - Core functionality and smoke tests
   - `quick_validation.bats` - Fast validation tests for CI/CD

## 🚀 Running Tests

### Prerequisites

Install BATS and dependencies:

```bash
# macOS with Homebrew
brew install bats-core gnu-parallel jq

# Ubuntu/Debian
sudo apt update
sudo apt install bats parallel jq

# Using npm (cross-platform)
npm install -g bats
```

### Quick Start

```bash
# Run all tests
make test

# Or use the test runner directly
./tests/run_tests.sh
```

### Advanced Usage

```bash
# Run specific test categories
./tests/run_tests.sh lib                    # Library tests only
./tests/run_tests.sh scripts                # Script tests only
./tests/run_tests.sh integration            # Integration tests only

# Run specific test files
./tests/run_tests.sh lib_common.bats
./tests/run_tests.sh script_ds_target_list.bats

# Verbose output
./tests/run_tests.sh -v

# Parallel execution (faster)
./tests/run_tests.sh -p

# Generate JUnit XML output
./tests/run_tests.sh -j

# Coverage report
./tests/run_tests.sh -c
```

## 🧪 Test Coverage

The test suite provides comprehensive coverage across multiple dimensions:

### Test Statistics (v0.24.0)

- **Total Tests**: 346
- **Test Files**: 33
- **Test Execution Time**: ~17 seconds
- **Scripts Covered**: 30
- **Library Functions**: ~80+

### Functional Coverage

- ✅ **CLI Argument Parsing** - All option combinations and validation
- ✅ **Configuration Loading** - Environment files, CLI overrides, defaults
- ✅ **OCI Integration** - API calls, response handling, error conditions
- ✅ **Data Safe Operations** - Target management, tag updates, connector assignments
- ✅ **Output Formats** - JSON, CSV, table, count modes
- ✅ **Error Handling** - Invalid inputs, missing resources, API failures
- ✅ **Resolution Patterns** - Name/OCID dual resolution for compartments and targets
- ✅ **Dry-Run Mode** - Read-only operations work, write operations blocked
- ✅ **Edge Cases** - Boundary conditions, unusual inputs, error paths (new 2026-02-11)
- ✅ **Parameter Combinations** - Complex option combinations, integration scenarios (new 2026-02-11)

### Library Function Coverage

- ✅ **common.sh functions**: `log_*`, `is_ocid`, `require_cmd`, `init_config`, etc.
- ✅ **oci_helpers.sh functions**: `oci_exec`, `oci_exec_ro`, `oci_resolve_*`, `ds_*`, etc.
- ✅ **ssh_helpers.sh functions**: remote execution, file transfer, and connectivity checks
- ✅ **Resolution helpers**:
  - `resolve_compartment_to_vars()` - Resolves compartment name or OCID to both NAME and OCID
  - `resolve_target_to_vars()` - Resolves target name or OCID to both NAME and OCID
- ✅ **Integration patterns**: Library loading, function composition, error propagation
- ✅ **Edge cases**: Long strings, empty values, special characters (new 2026-02-11)

### Script Coverage

- ✅ **ds_target_list.sh**: Count/details modes, filtering, output formats
- ✅ **ds_target_update_tags.sh**: Environment detection, tag application, dry-run/apply
- ✅ **ds_target_update_credentials.sh**: Credential sources, security, target selection
- ✅ **ds_target_update_connector.sh**: Set/migrate/distribute modes, connector resolution
- ✅ **ds_target_register.sh**: Registration validation, OCID resolution, dry-run
- ✅ **ds_find_untagged_targets.sh**: Tag namespace filtering, output formats
- ✅ **TEMPLATE.sh**: Standardization compliance verification

## 🔧 Test Architecture

### Mock OCI CLI

All tests use a comprehensive mock OCI CLI that:

- ✅ Simulates realistic API responses
- ✅ Supports all required Data Safe operations
- ✅ Handles compartment resolution and target queries
- ✅ Provides consistent test data across test suites

### Test Environment

Each test runs in an isolated environment with:

- ✅ Temporary directories for config and data files
- ✅ Mock OCI CLI in PATH precedence
- ✅ Controlled environment variables
- ✅ Automatic cleanup after each test

### Test Data

Consistent test data across all suites:

```text
Compartments:
- ocid1.compartment.oc1..test-root (DS_ROOT_COMP)
- ocid1.compartment.oc1..prod-comp (cmp-lzp-dbso-prod-projects)
- ocid1.compartment.oc1..test-comp (cmp-lzp-dbso-test-projects)

Targets:
- test-target-1, test-target-2 (various states and configurations)
- integration-target-1, integration-target-2 (for integration tests)

Connectors:
- test-connector-1, test-connector-2, test-connector-3
- integration-connector-1, integration-connector-2
```

## 📊 Test Results

### Test Execution

```bash
# Example test run output
OraDBA Data Safe Test Runner v0.2.0
==============================================

Running 8 test files...
✅ lib_common.bats
✅ lib_oci_helpers.bats  
✅ script_ds_target_list.bats
✅ script_ds_target_update_tags.bats
✅ script_ds_target_update_credentials.bats
✅ script_ds_target_update_connector.bats
✅ integration_tests.bats
✅ template_helpers.bats

✅ All tests passed!
Test execution time: 12 seconds
```

### Coverage Report

The test runner can generate coverage reports showing:

- Total library functions vs functions with tests
- Estimated test coverage percentage
- Detailed coverage by component

## 🐛 Debugging Tests

### Verbose Output

```bash
# See detailed test execution
./tests/run_tests.sh -v

# Debug specific test
bats -v tests/lib_common.bats
```

### Test Debugging

```bash
# Run single test with debugging
bats --verbose-run tests/script_ds_target_list.bats

# Check mock OCI calls (shown in STDERR)
./tests/run_tests.sh -v 2>&1 | grep MOCK_OCI_CALL
```

### Manual Testing

```bash
# Set up test environment manually
export TEST_TEMP_DIR="/tmp/bats-test"
mkdir -p "$TEST_TEMP_DIR/bin"

# Copy mock OCI CLI
cp tests/mock_oci.sh "$TEST_TEMP_DIR/bin/oci"
chmod +x "$TEST_TEMP_DIR/bin/oci"

# Test scripts with mock environment
PATH="$TEST_TEMP_DIR/bin:$PATH" ./bin/ds_target_list.sh --help
```

## 🔄 Continuous Integration

### Integration with Make

The test suite integrates with the project Makefile:

```bash
make test           # Run all tests
make lint           # Run linting
make build          # Build and test
```

### CI/CD Pipeline

For automated testing in CI/CD:

```yaml
# Example GitHub Actions step
- name: Run Test Suite
  run: |
    make test
    
# With JUnit output for reporting
- name: Run Tests with Reporting
  run: |
    ./tests/run_tests.sh -j
    
- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: test-results/
```

## 🎯 Best Practices

### Writing New Tests

1. **Follow naming conventions**: `test_category_component.bats`
2. **Use descriptive test names**: `@test "script validates required arguments"`
3. **Test both success and failure cases**
4. **Use setup/teardown for consistent environments**
5. **Keep tests focused and atomic**

### Test Organization

1. **Group related tests** in the same file
2. **Use consistent mock data** across test suites
3. **Test integration points** between components
4. **Verify error messages** and exit codes
5. **Test edge cases** and boundary conditions

### Performance

1. **Use parallel execution** for faster test runs
2. **Mock external dependencies** (OCI CLI, network calls)
3. **Clean up resources** in teardown functions
4. **Avoid unnecessary file I/O** in test loops
5. **Profile test execution** to identify bottlenecks

## 📚 References

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS GitHub Repository](https://github.com/bats-core/bats-core)
- [Bash Testing Best Practices](https://www.gnu.org/software/bash/manual/bash.html)
- [Oracle Cloud Infrastructure CLI](https://docs.oracle.com/en-us/iaas/tools/oci-cli/)

---

The test suite ensures the reliability and maintainability of the odb_datasafe
framework by providing comprehensive automated validation of all components and
workflows.
