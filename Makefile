# =============================================================================
# Jacker - Simplified Makefile Wrapper
# All functionality is now in the unified jacker CLI
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
SERVICE ?=
BACKUP ?=

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "$(BLUE)Jacker - Unified Docker Stack Management$(NC)"
	@echo ""
	@echo "$(GREEN)Primary Interface:$(NC)"
	@echo "  ./jacker [command] [options]    Use the jacker CLI directly"
	@echo ""
	@echo "$(GREEN)Common Make Targets:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)For full functionality, use: ./jacker help$(NC)"

# =============================================================================
##@ Installation & Setup
# =============================================================================

install: ## Run initial installation
	@./jacker init

reinstall: ## Reinstall preserving configuration
	@./jacker init --reinstall

update: ## Update Jacker system and images
	@./jacker update all

clean: ## Clean Docker resources and temp files
	@./jacker clean

# =============================================================================
##@ Service Management
# =============================================================================

up: ## Start all services
	@./jacker start $(SERVICE)

down: ## Stop all services
	@./jacker stop $(SERVICE)

start: up ## Alias for 'up'

stop: down ## Alias for 'down'

restart: ## Restart services
	@./jacker restart $(SERVICE)

ps: ## Show service status
	@./jacker status

# =============================================================================
##@ Monitoring & Health
# =============================================================================

logs: ## View service logs
ifdef SERVICE
	@./jacker logs $(SERVICE)
else
	@./jacker logs all --tail=50
endif

health: ## Run health check
	@./jacker health

status: ## Show full status dashboard
	@./jacker status --dashboard

# =============================================================================
##@ Backup & Maintenance
# =============================================================================

backup: ## Create backup
	@./jacker backup create

restore: ## Restore from backup
ifdef BACKUP
	@./jacker backup restore $(BACKUP)
else
	@echo "$(RED)Usage: make restore BACKUP=/path/to/backup$(NC)"
endif

prune: ## Clean unused Docker resources
	@./jacker clean docker

# =============================================================================
##@ Configuration
# =============================================================================

config: ## Show/edit configuration
	@./jacker config show

reconfigure-oauth: ## Reconfigure OAuth
	@./jacker config oauth

reconfigure-ssl: ## Reconfigure SSL/TLS
	@./jacker config ssl

reconfigure-domain: ## Reconfigure domain
	@./jacker config domain

# =============================================================================
##@ Security
# =============================================================================

security-status: ## Show security status
	@./jacker security status

security-scan: ## Run security scan
	@./jacker security scan

crowdsec-status: ## Show CrowdSec status
	@./jacker security crowdsec status

firewall-status: ## Show firewall status
	@./jacker security firewall status

# =============================================================================
##@ Development
# =============================================================================

lint: ## Lint configuration files
	@./jacker check lint

validate: ## Validate configuration
	@./jacker check validate

test: ## Run tests
	@./jacker check test

shell: ## Open shell in service
ifdef SERVICE
	@./jacker exec $(SERVICE) bash
else
	@echo "$(RED)Usage: make shell SERVICE=traefik$(NC)"
endif

# =============================================================================
# Shortcuts for common operations
# =============================================================================

.PHONY: quick-start quick-stop quick-restart
quick-start: ## Quick start essential services
	@./jacker start traefik oauth postgres redis

quick-stop: ## Quick stop all services
	@./jacker stop --all

quick-restart: ## Quick restart with pull
	@./jacker stop --all
	@./jacker update images
	@./jacker start --all

# =============================================================================
# Legacy compatibility (will be deprecated)
# =============================================================================

.PHONY: env generate-passwords crowdsec-decisions
env: ## Show environment (legacy)
	@./jacker config show

generate-passwords: ## Generate passwords (legacy)
	@./jacker secrets regenerate

crowdsec-decisions: ## Show CrowdSec decisions (legacy)
	@./jacker security crowdsec list-decisions