RUN := docker compose run --rm
PERL_FILES := scripts/*.pl scripts/20-fix-parsed/*.pl scripts/helps/*.pl parsed66/scripts/*.pl parsed81/scripts/*.pl

.DEFAULT_GOAL := help

.PHONY: help build dat dat78 dat66 dat81 tidy critic

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker compose build

dat: dat78 dat66 dat81 ## Build all .dat sets in order (78 -> 66, 81)

# dat66 и dat81 читают результат dat78 — порядок обязателен и при make -j
dat66 dat81: | dat78

dat78: ## Build parsed78 .dat from source/ (parse + fixes)
	$(RUN) -w /app/parsed78 perl bash patch.sh

dat66: ## Build parsed66 .dat from parsed78 (66-book edition)
	$(RUN) -w /app/parsed66/scripts perl bash update.sh

dat81: ## Build parsed81 .dat from parsed78 (split Daniel: s3y, sus, bel)
	$(RUN) -w /app/parsed81/scripts perl perl split-books.pl

tidy: ## Run perltidy [files]
	$(RUN) perl perltidy --profile=/app/.perltidyrc -b -bext='/' $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

critic: ## Run perlcritic [files]
	$(RUN) perl perlcritic --verbose 8 $(or $(filter-out $@,$(MAKECMDGOALS)),$(PERL_FILES))

%:
	@:
