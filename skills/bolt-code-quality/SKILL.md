---
name: bolt-code-quality
description: >-
  Use this skill whenever setting up, standardizing, or verifying PHP code quality,
  static analysis, and CI/CD pipelines in a Bolt CMS repository. Configures
  Easy Coding Standard (ECS) with PSR-12/cleanCode rules, PHPStan Level 8 static
  analysis on src/, unified Makefile commands (cscheck, csfix, stancheck, csclear),
  safe Doctrine migration synchronization, and a GitLab CI matrix for PHP 8.2–8.5.
---

# Bolt CMS Code Quality, Static Analysis & CI Pipeline

Maintaining strict code standards and static analysis is essential for stable Bolt CMS applications. Across production Bolt CMS repositories, code quality is standardized into a four-pillar pipeline:

1. **Easy Coding Standard (ECS)** via `ecs.php`: Enforces PSR-12, clean code, `declare(strict_types=1)`, import ordering, and custom fixer rules.
2. **PHPStan Level 8** via `phpstan.dist.neon`: Rigorous type checking on `src/` with Symfony and Doctrine extension support.
3. **Task Automation** via `Makefile`: Standard developer targets (`cscheck`, `csfix`, `stancheck`, `csclear`), development database workflows (`db-update`, `db-reset`) and the production migration target (`db-migrate`).
4. **Automated CI/CD** via `.gitlab-ci.yml`: Matrix testing across PHP 8.2–8.5 with Composer caching and Twig, XLIFF, and YAML syntax validation.

---

## Architectural Context

```text
Project Root (/)
├── composer.json               # Dev dependencies, scripts (lint, lint:fix, phpstan), allow-plugins
├── ecs.php                     # Easy Coding Standard rule definitions & fixer configuration
├── phpstan.dist.neon           # PHPStan configuration (Level 8 on src/)
├── Makefile                    # Developer workflow targets (cscheck, csfix, db-update)
├── .gitlab-ci.yml              # CI pipeline (ECS, PHPStan, lint:twig, lint:xliff, lint:yaml)
└── var/cache/ecs/              # Cache directory for ECS runs (git-ignored, cleared by csclear)
```

---

## Step-by-Step Implementation

### Step 1: Install Composer Dependencies

Add the required testing and static analysis dependencies to `composer.json`:

```bash
composer require --dev \
  symplify/easy-coding-standard:^13.3 \
  phpstan/phpstan:^2.2 \
  phpstan/extension-installer:^1.4.3 \
  phpstan/phpstan-symfony:^2.0 \
  phpstan/phpstan-doctrine:^2.0 \
  phpstan/phpstan-deprecation-rules:^2.0
```

Enable the extension installer plugin and add scripts to `composer.json`:

```json
{
  "scripts": {
    "lint": "@php vendor/bin/ecs check --no-progress-bar --no-interaction",
    "lint:fix": "@php vendor/bin/ecs check --no-progress-bar --no-interaction --fix",
    "phpstan": "@php vendor/bin/phpstan --memory-limit=1G analyse -c phpstan.dist.neon src"
  },
  "config": {
    "allow-plugins": {
      "phpstan/extension-installer": true
    }
  }
}
```

*Note: With `phpstan/extension-installer: true`, Symfony and Doctrine extension rules are loaded automatically by PHPStan.*

---

### Step 2: Configure Easy Coding Standard (`ecs.php`)

Create `ecs.php` at the project root. This standard configuration is shared identically across all production projects:

```php
<?php

declare(strict_types=1);

namespace Symfony\Component\DependencyInjection\Loader\Configurator;

use PhpCsFixer\Fixer\Alias\MbStrFunctionsFixer;
use PhpCsFixer\Fixer\ArrayNotation\NoWhitespaceBeforeCommaInArrayFixer;
use PhpCsFixer\Fixer\ArrayNotation\WhitespaceAfterCommaInArrayFixer;
use PhpCsFixer\Fixer\Basic\BracesFixer;
use PhpCsFixer\Fixer\CastNotation\LowercaseCastFixer;
use PhpCsFixer\Fixer\CastNotation\ShortScalarCastFixer;
use PhpCsFixer\Fixer\ClassNotation\ClassAttributesSeparationFixer;
use PhpCsFixer\Fixer\ClassNotation\FinalInternalClassFixer;
use PhpCsFixer\Fixer\ClassNotation\NoBlankLinesAfterClassOpeningFixer;
use PhpCsFixer\Fixer\ClassNotation\OrderedClassElementsFixer;
use PhpCsFixer\Fixer\ClassNotation\VisibilityRequiredFixer;
use PhpCsFixer\Fixer\ConstantNotation\NativeConstantInvocationFixer;
use PhpCsFixer\Fixer\ControlStructure\YodaStyleFixer;
use PhpCsFixer\Fixer\FunctionNotation\NativeFunctionInvocationFixer;
use PhpCsFixer\Fixer\FunctionNotation\PhpdocToReturnTypeFixer;
use PhpCsFixer\Fixer\FunctionNotation\ReturnTypeDeclarationFixer;
use PhpCsFixer\Fixer\Import\FullyQualifiedStrictTypesFixer;
use PhpCsFixer\Fixer\Import\NoLeadingImportSlashFixer;
use PhpCsFixer\Fixer\Import\OrderedImportsFixer;
use PhpCsFixer\Fixer\LanguageConstruct\DeclareEqualNormalizeFixer;
use PhpCsFixer\Fixer\Operator\ConcatSpaceFixer;
use PhpCsFixer\Fixer\Operator\IncrementStyleFixer;
use PhpCsFixer\Fixer\Operator\NewWithBracesFixer;
use PhpCsFixer\Fixer\Operator\TernaryOperatorSpacesFixer;
use PhpCsFixer\Fixer\Operator\UnaryOperatorSpacesFixer;
use PhpCsFixer\Fixer\Phpdoc\NoSuperfluousPhpdocTagsFixer;
use PhpCsFixer\Fixer\Phpdoc\PhpdocAlignFixer;
use PhpCsFixer\Fixer\Phpdoc\PhpdocAnnotationWithoutDotFixer;
use PhpCsFixer\Fixer\Phpdoc\PhpdocLineSpanFixer;
use PhpCsFixer\Fixer\Phpdoc\PhpdocSummaryFixer;
use PhpCsFixer\Fixer\PhpTag\BlankLineAfterOpeningTagFixer;
use PhpCsFixer\Fixer\PhpUnit\PhpUnitMethodCasingFixer;
use PhpCsFixer\Fixer\Semicolon\NoSinglelineWhitespaceBeforeSemicolonsFixer;
use PhpCsFixer\Fixer\Whitespace\NoTrailingWhitespaceFixer;
use Symplify\CodingStandard\Fixer\ArrayNotation\ArrayListItemNewlineFixer;
use Symplify\CodingStandard\Fixer\ArrayNotation\ArrayOpenerAndCloserNewlineFixer;
use Symplify\CodingStandard\Fixer\ArrayNotation\StandaloneLineInMultilineArrayFixer;
use Symplify\CodingStandard\Fixer\Commenting\RemoveUselessDefaultCommentFixer;
use Symplify\CodingStandard\Fixer\Strict\BlankLineAfterStrictTypesFixer;
use Symplify\EasyCodingStandard\Config\ECSConfig;

return ECSConfig::configure()
    ->withPaths([
        __DIR__ . '/src',
        __DIR__ . '/ecs.php',
    ])
    ->withCache('var/cache/ecs')
    ->withPreparedSets(psr12: true, common: true, cleanCode: true)
    ->withSkip([
        OrderedClassElementsFixer::class => null,
        YodaStyleFixer::class => null,
        IncrementStyleFixer::class => null,
        PhpdocAnnotationWithoutDotFixer::class => null,
        PhpdocSummaryFixer::class => null,
        PhpdocAlignFixer::class => null,
        NativeConstantInvocationFixer::class => null,
        NativeFunctionInvocationFixer::class => null,
        UnaryOperatorSpacesFixer::class => null,
        ArrayOpenerAndCloserNewlineFixer::class => null,
        ArrayListItemNewlineFixer::class => null,
    ])
    ->withRules([
        StandaloneLineInMultilineArrayFixer::class,
        BlankLineAfterStrictTypesFixer::class,
        RemoveUselessDefaultCommentFixer::class,
        PhpUnitMethodCasingFixer::class,
        FinalInternalClassFixer::class,
        MbStrFunctionsFixer::class,
        LowercaseCastFixer::class,
        ShortScalarCastFixer::class,
        BlankLineAfterOpeningTagFixer::class,
        NoLeadingImportSlashFixer::class,
        NewWithBracesFixer::class,
        NoBlankLinesAfterClassOpeningFixer::class,
        TernaryOperatorSpacesFixer::class,
        ReturnTypeDeclarationFixer::class,
        NoTrailingWhitespaceFixer::class,
        NoSinglelineWhitespaceBeforeSemicolonsFixer::class,
        NoWhitespaceBeforeCommaInArrayFixer::class,
        WhitespaceAfterCommaInArrayFixer::class,
        FullyQualifiedStrictTypesFixer::class,
    ])
    ->withConfiguredRule(PhpdocToReturnTypeFixer::class, ['union_types' => false])
    ->withConfiguredRule(NoSuperfluousPhpdocTagsFixer::class, ['remove_inheritdoc' => false])
    ->withConfiguredRule(ConcatSpaceFixer::class, ['spacing' => 'one'])
    ->withConfiguredRule(OrderedImportsFixer::class, ['imports_order' => ['class', 'const', 'function']])
    ->withConfiguredRule(DeclareEqualNormalizeFixer::class, ['space' => 'none'])
    ->withConfiguredRule(BracesFixer::class, [
        'allow_single_line_closure' => false,
        'position_after_functions_and_oop_constructs' => 'next',
        'position_after_control_structures' => 'same',
        'position_after_anonymous_constructs' => 'same',
    ])
    ->withConfiguredRule(VisibilityRequiredFixer::class, ['elements' => ['const', 'method', 'property']])
    ->withConfiguredRule(PhpdocLineSpanFixer::class, ['property' => 'single'])
    ->withConfiguredRule(ClassAttributesSeparationFixer::class, ['elements' => ['property' => 'none', 'method' => 'one', 'const' => 'none']]);
```

---

### Step 3: Configure PHPStan (`phpstan.dist.neon`)

Create `phpstan.dist.neon` at the root:

```neon
parameters:
    level: 8

    paths:
        - src

    treatPhpDocTypesAsCertain: false
    reportUnmatchedIgnoredErrors: true
```

* **Level 8**: Enforces strict typing, eliminates undefined properties, and ensures explicit return and parameter types.
* **`treatPhpDocTypesAsCertain: false`**: Crucial in Symfony/Bolt environments where runtime doctrine entities or database hydrations may return values different from docblocks.

---

### Step 4: Configure `Makefile` Automation

Create or update the project's `Makefile`:

```makefile
.PHONY: help install install_prod start stop server cache csclear cscheck csfix stancheck db-update db-reset db-migrate
.DEFAULT_GOAL := help

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

install: ## to install all project
	composer install
	make db-reset

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

# DEVELOPMENT ONLY: `--complete` drops tables Doctrine does not map (e.g. tables created by other
# tools), and `migrations:version --add --all` marks every migration as executed WITHOUT running
# it, so data migrations shipped by Bolt or extensions are skipped. Use db-migrate on production.
db-update: ## [dev] to update schema database and mark migrations as applied
	bin/console doctrine:schema:update --complete --force
	bin/console doctrine:migrations:sync-metadata-storage -q
	bin/console doctrine:migrations:version --add --all --no-interaction -q

db-reset: ## [dev] to delete database and load fixtures (destroys all content)
	bin/console doctrine:schema:drop --force --full-database
	bin/console doctrine:schema:create -q
	bin/console doctrine:migrations:sync-metadata-storage -q
	bin/console doctrine:migrations:version --add --all --no-interaction -q
	bin/console doctrine:fixtures:load --no-interaction

db-migrate: ## [prod] to run pending Doctrine migrations (what Bolt recommends after composer install/update)
	bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
```

> [!IMPORTANT]
> **Why `sync-metadata-storage` and `version --add --all` matter in Bolt (development):**
> Bolt CMS manages core tables via Doctrine Schema, while project customizations may use Doctrine Migrations. After `schema:update` / `schema:create` has built the tables from the mapping, the migrations are synced and marked as applied so Doctrine does not try to run them again on top of the freshly created schema.

> [!CAUTION]
> **`db-update` and `db-reset` are development tools.**
> - `doctrine:schema:update --complete` drops tables that Doctrine does not map (tables created by other tools or extensions without entities).
> - `doctrine:migrations:version --add --all` marks every migration as executed **without running it**, so data migrations shipped by Bolt core or extensions are silently skipped.
> - `db-reset` drops the whole database.
>
> On staging and production run the migrations instead — `make db-migrate`, i.e. `bin/console doctrine:migrations:migrate`, which is what Bolt itself asks for after `composer install` / `composer update` when migrations are pending.

---

### Step 5: Configure GitLab CI (`.gitlab-ci.yml`)

Create or update `.gitlab-ci.yml` at the root:

```yaml
stages:
  - lint

.lint:
  stage: lint
  image: php:${PHP_VERSION}-cli
  variables:
    COMPOSER_ALLOW_SUPERUSER: "1"
    COMPOSER_NO_INTERACTION: "1"
  cache:
    key: "composer-${PHP_VERSION}"
    paths:
      - vendor/
      - .composer-cache/
  before_script:
    - curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions
    - chmod +x /usr/local/bin/install-php-extensions
    - install-php-extensions intl gd zip pdo_mysql opcache exif bcmath
    - curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    - export COMPOSER_CACHE_DIR="$CI_PROJECT_DIR/.composer-cache"
    - composer install --prefer-dist --no-progress --no-scripts

ecs:
  extends: .lint
  parallel:
    matrix:
      - PHP_VERSION: [ "8.2", "8.3", "8.4", "8.5" ]
  script:
    - composer lint

phpstan:
  extends: .lint
  parallel:
    matrix:
      - PHP_VERSION: [ "8.2", "8.3", "8.4", "8.5" ]
  script:
    - composer phpstan

twig:
  extends: .lint
  variables:
    PHP_VERSION: "8.3"
  script:
    - php bin/console lint:twig public/theme/<theme_name>

xliff:
  extends: .lint
  variables:
    PHP_VERSION: "8.3"
  script:
    - php bin/console lint:xliff translations

yaml:
  extends: .lint
  variables:
    PHP_VERSION: "8.3"
  script:
    - php bin/console lint:yaml config --parse-tags
```

---

## Verification & Testing

### 1. Automated Verification Script
Run the built-in verification script to validate all files, configurations, and scripts:

```bash
skills/bolt-code-quality/scripts/verify.sh
```

The script verifies:
1. `ecs.php` existence, PHP syntax validity, and paths configuration.
2. `phpstan.dist.neon` existence, Level 8 verification, and paths configuration.
3. `composer.json` scripts (`lint`, `lint:fix`, `phpstan`) and dev dependencies.
4. `Makefile` targets (`cscheck`, `csfix`, `stancheck`, `csclear`, `db-update`; `db-migrate` recommended for production).
5. `.gitlab-ci.yml` lint stage and validation jobs (ECS, PHPStan, Twig, XLIFF, YAML).
6. Executes dry-run linting and static analysis if binaries are installed.

### 2. Manual Commands
Run standard checks from the command line:

```bash
# Check code style without modifying files
make cscheck

# Automatically fix coding style violations
make csfix

# Run PHPStan static analysis alone
make stancheck
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Corrupted or Stale ECS Cache
- **Symptom:** `Cannot clear cache` or ECS reports false positive violations after branch switching.
- **Solution:** Always run `make csclear` before checking. The Makefile targets `cscheck` and `csfix` do this automatically.

### Pitfall 2: Memory Exhaustion in PHPStan
- **Symptom:** `Fatal error: Allowed memory size of X bytes exhausted`.
- **Solution:** Always pass `--memory-limit=1G` in the Composer script:
  `"phpstan": "@php vendor/bin/phpstan --memory-limit=1G analyse -c phpstan.dist.neon src"`

### Pitfall 3: Doctrine Schema vs Migration Collisions
- **Symptom:** Running `bin/console doctrine:schema:update` causes migration errors or attempts to recreate Bolt core tables.
- **Solution (development):** Always run `doctrine:migrations:sync-metadata-storage -q` followed by `doctrine:migrations:version --add --all --no-interaction -q` immediately after schema updates (see `make db-update`).
- **Production:** never use `db-update` / `db-reset`; run `make db-migrate` (`doctrine:migrations:migrate`) so data migrations actually execute.
