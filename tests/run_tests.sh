#!/usr/bin/env bash
#
# run_tests.sh - Comprehensive test runner for Jacker platform
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="${PROJECT_ROOT}/tests"
RESULTS_DIR="${TEST_DIR}/results"
COVERAGE_DIR="${TEST_DIR}/coverage"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
VERBOSE=${VERBOSE:-false}
PARALLEL=${PARALLEL:-false}
COVERAGE=${COVERAGE:-false}
TEST_TYPE=${1:-all}

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_dependencies() {
    print_header "Checking Dependencies"

    local deps_missing=false

    # Check for BATS
    if ! command -v bats &> /dev/null; then
        print_error "BATS not installed"
        echo "  Run: ${TEST_DIR}/setup_bats.sh"
        deps_missing=true
    else
        print_success "BATS installed: $(bats --version)"
    fi

    # Check for Docker (only required for integration tests)
    if ! command -v docker &> /dev/null; then
        if [ "$TEST_TYPE" = "integration" ] || [ "$TEST_TYPE" = "docker" ] || [ "$TEST_TYPE" = "all" ]; then
            print_error "Docker not installed (required for $TEST_TYPE tests)"
            deps_missing=true
        else
            print_warning "Docker not installed (not required for unit tests)"
        fi
    else
        print_success "Docker installed: $(docker --version)"
    fi

    # Check for Docker Compose (only required for integration tests)
    if ! docker compose version &> /dev/null 2>&1; then
        if [ "$TEST_TYPE" = "integration" ] || [ "$TEST_TYPE" = "docker" ] || [ "$TEST_TYPE" = "all" ]; then
            print_error "Docker Compose not installed (required for $TEST_TYPE tests)"
            deps_missing=true
        else
            print_warning "Docker Compose not installed (not required for unit tests)"
        fi
    else
        print_success "Docker Compose installed: $(docker compose version)"
    fi

    # Check for ShellCheck (optional)
    if ! command -v shellcheck &> /dev/null; then
        print_warning "ShellCheck not installed (optional)"
    else
        print_success "ShellCheck installed: $(shellcheck --version | head -1)"
    fi

    if [ "$deps_missing" = true ]; then
        echo ""
        print_error "Missing dependencies. Please install them first."
        exit 1
    fi

    echo ""
}

setup_environment() {
    print_header "Setting Up Test Environment"

    # Create results directory
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$COVERAGE_DIR"

    # Export test environment variables
    export PROJECT_ROOT
    export TEST_DIR
    export LIB_DIR="${PROJECT_ROOT}/assets/lib"
    export FIXTURES_DIR="${TEST_DIR}/fixtures"

    # Create test fixtures if needed
    if [ ! -d "$FIXTURES_DIR" ]; then
        mkdir -p "$FIXTURES_DIR"
    fi

    # Copy test environment file
    if [ -f "${FIXTURES_DIR}/.env.test" ]; then
        cp "${FIXTURES_DIR}/.env.test" "${PROJECT_ROOT}/.env.test"
    fi

    print_success "Test environment prepared"
    echo ""
}

run_unit_tests() {
    print_header "Running Unit Tests"

    local test_files=(
        "${TEST_DIR}/unit/test_common.bats"
        "${TEST_DIR}/unit/test_system.bats"
        "${TEST_DIR}/unit/test_services.bats"
    )

    local failed=0
    local passed=0

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            echo "Running: $(basename "$test_file")"

            if [ "$VERBOSE" = true ]; then
                bats --verbose-run "$test_file" | tee "${RESULTS_DIR}/$(basename "$test_file" .bats).log"
            else
                bats "$test_file" > "${RESULTS_DIR}/$(basename "$test_file" .bats).log" 2>&1
            fi

            if [ $? -eq 0 ]; then
                print_success "$(basename "$test_file")"
                ((passed++))
            else
                print_error "$(basename "$test_file")"
                ((failed++))
            fi
        fi
    done

    echo ""
    echo "Unit Tests: ${passed} passed, ${failed} failed"
    echo ""

    return $failed
}

run_integration_tests() {
    print_header "Running Integration Tests"

    # Start test containers
    echo "Starting test environment..."
    docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" up -d

    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    sleep 30

    # Check service health
    docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" ps

    local test_files=(
        "${TEST_DIR}/integration/test_setup.bats"
        "${TEST_DIR}/integration/test_full_stack.bats"
    )

    local failed=0
    local passed=0

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            echo "Running: $(basename "$test_file")"

            if [ "$VERBOSE" = true ]; then
                bats --verbose-run "$test_file" | tee "${RESULTS_DIR}/$(basename "$test_file" .bats).log"
            else
                bats "$test_file" > "${RESULTS_DIR}/$(basename "$test_file" .bats).log" 2>&1
            fi

            if [ $? -eq 0 ]; then
                print_success "$(basename "$test_file")"
                ((passed++))
            else
                print_error "$(basename "$test_file")"
                ((failed++))
            fi
        fi
    done

    # Stop test containers
    echo "Stopping test environment..."
    docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" down -v

    echo ""
    echo "Integration Tests: ${passed} passed, ${failed} failed"
    echo ""

    return $failed
}

run_shellcheck() {
    print_header "Running ShellCheck"

    local failed=0
    local passed=0

    if ! command -v shellcheck &> /dev/null; then
        print_warning "ShellCheck not installed, skipping..."
        return 0
    fi

    # Check all shell scripts
    while IFS= read -r -d '' script; do
        echo "Checking: ${script#$PROJECT_ROOT/}"

        if shellcheck -S warning "$script" > "${RESULTS_DIR}/shellcheck_$(basename "$script").log" 2>&1; then
            print_success "$(basename "$script")"
            ((passed++))
        else
            print_error "$(basename "$script")"
            cat "${RESULTS_DIR}/shellcheck_$(basename "$script").log"
            ((failed++))
        fi
    done < <(find "${PROJECT_ROOT}/assets" -name "*.sh" -type f -print0)

    echo ""
    echo "ShellCheck: ${passed} passed, ${failed} failed"
    echo ""

    return $failed
}

run_docker_tests() {
    print_header "Running Docker Tests"

    echo "Validating docker-compose.yml..."
    if docker compose -f "${PROJECT_ROOT}/docker-compose.yml" config > /dev/null 2>&1; then
        print_success "docker-compose.yml is valid"
    else
        print_error "docker-compose.yml validation failed"
        return 1
    fi

    echo "Validating docker-compose.test.yml..."
    if docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" config > /dev/null 2>&1; then
        print_success "docker-compose.test.yml is valid"
    else
        print_error "docker-compose.test.yml validation failed"
        return 1
    fi

    echo "Building test image..."
    if docker build -f "${TEST_DIR}/Dockerfile.test" -t jacker-test:latest "${PROJECT_ROOT}" > "${RESULTS_DIR}/docker_build.log" 2>&1; then
        print_success "Test image built successfully"
    else
        print_error "Test image build failed"
        return 1
    fi

    echo ""
    return 0
}

generate_report() {
    print_header "Generating Test Report"

    local report_file="${RESULTS_DIR}/test_report_$(date +%Y%m%d_%H%M%S).md"

    cat > "$report_file" <<EOF
# Jacker Platform Test Report

**Date:** $(date)
**Test Type:** ${TEST_TYPE}

## Summary

EOF

    # Add test results
    if [ -f "${RESULTS_DIR}/summary.txt" ]; then
        cat "${RESULTS_DIR}/summary.txt" >> "$report_file"
    fi

    cat >> "$report_file" <<EOF

## Test Results

### Unit Tests
EOF

    # Add unit test results
    for log in "${RESULTS_DIR}"/test_*.log; do
        if [ -f "$log" ]; then
            echo "- $(basename "$log" .log): " >> "$report_file"
            tail -1 "$log" >> "$report_file"
        fi
    done

    cat >> "$report_file" <<EOF

### Integration Tests
EOF

    # Add integration test results
    for log in "${RESULTS_DIR}"/test_*.log; do
        if [ -f "$log" ]; then
            echo "- $(basename "$log" .log): " >> "$report_file"
            tail -1 "$log" >> "$report_file"
        fi
    done

    if [ -f "${RESULTS_DIR}/shellcheck_summary.log" ]; then
        cat >> "$report_file" <<EOF

### Code Quality (ShellCheck)
EOF
        cat "${RESULTS_DIR}/shellcheck_summary.log" >> "$report_file"
    fi

    print_success "Report generated: $report_file"
    echo ""
}

cleanup() {
    print_header "Cleanup"

    # Stop any running test containers
    if docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" ps -q | grep -q .; then
        echo "Stopping test containers..."
        docker compose -f "${PROJECT_ROOT}/docker-compose.test.yml" down -v
    fi

    # Clean up temporary files
    rm -f "${PROJECT_ROOT}/.env.test"

    print_success "Cleanup completed"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local total_failed=0

    # Trap cleanup on exit
    trap cleanup EXIT

    # Print banner
    print_header "Jacker Platform Test Suite"
    echo "Test Type: ${TEST_TYPE}"
    echo "Verbose: ${VERBOSE}"
    echo "Parallel: ${PARALLEL}"
    echo ""

    # Check dependencies
    check_dependencies

    # Setup environment
    setup_environment

    # Run tests based on type
    case "$TEST_TYPE" in
        unit)
            run_unit_tests || ((total_failed+=$?))
            ;;
        integration)
            run_integration_tests || ((total_failed+=$?))
            ;;
        shellcheck)
            run_shellcheck || ((total_failed+=$?))
            ;;
        docker)
            run_docker_tests || ((total_failed+=$?))
            ;;
        all)
            run_unit_tests || ((total_failed+=$?))
            run_integration_tests || ((total_failed+=$?))
            run_shellcheck || ((total_failed+=$?))
            run_docker_tests || ((total_failed+=$?))
            ;;
        *)
            print_error "Unknown test type: $TEST_TYPE"
            echo "Available types: unit, integration, shellcheck, docker, all"
            exit 1
            ;;
    esac

    # Generate report
    generate_report

    # Final summary
    print_header "Test Suite Summary"
    if [ $total_failed -eq 0 ]; then
        print_success "All tests passed!"
        exit 0
    else
        print_error "Tests failed: $total_failed"
        exit 1
    fi
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 [TEST_TYPE] [OPTIONS]

Test Types:
  unit          Run unit tests
  integration   Run integration tests
  shellcheck    Run shell script validation
  docker        Run Docker configuration tests
  all           Run all tests (default)

Options:
  VERBOSE=true  Enable verbose output
  PARALLEL=true Run tests in parallel (experimental)
  COVERAGE=true Generate coverage report (requires bashcov)

Examples:
  $0                    # Run all tests
  $0 unit              # Run only unit tests
  VERBOSE=true $0      # Run all tests with verbose output

EOF
}

# Parse arguments
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"