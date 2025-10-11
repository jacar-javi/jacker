#!/usr/bin/env bats
#
# test_stacks.bats - Unit tests for stacks.sh library
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    load_lib 'common.sh'
    load_lib 'stacks.sh'
    mock_docker
    create_test_structure
}

# ============================================================================
# Configuration Tests
# ============================================================================

@test "get_stacks_dir returns correct path" {
    run get_stacks_dir
    assert_success
    assert_output --regexp "jacker-stacks$"
}

@test "get_installed_dir returns correct path" {
    run get_installed_dir
    assert_success
    assert_output --regexp "stacks$"
}

@test "get_config_dir returns correct path" {
    run get_config_dir
    assert_success
    assert_output --regexp ".jacker$"
}

@test "get_repos_file returns correct path" {
    run get_repos_file
    assert_success
    assert_output --regexp "repositories.json$"
}

@test "init_stack_dirs creates required directories" {
    run init_stack_dirs
    assert_success

    local installed_dir="$(get_installed_dir)"
    local config_dir="$(get_config_dir)"

    assert [ -d "$installed_dir" ]
    assert [ -d "$config_dir" ]
}

# ============================================================================
# Repository Management Tests
# ============================================================================

@test "init_default_repos creates repos file" {
    local repos_file="$(get_repos_file)"
    [ -f "$repos_file" ] && rm "$repos_file"

    run init_default_repos
    assert_success

    assert [ -f "$repos_file" ]
    assert_file_contains "$repos_file" "jacker-stacks"
}

@test "init_default_repos does not overwrite existing repos" {
    local repos_file="$(get_repos_file)"
    init_default_repos

    # Modify file
    local original_content="$(cat "$repos_file")"
    echo "# test comment" >> "$repos_file"

    # Run again
    init_default_repos

    # File should still have our comment
    assert_file_contains "$repos_file" "# test comment"
}

@test "list_repos returns repository list" {
    function jq() {
        echo "jacker-stacks|local|true"
        echo "awesome-compose|git|false"
    }
    export -f jq

    run list_repos
    assert_success
    assert_output --partial "jacker-stacks"
}

@test "add_repo adds new repository" {
    function jq() {
        if [[ "$1" == "-e" ]]; then
            # Check if exists - return false
            return 1
        else
            # Add repo - just echo success
            cat
        fi
    }
    export -f jq

    function command_exists() {
        [[ "$1" == "jq" ]] && return 0
        return 1
    }
    export -f command_exists

    run add_repo "https://github.com/test/repo.git"
    assert_success
    assert_output --partial "Added repository"
}

@test "remove_repo removes repository" {
    function jq() {
        cat  # Just pass through
    }
    export -f jq

    function command_exists() {
        [[ "$1" == "jq" ]] && return 0
        return 1
    }
    export -f command_exists

    run remove_repo "test-repo"
    assert_success
    assert_output --partial "Removed repository"
}

# ============================================================================
# Stack Discovery Tests
# ============================================================================

@test "find_stacks returns empty when no stacks_dir" {
    function get_stacks_dir() {
        echo "/nonexistent"
    }
    export -f get_stacks_dir

    run find_stacks
    assert_success
    assert_output ""
}

@test "find_stacks discovers stacks" {
    # Create mock stack structure
    local stacks_dir="$(get_stacks_dir)"
    mkdir -p "$stacks_dir/category1/stack1"
    echo "# Stack 1" > "$stacks_dir/category1/stack1/README.md"
    touch "$stacks_dir/category1/stack1/docker-compose.yml"

    run find_stacks
    assert_success
    assert_output --partial "category1/stack1"
}

@test "find_stacks filters by search query" {
    local stacks_dir="$(get_stacks_dir)"
    mkdir -p "$stacks_dir/cat/wordpress"
    mkdir -p "$stacks_dir/cat/nextcloud"
    touch "$stacks_dir/cat/wordpress/docker-compose.yml"
    touch "$stacks_dir/cat/nextcloud/docker-compose.yml"

    run find_stacks "wordpress"
    assert_success
    assert_output --partial "wordpress"
    refute_output --partial "nextcloud"
}

@test "list_stacks_simple returns sorted stacks" {
    local stacks_dir="$(get_stacks_dir)"
    # First clear any existing stacks from previous tests
    rm -rf "$stacks_dir"
    mkdir -p "$stacks_dir/cat/stack-b"
    mkdir -p "$stacks_dir/cat/stack-a"
    touch "$stacks_dir/cat/stack-b/docker-compose.yml"
    touch "$stacks_dir/cat/stack-a/docker-compose.yml"

    run list_stacks_simple
    assert_success
    # Output should be sorted - first line should be stack-a
    assert_line --index 0 --partial "cat/stack-a"
}

@test "get_stack_path finds stack by name" {
    local stacks_dir="$(get_stacks_dir)"
    mkdir -p "$stacks_dir/category/mystack"
    touch "$stacks_dir/category/mystack/docker-compose.yml"

    run get_stack_path "mystack"
    assert_success
    assert_output --partial "category/mystack"
}

@test "get_stack_path fails for nonexistent stack" {
    run get_stack_path "nonexistent"
    assert_failure
}

@test "get_stack_info returns stack information" {
    local stacks_dir="$(get_stacks_dir)"
    mkdir -p "$stacks_dir/cat/teststack"
    echo "# Test Stack Description" > "$stacks_dir/cat/teststack/README.md"
    cat > "$stacks_dir/cat/teststack/docker-compose.yml" <<EOF
services:
  web:
    image: nginx
  db:
    image: postgres
EOF

    run get_stack_info "teststack"
    assert_success
    assert_output --partial "Test Stack"
}

# ============================================================================
# Stack Installation Tests
# ============================================================================

@test "install_stack installs a stack" {
    local stacks_dir="$(get_stacks_dir)"
    local install_dir="$(get_installed_dir)"

    # Clear any previously installed stack
    rm -rf "$install_dir/mystack"

    # Create source stack
    mkdir -p "$stacks_dir/cat/mystack"
    touch "$stacks_dir/cat/mystack/docker-compose.yml"
    echo "VAR=value" > "$stacks_dir/cat/mystack/.env.sample"

    run install_stack "mystack"
    assert_success
    assert [ -d "$install_dir/mystack" ]
    assert [ -f "$install_dir/mystack/.env" ]
}

@test "install_stack fails if already installed" {
    local install_dir="$(get_installed_dir)"
    mkdir -p "$install_dir/mystack"

    run install_stack "mystack"
    assert_failure
    assert_output --partial "already installed"
}

@test "install_stack fails for nonexistent stack" {
    run install_stack "nonexistent"
    assert_failure
    assert_output --partial "not found"
}

@test "uninstall_stack removes a stack" {
    local install_dir="$(get_installed_dir)"
    mkdir -p "$install_dir/teststack"
    touch "$install_dir/teststack/docker-compose.yml"

    run uninstall_stack "teststack"
    assert_success
    assert [ ! -d "$install_dir/teststack" ]
}

@test "uninstall_stack fails for nonexistent stack" {
    run uninstall_stack "nonexistent"
    assert_failure
    assert_output --partial "not installed"
}

@test "list_installed_stacks returns empty when none installed" {
    local install_dir="$(get_installed_dir)"
    # Clear any previously installed stacks from other tests
    rm -rf "$install_dir"
    mkdir -p "$install_dir"

    run list_installed_stacks
    assert_success
    assert_output ""
}

@test "list_installed_stacks returns installed stacks" {
    local install_dir="$(get_installed_dir)"
    mkdir -p "$install_dir/stack1"
    mkdir -p "$install_dir/stack2"
    touch "$install_dir/stack1/docker-compose.yml"
    touch "$install_dir/stack2/docker-compose.yml"

    run list_installed_stacks
    assert_success
    assert_output --partial "stack1"
    assert_output --partial "stack2"
}

@test "is_stack_installed returns true for installed stack" {
    local install_dir="$(get_installed_dir)"
    mkdir -p "$install_dir/mystack"

    run is_stack_installed "mystack"
    assert_success
}

@test "is_stack_installed returns false for nonexistent stack" {
    run is_stack_installed "nonexistent"
    assert_failure
}

# ============================================================================
# Systemd Service Tests
# ============================================================================

@test "get_systemd_service_name returns correct name" {
    run get_systemd_service_name "mystack"
    assert_success
    assert_output "jacker-mystack.service"
}

@test "get_systemd_service_path returns correct path" {
    run get_systemd_service_path "mystack"
    assert_success
    assert_output "/etc/systemd/system/jacker-mystack.service"
}

@test "systemd_service_exists checks if service file exists" {
    function get_systemd_service_path() {
        echo "/tmp/test-service.service"
    }
    export -f get_systemd_service_path

    touch "/tmp/test-service.service"
    run systemd_service_exists "mystack"
    assert_success

    rm "/tmp/test-service.service"
    run systemd_service_exists "mystack"
    assert_failure
}

@test "systemd_create_service requires installed stack" {
    run systemd_create_service "nonexistent"
    assert_failure
    assert_output --partial "not installed"
}

@test "systemd_create_service creates service file" {
    skip "Requires sudo and systemctl - integration test"
}

@test "systemd_remove_service requires existing service" {
    function systemd_service_exists() {
        return 1
    }
    export -f systemd_service_exists

    run systemd_remove_service "mystack"
    assert_failure
    assert_output --partial "not found"
}

@test "systemd_list_services returns services" {
    function systemctl() {
        if [[ "$1" == "list-unit-files" ]]; then
            echo "jacker-stack1.service"
            echo "jacker-stack2.service"
        elif [[ "$1" == "is-enabled" ]]; then
            echo "enabled"
        elif [[ "$1" == "is-active" ]]; then
            echo "active"
        fi
    }
    export -f systemctl

    run systemd_list_services
    assert_success
    assert_output --partial "stack1"
    assert_output --partial "stack2"
}
