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
echo " Bolt CMS Tailwind Theme Tokens & Utilities Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# 1. Get active theme
BOLT_CONFIG="config/bolt/config.yaml"
if [ ! -f "$BOLT_CONFIG" ]; then
    echo "FAILED: $BOLT_CONFIG not found."
    exit 1
fi

ACTIVE_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$ACTIVE_THEME" ]; then
    echo "FAILED: No active theme set in $BOLT_CONFIG."
    exit 1
fi

THEME_DIR="public/theme/$ACTIVE_THEME"
CSS_ENTRY="$THEME_DIR/css/tailwind/index.css"

echo "[1/6] Checking theme Tailwind entrypoint: $CSS_ENTRY... "
if [ ! -f "$CSS_ENTRY" ]; then
    echo "FAILED"
    echo "  Error: $CSS_ENTRY does not exist!"
    exit 1
fi
echo "PASSED (Theme '$ACTIVE_THEME')"

# 2. Check scanning safeguards
echo -n "[2/6] Checking scanning directives and safeguards (@source)... "
SOURCE_ERRORS=()
if ! grep -q "@source.*translations" "$CSS_ENTRY"; then
    SOURCE_ERRORS+=("Missing @source directive for translations directory")
fi
if ! grep -q '@source not "\.\./index\.css"' "$CSS_ENTRY" && ! grep -q "@source not '../index.css'" "$CSS_ENTRY"; then
    SOURCE_ERRORS+=("Missing safeguard: @source not \"../index.css\" (prevents compilation feedback loop)")
fi

if [ ${#SOURCE_ERRORS[@]} -gt 0 ]; then
    echo "FAILED"
    for err in "${SOURCE_ERRORS[@]}"; do
        echo "  - $err"
    done
    FAILED=1
else
    echo "PASSED"
fi

# 3. Check @theme block and core tokens
echo -n "[3/6] Checking @theme design tokens... "
TOKEN_ERRORS=()
if ! grep -q "@theme" "$CSS_ENTRY"; then
    TOKEN_ERRORS+=("Missing @theme or @theme inline block")
fi
if ! grep -q -- "--spacing-header" "$CSS_ENTRY"; then
    TOKEN_ERRORS+=("Missing --spacing-header token (header height and anchor scroll offset)")
fi
if ! grep -qE -- "--color-(accent|brand)" "$CSS_ENTRY"; then
    TOKEN_ERRORS+=("Missing brand/accent color token (--color-accent or --color-brand)")
fi

if [ ${#TOKEN_ERRORS[@]} -gt 0 ]; then
    echo "FAILED"
    for err in "${TOKEN_ERRORS[@]}"; do
        echo "  - $err"
    done
    FAILED=1
else
    echo "PASSED"
fi

# 4. Check sticky header scroll margin offset
echo -n "[4/6] Checking anchor scroll-margin-top offset... "
if grep -q "scroll-margin-top" "$CSS_ENTRY" || grep -q "scroll-padding-top" "$CSS_ENTRY"; then
    echo "PASSED"
else
    echo "WARNING: No scroll-margin-top or scroll-padding-top rule found in $CSS_ENTRY. In-page anchors may hide behind sticky header."
    WARNINGS=$((WARNINGS + 1))
fi

# 5. Check repeating utilities (.wrapper, .btn, .cms-redactor)
echo -n "[5/6] Checking repeating utility classes (wrapper, btn, cms-redactor)... "
UTIL_ERRORS=()
if ! grep -q "wrapper" "$CSS_ENTRY"; then
    UTIL_ERRORS+=("Missing wrapper utility class")
fi
if ! grep -q "btn" "$CSS_ENTRY"; then
    UTIL_ERRORS+=("Missing btn utility class")
fi
if ! grep -q "cms-redactor" "$CSS_ENTRY"; then
    UTIL_ERRORS+=("Missing .cms-redactor prose styling class")
fi

if [ ${#UTIL_ERRORS[@]} -gt 0 ]; then
    echo "WARNING"
    for err in "${UTIL_ERRORS[@]}"; do
        echo "  - $err"
    done
    WARNINGS=$((WARNINGS + 1))
else
    echo "PASSED"
fi

# 6. Test compilation with @tailwindcss/cli
echo -n "[6/6] Verifying Tailwind CSS compilation... "
if [ -f "$THEME_DIR/package.json" ] && command -v npm &>/dev/null; then
    COMPILED=0
    if grep -q '"build:css"' "$THEME_DIR/package.json"; then
        if (cd "$THEME_DIR" && npm run build:css > /dev/null 2>&1); then
            COMPILED=1
        fi
    elif (cd "$THEME_DIR" && npx @tailwindcss/cli --input ./css/tailwind/index.css --output ./css/index.css --minify > /dev/null 2>&1); then
        COMPILED=1
    fi

    if [ $COMPILED -eq 1 ] && [ -s "$THEME_DIR/css/index.css" ]; then
        SIZE=$(wc -c < "$THEME_DIR/css/index.css" | tr -d ' ')
        echo "PASSED (css/index.css compiled successfully, $SIZE bytes)"
    else
        echo "FAILED: Compilation failed or css/index.css is empty"
        FAILED=1
    fi
else
    echo "SKIPPED (npm not available or package.json not found)"
fi

echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo " RESULT: ALL TAILWIND THEME CHECKS PASSED PERFECTLY!"
    else
        echo " RESULT: PASSED with $WARNINGS warning(s)."
    fi
    exit 0
else
    echo " RESULT: VERIFICATION FAILED with errors above."
    exit 1
fi
