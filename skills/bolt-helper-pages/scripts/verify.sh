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
echo " Bolt CMS Helper & Error Pages Verification"
echo " (404 Not Found, 403 Forbidden, 500 Error, 503 Maintenance)"
echo " Project root: $BASE_DIR"
echo "=========================================================="

# True when a template contains a real {% setcontent %} tag (Twig comments {# … #} are ignored,
# so documentation such as "Rules: Zero setcontent." does not count).
has_setcontent_tag() {
    perl -0777 -ne 's/\{#.*?#\}//gs; exit(/\{%-?\s*setcontent\b/ ? 0 : 1)' "$1"
}

# True when a template queries the database: a {% setcontent %} tag or a menu_array() call
# (comments ignored).
has_db_lookup() {
    perl -0777 -ne 's/\{#.*?#\}//gs; exit(/\{%-?\s*setcontent\b|\bmenu_array\s*\(/ ? 0 : 1)' "$1"
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

CONFIG_FILE="config/bolt/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '$CONFIG_FILE' not found."
    exit 1
fi

# Detect active theme
THEME_NAME=$(grep -E "^theme:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
if [ -z "$THEME_NAME" ]; then
    THEME_NAME="default"
fi
THEME_DIR="public/theme/$THEME_NAME"
HELPER_DIR="$THEME_DIR/helper-pages"

echo "Active theme detected: '$THEME_NAME'"
echo "Helper pages directory: $HELPER_DIR"
echo ""

# -------------------------------------------------------------
# 1. Check config/bolt/config.yaml mappings
# -------------------------------------------------------------
echo "[1/5] Checking config/bolt/config.yaml error page mappings..."

check_config_mapping() {
    local key="$1"
    local expected_pattern="$2"
    echo -n "  • $key: "
    local val
    val=$(grep -E "^\s*$key:" "$CONFIG_FILE" 2>/dev/null | head -1 || true)
    if [ -z "$val" ]; then
        echo "MISSING from $CONFIG_FILE"
        FAILED=1
    elif echo "$val" | grep -q "$expected_pattern"; then
        echo "CONFIGURED ($val)"
    else
        echo "CUSTOM/UNEXPECTED ($val)"
        echo "    Recommended: $key: [ 'helper-pages/$expected_pattern' ]"
        WARNINGS=$((WARNINGS+1))
    fi
}

check_config_mapping "notfound" "notfound.404.twig"
check_config_mapping "maintenance" "maintenance.503.twig"
check_config_mapping "forbidden" "forbidden.403.twig"
check_config_mapping "internal_server_error" "internal-server-error.500.twig"

# 500 and 503 must name a root entrypoint (no '/'): Bolt's ErrorController looks up every item
# containing '/' as a contenttype/slug record first — a database query before the page renders,
# which fails exactly when the database is down (SKILL.md section 5).
check_root_entrypoint() {
    local key="$1" file="$2" severity="$3"
    local val
    val=$(grep -E "^$key:" "$CONFIG_FILE" 2>/dev/null | head -1 || true)
    [ -z "$val" ] && return
    if echo "$val" | grep -q "/"; then
        echo "  ❌ $key names a path with '/' — Bolt queries the database for it before rendering. Use [ '$file' ] with a root entrypoint (examples/root-$file)."
        if [ "$severity" = "fail" ]; then FAILED=1; else WARNINGS=$((WARNINGS+1)); fi
    elif [ -f "$THEME_DIR/$file" ]; then
        echo "  ✅ $key uses the root entrypoint $THEME_DIR/$file"
    else
        echo "  ❌ $key names '$file', but $THEME_DIR/$file does not exist (examples/root-$file)"
        FAILED=1
    fi
}
check_root_entrypoint "internal_server_error" "internal-server-error.500.twig" fail
check_root_entrypoint "maintenance" "maintenance.503.twig" fail

# -------------------------------------------------------------
# 2. Check Theme Template Files
# -------------------------------------------------------------
echo ""
echo "[2/5] Checking helper templates in $HELPER_DIR..."

if [ ! -d "$HELPER_DIR" ]; then
    echo "  ❌ Directory $HELPER_DIR does not exist!"
    echo "     Create directory and add helper templates."
    FAILED=1
else
    for TPL in "notfound.404.twig" "forbidden.403.twig" "internal-server-error.500.twig" "maintenance.503.twig" "_helper_template_with_master.twig" "_helper_template_without_master.twig"; do
        echo -n "  • $TPL: "
        if [ -f "$HELPER_DIR/$TPL" ]; then
            echo "FOUND"
        else
            echo "MISSING"
            FAILED=1
        fi
    done
fi

# -------------------------------------------------------------
# 3. Check SEO & Safety Rules
# -------------------------------------------------------------
echo ""
echo "[3/5] Checking SEO and robustness rules..."

# Rule: noindex, follow on error layouts
if [ -d "$HELPER_DIR" ]; then
    ROBOTS_COUNT=$(grep -rn "noindex" "$HELPER_DIR" 2>/dev/null | wc -l || true)
    if [ "$ROBOTS_COUNT" -gt 0 ]; then
        echo "  ✅ 'noindex' directive detected in helper templates (protects SEO ranking)"
    else
        echo "  ❌ No 'noindex' meta tag found in helper templates!"
        echo "     Error pages MUST declare <meta name=\"robots\" content=\"noindex, follow\">"
        FAILED=1
    fi

    # Rule: the 500 and 503 pages — and the standalone layout and scene they render — MUST NOT
    # query the database (SKILL.md section 5): a 500 is often a database failure, and maintenance
    # mode is on while the database is migrated or restored.
    for TPL in "internal-server-error.500.twig" "maintenance.503.twig" "_helper_template_without_master.twig" "_helper_scene.twig"; do
        [ -f "$HELPER_DIR/$TPL" ] || continue
        if has_db_lookup "$HELPER_DIR/$TPL"; then
            echo "  ❌ SAFETY VIOLATION: $TPL contains '{% setcontent %}' or menu_array()!"
            echo "     The 500 and 503 pages MUST NEVER query the database. With the database down,"
            echo "     the query throws and the error page itself turns into a white screen."
            FAILED=1
        else
            echo "  ✅ $TPL: zero database queries (setcontent, menu_array)"
        fi
    done

    # Rule: the 500 and 503 pages extend the standalone layout. The with-master layout renders the
    # header and footer containers (menu_array(), possibly setcontent), which would fail together
    # with the database.
    for TPL in "internal-server-error.500.twig" "maintenance.503.twig"; do
        [ -f "$HELPER_DIR/$TPL" ] || continue
        if grep -qE "extends[[:space:]]+['\"]helper-pages/_helper_template_without_master\.twig['\"]" "$HELPER_DIR/$TPL"; then
            echo "  ✅ $TPL extends the standalone layout (_helper_template_without_master.twig)"
        else
            echo "  ❌ SAFETY VIOLATION: $TPL must extend helper-pages/_helper_template_without_master.twig"
            echo "     (the with-master layout renders header/footer containers that may query the database)."
            FAILED=1
        fi
    done

    # Rule: the 503 page shows no contact details — it can be on without anyone noticing, and the
    # details would come from the database or go stale (SKILL.md section 5).
    if [ -f "$HELPER_DIR/maintenance.503.twig" ]; then
        if perl -0777 -ne 's/\{#.*?#\}//gs; exit(/(tel|mailto):/ ? 0 : 1)' "$HELPER_DIR/maintenance.503.twig"; then
            echo "  ⚠️  maintenance.503.twig links a phone number or e-mail address (tel: / mailto:)."
            echo "     The 503 page only says that the site is being worked on (SKILL.md section 5)."
            WARNINGS=$((WARNINGS+1))
        else
            echo "  ✅ maintenance.503.twig shows no contact details"
        fi
    fi
fi

# -------------------------------------------------------------
# 4. Check Tailwind Bundle Isolation
# -------------------------------------------------------------
echo ""
echo "[4/5] Checking Tailwind CSS bundle isolation..."

if [ -d "$HELPER_DIR" ]; then
    # Verify that scene styles are scoped inside _helper_scene_styles.twig
    if [ -f "$HELPER_DIR/_helper_scene_styles.twig" ] && grep -q "<style>" "$HELPER_DIR/_helper_scene_styles.twig"; then
        echo "  ✅ Scoped scene styles defined in _helper_scene_styles.twig (<style> tag present)"
    fi

    # Check for arbitrary one-off utilities that could bloat the main CSS bundle
    ARBITRARY_CLASSES=$(grep -rn -E "(class=\"[^\"]*(\b(text|bg|w|h|max-w|min-h|border)-\[[^\]]+\]|\bdark:)[^\"]*\")" "$HELPER_DIR" --exclude="_helper_scene_styles.twig" 2>/dev/null || true)
    if [ -n "$ARBITRARY_CLASSES" ]; then
        echo "  ⚠️  Advisory: Found arbitrary/variant classes in helper templates that may bloat main bundle:"
        echo "$ARBITRARY_CLASSES" | head -3 | sed 's/^/      /'
        echo "     Prefer using scoped classes (.helper-*) styled in _helper_scene_styles.twig."
        WARNINGS=$((WARNINGS+1))
    else
        echo "  ✅ Zero arbitrary one-off Tailwind utilities found in helper templates (clean markup)"
    fi
fi

# Check if Tailwind build config explicitly excludes helper-pages
TW_INPUT_CSS="$THEME_DIR/css/tailwind/index.css"
TW_CONFIG_JS="$THEME_DIR/tailwind.config.js"
if [ -f "$TW_INPUT_CSS" ]; then
    if grep -q "@source not.*helper-pages" "$TW_INPUT_CSS"; then
        echo "  ✅ Tailwind v4 explicitly excludes helper-pages from scanner (@source not active)"
    else
        echo "  ℹ️  Tip: Add '@source not \"../../helper-pages\";' to $TW_INPUT_CSS to strictly prevent"
        echo "     Tailwind from compiling helper-page classes into the app bundle."
    fi
elif [ -f "$TW_CONFIG_JS" ]; then
    if grep -q "helper-pages" "$TW_CONFIG_JS"; then
        echo "  ✅ Tailwind config includes helper-pages exclusion pattern"
    fi
fi

# -------------------------------------------------------------
# 5. Twig Syntax Linting
# -------------------------------------------------------------
echo ""
echo "[5/5] Validating Twig syntax..."
if [ -f "bin/console" ] && [ -d "$HELPER_DIR" ]; then
    if php bin/console lint:twig "$HELPER_DIR" > /dev/null 2>&1; then
        echo "  ✅ All helper Twig templates passed syntax linting."
    else
        echo "  ❌ Twig syntax linting FAILED:"
        php bin/console lint:twig "$HELPER_DIR" || true
        FAILED=1
    fi
else
    echo "  (Skipping console lint:twig — bin/console or directory not available)"
fi

echo ""
echo "=========================================================="
if [ "$FAILED" -gt 0 ]; then
    echo " Verification FAILED. Please resolve the errors highlighted above."
    echo "=========================================================="
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo " Verification PASSED with $WARNINGS advisory warnings."
    echo "=========================================================="
    exit 0
else
    echo " All helper and error pages are correctly configured and verified!"
    echo "=========================================================="
    exit 0
fi
