.PHONY: help install install_prod start stop server cache csclear cscheck csfix stancheck audit db-update db-reset db-migrate
.DEFAULT_GOAL := help

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

install: ## to install all project (creates or updates the schema; never loads fixtures, keeps existing content)
	composer install
	make db-update

install_prod: ## to install production dependencies (no dev packages, optimized autoloader)
	composer install --no-dev --optimize-autoloader

start: ## to start server
	symfony server:start -d
	cd public/theme/<theme_name> && npm run dev

stop: ## to stop server
	symfony server:stop

server: ## to start server
	symfony server:start -d

cache: ## to clean cache
	bin/console cache:clear

csclear: ## to clean cache and check coding style
	mkdir -p var/cache/ecs
	chmod -R a+rw var/cache/ecs
	rm -rf var/cache/ecs/*

cscheck: ## to check coding style
	make csclear
	composer lint
	make stancheck

csfix: ## to fix coding style
	make csclear
	composer lint:fix
	make stancheck

stancheck: ## to run phpstan
	composer phpstan

audit: ## to check PHP and npm dependencies for known vulnerabilities (bolt-security-hardening)
	composer audit --locked
	cd public/theme/<theme_name> && npm audit --omit=dev

# DEVELOPMENT ONLY: `--complete` drops tables Doctrine does not map (e.g. tables created by other
# tools), and `migrations:version --add --all` marks every migration as executed WITHOUT running
# it, so data migrations shipped by Bolt or extensions are skipped. Use db-migrate on production.
db-update: ## [dev] to update schema database and mark migrations as applied
	bin/console doctrine:schema:update --complete --force
	bin/console doctrine:migrations:sync-metadata-storage -q
	bin/console doctrine:migrations:version --add --all --no-interaction -q

db-reset: ## [dev] to delete database and create an empty schema without fixtures (destroys all content)
	bin/console doctrine:schema:drop --force --full-database
	bin/console doctrine:schema:create -q
	bin/console doctrine:migrations:sync-metadata-storage -q
	bin/console doctrine:migrations:version --add --all --no-interaction -q

db-migrate: ## [prod] to run pending Doctrine migrations (what Bolt recommends after composer install/update)
	bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
