#!/usr/bin/env bash
set -e

# bolt-map verification: the 3D city map (files, build, theme settings, templates, translations
# and privacy). Passes when the theme shows no bolt-map map.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=map-lib.sh
source "$SCRIPT_DIR/map-lib.sh"

BASE_DIR="$(find_project_root)"
if [ -z "$BASE_DIR" ]; then
    DIR="$SCRIPT_DIR"
    while [ "$DIR" != "/" ]; do
        if [ -f "$DIR/config/services.yaml" ]; then
            BASE_DIR="$DIR"
            break
        fi
        DIR="$(dirname "$DIR")"
    done
fi
if [ -z "$BASE_DIR" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi
cd "$BASE_DIR"

echo "=========================================================="
echo " Bolt CMS Map Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0
SECTION=0
TOTAL_SECTIONS=5

section() { SECTION=$((SECTION + 1)); echo ""; echo "[$SECTION/$TOTAL_SECTIONS] $1"; }
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ✗ FAILED: $1"; FAILED=$((FAILED + 1)); }

THEME="$(active_theme "$BASE_DIR")"
THEME_DIR="public/theme/$THEME"
THEME_YAML="$THEME_DIR/theme.yaml"
if [ -z "$THEME" ] || [ ! -f "$THEME_YAML" ]; then
    echo "ERROR: active theme not found ($THEME_YAML)."
    exit 1
fi

INCLUDES="$(grep -rlE "components/ui/map\.twig" "$THEME_DIR" --include='*.twig' --exclude=map.twig --exclude-dir=node_modules 2>/dev/null || true)"
if [ -z "$INCLUDES" ] && [ ! -f "$THEME_DIR/js/map.js" ]; then
    echo ""
    echo "  ✓ The theme shows no bolt-map map, nothing to verify."
    echo ""
    echo "=========================================================="
    echo " VERIFICATION PASSED (0 warning(s))"
    echo "=========================================================="
    exit 0
fi

section "Files and settings of the map"
if [ -f "$THEME_DIR/js/map.js" ]; then
    pass "js/map.js exists"
    if grep -q 'tiles.openfreemap.org/styles/' "$THEME_DIR/js/map.js"; then
        pass "map style comes from OpenFreeMap (no API key, no cookies)"
    else
        fail "js/map.js does not load an OpenFreeMap style"
    fi
    if grep -q 'cooperativeGestures: true' "$THEME_DIR/js/map.js"; then
        pass "the page keeps scrolling over the map (cooperativeGestures)"
    else
        warn "js/map.js has no cooperativeGestures: the map captures the page scroll"
    fi
    if grep -qE 'pitch:' "$THEME_DIR/js/map.js"; then
        pass "the map starts tilted (3D)"
    else
        warn "js/map.js sets no pitch: the buildings look flat"
    fi
    if grep -qE 'localStorage|sessionStorage|document\.cookie|indexedDB' "$THEME_DIR/js/map.js"; then
        fail "js/map.js stores data in the browser, which would need consent"
    else
        pass "js/map.js stores nothing in the browser"
    fi
else
    fail "js/map.js is missing (scaffold.sh)"
fi
if [ -f "$THEME_DIR/components/ui/map.twig" ]; then
    pass "components/ui/map.twig exists"
    if grep -qE '[" ]isolate[" ]' "$THEME_DIR/components/ui/map.twig"; then
        pass "the map's z-indexes stay inside the map (isolate)"
    else
        fail "components/ui/map.twig has no isolate on its wrapper: MapLibre's help text (z-index 99999) shows over the cookie banner"
    fi
    # Tailwind writes no rule for a class whose token the theme lacks (a theme older than the
    # Integration Contract), so the button or the pin silently loses the theme's colour.
    BUILT_CSS="$THEME_DIR/css/index.css"
    if [ -f "$BUILT_CSS" ]; then
        MISSING_CLASSES=""
        for class in $(grep -oE 'class="[^"]*"' "$THEME_DIR/components/ui/map.twig" | sed -E 's/^class="//; s/"$//' | tr ' ' '\n' \
            | grep -E '^(btn-[a-z0-9-]+|(bg|text|border)-[a-z][a-z0-9-]*)$' \
            | grep -vE '^border-([xytblrse]|solid|dashed|none)$|^text-(xs|sm|base|lg|[0-9]?xl|left|center|right)$' | sort -u); do
            grep -qF ".$class{" "$BUILT_CSS" || grep -qF ".$class " "$BUILT_CSS" || grep -qF ".$class:" "$BUILT_CSS" || MISSING_CLASSES="$MISSING_CLASSES $class"
        done
        if [ -z "$MISSING_CLASSES" ]; then
            pass "every colour class of the map is in css/index.css (button and pin in the theme's colours)"
        else
            fail "css/index.css has no rule for:$MISSING_CLASSES — the theme lacks the token or utility; use one it has in components/ui/map.twig, or run npm run prod"
        fi
    else
        warn "css/index.css is not built: the map's colour classes cannot be checked"
    fi
    if grep -q '\[data-map\] canvas' "$THEME_DIR/css/tailwind/index.css" 2>/dev/null; then
        pass "light or dark follows the visitor's system"
    else
        fail "css/tailwind/index.css has no light or dark rule for the map (scaffold.sh)"
    fi
else
    fail "components/ui/map.twig is missing (scaffold.sh)"
fi

section "Build"
if [ -f "$THEME_DIR/package.json" ] && grep -q '"maplibre-gl"' "$THEME_DIR/package.json"; then
    pass "maplibre-gl is a dependency"
else
    fail "maplibre-gl is not in package.json (scaffold.sh)"
fi
if [ -f "$THEME_DIR/package.json" ] && grep -E '"prod"' "$THEME_DIR/package.json" | grep -q 'build:map'; then
    pass "npm run prod copies the library"
else
    fail "npm run prod does not run build:map (scaffold.sh)"
fi
for file in maplibre-gl.js maplibre-gl-worker.js maplibre-gl.css; do
    if [ -s "$THEME_DIR/js/maplibre/$file" ]; then
        pass "js/maplibre/$file is built"
    else
        fail "js/maplibre/$file is missing: run npm run prod in the theme"
    fi
done
if [ -f "$THEME_DIR/js/app.js" ] && grep -q 'maplibregl-canvas' "$THEME_DIR/js/app.js"; then
    fail "MapLibre is bundled into js/app.js and loads on every page: do not import it in js/src/"
else
    pass "MapLibre stays out of js/app.js"
fi
if grep -rq 'js/maplibre' "$THEME_DIR/css/tailwind/index.css" 2>/dev/null; then
    pass "the library is left out of Tailwind's class scan"
else
    fail "css/tailwind/index.css has no @source not for js/maplibre: the 1 MB library is scanned for classes"
fi

section "Theme settings"
LATITUDE="$(yaml_block_value "$THEME_YAML" location latitude)"
LONGITUDE="$(yaml_block_value "$THEME_YAML" location longitude)"
ZOOM="$(yaml_block_value "$THEME_YAML" location zoom)"
if [[ "$LATITUDE" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && [[ "$LONGITUDE" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    pass "location: $LATITUDE, $LONGITUDE"
else
    warn "theme.yaml has no location coordinates: every map must pass latitude and longitude itself"
fi
if [[ "$ZOOM" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v zoom="$ZOOM" 'BEGIN { exit !(zoom < 14) }'; then
    warn "location.zoom is $ZOOM: 3D buildings appear from zoom 14"
fi

section "Templates"
if [ -n "$INCLUDES" ]; then
    pass "the map is used in: $(echo "$INCLUDES" | sed "s#^$THEME_DIR/##" | tr '\n' ' ')"
else
    warn "no template includes components/ui/map.twig"
fi
IFRAMES="$(grep -rlE '<iframe[^>]*(google\.[a-z.]+/maps|maps\.google|mapy\.(cz|com))' "$THEME_DIR" --include='*.twig' --exclude-dir=node_modules 2>/dev/null || true)"
EMBEDS="$(grep -rlE "src:[[:space:]]*['\"]https://[^'\"]*(google\.[a-z.]+/maps|maps\.google|mapy\.(cz|com))" "$THEME_DIR" --include='*.twig' --exclude-dir=node_modules 2>/dev/null || true)"
if [ -n "$IFRAMES$EMBEDS" ]; then
    fail "a third-party map embed is still there and needs consent: $(echo "$IFRAMES $EMBEDS" | tr '\n' ' ')"
else
    pass "no Google Maps or Mapy.com embed is left"
fi

section "Translations and privacy"
APP_LOCALES="$(grep -E '^[[:space:]]*app_locales:' config/services.yaml | head -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' ")"
for locale in ${APP_LOCALES//|/ }; do
    CATALOG="translations/messages.$locale.xlf"
    MISSING=""
    for key in $MAP_TRANSLATION_KEYS; do
        grep -q "name=\"$key\"" "$CATALOG" 2>/dev/null || MISSING="$MISSING $key"
    done
    if [ -z "$MISSING" ]; then
        pass "$CATALOG has every map label"
    else
        fail "$CATALOG misses:$MISSING (scripts/merge-xliff.php)"
    fi
done
if grep -q 'openfreemap' "$THEME_YAML"; then
    pass "the privacy data lists OpenFreeMap"
else
    warn "theme.yaml privacy: does not list OpenFreeMap (bolt-cookie-consent, --purposes=...,map_display)"
fi
CSP_FILE="config/packages/nelmio_security.yaml"
if [ -f "$CSP_FILE" ]; then
    CONNECT="$(grep -E '^[[:space:]]+connect-src:' "$CSP_FILE" || true)"
    IMAGES="$(grep -E '^[[:space:]]+img-src:' "$CSP_FILE" || true)"
    if [ -n "$CONNECT" ] && ! echo "$CONNECT" | grep -q 'tiles.openfreemap.org'; then
        fail "the CSP connect-src blocks the map: add https://tiles.openfreemap.org"
    elif [ -n "$IMAGES" ] && ! echo "$IMAGES" | grep -q 'blob:'; then
        fail "the CSP img-src blocks the map: add blob:"
    else
        pass "the Content-Security-Policy allows the map"
    fi
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED ($FAILED failure(s), $WARNINGS warning(s))"
    echo " Please review the errors reported above."
    echo "=========================================================="
    exit 1
fi
