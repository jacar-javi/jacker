#!/bin/bash
# ====================================================================
# Test Resource Manager
# ====================================================================
# Validates Resource Manager installation and configuration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_DIR/config/resource-manager"
DATA_DIR="$PROJECT_DIR/data/resource-manager"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Test functions
test_file_exists() {
    ((TESTS_RUN++))
    local file=$1
    local description=$2

    if [ -f "$file" ]; then
        log_success "$description: $file"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$description: $file NOT FOUND"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_dir_exists() {
    ((TESTS_RUN++))
    local dir=$1
    local description=$2

    if [ -d "$dir" ]; then
        log_success "$description: $dir"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$description: $dir NOT FOUND"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_file_executable() {
    ((TESTS_RUN++))
    local file=$1
    local description=$2

    if [ -x "$file" ]; then
        log_success "$description: $file"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$description: $file NOT EXECUTABLE"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_yaml_valid() {
    ((TESTS_RUN++))
    local file=$1
    local description=$2

    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_success "$description: $file"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$description: $file INVALID YAML"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_docker_image_buildable() {
    ((TESTS_RUN++))
    local dockerfile=$1
    local description=$2

    if docker build -t resource-manager-test -f "$dockerfile" "$CONFIG_DIR" --quiet > /dev/null 2>&1; then
        log_success "$description"
        ((TESTS_PASSED++))
        docker rmi resource-manager-test > /dev/null 2>&1 || true
        return 0
    else
        log_error "$description FAILED"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Header
echo ""
echo "========================================"
echo "  Resource Manager Validation Tests    "
echo "========================================"
echo ""

# Test 1: Directory structure
log_info "Testing directory structure..."
test_dir_exists "$CONFIG_DIR" "Config directory exists"
test_dir_exists "$CONFIG_DIR" "Resource Manager config directory"

# Test 2: Configuration files
log_info "Testing configuration files..."
test_file_exists "$CONFIG_DIR/config.yml" "Configuration file exists"
test_file_exists "$CONFIG_DIR/Dockerfile" "Dockerfile exists"
test_file_exists "$CONFIG_DIR/requirements.txt" "Requirements file exists"
test_file_exists "$CONFIG_DIR/README.md" "README exists"
test_file_exists "$CONFIG_DIR/.dockerignore" "Dockerignore file exists"

# Test 3: Python scripts
log_info "Testing Python scripts..."
test_file_exists "$CONFIG_DIR/manager.py" "Manager script exists"
test_file_executable "$CONFIG_DIR/manager.py" "Manager script is executable"

# Test 4: Shell scripts
log_info "Testing shell scripts..."
test_file_exists "$CONFIG_DIR/entrypoint.sh" "Entrypoint script exists"
test_file_executable "$CONFIG_DIR/entrypoint.sh" "Entrypoint script is executable"
test_file_exists "$SCRIPT_DIR/blue-green-deploy.sh" "Blue-Green script exists"
test_file_executable "$SCRIPT_DIR/blue-green-deploy.sh" "Blue-Green script is executable"
test_file_exists "$SCRIPT_DIR/enable-resource-manager.sh" "Enable script exists"
test_file_executable "$SCRIPT_DIR/enable-resource-manager.sh" "Enable script is executable"
test_file_exists "$SCRIPT_DIR/disable-resource-manager.sh" "Disable script exists"
test_file_executable "$SCRIPT_DIR/disable-resource-manager.sh" "Disable script is executable"

# Test 5: Docker compose files
log_info "Testing Docker compose files..."
test_file_exists "$PROJECT_DIR/compose/resource-manager.yml" "Compose file exists"

# Test 6: YAML validation
log_info "Testing YAML validity..."
test_yaml_valid "$CONFIG_DIR/config.yml" "Config YAML is valid"
test_yaml_valid "$PROJECT_DIR/compose/resource-manager.yml" "Compose YAML is valid"

# Test 7: Python syntax
log_info "Testing Python syntax..."
((TESTS_RUN++))
if python3 -m py_compile "$CONFIG_DIR/manager.py" 2>/dev/null; then
    log_success "Manager script has valid Python syntax"
    ((TESTS_PASSED++))
else
    log_error "Manager script has syntax errors"
    ((TESTS_FAILED++))
fi

# Test 8: Shell script syntax
log_info "Testing shell script syntax..."
for script in "$CONFIG_DIR/entrypoint.sh" "$SCRIPT_DIR/blue-green-deploy.sh" \
              "$SCRIPT_DIR/enable-resource-manager.sh" "$SCRIPT_DIR/disable-resource-manager.sh"; do
    ((TESTS_RUN++))
    if bash -n "$script" 2>/dev/null; then
        log_success "$(basename "$script") has valid syntax"
        ((TESTS_PASSED++))
    else
        log_error "$(basename "$script") has syntax errors"
        ((TESTS_FAILED++))
    fi
done

# Test 9: Dockerfile validation (optional, requires Docker)
if command -v docker &> /dev/null; then
    log_info "Testing Docker image build..."
    test_docker_image_buildable "$CONFIG_DIR/Dockerfile" "Docker image builds successfully"
else
    log_warn "Docker not available, skipping image build test"
fi

# Test 10: Service dependencies check
log_info "Testing service dependencies..."
((TESTS_RUN++))
if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config --services 2>/dev/null | grep -q "prometheus"; then
    log_success "Prometheus service available"
    ((TESTS_PASSED++))
else
    log_warn "Prometheus service not found (required dependency)"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config --services 2>/dev/null | grep -q "docker-socket-proxy"; then
    log_success "Docker Socket Proxy service available"
    ((TESTS_PASSED++))
else
    log_warn "Docker Socket Proxy not found (required dependency)"
    ((TESTS_FAILED++))
fi

# Test 11: Configuration validation
log_info "Testing configuration values..."
((TESTS_RUN++))
if grep -q "monitoring:" "$CONFIG_DIR/config.yml"; then
    log_success "Monitoring configuration present"
    ((TESTS_PASSED++))
else
    log_error "Monitoring configuration missing"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if grep -q "services:" "$CONFIG_DIR/config.yml"; then
    log_success "Services configuration present"
    ((TESTS_PASSED++))
else
    log_error "Services configuration missing"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if grep -q "blue_green:" "$CONFIG_DIR/config.yml"; then
    log_success "Blue-Green configuration present"
    ((TESTS_PASSED++))
else
    log_error "Blue-Green configuration missing"
    ((TESTS_FAILED++))
fi

# Summary
echo ""
echo "========================================"
echo "           Test Summary                 "
echo "========================================"
echo ""
echo "Total Tests:  $TESTS_RUN"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "All tests passed! Resource Manager is properly configured."
    echo ""
    echo "Next steps:"
    echo "  1. Enable: ./scripts/enable-resource-manager.sh"
    echo "  2. Build:  docker-compose build resource-manager"
    echo "  3. Start:  docker-compose up -d resource-manager"
    echo ""
    exit 0
else
    log_error "$TESTS_FAILED test(s) failed. Please fix the issues above."
    echo ""
    exit 1
fi
