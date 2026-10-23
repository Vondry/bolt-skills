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
echo -n "[1/10] Detecting active theme... "
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
echo -n "[2/10] Checking architectural directories and partials/_master.twig... "
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
echo -n "[3/10] Auditing pure components (ZERO setcontent rule)... "
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
echo -n "[4/10] Auditing page orchestrators in pages/... "
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
echo -n "[5/10] Auditing URL localization safety (locale_link usage)... "
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
echo -n "[6/10] Checking for __('key')|default(...) fallbacks... "
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
echo -n "[7/10] Checking template classes against the compiled css/index.css... "
CSS_OUT="$THEME_DIR/css/index.css"
if [ ! -s "$CSS_OUT" ]; then
    echo "SKIPPED (css/index.css not built yet — run npm run prod in the theme)"
else
    # Twig comments are stripped first, so prose such as "call-to-action" is not mistaken for a class.
    # A utility must start a token (not follow a letter, digit or hyphen), so ids and slugs such as
    # "jak-to-funguje" or "back-to-top" are not read as to-*/from-* gradient utilities.
    MISSING_CLASSES=$(find "$THEME_DIR" -name "*.twig" -not -path "*/helper-pages/*" -not -path "*/node_modules/*" -print0 2>/dev/null \
        | xargs -0 perl -0777 -ne 's/\{#.*?#\}//gs; print' 2>/dev/null \
        | perl -ne 'print "$1\n" while /(?<![\w-])((?:bg|text|border|ring|outline|fill|stroke|from|via|to|divide|decoration|accent|caret|shadow)-[a-z]+(?:-[a-z0-9]+)*)/g' \
        | grep -vE '^stroke-(linecap|linejoin|width|dasharray|dashoffset|miterlimit|opacity)$' \
        | sort -u | while read -r cls; do
            grep -qE -- "${cls}([^a-zA-Z0-9-]|\$)" "$CSS_OUT" || echo "$cls"
        done)
    # Integration Contract utilities (bolt-tailwind-theme) used in class="…" or in a {% set … = '…' %}
    # class variable. The skills' shared partials rely on them; in a theme that never defined one,
    # Tailwind generates nothing (a page without section padding, a button that looks like text).
    CONTRACT_UTILITIES="wrapper px-edge py-section no-scrollbar btn btn-primary btn-secondary btn-outline btn-ghost btn-on-accent btn-on-accent-outline card link-arrow cms-redactor"
    USED_TOKENS=$(find "$THEME_DIR" -name "*.twig" -not -path "*/node_modules/*" -print0 2>/dev/null \
        | xargs -0 perl -0777 -ne 's/\{#.*?#\}//gs; print' 2>/dev/null \
        | perl -ne 'while (/class="([^"]*)"|\{%-?\s*set\s+\w+\s*=\s*\x27([^\x27]*)\x27/g) { print "$_\n" for split /\s+/, ($1 // $2) }' \
        | sort -u)
    for cls in $CONTRACT_UTILITIES; do
        if grep -qxF -- "$cls" <<< "$USED_TOKENS" && ! grep -qE -- "\.${cls}([^a-zA-Z0-9_-]|\$)" "$CSS_OUT"; then
            MISSING_CLASSES=$(printf '%s\n%s' "$MISSING_CLASSES" "$cls (Integration Contract utility — define it in css/tailwind/index.css, see bolt-tailwind-theme)" | sed '/^$/d')
        fi
    done
    if [ -n "$MISSING_CLASSES" ]; then
        echo "WARNING"
        echo "  Classes used in templates but not generated (undefined token names?):"
        echo "$MISSING_CLASSES" | head -30 | sed 's/^/    - /'
        echo "  Rebuild with npm run prod first; prose words in templates can appear as false positives."
        WARNINGS=$((WARNINGS + 1))
    else
        echo "PASSED (every colour/token and Integration Contract utility used in templates exists in the build)"
    fi
fi

# -------------------------------------------------------------
# 8. Canonical Tailwind classes (the IDE's "can be written as" hint)
# -------------------------------------------------------------
echo -n "[8/10] Checking that Tailwind classes use their canonical (token) form... "
CANONICAL_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/canonical-classes.mjs"
if ! command -v node > /dev/null 2>&1; then
    echo "SKIPPED (node not available)"
else
    set +e
    CANONICAL_OUT=$(node "$CANONICAL_SCRIPT" --theme "$THEME_DIR" 2>&1)
    CANONICAL_STATUS=$?
    set -e
    if [ $CANONICAL_STATUS -eq 0 ]; then
        echo "PASSED (no class has a shorter token form)"
    elif [ $CANONICAL_STATUS -eq 2 ]; then
        echo "$CANONICAL_OUT" | sed 's/^SKIPPED: /SKIPPED (/; s/$/)/'
    else
        echo "FAILED"
        echo "$CANONICAL_OUT" | head -40 | sed 's/^/    /'
        echo "  Fix: node $CANONICAL_SCRIPT --fix, review the diff (a value match is not always a meaning match), npm run prod."
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 9. Twig Syntax Linting
# -------------------------------------------------------------
echo -n "[9/10] Linting Twig syntax via bin/console lint:twig... "
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

# -------------------------------------------------------------
# 10. Search page: Bolt serves /search and /{_locale}/search on every site
# -------------------------------------------------------------
echo "[10/10] Checking the search page (template, locale, escaping, live results)..."
yaml_value() { grep -E "^$1:" "$2" 2>/dev/null | head -n 1 | sed -E "s/^$1:[[:space:]]*//; s/[[:space:]]+#.*$//" | tr -d "\"'"; }
SEARCH_TEMPLATE=$(yaml_value search_results_template "$THEME_DIR/theme.yaml")
[ -z "$SEARCH_TEMPLATE" ] && SEARCH_TEMPLATE=$(yaml_value search_results_template "$BOLT_CONFIG")
[ -z "$SEARCH_TEMPLATE" ] && SEARCH_TEMPLATE=$(yaml_value listing_template "$BOLT_CONFIG")
if [ -z "$SEARCH_TEMPLATE" ] || [ ! -f "$THEME_DIR/$SEARCH_TEMPLATE" ]; then
    echo "  ✗ FAILED: the search template '${SEARCH_TEMPLATE:-(none)}' does not exist in $THEME_DIR — run scaffold.sh (search.twig → pages/search/search.twig)"
    FAILED=$((FAILED + 1))
else
    echo "  ✓ search_results_template: $SEARCH_TEMPLATE exists"
    # The search template and everything under its folder (page-scoped components, the extended page)
    SEARCH_FILES=$( { echo "$THEME_DIR/$SEARCH_TEMPLATE"; perl -ne "print \"$THEME_DIR/\$1\n\" if /\{%-?\s*extends\s+'([^']+)'/" "$THEME_DIR/$SEARCH_TEMPLATE"; } | sort -u)
    SEARCH_DIRS=$(for f in $SEARCH_FILES; do [ -f "$f" ] && dirname "$f"; done | sort -u | grep -vx "$THEME_DIR" || true)
    SEARCH_SCOPE=$( { echo "$SEARCH_FILES"; for d in $SEARCH_DIRS; do find "$d" -name '*.twig'; done; } | sort -u | while read -r f; do [ -f "$f" ] && echo "$f"; done)
    # path('search') is always the default locale: a form posting there sends /en/search visitors to Czech results.
    LOCALE_LOST=$(grep -rnE "action=\"\{\{ *path\('search'\) *\}\}\"" "$THEME_DIR" --include='*.twig' 2>/dev/null | grep -v node_modules || true)
    if [ -n "$LOCALE_LOST" ]; then
        echo "  ✗ FAILED: a search form posts to path('search'), the default locale only — use the current route (see pages/search/components/search-form.twig):"
        echo "$LOCALE_LOST" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    fi
    # __() output is printed unescaped and the term keeps the HTML cleaner's allowed tags.
    UNESCAPED=$(echo "$SEARCH_SCOPE" | xargs perl -0777 -ne 's/\{#.*?#\}//gs; while (/(__\([^)]*?:\s*(?:searchTerm|search|term)\s*[,}])/g) { print "$ARGV: $1\n" }' 2>/dev/null || true)
    if [ -n "$UNESCAPED" ]; then
        echo "  ✗ FAILED: the search term goes into __() unescaped — write searchTerm|e (Bolt's cleaner keeps tags like <img> and <a>):"
        echo "$UNESCAPED" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    fi
    [ -z "$LOCALE_LOST" ] && [ -z "$UNESCAPED" ] && echo "  ✓ the form keeps the locale and the term is escaped"
fi

# Live: against BOLT_BASE_URL, else PHP's built-in server started for this check.
LOCALES=$(grep -E "^\s*app_locales:" config/services.yaml 2>/dev/null | head -n 1 | sed -E "s/.*app_locales:[[:space:]]*//" | tr -d "\"'" | tr '|' ',')
DEFAULT_LOCALE=$(grep -E "^\s*locale:" config/services.yaml 2>/dev/null | head -n 1 | sed -E "s/.*locale:[[:space:]]*//" | tr -d "\"'")
if [ -n "$DEFAULT_LOCALE" ] && [ -n "$LOCALES" ]; then
    LOCALES=$( { echo "$DEFAULT_LOCALE"; echo "$LOCALES" | tr ',' '\n'; } | awk 'NF && !seen[$0]++' | paste -sd, - )
fi
SEARCH_BASE=""
SERVER_PID=""
if [ -n "${BOLT_BASE_URL:-}" ] && curl -s --max-time 10 -o /dev/null "$BOLT_BASE_URL"; then
    SEARCH_BASE="${BOLT_BASE_URL%/}"
elif command -v php > /dev/null 2>&1 && [ -f public/index.php ]; then
    PORT=$((18000 + RANDOM % 1000))
    # The project's .env may limit trusted hosts to the production domain; 127.0.0.1 must pass here.
    SYMFONY_TRUSTED_HOSTS='' php -S "127.0.0.1:$PORT" -t public "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/php-server-router.php" > /dev/null 2>&1 &
    SERVER_PID=$!
    trap '[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null' EXIT
    for _ in $(seq 1 30); do
        curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$PORT/" && { SEARCH_BASE="http://127.0.0.1:$PORT"; break; }
        sleep 0.5
    done
fi
if [ -z "$SEARCH_BASE" ]; then
    echo "  ✗ FAILED: no site to test against — set BOLT_BASE_URL, or make PHP's built-in server start (php -S, database reachable)"
    FAILED=$((FAILED + 1))
else
    echo "  (live check against $SEARCH_BASE${SERVER_PID:+, PHP built-in server}; locales: ${LOCALES:-default only})"
    if php "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-search.php" --base-url="$SEARCH_BASE" --locales="$LOCALES" ${BOLT_SEARCH_TERM:+--term="$BOLT_SEARCH_TERM"}; then
        :
    else
        FAILED=$((FAILED + $?))
    fi
fi
[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && SERVER_PID=""

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
