# Jacker Platform Testing Guide

## Overview

This directory contains the comprehensive test suite for the Jacker platform, including unit tests, integration tests, manual testing scripts, and testing utilities. The test suite uses **BATS** (Bash Automated Testing System) for automated testing and provides extensive coverage of all Jacker components.

## Quick Start

### Install Dependencies

```bash
# Install BATS testing framework and helper libraries
./tests/setup_bats.sh

# Verify installation
bats --version
```

### Run Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test types
./tests/run_tests.sh unit          # Unit tests only
./tests/run_tests.sh integration   # Integration tests only
./tests/run_tests.sh shellcheck    # Shell script validation
./tests/run_tests.sh docker        # Docker configuration tests

# Run with verbose output
VERBOSE=true ./tests/run_tests.sh

# Run via Make
make test                  # Run all tests
make test-unit            # Run unit tests
make test-integration     # Run integration tests
```

## Test Structure

```
tests/
├── unit/                   # Unit tests for library modules
│   ├── test_common.bats   # Tests for common.sh (62 tests)
│   ├── test_system.bats   # Tests for system.sh functions
│   ├── test_services.bats # Tests for services.sh functions
│   └── test_stacks.bats   # Tests for stacks.sh functions
│
├── integration/            # Integration tests for complete workflows
│   ├── test_setup.bats    # Setup workflow tests
│   ├── test_full_stack.bats # Full stack deployment tests
│   └── test_jacker_stack.bats # Stack CLI integration tests (19 tests)
│
├── manual/                # Manual testing scripts
│   ├── test_deploy.sh     # Manual deployment test
│   ├── test_setup.sh      # Manual setup test
│   ├── backup_test.sh     # Backup system test
│   ├── restore_test.sh    # Restore system test
│   ├── test_db_backup.sh  # Database backup test
│   ├── test_persistence.sh # Data persistence test
│   ├── test_networks.sh   # Network configuration test
│   └── test_recovery.sh   # Disaster recovery test
│
├── fixtures/              # Test data and configurations
│   └── prometheus.test.yml # Test Prometheus configuration
│
├── helpers/              # Test helper functions and utilities
│   └── test_helper.bash  # BATS helper functions and mocks
│
├── lib/                  # BATS helper libraries (bundled)
│   ├── bats-support/    # BATS support library
│   ├── bats-assert/     # Assertion library
│   └── bats-file/       # File assertion library
│
├── results/             # Test results (auto-generated, gitignored)
├── coverage/            # Coverage reports (optional, gitignored)
│
├── Dockerfile.test      # Test runner Docker image
├── setup_bats.sh       # BATS installation script
├── run_tests.sh        # Main test runner (461 lines)
└── README.md           # This file

```

## Detailed File Documentation

### 📁 Unit Tests (`unit/`)

Unit tests verify individual functions and library modules in isolation without external dependencies.

#### `test_common.bats` (388 lines, 62 tests)
**Purpose:** Tests all functions in `assets/lib/common.sh`

**Test Categories:**
1. **Color and Output Functions** (6 tests)
   - `print_color`, `info`, `success`, `warning`, `error`, `section`
   - Verifies colored output and message formatting

2. **Path and Environment Functions** (4 tests)
   - `get_jacker_root`, `get_data_dir`, `get_compose_dir`, `get_assets_dir`
   - Tests directory path resolution

3. **Environment File Functions** (5 tests)
   - `load_env`, `check_env_exists`, `get_env_var`, `set_env_var`
   - Tests .env file reading/writing

4. **Validation Functions** (24 tests)
   - `validate_hostname`, `validate_domain`, `validate_email`
   - `validate_ip`, `validate_port`
   - Tests input validation with valid and invalid cases

5. **Docker Functions** (3 tests)
   - `check_docker`, `is_container_running`
   - Tests Docker availability and container detection (with mocks)

6. **User Interaction Functions** (7 tests)
   - `confirm_action` with various defaults and inputs
   - Tests Y/N prompts and confirmation logic

7. **File and Directory Functions** (3 tests)
   - `ensure_dir`, `backup_file`, `create_from_template`
   - Tests file operations and template processing

8. **Utility Functions** (4 tests)
   - `generate_password`, `timestamp`, `command_exists`
   - Tests password generation, timestamp format, command detection

**Usage:**
```bash
bats tests/unit/test_common.bats
```

#### `test_system.bats`
**Purpose:** Tests system configuration functions from `assets/lib/system.sh`

**Test Categories:**
- OS detection and validation
- Package installation verification
- System requirements checks
- UFW firewall configuration
- Timezone and locale setup

#### `test_services.bats`
**Purpose:** Tests service management functions from `assets/lib/services.sh`

**Test Categories:**
- Docker Compose service operations
- Service health checks
- Container status verification
- Service startup/shutdown logic

#### `test_stacks.bats`
**Purpose:** Tests stack management functions from `assets/lib/stacks.sh`

**Test Categories:**
- Stack repository management
- Stack discovery and listing
- Stack installation helpers
- Stack validation logic

### 📁 Integration Tests (`integration/`)

Integration tests verify complete workflows and service interactions using real or mocked Docker environments.

#### `test_setup.bats`
**Purpose:** Tests the complete Jacker installation workflow

**Test Scenarios:**
- Environment file generation from templates
- Directory structure creation
- Service configuration setup
- First-round and second-round installation phases
- PostgreSQL and CrowdSec database initialization

**Dependencies:**
- Requires Docker (can use mocks for CI)
- Uses test environment variables

#### `test_full_stack.bats`
**Purpose:** Tests full Jacker platform deployment and operations

**Test Scenarios:**
- Complete stack deployment from scratch
- Service health verification
- Network connectivity between services
- OAuth and authentication flow
- CrowdSec integration
- Monitoring stack (Prometheus, Grafana, Loki)
- Backup and restore operations

**Dependencies:**
- Requires `docker-compose.test.yml` test environment
- Network isolation for testing

#### `test_jacker_stack.bats` (246 lines, 19 tests)
**Purpose:** Integration tests for `stack.sh` CLI tool

**Test Categories:**
1. **CLI Help & Basics** (2 tests)
   - Help command display
   - Unknown command error handling

2. **List & Search** (5 tests)
   - `list` - Show available stacks
   - `search` - Find stacks by keyword
   - `search` with no matches
   - `info` - Show stack details
   - `info` for nonexistent stack (failure case)

3. **Installation** (5 tests)
   - `install` - Basic stack installation
   - `install` with custom name
   - `install` - Prevent duplicate installations
   - `installed` - Show installed stacks
   - `installed` - Empty list when none installed

4. **Uninstall** (2 tests)
   - `uninstall` - Remove stack (requires confirmation, marked as skip)
   - `uninstall` - Fail for nonexistent stack

5. **Repository Management** (1 test)
   - `repos` - List stack repositories

6. **Systemd Integration** (2 tests)
   - `systemd-create` - Fail for uninstalled stack
   - `systemd-list` - Show systemd services

7. **Command Aliases** (2 tests)
   - `ls` alias for `list`
   - `remove` alias for `uninstall`

**Setup:**
- Creates temporary test environment with mock `jacker-stacks` repository
- Mocks Docker and systemctl commands
- Creates sample test stack with docker-compose.yml, README.md, .env.sample

**Usage:**
```bash
bats tests/integration/test_jacker_stack.bats
```

### 📁 Manual Tests (`manual/`)

Manual testing scripts for scenarios that require human verification or real infrastructure.

#### `test_deploy.sh` (30 lines)
**Purpose:** Manual deployment workflow test

**Process:**
1. Creates configuration directories
2. Sets up Traefik, PostgreSQL, Redis, CrowdSec
3. Creates Docker networks
4. Starts all services
5. Performs health checks

**Usage:**
```bash
./tests/manual/test_deploy.sh
```

#### `test_setup.sh`
**Purpose:** Manual test of the complete setup script workflow

**Tests:**
- Interactive prompts
- User input validation
- Configuration file generation
- Real Docker environment setup

#### `backup_test.sh`
**Purpose:** Tests backup system functionality

**Tests:**
- Backup script execution
- Archive creation
- File inclusion/exclusion
- Backup integrity

#### `restore_test.sh`
**Purpose:** Tests restore system functionality

**Tests:**
- Restore from backup
- Configuration restoration
- Data volume restoration
- Service restart after restore

#### `test_db_backup.sh`
**Purpose:** Tests PostgreSQL database backup

**Tests:**
- Database dump creation
- Backup compression
- CrowdSec data export

#### `test_persistence.sh`
**Purpose:** Tests data persistence across restarts

**Tests:**
- Volume mount persistence
- Database data retention
- Configuration preservation
- Certificate persistence

#### `test_networks.sh`
**Purpose:** Tests Docker network configuration

**Tests:**
- Network creation
- Service connectivity
- Network isolation
- Inter-service communication

#### `test_recovery.sh`
**Purpose:** Tests disaster recovery scenarios

**Tests:**
- Service failure recovery
- Database corruption recovery
- Certificate regeneration
- Full system recovery

### 📁 Fixtures (`fixtures/`)

Test data, mock configurations, and sample files used across tests.

#### `prometheus.test.yml` (507 bytes)
**Purpose:** Test configuration for Prometheus service

**Contents:**
- Minimal Prometheus scrape configuration
- Test job definitions
- Used by `docker-compose.test.yml` for integration testing

**Usage:** Mounted into test Prometheus container for integration tests

### 📁 Helpers (`helpers/`)

Shared test helper functions and utilities used across all test files.

#### `test_helper.bash` (184 lines)
**Purpose:** Common test utilities, mocks, and BATS library loading

**Key Components:**

1. **Library Loading** (lines 6-17)
   - Auto-detects BATS helper library locations
   - Loads `bats-support`, `bats-assert`, `bats-file`
   - Fallback for missing libraries with warning

2. **Environment Setup** (lines 19-58)
   - Exports PROJECT_ROOT, ASSETS_DIR, LIB_DIR paths
   - Creates temporary test directories
   - Loads test environment variables
   - Provides setup()/teardown() hooks

3. **Helper Functions**:
   - `load_lib(lib_name)` - Source library files from assets/lib/
   - `mock_docker()` - Mock Docker command responses
   - `mock_system_commands()` - Mock hostname, id commands
   - `create_test_file(filename, content)` - Create test files
   - `create_test_structure()` - Create Jacker directory structure
   - `run_function(func_name, args)` - Execute functions in isolated bash

4. **Custom Assertions**:
   - `assert_env_var(var, expected)` - Check environment variables
   - `assert_file_contains(file, content)` - Verify file contents
   - `assert_command_succeeds(cmd)` - Test command success
   - `assert_command_fails(cmd)` - Test command failure

**Usage in Tests:**
```bash
load '../helpers/test_helper'

setup() {
    load '../helpers/test_helper'
    load_lib 'common.sh'
    create_test_structure
}
```

### 📁 Library (`lib/`)

Bundled BATS helper libraries for local testing without system-wide installation.

#### `bats-support/`
**Purpose:** Core support library for BATS

**Features:**
- Output formatting utilities
- Error handling functions
- Language helpers for test writing

**Documentation:** https://github.com/bats-core/bats-support

#### `bats-assert/`
**Purpose:** Assertion library with rich assertions

**Assertions:**
- `assert_success`, `assert_failure`
- `assert_output`, `assert_line`
- `assert_equal`, `assert_not_equal`
- `assert_regex`, `refute_regex`
- `assert_stderr`, `assert_stderr_line`

**Documentation:** https://github.com/bats-core/bats-assert

#### `bats-file/`
**Purpose:** File system assertion library

**Assertions:**
- `assert_file_exists`, `assert_dir_exists`
- `assert_file_executable`, `assert_file_owner`
- `assert_file_permission`, `assert_file_size_equals`
- `assert_file_contains`, `assert_file_empty`
- `assert_symlink_to`, `assert_sticky_bit`

**Documentation:** https://github.com/bats-core/bats-file

### 📄 Core Test Scripts

#### `setup_bats.sh` (50 lines)
**Purpose:** Automated BATS installation script

**Process:**
1. Checks if BATS already installed
2. Installs bats-core v1.10.0 from GitHub
3. Installs helper libraries: bats-support, bats-assert, bats-file
4. Installs to `/usr/local` (requires sudo)

**Usage:**
```bash
./tests/setup_bats.sh
```

**Alternative Installation:**
```bash
# Via NPM
npm install -g bats

# Via package manager
apt-get install bats  # Ubuntu/Debian
brew install bats-core  # macOS
```

#### `run_tests.sh` (461 lines)
**Purpose:** Comprehensive test runner with multiple test types

**Configuration Variables:**
- `VERBOSE` - Enable verbose output
- `PARALLEL` - Run tests in parallel (experimental)
- `COVERAGE` - Generate coverage report (requires bashcov)
- `TEST_TYPE` - Test type to run (unit, integration, shellcheck, docker, all)

**Functions:**
1. `check_dependencies()` - Verify BATS, Docker, ShellCheck installed
2. `setup_environment()` - Create test directories and export variables
3. `run_unit_tests()` - Execute all unit test files
4. `run_integration_tests()` - Start test environment and run integration tests
5. `run_shellcheck()` - Validate shell scripts with ShellCheck
6. `run_docker_tests()` - Validate Docker Compose configurations
7. `generate_report()` - Create markdown test report
8. `cleanup()` - Stop test containers and clean up

**Test Types:**
- `unit` - Run unit tests only (fast, no Docker required)
- `integration` - Run integration tests (requires Docker)
- `shellcheck` - Lint all shell scripts in assets/
- `docker` - Validate Docker Compose files
- `all` - Run all test types (default)

**Usage:**
```bash
# Run all tests
./tests/run_tests.sh

# Run specific type
./tests/run_tests.sh unit

# With verbose output
VERBOSE=true ./tests/run_tests.sh integration

# Generate coverage
COVERAGE=true ./tests/run_tests.sh
```

**Output:**
- Test results displayed with colored output
- Logs saved to `tests/results/*.log`
- Test report generated as markdown in `tests/results/`

#### `Dockerfile.test` (39 lines)
**Purpose:** Docker image for running tests in containerized environment

**Base Image:** Ubuntu 22.04

**Installed Tools:**
- Bash, Git, Curl, Wget
- Make, Sudo
- Docker CLI
- jq (JSON parsing)
- netcat (network testing)
- BATS v1.10.0
- BATS helper libraries

**User:** testuser (UID 1000, in docker group)

**Usage:**
```bash
# Build test image
docker build -f tests/Dockerfile.test -t jacker-test:latest .

# Run tests in container
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v $PWD:/workspace jacker-test:latest \
  bats tests/unit/

# Interactive testing
docker run -it --rm jacker-test:latest bash
```

## Test Types

### Unit Tests (Fast, ~100ms each)

Unit tests verify individual functions and modules in isolation without external dependencies.

**Characteristics:**
- No Docker required
- Use mocked functions
- Test single function behavior
- Fast execution (<100ms per test)
- Can run in CI without Docker

**Example:**
```bash
@test "validate_hostname accepts valid hostnames" {
    run validate_hostname "my-host"
    assert_success
}
```

### Integration Tests (Slower, ~30s - 5min)

Integration tests verify complete workflows and service interactions using real or test Docker environments.

**Characteristics:**
- Requires Docker and Docker Compose
- Uses `docker-compose.test.yml` test environment
- Tests service interactions
- Verifies complete workflows
- Slower execution (30 seconds to 5 minutes)

**Example:**
```bash
@test "complete stack deployment workflow" {
    # Start test environment
    docker compose -f docker-compose.test.yml up -d

    # Test deployment
    run deploy_stack
    assert_success
    assert_output --partial "Deployment complete"

    # Verify services
    run check_service_health
    assert_success
}
```

### Manual Tests (Human Verification Required)

Manual tests are scripts that require human observation, real infrastructure, or interactive verification.

**When to Use:**
- Testing interactive prompts
- Verifying real SSL certificates
- Testing actual email delivery
- Recovery scenarios requiring manual steps
- Long-running stability tests

## Docker Test Environment

The test suite includes a Docker-based test environment (`docker-compose.test.yml`) that provides:

- Test PostgreSQL database
- Test Redis instance
- Test Traefik proxy
- Test monitoring stack (Prometheus/Grafana)
- Test security stack (CrowdSec)

### Starting Test Environment

```bash
# Start test environment
docker compose -f docker-compose.test.yml up -d

# Run tests against test environment
./tests/run_tests.sh integration

# Stop test environment
docker compose -f docker-compose.test.yml down -v
```

## Writing Tests

### Test Structure

```bash
#!/usr/bin/env bats

# Load helpers
load '../helpers/test_helper'

# Setup runs before each test
setup() {
    load '../helpers/test_helper'
    create_test_structure
}

# Individual test
@test "description of what is being tested" {
    # Arrange
    export TEST_VAR="value"

    # Act
    run function_to_test "argument"

    # Assert
    assert_success
    assert_output --partial "expected output"
}

# Teardown runs after each test
teardown() {
    cleanup_test_files
}
```

### Available Assertions

```bash
# Basic assertions
assert_success              # Command succeeded (exit 0)
assert_failure             # Command failed (non-zero exit)
assert_equal "$a" "$b"     # Values are equal
assert_output "text"       # Exact output match
assert_output --partial    # Partial output match
assert_output --regexp     # Regex match

# File assertions
assert_file_exists "path"
assert_file_not_exists "path"
assert_file_contains "file" "content"
assert_dir_exists "path"

# Custom assertions (from test_helper.bash)
assert_env_var "VAR_NAME" "expected_value"
assert_command_succeeds "command"
assert_command_fails "command"
```

### Mock Functions

The test suite provides mock functions for testing without real system dependencies:

```bash
# Mock Docker
mock_docker() {
    function docker() {
        case "$1" in
            "ps") echo "container_name" ;;
            "compose") echo "Mock compose" ;;
            *) return 0 ;;
        esac
    }
    export -f docker
}

# Mock system commands
mock_system_commands() {
    function hostname() { echo "test-host"; }
    function id() { echo "1000"; }
    export -f hostname id
}
```

## CI/CD Integration

The test suite is integrated with GitHub Actions for continuous testing:

```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./tests/setup_bats.sh
      - run: ./tests/run_tests.sh unit

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./tests/setup_bats.sh
      - run: ./tests/run_tests.sh integration
```

## Test Coverage

Generate test coverage reports (requires bashcov):

```bash
# Install bashcov
gem install bashcov

# Run tests with coverage
COVERAGE=true ./tests/run_tests.sh

# View coverage report
open tests/coverage/index.html
```

## Debugging Tests

### Verbose Output

```bash
# Run with verbose output
VERBOSE=true ./tests/run_tests.sh

# Or for individual test files
bats --verbose-run tests/unit/test_common.bats
```

### Test Isolation

```bash
# Run a single test file
bats tests/unit/test_common.bats

# Run tests matching a pattern
bats tests/unit/test_common.bats --filter "validate"
```

### Debug Output

Add debug output in tests:

```bash
@test "debug example" {
    echo "Debug: VAR=$VAR" >&3
    run command_to_test
    echo "Debug: output=$output" >&3
    assert_success
}
```

## Best Practices

### 1. Test Organization

- Group related tests in the same file
- Use descriptive test names
- Keep tests focused and independent
- Clean up after each test

### 2. Mock Dependencies

- Mock external commands (Docker, system commands)
- Use test fixtures for data
- Avoid network calls in unit tests

### 3. Assertions

- Use specific assertions (not just `assert_success`)
- Test both success and failure cases
- Verify output content, not just exit codes
- Check side effects (file creation, etc.)

### 4. Performance

- Keep unit tests fast (<100ms each)
- Use test environment for integration tests
- Parallelize when possible
- Cache test dependencies

## Troubleshooting

### Common Issues

**BATS not found**
```bash
# Install BATS
./tests/setup_bats.sh

# Or manually
npm install -g bats
```

**Permission denied**
```bash
# Make scripts executable
chmod +x tests/*.sh
chmod +x tests/**/*.bats
```

**Docker not available**
```bash
# Ensure Docker is running
docker version

# For CI environments
services:
  - docker:dind
```

**Test failures**
```bash
# Check logs
cat tests/results/*.log

# Run specific test with verbose output
bats --verbose-run tests/unit/test_common.bats
```

## Contributing

### Adding New Tests

1. Create test file in appropriate directory (unit/ or integration/)
2. Follow naming convention: `test_<module>.bats`
3. Include test helper: `load '../helpers/test_helper'`
4. Write focused, independent tests
5. Update this README if adding new test categories

### Test Review Checklist

- [ ] Tests pass locally
- [ ] Tests are independent (can run in any order)
- [ ] Mocks are properly exported
- [ ] Cleanup is performed in teardown
- [ ] Assertions are specific and meaningful
- [ ] Edge cases are covered
- [ ] Documentation is updated

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS Assert Library](https://github.com/bats-core/bats-assert)
- [BATS File Library](https://github.com/bats-core/bats-file)
- [ShellCheck](https://www.shellcheck.net/)
- [Docker Testing Best Practices](https://docs.docker.com/develop/dev-best-practices/)