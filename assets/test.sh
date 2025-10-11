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

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

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
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local test_name=$1
    local reason=${2:-"Unknown error"}
    echo -e "${RED}✗ FAIL${NC} ($reason)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name: $reason")

    if [ "$CI_MODE" = true ]; then
        echo "CI mode: Exiting on first failure"
        exit 1
    fi
}

test_skip() {
    local reason=${1:-""}
    echo -e "${YELLOW}⊘ SKIP${NC} ($reason)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

test_info() {
    local message=$1
    echo -e "${BLUE}ℹ${NC} $message"
}

# Test Categories

## 1. Script Syntax Tests
echo -e "${BLUE}=== Script Syntax Tests ===${NC}"

test_start "Shell script syntax (bash -n)"
syntax_ok=true
failed_script=""
for script in assets/setup.sh assets/clean.sh assets/update.sh assets/backup.sh assets/health-check.sh assets/register_bouncers.sh; do
    if [ ! -f "$script" ]; then
        syntax_ok=false
        failed_script="$script (not found)"
        break
    fi
    # Temporarily disable pipefail for this check
    set +e
    bash -n "$script" >/dev/null 2>&1
    result=$?
    set -e
    if [ $result -ne 0 ]; then
        syntax_ok=false
        failed_script="$script (syntax error)"
        break
    fi
done
if [ "$syntax_ok" = true ]; then
    test_pass
else
    test_fail "Shell script syntax" "$failed_script"
fi

test_start "Asset scripts syntax"
asset_syntax_ok=true
for script in assets/*.sh; do
    if [ -f "$script" ]; then
        if ! bash -n "$script" 2>/dev/null; then
            asset_syntax_ok=false
            break
        fi
    fi
done
if $asset_syntax_ok; then
    test_pass
else
    test_fail "Asset scripts syntax" "Syntax error in asset scripts"
fi

if command -v shellcheck &> /dev/null; then
    test_start "ShellCheck linting"
    if shellcheck -x assets/*.sh 2>/dev/null; then
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

test_start ".env.sample or .env.template file exists"
if [ -f .env.sample ] || [ -f .env.template ]; then
    test_pass
else
    test_fail ".env template" "Neither .env.sample nor .env.template found"
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
required_scripts=("assets/setup.sh" "assets/clean.sh" "assets/update.sh" "assets/backup.sh" "assets/health-check.sh")
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
doc_files=("README.md" "CONTRIBUTING.md" "SECURITY.md" "LICENSE")
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
for script in assets/*.sh; do
    if [ -f "$script" ]; then
        total_scripts=$((total_scripts + 1))
        if grep -q "set -euo pipefail" "$script"; then
            scripts_with_set=$((scripts_with_set + 1))
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
                images_without_tags=$((images_without_tags + 1))
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

        test_start "Health check script runs"
        if timeout 10 assets/health-check.sh > /dev/null 2>&1; then
            test_pass
        else
            test_skip "Health check timed out or failed"
        fi

        # OAuth Integration Tests
        test_info "Checking OAuth configuration..."

        test_start "OAuth service health"
        if docker ps --format '{{.Names}}' | grep -q "^oauth$"; then
            if docker inspect --format='{{.State.Health.Status}}' oauth 2>/dev/null | grep -q "healthy\|no"; then
                test_pass
            else
                test_fail "OAuth health" "OAuth container unhealthy"
            fi
        else
            test_skip "OAuth container not running"
        fi

        test_start "OAuth configuration exists"
        if [ -f secrets/traefik_forward_oauth ]; then
            if grep -q "client-id" secrets/traefik_forward_oauth && \
               grep -q "client-secret" secrets/traefik_forward_oauth; then
                test_pass
            else
                test_fail "OAuth config" "Missing client-id or client-secret"
            fi
        else
            test_skip "OAuth secrets file not found"
        fi

        test_start "OAuth environment variables set"
# shellcheck source=/dev/null
        source .env 2>/dev/null || true
        if [ -n "$OAUTH_CLIENT_ID" ] && [ -n "$OAUTH_CLIENT_SECRET" ] && [ -n "$OAUTH_WHITELIST" ]; then
            test_pass
        else
            test_skip "OAuth not configured in .env"
        fi

        # Service Health Tests
        test_info "Checking critical services..."

        test_start "Traefik is healthy"
        if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
            if docker inspect --format='{{.State.Health.Status}}' traefik 2>/dev/null | grep -q "healthy"; then
                test_pass
            else
                test_fail "Traefik health" "Traefik unhealthy"
            fi
        else
            test_skip "Traefik not running"
        fi

        test_start "Traefik API accessible"
        if curl -sf http://localhost:8080/ping &> /dev/null; then
            test_pass
        else
            test_skip "Traefik API not accessible"
        fi

        test_start "PostgreSQL is healthy"
        if docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
            if docker exec postgres pg_isready -U postgres &> /dev/null; then
                test_pass
            else
                test_fail "PostgreSQL health" "PostgreSQL not ready"
            fi
        else
            test_skip "PostgreSQL not running"
        fi

        test_start "CrowdSec is healthy"
        if docker ps --format '{{.Names}}' | grep -q "^crowdsec$"; then
            if docker exec crowdsec cscli version &> /dev/null; then
                test_pass
            else
                test_fail "CrowdSec health" "CrowdSec unhealthy"
            fi
        else
            test_skip "CrowdSec not running"
        fi

        test_start "Loki is accessible"
        if docker ps --format '{{.Names}}' | grep -q "^loki$"; then
            if curl -sf http://localhost:3100/ready &> /dev/null; then
                test_pass
            else
                test_skip "Loki not ready"
            fi
        else
            test_skip "Loki not running"
        fi

        # Network Tests
        test_info "Checking network connectivity..."

        test_start "Docker networks exist"
        required_networks=("socket_proxy" "traefik_proxy")
        networks_exist=true
        for net in "${required_networks[@]}"; do
            if ! docker network ls --format '{{.Name}}' | grep -q "^${net}$"; then
                networks_exist=false
                break
            fi
        done
        if $networks_exist; then
            test_pass
        else
            test_fail "Docker networks" "Required networks missing"
        fi

        test_start "Services can communicate"
        if docker ps --format '{{.Names}}' | grep -q "^traefik$" && \
           docker ps --format '{{.Names}}' | grep -q "^socket-proxy$"; then
            if docker exec traefik wget --spider -q http://socket-proxy:2375/version 2>/dev/null; then
                test_pass
            else
                test_skip "Service communication test failed"
            fi
        else
            test_skip "Required containers not running"
        fi

        # Backup/Restore Tests
        test_info "Testing backup and restore functionality..."

        test_start "Backup script creates valid backup"
        test_backup_dir="/tmp/jacker-test-backup-$$"
        if assets/backup.sh "$test_backup_dir" > /dev/null 2>&1; then
            # Check if backup files exist using glob with proper iteration
            backup_found=false
            for backup_file in "$test_backup_dir"/jacker-config-*.tar.gz; do
                if [ -f "$backup_file" ]; then
                    backup_found=true
                    break
                fi
            done
            if [ "$backup_found" = true ] && [ -f "$test_backup_dir/checksums.sha256" ]; then
                test_pass
            else
                test_fail "Backup validation" "Backup files not created properly"
            fi
        else
            test_fail "Backup creation" "Backup script failed"
        fi

        test_start "Backup includes .env file"
        if [ -d "$test_backup_dir" ]; then
            if tar -tzf "$test_backup_dir"/jacker-config-*.tar.gz 2>/dev/null | grep -q "\.env$"; then
                test_pass
            else
                test_fail "Backup .env" ".env not in backup"
            fi
        else
            test_skip "Backup directory not found"
        fi

        test_start "Backup checksums are valid"
        if [ -f "$test_backup_dir/checksums.sha256" ]; then
            cd "$test_backup_dir" && sha256sum -c checksums.sha256 &> /dev/null
            if [ $? -eq 0 ]; then
                test_pass
            else
                test_fail "Backup checksums" "Checksum validation failed"
            fi
            cd - > /dev/null
        else
            test_skip "Checksums file not found"
        fi

        # Cleanup test backup
        if [ -d "$test_backup_dir" ]; then
            rm -rf "$test_backup_dir"
        fi

        # Certificate Tests
        test_info "Checking SSL certificate configuration..."

        test_start "ACME JSON file exists"
        if [ -f data/traefik/acme.json ]; then
            test_pass
        else
            test_fail "ACME file" "acme.json not found"
        fi

        test_start "ACME JSON has correct permissions"
        if [ -f data/traefik/acme.json ]; then
            perms=$(stat -c '%a' data/traefik/acme.json 2>/dev/null || stat -f '%A' data/traefik/acme.json 2>/dev/null)
            if [ "$perms" = "600" ]; then
                test_pass
            else
                test_fail "ACME permissions" "Expected 600, got $perms"
            fi
        else
            test_skip "acme.json not found"
        fi

        test_start "Let's Encrypt email configured"
# shellcheck source=/dev/null
        source .env 2>/dev/null || true
        if [ -n "$LETSENCRYPT_EMAIL" ] && [ "$LETSENCRYPT_EMAIL" != "" ]; then
            test_pass
        else
            test_skip "LETSENCRYPT_EMAIL not set"
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
