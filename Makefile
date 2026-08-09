COMPOSE ?= docker compose
COMPOSE_FILE ?= docker-compose.yml
GATEWAY_SERVICE ?= openclaw-gateway

.PHONY: help init check build up down restart logs ps dashboard pair re-pair plugin-inspect secrets-audit status smoke shell

help: ## Show available commands.
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "%-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Create a private .env with a generated Gateway token when absent.
	@./scripts/init-env.sh

check: ## Validate shell scripts and the resolved Compose configuration.
	@sh -n scripts/init-env.sh
	@sh -n scripts/openclaw-playground.sh
	@test -f ../ag-plugin-openclaw/package.json
	@test -f ../ag-plugin-openclaw/openclaw.plugin.json
	@$(COMPOSE) --env-file .env.example -f $(COMPOSE_FILE) config --quiet

build: ## Build pinned OpenClaw with the current sibling AG Pay plugin source.
	@$(COMPOSE) -f $(COMPOSE_FILE) build

up: init ## Build and start the local Gateway; wait until it is healthy.
	@if ! $(COMPOSE) -f $(COMPOSE_FILE) up -d --build --wait $(GATEWAY_SERVICE); then \
		$(COMPOSE) -f $(COMPOSE_FILE) logs --no-color --tail=200 openclaw-bootstrap >&2; \
		exit 1; \
	fi

down: ## Stop containers while preserving OpenClaw state and secrets.
	@$(COMPOSE) -f $(COMPOSE_FILE) down

restart: ## Restart the Gateway without rebuilding the plugin package.
	@$(COMPOSE) -f $(COMPOSE_FILE) restart $(GATEWAY_SERVICE)
	@$(COMPOSE) -f $(COMPOSE_FILE) up -d --wait $(GATEWAY_SERVICE)

logs: ## Follow Gateway logs.
	@$(COMPOSE) -f $(COMPOSE_FILE) logs --follow $(GATEWAY_SERVICE)

ps: ## Show playground container status.
	@$(COMPOSE) -f $(COMPOSE_FILE) ps --all

dashboard: ## Print the local Control UI URL without opening it.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		node dist/index.js dashboard --no-open

pair: ## Pair once, or keep the existing private credential without prompting.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		openclaw-playground pair
	@$(MAKE) restart

re-pair: ## Replace the current AG Pay token through the hidden prompt.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		openclaw-playground pair --force
	@$(MAKE) restart

plugin-inspect: ## Prove the AG Pay runtime tools, CLI, and service load.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		node dist/index.js plugins inspect agpay --runtime --json

secrets-audit: ## Check active OpenClaw secret references.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		node dist/index.js secrets audit --check

status: ## Require a healthy, readable Gateway RPC endpoint.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) \
		node dist/index.js gateway status --deep --require-rpc

smoke: up ## Build, start, and verify the live plugin runtime.
	@$(MAKE) plugin-inspect
	@$(MAKE) secrets-audit
	@$(MAKE) status

shell: ## Open a shell in the running Gateway container.
	@$(COMPOSE) -f $(COMPOSE_FILE) exec $(GATEWAY_SERVICE) sh
