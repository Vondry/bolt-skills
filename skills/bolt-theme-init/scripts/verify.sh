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
echo " Bolt CMS Theme Initialization & Architecture Verification"
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
# 1. Check config/bolt/config.yaml for active theme
# -------------------------------------------------------------
echo -n "[1/7] Checking active theme configuration in config/bolt/config.yaml... "
BOLT_CONFIG="config/bolt/config.yaml"

if [ ! -f "$BOLT_CONFIG" ]; then
    echo "FAILED"
    echo "  Error: $BOLT_CONFIG not found."
    exit 1
fi

ACTIVE_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")

if [ -z "$ACTIVE_THEME" ]; then
    echo "FAILED"
    echo "  Error: No 'theme:' setting found in $BOLT_CONFIG."
    exit 1
fi

THEME_DIR="public/theme/$ACTIVE_THEME"
echo "PASSED (Theme: '$ACTIVE_THEME')"

# -------------------------------------------------------------
# 2. Check theme folder exists
# -------------------------------------------------------------
echo -n "[2/7] Checking theme directory public/theme/$ACTIVE_THEME... "
if [ ! -d "$THEME_DIR" ]; then
    echo "FAILED"
    echo "  Error: Directory $THEME_DIR does not exist!"
    exit 1
fi
echo "PASSED"

# -------------------------------------------------------------
# 3. Check Architecture Tiers & Layout Shell (Integration Contract)
# -------------------------------------------------------------
echo -n "[3/7] Checking Component/Container/Page structure and partials/_master.twig... "
TIER_ERRORS=()

if [ ! -d "$THEME_DIR/components" ]; then
    TIER_ERRORS+=("Missing components/ folder (pure components)")
fi
if [ ! -d "$THEME_DIR/containers" ]; then
    TIER_ERRORS+=("Missing containers/ folder (smart components)")
fi
if [ ! -d "$THEME_DIR/pages" ]; then
    TIER_ERRORS+=("Missing pages/ folder (page orchestrators)")
fi
MASTER="$THEME_DIR/partials/_master.twig"
if [ ! -f "$MASTER" ]; then
    TIER_ERRORS+=("Missing partials/_master.twig layout shell (the layout every page extends)")
else
    for block in seo head main; do
        if ! grep -qE "\{%-?[[:space:]]*block[[:space:]]+${block}[[:space:]]*-?%\}" "$MASTER"; then
            TIER_ERRORS+=("partials/_master.twig does not define {% block $block %}")
        fi
    done
fi
if [ -d "$THEME_DIR/layouts" ]; then
    TIER_ERRORS+=("Legacy layouts/ folder present — the contract layout is partials/_master.twig")
fi

if [ ${#TIER_ERRORS[@]} -gt 0 ]; then
    echo "FAILED"
    for err in "${TIER_ERRORS[@]}"; do
        echo "  - $err"
    done
    FAILED=1
else
    echo "PASSED (components/, containers/, pages/, partials/_master.twig with seo/head/main blocks)"
fi

# -------------------------------------------------------------
# 4. Enforce Pure Component Purity (ZERO setcontent in components/)
# -------------------------------------------------------------
echo -n "[4/7] Enforcing Pure Component Purity (no setcontent in components/)... "
if [ -d "$THEME_DIR/components" ]; then
    SETCONTENT_MATCHES=$(find_setcontent_tags "$THEME_DIR/components")
    if [ -n "$SETCONTENT_MATCHES" ]; then
        echo "FAILED"
        echo "  Architectural Violation: Pure components in 'components/' must not call 'setcontent'!"
        echo "$SETCONTENT_MATCHES"
        FAILED=1
    else
        echo "PASSED (Zero setcontent calls in pure components)"
    fi
else
    echo "SKIPPED (components directory not found)"
fi

# -------------------------------------------------------------
# 5. Check ContentType Template Bindings
#    Every record_template / listing_template configured in contenttypes.yaml must
#    exist in the theme (e.g. products -> product.twig / product.record.twig).
# -------------------------------------------------------------
echo -n "[5/7] Checking ContentType template bindings (record_template / listing_template)... "
CT_FILE="config/bolt/contenttypes.yaml"
if [ ! -f "$CT_FILE" ] || [ ! -f "vendor/autoload.php" ]; then
    echo "SKIPPED (contenttypes.yaml or vendor/autoload.php not found)"
else
    BINDING_OUTPUT=$(php -r '
        require "vendor/autoload.php";
        $themeDir = $argv[1];
        try {
            $cts = Symfony\Component\Yaml\Yaml::parseFile("config/bolt/contenttypes.yaml");
        } catch (\Throwable $e) {
            echo "ERROR:" . $e->getMessage() . PHP_EOL;
            exit(0);
        }
        foreach ((array) $cts as $key => $ct) {
            if (! is_array($ct) || str_starts_with((string) $key, "__") || ! empty($ct["viewless"])) {
                continue;
            }
            $templates = [];
            if (! empty($ct["record_template"])) {
                $templates[] = ["record_template", $ct["record_template"]];
            }
            if (! empty($ct["listing_template"]) && empty($ct["singleton"])) {
                $templates[] = ["listing_template", $ct["listing_template"]];
            }
            foreach ($templates as [$option, $template]) {
                $status = is_file($themeDir . "/" . $template) ? "OK" : "MISSING";
                echo $status . ":" . $key . "." . $option . "=" . $template . PHP_EOL;
            }
        }
    ' "$THEME_DIR" 2>&1 || true)

    if echo "$BINDING_OUTPUT" | grep -q "^ERROR:"; then
        echo "WARNING"
        echo "  - Could not parse $CT_FILE: $(echo "$BINDING_OUTPUT" | grep '^ERROR:' | sed 's/^ERROR://')"
        WARNINGS=$((WARNINGS + 1))
    elif echo "$BINDING_OUTPUT" | grep -q "^MISSING:"; then
        echo "WARNING"
        echo "$BINDING_OUTPUT" | grep "^MISSING:" | sed -E 's/^MISSING:([^=]*)=(.*)$/  - \1 points to "\2", which does not exist in the theme/'
        WARNINGS=$((WARNINGS + 1))
    else
        BOUND=$(echo "$BINDING_OUTPUT" | grep -c "^OK:" || true)
        echo "PASSED ($BOUND configured template(s) found)"
    fi
fi

# -------------------------------------------------------------
# 6. Check Build Tooling & Configuration (Tailwind v4 CLI, Rollup, TS)
# -------------------------------------------------------------
echo -n "[6/7] Checking Build Tooling configuration in $THEME_DIR... "
TOOL_ERRORS=()

if [ ! -f "$THEME_DIR/package.json" ]; then
    TOOL_ERRORS+=("Missing package.json")
else
    if ! grep -q '"build:css"' "$THEME_DIR/package.json"; then
        TOOL_ERRORS+=("package.json missing 'build:css' script")
    fi
    if ! grep -q '"prod"' "$THEME_DIR/package.json"; then
        TOOL_ERRORS+=("package.json missing 'prod' script")
    fi
    if ! grep -q "tailwindcss" "$THEME_DIR/package.json"; then
        TOOL_ERRORS+=("package.json missing tailwindcss dependency")
    fi
fi

if [ ! -f "$THEME_DIR/theme.yaml" ]; then
    TOOL_ERRORS+=("Missing theme.yaml (required for assets_version cache-busting)")
fi
if [ ! -f "$THEME_DIR/css/tailwind/index.css" ]; then
    TOOL_ERRORS+=("Missing css/tailwind/index.css Tailwind entrypoint")
fi

# Check shared TS modules
for ts_mod in auto-scroll.ts menu.ts locale-switcher.ts photoswipe.ts; do
    if [ ! -f "$THEME_DIR/js/src/$ts_mod" ]; then
        TOOL_ERRORS+=("Missing shared TypeScript module js/src/$ts_mod")
    fi
done

# Check Article CSS assets
if [ ! -f "$THEME_DIR/css/article/grid.css" ]; then
    TOOL_ERRORS+=("Missing css/article/grid.css")
fi

if [ ${#TOOL_ERRORS[@]} -gt 0 ]; then
    echo "FAILED"
    for err in "${TOOL_ERRORS[@]}"; do
        echo "  - $err"
    done
    FAILED=1
else
    echo "PASSED (Tailwind v4 CLI, Rollup, shared TS modules & article CSS verified)"
fi

# -------------------------------------------------------------
# 7. Check Compiled Production Assets (css/index.css & js/app.js)
# -------------------------------------------------------------
echo -n "[7/7] Checking compiled production assets... "
ASSET_ERRORS=()

if [ ! -f "$THEME_DIR/css/index.css" ] || [ ! -s "$THEME_DIR/css/index.css" ]; then
    ASSET_ERRORS+=("Compiled stylesheet $THEME_DIR/css/index.css is missing or empty")
fi

# JS can be app.js or index.js
if [ ! -f "$THEME_DIR/js/app.js" ] && [ ! -f "$THEME_DIR/js/index.js" ]; then
    ASSET_ERRORS+=("Compiled script $THEME_DIR/js/app.js is missing")
fi

if [ ${#ASSET_ERRORS[@]} -gt 0 ]; then
    echo "WARNING"
    for err in "${ASSET_ERRORS[@]}"; do
        echo "  - $err"
    done
    echo "  Hint: Run 'npm --prefix $THEME_DIR run prod' to generate assets."
    WARNINGS=$((WARNINGS + 1))
else
    echo "PASSED (css/index.css and JS bundle present and non-empty)"
fi

echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo " RESULT: ALL CHECKS PASSED PERFECTLY!"
    else
        echo " RESULT: PASSED with $WARNINGS warning(s)."
    fi
    exit 0
else
    echo " RESULT: VERIFICATION FAILED with errors above."
    exit 1
fi
