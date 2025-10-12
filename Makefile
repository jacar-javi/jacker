# =============================================================================
# Jacker - Simplified Makefile
# =============================================================================

.PHONY: help
.DEFAULT_GOAL := help

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# Variables
COMPOSE := docker compose
SHELL_CMD := sh -c
SERVICE ?=
STACK ?=
BACKUP_DIR ?=

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "$(BLUE)Jacker - Docker Stack Management$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "$(GREEN)Usage:$(NC)\n  make [command]\n\n$(GREEN)Commands:$(NC)\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) }' $(MAKEFILE_LIST)

# =============================================================================
##@ Installation & Setup
# =============================================================================

install: ## Run initial installation
	@echo "$(BLUE)Starting Jacker installation...$(NC)"
	@./jacker setup

reinstall: ## Reinstall (preserves .env)
	@[ -f .env ] || { echo "$(RED)No .env file found$(NC)"; exit 1; }
	@cp .env .env.backup-$$(date +%Y%m%d-%H%M%S)
	@./jacker setup

update: ## Update all images and containers
	@echo "$(BLUE)Updating Jacker...$(NC)"
	@./jacker update
	@echo "$(GREEN)Update complete!$(NC)"

clean: ## Remove all data and configuration (dangerous!)
	@./jacker clean

# =============================================================================
##@ Service Management
# =============================================================================

up: ## Start all services
	@./jacker start $(SERVICE)

down: ## Stop all services
	@./jacker stop

start: up ## Alias for 'up'

stop: down ## Alias for 'down'

restart: ## Restart services
	@./jacker restart $(SERVICE)

recreate: ## Recreate services
	@echo "$(YELLOW)Recreating services...$(NC)"
	@$(COMPOSE) up -d --force-recreate $(SERVICE)

ps: ## Show service status
	@./jacker status

stats: ## Show resource usage
	@docker stats --no-stream

# =============================================================================
##@ Logs & Monitoring
# =============================================================================

.PHONY: logs logs-follow
logs: ## View logs (use SERVICE=name for specific service)
	@./jacker logs $(SERVICE) --tail=100

logs-follow: ## Follow logs in real-time
	@./jacker logs $(SERVICE) -f

health: ## Check health of all services
	@./jacker health

health-watch: ## Watch health status
	@watch -n 2 ./jacker health

diagnose: ## Run network diagnostics (DNS, firewall, SSL)
	@./jacker check network

validate: ## Validate Docker Compose configuration
	@echo "$(BLUE)Validating configuration...$(NC)"
	@$(COMPOSE) config > /dev/null && echo "$(GREEN)✓ Configuration is valid$(NC)" || echo "$(RED)✗ Configuration has errors$(NC)"

validate-env: ## Validate .env file variables
	@./jacker check env

# =============================================================================
##@ Backup & Restore
# =============================================================================

backup: ## Create backup (use BACKUP_DIR=/path for custom location)
	@./jacker backup create $(BACKUP_DIR)

restore: ## Restore from backup (use BACKUP=/path/to/backup.tar.gz)
ifndef BACKUP
	@echo "$(RED)ERROR: BACKUP path required$(NC)"
	@echo "Usage: make restore BACKUP=/path/to/backup.tar.gz"
	@exit 1
endif
	@./jacker restore $(BACKUP)

# =============================================================================
##@ Configuration
# =============================================================================

config: ## Show Docker Compose configuration
	@$(COMPOSE) config

env: ## Show current environment variables
	@[ -f .env ] && cat .env | grep -v '^#' | grep -v '^$$' || echo "$(RED)No .env file found$(NC)"

reconfigure-oauth: ## Reconfigure OAuth authentication
	@./assets/lib/reconfigure.sh oauth

reconfigure-ssl: ## Reconfigure SSL certificates
	@./assets/lib/reconfigure.sh ssl

reconfigure-domain: ## Reconfigure domain name
	@./assets/lib/reconfigure.sh domain

generate-passwords: ## Generate new passwords
	@./assets/lib/reconfigure.sh passwords

# =============================================================================
##@ Security
# =============================================================================

crowdsec-status: ## Show CrowdSec status
	@docker exec crowdsec cscli metrics

crowdsec-decisions: ## Show CrowdSec decisions
	@docker exec crowdsec cscli decisions list

crowdsec-bouncers: ## Show CrowdSec bouncers
	@docker exec crowdsec cscli bouncers list

crowdsec-update: ## Update CrowdSec collections
	@docker exec crowdsec cscli hub update
	@docker exec crowdsec cscli collections upgrade --all

ufw-status: ## Show firewall status
	@sudo ufw status verbose

rotate-secrets: ## Rotate all secrets
	@./assets/lib/rotate-secrets.sh

secrets-verify: ## Verify Docker secrets
	@bash -c 'source ./assets/lib/secrets.sh && verify_secrets'

secrets-generate: ## Generate missing secrets
	@bash -c 'source ./assets/lib/secrets.sh && generate_all_secrets'

secrets-migrate: ## Migrate secrets from .env to files
	@bash -c 'source ./assets/lib/secrets.sh && migrate_env_to_secrets'

# =============================================================================
##@ Stack Management
# =============================================================================

stacks: ## List available stacks (alias for stack-list)
	@./assets/stack.sh list

stack-list: ## List available stacks
	@./assets/stack.sh list

stack-search: ## Search stacks (use QUERY=term)
ifdef QUERY
	@./assets/stack.sh search $(QUERY)
else
	@echo "$(RED)Usage: make stack-search QUERY=wordpress$(NC)"
endif

stack-install: ## Install a stack (use STACK=name)
ifdef STACK
	@./assets/stack.sh install $(STACK)
else
	@echo "$(RED)Usage: make stack-install STACK=wordpress$(NC)"
endif

stack-uninstall: ## Uninstall a stack (use STACK=name)
ifdef STACK
	@./assets/stack.sh uninstall $(STACK)
else
	@echo "$(RED)Usage: make stack-uninstall STACK=wordpress$(NC)"
endif

# =============================================================================
##@ Maintenance
# =============================================================================

pull: ## Pull latest images
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@$(COMPOSE) pull

prune: ## Clean unused Docker resources
	@echo "$(YELLOW)Cleaning Docker resources...$(NC)"
	@docker system prune -af --volumes
	@echo "$(GREEN)Cleanup complete!$(NC)"

shell: ## Open shell in service (use SERVICE=name)
ifdef SERVICE
	@$(COMPOSE) exec $(SERVICE) $(SHELL_CMD) 'bash || sh'
else
	@echo "$(RED)Usage: make shell SERVICE=traefik$(NC)"
endif


version: ## Show component versions
	@echo "$(BLUE)Component Versions:$(NC)"
	@docker --version
	@$(COMPOSE) version
	@echo ""
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Image}}"

# =============================================================================
##@ Development
# =============================================================================

dev-up: ## Start in development mode
	@$(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml up -d

dev-logs: ## Show development logs
	@$(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml logs -f

lint: ## Lint configuration files
	@echo "$(BLUE)Linting configuration...$(NC)"
	@yamllint docker-compose.yml compose/*.yml 2>/dev/null || true
	@shellcheck assets/*.sh assets/lib/*.sh 2>/dev/null || true

# =============================================================================
# Hidden targets for backward compatibility
# =============================================================================

.PHONY: up-monitoring
up-monitoring: up

.PHONY: status
status: ps

.PHONY: start-service stop-service restart-service
start-service stop-service restart-service: SERVICE_REQUIRED
	@$(COMPOSE) $(@:-service=) $(SERVICE)

.PHONY: SERVICE_REQUIRED
SERVICE_REQUIRED:
ifndef SERVICE
	@echo "$(RED)ERROR: SERVICE not specified$(NC)"
	@echo "Usage: make $@ SERVICE=name"
	@exit 1
endif