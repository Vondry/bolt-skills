#!/usr/bin/env bash
set -e

# Scaffolding script for new Bolt CMS themes (Component / Container / Page architecture).
# Usage: ./scaffold.sh <theme-name> [project-root] [--force]
#
# Creates the theme foundation: folder structure of the Integration Contract (WORKFLOWS.md),
# build tooling, TypeScript modules, the master layout shell, macros, theme.yaml, generic
# fallback templates and a homepage placeholder. Existing files are kept unless --force is given.
#
# Not created here (owned by other skills):
#   components/nav/*, containers/header/_menu.twig, containers/footer/_footer.twig,
#   components/brand/logo.twig                              -> bolt-menu (scaffold.sh --templates)
#   components/ui/*, containers/contact/*, pages/homepage/*,
#   pages/product/*                                          -> bolt-theme-templates (scaffold.sh)
#   design tokens in css/tailwind/index.css                  -> bolt-tailwind-theme

THEME_NAME=""
PROJECT_ROOT=""
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE=1
            ;;
        *)
            if [ -z "$THEME_NAME" ]; then
                THEME_NAME="$arg"
            elif [ -z "$PROJECT_ROOT" ]; then
                PROJECT_ROOT="$arg"
            fi
            ;;
    esac
done

if [ -z "$THEME_NAME" ]; then
    echo "Usage: $0 <theme-name> [project-root] [--force]"
    echo "Example: $0 mytheme"
    exit 1
fi

# Detect project root if not provided
if [ -z "$PROJECT_ROOT" ]; then
    if [ -f "./config/services.yaml" ]; then
        PROJECT_ROOT="$(pwd)"
    else
        DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        while [ "$DIR" != "/" ]; do
            if [ -f "$DIR/config/services.yaml" ]; then
                PROJECT_ROOT="$DIR"
                break
            fi
            DIR="$(dirname "$DIR")"
        done
    fi
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -f "$PROJECT_ROOT/config/services.yaml" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi

# The name becomes a folder, the `theme:` value in config.yaml and a sed replacement: keep it to
# lower-case letters, digits and hyphens.
if ! [[ "$THEME_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: theme name '$THEME_NAME' — use lower-case letters, digits and hyphens (e.g. acme-2026)."
    exit 1
fi

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLES_DIR="$SKILL_DIR/examples"
THEME_DIR="$PROJECT_ROOT/public/theme/$THEME_NAME"

echo "=========================================================="
echo " Scaffolding Bolt CMS Theme: $THEME_NAME"
echo " Project root: $PROJECT_ROOT"
echo " Target dir:   $THEME_DIR"
[ $FORCE -eq 1 ] && echo " Mode:         --force (existing files are overwritten)"
echo "=========================================================="

# Copy a file unless the target exists (or --force). Optional third argument: sed
# expression applied while copying (used for THEME_NAME placeholders).
copy_file() {
    local src="$1"
    local dest="$2"
    local sed_expr="${3:-}"
    if [ -f "$dest" ] && [ $FORCE -eq 0 ]; then
        echo "  [skip]   ${dest#"$PROJECT_ROOT"/} already exists"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -n "$sed_expr" ]; then
        sed "$sed_expr" "$src" > "$dest"
    else
        cp "$src" "$dest"
    fi
    echo "  [create] ${dest#"$PROJECT_ROOT"/}"
}

# Write a one-line file unless it exists (or --force).
write_file() {
    local dest="$1"
    local content="$2"
    if [ -f "$dest" ] && [ $FORCE -eq 0 ]; then
        echo "  [skip]   ${dest#"$PROJECT_ROOT"/} already exists"
        return
    fi
    printf '%s\n' "$content" > "$dest"
    echo "  [create] ${dest#"$PROJECT_ROOT"/}"
}

# 1. Create directory hierarchy (Integration Contract)
echo "--> Creating directories..."
for d in \
    partials \
    components/ui components/nav components/brand \
    containers/header containers/footer containers/contact \
    pages/homepage/components \
    static-pages helper-pages extensions \
    css/tailwind css/article css/fonts \
    js/src img; do
    mkdir -p "$THEME_DIR/$d"
done

# 2. Tooling: package.json, TypeScript, Rollup, Tailwind v4
echo "--> Setting up package.json, TypeScript and Tailwind v4..."
copy_file "$EXAMPLES_DIR/package.json" "$THEME_DIR/package.json" "s/THEME_NAME/$THEME_NAME/g"
copy_file "$EXAMPLES_DIR/postcss.config.mjs" "$THEME_DIR/postcss.config.mjs"
copy_file "$EXAMPLES_DIR/rollup.config.js" "$THEME_DIR/rollup.config.js"
copy_file "$EXAMPLES_DIR/tsconfig.json" "$THEME_DIR/tsconfig.json"
copy_file "$EXAMPLES_DIR/theme.yaml" "$THEME_DIR/theme.yaml" "s/THEME_NAME/$THEME_NAME/g"
copy_file "$EXAMPLES_DIR/index.css" "$THEME_DIR/css/tailwind/index.css"

# 3. Shared TypeScript modules & vendor assets
echo "--> Setting up TypeScript modules (auto-scroll, menu, locale-switcher, photoswipe) and vendor assets..."
for ts in "$EXAMPLES_DIR/js/src/"*.ts; do
    copy_file "$ts" "$THEME_DIR/js/src/$(basename "$ts")"
done
copy_file "$EXAMPLES_DIR/js/splide_4.1.2.min.js" "$THEME_DIR/js/splide_4.1.2.min.js"
copy_file "$EXAMPLES_DIR/css/splide_4.1.2.min.css" "$THEME_DIR/css/splide_4.1.2.min.css"
for css in "$EXAMPLES_DIR/css/article/"*.css; do
    copy_file "$css" "$THEME_DIR/css/article/$(basename "$css")"
done

# 4. Layout shell, macros, fallbacks and homepage placeholder
echo "--> Creating layout shell and entrypoints..."
copy_file "$EXAMPLES_DIR/_master.twig" "$THEME_DIR/partials/_master.twig"
copy_file "$EXAMPLES_DIR/macros.twig" "$THEME_DIR/macros.twig"
copy_file "$EXAMPLES_DIR/record.twig" "$THEME_DIR/record.twig"
copy_file "$EXAMPLES_DIR/listing.twig" "$THEME_DIR/listing.twig"
copy_file "$EXAMPLES_DIR/pages/homepage/homepage.twig" "$THEME_DIR/pages/homepage/homepage.twig"
write_file "$THEME_DIR/index.twig" "{% extends 'pages/homepage/homepage.twig' %}"

# 5. Link theme in config/bolt/config.yaml
BOLT_CONFIG="$PROJECT_ROOT/config/bolt/config.yaml"
if [ -f "$BOLT_CONFIG" ]; then
    echo "--> Linking theme in config/bolt/config.yaml..."
    if grep -q "^theme:" "$BOLT_CONFIG"; then
        sed -i.bak -E "s/^theme:.*/theme: $THEME_NAME/" "$BOLT_CONFIG" && rm -f "$BOLT_CONFIG.bak"
    else
        echo "theme: $THEME_NAME" >> "$BOLT_CONFIG"
    fi
fi

# 6. Install, update and build (npm)
if command -v npm &>/dev/null; then
    echo "--> Installing theme npm dependencies..."
    (cd "$THEME_DIR" && npm install)

    echo "--> Updating theme dependencies (npm update --save)..."
    (cd "$THEME_DIR" && npm update --save)

    echo "--> Building production assets (Tailwind v4 & Rollup)..."
    (cd "$THEME_DIR" && npm run prod)

    echo "--> Verifying compiled assets exist and are non-empty..."
    if [ ! -s "$THEME_DIR/css/index.css" ]; then
        echo "ERROR: $THEME_DIR/css/index.css was not created or is empty!"
        exit 1
    fi
    if [ ! -s "$THEME_DIR/js/app.js" ]; then
        echo "ERROR: $THEME_DIR/js/app.js was not created or is empty!"
        exit 1
    fi
    echo "    Assets build verified: css/index.css ($(wc -c < "$THEME_DIR/css/index.css" | tr -d ' ') bytes), js/app.js ($(wc -c < "$THEME_DIR/js/app.js" | tr -d ' ') bytes)"
else
    echo "WARNING: npm not found in PATH. Please run 'npm install && npm update --save && npm run prod' in $THEME_DIR"
fi

# 7. Clear Bolt cache if php is present
if command -v php &>/dev/null && [ -f "$PROJECT_ROOT/bin/console" ]; then
    echo "--> Clearing Bolt CMS cache..."
    php "$PROJECT_ROOT/bin/console" cache:clear || true
fi

echo "=========================================================="
echo " SUCCESS: Theme '$THEME_NAME' initialized."
echo " Directory: $THEME_DIR"
echo " Linked in: $BOLT_CONFIG"
echo ""
echo " Next steps (WORKFLOWS.md, Phase 4-6):"
echo "  - Merge translation units:"
echo "      php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "      (and translations.en.xlf for each secondary locale)"
echo "  - Header/footer + nav components: bolt-menu/scripts/scaffold.sh --profile=<p> --templates --force"
echo "  - Design tokens: bolt-tailwind-theme"
echo "  - UI components and pages: bolt-theme-templates/scripts/scaffold.sh"
echo "=========================================================="
