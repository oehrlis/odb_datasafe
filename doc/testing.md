# Testing Guide for odb_datasafe

## Overview

The `odb_datasafe` extension includes a comprehensive test suite built with
[BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core).
This guide explains the testing strategy, architecture, and best practices for
writing and running tests.

## Table of Contents

- [Quick Start](#quick-start)
- [Test Architecture](#test-architecture)
- [Test Categories](#test-categories)
- [Writing Tests](#writing-tests)
- [Mocking Strategy](#mocking-strategy)
- [Running Tests](#running-tests)
- [Debugging Tests](#debugging-tests)
- [CI/CD Integration](#cicd-integration)
- [Test Coverage](#test-coverage)
- [Best Practices](#best-practices)

## Quick Start

### Prerequisites

Install BATS and dependencies:

```bash
# macOS with Homebrew
brew install bats-core jq shellcheck

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y bats jq shellcheck

# Using npm (cross-platform)
npm install -g bats
```

### Running Tests

```bash
# Run all tests (excluding integration tests)
make test

# Run all tests including integration tests
make test-all

# Run specific test file
bats tests/edge_case_tests.bats

# Run with verbose output
bats -t tests/integration_oci_operations.bats
```

## Test Architecture

### Directory Structure

```text
tests/
├── README.md                           # Test suite overview
├── test_helper.bash                    # Common test helper functions
├── run_tests.sh                        # Test runner script
│
├── lib_*.bats                          # Library function tests
│   ├── lib_common.bats                 # Tests for lib/common.sh
│   └── lib_oci_helpers.bats            # Tests for lib/oci_helpers.sh
│
├── script_*.bats                       # Script-specific tests
│   ├── script_ds_target_list.bats      # Tests for ds_target_list.sh
│   ├── script_ds_target_update_*.bats  # Tests for update scripts
│   └── script_ds_find_*.bats           # Tests for utility scripts
│
├── integration_*.bats                  # Integration tests
│   ├── integration_tests.bats          # Cross-component integration
│   └── integration_oci_operations.bats # OCI CLI integration tests
│
├── edge_case_tests.bats                # Edge case and boundary tests
└── quick_validation.bats               # Fast smoke tests
```

### Test Phases

Each test follows this lifecycle:

1. **Setup** - Create test environment, mock OCI CLI, set variables
2. **Execution** - Run the script or function under test
3. **Assertion** - Verify expected output and behavior
4. **Teardown** - Clean up temporary files and environment

### Mock Environment

All tests use a comprehensive mocking system:

- **Mock OCI CLI** - Simulates OCI API responses without real API calls
- **Isolated Environment** - Each test runs in a temporary directory
- **Controlled Variables** - Tests set specific environment variables
- **Consistent Test Data** - Predictable compartments, targets, and connectors

## Test Categories

### 1. Library Tests (`lib_*.bats`)

Test individual library functions in isolation.

**Purpose:**
- Verify utility functions work correctly
- Test error handling in library code
- Validate input parsing and validation
- Test resolution helper functions

**Example:**

```bash
@test "lib/common.sh is_ocid validates OCID format" {
    source "${LIB_DIR}/common.sh"
    
    run is_ocid "ocid1.compartment.oc1..aaa123"
    [ "$status" -eq 0 ]
    
    run is_ocid "invalid-ocid"
    [ "$status" -ne 0 ]
}
```

### 2. Script Tests (`script_*.bats`)

Test individual scripts and their command-line interfaces.

**Purpose:**
- Verify CLI argument parsing
- Test help and version output
- Validate script-specific functionality
- Test output formats (JSON, CSV, table)

**Example:**

```bash
@test "ds_target_list.sh shows help message" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
```

### 3. Integration Tests (`integration_*.bats`)

Test complete workflows and cross-component interactions.

**Purpose:**
- Verify end-to-end workflows
- Test multiple scripts working together
- Validate OCI CLI parameter combinations
- Test dry-run and apply modes

**Example:**

```bash
@test "OCI Workflow: List, filter, and update tags" {
    # List all targets
    run "${BIN_DIR}/ds_target_list.sh" -c "$COMPARTMENT"
    [ "$status" -eq 0 ]
    
    # Filter ACTIVE targets
    run "${BIN_DIR}/ds_target_list.sh" -c "$COMPARTMENT" -L "ACTIVE"
    [ "$status" -eq 0 ]
    
    # Update tags in dry-run
    run "${BIN_DIR}/ds_target_update_tags.sh" -c "$COMPARTMENT"
    [ "$status" -eq 0 ]
}
```

### 4. Edge Case Tests (`edge_case_tests.bats`)

Test boundary conditions and unusual inputs.

**Purpose:**
- Test unusual but valid inputs
- Verify error handling for invalid inputs
- Test boundary conditions (max length, empty values)
- Validate concurrent operations

**Example:**

```bash
@test "Edge: Very long compartment name (255 chars)" {
    local long_name=$(printf 'a%.0s' {1..255})
    run "${BIN_DIR}/ds_target_list.sh" -c "$long_name" 2>&1 || true
    [ "$status" -ge 0 ]  # Should handle gracefully
}
```

### 5. Quick Validation Tests (`quick_validation.bats`)

Fast smoke tests for CI/CD pipelines.

**Purpose:**
- Verify basic functionality quickly
- Catch obvious errors early
- Suitable for pre-commit hooks
- Complete in under 30 seconds

## Writing Tests

### Test Structure Template

```bash
#!/usr/bin/env bats
# Test Suite.: my_new_tests.bats
# Author.....: Your Name
# Purpose....: Tests for new functionality

# Load test helpers
load test_helper

setup() {
    export REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export BIN_DIR="${REPO_ROOT}/bin"
    export LIB_DIR="${REPO_ROOT}/lib"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"
    
    # Create mock OCI CLI
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Mock OCI CLI implementation
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/oci"
}

teardown() {
    # Clean up test environment
    unset TEST_TEMP_DIR
}

@test "Test description goes here" {
    run "${BIN_DIR}/my_script.sh" --option value
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
}
```

### Assertion Patterns

```bash
# Exit status assertions
[ "$status" -eq 0 ]       # Success
[ "$status" -ne 0 ]       # Failure
[ "$status" -ge 0 ]       # Any valid exit code

# Output content assertions
[[ "$output" == *"substring"* ]]           # Contains substring
[[ "$output" != *"substring"* ]]           # Doesn't contain
[[ "$output" =~ ^pattern$ ]]               # Regex match

# File assertions
[ -f "$file" ]            # File exists
[ -x "$file" ]            # File is executable
[ -d "$dir" ]             # Directory exists

# Variable assertions
[ -n "$var" ]             # Variable is not empty
[ -z "$var" ]             # Variable is empty
```

### Common Test Helper Functions

Available in `test_helper.bash`:

```bash
# Skip tests based on conditions
skip_if_root                 # Skip if running as root
skip_if_not_root             # Skip if not running as root
skip_if_no_oci_config        # Skip if OCI CLI not configured

# Create test directories
test_dir=$(create_test_dir)
cleanup_test_dir "$test_dir"
```

## Mocking Strategy

### Mock OCI CLI

The mock OCI CLI simulates realistic API responses without making actual OCI API calls.

#### Basic Mock

```bash
cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "3.45.0"
        ;;
    "data-safe target-database list"*)
        echo '{"data": [{"id": "ocid1.test", "display-name": "test"}]}'
        ;;
    *)
        echo '{"data": []}'
        ;;
esac
EOF
chmod +x "${TEST_TEMP_DIR}/bin/oci"
```

#### Advanced Mock with Arguments

```bash
cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
# Log calls for debugging
echo "MOCK_OCI_CALL: $*" >&2

# Parse arguments
declare -A args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compartment-id)
            args[comp_id]="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Return different responses based on arguments
if [[ "${args[comp_id]}" == *"prod"* ]]; then
    echo '{"data": [{"id": "ocid1.prod.1", "display-name": "prod-db"}]}'
else
    echo '{"data": []}'
fi
EOF
chmod +x "${TEST_TEMP_DIR}/bin/oci"
```

#### Mock Error Responses

```bash
cat > "${TEST_TEMP_DIR}/bin/oci" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"nonexistent"* ]]; then
    echo "ServiceError: Compartment not found" >&2
    exit 1
fi
echo '{"data": []}'
EOF
chmod +x "${TEST_TEMP_DIR}/bin/oci"
```

### Mock Test Data

Use consistent test data across all tests:

```bash
# Compartments
ocid1.compartment.oc1..root-test        # Root compartment
ocid1.compartment.oc1..prod             # Production compartment
ocid1.compartment.oc1..test             # Test compartment
ocid1.compartment.oc1..dev              # Development compartment

# Targets
prod-db-target-1                        # Active production target
prod-db-target-2                        # Needs attention target
test-db-target-1                        # Test target

# Connectors
prod-connector-1                        # Production connector
test-connector-1                        # Test connector
dev-connector-1                         # Inactive connector
```

## Running Tests

### Make Targets

```bash
# Run unit tests only (fast, excludes integration)
make test

# Run all tests including integration
make test-all

# Run linting
make lint

# Run formatting check
make format-check

# Run complete CI pipeline
make ci
```

### Direct BATS Execution

```bash
# Run all tests
bats tests/*.bats

# Run specific test file
bats tests/edge_case_tests.bats

# Run with verbose output
bats -t tests/integration_oci_operations.bats

# Run in parallel (faster)
bats -j 4 tests/*.bats

# Run with no temp cleanup (for debugging)
bats --no-tempdir-cleanup tests/my_test.bats
```

### Test Filters

```bash
# Run only library tests
bats tests/lib_*.bats

# Run only script tests
bats tests/script_*.bats

# Run only integration tests
bats tests/integration_*.bats

# Run specific test pattern
bats tests/*target_list*.bats
```

## Debugging Tests

### Verbose Output

```bash
# Enable verbose test output
bats -t tests/my_test.bats

# Enable verbose run output (shows executed commands)
bats --verbose-run tests/my_test.bats
```

### Debug Individual Test

```bash
# Run single test by name
bats -f "specific test name" tests/my_test.bats

# Keep temp directory for inspection
bats --no-tempdir-cleanup tests/my_test.bats
echo "Temp dir: $BATS_TEST_TMPDIR"
```

### Inspect Mock Calls

Mock OCI CLI logs all calls to stderr:

```bash
bats -t tests/my_test.bats 2>&1 | grep "MOCK_OCI_CALL"
```

### Add Debug Output to Tests

```bash
@test "My test with debug output" {
    echo "DEBUG: Starting test" >&3
    run "${BIN_DIR}/script.sh" --option
    echo "DEBUG: Status=$status" >&3
    echo "DEBUG: Output=$output" >&3
    [ "$status" -eq 0 ]
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y bats jq shellcheck
      
      - name: Run tests
        run: make test
      
      - name: Run linting
        run: make lint
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running pre-commit tests..."
make test

if [ $? -ne 0 ]; then
    echo "Tests failed. Commit aborted."
    exit 1
fi

echo "All tests passed!"
```

## Test Coverage

### Current Coverage

As of v0.7.0, the test suite includes:

- **163+ tests** covering all major functionality
- **23 executable scripts** with comprehensive tests
- **Multiple test categories** (unit, integration, edge cases)
- **~2,300+ lines** of test code

### Coverage by Component

| Component | Coverage | Test Files |
|-----------|----------|------------|
| Library functions | High | `lib_*.bats` |
| Target management | High | `script_ds_target_*.bats` |
| Connector operations | High | `script_ds_*connector*.bats` |
| Tag management | High | `script_ds_*tag*.bats` |
| Service installation | Medium | `install_*.bats`, `uninstall_*.bats` |
| Edge cases | High | `edge_case_tests.bats` |
| Integration | High | `integration_*.bats` |

### Measuring Coverage

```bash
# Run test runner with coverage report
./tests/run_tests.sh -c

# Count total tests
grep -r "@test" tests/*.bats | wc -l

# List untested scripts
comm -23 <(ls bin/*.sh | sort) <(grep -l "script_" tests/*.bats | sed 's/.*script_//' | sed 's/.bats//' | sort)
```

## Best Practices

### 1. Test Isolation

- Each test should be independent
- Use setup/teardown for consistent environments
- Don't rely on test execution order
- Clean up resources in teardown

### 2. Clear Test Names

```bash
# Good: Descriptive and specific
@test "ds_target_list.sh returns error for invalid compartment OCID"

# Bad: Vague and unclear
@test "test list error"
```

### 3. Test One Thing

```bash
# Good: Single assertion
@test "Script validates required compartment parameter" {
    run "${BIN_DIR}/ds_target_list.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
}

# Bad: Multiple unrelated assertions
@test "Script works" {
    run "${BIN_DIR}/ds_target_list.sh" --help
    [ "$status" -eq 0 ]
    run "${BIN_DIR}/ds_target_list.sh" --version
    [ "$status" -eq 0 ]
    run "${BIN_DIR}/ds_target_list.sh" -c test
    [ "$status" -eq 0 ]
}
```

### 4. Test Both Success and Failure

```bash
@test "Function accepts valid OCID" {
    run is_ocid "ocid1.compartment.oc1..valid"
    [ "$status" -eq 0 ]
}

@test "Function rejects invalid OCID" {
    run is_ocid "invalid"
    [ "$status" -ne 0 ]
}
```

### 5. Use Appropriate Test Categories

- **Unit tests** for library functions
- **Integration tests** for workflows
- **Edge case tests** for boundaries
- **Quick tests** for CI smoke tests

### 6. Mock External Dependencies

- Always mock OCI CLI in tests
- Don't make actual API calls in tests
- Use consistent mock data
- Simulate various response scenarios

### 7. Document Complex Tests

```bash
@test "Complex workflow with multiple steps" {
    # Step 1: List all targets
    run "${BIN_DIR}/ds_target_list.sh" -c "$COMPARTMENT"
    [ "$status" -eq 0 ]
    
    # Step 2: Extract ACTIVE targets from output
    local active_targets
    active_targets=$(echo "$output" | grep "ACTIVE" | cut -d' ' -f1)
    
    # Step 3: Verify we found at least one target
    [ -n "$active_targets" ]
}
```

### 8. Performance Testing

```bash
@test "Operation completes within time limit" {
    local start_time=$(date +%s)
    
    run "${BIN_DIR}/ds_target_list.sh" -c "$COMPARTMENT"
    [ "$status" -eq 0 ]
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should complete in under 10 seconds
    [ "$duration" -lt 10 ]
}
```

### 9. Skip Tests Appropriately

```bash
@test "Test requiring root privileges" {
    skip_if_not_root
    # Test code that requires root
}

@test "Test requiring real OCI access" {
    skip_if_no_oci_config
    # Test code that needs real OCI CLI
}
```

### 10. Test Error Messages

```bash
@test "Script provides helpful error for missing parameter" {
    run "${BIN_DIR}/ds_target_list.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compartment"* ]]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"must"* ]]
}
```

## Performance Targets

### Success Criteria (from Issue Requirements)

- ✅ **All tests complete in <5 minutes** - Current: ~2-3 minutes for full suite
- ✅ **Clear test output for debugging** - Verbose and descriptive test names
- ✅ **Good coverage of main scripts** - 163+ tests covering 23 scripts

### Test Execution Times

| Test Suite | Time | Tests |
|------------|------|-------|
| Quick validation | <30s | ~10 |
| Library tests | <1min | ~30 |
| Script tests | <2min | ~80 |
| Integration tests | <1min | ~30 |
| Edge case tests | <1min | ~40 |
| **Total** | **<5min** | **163+** |

## Additional Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS GitHub Repository](https://github.com/bats-core/bats-core)
- [Bash Testing Best Practices](https://www.gnu.org/software/bash/manual/bash.html)
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/tools/oci-cli/)
- [odb_datasafe Test Suite README](../tests/README.md)

## Contributing

When adding new functionality:

1. **Write tests first** (TDD approach recommended)
2. **Add to appropriate test category** (lib, script, integration, edge)
3. **Follow naming conventions** (`test_category_component.bats`)
4. **Use consistent mock data** (see [Mock Test Data](#mock-test-data))
5. **Document complex scenarios** with comments
6. **Verify all tests pass** before committing (`make test`)
7. **Check test coverage** for new code

## Questions and Support

For questions about testing:

- Review existing tests in `tests/` directory
- Check [tests/README.md](../tests/README.md) for overview
- Consult [BATS documentation](https://bats-core.readthedocs.io/)
- Contact maintainer: Stefan Oehrli (stefan.oehrli@oradba.ch)

---

**Last Updated:** 2026-02-11  
**Version:** 0.7.0
