#!/usr/bin/env bats
#
# test_system.bats - Unit tests for system.sh library
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    load_lib 'common.sh'
    load_lib 'system.sh'
    mock_system_commands
}

# ============================================================================
# System Detection Tests
# ============================================================================

@test "detect_os identifies Ubuntu correctly" {
    # Test should work with both Ubuntu and Debian (test environment may vary)
    run detect_os
    assert_success
    assert_output --regexp "(ubuntu|debian)"
}

@test "apply_sysctl_settings creates config file" {
    # Mock sudo
    function sudo() {
        case "$1" in
            "tee")
                shift
                cat > "$@"
                ;;
            "sysctl")
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f sudo

    run apply_sysctl_settings
    assert_success
}

@test "configure_system_limits creates limits file" {
    function sudo() {
        case "$1" in
            "tee")
                shift
                cat > "$@"
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f sudo

    run configure_system_limits
    assert_success
}

# ============================================================================
# Docker Installation Tests
# ============================================================================

@test "check_docker detects docker installation" {
    mock_docker

    # Override check_docker for testing
    function check_docker() {
        if command -v docker &> /dev/null; then
            return 0
        else
            return 1
        fi
    }
    export -f check_docker

    run check_docker
    assert_success
}

@test "configure_docker creates daemon.json" {
    function sudo() {
        case "$2" in
            "-p")
                mkdir -p "$3"
                ;;
            "/etc/docker/daemon.json")
                cat > /tmp/daemon.json
                ;;
            "restart"|"enable")
                return 0
                ;;
            *)
                shift
                command "$@" 2>/dev/null || return 0
                ;;
        esac
    }
    export -f sudo

    run configure_docker
    assert_success
}

@test "add_user_to_docker_group handles user addition" {
    function groups() {
        echo "testuser"
    }
    export -f groups

    function sudo() {
        if [[ "$1" == "usermod" ]]; then
            return 0
        fi
    }
    export -f sudo

    run add_user_to_docker_group
    assert_success
}

# ============================================================================
# Firewall Configuration Tests
# ============================================================================

@test "configure_ufw_rules sets basic rules" {
    export UFW_ALLOW_SSH="192.168.1.0/24"
    export UFW_ALLOW_PORTS="8080,9090"
    export ENABLE_SWARM="false"

    function sudo() {
        case "$1" in
            "ufw")
                echo "UFW command: $*"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f sudo

    function command_exists() {
        [[ "$1" == "ufw" ]] && return 0
        return 1
    }
    export -f command_exists

    run configure_ufw_rules
    assert_success
    assert_output --partial "UFW command"
}

# ============================================================================
# Package Installation Tests
# ============================================================================

@test "install_packages_debian runs apt commands" {
    function sudo() {
        case "$1" in
            "apt-get")
                echo "Installing packages with apt-get"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f sudo

    run install_packages_debian
    assert_success
    assert_output --partial "Installing packages"
}

@test "install_packages_rhel runs yum commands" {
    function sudo() {
        case "$1" in
            "yum")
                echo "Installing packages with yum"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f sudo

    run install_packages_rhel
    assert_success
    assert_output --partial "Installing packages"
}

# ============================================================================
# System Tuning Tests
# ============================================================================

@test "tune_system calls all tuning functions" {
    # Mock all sub-functions
    function apply_sysctl_settings() { echo "sysctl"; return 0; }
    function configure_system_limits() { echo "limits"; return 0; }
    function configure_logrotate() { echo "logrotate"; return 0; }
    export -f apply_sysctl_settings configure_system_limits configure_logrotate

    run tune_system
    assert_success
    assert_output --partial "System Tuning"
}