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
TARGET_LOCALE="$1"

echo "=========================================================="
echo " Bolt CMS New Language / Locale Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

if [ -z "$TARGET_LOCALE" ]; then
    echo "Usage: $0 <locale_code> (e.g. $0 de)"
    echo "Scanning current locales registered in config/services.yaml..."
    grep -E "(locale|locales_array|app_locales)" config/services.yaml || true
    exit 1
fi

echo "Verifying integration for locale: '$TARGET_LOCALE'..."
FAILED=0

# 1. Check services.yaml
echo -n "[1/7] Checking config/services.yaml... "
if grep -q "$TARGET_LOCALE" config/services.yaml; then
    echo "PASSED"
else
    echo "FAILED ('$TARGET_LOCALE' not found in config/services.yaml)"
    FAILED=1
fi

# 2. Check contenttypes.yaml
echo -n "[2/7] Checking config/bolt/contenttypes.yaml... "
MISSING_CT=$(grep -n "locales:" config/bolt/contenttypes.yaml | grep -v "'$TARGET_LOCALE'" | grep -v "$TARGET_LOCALE" || true)
if [ -z "$MISSING_CT" ]; then
    echo "PASSED (Declared on all ContentTypes)"
else
    echo "FAILED (Some ContentTypes are missing '$TARGET_LOCALE'):"
    echo "$MISSING_CT"
    FAILED=1
fi

# 3. Check XLIFF catalog file
echo -n "[3/7] Checking translations/messages.$TARGET_LOCALE.xlf existence... "
CATALOG="translations/messages.$TARGET_LOCALE.xlf"
if [ -f "$CATALOG" ]; then
    echo "PASSED"
else
    echo "FAILED ($CATALOG does not exist)"
    FAILED=1
fi

# 4. Check Unit Parity against source catalog
echo -n "[4/7] Checking catalog unit parity... "
DEFAULT_LOCALE=$(grep -E "^\s*locale:" config/services.yaml | awk '{print $2}' | tr -d "'" | tr -d '"' || echo "cs")
SOURCE_CATALOG="translations/messages.$DEFAULT_LOCALE.xlf"

if [ -f "$SOURCE_CATALOG" ] && [ -f "$CATALOG" ]; then
    SOURCE_COUNT=$(grep -c '<unit ' "$SOURCE_CATALOG" || true)
    TARGET_COUNT=$(grep -c '<unit ' "$CATALOG" || true)
    if [ "$SOURCE_COUNT" -eq "$TARGET_COUNT" ]; then
        echo "PASSED (Parity: $TARGET_COUNT units)"
    else
        echo "WARNING / NOTICE (Source has $SOURCE_COUNT units, target has $TARGET_COUNT units)"
    fi
else
    echo "SKIPPED (Source catalog $SOURCE_CATALOG not found)"
fi

# 5. Lint XLIFF Catalogs
echo -n "[5/7] Linting XLIFF catalogs with Symfony console... "
if php bin/console lint:xliff translations > /dev/null 2>&1; then
    echo "PASSED"
else
    echo "FAILED (XLIFF syntax errors detected)"
    FAILED=1
fi

# 6. Check Navigation Menu
echo -n "[6/7] Checking config/bolt/menu.yaml... "
if grep -q "$TARGET_LOCALE:" config/bolt/menu.yaml 2>/dev/null; then
    echo "PASSED"
else
    echo "WARNING / NOTICE ('$TARGET_LOCALE:' not found in menu.yaml labels)"
fi

# 7. Check Theme Switcher
echo -n "[7/7] Checking theme _locale-switcher.twig... "
SWITCHER=$(find public/theme -name '_locale-switcher.twig' 2>/dev/null | head -n 1 || true)
if [ -n "$SWITCHER" ]; then
    if grep -q "'$TARGET_LOCALE'" "$SWITCHER"; then
        echo "PASSED (Found in $SWITCHER)"
    else
        echo "WARNING / NOTICE ('$TARGET_LOCALE' not found in $SWITCHER)"
    fi
else
    echo "SKIPPED (No _locale-switcher.twig found)"
fi

echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo " RESULT: Locale '$TARGET_LOCALE' integration checks passed!"
    exit 0
else
    echo " RESULT: Verification encountered failures."
    exit 1
fi
