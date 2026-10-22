#!/usr/bin/env bash
set -e

# bolt-legal-cz verification. Requirement IDs refer to references/requirements.cs.md.
#   bash verify.sh [--draft] [--ares]
# --draft: report [DOPLNIT] placeholders as warnings (while the operator is still answering).
# --ares:  compare name, seat, register entry and VAT status with ARES (needs internet access).
# Live checks use BOLT_BASE_URL (set by verify-all.sh --base-url=…). Any other website can be
# checked without a project: php check-site.php --url=https://… (see its header).

DRAFT=""
ARES=""
for arg in "$@"; do
    case "$arg" in
        --draft) DRAFT="--draft" ;;
        --ares) ARES="--ares" ;;
        *) echo "Usage: verify.sh [--draft] [--ares]"; exit 1 ;;
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
echo " Bolt CMS Legal Information Verification (Czech Republic)"
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
echo "[1/7] Active theme"
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
# 2. Data in theme.yaml (contact: identity, legal: profile)
# -------------------------------------------------------------
echo "[2/7] theme.yaml contact: and legal: data${ARES:+ (with ARES)}"
OPERATOR="unknown"; CONSUMERS=0; ONLINE=0; REVIEWS=0; EXPECT_ICO=""; EXPECT_NAME=""
if [ ! -f "$THEME_DIR/theme.yaml" ]; then
    fail "$THEME_DIR/theme.yaml not found."
elif [ ! -f vendor/autoload.php ]; then
    warn "vendor/autoload.php missing (run composer install) — theme.yaml data not validated."
else
    while IFS= read -r line; do
        case "$line" in
            FAIL:*) fail "${line#FAIL: }" ;;
            WARN:*) warn "${line#WARN: }" ;;
            OK:*) pass "${line#OK: }" ;;
            PROFILE:*) read -r OPERATOR CONSUMERS ONLINE REVIEWS <<< "${line#PROFILE: }" ;;
            EXPECT_ICO:*) EXPECT_ICO="${line#EXPECT_ICO:}"; EXPECT_ICO="${EXPECT_ICO# }" ;;
            EXPECT_NAME:*) EXPECT_NAME="${line#EXPECT_NAME:}"; EXPECT_NAME="${EXPECT_NAME# }" ;;
            *) [ -n "$line" ] && warn "$line" ;;
        esac
    done < <(php "$SCRIPT_DIR/check-legal.php" "$THEME_DIR/theme.yaml" $DRAFT $ARES 2>&1)
fi
echo "  INFO: profile — operator $OPERATOR, consumers $CONSUMERS, online contracts $ONLINE, reviews $REVIEWS"

theme_twig() { find "$THEME_DIR" -name "*.twig" -not -path "*/node_modules/*" 2>/dev/null; }

# -------------------------------------------------------------
# 3. Identity on every page (ID-05)
# -------------------------------------------------------------
echo "[3/7] Identity partial on every page"
PARTIAL="$THEME_DIR/partials/_legal-identity.twig"
if [ -f "$PARTIAL" ]; then
    pass "partials/_legal-identity.twig present."
    grep -q "theme/contact" "$PARTIAL" && grep -q "theme/legal" "$PARTIAL" \
        && pass "rendered from theme.yaml contact: and legal: (AG-04)." \
        || fail "partials/_legal-identity.twig must read theme.yaml contact: and legal: — facts typed into the template drift (AG-04)."
    # Bolt returns theme.yaml blocks as collections: a key set to ~ (dic: ~) throws on access and
    # every page answers 500. The current partial converts them with toArray() first.
    grep -q "toArray()" "$PARTIAL" \
        || fail "partials/_legal-identity.twig reads theme.yaml without toArray() — with dic: ~ (or any ~ value) every page answers 500. Copy examples/_legal-identity.twig."
    INCLUDED_IN=$(grep -rlE "_legal-identity\.twig" "$THEME_DIR" --include="*.twig" --exclude-dir=node_modules 2>/dev/null | grep -v "partials/_legal-identity.twig" || true)
    if echo "$INCLUDED_IN" | grep -qiE "footer|_master\.twig"; then
        pass "included in $(echo "$INCLUDED_IN" | grep -iE "footer|_master\.twig" | head -n 1) (every page)."
    elif [ -n "$INCLUDED_IN" ]; then
        warn "partials/_legal-identity.twig is included only in $(echo "$INCLUDED_IN" | tr '\n' ' ')— put it in the footer so every page has it (ID-05)."
    else
        fail "partials/_legal-identity.twig is not included anywhere — add it to the footer (ID-05)."
    fi
else
    fail "partials/_legal-identity.twig missing — run scaffold.sh (ID-01–ID-05)."
fi

# -------------------------------------------------------------
# 4. No legal facts typed into templates (AG-04), no ODR link (SP-02)
# -------------------------------------------------------------
echo "[4/7] Templates and catalogs"
HARDCODED=$(grep -rnE "I[ČC]O?[[:space:]]*:?[[:space:]]*[0-9]{8}" "$THEME_DIR" --include="*.twig" --exclude-dir=node_modules 2>/dev/null | grep -v "partials/_legal-identity.twig" || true)
if [ -n "$HARDCODED" ]; then
    warn "IČO typed into a template — render it from theme.yaml contact.ico instead (AG-04):"
    echo "$HARDCODED" | head -5 | sed 's/^/    /'
else
    pass "no IČO typed into templates."
fi
ODR=$(grep -rnE "ec\.europa\.eu/consumers/odr" "$THEME_DIR" translations config --include="*.twig" --include="*.xlf" --include="*.yaml" --include="*.md" 2>/dev/null | grep -v node_modules || true)
if [ -n "$ODR" ]; then
    fail "link to the EU ODR platform (closed on 20. 7. 2025) — remove it (SP-02):"
    echo "$ODR" | head -5 | sed 's/^/    /'
else
    pass "no link to the closed EU ODR platform in templates, catalogs or config (SP-02)."
fi

# -------------------------------------------------------------
# 5. Reviews notice (SP-06)
# -------------------------------------------------------------
echo "[5/7] Reviews and testimonials"
REVIEW_FILES=$(theme_twig | grep -iE "review|testimonial|recenz|referenc" | grep -v "_reviews-notice.twig" || true)
if [ "$REVIEWS" = "1" ]; then
    [ -f "$THEME_DIR/partials/_reviews-notice.twig" ] || fail "partials/_reviews-notice.twig missing (SP-06)."
    if [ -z "$REVIEW_FILES" ]; then
        warn "legal.reviews.shown is true, but no review / testimonial template found by name — include partials/_reviews-notice.twig below every block that shows reviews (SP-06)."
    fi
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        grep -q "_reviews-notice.twig" "$file" && pass "$file includes the reviews notice (SP-06)." \
            || fail "$file shows reviews without partials/_reviews-notice.twig (SP-06, § 5a ZOS)."
    done <<< "$REVIEW_FILES"
elif [ -n "$REVIEW_FILES" ]; then
    warn "review / testimonial templates found ($(echo "$REVIEW_FILES" | tr '\n' ' ')) but legal.reviews.shown is false — confirm with the operator (SP-06)."
else
    pass "no reviews shown."
fi

# -------------------------------------------------------------
# 6. Translations
# -------------------------------------------------------------
echo "[6/7] Translations"
REQUIRED_KEYS=$(grep -o 'name="[^"]*"' "$EXAMPLES_DIR/translations.cs.xlf" | sed 's/name="//; s/"$//' | grep -E "^legal\.")
CS_XLF="translations/messages.cs.xlf"
for catalog in translations/messages.*.xlf; do
    [ -f "$catalog" ] || continue
    MISSING=""
    for key in $REQUIRED_KEYS; do
        grep -q "name=\"$key\"" "$catalog" || MISSING="$MISSING $key"
    done
    if [ -z "$MISSING" ]; then
        pass "$catalog has every legal.* unit."
    elif [ "$catalog" = "$CS_XLF" ]; then
        fail "$catalog is missing:$MISSING (merge with scripts/merge-xliff.php; Czech is mandatory, SP-07)."
    else
        warn "$catalog is missing:$MISSING"
    fi
done
[ -f "$CS_XLF" ] || fail "$CS_XLF missing — the legal texts must exist in Czech (SP-07)."

# -------------------------------------------------------------
# 7. Live website
# -------------------------------------------------------------
echo "[7/7] Live website"
BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"
# 10 s: a production site on a cold cache (or behind a CDN) often needs more than 2 s; a closed
# port still fails at once.
if curl -s --max-time 10 "$BASE_URL" > /dev/null 2>&1; then
    SITE_ARGS=("--url=$BASE_URL" "--pages=10")
    [ -n "$EXPECT_ICO" ] && SITE_ARGS+=("--ico=$EXPECT_ICO")
    [ -n "$EXPECT_NAME" ] && SITE_ARGS+=("--name=$EXPECT_NAME")
    [ "$OPERATOR" != "unknown" ] && SITE_ARGS+=("--operator=$OPERATOR")
    if [ "$CONSUMERS" = "1" ]; then SITE_ARGS+=("--consumers"); else SITE_ARGS+=("--no-consumers"); fi
    [ "$ONLINE" = "1" ] && SITE_ARGS+=("--online-contracts")
    [ "$REVIEWS" = "1" ] && SITE_ARGS+=("--reviews")
    [ -n "$ARES" ] && SITE_ARGS+=("--ares")
    while IFS= read -r line; do
        case "$line" in
            FAIL:*) fail "$BASE_URL: ${line#FAIL: }" ;;
            WARN:*) warn "$BASE_URL: ${line#WARN: }" ;;
            OK:*) pass "${line#OK: }" ;;
            INFO:*) echo "  INFO: ${line#INFO: }" ;;
        esac
    done < <(php "$SCRIPT_DIR/check-site.php" "${SITE_ARGS[@]}" 2>&1 || true)
else
    echo "  SKIPPED: $BASE_URL not reachable (set BOLT_BASE_URL / verify-all.sh --base-url=…)."
fi

echo "----------------------------------------------------------"
echo " Manual (references/requirements.cs.md, Akceptační checklist): identity matches ARES (--ares);"
echo " consumer sites: ADR with web address, where to complain, prices with VAT, discounts with the"
echo ' 30-day lowest price; online shops: terms, „Objednávka zavazující k platbě“, withdrawal notice'
echo ' and form, „Odstoupit od smlouvy“ button with e-mail confirmation (from 1. 1. 2027),'
echo " accessibility unless a microenterprise; whistleblowing page for obliged entities."
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
