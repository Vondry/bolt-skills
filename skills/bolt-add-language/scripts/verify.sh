#!/usr/bin/env bash
set -e

# bolt-add-language verification for one locale: configuration files (scripts/check-language.php
# parses services.yaml, contenttypes.yaml, the XLIFF catalogs and menu.yaml), XLIFF lint, the
# theme's locale switcher and its hreflang alternates.
#
# Usage: verify.sh <locale_code>   (e.g. verify.sh de)

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_LOCALE="${1:-}"

echo "=========================================================="
echo " Bolt CMS New Language / Locale Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

if [ -z "$TARGET_LOCALE" ]; then
    echo "Usage: $0 <locale_code> (e.g. $0 de)"
    echo "Locales registered in config/services.yaml:"
    grep -E "^[[:space:]]*(locale|app_locales):" config/services.yaml || true
    exit 1
fi

echo "Verifying integration for locale: '$TARGET_LOCALE'"

FAILED=0
WARNINGS=0
SECTION=0
TOTAL_SECTIONS=7

section() { SECTION=$((SECTION + 1)); echo ""; echo "[$SECTION/$TOTAL_SECTIONS] $1"; }
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ✗ FAILED: $1"; FAILED=$((FAILED + 1)); }

# -------------------------------------------------------------
# 1–4. app_locales, ContentTypes, catalogs (existence and key parity), menus
# -------------------------------------------------------------
while IFS= read -r line; do
    kind="${line%% *}"
    message="${line#* }"
    case "$kind" in
        SECTION) section "$message" ;;
        PASS) pass "$message" ;;
        WARN) warn "$message" ;;
        FAIL) fail "$message" ;;
        *) [ -n "$line" ] && echo "  $line" ;;
    esac
done < <(php "$SCRIPT_DIR/check-language.php" "$BASE_DIR" "$TARGET_LOCALE" 2>&1)

# -------------------------------------------------------------
# 5. XLIFF syntax
# -------------------------------------------------------------
section "XLIFF syntax (bin/console lint:xliff translations)"
if php bin/console lint:xliff translations > /dev/null 2>&1; then
    pass "all catalogs are valid XLIFF"
else
    fail "lint:xliff reports errors — run: php bin/console lint:xliff translations"
fi

# -------------------------------------------------------------
# 6. Theme language switcher
# -------------------------------------------------------------
section "Theme language switcher (partials/_locale-switcher.twig)"
SWITCHER=$(find public/theme -name '_locale-switcher.twig' -not -path '*/node_modules/*' 2>/dev/null | head -n 1 || true)
if [ -z "$SWITCHER" ]; then
    warn "no _locale-switcher.twig found — copy examples/_locale-switcher.twig (Step 6)"
elif grep -qE "['\"]${TARGET_LOCALE}['\"][[:space:]]*:" "$SWITCHER"; then
    pass "'$TARGET_LOCALE' is in the locales map of $SWITCHER"
else
    warn "'$TARGET_LOCALE' is not in the locales map of $SWITCHER — add its endonym (Step 6)"
fi

# -------------------------------------------------------------
# 7. hreflang alternates in <head>
# -------------------------------------------------------------
section "hreflang alternates (partials/_hreflang.twig in the master layout)"
HREFLANG=$(find public/theme -name '_hreflang.twig' -not -path '*/node_modules/*' 2>/dev/null | head -n 1 || true)
MASTER=$(find public/theme -path '*/partials/_master.twig' -not -path '*/node_modules/*' 2>/dev/null | head -n 1 || true)
if [ -n "$HREFLANG" ]; then
    if [ -n "$MASTER" ] && ! grep -q "_hreflang.twig" "$MASTER"; then
        fail "$HREFLANG exists but $MASTER does not include it — add {% include 'partials/_hreflang.twig' ignore missing %} to the seo block (Step 6)"
    elif grep -qE "['\"]${TARGET_LOCALE}['\"]" "$HREFLANG"; then
        pass "'$TARGET_LOCALE' is in the locales list of $HREFLANG"
    else
        fail "'$TARGET_LOCALE' is not in the locales list of $HREFLANG — search engines do not learn about this version (Step 6)"
    fi
# Page <link> tags only: the sitemap template's <xhtml:link rel="alternate" hreflang> does not count.
elif grep -rqE '<link[^>]*rel="alternate"[^>]*hreflang|<link[^>]*hreflang[^>]*rel="alternate"' public/theme --include='*.twig' 2>/dev/null; then
    pass "the theme prints its own <link rel=\"alternate\" hreflang> tags"
else
    fail "no <link rel=\"alternate\" hreflang> in the theme — copy examples/_hreflang.twig and include it in the master layout (Step 6)"
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " RESULT: Locale '$TARGET_LOCALE' integration checks passed ($WARNINGS warning(s))."
    echo "=========================================================="
    exit 0
else
    echo " RESULT: Verification encountered failures ($FAILED failure(s), $WARNINGS warning(s))."
    echo "=========================================================="
    exit 1
fi
