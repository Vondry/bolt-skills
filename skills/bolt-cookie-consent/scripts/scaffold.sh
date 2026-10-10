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

echo "=========================================================="
echo " Bolt CMS Cookie Consent & Privacy Policy Scaffolder"
echo " Project root: $BASE_DIR"
echo "=========================================================="

# 1. Detect active theme
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
    echo "Error: Theme directory '$THEME_DIR' not found."
    exit 1
fi

echo "Target Theme: $ACTIVE_THEME ($THEME_DIR)"

usage() {
    echo "Usage: scaffold.sh --model=single|joint|separate|hybrid [--trackers=ga4,google_ads,sklik,meta_pixel]"
    echo "                   [--embeds=youtube,google_maps,mapy_com] [--purposes=web_operation,contact_form,...]"
    echo "                   [--controllers=N] [--necessary=session] [--no-banner]"
    echo ""
    echo "The intake answers (SKILL.md, Step 0) build the privacy: block of theme.yaml through"
    echo "scripts/privacy-config.php. --model is required while theme.yaml has no privacy: block"
    echo "(the controller model is never guessed, AG-02). --no-banner: privacy page only (no"
    echo "trackers, no embeds)."
}

BANNER=1
CONFIG_ARGS=()
HAS_MODEL=0
for arg in "$@"; do
    case "$arg" in
        --no-banner) BANNER=0 ;;
        --model=*) HAS_MODEL=1; CONFIG_ARGS+=("$arg") ;;
        --trackers=*|--embeds=*|--purposes=*|--controllers=*|--necessary=*) CONFIG_ARGS+=("$arg") ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $arg"; usage; exit 1 ;;
    esac
done

THEME_YAML="$THEME_DIR/theme.yaml"
if [ $BANNER -eq 0 ]; then
    for arg in "${CONFIG_ARGS[@]}"; do
        case "$arg" in
            --trackers=?*|--embeds=?*) echo "ERROR: --no-banner contradicts $arg (trackers and embeds need the banner)."; exit 1 ;;
        esac
    done
fi

# 2. theme.yaml privacy: block — the single source of truth (data model, DM-01)
if [ -f "$THEME_YAML" ] && grep -qE "^privacy:" "$THEME_YAML"; then
    echo "Existing: $THEME_YAML already has a privacy: block — preserved."
elif [ $HAS_MODEL -eq 0 ]; then
    echo "ERROR: $THEME_YAML has no privacy: block yet. Run the intake (SKILL.md, Step 0) and pass"
    echo "       at least --model=single|joint|separate|hybrid (plus --trackers / --embeds / --purposes)."
    exit 1
else
    php "$SCRIPT_DIR/privacy-config.php" "${CONFIG_ARGS[@]}" --write="$THEME_YAML"
fi

copy_if_missing() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ ! -f "$dest" ]; then
        cp "$src" "$dest"
        echo "Created: $dest"
    else
        echo "Existing: $dest preserved."
    fi
}

# 3. Partials shared by the banner and the privacy page
copy_if_missing "$EXAMPLES_DIR/_privacy-macros.twig" "$THEME_DIR/partials/_privacy-macros.twig"
copy_if_missing "$EXAMPLES_DIR/_cookie-table.twig" "$THEME_DIR/partials/_cookie-table.twig"
copy_if_missing "$EXAMPLES_DIR/_privacy-form-note.twig" "$THEME_DIR/partials/_privacy-form-note.twig"

# 4. Banner, consent configuration, embed placeholder and TypeScript module
if [ $BANNER -eq 1 ]; then
    copy_if_missing "$EXAMPLES_DIR/_cookie-banner.twig" "$THEME_DIR/partials/_cookie-banner.twig"
    copy_if_missing "$EXAMPLES_DIR/_consent-mode.twig" "$THEME_DIR/partials/_consent-mode.twig"
    copy_if_missing "$EXAMPLES_DIR/_consent-embed.twig" "$THEME_DIR/partials/_consent-embed.twig"

    if [ -d "$THEME_DIR/js/src" ]; then
        copy_if_missing "$EXAMPLES_DIR/cookie-consent.ts" "$THEME_DIR/js/src/cookie-consent.ts"

        # Wire the module into the bundle entrypoint (js/src/index.ts from bolt-theme-init)
        INDEX_TS="$THEME_DIR/js/src/index.ts"
        if [ -f "$INDEX_TS" ]; then
            if grep -qE "^import ['\"]\./cookie-consent['\"]" "$INDEX_TS"; then
                echo "Verified: $INDEX_TS already imports ./cookie-consent."
            elif grep -qE "^// import ['\"]\./cookie-consent['\"]" "$INDEX_TS"; then
                sed -i.bak -E "s#^// import (['\"])\./cookie-consent(['\"]);?.*#import \1./cookie-consent\2;  // bolt-cookie-consent: banner + consent updates#" "$INDEX_TS" && rm -f "$INDEX_TS.bak"
                echo "Enabled: import './cookie-consent' in $INDEX_TS"
            else
                echo "import './cookie-consent';  // bolt-cookie-consent: banner + consent updates" >> "$INDEX_TS"
                echo "Added: import './cookie-consent' to $INDEX_TS"
            fi
        fi
    fi
fi

# 5. Privacy policy static page
copy_if_missing "$EXAMPLES_DIR/gdpr.twig" "$THEME_DIR/static-pages/gdpr.twig"

# 6. Routes for the static privacy page, inserted ABOVE Bolt's `frontend:` import — Bolt's
#    catch-all frontend routes would otherwise answer /zasady-ochrany-osobnich-udaju with 404.
ROUTES_FILE="config/routes.yaml"
if [ -f "$ROUTES_FILE" ]; then
    if grep -q "zasady-ochrany-osobnich-udaju" "$ROUTES_FILE"; then
        echo "Verified: $ROUTES_FILE already defines the privacy page route."
    else
        ROUTES_BLOCK="$(mktemp)"
        cat > "$ROUTES_BLOCK" <<'ROUTES'
# Privacy policy (bolt-cookie-consent: static page rendered from theme.yaml privacy:)
privacy:
  path: /zasady-ochrany-osobnich-udaju
  defaults:
    _controller: Bolt\Controller\Frontend\TemplateController::template
    templateName: static-pages/gdpr.twig

# Locale-prefixed variant (e.g. /en/zasady-ochrany-osobnich-udaju). Symfony sets the request
# locale from {_locale}, which __() / |trans and locale_link() pick up.
privacy_locale:
  path: /{_locale}/zasady-ochrany-osobnich-udaju
  requirements: { _locale: '%app_locales%' }
  defaults:
    _controller: Bolt\Controller\Frontend\TemplateController::template
    templateName: static-pages/gdpr.twig

ROUTES
        if grep -qE "^frontend:" "$ROUTES_FILE"; then
            awk -v block="$ROUTES_BLOCK" '
                /^frontend:/ && !done { while ((getline line < block) > 0) print line; done = 1 }
                { print }
            ' "$ROUTES_FILE" > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
            echo "Added: privacy routes above 'frontend:' in $ROUTES_FILE"
        else
            echo "WARNING: no 'frontend:' import found in $ROUTES_FILE. Add these routes above Bolt's frontend routes:"
            cat "$ROUTES_BLOCK"
        fi
        rm -f "$ROUTES_BLOCK"
    fi
fi

# 7. Check _master.twig inclusion
MASTER_FILE="$THEME_DIR/partials/_master.twig"
if [ -f "$MASTER_FILE" ]; then
    for partial in _cookie-banner.twig _consent-mode.twig; do
        if grep -q "$partial" "$MASTER_FILE"; then
            echo "Verified: $MASTER_FILE includes partials/$partial."
        else
            echo "Note: include 'partials/$partial' in $MASTER_FILE (the bolt-theme-init master already does)."
        fi
    done
fi

# 8. Translations
echo "----------------------------------------------------------"
echo "Translations: merge the cookie.* and privacy.* units into every catalog (Czech is mandatory, CB-23):"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf translations/messages.en.xlf"
echo "Next: fill every [DOPLNIT] in $THEME_YAML with the operator, measure every [OVĚŘIT] item in a"
echo "clean browser profile (DM-02), set the tracker IDs under analytics:, and hand the operator the"
echo "list of open questions (AG-05)."
echo "----------------------------------------------------------"
echo "Done! Rebuild the theme (npm run prod), clear the cache, then run scripts/verify.sh (--draft while placeholders remain)."
