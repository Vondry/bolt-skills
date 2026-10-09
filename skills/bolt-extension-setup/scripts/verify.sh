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
echo " Bolt CMS Essential Extensions Verification"
echo " (AppoloDev/bolt-seo, bolt/sitemap-extension, bolt-llms-txt)"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# Determine active theme from config/bolt/config.yaml
THEME_NAME=$(grep -E "^\s*theme:" config/bolt/config.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
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
echo "[1/6] Checking composer.json dependencies..."
for PKG in "appolodev/bolt-seo" "bolt/sitemap-extension" "tomvondracek/bolt-llms-txt"; do
    echo -n "  • $PKG: "
    if grep -q "\"$PKG\"" composer.json; then
        VERSION=$(grep "\"$PKG\"" composer.json | head -1 | awk -F: '{print $2}' | tr -d '", ')
        echo "INSTALLED ($VERSION)"
    else
        echo "MISSING"
        echo "    Run: composer require $PKG"
        FAILED=1
    fi
done

# -------------------------------------------------------------
# 2. Check Extension Configuration Files
# -------------------------------------------------------------
echo ""
echo "[2/6] Checking extension configuration files..."

# SEO config
echo -n "  • config/extensions/appolo-boltseo.yaml: "
if [ -f "config/extensions/appolo-boltseo.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config)"
    FAILED=1
fi

# Sitemap config
echo -n "  • config/extensions/bolt-sitemapextension.yaml: "
if [ -f "config/extensions/bolt-sitemapextension.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config)"
    FAILED=1
fi

# llms.txt config
echo -n "  • config/extensions/tomvondracek-llmstxt.yaml: "
if [ -f "config/extensions/tomvondracek-llmstxt.yaml" ]; then
    echo "FOUND"
    LLMS_LOCALE=$(grep -E "^\s*locale:" config/extensions/tomvondracek-llmstxt.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    if [ "$LLMS_LOCALE" = "en" ]; then
        echo "    ✅ locale is set to 'en' (standard for AI models and crawlers)"
    else
        echo "    ⚠️  Advisory: locale is set to '$LLMS_LOCALE' (standard practice: 'en' for AI crawlers)"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "MISSING (Run: php bin/console extensions:configure --with-config)"
    FAILED=1
fi

# -------------------------------------------------------------
# 3. Check Symfony Package & Route Configurations
# -------------------------------------------------------------
echo ""
echo "[3/6] Checking package and route recipes..."

# Bolt SEO package config
echo -n "  • config/packages/extension_bolt-seo.yaml: "
if [ -f "config/packages/extension_bolt-seo.yaml" ]; then
    echo "FOUND"
else
    echo "MISSING (Required for Appolo SEO doctrine mappings and translations)"
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
echo "[4/6] Checking ContentTypes SEO schema integration..."
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
echo "[5/6] Checking Theme SEO integration in templates..."
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
# 6. Check Sitemap Override & llms.txt in Theme Extensions
# -------------------------------------------------------------
echo ""
echo "[6/6] Checking theme extensions folder ($EXT_THEME_DIR)..."

# Sitemap override check
SITEMAP_FILE=""
if [ -f "$EXT_THEME_DIR/sitemap.xml.twig" ]; then
    SITEMAP_FILE="$EXT_THEME_DIR/sitemap.xml.twig"
elif [ -f "$EXT_THEME_DIR/_sitemap.xml.twig" ]; then
    SITEMAP_FILE="$EXT_THEME_DIR/_sitemap.xml.twig"
fi

if [ -n "$SITEMAP_FILE" ]; then
    echo "  ✅ Sitemap template override found ($SITEMAP_FILE)"
    # Check if the singleton slug stripping logic is included
    if grep -q "record.slug" "$SITEMAP_FILE" && grep -q "isSingleton" "$SITEMAP_FILE"; then
        echo "  ✅ Singleton slug fix logic is present (PR #5 workaround active)"
    else
        echo "  ⚠️  Sitemap override file exists but may lack singleton slug stripping logic."
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "  ❌ Sitemap template override MISSING in $EXT_THEME_DIR (needed until bolt/sitemap-extension#5 is merged)"
    echo "     Copy 'sitemap.xml.twig' from skill examples to '$EXT_THEME_DIR/sitemap.xml.twig'"
    echo "     and set 'xml: \"@theme/extensions/sitemap.xml.twig\"' in config/extensions/bolt-sitemapextension.yaml."
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
