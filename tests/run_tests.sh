#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: run_tests.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.01.09
# Purpose....: Test runner for odb_datasafe test suite
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="0.2.0"

# Defaults
: "${TEST_PATTERN:=*.bats}"
: "${VERBOSE:=false}"
: "${PARALLEL:=false}"
: "${COVERAGE:=false}"
: "${JUNIT_OUTPUT:=false}"

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [TEST_FILES...]

Description:
  Run BATS test suite for odb_datasafe framework.
  
Options:
  -h, --help              Show this help message
  -V, --version           Show version
  -v, --verbose           Enable verbose output
  -p, --parallel          Run tests in parallel
  -c, --coverage          Generate coverage report
  -j, --junit             Generate JUnit XML output
  -t, --pattern PATTERN   Test file pattern (default: ${TEST_PATTERN})
  
Test Categories:
  lib                     Library function tests only
  scripts                 Script tests only  
  integration            Integration tests only
  basic                   Basic functionality tests only
  all                     All tests (default)

Examples:
  ${SCRIPT_NAME}                           # Run all tests
  ${SCRIPT_NAME} lib                       # Run library tests only
  ${SCRIPT_NAME} scripts                   # Run script tests only
  ${SCRIPT_NAME} integration               # Run integration tests only
  ${SCRIPT_NAME} -v -p                     # Verbose parallel execution
  ${SCRIPT_NAME} lib_common.bats           # Run specific test file

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -V|--version)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -c|--coverage)
                COVERAGE=true
                shift
                ;;
            -j|--junit)
                JUNIT_OUTPUT=true
                shift
                ;;
            -t|--pattern)
                [[ -n "${2:-}" ]] || { echo "ERROR: --pattern requires a value" >&2; exit 1; }
                TEST_PATTERN="$2"
                shift 2
                ;;
            lib|scripts|integration|basic|all)
                TEST_CATEGORY="$1"
                shift
                ;;
            *.bats)
                TEST_FILES+=("$1")
                shift
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                exit 1
                ;;
            *)
                TEST_FILES+=("$1")
                shift
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v bats >/dev/null 2>&1; then
        missing+=("bats")
    fi
    
    if [[ "${PARALLEL}" == "true" ]] && ! command -v parallel >/dev/null 2>&1; then
        missing+=("parallel")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing[*]}" >&2
        echo "Install with:" >&2
        echo "  brew install bats-core gnu-parallel  # macOS" >&2
        echo "  sudo apt install bats parallel       # Ubuntu" >&2
        exit 1
    fi
}

# Determine test files to run
determine_test_files() {
    local -a files=()
    
    if [[ ${#TEST_FILES[@]} -gt 0 ]]; then
        # Use explicitly specified files
        for file in "${TEST_FILES[@]}"; do
            if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
                files+=("${SCRIPT_DIR}/${file}")
            elif [[ -f "${file}" ]]; then
                files+=("${file}")
            else
                echo "WARNING: Test file not found: ${file}" >&2
            fi
        done
    else
        # Use category or pattern
        case "${TEST_CATEGORY:-all}" in
            lib)
                files=($(find "${SCRIPT_DIR}" -name "lib_*.bats"))
                ;;
            scripts)
                files=($(find "${SCRIPT_DIR}" -name "script_*.bats"))
                ;;
            integration)
                files=($(find "${SCRIPT_DIR}" -name "integration*.bats"))
                ;;
            basic)
                files=($(find "${SCRIPT_DIR}" -name "basic_*.bats" -o -name "quick_*.bats"))
                ;;
            all)
                files=($(find "${SCRIPT_DIR}" -name "${TEST_PATTERN}"))
                ;;
        esac
    fi
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "ERROR: No test files found matching criteria" >&2
        exit 1
    fi
    
    printf '%s\n' "${files[@]}"
}

# Run tests
run_tests() {
    local -a test_files
    mapfile -t test_files < <(determine_test_files)
    
    echo "Running ${#test_files[@]} test files..."
    [[ "${VERBOSE}" == "true" ]] && printf '  %s\n' "${test_files[@]}"
    
    local -a bats_args=()
    
    # Configure output options
    if [[ "${VERBOSE}" == "true" ]]; then
        bats_args+=(--verbose-run)
    fi
    
    if [[ "${JUNIT_OUTPUT}" == "true" ]]; then
        mkdir -p "${REPO_ROOT}/test-results"
        bats_args+=(--formatter junit)
        bats_args+=(--output "${REPO_ROOT}/test-results")
    fi
    
    # Run tests
    if [[ "${PARALLEL}" == "true" && ${#test_files[@]} -gt 1 ]]; then
        echo "Running tests in parallel..."
        bats "${bats_args[@]}" --jobs "$(nproc 2>/dev/null || echo 4)" "${test_files[@]}"
    else
        echo "Running tests sequentially..."
        bats "${bats_args[@]}" "${test_files[@]}"
    fi
}

# Generate coverage report
generate_coverage() {
    if [[ "${COVERAGE}" == "true" ]]; then
        echo "Generating coverage report..."
        
        # Simple coverage report based on function calls
        local coverage_file="${REPO_ROOT}/coverage.txt"
        
        echo "Coverage Report - $(date)" > "$coverage_file"
        echo "================================" >> "$coverage_file"
        echo >> "$coverage_file"
        
        # Count functions in libraries
        local lib_functions
        lib_functions=$(grep -h "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "${REPO_ROOT}/lib"/*.sh | wc -l)
        echo "Library functions: $lib_functions" >> "$coverage_file"
        
        # Count functions tested (rough estimate)
        local tested_functions
        tested_functions=$(grep -h "@test.*function" "${SCRIPT_DIR}"/*.bats | wc -l)
        echo "Functions with tests: $tested_functions" >> "$coverage_file"
        
        if [[ $lib_functions -gt 0 ]]; then
            local coverage_pct
            coverage_pct=$(( (tested_functions * 100) / lib_functions ))
            echo "Estimated coverage: ${coverage_pct}%" >> "$coverage_file"
        fi
        
        echo "Coverage report generated: $coverage_file"
    fi
}

# Main execution
main() {
    echo "OraDBA Data Safe Test Runner v${SCRIPT_VERSION}"
    echo "=============================================="
    echo
    
    check_dependencies
    
    # Set up environment
    export BATS_LIB_PATH="${SCRIPT_DIR}"
    
    # Change to repo root for consistent paths
    cd "${REPO_ROOT}"
    
    # Run tests
    local start_time end_time duration
    start_time=$(date +%s)
    
    if run_tests; then
        echo
        echo "✅ All tests passed!"
        local exit_code=0
    else
        echo
        echo "❌ Some tests failed!"
        local exit_code=1
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo "Test execution time: ${duration} seconds"
    
    generate_coverage
    
    exit $exit_code
}

# Initialize variables
declare -a TEST_FILES=()
TEST_CATEGORY=""

# Parse arguments and run
parse_args "$@"
main