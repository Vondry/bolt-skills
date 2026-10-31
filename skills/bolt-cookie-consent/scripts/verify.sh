#!/usr/bin/env bash
set -e

# bolt-cookie-consent verification. Requirement IDs refer to references/guidelines.cs.md.
#   bash verify.sh [--draft]
# --draft: report [DOPLNIT] / [OVĚŘIT] placeholders as warnings (while the operator is still
#          answering). A production sign-off runs without it.
# Live checks use BOLT_BASE_URL (set by verify-all.sh --base-url=…).

DRAFT=""
for arg in "$@"; do
    case "$arg" in
        --draft) DRAFT="--draft" ;;
        *) echo "Usage: verify.sh [--draft]"; exit 1 ;;
    esac
done

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

echo "=========================================================="
echo " Bolt CMS Cookie Consent & Privacy Policy Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0
fail() { echo "  FAILED: $1"; FAILED=$((FAILED + 1)); }
warn() { echo "  WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
pass() { echo "  PASSED: $1"; }

# -------------------------------------------------------------
# 1. Active theme
# -------------------------------------------------------------
echo "[1/10] Active theme"
ACTIVE_THEME="default"
if [ -f "$BOLT_CONFIG" ]; then
    FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    [ -n "$FOUND_THEME" ] && ACTIVE_THEME="$FOUND_THEME"
fi
THEME_DIR="public/theme/$ACTIVE_THEME"
if [ ! -d "$THEME_DIR" ]; then
    echo "  FAILED: Theme directory '$THEME_DIR' does not exist."
    exit 1
fi
pass "$ACTIVE_THEME ($THEME_DIR)"

# -------------------------------------------------------------
# 2. Data model: theme.yaml privacy: (default) or a privacy ContentType (single source of truth)
# -------------------------------------------------------------
# A theme.yaml without a privacy: block may keep the data in a ContentType instead: the first
# ContentType whose `cookies` collection has a `category` field (SKILL.md, "Data model in a
# ContentType"). Its published record is then read through the project's kernel.
PRIVACY_CT=""
if [ -f vendor/autoload.php ] && [ -f "$THEME_DIR/theme.yaml" ] && ! grep -qE '^privacy:' "$THEME_DIR/theme.yaml"; then
    PRIVACY_CT=$(php -r '
        require "vendor/autoload.php";
        $types = Symfony\Component\Yaml\Yaml::parseFile("config/bolt/contenttypes.yaml");
        foreach ($types as $key => $type) {
            $cookies = $type["fields"]["cookies"] ?? [];
            $item = is_array($cookies["fields"] ?? null) ? reset($cookies["fields"]) : null;
            if (($cookies["type"] ?? "") === "collection" && is_array($item) && isset($item["fields"]["category"])) {
                echo $type["slug"] ?? $key;
                break;
            }
        }' 2>/dev/null || true)
fi
if [ -n "$PRIVACY_CT" ]; then
    echo "[2/10] privacy data in the '$PRIVACY_CT' ContentType (cookie inventory; tracker IDs in theme.yaml analytics:)"
else
    echo "[2/10] theme.yaml privacy: data (controllers, purposes, recipients, cookie inventory)"
fi
CATEGORIES=""
INVENTORY=""
if [ ! -f "$THEME_DIR/theme.yaml" ]; then
    fail "$THEME_DIR/theme.yaml not found."
elif [ ! -f vendor/autoload.php ]; then
    warn "vendor/autoload.php missing (run composer install) — privacy data not validated."
    CATEGORIES="unknown"
else
    CT_ARG=()
    [ -n "$PRIVACY_CT" ] && CT_ARG=("--contenttype=$PRIVACY_CT")
    while IFS= read -r line; do
        case "$line" in
            FAIL:*) fail "${line#FAIL: }" ;;
            WARN:*) warn "${line#WARN: }" ;;
            OK:*) pass "${line#OK: }" ;;
            CATEGORIES:*) CATEGORIES="$(echo "${line#CATEGORIES:}" | tr -d ' ')" ;;
            INVENTORY:*) INVENTORY="$(echo "${line#INVENTORY:}" | tr -d ' ')" ;;
        esac
    done < <(php "$SCRIPT_DIR/check-privacy.php" "$THEME_DIR/theme.yaml" ${CT_ARG[@]+"${CT_ARG[@]}"} $DRAFT 2>&1)
fi

if [ -z "$CATEGORIES" ]; then
    echo "  INFO: no consent category in privacy.cookies — no banner needed (privacy page still required)."
else
    echo "  INFO: consent categories in use: $CATEGORIES"
fi
HAS_CONSENT=0
[ -n "$CATEGORIES" ] && HAS_CONSENT=1

# Twig templates of the theme, without the skill's own partials where noted
theme_twig() { find "$THEME_DIR" -name "*.twig" -not -path "*/node_modules/*" 2>/dev/null; }

# -------------------------------------------------------------
# 3. Banner templates and layout wiring
# -------------------------------------------------------------
echo "[3/10] Banner partials and layout"
BANNER_FILE="$THEME_DIR/partials/_cookie-banner.twig"
CONSENT_FILE="$THEME_DIR/partials/_consent-mode.twig"
MASTER_FILE="$THEME_DIR/partials/_master.twig"
# The macros render theme.yaml privacy: data; a ContentType model renders the record with the
# site's own templates.
if [ -z "$PRIVACY_CT" ]; then
    for partial in _privacy-macros.twig _cookie-table.twig; do
        [ -f "$THEME_DIR/partials/$partial" ] || fail "partials/$partial missing (used by the privacy page and the banner)."
    done
fi
# Bolt returns theme.yaml blocks as collections: |column('category') finds nothing in them (no
# consent categories → no banner, no consent configuration) and a key set to ~ throws on access.
for file in "$THEME_DIR/partials/_consent-mode.twig" "$THEME_DIR/partials/_cookie-banner.twig" "$THEME_DIR/partials/_privacy-form-note.twig" "$THEME_DIR/static-pages/gdpr.twig"; do
    if [ -f "$file" ] && grep -qE "config\.get\('theme/(privacy|analytics)'\)" "$file" && ! grep -q "toArray()" "$file"; then
        fail "${file#"$THEME_DIR"/} reads theme.yaml privacy: / analytics: without toArray() — Bolt's collections make the banner disappear and ~ values throw. Copy the current example."
    fi
done
if [ $HAS_CONSENT -eq 1 ]; then
    [ -f "$BANNER_FILE" ] || fail "partials/_cookie-banner.twig missing."
    [ -f "$CONSENT_FILE" ] || fail "partials/_consent-mode.twig missing."
    if [ -f "$MASTER_FILE" ]; then
        HEAD_PART=$(sed -n '1,/<\/head>/p' "$MASTER_FILE")
        if echo "$HEAD_PART" | grep -q "_consent-mode.twig"; then
            pass "_consent-mode.twig included in <head>."
        else
            fail "partials/_master.twig must include partials/_consent-mode.twig inside <head>."
        fi
        if grep -q "_cookie-banner.twig" "$MASTER_FILE"; then
            pass "_cookie-banner.twig included in the master layout."
        else
            fail "partials/_master.twig does not include partials/_cookie-banner.twig."
        fi
    else
        warn "partials/_master.twig not found — check the includes manually."
    fi
else
    pass "skipped (no consent category)."
fi

# -------------------------------------------------------------
# 4. Banner compliance (CB-10–CB-22, CB-60, DP-01–DP-03, DP-07)
# -------------------------------------------------------------
echo "[4/10] Banner compliance (equal Accept / Reject, layer 2, defaults off, a11y)"
if [ $HAS_CONSENT -eq 1 ] && [ -f "$BANNER_FILE" ]; then
    RESULT=$(php -r '
        $html = file_get_contents($argv[1]);
        // Resolve {{ var }} class variables set in the template
        preg_match_all("~\{%\s*set\s+(\w+)\s*=\s*\x27([^\x27]*)\x27\s*%\}~", $html, $sets, PREG_SET_ORDER);
        $vars = [];
        foreach ($sets as $set) { $vars[$set[1]] = $set[2]; }
        $classes = function (string $id) use ($html, $vars) {
            if (! preg_match("~<button\b[^>]*\bid=\"" . $id . "\"[^>]*>~s", $html, $m)) { return null; }
            if (! preg_match("~\bclass=\"([^\"]*)\"~", $m[0], $c)) { return ""; }
            $value = preg_replace_callback("~\{\{\s*(\w+)\s*\}\}~", fn ($v) => $vars[$v[1]] ?? $v[0], $c[1]);
            $list = array_values(array_filter(preg_split("~\s+~", trim($value)), fn ($x) => $x !== "" && ! preg_match("~^(\w+:)?(order-|col-span-)~", $x)));
            sort($list);
            return implode(" ", $list);
        };
        $out = [];
        foreach ([["cookie-btn-reject", "cookie-btn-accept"], ["cookie-dialog-reject", "cookie-dialog-save", "cookie-dialog-accept"]] as $group) {
            $values = array_map($classes, $group);
            if (in_array(null, $values, true)) { $out[] = "MISSING " . implode("/", $group); continue; }
            $out[] = count(array_unique($values)) === 1 ? "EQUAL " . implode("/", $group) : "DIFFERENT " . implode("/", $group);
        }
        echo implode("\n", $out);
    ' "$BANNER_FILE" 2>/dev/null || echo "UNKNOWN")
    while IFS= read -r line; do
        case "$line" in
            EQUAL*) pass "${line#EQUAL } share identical classes (CB-12)." ;;
            DIFFERENT*) fail "${line#DIFFERENT } are styled differently — equal visual weight is required (CB-12, DP-02)." ;;
            MISSING*) fail "buttons ${line#MISSING } not found — Accept and Reject must both be buttons in each layer (CB-10, CB-11, CB-22)." ;;
            *) warn "button styling not compared ($line)." ;;
        esac
    done <<< "$RESULT"

    grep -q "data-cookie-settings" "$BANNER_FILE" && pass "layer 1 offers \"Nastavení cookies\" (CB-13)." || fail "layer 1 has no [data-cookie-settings] button (CB-13)."
    grep -q "data-cookie-save" "$BANNER_FILE" && grep -q "data-cookie-dialog" "$BANNER_FILE" \
        && pass "layer 2 dialog with \"Uložit výběr\" (CB-22)." || fail "layer 2 ([data-cookie-dialog] with [data-cookie-save]) missing (CB-22)."
    if grep -E "data-cookie-category" "$BANNER_FILE" | grep -qE 'aria-checked="true"|[[:space:]]checked([[:space:]>=]|$)'; then
        fail "a consent switch is pre-checked — every consent category must start off (CB-20, DP-03)."
    else
        pass "consent switches start off (CB-20)."
    fi
    if grep -q 'role="dialog"' "$BANNER_FILE" && grep -q 'aria-labelledby' "$BANNER_FILE" && grep -q 'role="switch"' "$BANNER_FILE"; then
        pass "role=\"dialog\" with aria-labelledby, role=\"switch\" (CB-60)."
    else
        fail "banner needs role=\"dialog\" + aria-labelledby and role=\"switch\" toggles (CB-60)."
    fi
else
    pass "skipped (no consent category)."
fi

# -------------------------------------------------------------
# 5. Forbidden wording (CB-05, DP-04) and consistent labels (DP-08)
# -------------------------------------------------------------
echo "[5/10] Wording"
WORDING=$(grep -rniE "používáním (tohoto |našeho )?(webu|stránek)[^.]{0,40}souhlasíte|pokračováním[^.]{0,60}souhlasíte|by (continuing|using)[^.]{0,40}(you agree|you consent)" "$THEME_DIR" translations --include="*.twig" --include="*.xlf" --include="*.yaml" 2>/dev/null || true)
if [ -n "$WORDING" ]; then
    fail "implied-consent wording found (CB-05):"
    echo "$WORDING" | head -5 | sed 's/^/    /'
else
    pass "no \"používáním webu souhlasíte\" wording (CB-05)."
fi
CS_XLF="translations/messages.cs.xlf"
if [ -f "$CS_XLF" ]; then
    target_of() { grep -o "name=\"$1\"><segment><source>[^<]*</source><target>[^<]*" "$CS_XLF" | sed 's/.*<target>//'; }
    if [ -n "$(target_of footer.cookie_settings)" ] && [ "$(target_of footer.cookie_settings)" != "$(target_of cookie.settings)" ]; then
        warn "footer.cookie_settings and cookie.settings differ — use one name for the same thing (DP-08)."
    else
        pass "one label for the settings entry point (DP-08)."
    fi
fi

# -------------------------------------------------------------
# 6. Nothing non-essential hard-coded outside the consent mechanism (CB-01, CB-02)
# -------------------------------------------------------------
echo "[6/10] Trackers and embeds only behind consent"
TRACKER_RE='googletagmanager\.com|google-analytics\.com|c\.seznam\.cz/js/rc\.js|connect\.facebook\.net|static\.hotjar\.com|clarity\.ms|snap\.licdn\.com|analytics\.tiktok\.com'
EMBED_RE='<iframe[^>]*(youtube\.com|youtube-nocookie\.com|vimeo\.com|google\.[a-z.]+/maps|maps\.google|mapy\.(cz|com)|facebook\.com)'
LEAKS=""
while IFS= read -r file; do
    case "$file" in */partials/_consent-embed.twig) continue ;; esac
    while IFS= read -r hit; do
        line="${hit#*:}"
        # Allowed: blocked scripts and include parameters (src: '…' for _consent-embed)
        echo "$line" | grep -qE 'type="text/plain"|^[[:space:]]*src:' && continue
        LEAKS="$LEAKS"$'\n'"    $file:$hit"
    done < <(grep -nE "$TRACKER_RE|$EMBED_RE|gtag\(['\"](config|js)" "$file" 2>/dev/null || true)
done < <(theme_twig)
if [ -n "$LEAKS" ]; then
    fail "tracker or embed outside the consent mechanism — use partials/_consent-embed.twig or <script type=\"text/plain\" data-consent-category=\"…\"> (CB-01, CB-02):$LEAKS"
else
    pass "no tracker script or third-party iframe hard-coded in templates."
fi

# -------------------------------------------------------------
# 7. JavaScript module
# -------------------------------------------------------------
echo "[7/10] js/src/cookie-consent.ts"
if [ $HAS_CONSENT -eq 1 ]; then
    if [ -f "$THEME_DIR/js/src/cookie-consent.ts" ]; then
        pass "module present."
        if grep -qE "^import ['\"]\./cookie-consent['\"]" "$THEME_DIR/js/src/index.ts" 2>/dev/null; then
            pass "imported by js/src/index.ts."
        else
            fail "js/src/index.ts does not import './cookie-consent'."
        fi
        if grep -qE "setTimeout\([^)]*(hide|close|banner)" "$THEME_DIR/js/src/cookie-consent.ts"; then
            fail "the banner must never close on its own (CB-62)."
        fi
    else
        fail "js/src/cookie-consent.ts missing."
    fi
else
    pass "skipped (no consent category)."
fi

# -------------------------------------------------------------
# 8. Footer: privacy link everywhere (PP-01) and cookie settings (CB-30, DP-09)
# -------------------------------------------------------------
echo "[8/10] Footer links"
FOOTER_FILES=$(theme_twig | grep -iE "footer" || true)
if [ -z "$FOOTER_FILES" ]; then
    warn "no footer template found — the footer must link the privacy policy and \"Nastavení cookies\" on every page."
else
    # shellcheck disable=SC2086
    if grep -q "zasady-ochrany-osobnich-udaju" $FOOTER_FILES; then
        pass "footer links the privacy policy (PP-01)."
    elif [ -n "$PRIVACY_CT" ] && grep -qE "\|link" $FOOTER_FILES; then
        # The ContentType model links the record (`privacy_policy|link`); its URL is checked live.
        pass "footer links a record with |link — the link to /zasady-ochrany-osobnich-udaju is checked live (PP-01)."
    else
        fail "footer does not link /zasady-ochrany-osobnich-udaju (PP-01)."
    fi
    if [ $HAS_CONSENT -eq 1 ]; then
        # shellcheck disable=SC2086
        if grep -q "data-cookie-settings" $FOOTER_FILES; then
            pass "footer has the \"Nastavení cookies\" button (CB-30)."
            # shellcheck disable=SC2086
            if grep -qE "has_tracking[^%]*ga4_id" $FOOTER_FILES && ! grep -qE "has_tracking[^%]*privacy" $FOOTER_FILES; then
                warn "the footer shows \"Nastavení cookies\" only for analytics IDs — base it on privacy.cookies so embeds and other trackers count too (bolt-menu footer)."
            fi
        else
            fail "footer has no [data-cookie-settings] button — withdrawal must be as easy as consent (CB-30, DP-09)."
        fi
    fi
fi

# -------------------------------------------------------------
# 9. Privacy policy page and route
# -------------------------------------------------------------
echo "[9/10] Privacy policy page (/zasady-ochrany-osobnich-udaju)"
PAGE="$THEME_DIR/static-pages/gdpr.twig"
CHECK_ANCHORS_LIVE=0
if [ -n "$PRIVACY_CT" ]; then
    # The record is the page: its record_template renders the controllers, purposes, recipients
    # and cookies from the same record the banner reads. Its sections are checked on the live page
    # (step 10), where ids built from variables are visible.
    RECORD_TEMPLATE=$(php -r '
        require "vendor/autoload.php";
        foreach (Symfony\Component\Yaml\Yaml::parseFile("config/bolt/contenttypes.yaml") as $key => $type) {
            if (($type["slug"] ?? $key) === $argv[1]) { echo $type["record_template"] ?? ""; }
        }' "$PRIVACY_CT" 2>/dev/null || true)
    if [ -z "$RECORD_TEMPLATE" ]; then
        fail "the '$PRIVACY_CT' ContentType has no record_template — the record must render the privacy page."
    elif [ ! -f "$THEME_DIR/$RECORD_TEMPLATE" ]; then
        fail "record_template $RECORD_TEMPLATE of '$PRIVACY_CT' not found in $THEME_DIR."
    else
        pass "page rendered from the '$PRIVACY_CT' record ($RECORD_TEMPLATE)."
        grep -rq "data-cookie-banner-defer" "$(dirname "$THEME_DIR/$RECORD_TEMPLATE")" \
            || warn "the banner may cover the privacy page — add <div data-cookie-banner-defer hidden></div> to $RECORD_TEMPLATE (PP-05)."
    fi
    if [ $HAS_CONSENT -eq 1 ]; then
        # shellcheck disable=SC2046
        grep -qE "setcontent [a-z_]+ = '$PRIVACY_CT'" $(theme_twig | grep -E "partials/(_master|_consent-mode|_cookie-banner)\.twig") 2>/dev/null \
            && pass "the layout reads the consent categories from the '$PRIVACY_CT' record (same data as the page)." \
            || warn "partials/_master.twig / _consent-mode.twig do not setcontent '$PRIVACY_CT' — the banner must read the same record as the page."
    fi
    CHECK_ANCHORS_LIVE=1
elif [ -f "$PAGE" ]; then
    pass "static-pages/gdpr.twig present."
    if grep -q "zasady-ochrany-osobnich-udaju" config/routes.yaml 2>/dev/null; then
        pass "route in config/routes.yaml."
    else
        fail "config/routes.yaml has no /zasady-ochrany-osobnich-udaju route — add the TemplateController routes above 'frontend:' (scaffold.sh does this)."
    fi
    grep -q "theme/privacy" "$PAGE" && pass "page rendered from theme.yaml privacy: (same data as the banner)." \
        || fail "the privacy page must render from theme.yaml privacy: — texts duplicated by hand drift from the banner."
    for anchor in spravce ucely prijemci prava namitka cookies kontakt historie-zmen; do
        grep -q "id=\"$anchor\"" "$PAGE" || fail "section #$anchor missing (mandatory content blocks / recommended order)."
    done
    grep -q "data-cookie-banner-defer" "$PAGE" || warn "the banner may cover the privacy page — add <div data-cookie-banner-defer hidden></div> (PP-05)."
else
    fail "static-pages/gdpr.twig missing (every website needs the privacy policy page)."
fi

# -------------------------------------------------------------
# 10. Translations and live checks
# -------------------------------------------------------------
echo "[10/10] Translations and live checks"
REQUIRED_KEYS=$(grep -o 'name="[^"]*"' "$EXAMPLES_DIR/translations.cs.xlf" | sed 's/name="//; s/"$//' | grep -E "^(cookie|privacy)\.")
for catalog in translations/messages.*.xlf; do
    [ -f "$catalog" ] || continue
    MISSING=""
    for key in $REQUIRED_KEYS; do
        grep -q "name=\"$key\"" "$catalog" || MISSING="$MISSING $key"
    done
    if [ -z "$MISSING" ]; then
        pass "$catalog has every cookie.* / privacy.* unit."
    elif [ "$catalog" = "$CS_XLF" ]; then
        fail "$catalog is missing:$(echo "$MISSING" | cut -c1-300) (merge with scripts/merge-xliff.php; Czech is mandatory, CB-23)."
    else
        warn "$catalog is missing:$(echo "$MISSING" | cut -c1-300)"
    fi
done
[ -f "$CS_XLF" ] || fail "$CS_XLF missing — all banner and policy texts must exist in Czech (CB-23)."

BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"
# 10 s: a production site on a cold cache (or behind a CDN) often needs more than 2 s; a closed
# port still fails at once.
if curl -s --max-time 10 "$BASE_URL" > /dev/null 2>&1; then
    HOME_HTML=$(curl -s --max-time 10 "$BASE_URL/" || true)
    if echo "$HOME_HTML" | grep -qE "<script[^>]+src=\"[^\"]*($TRACKER_RE)"; then
        fail "$BASE_URL/ loads a tracker script before consent (CB-01)."
    else
        pass "$BASE_URL/ loads no tracker script before consent (CB-01)."
    fi
    if [ $HAS_CONSENT -eq 1 ]; then
        echo "$HOME_HTML" | grep -q 'id="cookie-consent-config"' && pass "consent configuration rendered on $BASE_URL/." \
            || fail "$BASE_URL/ has no #cookie-consent-config (partials/_consent-mode.twig not rendered)."
    fi
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE_URL/zasady-ochrany-osobnich-udaju" || true)
    [ "$STATUS" = "200" ] && pass "/zasady-ochrany-osobnich-udaju returns 200." || fail "/zasady-ochrany-osobnich-udaju returns HTTP $STATUS."
    PAGE_HTML=$(curl -s --max-time 10 "$BASE_URL/zasady-ochrany-osobnich-udaju" || true)
    if echo "$PAGE_HTML" | grep -qE '\[(DOPLNIT|OVĚŘIT)'; then
        [ -n "$DRAFT" ] && warn "the live privacy page still shows placeholders." || fail "the live privacy page still shows [DOPLNIT] / [OVĚŘIT]."
    fi
    echo "$HOME_HTML" | grep -qE 'href="[^"]*/zasady-ochrany-osobnich-udaju"' && pass "$BASE_URL/ links /zasady-ochrany-osobnich-udaju (PP-01)." \
        || fail "$BASE_URL/ has no link to /zasady-ochrany-osobnich-udaju (PP-01)."
    if [ $CHECK_ANCHORS_LIVE -eq 1 ]; then
        MISSING_ANCHORS=""
        for anchor in spravce ucely prijemci prava namitka cookies kontakt historie-zmen; do
            echo "$PAGE_HTML" | grep -q "id=\"$anchor\"" || MISSING_ANCHORS="$MISSING_ANCHORS #$anchor"
        done
        [ -z "$MISSING_ANCHORS" ] && pass "the live privacy page has every mandatory section (#spravce … #historie-zmen)." \
            || fail "the live privacy page lacks section(s)$MISSING_ANCHORS (mandatory content blocks / recommended order)."
    fi

    # INV-01: every cookie the site sets itself is in the inventory. Bolt writes the locale into the
    # session on every /<locale>/ page (LocaleSubscriber), so a multilingual site sets a session
    # cookie on its secondary-locale pages even without forms — request those too.
    if [ "$CATEGORIES" != "unknown" ]; then
        DEFAULT_LOCALE=$(grep -E '^\s+locale:' config/services.yaml 2>/dev/null | head -n 1 | sed -E "s/.*locale:[[:space:]]*['\"]?([a-z_A-Z]+).*/\1/")
        COOKIE_PATHS="/ /zasady-ochrany-osobnich-udaju"
        for code in $(grep -E '^\s+app_locales:' config/services.yaml 2>/dev/null | head -n 1 | sed -E "s/.*app_locales:[[:space:]]*['\"]?([^'\"]*).*/\1/" | tr '|' ' '); do
            [ "$code" != "$DEFAULT_LOCALE" ] && COOKIE_PATHS="$COOKIE_PATHS /$code/"
        done
        SET_COOKIES=""
        for p in $COOKIE_PATHS; do
            for name in $(curl -s -o /dev/null -D - --max-time 10 "$BASE_URL$p" | tr -d '\r' | grep -iE '^set-cookie:' | sed -E 's/^[Ss][Ee][Tt]-[Cc][Oo][Oo][Kk][Ii][Ee]:[[:space:]]*([^=;]+)=.*/\1/'); do
                SET_COOKIES="$SET_COOKIES $name@$p"
            done
        done
        UNLISTED=""
        for entry in $SET_COOKIES; do
            name="${entry%@*}"
            listed=0
            for item in $(echo "$INVENTORY" | tr ',' ' '); do
                # shellcheck disable=SC2254
                case "$name" in $item) listed=1 ;; esac
            done
            [ $listed -eq 0 ] && UNLISTED="$UNLISTED $name (${entry#*@})"
        done
        if [ -z "$SET_COOKIES" ]; then
            pass "no cookie set by $COOKIE_PATHS."
        elif [ -z "$UNLISTED" ]; then
            pass "every cookie set by $COOKIE_PATHS is in the inventory (INV-01)."
        else
            fail "cookie(s) set by the site but missing from the inventory:$UNLISTED — list them as necessary items (INV-01). A session cookie on /<locale>/ pages comes from Bolt storing the locale in the session; describe it as such, with the session lifetime (framework.session.cookie_lifetime)."
        fi
    fi
else
    echo "  SKIPPED: $BASE_URL not reachable (set BOLT_BASE_URL / verify-all.sh --base-url=…)."
fi

echo "----------------------------------------------------------"
echo " Manual acceptance (references/guidelines.cs.md, Akceptační checklist), clean browser profile,"
echo " desktop and 360 px: DevTools shows no non-essential cookie / request before a choice; both"
echo " buttons visible at 360 px; Reject → reload → nothing; Accept → scripts + record; footer"
echo " \"Nastavení cookies\" → withdraw → cookies deleted; keyboard + screen reader in both layers."
echo "=========================================================="
if [ $FAILED -ne 0 ]; then
    echo " VERIFICATION FAILED ($FAILED critical error(s), $WARNINGS warning(s))"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo " VERIFICATION PASSED with $WARNINGS warning(s)."
    exit 0
else
    echo " VERIFICATION PASSED (All checks green)."
    exit 0
fi
