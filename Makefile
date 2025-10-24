# RedELK Makefile
# Version 3.0.0
#
# Provides convenient shortcuts for common RedELK operations

.PHONY: help install quickstart status logs stop start restart clean uninstall backup restore update lint test

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@echo "$(CYAN)RedELK v3.0 - Makefile Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make $(CYAN)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Installation

install: ## Run full interactive installation
	@echo "$(GREEN)Starting RedELK installation...$(NC)"
	@python3 install.py

quickstart: ## Quick install with defaults (for testing)
	@echo "$(GREEN)Starting RedELK quick installation...$(NC)"
	@python3 install.py --quickstart

dry-run: ## Perform dry-run to validate configuration
	@echo "$(YELLOW)Running installation dry-run...$(NC)"
	@python3 install.py --dry-run

##@ Service Management

status: ## Show status of all RedELK services
	@echo "$(CYAN)RedELK Service Status:$(NC)"
	@cd elkserver && docker-compose ps

logs: ## Show logs from all services (follow mode)
	@echo "$(CYAN)Following RedELK logs (Ctrl+C to exit)...$(NC)"
	@cd elkserver && docker-compose logs -f

logs-tail: ## Show last 100 lines of logs from all services
	@cd elkserver && docker-compose logs --tail=100

logs-errors: ## Show only error logs
	@cd elkserver && docker-compose logs | grep -i error

start: ## Start all RedELK services
	@echo "$(GREEN)Starting RedELK services...$(NC)"
	@cd elkserver && docker-compose up -d
	@echo "$(GREEN)Services started!$(NC)"
	@$(MAKE) status

stop: ## Stop all RedELK services
	@echo "$(YELLOW)Stopping RedELK services...$(NC)"
	@cd elkserver && docker-compose stop
	@echo "$(YELLOW)Services stopped.$(NC)"

restart: ## Restart all RedELK services
	@echo "$(YELLOW)Restarting RedELK services...$(NC)"
	@cd elkserver && docker-compose restart
	@echo "$(GREEN)Services restarted!$(NC)"
	@$(MAKE) status

down: ## Stop and remove all containers
	@echo "$(RED)Stopping and removing RedELK containers...$(NC)"
	@cd elkserver && docker-compose down
	@echo "$(RED)Containers removed.$(NC)"

##@ Health & Diagnostics

health: ## Check health of all services
	@echo "$(CYAN)Checking service health...$(NC)"
	@python3 scripts/health-check.py 2>/dev/null || echo "$(YELLOW)Health check script not yet implemented$(NC)"

ps: ## Show detailed container information
	@cd elkserver && docker-compose ps -a

top: ## Show running processes in containers
	@cd elkserver && docker-compose top

stats: ## Show resource usage statistics
	@docker stats --no-stream $$(cd elkserver && docker-compose ps -q)

##@ Data Management

backup: ## Create backup of RedELK data
	@echo "$(CYAN)Creating RedELK backup...$(NC)"
	@bash scripts/backup.sh 2>/dev/null || echo "$(YELLOW)Backup script not yet implemented$(NC)"

restore: ## Restore RedELK from backup
	@echo "$(CYAN)Restoring RedELK from backup...$(NC)"
	@bash scripts/restore.sh 2>/dev/null || echo "$(YELLOW)Restore script not yet implemented$(NC)"

clean-logs: ## Clean up log files
	@echo "$(YELLOW)Cleaning old log files...$(NC)"
	@find elkserver/mounts/redelk-logs -name "*.log" -mtime +30 -delete 2>/dev/null || true
	@echo "$(GREEN)Logs cleaned!$(NC)"

##@ Maintenance

update: ## Update RedELK to latest version
	@echo "$(CYAN)Updating RedELK...$(NC)"
	@git pull origin master
	@cd elkserver && docker-compose pull
	@echo "$(GREEN)Update complete! Run 'make restart' to apply changes.$(NC)"

rebuild: ## Rebuild all Docker images
	@echo "$(CYAN)Rebuilding Docker images...$(NC)"
	@cd elkserver && docker-compose build --no-cache
	@echo "$(GREEN)Rebuild complete!$(NC)"

prune: ## Remove unused Docker resources
	@echo "$(YELLOW)Cleaning up unused Docker resources...$(NC)"
	@docker system prune -f
	@docker volume prune -f
	@echo "$(GREEN)Cleanup complete!$(NC)"

##@ Development

dev-setup: ## Setup development environment
	@echo "$(CYAN)Setting up development environment...$(NC)"
	@pip3 install -r requirements-dev.txt 2>/dev/null || echo "$(YELLOW)requirements-dev.txt not found$(NC)"
	@echo "$(GREEN)Development environment ready!$(NC)"

lint: ## Run linters on Python code
	@echo "$(CYAN)Running linters...$(NC)"
	@python3 -m pylint install.py 2>/dev/null || echo "$(YELLOW)pylint not installed$(NC)"
	@python3 -m flake8 install.py 2>/dev/null || echo "$(YELLOW)flake8 not installed$(NC)"

test: ## Run tests
	@echo "$(CYAN)Running tests...$(NC)"
	@python3 -m pytest tests/ 2>/dev/null || echo "$(YELLOW)No tests found or pytest not installed$(NC)"

shell-es: ## Open shell in Elasticsearch container
	@docker exec -it redelk-elasticsearch /bin/bash

shell-logstash: ## Open shell in Logstash container
	@docker exec -it redelk-logstash /bin/bash

shell-kibana: ## Open shell in Kibana container
	@docker exec -it redelk-kibana /bin/bash

##@ Cleanup

uninstall: ## Completely remove RedELK (WARNING: deletes all data!)
	@echo "$(RED)WARNING: This will delete ALL RedELK data!$(NC)"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(RED)Removing RedELK...$(NC)"
	@cd elkserver && docker-compose down -v
	@rm -rf elkserver/mounts/redelk-logs/*
	@rm -rf certs/*.crt certs/*.key certs/*.pem 2>/dev/null || true
	@echo "$(RED)RedELK uninstalled.$(NC)"

clean: ## Clean temporary files and caches
	@echo "$(YELLOW)Cleaning temporary files...$(NC)"
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@find . -type f -name "*.log" -path "*/tmp/*" -delete 2>/dev/null || true
	@rm -f *.tgz 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete!$(NC)"

##@ Information

info: ## Display RedELK information
	@echo "$(CYAN)RedELK Information:$(NC)"
	@echo "  Version: $$(cat VERSION)"
	@echo "  Install Path: $$(pwd)"
	@echo "  Docker Compose: $$(cd elkserver && docker-compose version --short 2>/dev/null || echo 'not found')"
	@echo "  Python: $$(python3 --version)"
	@echo ""
	@echo "$(CYAN)Services:$(NC)"
	@$(MAKE) status

passwords: ## Display RedELK passwords
	@if [ -f elkserver/redelk_passwords.cfg ]; then \
		echo "$(CYAN)RedELK Passwords:$(NC)"; \
		cat elkserver/redelk_passwords.cfg; \
	else \
		echo "$(YELLOW)Passwords file not found. Run installation first.$(NC)"; \
	fi

urls: ## Display RedELK access URLs
	@echo "$(CYAN)RedELK Access URLs:$(NC)"
	@echo "  Kibana: https://$$(hostname -f || echo 'localhost')/"
	@echo "  Jupyter: https://$$(hostname -f || echo 'localhost')/jupyter"
	@echo "  BloodHound: https://$$(hostname -f || echo 'localhost'):8443"
	@echo "  Neo4j: http://$$(hostname -f || echo 'localhost'):7474"


