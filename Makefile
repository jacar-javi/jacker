.PHONY: help install update clean start stop restart logs status validate health backup restore test shell

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

## help: Display this help message
help:
	@echo "$(BLUE)Jacker - Docker Stack Management$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /' | column -t -s ':'
	@echo ""

## install: Run initial installation
install:
	@echo "$(BLUE)Starting Jacker installation...$(NC)"
	@./assets/setup.sh

## update: Update all Docker images and containers
update:
	@echo "$(BLUE)Updating Jacker...$(NC)"
	@./assets/update.sh

## clean: Remove all Jacker data and configuration
clean:
	@echo "$(RED)Cleaning Jacker...$(NC)"
	@./assets/clean.sh

## start: Start all services
start:
	@echo "$(GREEN)Starting services...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)Services started!$(NC)"
	@make status

## stop: Stop all services
stop:
	@echo "$(YELLOW)Stopping services...$(NC)"
	@docker compose down
	@echo "$(YELLOW)Services stopped!$(NC)"

## restart: Restart all services
restart: stop start

## restart-service: Restart a specific service (usage: make restart-service SERVICE=traefik)
restart-service:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make restart-service SERVICE=traefik"
	@exit 1
endif
	@echo "$(YELLOW)Restarting $(SERVICE)...$(NC)"
	@docker compose restart $(SERVICE)
	@echo "$(GREEN)$(SERVICE) restarted!$(NC)"

## logs: View logs from all services
logs:
	@docker compose logs -f

## logs-service: View logs from a specific service (usage: make logs-service SERVICE=traefik)
logs-service:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make logs-service SERVICE=traefik"
	@exit 1
endif
	@docker compose logs -f $(SERVICE)

## status: Show status of all services
status:
	@echo "$(BLUE)Service Status:$(NC)"
	@docker compose ps

## ps: Alias for status
ps: status

## validate: Validate installation and configuration
validate:
	@echo "$(BLUE)Validating Jacker installation...$(NC)"
	@./assets/validate.sh

## health: Check health of all services
health:
	@./assets/health-check.sh

## health-watch: Watch health status in real-time
health-watch:
	@./assets/health-check.sh --watch

## backup: Create a backup (usage: make backup [BACKUP_DIR=/path/to/backup])
backup:
ifdef BACKUP_DIR
	@echo "$(BLUE)Creating backup to $(BACKUP_DIR)...$(NC)"
	@./assets/backup.sh $(BACKUP_DIR)
else
	@echo "$(BLUE)Creating backup...$(NC)"
	@./assets/backup.sh
endif

## restore: Restore from backup (usage: make restore BACKUP=/path/to/backup)
restore:
ifndef BACKUP
	@echo "$(RED)ERROR: BACKUP path not specified$(NC)"
	@echo "Usage: make restore BACKUP=/path/to/backup"
	@exit 1
endif
	@echo "$(BLUE)Restoring from $(BACKUP)...$(NC)"
	@./assets/restore.sh $(BACKUP)

## test: Run automated tests (usage: make test [MODE=quick|full|ci])
test:
ifdef MODE
	@./assets/test.sh --$(MODE)
else
	@./assets/test.sh
endif

## test-quick: Run quick tests only
test-quick:
	@./assets/test.sh --quick

## test-full: Run full test suite
test-full:
	@./assets/test.sh --full

## shell: Open a shell in a service container (usage: make shell SERVICE=traefik)
shell:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make shell SERVICE=traefik"
	@exit 1
endif
	@docker compose exec $(SERVICE) sh || docker compose exec $(SERVICE) bash

## pull: Pull latest images
pull:
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@docker compose pull

## prune: Clean up unused Docker resources
prune:
	@echo "$(YELLOW)Cleaning up Docker resources...$(NC)"
	@docker system prune -f
	@docker volume prune -f
	@echo "$(GREEN)Cleanup complete!$(NC)"

## config: Validate and view Docker Compose configuration
config:
	@docker compose config

## crowdsec-decisions: Show CrowdSec decisions
crowdsec-decisions:
	@cscli decisions list

## crowdsec-bouncers: Show CrowdSec bouncers
crowdsec-bouncers:
	@cscli bouncers list

## crowdsec-metrics: Show CrowdSec metrics
crowdsec-metrics:
	@cscli metrics

## crowdsec-update: Update CrowdSec collections
crowdsec-update:
	@echo "$(BLUE)Updating CrowdSec collections...$(NC)"
	@cscli collections upgrade --all
	@docker compose restart crowdsec

## ufw-status: Show UFW firewall status
ufw-status:
	@sudo ufw status verbose

## ufw-reload: Reload UFW firewall
ufw-reload:
	@sudo ufw reload

## cert-renew: Force SSL certificate renewal
cert-renew:
	@echo "$(BLUE)Forcing certificate renewal...$(NC)"
	@rm -f data/traefik/acme.json
	@touch data/traefik/acme.json
	@chmod 600 data/traefik/acme.json
	@docker compose restart traefik
	@echo "$(GREEN)Traefik restarted. Certificates will be renewed automatically.$(NC)"

## rotate-secrets: Rotate secrets (OAuth, API keys)
rotate-secrets:
	@echo "$(BLUE)Rotating secrets...$(NC)"
	@./assets/rotate-secrets.sh

## version: Show versions of all components
version:
	@echo "$(BLUE)Component Versions:$(NC)"
	@echo ""
	@echo "Docker: $$(docker --version)"
	@echo "Docker Compose: $$(docker compose version --short)"
	@docker compose ps --format "table {{.Name}}\t{{.Image}}"

## rebuild: Rebuild and restart all services
rebuild:
	@echo "$(YELLOW)Rebuilding services...$(NC)"
	@docker compose up -d --force-recreate --build
	@echo "$(GREEN)Rebuild complete!$(NC)"

## rebuild-service: Rebuild a specific service (usage: make rebuild-service SERVICE=traefik)
rebuild-service:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make rebuild-service SERVICE=traefik"
	@exit 1
endif
	@echo "$(YELLOW)Rebuilding $(SERVICE)...$(NC)"
	@docker compose up -d --force-recreate $(SERVICE)
	@echo "$(GREEN)$(SERVICE) rebuilt!$(NC)"

## stats: Show resource usage statistics
stats:
	@docker stats --no-stream

## disk-usage: Show Docker disk usage
disk-usage:
	@docker system df -v

## stack-list: List available stacks
stack-list:
	@./assets/jacker-stack list

## stack-search: Search for stacks (usage: make stack-search QUERY=wordpress)
stack-search:
ifndef QUERY
	@echo "$(RED)ERROR: QUERY not specified$(NC)"
	@echo "Usage: make stack-search QUERY=wordpress"
	@exit 1
endif
	@./assets/jacker-stack search $(QUERY)

## stack-info: Show stack information (usage: make stack-info STACK=wordpress)
stack-info:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-info STACK=wordpress"
	@exit 1
endif
	@./assets/jacker-stack info $(STACK)

## stack-install: Install a stack (usage: make stack-install STACK=wordpress)
stack-install:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-install STACK=wordpress"
	@exit 1
endif
	@./assets/jacker-stack install $(STACK)

## stack-uninstall: Uninstall a stack (usage: make stack-uninstall STACK=wordpress)
stack-uninstall:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-uninstall STACK=wordpress"
	@exit 1
endif
	@./assets/jacker-stack uninstall $(STACK)

## stack-installed: List installed stacks
stack-installed:
	@./assets/jacker-stack installed

## tracing-enable: Enable Traefik distributed tracing with Jaeger
tracing-enable:
	@echo "$(BLUE)Enabling Traefik tracing...$(NC)"
	@if grep -q "^TRAEFIK_TRACING_ENABLED=false" .env 2>/dev/null; then \
		sed -i 's/^TRAEFIK_TRACING_ENABLED=false/TRAEFIK_TRACING_ENABLED=true/' .env; \
		echo "$(GREEN)✓ TRAEFIK_TRACING_ENABLED set to true in .env$(NC)"; \
	elif grep -q "^TRAEFIK_TRACING_ENABLED=true" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Tracing already enabled in .env$(NC)"; \
	else \
		echo "TRAEFIK_TRACING_ENABLED=true" >> .env; \
		echo "$(GREEN)✓ TRAEFIK_TRACING_ENABLED added to .env$(NC)"; \
	fi
	@if ! grep -q "^  - compose/jaeger.yml" docker-compose.yml 2>/dev/null; then \
		sed -i '/^include:/a\  - compose/jaeger.yml' docker-compose.yml; \
		echo "$(GREEN)✓ Jaeger service added to docker-compose.yml$(NC)"; \
	else \
		echo "$(YELLOW)⚠ Jaeger already in docker-compose.yml$(NC)"; \
	fi
	@if grep -q "^# tracing:" data/traefik/traefik.yml 2>/dev/null; then \
		sed -i '/^# tracing:/,/^#     disableAttemptReconnecting: true/s/^# //' data/traefik/traefik.yml; \
		echo "$(GREEN)✓ Tracing section uncommented in traefik.yml$(NC)"; \
	elif grep -q "^tracing:" data/traefik/traefik.yml 2>/dev/null; then \
		echo "$(YELLOW)⚠ Tracing already uncommented in traefik.yml$(NC)"; \
	else \
		echo "$(RED)✗ Tracing section not found in traefik.yml$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)Starting Jaeger...$(NC)"
	@docker compose up -d jaeger
	@echo "$(BLUE)Restarting Traefik...$(NC)"
	@docker compose restart traefik
	@echo ""
	@echo "$(GREEN)✓ Tracing enabled successfully!$(NC)"
	@echo "$(BLUE)Access Jaeger UI at: https://jaeger.$$(grep PUBLIC_FQDN .env | cut -d'=' -f2)$(NC)"

## tracing-disable: Disable Traefik distributed tracing
tracing-disable:
	@echo "$(BLUE)Disabling Traefik tracing...$(NC)"
	@if grep -q "^TRAEFIK_TRACING_ENABLED=true" .env 2>/dev/null; then \
		sed -i 's/^TRAEFIK_TRACING_ENABLED=true/TRAEFIK_TRACING_ENABLED=false/' .env; \
		echo "$(GREEN)✓ TRAEFIK_TRACING_ENABLED set to false in .env$(NC)"; \
	elif grep -q "^TRAEFIK_TRACING_ENABLED=false" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Tracing already disabled in .env$(NC)"; \
	else \
		echo "TRAEFIK_TRACING_ENABLED=false" >> .env; \
		echo "$(GREEN)✓ TRAEFIK_TRACING_ENABLED added to .env$(NC)"; \
	fi
	@if grep -q "^tracing:" data/traefik/traefik.yml 2>/dev/null; then \
		sed -i '/^tracing:/,/^    disableAttemptReconnecting: true/s/^/# /' data/traefik/traefik.yml; \
		echo "$(GREEN)✓ Tracing section commented in traefik.yml$(NC)"; \
	elif grep -q "^# tracing:" data/traefik/traefik.yml 2>/dev/null; then \
		echo "$(YELLOW)⚠ Tracing already commented in traefik.yml$(NC)"; \
	else \
		echo "$(RED)✗ Tracing section not found in traefik.yml$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)Restarting Traefik...$(NC)"
	@docker compose restart traefik
	@echo "$(GREEN)✓ Tracing disabled successfully!$(NC)"
	@echo "$(YELLOW)Note: Jaeger container is still running. Use 'make jaeger-stop' to stop it.$(NC)"

## tracing-status: Show current tracing status
tracing-status:
	@echo "$(BLUE)Tracing Status:$(NC)"
	@echo ""
	@if grep -q "^TRAEFIK_TRACING_ENABLED=true" .env 2>/dev/null; then \
		echo "$(GREEN)✓ Tracing: ENABLED in .env$(NC)"; \
	else \
		echo "$(YELLOW)✗ Tracing: DISABLED in .env$(NC)"; \
	fi
	@if grep -q "^tracing:" data/traefik/traefik.yml 2>/dev/null; then \
		echo "$(GREEN)✓ traefik.yml: Tracing section ACTIVE$(NC)"; \
	else \
		echo "$(YELLOW)✗ traefik.yml: Tracing section COMMENTED$(NC)"; \
	fi
	@if docker compose ps jaeger 2>/dev/null | grep -q "running"; then \
		echo "$(GREEN)✓ Jaeger: RUNNING$(NC)"; \
		echo "$(BLUE)  URL: https://jaeger.$$(grep PUBLIC_FQDN .env | cut -d'=' -f2)$(NC)"; \
	elif docker compose ps jaeger 2>/dev/null | grep -q "Up"; then \
		echo "$(GREEN)✓ Jaeger: RUNNING$(NC)"; \
	else \
		echo "$(YELLOW)✗ Jaeger: STOPPED$(NC)"; \
	fi

## jaeger-start: Start Jaeger tracing service
jaeger-start:
	@echo "$(BLUE)Starting Jaeger...$(NC)"
	@if ! grep -q "compose/jaeger.yml" docker-compose.yml; then \
		echo "$(RED)✗ ERROR: Jaeger not configured in docker-compose.yml$(NC)"; \
		echo "$(YELLOW)Run 'make tracing-enable' first$(NC)"; \
		exit 1; \
	fi
	@docker compose up -d jaeger
	@echo "$(GREEN)✓ Jaeger started!$(NC)"
	@echo "$(BLUE)Access Jaeger UI at: https://jaeger.$$(grep PUBLIC_FQDN .env | cut -d'=' -f2)$(NC)"

## jaeger-stop: Stop Jaeger tracing service
jaeger-stop:
	@echo "$(YELLOW)Stopping Jaeger...$(NC)"
	@docker compose stop jaeger
	@echo "$(GREEN)✓ Jaeger stopped!$(NC)"

## jaeger-restart: Restart Jaeger tracing service
jaeger-restart:
	@echo "$(YELLOW)Restarting Jaeger...$(NC)"
	@docker compose restart jaeger
	@echo "$(GREEN)✓ Jaeger restarted!$(NC)"

## jaeger-logs: View Jaeger logs
jaeger-logs:
	@docker compose logs -f jaeger

## jaeger-remove: Remove Jaeger service and data
jaeger-remove:
	@echo "$(RED)Removing Jaeger service and data...$(NC)"
	@read -p "Are you sure? This will delete all traces [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker compose down jaeger; \
		rm -rf data/jaeger/badger; \
		sed -i '/^  - compose\/jaeger.yml/d' docker-compose.yml 2>/dev/null || true; \
		echo "$(GREEN)✓ Jaeger removed!$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled.$(NC)"; \
	fi

## stack-systemd-create: Create systemd service for a stack (usage: make stack-systemd-create STACK=example-stack)
stack-systemd-create:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-create STACK=example-stack"
	@exit 1
endif
	@echo "$(BLUE)Creating systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-create $(STACK)

## stack-systemd-remove: Remove systemd service for a stack (usage: make stack-systemd-remove STACK=example-stack)
stack-systemd-remove:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-remove STACK=example-stack"
	@exit 1
endif
	@echo "$(YELLOW)Removing systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-remove $(STACK)

## stack-systemd-enable: Enable systemd service for a stack (usage: make stack-systemd-enable STACK=example-stack)
stack-systemd-enable:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-enable STACK=example-stack"
	@exit 1
endif
	@echo "$(BLUE)Enabling systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-enable $(STACK)

## stack-systemd-disable: Disable systemd service for a stack (usage: make stack-systemd-disable STACK=example-stack)
stack-systemd-disable:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-disable STACK=example-stack"
	@exit 1
endif
	@echo "$(YELLOW)Disabling systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-disable $(STACK)

## stack-systemd-start: Start systemd service for a stack (usage: make stack-systemd-start STACK=example-stack)
stack-systemd-start:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-start STACK=example-stack"
	@exit 1
endif
	@echo "$(GREEN)Starting systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-start $(STACK)

## stack-systemd-stop: Stop systemd service for a stack (usage: make stack-systemd-stop STACK=example-stack)
stack-systemd-stop:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-stop STACK=example-stack"
	@exit 1
endif
	@echo "$(YELLOW)Stopping systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-stop $(STACK)

## stack-systemd-restart: Restart systemd service for a stack (usage: make stack-systemd-restart STACK=example-stack)
stack-systemd-restart:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-restart STACK=example-stack"
	@exit 1
endif
	@echo "$(YELLOW)Restarting systemd service for $(STACK)...$(NC)"
	@./assets/jacker-stack systemd-restart $(STACK)

## stack-systemd-status: Show systemd service status for a stack (usage: make stack-systemd-status STACK=example-stack)
stack-systemd-status:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-status STACK=example-stack"
	@exit 1
endif
	@./assets/jacker-stack systemd-status $(STACK)

## stack-systemd-logs: View systemd service logs for a stack (usage: make stack-systemd-logs STACK=example-stack [LINES=100])
stack-systemd-logs:
ifndef STACK
	@echo "$(RED)ERROR: STACK not specified$(NC)"
	@echo "Usage: make stack-systemd-logs STACK=example-stack [LINES=100]"
	@exit 1
endif
	@./assets/jacker-stack systemd-logs $(STACK) $(LINES)

## stack-systemd-list: List all Jacker systemd services
stack-systemd-list:
	@./assets/jacker-stack systemd-list

## stack-manager: Launch interactive stack management menu
stack-manager:
	@./assets/stack-manager

## stacks: Alias for stack-manager (interactive menu)
stacks: stack-manager
