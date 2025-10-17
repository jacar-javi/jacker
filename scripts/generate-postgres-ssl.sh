#!/usr/bin/env bash
# ====================================================================
# PostgreSQL SSL Certificate Generation Script
# ====================================================================
# This script generates self-signed SSL certificates for PostgreSQL.
#
# USAGE:
#   ./scripts/generate-postgres-ssl.sh
#
# OUTPUT:
#   - CA certificate: ${DATADIR}/postgres/ssl/ca.crt
#   - CA key: ${DATADIR}/postgres/ssl/ca.key
#   - Server certificate: ${DATADIR}/postgres/ssl/server.crt
#   - Server key: ${DATADIR}/postgres/ssl/server.key
#
# PRODUCTION NOTES:
#   For production environments, replace self-signed certificates with
#   certificates from a trusted Certificate Authority (CA) like Let's Encrypt.
#
#   Using Let's Encrypt certificates:
#   1. Obtain certificates using certbot or similar tools
#   2. Copy the following files to ${DATADIR}/postgres/ssl/:
#      - fullchain.pem -> server.crt
#      - privkey.pem -> server.key
#      - chain.pem -> ca.crt
#   3. Set proper permissions (see below)
#   4. Restart PostgreSQL
# ====================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source environment variables
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

# Set default values
DATADIR="${DATADIR:-${PROJECT_ROOT}/data}"
SSL_DIR="${DATADIR}/postgres/ssl"
CERT_DAYS="${POSTGRES_SSL_CERT_DAYS:-3650}" # 10 years for self-signed
CERT_COUNTRY="${POSTGRES_SSL_COUNTRY:-US}"
CERT_STATE="${POSTGRES_SSL_STATE:-State}"
CERT_CITY="${POSTGRES_SSL_CITY:-City}"
CERT_ORG="${POSTGRES_SSL_ORG:-Organization}"
CERT_OU="${POSTGRES_SSL_OU:-IT Department}"
CERT_CN="${POSTGRES_SSL_CN:-postgres}"
CERT_EMAIL="${POSTGRES_SSL_EMAIL:-admin@localhost}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
}

create_ssl_directory() {
    log_info "Creating SSL directory: ${SSL_DIR}"
    mkdir -p "${SSL_DIR}"
    chmod 755 "${SSL_DIR}"
}

generate_ca_certificate() {
    log_info "Generating CA certificate and key..."

    # Generate CA private key
    openssl genrsa -out "${SSL_DIR}/ca.key" 4096

    # Generate CA certificate
    openssl req -new -x509 -days "${CERT_DAYS}" -key "${SSL_DIR}/ca.key" \
        -out "${SSL_DIR}/ca.crt" \
        -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${CERT_CN}-ca/emailAddress=${CERT_EMAIL}"

    log_info "CA certificate generated successfully"
}

generate_server_certificate() {
    log_info "Generating server certificate and key..."

    # Generate server private key
    openssl genrsa -out "${SSL_DIR}/server.key" 4096

    # Generate certificate signing request (CSR)
    openssl req -new -key "${SSL_DIR}/server.key" \
        -out "${SSL_DIR}/server.csr" \
        -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${CERT_CN}/emailAddress=${CERT_EMAIL}"

    # Create extensions file for Subject Alternative Names (SAN)
    cat > "${SSL_DIR}/server.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = postgres
DNS.2 = localhost
DNS.3 = *.local
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Sign the server certificate with CA
    openssl x509 -req -in "${SSL_DIR}/server.csr" \
        -CA "${SSL_DIR}/ca.crt" \
        -CAkey "${SSL_DIR}/ca.key" \
        -CAcreateserial \
        -out "${SSL_DIR}/server.crt" \
        -days "${CERT_DAYS}" \
        -sha256 \
        -extfile "${SSL_DIR}/server.ext"

    # Clean up temporary files
    rm -f "${SSL_DIR}/server.csr" "${SSL_DIR}/server.ext" "${SSL_DIR}/ca.srl"

    log_info "Server certificate generated successfully"
}

set_permissions() {
    log_info "Setting proper file permissions..."

    # CA certificate (public) - readable by all
    chmod 644 "${SSL_DIR}/ca.crt"

    # CA key (private) - readable only by owner
    chmod 600 "${SSL_DIR}/ca.key"

    # Server certificate (public) - readable by all
    chmod 644 "${SSL_DIR}/server.crt"

    # Server key (private) - readable only by owner
    chmod 600 "${SSL_DIR}/server.key"

    # Set ownership (if running as root, change to postgres user)
    if [[ $EUID -eq 0 ]]; then
        log_info "Setting ownership to postgres user..."
        chown -R 70:70 "${SSL_DIR}" 2>/dev/null || chown -R 999:999 "${SSL_DIR}" 2>/dev/null || true
    else
        log_warn "Not running as root. Ownership may need to be adjusted manually."
        log_warn "Run: sudo chown -R 70:70 ${SSL_DIR} (or 999:999 depending on your postgres image)"
    fi

    log_info "Permissions set successfully"
}

verify_certificates() {
    log_info "Verifying certificates..."

    # Verify CA certificate
    if openssl x509 -in "${SSL_DIR}/ca.crt" -text -noout > /dev/null 2>&1; then
        log_info "CA certificate is valid"
    else
        log_error "CA certificate verification failed"
        exit 1
    fi

    # Verify server certificate
    if openssl x509 -in "${SSL_DIR}/server.crt" -text -noout > /dev/null 2>&1; then
        log_info "Server certificate is valid"
    else
        log_error "Server certificate verification failed"
        exit 1
    fi

    # Verify certificate chain
    if openssl verify -CAfile "${SSL_DIR}/ca.crt" "${SSL_DIR}/server.crt" > /dev/null 2>&1; then
        log_info "Certificate chain is valid"
    else
        log_error "Certificate chain verification failed"
        exit 1
    fi
}

display_certificate_info() {
    log_info "Certificate information:"
    echo ""
    echo "CA Certificate:"
    openssl x509 -in "${SSL_DIR}/ca.crt" -noout -subject -issuer -dates
    echo ""
    echo "Server Certificate:"
    openssl x509 -in "${SSL_DIR}/server.crt" -noout -subject -issuer -dates
    echo ""
}

show_next_steps() {
    log_info "SSL certificates generated successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Restart PostgreSQL to enable SSL:"
    echo "   docker compose restart postgres"
    echo ""
    echo "2. Test SSL connection:"
    echo "   psql \"postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@localhost:5432/\${POSTGRES_DB}?sslmode=require\""
    echo ""
    echo "3. Verify SSL is enabled:"
    echo "   docker compose exec postgres psql -U \${POSTGRES_USER} -d \${POSTGRES_DB} -c 'SHOW ssl;'"
    echo ""
    log_warn "PRODUCTION NOTE: Replace these self-signed certificates with trusted CA certificates"
    log_warn "See script header for instructions on using Let's Encrypt certificates"
}

# Main execution
main() {
    log_info "Starting PostgreSQL SSL certificate generation..."
    echo ""

    check_requirements

    # Check if certificates already exist
    if [[ -f "${SSL_DIR}/server.crt" ]] && [[ -f "${SSL_DIR}/server.key" ]]; then
        log_warn "SSL certificates already exist in ${SSL_DIR}"
        read -rp "Do you want to regenerate them? This will overwrite existing certificates. (y/N): " response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Keeping existing certificates. Exiting."
            exit 0
        fi
        log_warn "Regenerating certificates..."
    fi

    create_ssl_directory
    generate_ca_certificate
    generate_server_certificate
    set_permissions
    verify_certificates
    display_certificate_info
    show_next_steps

    log_info "Done!"
}

# Run main function
main "$@"
