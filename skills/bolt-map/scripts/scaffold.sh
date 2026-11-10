#!/usr/bin/env bash
set -e

# bolt-map scaffold: copies the component and js/map.js into the active theme, adds MapLibre and
# its build step to package.json, keeps the library out of Tailwind's class scan and writes
# location: to theme.yaml. Existing files and keys are kept; safe to repeat.
#
# Usage: scaffold.sh --lat=<latitude> --lng=<longitude> [--zoom=17]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../examples" && pwd)"
# shellcheck source=map-lib.sh
source "$SCRIPT_DIR/map-lib.sh"

LAT=""
LNG=""
ZOOM="17"
for argument in "$@"; do
    case "$argument" in
        --lat=*) LAT="${argument#--lat=}" ;;
        --lng=*) LNG="${argument#--lng=}" ;;
        --zoom=*) ZOOM="${argument#--zoom=}" ;;
        *) echo "Usage: scaffold.sh --lat=<latitude> --lng=<longitude> [--zoom=17]"; exit 1 ;;
    esac
done

BASE_DIR="$(find_project_root)"
if [ -z "$BASE_DIR" ]; then
    echo "ERROR: run this inside a Bolt project (config/services.yaml not found)."
    exit 1
fi
cd "$BASE_DIR"

THEME="$(active_theme "$BASE_DIR")"
THEME_DIR="public/theme/$THEME"
if [ -z "$THEME" ] || [ ! -f "$THEME_DIR/theme.yaml" ]; then
    echo "ERROR: active theme not found (theme: in config/bolt/config.yaml, $THEME_DIR/theme.yaml)."
    exit 1
fi
if [ ! -f "$THEME_DIR/package.json" ]; then
    echo "ERROR: $THEME_DIR/package.json not found. Run bolt-theme-init first."
    exit 1
fi

copy_if_missing() {
    mkdir -p "$(dirname "$2")"
    if [ -e "$2" ]; then
        echo "  kept    $2"
    else
        cp "$1" "$2"
        echo "  created $2"
    fi
}

copy_if_missing "$EXAMPLES_DIR/map.js" "$THEME_DIR/js/map.js"
copy_if_missing "$EXAMPLES_DIR/map.twig" "$THEME_DIR/components/ui/map.twig"

php -r '
    $file = $argv[1];
    $package = json_decode(file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    $package["dependencies"]["maplibre-gl"] ??= "^6.17.0";
    $dist = "node_modules/maplibre-gl/dist";
    $package["scripts"]["build:map"] = "mkdir -p js/maplibre"
        . " && cp $dist/maplibre-gl.mjs js/maplibre/maplibre-gl.js"
        . " && cp $dist/maplibre-gl-worker.mjs js/maplibre/maplibre-gl-worker.js"
        . " && cp $dist/maplibre-gl.css js/maplibre/maplibre-gl.css";
    $production = $package["scripts"]["prod"] ?? "npm run build:css && npm run build:js";
    if (!str_contains($production, "build:map")) {
        $package["scripts"]["prod"] = "npm run build:map && " . $production;
    }
    $json = json_encode($package, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    // npm style (two spaces): npm copies the indentation of package.json into package-lock.json.
    $json = preg_replace_callback("/^(?: {4})+/m", static fn (array $match): string => substr($match[0], 0, (int) (strlen($match[0]) / 2)), $json);
    file_put_contents($file, $json . "\n");
' "$THEME_DIR/package.json"
echo "  updated $THEME_DIR/package.json (maplibre-gl, build:map, prod)"

CSS_SOURCE="$THEME_DIR/css/tailwind/index.css"
if [ -f "$CSS_SOURCE" ] && ! grep -q 'js/maplibre' "$CSS_SOURCE"; then
    php -r '
        $file = $argv[1];
        $rule = "/* bolt-map: the map library is not a source of Tailwind classes. */\n@source not \"../../js/maplibre\";\n\n";
        $css = file_get_contents($file);
        $position = preg_match("/^@theme\b/m", $css, $match, PREG_OFFSET_CAPTURE) ? $match[0][1] : strlen($css);
        file_put_contents($file, substr($css, 0, $position) . $rule . substr($css, $position));
    ' "$CSS_SOURCE"
    echo "  updated $CSS_SOURCE (@source not js/maplibre)"
fi

if [ -f "$CSS_SOURCE" ] && ! grep -q '\[data-map\] canvas' "$CSS_SOURCE"; then
    cat >> "$CSS_SOURCE" <<'CSS'

/* bolt-map: light or dark by the visitor's system, whatever the site does. Not `dark:`, which a theme can redefine. */
@media (prefers-color-scheme: dark) {
    [data-map] canvas { filter: hue-rotate(180deg) invert(1); }
    [data-map] .maplibregl-ctrl-group,
    [data-map] .maplibregl-ctrl-attrib { filter: invert(1); }
}
CSS
    echo "  updated $CSS_SOURCE (the map's light or dark rule)"
fi

if grep -qE '^location:' "$THEME_DIR/theme.yaml"; then
    echo "  kept    location in theme.yaml"
else
    {
        echo ""
        echo "# bolt-map: position of the pin and how close the 3D map starts (buildings appear from zoom 14)."
        echo "location:"
        echo "  latitude: ${LAT:-~}"
        echo "  longitude: ${LNG:-~}"
        echo "  zoom: $ZOOM"
    } >> "$THEME_DIR/theme.yaml"
    echo "  added   location to theme.yaml"
fi

SKILLS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
echo ""
echo "Next:"
echo "  php $SKILLS_ROOT/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "  php $SKILLS_ROOT/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf translations/messages.en.xlf"
echo "  (npm install && npm run prod in $THEME_DIR, then bump assets_version in theme.yaml)"
