#!/bin/bash
# Fix Promtail excessive Docker labels causing HTTP 400 errors from Loki
#
# Problem: Promtail's labelmap was converting ALL Docker labels to Loki labels,
# causing high cardinality and exceeding Loki's label limits.
#
# Solution: Remove the broad labelmap and only keep essential labels.

set -e

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine Jacker root directory
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi

cd "$JACKER_DIR"

echo "=== Fixing Promtail Docker Label Issues ==="
echo ""

PROMTAIL_CONFIG="data/loki/promtail-config.yml"

# Check if Promtail config exists
if [ ! -f "$PROMTAIL_CONFIG" ]; then
    echo "❌ Promtail config not found: $JACKER_DIR/$PROMTAIL_CONFIG"
    echo "   Is this a Jacker installation?"
    exit 1
fi

# Backup the current config
BACKUP_FILE="$PROMTAIL_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
cp "$PROMTAIL_CONFIG" "$BACKUP_FILE"
echo "✓ Created backup: $BACKUP_FILE"
echo ""

# Check if the problematic labelmap exists
if grep -q "action: labelmap" "$PROMTAIL_CONFIG"; then
    echo "Found problematic labelmap configuration..."
    echo ""

    # Create the fixed configuration
    cat > "$PROMTAIL_CONFIG" <<'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0
  log_level: info

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker containers log scraping
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      # Container name as a label
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'

      # Container ID as a label
      - source_labels: ['__meta_docker_container_id']
        target_label: 'container_id'

      # Image name as a label
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'

      # Docker compose project
      - source_labels: ['__meta_docker_container_label_com_docker_compose_project']
        target_label: 'compose_project'

      # Docker compose service
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'compose_service'

      # Optional: Add homepage labels if they exist (for organization)
      - source_labels: ['__meta_docker_container_label_homepage_group']
        target_label: 'app_group'

      - source_labels: ['__meta_docker_container_label_homepage_name']
        target_label: 'app_name'

      # Note: Removed broad labelmap to prevent high cardinality
      # and HTTP 400 errors from Loki due to excessive labels

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOSTNAME}
          __path__: /var/log/*.log

  # Traefik access logs
  - job_name: traefik
    static_configs:
      - targets:
          - localhost
        labels:
          job: traefik
          host: ${HOSTNAME}
          __path__: /logs/traefik/access.log
    pipeline_stages:
      - json:
          expressions:
            level: level
            msg: msg
      - labels:
          level:
EOF

    echo "✓ Applied fixed Promtail configuration"
    echo ""
    echo "Changes made:"
    echo "  - Removed broad labelmap that captured all Docker labels"
    echo "  - Kept essential labels: container, compose_project, compose_service"
    echo "  - Added selective homepage labels for organization"
    echo "  - Reduced label cardinality for better Loki performance"
    echo ""
else
    echo "✓ No problematic labelmap found - config may already be fixed"
    echo ""
fi

# Show label count
echo "Labels now being sent to Loki:"
echo "  - container (container name)"
echo "  - container_id (container ID)"
echo "  - stream (stdout/stderr)"
echo "  - compose_project (Docker Compose project)"
echo "  - compose_service (Docker Compose service name)"
echo "  - app_group (from homepage label, if set)"
echo "  - app_name (from homepage label, if set)"
echo ""
echo "Total: ~7 labels (was 20+ with labelmap)"
echo ""

# Restart Promtail if Docker is available
if command -v docker &> /dev/null && [ -f "Makefile" ]; then
    echo "Restarting Promtail service..."
    make restart service=promtail 2>&1 || true

    echo ""
    echo "Waiting for Promtail to start..."
    sleep 3

    echo ""
    echo "Checking Promtail status..."
    make ps 2>&1 | grep promtail || true
    echo ""
else
    echo "⚠️  Docker not available - please restart Promtail manually:"
    echo "   make restart service=promtail"
    echo "   or"
    echo "   docker compose restart promtail"
    echo ""
fi

echo "=== Fix Complete ==="
echo ""
echo "Promtail should now send logs to Loki without HTTP 400 errors."
echo ""
echo "To verify:"
echo "  make logs service=promtail"
echo "  (should no longer show 'HTTP status 400 Bad Request' errors)"
echo ""
echo "To restore previous config:"
echo "  cp $BACKUP_FILE $PROMTAIL_CONFIG"
echo "  make restart service=promtail"
echo ""
