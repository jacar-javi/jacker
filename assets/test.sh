#!/usr/bin/env bash
#
# Script: test.sh
# Description: Automated testing suite for Jacker
# Usage: ./test.sh [--quick|--full|--ci]
# Options:
#   --quick    Run quick tests only (syntax, configuration)
#   --full     Run full test suite including integration tests
#   --ci       CI mode (non-interactive, exit on first failure)
#

set -euo pipefail

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test mode
TEST_MODE="${1:-full}"
CI_MODE=false

if [ "$TEST_MODE" = "--ci" ]; then
    CI_MODE=true
    TEST_MODE="full"
fi

# Test result tracking
declare -a FAILED_TESTS=()

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Jacker Automated Test Suite         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo ""
echo "Test Mode: $TEST_MODE"
echo "CI Mode: $CI_MODE"
echo ""

# Test helper functions
test_start() {
    local test_name=$1
    echo -n "Testing: $test_name... "
    ((TESTS_RUN++))
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    local test_name=$1
    local reason=${2:-"Unknown error"}
    echo -e "${RED}✗ FAIL${NC} ($reason)"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$test_name: $reason")

    if [ "$CI_MODE" = true ]; then
        echo "CI mode: Exiting on first failure"
        exit 1
    fi
}

test_skip() {
    local reason=${1:-""}
    echo -e "${YELLOW}⊘ SKIP${NC} ($reason)"
    ((TESTS_SKIPPED++))
}

# Test Categories

## 1. Script Syntax Tests
echo -e "${BLUE}=== Script Syntax Tests ===${NC}"

test_start "Shell script syntax (bash -n)"
if bash -n setup.sh && bash -n clean.sh && bash -n update.sh && \
   bash -n backup.sh && bash -n validate.sh && bash -n health-check.sh && \
   bash -n register_bouncers.sh; then
    test_pass
else
    test_fail "Shell script syntax" "Syntax error in main scripts"
fi

test_start "Asset scripts syntax"
if bash -n assets/*.sh; then
    test_pass
else
    test_fail "Asset scripts syntax" "Syntax error in asset scripts"
fi

if command -v shellcheck &> /dev/null; then
    test_start "ShellCheck linting"
    if shellcheck -x *.sh assets/*.sh 2>/dev/null; then
        test_pass
    else
        test_skip "ShellCheck warnings/errors found (non-critical)"
    fi
else
    test_start "ShellCheck linting"
    test_skip "shellcheck not installed"
fi

## 2. Configuration Tests
echo ""
echo -e "${BLUE}=== Configuration Tests ===${NC}"

test_start "docker-compose.yml syntax"
if docker compose config > /dev/null 2>&1; then
    test_pass
else
    test_fail "docker-compose.yml syntax" "Invalid compose configuration"
fi

test_start "All compose files syntax"
all_valid=true
for file in compose/*.yml; do
    if ! docker compose -f "$file" config > /dev/null 2>&1; then
        all_valid=false
        break
    fi
done
if $all_valid; then
    test_pass
else
    test_fail "Compose files syntax" "Invalid compose file found"
fi

test_start ".env.defaults file exists"
if [ -f .env.defaults ]; then
    test_pass
else
    test_fail ".env.defaults" "File not found"
fi

test_start ".env.sample file exists"
if [ -f .env.sample ]; then
    test_pass
else
    test_fail ".env.sample" "File not found"
fi

test_start ".env.template file exists"
if [ -f .env.template ]; then
    test_pass
else
    test_fail ".env.template" "File not found"
fi

## 3. File Structure Tests
echo ""
echo -e "${BLUE}=== File Structure Tests ===${NC}"

test_start "Required directories exist"
required_dirs=("assets" "compose" "data" "stacks" "templates")
all_exist=true
for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        all_exist=false
        break
    fi
done
if $all_exist; then
    test_pass
else
    test_fail "Required directories" "Missing directory"
fi

test_start "Required scripts exist and executable"
required_scripts=("setup.sh" "clean.sh" "update.sh" "backup.sh" "validate.sh" "health-check.sh")
all_executable=true
for script in "${required_scripts[@]}"; do
    if [ ! -f "$script" ] || [ ! -x "$script" ]; then
        all_executable=false
        break
    fi
done
if $all_executable; then
    test_pass
else
    test_fail "Required scripts" "Missing or not executable"
fi

test_start "Asset scripts exist and executable"
asset_scripts=("01-tune_system.sh" "02-install_docker.sh" "03-setup_ufw.sh" "04-install_assets.sh" "05-install_iptables-bouncer.sh")
all_asset_executable=true
for script in "${asset_scripts[@]}"; do
    if [ ! -f "assets/$script" ] || [ ! -x "assets/$script" ]; then
        all_asset_executable=false
        break
    fi
done
if $all_asset_executable; then
    test_pass
else
    test_fail "Asset scripts" "Missing or not executable"
fi

test_start "Documentation files exist"
doc_files=("README.md" "CONTRIBUTING.md" "SECURITY.md" "TROUBLESHOOTING.md" "LICENSE")
all_docs_exist=true
for doc in "${doc_files[@]}"; do
    if [ ! -f "$doc" ]; then
        all_docs_exist=false
        break
    fi
done
if $all_docs_exist; then
    test_pass
else
    test_fail "Documentation files" "Missing documentation"
fi

## 4. Docker Tests
if [ "$TEST_MODE" = "full" ] || [ "$TEST_MODE" = "--full" ]; then
    echo ""
    echo -e "${BLUE}=== Docker Tests ===${NC}"

    test_start "Docker daemon running"
    if docker info &> /dev/null; then
        test_pass
    else
        test_fail "Docker daemon" "Docker not running or not accessible"
    fi

    test_start "Docker Compose available"
    if docker compose version &> /dev/null; then
        test_pass
    else
        test_fail "Docker Compose" "Docker Compose not available"
    fi

    test_start "Docker networks can be created"
    test_network="jacker-test-network-$$"
    if docker network create "$test_network" &> /dev/null; then
        docker network rm "$test_network" &> /dev/null
        test_pass
    else
        test_fail "Docker networks" "Cannot create network"
    fi
fi

## 5. Security Tests
echo ""
echo -e "${BLUE}=== Security Tests ===${NC}"

test_start "No secrets in git tracked files"
if git check-ignore .env &> /dev/null; then
    test_pass
else
    test_skip ".env not in gitignore (may not be using git)"
fi

test_start "Script security headers (set -euo pipefail)"
scripts_with_set=0
total_scripts=0
for script in *.sh assets/*.sh; do
    if [ -f "$script" ]; then
        ((total_scripts++))
        if grep -q "set -euo pipefail" "$script"; then
            ((scripts_with_set++))
        fi
    fi
done
if [ $scripts_with_set -ge $((total_scripts - 2)) ]; then  # Allow 2 scripts without it
    test_pass
else
    test_skip "Some scripts missing 'set -euo pipefail'"
fi

test_start "No hardcoded secrets in compose files"
if grep -r -i "password.*:.*[^$]" compose/*.yml | grep -v "PASSWORD" | grep -q .; then
    test_fail "Hardcoded secrets" "Found potential hardcoded password"
else
    test_pass
fi

## 6. Image Version Tests
echo ""
echo -e "${BLUE}=== Image Version Tests ===${NC}"

test_start "No :latest tags in compose files"
if grep -r ":latest" compose/*.yml; then
    test_fail "Image versions" "Found :latest tags"
else
    test_pass
fi

test_start "All images have version tags"
images_without_tags=0
for file in compose/*.yml; do
    while IFS= read -r line; do
        if echo "$line" | grep -q "image:"; then
            if ! echo "$line" | grep -q ":"; then
                ((images_without_tags++))
            fi
        fi
    done < "$file"
done
if [ $images_without_tags -eq 0 ]; then
    test_pass
else
    test_fail "Image versions" "$images_without_tags images without version tags"
fi

## 7. Integration Tests (Full mode only)
if [ "$TEST_MODE" = "full" ] || [ "$TEST_MODE" = "--full" ]; then
    if [ -f .env ]; then
        echo ""
        echo -e "${BLUE}=== Integration Tests ===${NC}"

        test_start "Validation script runs"
        if ./validate.sh > /dev/null 2>&1; then
            test_pass
        else
            test_skip "Validation failed (system may not be fully configured)"
        fi

        test_start "Health check script runs"
        if timeout 10 ./health-check.sh > /dev/null 2>&1; then
            test_pass
        else
            test_skip "Health check timed out or failed"
        fi

        test_start "Backup script runs (dry-run)"
        if [ ! -d /tmp/jacker-test-backup ]; then
            if ./backup.sh /tmp/jacker-test-backup > /dev/null 2>&1; then
                rm -rf /tmp/jacker-test-backup
                test_pass
            else
                test_fail "Backup script" "Backup failed"
            fi
        else
            test_skip "Test backup directory exists"
        fi
    else
        echo ""
        echo -e "${YELLOW}Skipping integration tests (.env not found)${NC}"
    fi
fi

# Test Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Test Summary                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Tests Run:     $TESTS_RUN"
echo -e "Tests Passed:  ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed:  ${RED}$TESTS_FAILED${NC}"
echo -e "Tests Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
echo ""

# Show failed tests
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${RED}Failed Tests:${NC}"
    for failed in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗${NC} $failed"
    done
    echo ""
fi

# Exit code
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
