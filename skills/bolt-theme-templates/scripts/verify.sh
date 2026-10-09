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

BOLT_CONFIG="config/bolt/config.yaml"

echo "=========================================================="
echo " Bolt CMS Theme Templates & Architecture Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

# True when a template contains a real {% setcontent %} tag (Twig comments {# … #} are ignored,
# so documentation such as "Rules: Zero setcontent." does not count).
has_setcontent_tag() {
    perl -0777 -ne 's/\{#.*?#\}//gs; exit(/\{%-?\s*setcontent\b/ ? 0 : 1)' "$1"
}

# Lists templates under a directory that contain a real {% setcontent %} tag.
find_setcontent_tags() {
    find "$1" -type f -name "*.twig" 2>/dev/null | while IFS= read -r tpl; do
        if has_setcontent_tag "$tpl"; then
            echo "$tpl"
        fi
    done
}

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Detect Active Theme
# -------------------------------------------------------------
echo -n "[1/8] Detecting active theme... "
ACTIVE_THEME="default"
if [ -f "$BOLT_CONFIG" ]; then
    FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$FOUND_THEME" ]; then
        ACTIVE_THEME="$FOUND_THEME"
    fi
fi

THEME_DIR="public/theme/$ACTIVE_THEME"
if [ ! -d "$THEME_DIR" ]; then
    echo "FAILED: Theme directory '$THEME_DIR' does not exist."
    exit 1
fi
echo "PASSED (Theme: '$ACTIVE_THEME')"

# -------------------------------------------------------------
# 2. Check Directory Structure & Layout Shell (Integration Contract)
# -------------------------------------------------------------
echo -n "[2/8] Checking architectural directories and partials/_master.twig... "
STRUCT_ERRORS=()
for d in components containers pages; do
    [ -d "$THEME_DIR/$d" ] || STRUCT_ERRORS+=("Missing $d/ folder")
done
MASTER="$THEME_DIR/partials/_master.twig"
if [ ! -f "$MASTER" ]; then
    STRUCT_ERRORS+=("Missing partials/_master.twig (the layout every page extends)")
elif ! grep -qE "\{%-?[[:space:]]*block[[:space:]]+main[[:space:]]*-?%\}" "$MASTER"; then
    STRUCT_ERRORS+=("partials/_master.twig does not define {% block main %}")
fi

if [ ${#STRUCT_ERRORS[@]} -eq 0 ]; then
    echo "PASSED (components/, containers/, pages/ and partials/_master.twig with block main)"
else
    echo "WARNING"
    for err in "${STRUCT_ERRORS[@]}"; do
        echo "  - $err"
    done
    WARNINGS=$((WARNINGS + 1))
fi

# -------------------------------------------------------------
# 3. Strict Pure Component Audit: ZERO setcontent in components/
# -------------------------------------------------------------
echo -n "[3/8] Auditing pure components (ZERO setcontent rule)... "
SETCONTENT_VIOLATIONS=0

# Find all components directories (both top-level and page-scoped)
COMPONENT_DIRS=$(find "$THEME_DIR" -type d -name "components" 2>/dev/null || true)

if [ -n "$COMPONENT_DIRS" ]; then
    while IFS= read -r cdir; do
        VIOLATIONS=$(find_setcontent_tags "$cdir")
        if [ -n "$VIOLATIONS" ]; then
            echo ""
            echo "  VIOLATION: setcontent found inside pure component directory '$cdir':"
            echo "$VIOLATIONS" | sed 's/^/    - /'
            SETCONTENT_VIOLATIONS=$((SETCONTENT_VIOLATIONS + 1))
        fi
    done <<< "$COMPONENT_DIRS"

    if [ $SETCONTENT_VIOLATIONS -gt 0 ]; then
        echo "FAILED: Pure components must NEVER call setcontent. Data must be passed via props."
        FAILED=1
    else
        echo "PASSED (All components are pure with zero setcontent)"
    fi
else
    echo "PASSED (No dedicated components/ directory to audit yet)"
fi

# -------------------------------------------------------------
# 4. Page Orchestrator Audit: every page extends a layout
# -------------------------------------------------------------
echo -n "[4/8] Auditing page orchestrators in pages/... "
if [ -d "$THEME_DIR/pages" ]; then
    PAGE_FILES=$(find "$THEME_DIR/pages" -name "*.twig" ! -path "*/components/*" 2>/dev/null || true)
    PAGE_COUNT=0
    NOT_EXTENDING=()
    while IFS= read -r page; do
        [ -z "$page" ] && continue
        PAGE_COUNT=$((PAGE_COUNT + 1))
        if ! grep -qE "\{%-?[[:space:]]*extends[[:space:]]" "$page"; then
            NOT_EXTENDING+=("$page")
        fi
    done <<< "$PAGE_FILES"

    if [ ${#NOT_EXTENDING[@]} -gt 0 ]; then
        echo "WARNING"
        for page in "${NOT_EXTENDING[@]}"; do
            echo "  - $page does not {% extends %} a layout (expected 'partials/_master.twig')"
        done
        WARNINGS=$((WARNINGS + 1))
    else
        echo "PASSED (Found $PAGE_COUNT page templates, all extending a layout)"
    fi
else
    echo "SKIPPED (No pages/ directory)"
fi

# -------------------------------------------------------------
# 5. Link Locale Safety Audit: locale_link usage
# -------------------------------------------------------------
echo -n "[5/8] Auditing URL localization safety (locale_link usage)... "
LOCALE_LINKS=$(grep -rn "locale_link(" "$THEME_DIR" --include="*.twig" 2>/dev/null || true)
if [ -n "$LOCALE_LINKS" ]; then
    echo "PASSED (Found locale_link calls wrapping template URLs)"
else
    echo "WARNING: No locale_link() calls found. Multilingual routing may lose active locale."
    WARNINGS=$((WARNINGS + 1))
fi

# -------------------------------------------------------------
# 6. Translation Fallback Trap: __('key')|default('…')
#    The translator returns the key itself for a missing translation, so the
#    default never renders; every key must exist in every catalog instead.
# -------------------------------------------------------------
echo -n "[6/8] Checking for __('key')|default(...) fallbacks... "
DEFAULT_TRAPS=$(grep -rnE "__\([^)]*\)\|default\(" "$THEME_DIR" --include="*.twig" --exclude-dir=node_modules 2>/dev/null || true)
if [ -n "$DEFAULT_TRAPS" ]; then
    echo "WARNING"
    echo "  The default never applies (a missing key renders as the key). Add the keys to translations/messages.<locale>.xlf:"
    echo "$DEFAULT_TRAPS" | head -10 | sed 's/^/    - /'
    WARNINGS=$((WARNINGS + 1))
else
    echo "PASSED"
fi

# -------------------------------------------------------------
# 7. Undefined Tailwind Classes (colour/token utilities missing from the build)
# -------------------------------------------------------------
echo -n "[7/8] Checking template classes against the compiled css/index.css... "
CSS_OUT="$THEME_DIR/css/index.css"
if [ ! -s "$CSS_OUT" ]; then
    echo "SKIPPED (css/index.css not built yet — run npm run prod in the theme)"
else
    # Twig comments are stripped first, so prose such as "call-to-action" is not mistaken for a class.
    MISSING_CLASSES=$(find "$THEME_DIR" -name "*.twig" -not -path "*/helper-pages/*" -not -path "*/node_modules/*" -print0 2>/dev/null \
        | xargs -0 perl -0777 -ne 's/\{#.*?#\}//gs; print' 2>/dev/null \
        | grep -oE "\b(bg|text|border|ring|outline|fill|stroke|from|via|to|divide|decoration|accent|caret|shadow)-[a-z]+(-[a-z0-9]+)*" \
        | grep -vE '^stroke-(linecap|linejoin|width|dasharray|dashoffset|miterlimit|opacity)$' \
        | sort -u | while read -r cls; do
            grep -qE -- "${cls}([^a-zA-Z0-9-]|\$)" "$CSS_OUT" || echo "$cls"
        done)
    if [ -n "$MISSING_CLASSES" ]; then
        echo "WARNING"
        echo "  Classes used in templates but not generated (undefined token names?):"
        echo "$MISSING_CLASSES" | head -30 | sed 's/^/    - /'
        echo "  Rebuild with npm run prod first; prose words in templates can appear as false positives."
        WARNINGS=$((WARNINGS + 1))
    else
        echo "PASSED (every colour/token utility used in templates exists in the build)"
    fi
fi

# -------------------------------------------------------------
# 8. Twig Syntax Linting
# -------------------------------------------------------------
echo -n "[8/8] Linting Twig syntax via bin/console lint:twig... "
if [ -f "bin/console" ]; then
    if php bin/console lint:twig "$THEME_DIR" > /dev/null 2>&1; then
        echo "PASSED (0 syntax errors in $THEME_DIR)"
    else
        echo "FAILED: Twig syntax error detected."
        php bin/console lint:twig "$THEME_DIR" || true
        FAILED=1
    fi
else
    echo "SKIPPED (bin/console not available)"
fi

echo "=========================================================="
if [ $FAILED -ne 0 ]; then
    echo " VERIFICATION FAILED ($FAILED critical error(s), $WARNINGS warning(s))"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo " VERIFICATION PASSED with $WARNINGS warning(s)."
    exit 0
else
    echo " VERIFICATION PASSED (All checks green)."
    exit 0
fi
