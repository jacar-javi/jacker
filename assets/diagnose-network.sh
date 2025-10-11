#!/usr/bin/env bash
#
# diagnose-network.sh - Network diagnostics for Jacker external access
#

set -euo pipefail

# Source common functions first (provides colors and helper functions)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        JACKER NETWORK DIAGNOSTICS                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Load environment
cd_jacker_root
load_env

section "Configuration Check"

info "Domain: $PUBLIC_FQDN"
info "Let's Encrypt Email: ${LETSENCRYPT_EMAIL:-Not configured}"

# Check if using placeholder domain
if [[ "$DOMAINNAME" == "example.com" ]] || [[ "$DOMAINNAME" == "localhost" ]]; then
    error "You are using a placeholder domain: $DOMAINNAME"
    echo ""
    echo "This will NOT work for external access!"
    echo "You need to:"
    echo "  1. Own a real domain name"
    echo "  2. Update configuration: make reconfigure-domain"
    echo ""
    exit 1
fi

section "DNS Resolution Check"

echo "Testing DNS resolution for your domain..."
echo ""

# Get public IP
PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "Unable to detect")
info "Your server's public IP: $PUBLIC_IP"

# Check DNS resolution
echo ""
echo "Checking DNS records..."
echo ""

# Check main domain
RESOLVED_IP=$(dig +short "$PUBLIC_FQDN" 2>/dev/null | head -1)
if [ -z "$RESOLVED_IP" ]; then
    error "$PUBLIC_FQDN does not resolve to any IP"
    echo ""
    echo "DNS is NOT configured! You need to add DNS records:"
    echo ""
    echo "  A     $PUBLIC_FQDN                → $PUBLIC_IP"
    echo "  A     traefik.$DOMAINNAME         → $PUBLIC_IP"
    echo "  A     portainer.$DOMAINNAME       → $PUBLIC_IP"
    echo "  A     grafana.$DOMAINNAME         → $PUBLIC_IP"
    echo "  CNAME *.$DOMAINNAME               → $PUBLIC_FQDN"
    echo ""
    echo "Or use a wildcard record:"
    echo "  A     *.$DOMAINNAME               → $PUBLIC_IP"
    echo ""
    DNS_CONFIGURED=false
else
    if [ "$RESOLVED_IP" == "$PUBLIC_IP" ]; then
        success "$PUBLIC_FQDN resolves to $RESOLVED_IP ✓"
        DNS_CONFIGURED=true
    else
        warning "$PUBLIC_FQDN resolves to $RESOLVED_IP but server is at $PUBLIC_IP"
        echo ""
        echo "DNS record points to wrong IP!"
        echo "Update your DNS A record to point to: $PUBLIC_IP"
        echo ""
        DNS_CONFIGURED=false
    fi
fi

section "Port Accessibility Check"

if [ "$DNS_CONFIGURED" = true ]; then
    echo "Testing if ports are accessible from outside..."
    echo ""

    # Test HTTP (port 80)
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/80" 2>/dev/null; then
        success "Port 80 (HTTP) is accessible ✓"
        HTTP_OK=true
    else
        error "Port 80 (HTTP) is NOT accessible"
        HTTP_OK=false
    fi

    # Test HTTPS (port 443)
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/443" 2>/dev/null; then
        success "Port 443 (HTTPS) is accessible ✓"
        HTTPS_OK=true
    else
        error "Port 443 (HTTPS) is NOT accessible"
        HTTPS_OK=false
    fi

    echo ""

    if [ "$HTTP_OK" = false ] || [ "$HTTPS_OK" = false ]; then
        warning "Ports are not accessible!"
        echo ""
        echo "This could be due to:"
        echo "  1. Cloud provider firewall/security groups blocking ports"
        echo "  2. ISP blocking incoming connections"
        echo "  3. UFW configuration issue (though UFW shows open)"
        echo ""
        echo "Check your cloud provider's firewall settings:"
        echo "  • AWS: Security Groups"
        echo "  • Azure: Network Security Groups"
        echo "  • GCP: Firewall Rules"
        echo "  • OpenStack: Security Groups"
        echo ""
        echo "Ensure these ports are allowed:"
        echo "  • Port 22 (SSH) from your IP"
        echo "  • Port 80 (HTTP) from anywhere (0.0.0.0/0)"
        echo "  • Port 443 (HTTPS) from anywhere (0.0.0.0/0)"
        echo ""
    fi
else
    warning "Skipping port check (DNS not configured)"
fi

section "UFW Firewall Status"

echo "Local firewall rules:"
echo ""
sudo ufw status numbered | grep -E "(80|443)" || echo "No HTTP/HTTPS rules found"

section "SSL Certificate Status"

echo "Checking SSL certificates..."
echo ""

ACME_JSON="$DATADIR/traefik/acme/acme.json"
if [ -f "$ACME_JSON" ] && [ -s "$ACME_JSON" ]; then
    CERT_COUNT=$(jq '.le.Certificates | length' "$ACME_JSON" 2>/dev/null || echo "0")
    if [ "$CERT_COUNT" -gt 0 ]; then
        success "Let's Encrypt certificates present: $CERT_COUNT domain(s)"

        # Show certificate domains
        DOMAINS=$(jq -r '.le.Certificates[].domain.main' "$ACME_JSON" 2>/dev/null || echo "")
        if [ -n "$DOMAINS" ]; then
            echo ""
            echo "Certificates for:"
            echo "$DOMAINS" | while read -r domain; do
                echo "  • $domain"
            done
        fi
    else
        warning "No Let's Encrypt certificates found"
        echo ""
        echo "Certificates will be generated when:"
        echo "  1. DNS is properly configured"
        echo "  2. Ports 80/443 are accessible"
        echo "  3. You access a service URL in your browser"
    fi
else
    warning "acme.json is empty or missing"
fi

section "Traefik Status"

if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    success "Traefik is running"

    # Check Traefik logs for errors (grep returns 1 if no matches, so use || true)
    ERROR_COUNT=$(docker logs traefik 2>&1 | { grep -i "error\|fail" || true; } | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        warning "Found $ERROR_COUNT errors in Traefik logs"
        echo ""
        echo "Recent errors:"
        docker logs traefik 2>&1 | { grep -i "error\|fail" || true; } | tail -5
    fi
else
    error "Traefik is not running!"
fi

section "Summary & Recommendations"

echo ""

if [ "$DNS_CONFIGURED" = false ]; then
    echo -e "${RED}❌ DNS NOT CONFIGURED${NC}"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Go to your domain registrar (Namecheap, GoDaddy, Cloudflare, etc.)"
    echo "  2. Add an A record:"
    echo "     Type: A"
    echo "     Name: * (wildcard) or specific subdomain"
    echo "     Value: $PUBLIC_IP"
    echo "     TTL: 300 (5 minutes)"
    echo "  3. Wait for DNS propagation (5-30 minutes)"
    echo "  4. Run this script again: ./assets/diagnose-network.sh"
    echo ""
elif [ "${HTTP_OK:-false}" = false ] || [ "${HTTPS_OK:-false}" = false ]; then
    echo -e "${YELLOW}⚠️  DNS CONFIGURED BUT PORTS BLOCKED${NC}"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Check cloud provider firewall/security groups"
    echo "  2. Ensure ports 80 and 443 are open from 0.0.0.0/0"
    echo "  3. Restart Traefik: docker restart traefik"
    echo "  4. Check Traefik logs: docker logs traefik"
    echo ""
else
    echo -e "${GREEN}✓ CONFIGURATION LOOKS GOOD${NC}"
    echo ""
    echo "Access your services at:"
    echo "  • https://traefik.$DOMAINNAME"
    echo "  • https://portainer.$DOMAINNAME"
    echo "  • https://grafana.$DOMAINNAME"
    echo ""
    if [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
        warning "Let's Encrypt not configured - using self-signed certificates"
        echo "To enable SSL: make reconfigure-ssl"
    fi
fi

echo ""

# Exit successfully
exit 0
