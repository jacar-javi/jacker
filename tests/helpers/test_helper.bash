#!/usr/bin/env bash
#
# test_helper.bash - Common test helper functions
#

# Load BATS helper libraries
if [ -d '/usr/local/lib/bats-support' ]; then
    load '/usr/local/lib/bats-support/load.bash'
    load '/usr/local/lib/bats-assert/load.bash'
    load '/usr/local/lib/bats-file/load.bash'
elif [ -d "${TEST_DIR}/lib/bats-support" ]; then
    load "${TEST_DIR}/lib/bats-support/load.bash"
    load "${TEST_DIR}/lib/bats-assert/load.bash"
    load "${TEST_DIR}/lib/bats-file/load.bash"
else
    echo "Warning: BATS helper libraries not found, some assertions may fail" >&2
fi

# Project root directory
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ASSETS_DIR="${PROJECT_ROOT}/assets"
export LIB_DIR="${ASSETS_DIR}/lib"
export TEST_DIR="${PROJECT_ROOT}/tests"
export FIXTURES_DIR="${TEST_DIR}/fixtures"

# Test environment
export TEST_ENV_FILE="${TEST_DIR}/fixtures/.env.test"
export TEST_TMP_DIR=""

# Setup function - runs before each test
setup() {
    # Create temporary directory for test
    TEST_TMP_DIR="$(mktemp -d)"
    export TEST_TMP_DIR

    # Change to temp directory
    cd "${TEST_TMP_DIR}" || return 1

    # Copy test fixtures if needed
    if [ -d "${FIXTURES_DIR}" ]; then
        cp -r "${FIXTURES_DIR}"/* . 2>/dev/null || true
    fi

    # Load test environment if exists
    if [ -f "${TEST_ENV_FILE}" ]; then
        set -a
        # shellcheck source=/dev/null
        source "${TEST_ENV_FILE}"
        set +a
    fi
}

# Teardown function - runs after each test
teardown() {
    # Clean up temporary directory
    if [ -n "${TEST_TMP_DIR}" ] && [ -d "${TEST_TMP_DIR}" ]; then
        rm -rf "${TEST_TMP_DIR}"
    fi
}

# Helper function to source library files
load_lib() {
    local lib_name="$1"
    # shellcheck source=/dev/null
    source "${LIB_DIR}/${lib_name}"
}

# Mock function for docker command
mock_docker() {
    function docker() {
        case "$1" in
            "ps")
                echo "mock_container_1"
                echo "mock_container_2"
                ;;
            "compose")
                case "$2" in
                    "ps")
                        echo "NAME                STATUS"
                        echo "jacker_traefik_1   running"
                        echo "jacker_postgres_1  running"
                        ;;
                    "up")
                        echo "Starting services..."
                        return 0
                        ;;
                    "down")
                        echo "Stopping services..."
                        return 0
                        ;;
                    *)
                        echo "Mock docker compose $2"
                        return 0
                        ;;
                esac
                ;;
            "inspect")
                echo '{"State":{"Health":{"Status":"healthy"}}}'
                ;;
            *)
                echo "Mock docker $1"
                return 0
                ;;
        esac
    }
    export -f docker
}

# Mock function for system commands
mock_system_commands() {
    function hostname() {
        echo "test-host"
    }
    export -f hostname

    function id() {
        case "$1" in
            "-u") echo "1000" ;;
            "-g") echo "1000" ;;
            *) echo "uid=1000(testuser) gid=1000(testuser)" ;;
        esac
    }
    export -f id
}

# Helper to create test files
create_test_file() {
    local filename="$1"
    local content="${2:-test content}"
    echo "$content" > "$filename"
}

# Helper to create test directory structure
create_test_structure() {
    mkdir -p data/traefik
    mkdir -p data/crowdsec/config
    mkdir -p compose
    mkdir -p secrets
    touch .env
    touch docker-compose.yml
}

# Assert functions for common checks
assert_env_var() {
    local var_name="$1"
    local expected="${2:-}"

    if [ -n "$expected" ]; then
        assert_equal "${!var_name}" "$expected"
    else
        assert [ -n "${!var_name}" ]
    fi
}

assert_file_contains() {
    local file="$1"
    local content="$2"
    assert_file_exists "$file"
    assert grep -q "$content" "$file"
}

assert_command_succeeds() {
    local cmd="$1"
    run "$cmd"
    assert_success
}

assert_command_fails() {
    local cmd="$1"
    run "$cmd"
    assert_failure
}

# Helper to run function and capture output
run_function() {
    local func_name="$1"
    shift
    run bash -c "source ${LIB_DIR}/common.sh && $func_name $*"
}

# Export all helper functions
export -f load_lib mock_docker mock_system_commands
export -f create_test_file create_test_structure
export -f assert_env_var assert_file_contains
export -f assert_command_succeeds assert_command_fails
export -f run_function