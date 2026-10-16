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
# -k: the probes below test the application, not TLS; the certificate of each host is checked
# separately (without -k) in the host checks.
CURL=(curl -s -k --max-time 15)

# Host part of a URL (no scheme, port or path).
url_host() { local h="${1#*://}"; h="${h%%/*}"; echo "${h%%:*}"; }

# A public domain gets the www / bare-domain checks; localhost, IPs and .test / .local do not.
is_public_host() {
    local url="$1" host
    host="$(url_host "$url")"
    case "${url#*://}" in *:[0-9]*) return 1 ;; esac
    case "$host" in localhost|*.localhost|*.test|*.local|*.ddev.site) return 1 ;; esac
    echo "$host" | grep -qE '^[0-9.]+$|:' && return 1
    echo "$host" | grep -q '\.'
}

# Application checks against one host. $1 = base URL, $2 = label prefixed to every message.
app_checks() {
    local url="$1" label="$2" status path leaks cookie
    # Foreign Host header: Symfony must refuse it (400) — or the web server never routes it here.
    status=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -H "Host: bolt-security-probe.invalid" "$url/" || true)
    case "$status" in
        400|403|404|421) pass "${label}foreign Host header refused (HTTP $status)" ;;
        2*) fail "${label}a request with 'Host: bolt-security-probe.invalid' answers $status — password-reset links can point to any domain. Set SYMFONY_TRUSTED_HOSTS." ;;
        3*) warn "${label}a foreign Host header is redirected ($status) before reaching Bolt — repeat the check with the https:// URL." ;;
        *) warn "${label}a foreign Host header answers $status — check by hand." ;;
    esac

    # Debug tools must not exist in production.
    for path in /_profiler /_wdt/probe; do
        status=$("${CURL[@]}" -o "$TMP/body" -w '%{http_code}' "$url$path" || true)
        if [ "$status" = "200" ] || grep -q "sf-toolbar\|Symfony Profiler" "$TMP/body" 2>/dev/null; then
            fail "${label}$path answers $status — the site runs with APP_ENV=dev. Set APP_ENV=prod on the server."
        fi
    done
    "${CURL[@]}" -D "$TMP/home.headers" -o "$TMP/home.html" "$url/" || true
    if grep -qi "^x-debug-token" "$TMP/home.headers"; then
        fail "${label}the homepage sends X-Debug-Token — the profiler is active (APP_ENV=dev / APP_DEBUG=1)."
    else
        pass "${label}no profiler, no debug token"
    fi

    # Error pages must not show stack traces.
    "${CURL[@]}" -o "$TMP/404.html" "$url/bolt-security-probe-$$" || true
    if grep -qE "Stack Trace|sf-dump|Symfony\\\\Component|vendor/symfony" "$TMP/404.html"; then
        fail "${label}the 404 page shows a stack trace / Symfony internals — APP_DEBUG must be 0."
    else
        pass "${label}404 page shows no stack trace"
    fi

    # Files that must never download.
    leaks=0
    for path in /.env /.env.local /composer.json /composer.lock /var/data/bolt.sqlite /config/bolt/config.yaml /.git/config "/theme/${THEME:-default}/theme.yaml"; do
        status=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$url$path" || true)
        if [ "$status" = "200" ]; then
            fail "${label}$path is downloadable (HTTP 200) — see bolt-htaccess (document root / allowlist)."
            leaks=$((leaks + 1))
        fi
    done
    [ $leaks -eq 0 ] && pass "${label}no secret or source file downloadable (.env, composer.*, database, config, .git, theme.yaml)"

    # Headers of a page.
    if grep -qi "^x-frame-options" "$TMP/home.headers" || grep -qiE "^content-security-policy:.*frame-ancestors" "$TMP/home.headers"; then
        pass "${label}clickjacking protection on pages (X-Frame-Options / frame-ancestors)"
    else
        fail "${label}pages send neither X-Frame-Options nor CSP frame-ancestors — the site can be framed (nelmio_security)."
    fi
    grep -qi "^x-content-type-options: *nosniff" "$TMP/home.headers" || warn "${label}pages send no 'X-Content-Type-Options: nosniff'."
    grep -qi "^content-security-policy:" "$TMP/home.headers" || warn "${label}pages send no Content-Security-Policy (Step 6, examples/nelmio_security.yaml)."
    # HSTS of public domains is checked per host above.
    if [ -z "$HOSTS_CHECKED" ]; then
        case "$url" in
            https://*) grep -qi "^strict-transport-security" "$TMP/home.headers" || warn "${label}no Strict-Transport-Security header (bolt-htaccess security headers)." ;;
        esac
    fi
    if grep -qi "^x-powered-by" "$TMP/home.headers"; then
        warn "${label}the homepage sends $(grep -i '^x-powered-by' "$TMP/home.headers" | tr -d '\r') — hide it (headers.powered_by: false, .htaccess 'Header unset X-Powered-By', expose_php off)."
    fi
    grep -qi '<meta name="generator"' "$TMP/home.html" && warn "${label}the homepage names Bolt in <meta name=\"generator\"> (omit_meta_generator_tag: true)."

    # Session cookie of the login page.
    "${CURL[@]}" -D "$TMP/login.headers" -o /dev/null "$url/bolt/login" || true
    cookie=$(grep -i "^set-cookie:" "$TMP/login.headers" | head -n 1 | tr -d '\r' || true)
    if [ -n "$cookie" ]; then
        echo "$cookie" | grep -qi "httponly" || warn "${label}the session cookie lacks HttpOnly."
        case "$url" in
            https://*) echo "$cookie" | grep -qi "secure" || warn "${label}the session cookie lacks the Secure flag (session.cookie_secure: true)." ;;
        esac
        echo "$cookie" | grep -qi "httponly" && pass "${label}session cookie: $(echo "$cookie" | grep -oiE '(secure|httponly|samesite=[a-z]+)' | tr '\n' ' ')"
    fi

    # /_fragment: 403 means the fragment listener is active (it only rejects unsigned requests).
    status=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$url/_fragment?_path=probe" || true)
    if [ "$status" = "403" ]; then
        warn "${label}/_fragment exists (HTTP 403) — disable framework fragments / esi (examples/security_hardening.yaml)."
    else
        pass "${label}/_fragment does not exist (HTTP $status)"
    fi

    # An upload: nosniff and the sandbox policy (served by Apache / Nginx, not PHP).
    if [ -n "$UPLOAD" ]; then
        status=$("${CURL[@]}" -D "$TMP/upload.headers" -o /dev/null -w '%{http_code}' "$url/files/$UPLOAD" || true)
        if [ "$status" = "200" ]; then
            if grep -qiE "^content-security-policy:.*sandbox" "$TMP/upload.headers"; then
                pass "${label}uploads are served with the sandbox policy (/files/$UPLOAD)"
            else
                warn "${label}uploads are served without the sandbox Content-Security-Policy (/files/$UPLOAD) — bolt-htaccess security headers (Apache) or examples/docker/nginx_security.conf."
            fi
            grep -qi "^x-content-type-options: *nosniff" "$TMP/upload.headers" || warn "${label}uploads are served without 'X-Content-Type-Options: nosniff'."
        else
            echo "  - ${label}/files/$UPLOAD answers $status on this server (local file not deployed?) — upload headers not checked."
        fi
    fi
}

HOSTS_CHECKED=""
if ! "${CURL[@]}" -o /dev/null "$BASE_URL/" 2>/dev/null; then
    echo "  SKIPPED ($BASE_URL not reachable — set BOLT_BASE_URL to this project's running site)"
else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    THEME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d "\"'")
    UPLOAD=$(cd public/files 2>/dev/null && find . -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) 2>/dev/null | grep -E '^\./[A-Za-z0-9._/-]+$' | head -n 1 | sed 's#^\./##' || true)

    if ! is_public_host "$BASE_URL"; then
        echo "  Target: $BASE_URL"
        app_checks "$BASE_URL" ""
    else
        # A public domain: both the bare domain and www must answer over valid HTTPS, plain HTTP
        # must redirect, and exactly one host may serve the site (the other redirects to it).
        HOSTS_CHECKED=1
        BARE="$(url_host "$BASE_URL")"
        BARE="${BARE#www.}"
        SERVING=()
        for HOST in "$BARE" "www.$BARE"; do
            echo "  Host: $HOST"
            CERT_STATUS=0
            curl -s -o /dev/null --max-time 15 "https://$HOST/" 2>/dev/null || CERT_STATUS=$?
            case "$CERT_STATUS" in
                0) pass "https://$HOST/ — valid certificate" ;;
                6) warn "$HOST does not resolve (no DNS record) — visitors who type it get an error. Add DNS, a certificate and the redirect." ; continue ;;
                35|51|58|60) fail "https://$HOST/ has no valid certificate (curl error $CERT_STATUS) — browsers block the site on this host." ; continue ;;
                *) warn "https://$HOST/ did not answer (curl error $CERT_STATUS)." ; continue ;;
            esac

            HTTP_RESULT=$(curl -s -o /dev/null --max-time 15 -w '%{http_code} %{redirect_url}' "http://$HOST/" 2>/dev/null || true)
            case "$HTTP_RESULT" in
                30[18]\ https://*) pass "http://$HOST/ redirects to HTTPS (${HTTP_RESULT%% *} → ${HTTP_RESULT#* })" ;;
                30[27]\ https://*) warn "http://$HOST/ redirects to HTTPS only temporarily (${HTTP_RESULT%% *}) — use 301." ;;
                *) fail "http://$HOST/ is not redirected to HTTPS (got: ${HTTP_RESULT:-no answer}) — bolt-htaccess Step 1." ;;
            esac

            "${CURL[@]}" -D "$TMP/host.headers" -o /dev/null "https://$HOST/" || true
            HOST_STATUS=$(head -n 1 "$TMP/host.headers" | awk '{print $2}')
            grep -qi "^strict-transport-security" "$TMP/host.headers" || warn "https://$HOST/ sends no Strict-Transport-Security header (bolt-htaccess, root .htaccess for redirects)."
            case "$HOST_STATUS" in
                2*) SERVING+=("$HOST") ;;
                30[18])
                    TARGET=$(grep -i "^location:" "$TMP/host.headers" | head -n 1 | tr -d '\r' | sed -E 's/^[Ll]ocation:[[:space:]]*//')
                    case "$TARGET" in
                        https://$BARE/*|https://www.$BARE/*) pass "https://$HOST/ redirects to the canonical host ($TARGET)" ;;
                        *) warn "https://$HOST/ redirects to an unexpected place: $TARGET" ;;
                    esac
                    ;;
                *) warn "https://$HOST/ answers $HOST_STATUS." ;;
            esac
        done

        if [ ${#SERVING[@]} -gt 1 ]; then
            warn "both $BARE and www.$BARE serve the site — every page exists twice and sessions / HSTS are split. Redirect one to the other (bolt-htaccess Step 1) and set BOLT_CANONICAL."
        elif [ ${#SERVING[@]} -eq 1 ]; then
            pass "canonical host: ${SERVING[0]} (the other host redirects to it)"
        fi

        # The application checks run on every host that serves the site.
        for HOST in "${SERVING[@]}"; do
            echo "  Application checks on https://$HOST"
            if [ ${#SERVING[@]} -gt 1 ]; then
                app_checks "https://$HOST" "[$HOST] "
            else
                app_checks "https://$HOST" ""
            fi
        done
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
