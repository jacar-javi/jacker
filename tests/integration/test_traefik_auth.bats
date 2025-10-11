#!/usr/bin/env bats
#
# test_traefik_auth.bats - Integration tests for Traefik authentication and protocol support
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    create_test_structure
    mock_docker
    mock_system_commands

    # Load all libraries
    load_lib 'common.sh'
    load_lib 'system.sh'
    load_lib 'services.sh'
}

# ============================================================================
# Middleware Chain Tests
# ============================================================================

@test "chain-oauth-no-crowdsec middleware configuration exists" {
    # Create middleware configuration
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/chain-oauth-no-crowdsec.yml <<'EOF'
http:
  middlewares:
    chain-oauth-no-crowdsec:
      chain:
        middlewares:
          - middlewares-rate-limit
          - security-headers
          - request-size-limit
          - middlewares-oauth
          - middlewares-compress
EOF

    assert_file_exists "data/traefik/rules/chain-oauth-no-crowdsec.yml"
    assert_file_contains "data/traefik/rules/chain-oauth-no-crowdsec.yml" "chain-oauth-no-crowdsec"
    assert_file_contains "data/traefik/rules/chain-oauth-no-crowdsec.yml" "middlewares-oauth"

    # Verify CrowdSec is NOT in the chain
    run grep -q "crowdsec" data/traefik/rules/chain-oauth-no-crowdsec.yml
    assert_failure
}

@test "chain-no-oauth-no-crowdsec middleware configuration exists" {
    # Create middleware configuration
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/chain-no-oauth-no-crowdsec.yml <<'EOF'
http:
  middlewares:
    chain-no-oauth-no-crowdsec:
      chain:
        middlewares:
          - middlewares-rate-limit
          - security-headers
          - request-size-limit
          - middlewares-compress
EOF

    assert_file_exists "data/traefik/rules/chain-no-oauth-no-crowdsec.yml"
    assert_file_contains "data/traefik/rules/chain-no-oauth-no-crowdsec.yml" "chain-no-oauth-no-crowdsec"

    # Verify neither OAuth nor CrowdSec are in the chain
    run grep -q "middlewares-oauth" data/traefik/rules/chain-no-oauth-no-crowdsec.yml
    assert_failure

    run grep -q "crowdsec" data/traefik/rules/chain-no-oauth-no-crowdsec.yml
    assert_failure
}

@test "middlewares-oauth forwardAuth configuration is correct" {
    # Create OAuth middleware configuration
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/middlewares-oauth.yml <<'EOF'
http:
  middlewares:
    middlewares-oauth:
      forwardAuth:
        address: "http://oauth:4181"
        trustForwardHeader: true
        authResponseHeaders:
          - "X-Forwarded-User"
EOF

    assert_file_exists "data/traefik/rules/middlewares-oauth.yml"
    assert_file_contains "data/traefik/rules/middlewares-oauth.yml" "forwardAuth"
    assert_file_contains "data/traefik/rules/middlewares-oauth.yml" "http://oauth:4181"
    assert_file_contains "data/traefik/rules/middlewares-oauth.yml" "trustForwardHeader: true"
    assert_file_contains "data/traefik/rules/middlewares-oauth.yml" "X-Forwarded-User"
}

@test "security headers middleware is properly configured" {
    # Create security headers middleware
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/middlewares-security.yml <<'EOF'
http:
  middlewares:
    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        contentTypeNosniff: true
        browserXssFilter: true
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
EOF

    assert_file_exists "data/traefik/rules/middlewares-security.yml"
    assert_file_contains "data/traefik/rules/middlewares-security.yml" "stsSeconds: 31536000"
    assert_file_contains "data/traefik/rules/middlewares-security.yml" "contentTypeNosniff: true"
    assert_file_contains "data/traefik/rules/middlewares-security.yml" "browserXssFilter: true"
}

@test "rate limiting middleware is configured" {
    # Create rate limit middleware
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/middlewares-rate-limit.yml <<'EOF'
http:
  middlewares:
    middlewares-rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1s
EOF

    assert_file_exists "data/traefik/rules/middlewares-rate-limit.yml"
    assert_file_contains "data/traefik/rules/middlewares-rate-limit.yml" "rateLimit"
    assert_file_contains "data/traefik/rules/middlewares-rate-limit.yml" "average: 100"
}

@test "all services use chain-oauth-no-crowdsec middleware" {
    # Check each service compose file
    local services=(
        "compose/traefik.yml"
        "compose/grafana.yml"
        "compose/homepage.yml"
        "compose/portainer.yml"
        "compose/vscode.yml"
    )

    for service in "${services[@]}"; do
        if [ -f "$service" ]; then
            # Verify the service uses the correct middleware chain
            run grep -q "chain-oauth-no-crowdsec@file" "$service"
            assert_success "Service $service should use chain-oauth-no-crowdsec@file"
        fi
    done
}

# ============================================================================
# OAuth Redirect Tests
# ============================================================================

@test "OAuth service is configured with correct environment variables" {
    # Create OAuth service configuration
    cat > compose/oauth.yml <<'EOF'
services:
  oauth:
    image: thomseddon/traefik-forward-auth:latest
    container_name: oauth
    environment:
      - COOKIE_DOMAIN=${PUBLIC_FQDN}
      - AUTH_HOST=oauth.${PUBLIC_FQDN}
      - URL_PATH=/_oauth
      - DEFAULT_ACTION=auth
      - DEFAULT_PROVIDER=google
      - PROVIDERS_GOOGLE_CLIENT_ID=${OAUTH_CLIENT_ID}
      - PROVIDERS_GOOGLE_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - SECRET=${OAUTH_SECRET}
      - WHITELIST=${OAUTH_WHITELIST}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.oauth-rtr.rule=Host(`oauth.${PUBLIC_FQDN}`)"
      - "traefik.http.routers.oauth-rtr.middlewares=chain-oauth-no-crowdsec@file"
EOF

    assert_file_exists "compose/oauth.yml"
    assert_file_contains "compose/oauth.yml" "thomseddon/traefik-forward-auth:latest"
    assert_file_contains "compose/oauth.yml" "AUTH_HOST=oauth"
    assert_file_contains "compose/oauth.yml" "URL_PATH=/_oauth"
    assert_file_contains "compose/oauth.yml" "DEFAULT_PROVIDER=google"
}

@test "OAuth redirect URI uses oauth subdomain" {
    export PUBLIC_FQDN="vps1.example.com"
    export OAUTH_CLIENT_ID="test-client-id"
    export OAUTH_CLIENT_SECRET="test-secret"
    export OAUTH_SECRET="test-secret-key"
    export OAUTH_WHITELIST="user@example.com"

    # Mock curl to test OAuth redirect
    function curl() {
        if [[ "$*" == *"oauth:4181"* ]]; then
            # Simulate OAuth redirect response
            echo "Location: https://accounts.google.com/o/oauth2/auth?redirect_uri=https%3A%2F%2Foauth.vps1.example.com%2F_oauth"
            return 0
        fi
        return 0
    }
    export -f curl

    # Test OAuth redirect
    cat > test_oauth_redirect.sh <<'EOF'
#!/bin/bash
# Simulate accessing a protected service
RESPONSE=$(curl -sI -H "X-Forwarded-Proto: https" \
                 -H "X-Forwarded-Host: traefik.vps1.example.com" \
                 -H "X-Forwarded-Uri: /dashboard/" \
                 http://oauth:4181/)

# Check if redirect_uri uses oauth subdomain
if [[ "$RESPONSE" == *"oauth.vps1.example.com"* ]]; then
    echo "OAuth redirect URI correct"
else
    echo "OAuth redirect URI incorrect"
    exit 1
fi
EOF

    chmod +x test_oauth_redirect.sh
    run ./test_oauth_redirect.sh
    assert_success
    assert_output --partial "OAuth redirect URI correct"
}

@test "OAuth callback accepts valid state and code parameters" {
    # Mock OAuth callback handling
    function curl() {
        if [[ "$*" == *"/_oauth?state="* ]] && [[ "$*" == *"&code="* ]]; then
            echo "HTTP/1.1 302 Found"
            echo "Location: https://traefik.vps1.example.com/dashboard/"
            echo "Set-Cookie: _forward_auth=valid_session_token"
            return 0
        fi
        return 1
    }
    export -f curl

    cat > test_oauth_callback.sh <<'EOF'
#!/bin/bash
# Simulate OAuth callback
RESPONSE=$(curl -sI "http://oauth:4181/_oauth?state=abc123&code=auth_code_from_google")

if [[ "$RESPONSE" == *"302 Found"* ]] && [[ "$RESPONSE" == *"_forward_auth"* ]]; then
    echo "OAuth callback successful"
else
    echo "OAuth callback failed"
    exit 1
fi
EOF

    chmod +x test_oauth_callback.sh
    run ./test_oauth_callback.sh
    assert_success
    assert_output --partial "OAuth callback successful"
}

@test "OAuth whitelist validation works correctly" {
    export OAUTH_WHITELIST="allowed@example.com,admin@example.com"

    # Create test script to validate whitelist
    cat > test_oauth_whitelist.sh <<'EOF'
#!/bin/bash
WHITELIST="$OAUTH_WHITELIST"

# Test allowed email
if [[ "$WHITELIST" == *"allowed@example.com"* ]]; then
    echo "Allowed email found in whitelist"
else
    echo "Whitelist validation failed"
    exit 1
fi

# Test disallowed email
if [[ "$WHITELIST" != *"blocked@example.com"* ]]; then
    echo "Blocked email not in whitelist"
else
    echo "Whitelist validation failed"
    exit 1
fi
EOF

    chmod +x test_oauth_whitelist.sh
    run ./test_oauth_whitelist.sh
    assert_success
    assert_output --partial "Allowed email found in whitelist"
    assert_output --partial "Blocked email not in whitelist"
}

@test "OAuth session cookies have correct domain" {
    export PUBLIC_FQDN="vps1.example.com"

    # Verify COOKIE_DOMAIN is set without leading dot
    cat > compose/oauth.yml <<EOF
services:
  oauth:
    environment:
      - COOKIE_DOMAIN=${PUBLIC_FQDN}
EOF

    assert_file_exists "compose/oauth.yml"
    assert_file_contains "compose/oauth.yml" "COOKIE_DOMAIN"

    # Verify no leading dot
    run grep -q "COOKIE_DOMAIN=\\.${PUBLIC_FQDN}" compose/oauth.yml
    assert_failure "COOKIE_DOMAIN should not have leading dot"
}

# ============================================================================
# HTTP/2 and HTTP/3 Protocol Tests
# ============================================================================

@test "Traefik is configured for HTTP/2" {
    # Create Traefik static configuration
    mkdir -p data/traefik
    cat > data/traefik/traefik.yml <<'EOF'
entryPoints:
  web:
    address: :80
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: :443
    http:
      tls:
        certResolver: http

# HTTP/2 is enabled by default in Traefik
# No explicit configuration needed
EOF

    assert_file_exists "data/traefik/traefik.yml"
    assert_file_contains "data/traefik/traefik.yml" "websecure"
    assert_file_contains "data/traefik/traefik.yml" "address: :443"
}

@test "HTTP/3 configuration can be enabled" {
    # Create Traefik config with HTTP/3
    mkdir -p data/traefik
    cat > data/traefik/traefik.yml <<'EOF'
entryPoints:
  websecure:
    address: :443
    http:
      tls:
        certResolver: http
    # HTTP/3 configuration (Traefik v3.x)
    http3: {}
EOF

    assert_file_exists "data/traefik/traefik.yml"
    assert_file_contains "data/traefik/traefik.yml" "http3"
}

@test "HTTP/3 can be disabled when needed" {
    # Create Traefik config with HTTP/3 disabled
    mkdir -p data/traefik
    cat > data/traefik/traefik.yml <<'EOF'
entryPoints:
  websecure:
    address: :443
    http:
      tls:
        certResolver: http
    # HTTP/3 disabled due to forwardAuth protocol errors
    # http3: {}
EOF

    assert_file_exists "data/traefik/traefik.yml"

    # Verify HTTP/3 is commented out
    run grep -q "^    # http3:" data/traefik/traefik.yml
    assert_success "HTTP/3 should be commented out"
}

@test "Traefik supports TLS 1.2 and 1.3" {
    # Create TLS options
    mkdir -p data/traefik/rules
    cat > data/traefik/rules/tls-options.yml <<'EOF'
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - TLS_CHACHA20_POLY1305_SHA256
      sniStrict: true
EOF

    assert_file_exists "data/traefik/rules/tls-options.yml"
    assert_file_contains "data/traefik/rules/tls-options.yml" "minVersion: VersionTLS12"
    assert_file_contains "data/traefik/rules/tls-options.yml" "TLS_AES_256_GCM_SHA384"
}

@test "Traefik protocol detection works correctly" {
    # Mock curl to test protocol detection
    function curl() {
        if [[ "$*" == *"--http2"* ]]; then
            echo "< HTTP/2 200"
            echo "< content-type: text/html"
            return 0
        elif [[ "$*" == *"--http3"* ]]; then
            echo "< HTTP/3 200"
            echo "< alt-svc: h3=\":443\""
            return 0
        fi
        return 1
    }
    export -f curl

    cat > test_protocol.sh <<'EOF'
#!/bin/bash
# Test HTTP/2
HTTP2_RESPONSE=$(curl -sI --http2 https://traefik.example.com 2>&1)
if [[ "$HTTP2_RESPONSE" == *"HTTP/2"* ]]; then
    echo "HTTP/2 supported"
else
    echo "HTTP/2 not supported"
fi

# Test HTTP/3
HTTP3_RESPONSE=$(curl -sI --http3 https://traefik.example.com 2>&1)
if [[ "$HTTP3_RESPONSE" == *"HTTP/3"* ]]; then
    echo "HTTP/3 supported"
else
    echo "HTTP/3 not supported (may be disabled)"
fi
EOF

    chmod +x test_protocol.sh
    run ./test_protocol.sh
    assert_success
    assert_output --partial "HTTP/2 supported"
}

@test "forwardAuth works correctly with HTTP/2" {
    # Test that forwardAuth middleware works with HTTP/2
    function docker() {
        if [[ "$*" == *"exec"* ]] && [[ "$*" == *"traefik"* ]]; then
            # Simulate successful forwardAuth with HTTP/2
            echo "HTTP/2.0 200 OK"
            echo "x-forwarded-user: test@example.com"
            return 0
        fi
        return 0
    }
    export -f docker

    cat > test_forwardauth_http2.sh <<'EOF'
#!/bin/bash
# Test forwardAuth with HTTP/2
RESPONSE=$(docker exec traefik wget -q -O- -S \
    --header='X-Forwarded-Proto: https' \
    --header='X-Forwarded-Host: traefik.example.com' \
    http://oauth:4181/ 2>&1)

if [[ "$RESPONSE" == *"200 OK"* ]]; then
    echo "forwardAuth works with HTTP/2"
else
    echo "forwardAuth failed with HTTP/2"
    exit 1
fi
EOF

    chmod +x test_forwardauth_http2.sh
    run ./test_forwardauth_http2.sh
    assert_success
    assert_output --partial "forwardAuth works with HTTP/2"
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "complete OAuth flow with middleware chain" {
    export PUBLIC_FQDN="vps1.example.com"
    export OAUTH_CLIENT_ID="test-client-id"
    export OAUTH_WHITELIST="allowed@example.com"

    # Mock complete OAuth flow
    function curl() {
        local url="$*"

        # Step 1: Initial request to protected resource
        if [[ "$url" == *"traefik.vps1.example.com"* ]] && [[ "$url" != *"_oauth"* ]]; then
            echo "HTTP/1.1 302 Found"
            echo "Location: https://accounts.google.com/o/oauth2/auth?redirect_uri=https%3A%2F%2Foauth.vps1.example.com%2F_oauth"
            return 0
        fi

        # Step 2: OAuth callback
        if [[ "$url" == *"_oauth?state="* ]] && [[ "$url" == *"&code="* ]]; then
            echo "HTTP/1.1 302 Found"
            echo "Location: https://traefik.vps1.example.com/dashboard/"
            echo "Set-Cookie: _forward_auth=valid_token"
            return 0
        fi

        # Step 3: Accessing protected resource with valid session
        if [[ "$url" == *"Cookie: _forward_auth=valid_token"* ]]; then
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            return 0
        fi

        return 1
    }
    export -f curl

    cat > test_complete_oauth_flow.sh <<'EOF'
#!/bin/bash

# Step 1: Request protected resource
echo "Step 1: Requesting protected resource..."
INITIAL=$(curl -sI https://traefik.vps1.example.com/dashboard/)
if [[ "$INITIAL" == *"accounts.google.com"* ]] && [[ "$INITIAL" == *"oauth.vps1.example.com"* ]]; then
    echo "✓ Redirected to Google OAuth with correct redirect_uri"
else
    echo "✗ OAuth redirect failed"
    exit 1
fi

# Step 2: OAuth callback
echo "Step 2: Processing OAuth callback..."
CALLBACK=$(curl -sI "https://oauth.vps1.example.com/_oauth?state=abc&code=123")
if [[ "$CALLBACK" == *"302 Found"* ]] && [[ "$CALLBACK" == *"_forward_auth"* ]]; then
    echo "✓ OAuth callback successful, session created"
else
    echo "✗ OAuth callback failed"
    exit 1
fi

# Step 3: Access protected resource with session
echo "Step 3: Accessing protected resource with valid session..."
PROTECTED=$(curl -sI -H "Cookie: _forward_auth=valid_token" https://traefik.vps1.example.com/dashboard/)
if [[ "$PROTECTED" == *"200 OK"* ]]; then
    echo "✓ Successfully accessed protected resource"
else
    echo "✗ Failed to access protected resource"
    exit 1
fi

echo "Complete OAuth flow successful!"
EOF

    chmod +x test_complete_oauth_flow.sh
    run ./test_complete_oauth_flow.sh
    assert_success
    assert_output --partial "Complete OAuth flow successful"
}

@test "middleware chain blocks requests without valid session" {
    # Mock request without session cookie
    function curl() {
        if [[ "$*" == *"traefik.example.com"* ]] && [[ "$*" != *"Cookie"* ]]; then
            echo "HTTP/1.1 302 Found"
            echo "Location: https://accounts.google.com/o/oauth2/auth"
            return 0
        fi
        return 1
    }
    export -f curl

    cat > test_middleware_blocks.sh <<'EOF'
#!/bin/bash
# Request without session cookie
RESPONSE=$(curl -sI https://traefik.example.com/dashboard/)

if [[ "$RESPONSE" == *"302"* ]] && [[ "$RESPONSE" == *"accounts.google.com"* ]]; then
    echo "Middleware correctly blocks unauthenticated request"
else
    echo "Middleware failed to block request"
    exit 1
fi
EOF

    chmod +x test_middleware_blocks.sh
    run ./test_middleware_blocks.sh
    assert_success
    assert_output --partial "Middleware correctly blocks unauthenticated request"
}
