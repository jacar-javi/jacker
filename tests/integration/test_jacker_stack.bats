#!/usr/bin/env bats
#
# test_jacker_stack.bats - Integration tests for stack.sh CLI
#

load '../helpers/test_helper'

setup() {
    load '../helpers/test_helper'

    # Setup test environment
    export TEST_ROOT="$(mktemp -d)"
    export JACKER_ROOT="$TEST_ROOT"

    # Create directory structure
    mkdir -p "$TEST_ROOT/jacker-stacks/category/teststack"
    mkdir -p "$TEST_ROOT/stacks"
    mkdir -p "$TEST_ROOT/.jacker"
    mkdir -p "$TEST_ROOT/assets/lib"

    # Copy stack.sh
    cp "$PROJECT_ROOT/assets/stack.sh" "$TEST_ROOT/"

    # Copy libraries to the same directory as stack.sh (it sources $SCRIPT_DIR/lib/*.sh)
    cp -r "$PROJECT_ROOT/assets/lib" "$TEST_ROOT/"

    # Create test stack
    cat > "$TEST_ROOT/jacker-stacks/category/teststack/docker-compose.yml" <<EOF
services:
  web:
    image: nginx:latest
EOF

    echo "# Test Stack" > "$TEST_ROOT/jacker-stacks/category/teststack/README.md"
    echo "ENV_VAR=value" > "$TEST_ROOT/jacker-stacks/category/teststack/.env.sample"

    # Mock docker and systemctl
    function docker() {
        return 0
    }
    export -f docker

    function systemctl() {
        return 0
    }
    export -f systemctl

    function sudo() {
        "$@"
    }
    export -f sudo

    cd "$TEST_ROOT"
}

teardown() {
    # Cleanup
    [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

# ============================================================================
# CLI Help & Basics Tests
# ============================================================================

@test "stack.sh shows help" {
    run ./stack.sh help
    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "COMMANDS"
}

@test "stack.sh unknown command shows error" {
    run ./stack.sh invalid_command
    assert_failure
    assert_output --partial "Unknown command"
}

# ============================================================================
# List & Search Tests
# ============================================================================

@test "stack.sh list shows available stacks" {
    run ./stack.sh list
    assert_success
    assert_output --partial "Available Stacks"
    assert_output --partial "teststack"
}

@test "stack.sh search finds stacks" {
    run ./stack.sh search test
    assert_success
    assert_output --partial "Search results"
    assert_output --partial "teststack"
}

@test "stack.sh search with no matches" {
    run ./stack.sh search nonexistent_xyz
    assert_success
    assert_output --partial "Found: 0"
}

@test "stack.sh info shows stack details" {
    run ./stack.sh info teststack
    assert_success
    assert_output --partial "Stack Information"
    assert_output --partial "teststack"
    assert_output --partial "Test Stack"
}

@test "stack.sh info for nonexistent stack fails" {
    run ./stack.sh info nonexistent
    assert_failure
    assert_output --partial "not found"
}

# ============================================================================
# Installation Tests
# ============================================================================

@test "stack.sh install installs a stack" {
    run ./stack.sh install teststack
    assert_success
    assert_output --partial "Stack installed"

    # Verify installation
    assert [ -d "$TEST_ROOT/stacks/teststack" ]
    assert [ -f "$TEST_ROOT/stacks/teststack/docker-compose.yml" ]
    assert [ -f "$TEST_ROOT/stacks/teststack/.env" ]
}

@test "stack.sh install with custom name" {
    run ./stack.sh install teststack mycustomname
    assert_success

    assert [ -d "$TEST_ROOT/stacks/mycustomname" ]
}

@test "stack.sh install fails for already installed stack" {
    ./stack.sh install teststack

    run ./stack.sh install teststack
    assert_failure
    assert_output --partial "already installed"
}

@test "stack.sh installed shows installed stacks" {
    # Install a stack first
    ./stack.sh install teststack

    run ./stack.sh installed
    assert_success
    assert_output --partial "Installed Stacks"
    assert_output --partial "teststack"
}

@test "stack.sh installed shows empty when none installed" {
    run ./stack.sh installed
    assert_success
    assert_output --partial "No stacks installed"
}

# ============================================================================
# Uninstall Tests
# ============================================================================

@test "stack.sh uninstall removes a stack" {
    skip "Requires interactive confirmation - manual test"
}

@test "stack.sh uninstall fails for nonexistent stack" {
    run ./stack.sh uninstall nonexistent
    assert_failure
    assert_output --partial "not installed"
}

# ============================================================================
# Repository Tests
# ============================================================================

@test "stack.sh repos lists repositories" {
    # Need jq for repos
    function command_exists() {
        [[ "$1" == "jq" ]] && return 0
        return 1
    }
    export -f command_exists

    function jq() {
        case "$1" in
            "-r")
                echo "jacker-stacks|local|true"
                ;;
            *)
                cat
                ;;
        esac
    }
    export -f jq

    run ./stack.sh repos
    assert_success
    assert_output --partial "Stack Repositories"
}

# ============================================================================
# Systemd Tests
# ============================================================================

@test "stack.sh systemd-create requires installed stack" {
    run ./stack.sh systemd-create nonexistent
    assert_failure
    assert_output --partial "not installed"
}

@test "stack.sh systemd-list shows services" {
    function systemctl() {
        if [[ "$1" == "list-unit-files" ]]; then
            echo "jacker-teststack.service enabled"
        elif [[ "$1" == "is-enabled" ]]; then
            echo "enabled"
        elif [[ "$1" == "is-active" ]]; then
            echo "active"
        fi
    }
    export -f systemctl

    run ./stack.sh systemd-list
    assert_success
    assert_output --partial "Systemd Services"
}

# ============================================================================
# Command Aliases Tests
# ============================================================================

@test "stack.sh ls is alias for list" {
    run ./stack.sh ls
    assert_success
    assert_output --partial "Available Stacks"
}

@test "stack.sh remove is alias for uninstall" {
    run ./stack.sh remove nonexistent
    assert_failure
    assert_output --partial "not installed"
}
