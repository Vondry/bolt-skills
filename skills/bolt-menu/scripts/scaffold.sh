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

MENU_FILE="config/bolt/menu.yaml"
PROFILE="auto"
FORCE=0
COPY_TEMPLATES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile=*)
            PROFILE="${1#*=}"
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --templates)
            COPY_TEMPLATES=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: ./scaffold.sh [--profile=landing|catalog|conditional|auto] [--templates] [--force]"
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo " Bolt CMS Menu Scaffolder"
echo " Project root: $BASE_DIR"
echo " Profile:      $PROFILE"
echo " Target file:  $MENU_FILE"
echo "=========================================================="

if [ -f "$MENU_FILE" ] && [ $FORCE -eq 0 ]; then
    echo "File $MENU_FILE already exists. Use --force to overwrite."
    exit 0
fi

mkdir -p "config/bolt"

# Determine which example profile to copy or generate
case "$PROFILE" in
    landing)
        cp "$EXAMPLES_DIR/menu_landing.yaml" "$MENU_FILE"
        echo "Created $MENU_FILE from 'landing' profile (anchor navigation)."
        ;;
    catalog)
        cp "$EXAMPLES_DIR/menu_catalog.yaml" "$MENU_FILE"
        echo "Created $MENU_FILE from 'catalog' profile (nested hierarchical submenus)."
        ;;
    conditional)
        cp "$EXAMPLES_DIR/menu_conditional.yaml" "$MENU_FILE"
        echo "Created $MENU_FILE from 'conditional' profile (event/media structure)."
        ;;
    auto|*)
        # Inspect contenttypes.yaml to determine best profile or generate
        if [ -f "config/bolt/contenttypes.yaml" ]; then
            # Check if there are catalog-like contenttypes
            if grep -q -E "(products|catalog|sluzby|services|nabidka)" "config/bolt/contenttypes.yaml" 2>/dev/null; then
                cp "$EXAMPLES_DIR/menu_catalog.yaml" "$MENU_FILE"
                echo "Detected product/service ContentTypes. Scaffolding 'catalog' profile into $MENU_FILE."
            elif grep -q -E "(events|udalosti|program|performers|ucinkujici|tickets|vstupenky)" "config/bolt/contenttypes.yaml" 2>/dev/null; then
                cp "$EXAMPLES_DIR/menu_conditional.yaml" "$MENU_FILE"
                echo "Detected event ContentTypes. Scaffolding 'conditional' profile into $MENU_FILE."
            else
                cp "$EXAMPLES_DIR/menu_landing.yaml" "$MENU_FILE"
                echo "Scaffolding baseline 'landing' profile into $MENU_FILE."
            fi
        else
            cp "$EXAMPLES_DIR/menu_landing.yaml" "$MENU_FILE"
            echo "Scaffolding baseline 'landing' profile into $MENU_FILE."
        fi
        ;;
esac

# Check if user requested Twig templates copying into active theme
if [ $COPY_TEMPLATES -eq 1 ]; then
    BOLT_CONFIG="config/bolt/config.yaml"
    ACTIVE_THEME="default"
    if [ -f "$BOLT_CONFIG" ]; then
        FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [ -n "$FOUND_THEME" ]; then
            ACTIVE_THEME="$FOUND_THEME"
        fi
    fi
    THEME_DIR="public/theme/$ACTIVE_THEME"
    if [ -d "$THEME_DIR" ]; then
        echo "Copying menu components and containers into $THEME_DIR..."
        mkdir -p "$THEME_DIR/components/nav"
        mkdir -p "$THEME_DIR/components/brand"
        mkdir -p "$THEME_DIR/containers/header"
        mkdir -p "$THEME_DIR/containers/footer"

        # cp -n keeps files that already exist in the theme (no overwrite).
        cp -n "$EXAMPLES_DIR/templates/components/nav/item.twig" "$THEME_DIR/components/nav/" || true
        cp -n "$EXAMPLES_DIR/templates/components/nav/dropdown.twig" "$THEME_DIR/components/nav/" || true
        cp -n "$EXAMPLES_DIR/templates/components/brand/logo.twig" "$THEME_DIR/components/brand/" || true
        cp -n "$EXAMPLES_DIR/templates/containers/header/_menu.twig" "$THEME_DIR/containers/header/" || true
        cp -n "$EXAMPLES_DIR/templates/containers/footer/_footer.twig" "$THEME_DIR/containers/footer/" || true
        echo "Templates copied successfully."
        echo "Merge the navigation translation units into every catalog, e.g.:"
        echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
    else
        echo "Theme directory $THEME_DIR does not exist. Skipping template copy."
    fi
fi

echo "Done! Run scripts/verify.sh to validate menu configuration."
