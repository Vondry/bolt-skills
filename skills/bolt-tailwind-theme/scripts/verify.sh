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
if ! grep -qE "@utility[[:space:]]+wrapper\b|\.wrapper[[:space:]]*\{" "$CSS_ENTRY"; then
    UTIL_ERRORS+=("Missing wrapper utility class")
fi
if ! grep -qE "@utility[[:space:]]+btn\b|\.btn[[:space:]]*\{" "$CSS_ENTRY"; then
    UTIL_ERRORS+=("Missing btn utility class")
fi
if ! grep -qE "\.cms-redactor\b" "$CSS_ENTRY"; then
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

# 6. Test compilation with @tailwindcss/cli — into a temporary file, so the check never rewrites
#    the theme's css/index.css (bolt-audit promises to change nothing in the project).
echo -n "[6/6] Verifying Tailwind CSS compilation... "
if [ -f "$THEME_DIR/package.json" ] && [ -d "$THEME_DIR/node_modules" ] && command -v npx &>/dev/null; then
    TMP_CSS=$(mktemp -t bolt-tailwind-XXXXXX).css
    if (cd "$THEME_DIR" && npx --no-install @tailwindcss/cli --input ./css/tailwind/index.css --output "$TMP_CSS" --minify > /dev/null 2>&1) && [ -s "$TMP_CSS" ]; then
        SIZE=$(wc -c < "$TMP_CSS" | tr -d ' ')
        echo "PASSED (compiles, $SIZE bytes)"
        # Helper pages and inline styles read the tokens with var(); Tailwind v4 emits a token as a
        # variable only when something references it, unless the block is @theme static.
        if ! grep -q -- "--color-accent:" "$TMP_CSS"; then
            echo "  WARNING: the build defines no --color-accent variable — use @theme static inline (section 3), or the helper pages fall back to hard-coded colours."
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "FAILED: compilation failed or produced an empty file"
        FAILED=1
    fi
    rm -f "$TMP_CSS"
else
    echo "SKIPPED (npm or the theme's node_modules not available — run npm install in $THEME_DIR)"
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
