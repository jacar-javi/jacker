.PHONY: help up down restart logs status health update clean backup restore

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

.DEFAULT_GOAL := help

## help: Display this help message
help:
	@echo "$(BLUE){STACK_NAME} - Management Commands$(NC)"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /' | column -t -s ':'
	@echo ""

# ============================================================================
# DOCKER COMPOSE COMMANDS
# ============================================================================

## up: Start {STACK_NAME}
up:
	@echo "$(GREEN)Starting {STACK_NAME}...$(NC)"
	@docker compose up -d
	@make status

## down: Stop {STACK_NAME}
down:
	@echo "$(YELLOW)Stopping {STACK_NAME}...$(NC)"
	@docker compose down

## restart: Restart {STACK_NAME}
restart:
	@make down
	@make up

## logs: View logs
logs:
	@docker compose logs -f

## logs-follow: Follow logs in real-time
logs-follow:
	@docker compose logs -f {SERVICE_NAME}

## status: Show service status
status:
	@echo "$(BLUE)Service Status:$(NC)"
	@docker compose ps

## ps: Alias for status
ps: status

## pull: Pull latest images
pull:
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@docker compose pull

## update: Update to latest version
update:
	@echo "$(BLUE)Updating {STACK_NAME}...$(NC)"
	@docker compose pull
	@docker compose up -d
	@echo "$(GREEN)Update complete!$(NC)"

# ============================================================================
# HEALTH & MONITORING
# ============================================================================

## health: Check service health
health:
	@echo "$(BLUE)Health Check:$(NC)"
	@docker compose ps

## stats: Show resource usage
stats:
	@docker compose stats --no-stream

## top: Show running processes
top:
	@docker compose top

## inspect: Inspect service configuration
inspect:
	@docker compose config

# ============================================================================
# DATABASE MANAGEMENT (if applicable - remove if not needed)
# ============================================================================

## db-shell: Open database shell
db-shell:
	@docker compose exec {DB_SERVICE} {DB_SHELL_COMMAND}

## db-backup: Backup database
db-backup:
	@echo "$(BLUE)Backing up database...$(NC)"
	@mkdir -p backups
	@docker compose exec {DB_SERVICE} {DB_BACKUP_COMMAND} > backups/db_backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)Backup created!$(NC)"

## db-restore: Restore database (use BACKUP=file.sql)
db-restore:
ifndef BACKUP
	@echo "$(RED)ERROR: BACKUP not specified$(NC)"
	@echo "Usage: make db-restore BACKUP=backup_file.sql"
	@exit 1
endif
	@echo "$(YELLOW)Restoring database from $(BACKUP)...$(NC)"
	@cat $(BACKUP) | docker compose exec -T {DB_SERVICE} {DB_RESTORE_COMMAND}
	@echo "$(GREEN)Database restored!$(NC)"

# ============================================================================
# BACKUP & RESTORE (general)
# ============================================================================

## backup: Create full backup
backup:
	@echo "$(BLUE)Creating backup...$(NC)"
	@mkdir -p backups
	@tar czf backups/{STACK_NAME}_backup_$(shell date +%Y%m%d_%H%M%S).tar.gz data/
	@echo "$(GREEN)Backup created!$(NC)"

## backup-list: List available backups
backup-list:
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -lh backups/ 2>/dev/null || echo "No backups found"

## restore: Restore from backup (use BACKUP=file.tar.gz)
restore:
ifndef BACKUP
	@echo "$(RED)ERROR: BACKUP not specified$(NC)"
	@echo "Usage: make restore BACKUP=backup_file.tar.gz"
	@exit 1
endif
	@echo "$(YELLOW)Restoring from $(BACKUP)...$(NC)"
	@docker compose down
	@tar xzf $(BACKUP)
	@docker compose up -d
	@echo "$(GREEN)Restore complete!$(NC)"

# ============================================================================
# MAINTENANCE
# ============================================================================

## clean: Clean up unused resources
clean:
	@echo "$(YELLOW)Cleaning up...$(NC)"
	@docker compose down --remove-orphans
	@docker system prune -f
	@echo "$(GREEN)Cleanup complete!$(NC)"

## clean-all: Clean up everything including volumes
clean-all:
	@echo "$(RED)WARNING: This will delete all data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v --remove-orphans; \
		rm -rf data/; \
		echo "$(GREEN)Complete cleanup done!$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

## prune: Remove unused Docker resources
prune:
	@echo "$(YELLOW)Pruning Docker resources...$(NC)"
	@docker system prune -af --volumes
	@echo "$(GREEN)Prune complete!$(NC)"

# ============================================================================
# SYSTEMD SERVICE MANAGEMENT
# ============================================================================

## systemd-create: Create systemd service
systemd-create:
	@echo "$(BLUE)Creating systemd service...$(NC)"
	@if [ ! -f systemd/{STACK_NAME}.service.template ]; then \
		echo "$(RED)ERROR: systemd template not found$(NC)"; \
		exit 1; \
	fi
	@sudo cp systemd/{STACK_NAME}.service.template /etc/systemd/system/jacker-{STACK_NAME}.service
	@sudo sed -i "s|/path/to/{STACK_NAME}|$(shell pwd)|g" /etc/systemd/system/jacker-{STACK_NAME}.service
	@sudo systemctl daemon-reload
	@echo "$(GREEN)Systemd service created!$(NC)"

## systemd-enable: Enable systemd service
systemd-enable:
	@sudo systemctl enable jacker-{STACK_NAME}
	@echo "$(GREEN)Systemd service enabled!$(NC)"

## systemd-disable: Disable systemd service
systemd-disable:
	@sudo systemctl disable jacker-{STACK_NAME}
	@echo "$(YELLOW)Systemd service disabled!$(NC)"

## systemd-start: Start systemd service
systemd-start:
	@sudo systemctl start jacker-{STACK_NAME}
	@echo "$(GREEN)Systemd service started!$(NC)"

## systemd-stop: Stop systemd service
systemd-stop:
	@sudo systemctl stop jacker-{STACK_NAME}
	@echo "$(YELLOW)Systemd service stopped!$(NC)"

## systemd-restart: Restart systemd service
systemd-restart:
	@sudo systemctl restart jacker-{STACK_NAME}
	@echo "$(GREEN)Systemd service restarted!$(NC)"

## systemd-status: Show systemd service status
systemd-status:
	@sudo systemctl status jacker-{STACK_NAME}

## systemd-logs: View systemd service logs
systemd-logs:
	@sudo journalctl -u jacker-{STACK_NAME} -f

## systemd-remove: Remove systemd service
systemd-remove:
	@sudo systemctl stop jacker-{STACK_NAME} 2>/dev/null || true
	@sudo systemctl disable jacker-{STACK_NAME} 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/jacker-{STACK_NAME}.service
	@sudo systemctl daemon-reload
	@echo "$(YELLOW)Systemd service removed!$(NC)"

# ============================================================================
# DEVELOPMENT & TESTING
# ============================================================================

## shell: Open shell in main container
shell:
	@docker compose exec {SERVICE_NAME} sh

## bash: Open bash in main container
bash:
	@docker compose exec {SERVICE_NAME} bash

## root-shell: Open root shell in main container
root-shell:
	@docker compose exec -u root {SERVICE_NAME} sh

## config: Validate Docker Compose configuration
config:
	@docker compose config

## version: Show component versions
version:
	@echo "$(BLUE)Component Versions:$(NC)"
	@docker compose images

## networks: Show Docker networks
networks:
	@echo "$(BLUE)Docker Networks:$(NC)"
	@docker network ls | grep {STACK_NAME}

## volumes: Show Docker volumes
volumes:
	@echo "$(BLUE)Docker Volumes:$(NC)"
	@docker volume ls | grep {STACK_NAME}

# ============================================================================
# LOGS & DEBUGGING
# ============================================================================

## logs-tail: View last N lines of logs (use LINES=100)
logs-tail:
	@docker compose logs --tail=${LINES:-100}

## logs-service: View logs for specific service (use SERVICE=name)
logs-service:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make logs-service SERVICE=service_name"
	@exit 1
endif
	@docker compose logs -f $(SERVICE)

## logs-error: View only error logs
logs-error:
	@docker compose logs | grep -i error

## logs-export: Export logs to file
logs-export:
	@mkdir -p logs
	@docker compose logs > logs/{STACK_NAME}_logs_$(shell date +%Y%m%d_%H%M%S).log
	@echo "$(GREEN)Logs exported!$(NC)"

# ============================================================================
# SECURITY & PERMISSIONS
# ============================================================================

## fix-permissions: Fix data directory permissions
fix-permissions:
	@echo "$(BLUE)Fixing permissions...$(NC)"
	@sudo chown -R ${PUID:-1000}:${PGID:-1000} data/
	@echo "$(GREEN)Permissions fixed!$(NC)"

## scan: Scan images for vulnerabilities (requires trivy)
scan:
	@echo "$(BLUE)Scanning images for vulnerabilities...$(NC)"
	@docker compose config --images | xargs -I {} trivy image {}

# ============================================================================
# QUICK REFERENCE
# ============================================================================

## quick-start: Quick start guide
quick-start:
	@echo "$(BLUE){STACK_NAME} Quick Start$(NC)"
	@echo ""
	@echo "1. Configure .env with your settings"
	@echo "2. Start service: $(GREEN)make up$(NC)"
	@echo "3. Access: $(GREEN)https://{SERVICE_NAME}.$$PUBLIC_FQDN$(NC)"
	@echo ""
	@echo "For help: $(GREEN)make help$(NC)"

## env-check: Check required environment variables
env-check:
	@echo "$(BLUE)Checking environment variables...$(NC)"
	@if [ -f .env ]; then \
		echo "$(GREEN)✓ .env file exists$(NC)"; \
	else \
		echo "$(RED)✗ .env file missing$(NC)"; \
		echo "$(YELLOW)Run: cp .env.sample .env$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Environment check complete!$(NC)"

## info: Display stack information
info:
	@echo "$(BLUE){STACK_NAME} Information$(NC)"
	@echo ""
	@echo "Status: $(shell docker compose ps --format '{{.Service}}: {{.State}}' 2>/dev/null || echo 'Not running')"
	@echo "Uptime: $(shell docker compose ps --format '{{.Service}}: {{.Status}}' 2>/dev/null || echo 'N/A')"
	@echo ""
	@echo "URLs:"
	@echo "  - https://{SERVICE_NAME}.$$PUBLIC_FQDN"
	@echo ""
