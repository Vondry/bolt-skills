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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../examples" && pwd)"

BOLT_CONFIG="config/bolt/config.yaml"
ACTIVE_THEME="default"
if [ -f "$BOLT_CONFIG" ]; then
    FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$FOUND_THEME" ]; then
        ACTIVE_THEME="$FOUND_THEME"
    fi
fi

THEME_DIR="public/theme/$ACTIVE_THEME"
if [ ! -d "$THEME_DIR" ]; then
    echo "ERROR: Theme directory '$THEME_DIR' not found."
    exit 1
fi

FORCE=0
PRODUCTS="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --products=*)
            PRODUCTS="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: ./scaffold.sh [--force] [--products=auto|yes|no]"
            exit 1
            ;;
    esac
done

# Product pages: auto = only when contenttypes.yaml defines a top-level `products:` ContentType.
if [ "$PRODUCTS" = "auto" ]; then
    if grep -qE "^products:" config/bolt/contenttypes.yaml 2>/dev/null; then
        PRODUCTS="yes"
    else
        PRODUCTS="no"
    fi
fi

echo "=========================================================="
echo " Bolt CMS Theme Templates Scaffolder"
echo " Project root: $BASE_DIR"
echo " Target Theme: $ACTIVE_THEME ($THEME_DIR)"
echo " Product pages: $PRODUCTS"
echo "=========================================================="

# Copy a file unless it exists. Files that still carry bolt-theme-init's placeholder
# marker are replaced; --force replaces everything.
copy_file() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && [ $FORCE -eq 0 ] && ! grep -q "bolt-theme-init:placeholder" "$dest"; then
        echo "  [skip]    $dest already exists."
    elif [ -f "$dest" ]; then
        cp "$src" "$dest"
        echo "  [replace] $dest"
    else
        cp "$src" "$dest"
        echo "  [create]  $dest"
    fi
}

echo "1. Scaffolding pure UI components (components/ui/)..."
for f in button badge picture card breadcrumbs pagination empty-state section-header; do
    copy_file "$EXAMPLES_DIR/components/ui/$f.twig" "$THEME_DIR/components/ui/$f.twig"
done

echo "2. Scaffolding smart containers (containers/)..."
copy_file "$EXAMPLES_DIR/containers/contact/_contact-section.twig" "$THEME_DIR/containers/contact/_contact-section.twig"
copy_file "$EXAMPLES_DIR/containers/contact/_contact-banner.twig" "$THEME_DIR/containers/contact/_contact-banner.twig"

echo "3. Scaffolding page orchestrators (pages/)..."
copy_file "$EXAMPLES_DIR/pages/homepage/homepage.twig" "$THEME_DIR/pages/homepage/homepage.twig"
copy_file "$EXAMPLES_DIR/pages/homepage/components/hero.twig" "$THEME_DIR/pages/homepage/components/hero.twig"
copy_file "$EXAMPLES_DIR/pages/homepage/components/hero-metrics.twig" "$THEME_DIR/pages/homepage/components/hero-metrics.twig"

if [ "$PRODUCTS" = "yes" ]; then
    copy_file "$EXAMPLES_DIR/containers/products/_featured-products.twig" "$THEME_DIR/containers/products/_featured-products.twig"
    copy_file "$EXAMPLES_DIR/pages/product/product.twig" "$THEME_DIR/pages/product/product.twig"
    copy_file "$EXAMPLES_DIR/pages/product/product.record.twig" "$THEME_DIR/pages/product/product.record.twig"
    copy_file "$EXAMPLES_DIR/pages/product/components/spec-table.twig" "$THEME_DIR/pages/product/components/spec-table.twig"
    copy_file "$EXAMPLES_DIR/pages/product/components/stock-badge.twig" "$THEME_DIR/pages/product/components/stock-badge.twig"
    # Thin root entrypoints bound by `listing_template: product.twig` / `record_template: product.record.twig`
    for entry in product product.record; do
        if [ ! -f "$THEME_DIR/$entry.twig" ] || [ $FORCE -eq 1 ]; then
            printf "{%% extends 'pages/product/%s.twig' %%}\n" "$entry" > "$THEME_DIR/$entry.twig"
            echo "  [create]  $THEME_DIR/$entry.twig"
        else
            echo "  [skip]    $THEME_DIR/$entry.twig already exists."
        fi
    done
else
    echo "  (no products ContentType: product pages and the featured-products container skipped;"
    echo "   the homepage include of containers/products/_featured-products.twig is ignored when missing)"
fi

# Root homepage entrypoint (bolt-theme-init writes the same line)
if [ ! -f "$THEME_DIR/index.twig" ]; then
    printf "{%% extends 'pages/homepage/homepage.twig' %%}\n" > "$THEME_DIR/index.twig"
    echo "  [create]  $THEME_DIR/index.twig"
fi

# Search: Bolt serves /search and /{_locale}/search on every site, so every theme gets the page.
echo "4. Scaffolding the search results page (pages/search/)..."
copy_file "$EXAMPLES_DIR/pages/search/search.twig" "$THEME_DIR/pages/search/search.twig"
copy_file "$EXAMPLES_DIR/pages/search/components/search-form.twig" "$THEME_DIR/pages/search/components/search-form.twig"
copy_file "$EXAMPLES_DIR/pages/search/components/search-result.twig" "$THEME_DIR/pages/search/components/search-result.twig"
# Thin root entrypoint matching Bolt's default `search_results_template: search.twig`
if [ ! -f "$THEME_DIR/search.twig" ] || [ $FORCE -eq 1 ]; then
    printf "{%% extends 'pages/search/search.twig' %%}\n" > "$THEME_DIR/search.twig"
    echo "  [create]  $THEME_DIR/search.twig"
else
    echo "  [skip]    $THEME_DIR/search.twig already exists."
fi
SEARCH_TEMPLATE=$(grep -E "^search_results_template:" "$BOLT_CONFIG" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -n "$SEARCH_TEMPLATE" ] && [ "$SEARCH_TEMPLATE" != "search.twig" ] && [ ! -f "$THEME_DIR/$SEARCH_TEMPLATE" ]; then
    echo "  [warn]    $BOLT_CONFIG sets search_results_template: $SEARCH_TEMPLATE, which does not exist —"
    echo "            set it to search.twig."
fi

echo "=========================================================="
echo " Done! Next:"
echo "  - Merge the translation units into every catalog:"
echo "      php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "      php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf translations/messages.en.xlf"
echo "  - Build one orchestrator per routable ContentType: pages/<name>/<name>.twig (+ .record.twig)"
echo "  - Run scripts/verify.sh to test architecture compliance."
echo "=========================================================="
