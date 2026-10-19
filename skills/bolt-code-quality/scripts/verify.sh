#!/usr/bin/env bash
set -e

# Detect Bolt CMS project root
if [ -f "./config/services.yaml" ]; then
    BASE_DIR="$(pwd)"
else
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ "$DIR" != "/" ]; do
        if [ -f "$DIR/config/services.yaml" ]; then
            BASE_DIR="$DIR"
            break
        fi
        DIR="$(dirname "$DIR")"
    done
fi

if [ -z "$BASE_DIR" ] || [ ! -f "$BASE_DIR/config/services.yaml" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi

cd "$BASE_DIR"

echo "=========================================================="
echo " Bolt CMS Code Quality & Static Analysis Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Check composer.json configuration
# -------------------------------------------------------------
echo -n "[1/5] Checking composer.json dependencies and scripts... "
COMPOSER_JSON="composer.json"

if [ ! -f "$COMPOSER_JSON" ]; then
    echo "FAILED"
    echo "  Error: composer.json not found."
    FAILED=1
else
    HAS_ECS_PKG=$(grep -E "\"symplify/easy-coding-standard\"" "$COMPOSER_JSON" || true)
    HAS_STAN_PKG=$(grep -E "\"phpstan/phpstan\"" "$COMPOSER_JSON" || true)
    HAS_LINT_SCRIPT=$(grep -E "\"lint\":\s*\"" "$COMPOSER_JSON" || true)
    HAS_LINT_FIX_SCRIPT=$(grep -E "\"lint:fix\":\s*\"" "$COMPOSER_JSON" || true)
    HAS_STAN_SCRIPT=$(grep -E "\"phpstan\":\s*\"" "$COMPOSER_JSON" || true)

    if [ -n "$HAS_ECS_PKG" ] && [ -n "$HAS_STAN_PKG" ] && [ -n "$HAS_LINT_SCRIPT" ] && [ -n "$HAS_LINT_FIX_SCRIPT" ] && [ -n "$HAS_STAN_SCRIPT" ]; then
        echo "PASSED"
    else
        echo "FAILED"
        [ -z "$HAS_ECS_PKG" ] && echo "  - Missing dependency: symplify/easy-coding-standard"
        [ -z "$HAS_STAN_PKG" ] && echo "  - Missing dependency: phpstan/phpstan"
        [ -z "$HAS_LINT_SCRIPT" ] && echo "  - Missing composer script: 'lint'"
        [ -z "$HAS_LINT_FIX_SCRIPT" ] && echo "  - Missing composer script: 'lint:fix'"
        [ -z "$HAS_STAN_SCRIPT" ] && echo "  - Missing composer script: 'phpstan'"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 2. Check ecs.php configuration
# -------------------------------------------------------------
echo -n "[2/5] Checking ecs.php Easy Coding Standard configuration... "
ECS_FILE="ecs.php"

if [ ! -f "$ECS_FILE" ]; then
    echo "FAILED"
    echo "  Error: ecs.php does not exist at project root."
    FAILED=1
else
    # Check PHP syntax
    if ! php -l "$ECS_FILE" > /dev/null 2>&1; then
        echo "FAILED (PHP syntax error in ecs.php)"
        FAILED=1
    else
        HAS_PREPARED_SETS=$(grep -E "withPreparedSets\(.*psr12: true" "$ECS_FILE" || true)
        HAS_SRC_PATH=$(grep -E "'src'|/src" "$ECS_FILE" || true)
        HAS_CACHE_DIR=$(grep -E "withCache\(['\"]var/cache/ecs['\"]\)" "$ECS_FILE" || true)

        if [ -n "$HAS_PREPARED_SETS" ] && [ -n "$HAS_SRC_PATH" ] && [ -n "$HAS_CACHE_DIR" ]; then
            echo "PASSED (PSR-12/cleanCode configured with cache in var/cache/ecs)"
        else
            echo "WARNING / NOTICE"
            [ -z "$HAS_PREPARED_SETS" ] && echo "  - Missing withPreparedSets(psr12: true, ...)"
            [ -z "$HAS_SRC_PATH" ] && echo "  - Missing target path 'src'"
            [ -z "$HAS_CACHE_DIR" ] && echo "  - Missing cache directory 'var/cache/ecs'"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
fi

# -------------------------------------------------------------
# 3. Check phpstan.dist.neon configuration
# -------------------------------------------------------------
echo -n "[3/5] Checking phpstan.dist.neon static analysis configuration... "
STAN_FILE="phpstan.dist.neon"

if [ ! -f "$STAN_FILE" ]; then
    echo "FAILED"
    echo "  Error: phpstan.dist.neon does not exist at project root."
    FAILED=1
else
    STAN_LEVEL=$(grep -E "^\s*level:\s*" "$STAN_FILE" | awk '{print $2}' || true)
    HAS_STAN_SRC=$(grep -E -- "-\s*src" "$STAN_FILE" || true)
    HAS_CERTAIN_FLAG=$(grep -E "treatPhpDocTypesAsCertain:\s*false" "$STAN_FILE" || true)

    if [ "$STAN_LEVEL" = "8" ] && [ -n "$HAS_STAN_SRC" ] && [ -n "$HAS_CERTAIN_FLAG" ]; then
        echo "PASSED (Level 8 on src/, treatPhpDocTypesAsCertain: false)"
    else
        echo "FAILED"
        [ "$STAN_LEVEL" != "8" ] && echo "  - Expected 'level: 8', found '${STAN_LEVEL:-missing}'"
        [ -z "$HAS_STAN_SRC" ] && echo "  - Missing target path '- src'"
        [ -z "$HAS_CERTAIN_FLAG" ] && echo "  - Missing 'treatPhpDocTypesAsCertain: false'"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 4. Check Makefile automation targets
# -------------------------------------------------------------
echo -n "[4/5] Checking Makefile targets... "
MAKEFILE="Makefile"

if [ ! -f "$MAKEFILE" ]; then
    echo "FAILED"
    echo "  Error: Makefile does not exist at project root."
    FAILED=1
else
    HAS_CSCHECK=$(grep -E "^cscheck:" "$MAKEFILE" || true)
    HAS_CSFIX=$(grep -E "^csfix:" "$MAKEFILE" || true)
    HAS_STANCHECK=$(grep -E "^stancheck:" "$MAKEFILE" || true)
    HAS_CSCLEAR=$(grep -E "^csclear:" "$MAKEFILE" || true)
    HAS_DBUPDATE=$(grep -E "^db-update:" "$MAKEFILE" || true)

    if [ -n "$HAS_CSCHECK" ] && [ -n "$HAS_CSFIX" ] && [ -n "$HAS_STANCHECK" ] && [ -n "$HAS_CSCLEAR" ]; then
        echo "PASSED (cscheck, csfix, stancheck, csclear present)"
    else
        echo "FAILED"
        [ -z "$HAS_CSCHECK" ] && echo "  - Missing Makefile target 'cscheck:'"
        [ -z "$HAS_CSFIX" ] && echo "  - Missing Makefile target 'csfix:'"
        [ -z "$HAS_STANCHECK" ] && echo "  - Missing Makefile target 'stancheck:'"
        [ -z "$HAS_CSCLEAR" ] && echo "  - Missing Makefile target 'csclear:'"
        FAILED=1
    fi

    if [ -z "$HAS_DBUPDATE" ]; then
        echo "  Notice: Missing 'db-update:' with migration sync"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# -------------------------------------------------------------
# 5. Check CI Pipeline / Live Execution
# -------------------------------------------------------------
echo -n "[5/5] Checking CI pipeline and tool binaries... "
CI_FILE=".gitlab-ci.yml"
if [ -f "$CI_FILE" ]; then
    HAS_CI_ECS=$(grep -E "composer lint" "$CI_FILE" || true)
    HAS_CI_STAN=$(grep -E "composer phpstan" "$CI_FILE" || true)
    HAS_CI_TWIG=$(grep -E "lint:twig" "$CI_FILE" || true)
    HAS_CI_XLIFF=$(grep -E "lint:xliff" "$CI_FILE" || true)
    HAS_CI_YAML=$(grep -E "lint:yaml" "$CI_FILE" || true)

    if [ -n "$HAS_CI_ECS" ] && [ -n "$HAS_CI_STAN" ] && [ -n "$HAS_CI_TWIG" ] && [ -n "$HAS_CI_XLIFF" ] && [ -n "$HAS_CI_YAML" ]; then
        echo "PASSED (.gitlab-ci.yml covers ECS, PHPStan, Twig, XLIFF, YAML)"
    else
        echo "NOTICE (.gitlab-ci.yml present with partial checks)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "NOTICE (.gitlab-ci.yml not found, skipping CI validation)"
    WARNINGS=$((WARNINGS + 1))
fi

# Live execution if tools are available: violations fail the check, they are what this skill
# exists to prevent. (ECS keeps its cache in var/cache/ecs, as `make cscheck` does.)
if [ -f "vendor/bin/ecs" ] && [ -f "vendor/bin/phpstan" ]; then
    echo ""
    echo "Running live checks:"
    echo -n "  • ECS on src/... "
    if ECS_OUTPUT=$(php vendor/bin/ecs check --no-progress-bar --no-interaction src 2>&1); then
        echo "OK (clean)"
    else
        echo "FAILED (code style violations — run 'make csfix'):"
        echo "$ECS_OUTPUT" | grep -E "^ *[0-9]+\) |\[ERROR\]" | head -20 | sed 's/^ */      /'
        FAILED=1
    fi

    echo -n "  • PHPStan (phpstan.dist.neon) on src/... "
    if STAN_OUTPUT=$(php vendor/bin/phpstan --memory-limit=1G analyse -c phpstan.dist.neon src --no-progress --error-format=raw 2>&1); then
        echo "OK (clean)"
    else
        echo "FAILED (run 'make stancheck'):"
        echo "$STAN_OUTPUT" | grep -E "\.php:[0-9]+:|^ *(Error|Fatal)" | head -20 | sed "s#^$BASE_DIR/#      #"
        FAILED=1
    fi
else
    echo ""
    echo "  NOTICE: vendor/bin/ecs or vendor/bin/phpstan not installed (composer install with dev packages) — style and static analysis not run."
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo " Code quality standards, PHPStan Level 8, and tooling are properly configured."
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED"
    echo " Please review the errors reported above."
    echo "=========================================================="
    exit 1
fi
