.PHONY: help build start stop restart logs status update force-update clean prune exec shell test workspace

# Default target
.DEFAULT_GOAL := help

# Variables
COMPOSE := docker compose
CONTAINER := trm-doppler
UPDATE_SCRIPT := ./update.sh

help: ## Show this help message
	@echo "TRM-Doppler & Lcurve Container - Available Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Build the Docker container
	$(COMPOSE) build

start: ## Start the container and launch Jupyter Lab
	@echo "Starting container..."
	$(COMPOSE) up -d
	@echo "✓ Jupyter Lab available at http://localhost:8888"

stop: ## Stop the container
	@echo "Stopping container..."
	$(COMPOSE) down
	@echo "✓ Container stopped"

restart: ## Restart the container
	@echo "Restarting container..."
	$(COMPOSE) restart
	@echo "✓ Container restarted"

logs: ## View container logs (follow mode)
	$(COMPOSE) logs -f

status: ## Show repository status and container state
	$(UPDATE_SCRIPT) status

update: ## Check for updates and rebuild if needed
	$(UPDATE_SCRIPT) update

force-update: ## Force rebuild regardless of updates
	$(UPDATE_SCRIPT) force

clean: ## Remove stopped containers and dangling images
	@echo "Cleaning up Docker resources..."
	docker system prune -f
	@echo "✓ Cleanup complete"

prune: ## Deep clean: remove all stopped containers, networks, and images
	@echo "WARNING: This will remove all unused Docker resources"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker system prune -a; \
		echo "✓ Deep cleanup complete"; \
	fi

exec: ## Execute a command in the running container (usage: make exec cmd="command")
	$(COMPOSE) exec $(CONTAINER) $(cmd)

shell: ## Open a bash shell in the running container
	$(COMPOSE) exec $(CONTAINER) bash

workspace: ## Create workspace directories if they don't exist
	@mkdir -p workspace/notebooks workspace/input workspace/output
	@echo "✓ Workspace directories ready"

rebuild: ## Clean rebuild with no cache
	@echo "Rebuilding with no cache..."
	$(COMPOSE) build --no-cache
	@echo "✓ Rebuild complete"

dev: build start ## Quick development setup: build and start

jupyter: start ## Alias for start (launch Jupyter)

down: stop ## Alias for stop

up: start ## Alias for start
