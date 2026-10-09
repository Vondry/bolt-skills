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

# Options: --no-banner (privacy page only, for sites without tracking)
BANNER=1
for arg in "$@"; do
    case "$arg" in
        --no-banner) BANNER=0 ;;
        *) echo "Unknown argument: $arg"; echo "Usage: ./scaffold.sh [--no-banner]"; exit 1 ;;
    esac
done

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

# 2. Banner, Consent Mode partial and TypeScript module (only when the site uses tracking)
if [ $BANNER -eq 1 ]; then
    copy_if_missing "$EXAMPLES_DIR/_cookie-banner.twig" "$THEME_DIR/partials/_cookie-banner.twig"
    copy_if_missing "$EXAMPLES_DIR/_consent-mode.twig" "$THEME_DIR/partials/_consent-mode.twig"

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

# 3. Privacy policy static page (Pattern A)
copy_if_missing "$EXAMPLES_DIR/gdpr.twig" "$THEME_DIR/static-pages/gdpr.twig"

# 4. Routes for the static privacy page, inserted ABOVE Bolt's `frontend:` import — Bolt's
#    catch-all frontend routes would otherwise answer /zasady-ochrany-osobnich-udaju with 404.
ROUTES_FILE="config/routes.yaml"
if [ -f "$ROUTES_FILE" ]; then
    if grep -q "zasady-ochrany-osobnich-udaju" "$ROUTES_FILE"; then
        echo "Verified: $ROUTES_FILE already defines the privacy page route."
    else
        ROUTES_BLOCK="$(mktemp)"
        cat > "$ROUTES_BLOCK" <<'ROUTES'
# Privacy policy (bolt-cookie-consent, Pattern A: static page + XLIFF translations)
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

# 5. Check _master.twig inclusion
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

# 6. Translations
echo "----------------------------------------------------------"
echo "Translations: merge the cookie.* and privacy.* units into every catalog:"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf translations/messages.en.xlf"
echo "Tracking IDs: theme.yaml -> analytics.ga4_id / analytics.sklik_id / analytics.consent_mode"
echo "----------------------------------------------------------"
echo "Done! Rebuild the theme (npm run prod), clear the cache, then run scripts/verify.sh."
