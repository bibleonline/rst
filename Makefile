RUN := docker compose run --rm

.DEFAULT_GOAL := help

.PHONY: help build dat

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker compose build

dat: ## Build .dat files from sources
	$(RUN) -w /app/parsed perl bash patch.sh
