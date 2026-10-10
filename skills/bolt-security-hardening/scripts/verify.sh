#!/usr/bin/env bash
set -e

# bolt-security-hardening verification: configuration files (sections 1–6, scripts/check-config.php),
# dependencies (7) and live probes against the running site (8, needs BOLT_BASE_URL).

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

echo "=========================================================="
echo " Bolt CMS Security Hardening Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0
SECTION=0
TOTAL_SECTIONS=8

section() { SECTION=$((SECTION + 1)); echo ""; echo "[$SECTION/$TOTAL_SECTIONS] $1"; }
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ✗ FAILED: $1"; FAILED=$((FAILED + 1)); }

# -------------------------------------------------------------
# 1–6. Configuration files
# -------------------------------------------------------------
while IFS= read -r line; do
    kind="${line%% *}"
    message="${line#* }"
    case "$kind" in
        SECTION) section "$message" ;;
        PASS) pass "$message" ;;
        WARN) warn "$message" ;;
        FAIL) fail "$message" ;;
        *) [ -n "$line" ] && echo "  $line" ;;
    esac
done < <(php "$SCRIPT_DIR/check-config.php" "$BASE_DIR" 2>&1)
SECTION=6

# -------------------------------------------------------------
# 7. Dependencies
# -------------------------------------------------------------
section "Dependencies (composer audit, Bolt version)"

if [ -f composer.lock ]; then
    BOLT_VERSION=$(php -r '$l = json_decode(file_get_contents("composer.lock"), true);
        foreach ($l["packages"] ?? [] as $p) { if ($p["name"] === "bolt/core") { echo ltrim($p["version"], "v"); } }' 2>/dev/null || true)
    if [ -n "$BOLT_VERSION" ] && [ "${BOLT_VERSION%%.*}" -lt 6 ] 2>/dev/null; then
        warn "bolt/core $BOLT_VERSION — Bolt 5 and older have no login throttling in security.yaml and are not what the skills target; upgrade to Bolt 6."
    elif [ -n "$BOLT_VERSION" ]; then
        pass "bolt/core $BOLT_VERSION"
    fi
fi

if command -v composer > /dev/null 2>&1 && [ -f composer.lock ]; then
    AUDIT_OUTPUT=$(composer audit --locked --no-interaction 2>&1 || true)
    if echo "$AUDIT_OUTPUT" | grep -qi "No security vulnerability advisories found"; then
        pass "composer audit: no security advisories"
    elif echo "$AUDIT_OUTPUT" | grep -qiE "Found [0-9]+ security vulnerability advisor"; then
        COUNT=$(echo "$AUDIT_OUTPUT" | grep -oiE "Found [0-9]+ security vulnerability advisor" | grep -oE "[0-9]+" | head -n 1)
        warn "composer audit: $COUNT security advisory(ies) — run 'composer audit' for the packages and update them (composer update <package>)."
    else
        echo "  - composer audit could not run (offline?) — run it manually."
    fi
else
    echo "  - composer or composer.lock not available — run 'composer audit' manually."
fi

# -------------------------------------------------------------
# 8. Live probes
# -------------------------------------------------------------
section "Live checks against the running site"

BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"  # set BOLT_BASE_URL to this project's running site
BASE_URL="${BASE_URL%/}"
CURL=(curl -s -k --max-time 15)

if ! "${CURL[@]}" -o /dev/null "$BASE_URL/" 2>/dev/null; then
    echo "  SKIPPED ($BASE_URL not reachable — set BOLT_BASE_URL to this project's running site)"
else
    echo "  Target: $BASE_URL"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    # Foreign Host header: Symfony must refuse it (400) — or the web server never routes it here.
    STATUS=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -H "Host: bolt-security-probe.invalid" "$BASE_URL/" || true)
    case "$STATUS" in
        400|403|404|421) pass "foreign Host header refused (HTTP $STATUS)" ;;
        2*) fail "a request with 'Host: bolt-security-probe.invalid' answers $STATUS — password-reset links can point to any domain. Set SYMFONY_TRUSTED_HOSTS." ;;
        3*) warn "a foreign Host header is redirected ($STATUS) before reaching Bolt — repeat the check with the https:// URL." ;;
        *) warn "a foreign Host header answers $STATUS — check by hand." ;;
    esac

    # Debug tools must not exist in production.
    for path in /_profiler /_wdt/probe; do
        STATUS=$("${CURL[@]}" -o "$TMP/body" -w '%{http_code}' "$BASE_URL$path" || true)
        if [ "$STATUS" = "200" ] || grep -q "sf-toolbar\|Symfony Profiler" "$TMP/body" 2>/dev/null; then
            fail "$path answers $STATUS — the site runs with APP_ENV=dev. Set APP_ENV=prod on the server."
        fi
    done
    "${CURL[@]}" -D "$TMP/home.headers" -o "$TMP/home.html" "$BASE_URL/" || true
    if grep -qi "^x-debug-token" "$TMP/home.headers"; then
        fail "the homepage sends X-Debug-Token — the profiler is active (APP_ENV=dev / APP_DEBUG=1)."
    else
        pass "no profiler, no debug token"
    fi

    # Error pages must not show stack traces.
    "${CURL[@]}" -o "$TMP/404.html" "$BASE_URL/bolt-security-probe-$$" || true
    if grep -qE "Stack Trace|sf-dump|Symfony\\\\Component|vendor/symfony" "$TMP/404.html"; then
        fail "the 404 page shows a stack trace / Symfony internals — APP_DEBUG must be 0."
    else
        pass "404 page shows no stack trace"
    fi

    # Files that must never download.
    THEME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d "\"'")
    LEAKS=0
    for path in /.env /.env.local /composer.json /composer.lock /var/data/bolt.sqlite /config/bolt/config.yaml /.git/config "/theme/${THEME:-default}/theme.yaml"; do
        STATUS=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$BASE_URL$path" || true)
        if [ "$STATUS" = "200" ]; then
            fail "$path is downloadable (HTTP 200) — see bolt-htaccess (document root / allowlist)."
            LEAKS=$((LEAKS + 1))
        fi
    done
    [ $LEAKS -eq 0 ] && pass "no secret or source file downloadable (.env, composer.*, database, config, .git, theme.yaml)"

    # Headers of a page.
    if grep -qi "^x-frame-options" "$TMP/home.headers" || grep -qiE "^content-security-policy:.*frame-ancestors" "$TMP/home.headers"; then
        pass "clickjacking protection on pages (X-Frame-Options / frame-ancestors)"
    else
        fail "pages send neither X-Frame-Options nor CSP frame-ancestors — the site can be framed (nelmio_security)."
    fi
    grep -qi "^x-content-type-options: *nosniff" "$TMP/home.headers" || warn "pages send no 'X-Content-Type-Options: nosniff'."
    grep -qi "^content-security-policy:" "$TMP/home.headers" || warn "pages send no Content-Security-Policy (Step 6, examples/nelmio_security.yaml)."
    case "$BASE_URL" in
        https://*) grep -qi "^strict-transport-security" "$TMP/home.headers" || warn "no Strict-Transport-Security header (bolt-htaccess security headers)." ;;
    esac
    if grep -qi "^x-powered-by" "$TMP/home.headers"; then
        warn "the homepage sends $(grep -i '^x-powered-by' "$TMP/home.headers" | tr -d '\r') — hide it (headers.powered_by: false, .htaccess 'Header unset X-Powered-By', expose_php off)."
    fi
    grep -qi '<meta name="generator"' "$TMP/home.html" && warn "the homepage names Bolt in <meta name=\"generator\"> (omit_meta_generator_tag: true)."

    # Session cookie of the login page.
    "${CURL[@]}" -D "$TMP/login.headers" -o /dev/null "$BASE_URL/bolt/login" || true
    COOKIE=$(grep -i "^set-cookie:" "$TMP/login.headers" | head -n 1 | tr -d '\r' || true)
    if [ -n "$COOKIE" ]; then
        echo "$COOKIE" | grep -qi "httponly" || warn "the session cookie lacks HttpOnly."
        case "$BASE_URL" in
            https://*) echo "$COOKIE" | grep -qi "secure" || warn "the session cookie lacks the Secure flag (session.cookie_secure: true)." ;;
        esac
        echo "$COOKIE" | grep -qi "httponly" && pass "session cookie: $(echo "$COOKIE" | grep -oiE '(secure|httponly|samesite=[a-z]+)' | tr '\n' ' ')"
    fi

    # /_fragment: 403 means the fragment listener is active (it only rejects unsigned requests).
    STATUS=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$BASE_URL/_fragment?_path=probe" || true)
    if [ "$STATUS" = "403" ]; then
        warn "/_fragment exists (HTTP 403) — disable framework fragments / esi (examples/security_hardening.yaml)."
    else
        pass "/_fragment does not exist (HTTP $STATUS)"
    fi

    # An upload: nosniff and the sandbox policy (served by Apache / Nginx, not PHP).
    UPLOAD=$(cd public/files 2>/dev/null && find . -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) 2>/dev/null | grep -E '^\./[A-Za-z0-9._/-]+$' | head -n 1 | sed 's#^\./##' || true)
    if [ -n "$UPLOAD" ]; then
        STATUS=$("${CURL[@]}" -D "$TMP/upload.headers" -o /dev/null -w '%{http_code}' "$BASE_URL/files/$UPLOAD" || true)
        if [ "$STATUS" = "200" ]; then
            if grep -qiE "^content-security-policy:.*sandbox" "$TMP/upload.headers"; then
                pass "uploads are served with the sandbox policy (/files/$UPLOAD)"
            else
                warn "uploads are served without the sandbox Content-Security-Policy (/files/$UPLOAD) — bolt-htaccess security headers (Apache) or examples/docker/nginx_security.conf."
            fi
            grep -qi "^x-content-type-options: *nosniff" "$TMP/upload.headers" || warn "uploads are served without 'X-Content-Type-Options: nosniff'."
        else
            echo "  - /files/$UPLOAD answers $STATUS on this server (local file not deployed?) — upload headers not checked."
        fi
    fi
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo " No open security defect found."
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED ($FAILED failure(s), $WARNINGS warning(s))"
    echo " Fix the failures above — each line names the step of SKILL.md."
    echo "=========================================================="
    exit 1
fi
