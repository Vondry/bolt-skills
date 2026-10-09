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

BOLT_CONFIG="config/bolt/config.yaml"
CT_FILE="config/bolt/contenttypes.yaml"

echo "=========================================================="
echo " Bolt CMS Cookie Consent & Privacy Policy Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Detect Active Theme
# -------------------------------------------------------------
echo -n "[1/7] Detecting active theme... "
ACTIVE_THEME="default"
if [ -f "$BOLT_CONFIG" ]; then
    FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$FOUND_THEME" ]; then
        ACTIVE_THEME="$FOUND_THEME"
    fi
fi

THEME_DIR="public/theme/$ACTIVE_THEME"
if [ ! -d "$THEME_DIR" ]; then
    echo "FAILED: Theme directory '$THEME_DIR' does not exist."
    exit 1
fi
echo "PASSED (Theme: '$ACTIVE_THEME')"

# -------------------------------------------------------------
# 2. Check Cookie Banner Template Existence
# -------------------------------------------------------------
echo -n "[2/7] Checking cookie banner template existence... "
BANNER_FILE=""
if [ -f "$THEME_DIR/partials/_cookie-banner.twig" ]; then
    BANNER_FILE="$THEME_DIR/partials/_cookie-banner.twig"
elif [ -f "$THEME_DIR/containers/cookie/_cookie-banner.twig" ]; then
    BANNER_FILE="$THEME_DIR/containers/cookie/_cookie-banner.twig"
elif [ -f "$THEME_DIR/components/cookie/_cookie-banner.twig" ]; then
    BANNER_FILE="$THEME_DIR/components/cookie/_cookie-banner.twig"
else
    FOUND=$(find "$THEME_DIR" -name "*cookie-banner*.twig" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND" ]; then
        BANNER_FILE="$FOUND"
    fi
fi

if [ -z "$BANNER_FILE" ]; then
    echo "FAILED: No _cookie-banner.twig found in $THEME_DIR."
    FAILED=1
else
    echo "PASSED ($BANNER_FILE)"
fi

# -------------------------------------------------------------
# 3. Check Cookie Banner Compliance (No Dark Patterns)
# -------------------------------------------------------------
echo -n "[3/7] Verifying banner compliance (Equal Reject/Accept, opt-in)... "
if [ -n "$BANNER_FILE" ]; then
    HAS_REJECT=0
    HAS_ACCEPT=0

    # Identifiers of a first-layer Reject / Accept control (ids, data attributes, translation keys, API names)
    if grep -q -E "(rejectCookies|rejectAll|cookie\.reject|cookie\.decline|cookie-btn-reject|cookie-banner\.reject|data-cookie-reject|data-cookie-decline)" "$BANNER_FILE"; then
        HAS_REJECT=1
    fi
    if grep -q -E "(acceptCookies|acceptAll|cookie\.accept|cookie\.allow|cookie-btn-accept|cookie-banner\.accept|data-cookie-accept)" "$BANNER_FILE"; then
        HAS_ACCEPT=1
    fi

    # Equal visual prominence: the Reject and Accept buttons must carry the same classes
    # (order-* utilities excluded). Compared when both buttons are identified by id.
    EQUAL_STYLE=$(php -r '
        $html = file_get_contents($argv[1]);
        $classes = [];
        foreach (["cookie-btn-reject", "cookie-btn-accept"] as $id) {
            if (! preg_match("~<button\b[^>]*\bid=\"" . $id . "\"[^>]*>~s", $html, $m)) { echo "UNKNOWN"; exit; }
            if (! preg_match("~\bclass=\"([^\"]*)\"~", $m[0], $c)) { echo "UNKNOWN"; exit; }
            $list = preg_split("~\s+~", trim($c[1]));
            $list = array_values(array_filter($list, fn ($x) => $x !== "" && ! preg_match("~^(\w+:)?order-~", $x)));
            sort($list);
            $classes[] = implode(" ", $list);
        }
        echo $classes[0] === $classes[1] ? "EQUAL" : "DIFFERENT";
    ' "$BANNER_FILE" 2>/dev/null || echo "UNKNOWN")

    if [ $HAS_REJECT -eq 0 ]; then
        echo "FAILED: Cookie banner is missing a clear 'Reject' (Odmítnout) option on the first layer."
        FAILED=1
    elif [ $HAS_ACCEPT -eq 0 ]; then
        echo "FAILED: Cookie banner is missing an 'Accept' option."
        FAILED=1
    elif [ "$EQUAL_STYLE" = "DIFFERENT" ]; then
        echo "FAILED: #cookie-btn-reject and #cookie-btn-accept are styled differently."
        echo "  Czech ÚOOÚ / EDPB guidance requires equal visual prominence: give both buttons the same classes"
        echo "  (only the label and the order-* utilities may differ)."
        FAILED=1
    elif [ "$EQUAL_STYLE" = "EQUAL" ]; then
        echo "PASSED (Reject and Accept on the first layer, identical styling)"
    else
        echo "PASSED (Reject and Accept options found on first layer)"
        echo "  Note: styling not compared — give the buttons id=\"cookie-btn-reject\" / id=\"cookie-btn-accept\" to enable the equal-prominence check."
    fi
else
    echo "SKIPPED"
fi

# -------------------------------------------------------------
# 4. Check Base Layout Inclusion
# -------------------------------------------------------------
echo -n "[4/7] Checking banner inclusion in base layout... "
INCLUDED=0
for master in "$THEME_DIR/partials/_master.twig" "$THEME_DIR/partials/_base.twig" "$THEME_DIR/_master.twig" "$THEME_DIR/_base.twig"; do
    if [ -f "$master" ] && grep -q -E "(_cookie-banner|cookieConsent)" "$master"; then
        INCLUDED=1
        break
    fi
done

if [ $INCLUDED -eq 1 ]; then
    echo "PASSED"
else
    echo "WARNING: Cookie banner does not appear to be included in _master.twig / _base.twig."
    WARNINGS=$((WARNINGS + 1))
fi

# -------------------------------------------------------------
# 5. Check Easy Revocation (Footer 'Nastavení cookies' link)
# -------------------------------------------------------------
echo -n "[5/7] Verifying consent revocation mechanism (resetCookieConsent)... "
REVOKE_CALLS=$(grep -rn -E "(resetCookieConsent|cookieConsent\.reset|data-cookie-settings)" "$THEME_DIR" --include="*.twig" --include="*.ts" --include="*.js" 2>/dev/null || true)

if [ -n "$REVOKE_CALLS" ]; then
    echo "PASSED (Found resetCookieConsent trigger in theme)"
else
    echo "WARNING: No 'resetCookieConsent()' trigger found in templates (e.g. footer link). Czech law requires consent withdrawal to be as easy as granting it."
    WARNINGS=$((WARNINGS + 1))
fi

# -------------------------------------------------------------
# 6. Check Privacy Policy Page Existence
# -------------------------------------------------------------
echo -n "[6/7] Checking Privacy Policy page (/zasady-ochrany-osobnich-udaju)... "
HAS_PRIVACY=0

# Check static page template
if [ -f "$THEME_DIR/static-pages/gdpr.twig" ] || [ -f "$THEME_DIR/pages/zasady/zasady.twig" ] || [ -f "$THEME_DIR/gdpr.twig" ]; then
    HAS_PRIVACY=1
fi

# Check ContentTypes singleton
if [ -f "$CT_FILE" ] && grep -q "zasady-ochrany-osobnich-udaju" "$CT_FILE"; then
    HAS_PRIVACY=1
fi

if [ $HAS_PRIVACY -eq 1 ]; then
    if [ -f "$THEME_DIR/static-pages/gdpr.twig" ] && ! grep -q "zasady-ochrany-osobnich-udaju" config/routes.yaml 2>/dev/null; then
        echo "FAILED: static-pages/gdpr.twig exists but config/routes.yaml has no /zasady-ochrany-osobnich-udaju route."
        echo "  Add the TemplateController routes above the 'frontend:' import (scripts/scaffold.sh does this)."
        FAILED=1
    else
        echo "PASSED (Privacy policy template/ContentType found)"
    fi
else
    echo "FAILED: Neither a gdpr/zasady template nor a 'zasady-ochrany-osobnich-udaju' ContentType was found."
    FAILED=1
fi

# -------------------------------------------------------------
# 7. Check Translation Catalogs
# -------------------------------------------------------------
echo -n "[7/7] Checking translation keys in translations/messages.cs.xlf... "
CS_XLF="translations/messages.cs.xlf"
if [ -f "$CS_XLF" ]; then
    HAS_COOKIE_TRANS=$(grep -c "cookie" "$CS_XLF" 2>/dev/null || true)
    HAS_COOKIE_TRANS=${HAS_COOKIE_TRANS:-0}
    HAS_PRIVACY_TRANS=$(grep -c "privacy" "$CS_XLF" 2>/dev/null || true)
    HAS_PRIVACY_TRANS=${HAS_PRIVACY_TRANS:-0}
    
    if [ "$HAS_COOKIE_TRANS" -gt 0 ] && [ "$HAS_PRIVACY_TRANS" -gt 0 ]; then
        echo "PASSED (Found $HAS_COOKIE_TRANS cookie and $HAS_PRIVACY_TRANS privacy units)"
    elif [ "$HAS_COOKIE_TRANS" -gt 0 ]; then
        echo "PASSED with notice (Found $HAS_COOKIE_TRANS cookie units; privacy content authored via ContentType singleton)"
    else
        echo "WARNING: Missing 'cookie' translation units in $CS_XLF."
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED (No $CS_XLF found)"
fi

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
