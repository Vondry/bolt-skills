#!/usr/bin/env bash
set -e

# Scaffolding script for Bolt runtime extensions
# Usage: ./scaffold.sh [project-root] [--force]
# Existing src/*Extension.php files are kept unless --force is given.

PROJECT_ROOT=""
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) PROJECT_ROOT="$arg" ;;
    esac
done

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

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLES_DIR="$SKILL_DIR/examples"

echo "=========================================================="
echo " Scaffolding Bolt Runtime Extensions"
echo " Project root: $PROJECT_ROOT"
echo "=========================================================="

# 1. Copy PHP extensions to src/
echo "--> Installing PHP extensions to src/..."
mkdir -p "$PROJECT_ROOT/src"
for ext in LocaleLinkExtension ImageDimensionsExtension FileSizeExtension; do
    if [ -f "$PROJECT_ROOT/src/$ext.php" ] && [ $FORCE -eq 0 ]; then
        echo "    [skip]   src/$ext.php already exists (use --force to overwrite)"
    else
        cp "$EXAMPLES_DIR/$ext.php" "$PROJECT_ROOT/src/$ext.php"
        echo "    [create] src/$ext.php"
    fi
done

# 2. Check and configure config/services.yaml
SERVICES_FILE="$PROJECT_ROOT/config/services.yaml"
echo "--> Updating $SERVICES_FILE..."

# Ensure $appLocales is configured in LocaleLinkExtension service definition
if ! grep -q "App\\\\LocaleLinkExtension:" "$SERVICES_FILE"; then
    echo "    Adding App\\LocaleLinkExtension service definition..."
    cat << 'EOF' >> "$SERVICES_FILE"

  App\LocaleLinkExtension:
    arguments:
      $appLocales: '%app_locales%'
      $defaultLocale: '%locale%'
    tags: [ 'twig.extension' ]
EOF
fi

# Ensure app_locales parameter is defined
if ! grep -q "app_locales:" "$SERVICES_FILE"; then
    echo "    Adding app_locales parameter..."
    sed -i.bak -E 's/parameters:/parameters:\n  app_locales: cs|en/' "$SERVICES_FILE" && rm -f "$SERVICES_FILE.bak"
fi

# 3. Syntax check PHP files
echo "--> Verifying PHP syntax..."
php -l "$PROJECT_ROOT/src/LocaleLinkExtension.php"
php -l "$PROJECT_ROOT/src/ImageDimensionsExtension.php"
php -l "$PROJECT_ROOT/src/FileSizeExtension.php"

# 4. Clear cache if console is available
if [ -f "$PROJECT_ROOT/bin/console" ]; then
    echo "--> Clearing Symfony/Bolt cache..."
    php "$PROJECT_ROOT/bin/console" cache:clear || true
fi

echo "=========================================================="
echo " SUCCESS: Runtime extensions successfully installed!"
echo " Extensions:"
echo "   - src/LocaleLinkExtension.php (locale_link() function)"
echo "   - src/ImageDimensionsExtension.php (image_dimensions() function)"
echo "   - src/FileSizeExtension.php (file_size & format_bytes filters)"
echo "=========================================================="
