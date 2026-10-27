#!/usr/bin/env bash
set -e

# The skill's examples/, to compare the project's canonical partials with (section 1.6).
EXAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../examples" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo " Bolt CMS Essential Extensions Verification"
echo " (AppoloDev/bolt-seo, bolt-sitemap, bolt-llms-txt)"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# Determine active theme from config/bolt/config.yaml
THEME_NAME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
if [ -z "$THEME_NAME" ]; then
    THEME_NAME="default"
fi
THEME_DIR="public/theme/$THEME_NAME"
EXT_THEME_DIR="$THEME_DIR/extensions"

echo "Active theme detected: '$THEME_NAME' ($THEME_DIR)"
echo ""

# -------------------------------------------------------------
# 1. Check Composer Dependencies
# -------------------------------------------------------------
echo "[1/7] Checking installed packages (vendor/composer/installed.json)..."
for PKG in "appolodev/bolt-seo" "tomvondracek/bolt-sitemap" "tomvondracek/bolt-llms-txt"; do
    echo -n "  • $PKG: "
    # The installed version, not the constraint in composer.json: a required package that was
    # never installed (or was removed from vendor/) must not pass.
    VERSION=$(php -r '$i = json_decode((string) @file_get_contents("vendor/composer/installed.json"), true);
        foreach ($i["packages"] ?? $i ?? [] as $p) { if (($p["name"] ?? "") === $argv[1]) { echo $p["pretty_version"] ?? $p["version"]; } }' "$PKG" 2>/dev/null || true)
    if [ -n "$VERSION" ]; then
        echo "INSTALLED ($VERSION)"
    elif grep -q "\"$PKG\"" composer.json; then
        echo "MISSING from vendor/ (in composer.json, run: composer install)"
        FAILED=1
    else
        echo "MISSING"
        echo "    Run: composer require $PKG"
        FAILED=1
    fi
done

# bolt/sitemap-extension also serves /sitemap.xml; tomvondracek/bolt-sitemap replaces it (section 2.6).
OLD_SITEMAP=$(php -r '$i = json_decode((string) @file_get_contents("vendor/composer/installed.json"), true);
    foreach ($i["packages"] ?? $i ?? [] as $p) { if (($p["name"] ?? "") === "bolt/sitemap-extension") { echo $p["pretty_version"] ?? $p["version"]; } }' 2>/dev/null || true)
if [ -n "$OLD_SITEMAP" ]; then
    echo "  ❌ bolt/sitemap-extension ($OLD_SITEMAP) is still installed — run: composer remove bolt/sitemap-extension (section 2.6)"
    FAILED=1
fi

# -------------------------------------------------------------
# 2. Check Extension Configuration Files
# -------------------------------------------------------------
echo ""
echo "[2/7] Checking extension configuration files..."

# SEO config
echo -n "  • config/extensions/appolo-boltseo.yaml: "
if [ -f "config/extensions/appolo-boltseo.yaml" ]; then
    echo "FOUND"
    # Never read by the extension; bolt-seo 2.3 removed them from its config (section 1.3).
    if grep -qE '^meta_robots:' config/extensions/appolo-boltseo.yaml; then
        echo "    ⚠️  Dead key 'meta_robots' — remove it; the robots default is 'default.robots' (section 1.3)"
        WARNINGS=$((WARNINGS+1))
    fi
    if grep -qE '^#?[[:space:]]*allow:' config/extensions/appolo-boltseo.yaml; then
        echo "    ⚠️  Dead 'allow:' block (also commented out) — remove it (section 1.3)"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config)"
    FAILED=1
fi

# Sitemap config
SITEMAP_CONFIG="config/extensions/tomvondracek-sitemap.yaml"
echo -n "  • $SITEMAP_CONFIG: "
if [ -f "$SITEMAP_CONFIG" ]; then
    echo "FOUND"
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config, then section 2.3)"
    FAILED=1
fi
if [ -f "config/extensions/bolt-sitemapextension.yaml" ]; then
    echo "    ⚠️  Leftover config/extensions/bolt-sitemapextension.yaml of bolt/sitemap-extension — delete it (section 2.6)"
    WARNINGS=$((WARNINGS+1))
fi

# llms.txt config
echo -n "  • config/extensions/tomvondracek-llmstxt.yaml: "
if [ -f "config/extensions/tomvondracek-llmstxt.yaml" ]; then
    echo "FOUND"
    LLMS_LOCALE=$(grep -E "^locale:" config/extensions/tomvondracek-llmstxt.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    APP_LOCALES=$(grep -E "^[[:space:]]*app_locales:" config/services.yaml | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    if [ "$LLMS_LOCALE" = "en" ]; then
        echo "    ✅ locale is set to 'en' (AI crawlers read English best)"
    elif [[ "|$APP_LOCALES|" == *"|en|"* ]]; then
        echo "    ⚠️  Advisory: locale is '${LLMS_LOCALE:-default}' although the site has English — set locale: en"
        WARNINGS=$((WARNINGS+1))
    else
        echo "    ✅ locale '${LLMS_LOCALE:-default}' (the site has no English)"
    fi
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config)"
    FAILED=1
fi

# -------------------------------------------------------------
# 3. Check Symfony Package & Route Configurations
# -------------------------------------------------------------
echo ""
echo "[3/7] Checking package and route recipes..."

# Bolt SEO package config
echo -n "  • config/packages/extension_bolt-seo.yaml: "
if [ -f "config/packages/extension_bolt-seo.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for Appolo SEO doctrine mappings and translations)"
    FAILED=1
fi

# Sitemap package and route config
echo -n "  • config/packages/extension_bolt-sitemap.yaml: "
if [ -f "config/packages/extension_bolt-sitemap.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for the sitemap cache invalidation and Twig namespace)"
    FAILED=1
fi
echo -n "  • config/routes/extension_bolt-sitemap.yaml: "
if [ -f "config/routes/extension_bolt-sitemap.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for the /sitemap.xml route registration)"
    FAILED=1
fi

# llms.txt package config
echo -n "  • config/packages/extension_bolt-llms-txt.yaml: "
if [ -f "config/packages/extension_bolt-llms-txt.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for llms-txt doctrine listener and Twig namespace)"
    FAILED=1
fi

# llms.txt route config
echo -n "  • config/routes/extension_bolt-llms-txt.yaml: "
if [ -f "config/routes/extension_bolt-llms-txt.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for /llms.txt route registration)"
    FAILED=1
fi

# -------------------------------------------------------------
# 4. Check ContentTypes Reusable SEO Field
# -------------------------------------------------------------
echo ""
echo "[4/7] Checking ContentTypes SEO schema integration..."
CT_FILE="config/bolt/contenttypes.yaml"
if [ ! -f "$CT_FILE" ]; then
    echo "  ❌ config/bolt/contenttypes.yaml not found!"
    FAILED=1
else
    SEO_FIELD_COUNT=$(grep -c "type: seo" "$CT_FILE" || true)
    if [ "$SEO_FIELD_COUNT" -gt 0 ]; then
        echo "  ✅ 'type: seo' found ($SEO_FIELD_COUNT occurrences in $CT_FILE)"
    else
        echo "  ❌ 'type: seo' is NOT defined in $CT_FILE!"
        echo "     Define 'seo_field: &seo_field' under __nodes and merge with '<<: [ *common_fields, *seo_field ]'."
        FAILED=1
    fi

    # Check for __nodes anchor best practice
    if grep -q "seo_field:" "$CT_FILE"; then
        echo "  ✅ Reusable 'seo_field: &seo_field' anchor present under __nodes"
    else
        echo "  ⚠️  Advisory: Reusable anchor 'seo_field: &seo_field' not explicitly named in __nodes."
        WARNINGS=$((WARNINGS+1))
    fi
fi

# -------------------------------------------------------------
# 5. Check Theme SEO Integration
# -------------------------------------------------------------
echo ""
echo "[5/7] Checking Theme SEO integration in templates..."
THEME_SEO_FOUND=0
if [ -d "$THEME_DIR" ]; then
    if grep -rq "seo.metatags()" "$THEME_DIR" 2>/dev/null || grep -rq "@seo/_metatags.html.twig" "$THEME_DIR" 2>/dev/null; then
        THEME_SEO_FOUND=1
    fi
fi

if [ "$THEME_SEO_FOUND" -eq 1 ]; then
    echo "  ✅ SEO tags block found in theme templates ('{{ seo.metatags() }}' or '@seo/_metatags.html.twig')"
else
    echo "  ⚠️  No '{{ seo.metatags() }}' call detected in $THEME_DIR."
    echo "     Add the following block to your theme's base layout <head>:"
    echo "     {% block seo %}"
    echo "         <title>{{ seo.title() }}</title>"
    echo "         {{ seo.metatags() }}"
    echo "     {% endblock seo %}"
    WARNINGS=$((WARNINGS+1))
fi

# -------------------------------------------------------------
# 6. Check the sitemap's static pages, robots.txt & llms.txt in Theme Extensions
# -------------------------------------------------------------
echo ""
echo "[6/7] Checking the sitemap's static pages and the theme extensions folder ($EXT_THEME_DIR)..."

# The old bolt/sitemap-extension override is not read any more (section 2.6).
for OLD_OVERRIDE in "$EXT_THEME_DIR/sitemap.xml.twig" "$EXT_THEME_DIR/_sitemap.xml.twig"; do
    if [ -f "$OLD_OVERRIDE" ]; then
        echo "  ⚠️  Leftover sitemap override $OLD_OVERRIDE of bolt/sitemap-extension — delete it; bolt-sitemap needs no theme template (section 2.6)"
        WARNINGS=$((WARNINGS+1))
    fi
done

# Static pages are in the sitemap only through their TemplateController routes (section 2.4).
if [ -d "$THEME_DIR/static-pages" ]; then
    if grep -qE '^static_routes:[[:space:]]*false' "$SITEMAP_CONFIG" 2>/dev/null; then
        echo "  ⚠️  static_routes: false in $SITEMAP_CONFIG — the static pages are not in the sitemap (section 2.4)"
        WARNINGS=$((WARNINGS+1))
    fi

    APP_LOCALES=$(grep -E "^[[:space:]]*app_locales:" config/services.yaml | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    STATIC_REPORT=$(php "$SCRIPT_DIR/static-pages.php" "$THEME_DIR" "$APP_LOCALES" "$SITEMAP_CONFIG" 2>&1 || true)
    if [ -z "$STATIC_REPORT" ]; then
        echo "  ✅ No static pages in $THEME_DIR/static-pages"
    fi
    while IFS='|' read -r LEVEL MESSAGE; do
        case "$LEVEL" in
            OK)   echo "  ✅ $MESSAGE" ;;
            WARN) echo "  ⚠️  $MESSAGE"; WARNINGS=$((WARNINGS+1)) ;;
            FAIL) echo "  ❌ $MESSAGE"; FAILED=1 ;;
            "")   ;;
            *)    echo "  ⚠️  $LEVEL${MESSAGE:+|$MESSAGE}"; WARNINGS=$((WARNINGS+1)) ;;
        esac
    done <<< "$STATIC_REPORT"
fi

# robots.txt names the sitemap (section 2.5), so crawlers find it without Search Console.
if [ -f "public/robots.txt" ]; then
    if grep -qiE '^\s*Sitemap:\s*https?://[^ ]+/sitemap\.xml' public/robots.txt; then
        echo "  ✅ public/robots.txt names the sitemap ($(grep -iE '^\s*Sitemap:' public/robots.txt | head -n 1 | tr -d '\r'))"
    else
        echo "  ⚠️  public/robots.txt has no 'Sitemap: https://<domain>/sitemap.xml' line (section 2.5)"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "  ⚠️  public/robots.txt is missing — add one with a 'Sitemap: https://<domain>/sitemap.xml' line (section 2.5)"
    WARNINGS=$((WARNINGS+1))
fi
if [ -f "public/sitemap.xml" ]; then
    echo "  ❌ A static public/sitemap.xml is served instead of the extension's — delete it (section 2.5)"
    FAILED=1
fi

# llms.txt check
LLMS_FILE="$EXT_THEME_DIR/llms.txt.twig"
if [ -f "$LLMS_FILE" ]; then
    echo "  ✅ llms.txt template found ($LLMS_FILE)"
    # Check llmstxt.org formatting rules
    if grep -q "^# " "$LLMS_FILE" && grep -q "^> " "$LLMS_FILE"; then
        echo "  ✅ llmstxt.org layout verified (H1 header and summary blockquote present)"
    else
        echo "  ⚠️  $LLMS_FILE should start with H1 ('# Title') followed by blockquote ('> Summary') per https://llmstxt.org/"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "  ❌ llms.txt template MISSING in $EXT_THEME_DIR"
    echo "     Copy 'llms.txt.twig' from skill examples to '$LLMS_FILE'"
    FAILED=1
fi

# -------------------------------------------------------------
# 7. Check the canonical URL override (bolt/core PR #3735 workaround)
# -------------------------------------------------------------
echo ""
echo "[7/7] Checking the canonical URL override (section 1.6, needed until bolt/core#3735 is released)..."
BOLT_CORE_VERSION=$(php -r '$i = json_decode((string) @file_get_contents("vendor/composer/installed.json"), true);
    foreach ($i["packages"] ?? $i ?? [] as $p) { if (($p["name"] ?? "") === "bolt/core") { echo $p["pretty_version"] ?? $p["version"]; } }' 2>/dev/null || true)
echo "  • bolt/core ${BOLT_CORE_VERSION:-not installed} — remove the override only on a release that includes https://github.com/bolt/core/pull/3735"

for PARTIAL in _canonical.twig _canonical.macros.twig _seo_metatags.twig; do
    PARTIAL_FILE="$THEME_DIR/partials/$PARTIAL"
    if [ ! -f "$PARTIAL_FILE" ]; then
        echo "  ❌ $PARTIAL_FILE is MISSING — copy examples/$PARTIAL from the skill"
        FAILED=1
    elif cmp -s "$PARTIAL_FILE" "$EXAMPLES_DIR/$PARTIAL"; then
        echo "  ✅ $PARTIAL_FILE matches the skill example"
    else
        echo "  ⚠️  $PARTIAL_FILE differs from the skill example — copy examples/$PARTIAL again (the copies must be identical)"
        WARNINGS=$((WARNINGS+1))
    fi
done

if grep -qE "^canonical_template:[[:space:]]*['\"]?partials/_canonical\.twig['\"]?[[:space:]]*(#.*)?$" config/bolt/config.yaml 2>/dev/null; then
    echo "  ✅ config/bolt/config.yaml: canonical_template is 'partials/_canonical.twig'"
else
    echo "  ❌ config/bolt/config.yaml: set canonical_template: 'partials/_canonical.twig'"
    FAILED=1
fi

if grep -qE '^templates:' config/extensions/appolo-boltseo.yaml 2>/dev/null \
    && grep -qE "^[[:space:]]+meta:[[:space:]]*['\"]?partials/_seo_metatags\.twig" config/extensions/appolo-boltseo.yaml; then
    echo "  ✅ config/extensions/appolo-boltseo.yaml: templates.meta is partials/_seo_metatags.twig"
else
    echo "  ❌ config/extensions/appolo-boltseo.yaml: set templates.meta: partials/_seo_metatags.twig"
    FAILED=1
fi

# Pages that include the meta tags themselves must pass the canonical, not the request URL (section 1.5).
REQUEST_URI_FILES=$(grep -rlE 'canonical:[[:space:]]*app\.request\.(uri|requestUri)' "$THEME_DIR" --include='*.twig' 2>/dev/null | grep -v node_modules || true)
if [ -n "$REQUEST_URI_FILES" ]; then
    echo "  ⚠️  These templates pass 'canonical: app.request.uri' — use 'canonical: seo.canonical()' (section 1.5):"
    echo "$REQUEST_URI_FILES" | sed 's/^/       /'
    WARNINGS=$((WARNINGS+1))
else
    echo "  ✅ No template passes the request URL as the canonical"
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
    echo " All essential extensions and override templates are correctly configured!"
    echo "=========================================================="
    exit 0
fi
