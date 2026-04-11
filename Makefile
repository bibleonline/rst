RUN := docker compose run --rm
PERL_FILES := scripts/*.pl scripts/20-fix-parsed/*.pl scripts/helps/*.pl parsed66/scripts/*.pl

.DEFAULT_GOAL := help

.PHONY: help build dat dat66 tidy critic

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker compose build

dat: ## Build .dat files from sources
	$(RUN) -w /app/parsed perl bash patch.sh

dat66: ## Build parsed66 .dat files
	$(RUN) -w /app/parsed66/scripts perl bash update.sh

tidy: ## Run perltidy [files]
	$(RUN) perl perltidy --profile=/app/.perltidyrc -b -bext='/' $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

critic: ## Run perlcritic [files]
	$(RUN) perl perlcritic --verbose 8 $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

%:
	@:
