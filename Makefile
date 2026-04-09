RUN := docker compose run --rm
PERL_FILES := scripts/*.pl scripts/20-fix-parsed/*.pl scripts/helps/*.pl

.DEFAULT_GOAL := help

.PHONY: help build dat tidy critic

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker compose build

dat: ## Build .dat files from sources
	$(RUN) -w /app/parsed perl bash patch.sh

tidy: ## Run perltidy [files]
	$(RUN) perl perltidy --profile=/app/.perltidyrc -b -bext='/' $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

critic: ## Run perlcritic [files]
	$(RUN) perl perlcritic --verbose 8 $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

%:
	@:
