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
echo " Bolt CMS Apache .htaccess & Security Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0
ROOT_HTACCESS=".htaccess"
PUBLIC_HTACCESS="public/.htaccess"
HAS_INDEX_PHP_REDIRECT=""

# -------------------------------------------------------------
# 1. Check Root .htaccess (Tier 1: HTTPS & public/ rewrite)
# -------------------------------------------------------------
echo -n "[1/6] Checking root .htaccess... "

if [ ! -f "$ROOT_HTACCESS" ]; then
    echo "FAILED"
    echo "  Error: Root .htaccess file does not exist at $BASE_DIR/.htaccess"
    echo "  (Not needed when the vhost's document root is public/ — then skip this skill's root check.)"
    FAILED=1
else
    HAS_REWRITE_ENGINE=$(grep -i -E "^\s*RewriteEngine\s+on" "$ROOT_HTACCESS" || true)
    HAS_PUBLIC_REDIRECT=$(grep -F "public/\$1" "$ROOT_HTACCESS" || true)
    HAS_HTTPS_REDIRECT=$(grep -E "https://%\{HTTP_HOST\}" "$ROOT_HTACCESS" || true)

    if [ -n "$HAS_REWRITE_ENGINE" ] && [ -n "$HAS_PUBLIC_REDIRECT" ] && [ -n "$HAS_HTTPS_REDIRECT" ]; then
        echo "PASSED"
    else
        echo "FAILED"
        [ -z "$HAS_REWRITE_ENGINE" ] && echo "  - Missing 'RewriteEngine on'"
        [ -z "$HAS_HTTPS_REDIRECT" ] && echo "  - Missing HTTPS redirect rule"
        [ -z "$HAS_PUBLIC_REDIRECT" ] && echo "  - Missing redirect to public/ ('RewriteRule (.*) public/\$1 [QSA,L]')"
        FAILED=1
    fi
fi

# The X-Forwarded-Proto condition must be negative (!https): `^http$` never matches on hosts
# without a TLS proxy, so plain HTTP would never be redirected.
if [ -f "$ROOT_HTACCESS" ] && grep -qE 'X-Forwarded-Proto\}[[:space:]]+\^http\$' "$ROOT_HTACCESS"; then
    echo "  WARNING: root .htaccess uses 'RewriteCond %{HTTP:X-Forwarded-Proto} ^http\$' — without a proxy"
    echo "           plain HTTP is never redirected. Use: RewriteCond %{HTTPS} off + RewriteCond %{HTTP:X-Forwarded-Proto} !https"
    WARNINGS=$((WARNINGS + 1))
fi

# Canonical host: www and the bare domain must not both serve the site (Step 1). The rule may sit in
# the root file or, with the document root on public/, in public/.htaccess.
if ! grep -qsE 'RewriteCond[[:space:]]+%\{HTTP_HOST\}[[:space:]]+!?\^www' "$ROOT_HTACCESS" "$PUBLIC_HTACCESS"; then
    echo "  WARNING: no canonical-host redirect (www → bare domain or back) — both hosts serve the site."
    echo "           Add the RewriteCond %{HTTP_HOST} ^www\\.(.+)\$ rule of examples/root.htaccess (SKILL.md Step 1)."
    WARNINGS=$((WARNINGS + 1))
fi

# Redirect targets are built from $1, never from %{REQUEST_URI}: on hosts that serve the domain from a
# webroot subfolder (WEDOS www/domains/<domain>/), REQUEST_URI carries that prefix and www.example.cz
# redirects to https://example.cz/domains/example.cz/ (Pitfall 9).
BAD_REDIRECTS=$(grep -nsE '^[[:space:]]*RewriteRule[[:space:]].*%\{REQUEST_URI\}.*R=30' "$ROOT_HTACCESS" "$PUBLIC_HTACCESS" || true)
if [ -n "$BAD_REDIRECTS" ]; then
    echo "  ERROR: redirect target built from %{REQUEST_URI} — on a host with a webroot subfolder it"
    echo "         redirects to /domains/<domain>/… Use RewriteRule (.*) https://…/\$1 (SKILL.md Pitfall 9):"
    echo "$BAD_REDIRECTS" | sed 's/^/           /'
    FAILED=1
fi

# -------------------------------------------------------------
# 2. Check public/.htaccess (Tier 2: Charset & Front Controller)
# -------------------------------------------------------------
echo -n "[2/6] Checking public/.htaccess basic directives... "

if [ ! -f "$PUBLIC_HTACCESS" ]; then
    echo "FAILED"
    echo "  Error: public/.htaccess file does not exist at $BASE_DIR/public/.htaccess"
    FAILED=1
else
    HAS_UTF8=$(grep -E "^\s*AddDefaultCharset\s+UTF-8" "$PUBLIC_HTACCESS" || true)
    HAS_FC_REWRITE=$(grep -E "RewriteRule\s+\^\s+.*index\.php" "$PUBLIC_HTACCESS" || true)

    if [ -n "$HAS_UTF8" ] && [ -n "$HAS_FC_REWRITE" ]; then
        echo "PASSED (UTF-8 charset and Front Controller rewrite present)"
    else
        echo "WARNING / NOTICE"
        [ -z "$HAS_UTF8" ] && echo "  - Missing 'AddDefaultCharset UTF-8'"
        [ -z "$HAS_FC_REWRITE" ] && echo "  - Missing front controller rewrite to index.php"
        WARNINGS=$((WARNINGS + 1))
    fi

    # /index.php/… and /domains/<domain>/… in the requested URL become Symfony's base URL, which
    # Bolt caches into canonical links, the sitemap and llms.txt (Pitfall 10).
    if grep -qE '^\s*RewriteCond\s+%\{THE_REQUEST\}.*index\\\.php' "$PUBLIC_HTACCESS"; then
        HAS_INDEX_PHP_REDIRECT=1
    else
        echo "  ERROR: no redirect of /index.php/… based on %{THE_REQUEST} — a request for /index.php/page"
        echo "         turns the script path into the base URL of canonical links, the sitemap and llms.txt."
        echo "         Copy the three rules after 'RewriteEngine On' from examples/public.htaccess (Pitfall 10)."
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 3. Allowlist for theme/, files/ and thumbs/
# -------------------------------------------------------------
echo "[3/6] Checking the allowlist for theme/, files/ and thumbs/..."

# check_samples REGEX EXPECT SAMPLES... — EXPECT "allow" (must match) or "deny" (must not match).
check_samples() {
    local regex="$1" expect="$2" errors=0
    shift 2
    for sample in "$@"; do
        if echo "$sample" | grep -qiE "$regex"; then
            if [ "$expect" = "deny" ]; then
                echo "    ✗ '$sample' would be SERVED (expected 403)"
                errors=$((errors + 1))
            fi
        elif [ "$expect" = "allow" ]; then
            echo "    ✗ '$sample' would be DENIED (expected to be served)"
            errors=$((errors + 1))
        fi
    done
    return $errors
}

if [ -f "$PUBLIC_HTACCESS" ]; then
    THEME_COND=$(grep -E 'RewriteCond[[:space:]]+\$0[[:space:]]+!\^theme/' "$PUBLIC_HTACCESS" | head -n 1 || true)
    UPLOAD_COND=$(grep -E 'RewriteCond[[:space:]]+\$0[[:space:]]+!\\\.' "$PUBLIC_HTACCESS" | head -n 1 || true)
    HAS_THEME_RULE=$(grep -E 'RewriteRule[[:space:]]+\^theme/' "$PUBLIC_HTACCESS" || true)
    HAS_UPLOAD_RULE=$(grep -E 'RewriteRule[[:space:]]+\^\(files\|thumbs\)/' "$PUBLIC_HTACCESS" || true)

    if [ -n "$THEME_COND" ] && [ -n "$HAS_THEME_RULE" ]; then
        THEME_REGEX=$(echo "$THEME_COND" | sed -E 's/.*RewriteCond[[:space:]]+\$0[[:space:]]+!//; s/[[:space:]]+\[[A-Z,]+\][[:space:]]*$//')
        ERRORS=0
        check_samples "$THEME_REGEX" allow \
            "theme/acme/css/index.css" "theme/acme/js/app.js" "theme/acme/img/logo.svg" \
            "theme/acme/img/hero.webp" "theme/acme/css/fonts/inter/inter-latin.woff2" "theme/acme/img/favicon.ico" || ERRORS=$?
        check_samples "$THEME_REGEX" deny \
            "theme/acme/theme.yaml" "theme/acme/index.twig" "theme/acme/partials/_master.twig" \
            "theme/acme/package.json" "theme/acme/rollup.config.js" "theme/acme/js/src/index.ts" \
            "theme/acme/css/tailwind/index.scss" "theme/acme/img/snippet.twig" "theme/acme/js/config.yaml" \
            "theme/acme/favicon.ico" "theme/acme/README.md" || ERRORS=$((ERRORS + $?))
        if [ $ERRORS -gt 0 ]; then
            echo "  Error: the theme allowlist does not separate built assets from sources ($ERRORS sample(s))."
            FAILED=1
        else
            echo "  ✓ theme/: only built assets in css/, js/, img/, images/, fonts/ are served"
        fi
    else
        echo "  WARNING: no allowlist for theme/ — only the deny list protects theme sources, and any"
        echo "           file type it does not name is served. Add Step 2 of SKILL.md (examples/public.htaccess)."
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ -n "$UPLOAD_COND" ] && [ -n "$HAS_UPLOAD_RULE" ]; then
        UPLOAD_REGEX=$(echo "$UPLOAD_COND" | sed -E 's/.*RewriteCond[[:space:]]+\$0[[:space:]]+!//; s/[[:space:]]+\[[A-Z,]+\][[:space:]]*$//')
        ERRORS=0
        check_samples "$UPLOAD_REGEX" allow \
            "files/2024/05/photo.jpg" "files/documents/price-list.PDF" "files/brochure.docx" \
            "thumbs/320x240/photo.webp" "files/video/intro.mp4" || ERRORS=$?
        check_samples "$UPLOAD_REGEX" deny \
            "files/evil.html" "files/page.htm" "files/shell.php" "files/shell.phtml" \
            "files/payload.js" "files/dump.sql" "thumbs/320x240/evil.html" || ERRORS=$((ERRORS + $?))
        if [ $ERRORS -gt 0 ]; then
            echo "  Error: the files/ / thumbs/ allowlist lets dangerous types through or blocks uploads ($ERRORS sample(s))."
            FAILED=1
        else
            echo "  ✓ files/ and thumbs/: only accepted upload types are served (.html, .php, .js, .sql denied)"
        fi
    else
        echo "  WARNING: no allowlist for files/ and thumbs/ — an .html, .svg or .php file that gets into"
        echo "           public/files/ is served from the site's origin. Add Step 2 of SKILL.md."
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "  SKIPPED (public/.htaccess missing)"
fi

# -------------------------------------------------------------
# 4. Safety-net deny list (FilesMatch)
# -------------------------------------------------------------
echo -n "[4/6] Checking the deny list for the rest of public/... "
if [ -f "$PUBLIC_HTACCESS" ]; then
    HAS_AUTHZ=$(grep -E "<IfModule mod_authz_core\.c>" "$PUBLIC_HTACCESS" || true)
    HAS_DENY=$(grep -E "Require all denied" "$PUBLIC_HTACCESS" || true)
    FILESMATCH_LINE=$(grep -E "<FilesMatch\s+\"" "$PUBLIC_HTACCESS" | head -1 || true)

    if [ -n "$HAS_AUTHZ" ] && [ -n "$HAS_DENY" ] && [ -n "$FILESMATCH_LINE" ]; then
        echo "PASSED"
        echo "  Configured pattern: $FILESMATCH_LINE"

        echo "  Validating pattern against protected source files:"
        SAMPLE_BLOCKED=(
            "theme.yaml"
            "config.yml"
            "index.twig"
            "package.json"
            "package-lock.json"
            "tsconfig.json"
            "app.ts"
            "rollup.config.js"
            "postcss.config.mjs"
            "README.md"
            "design.psd"
            ".DS_Store"
            "composer.lock"
        )
        # Recommended by the current template; reported as warnings so older deny lists still pass.
        SAMPLE_RECOMMENDED=(
            "composer.json"
            "dump.sql"
            "bolt.sqlite"
            "backup.bak"
            ".user.ini"
            "error.log"
        )

        REGEX_PATTERN=$(echo "$FILESMATCH_LINE" | sed -E 's/.*<FilesMatch "([^"]+)".*/\1/')

        MATCH_ERRORS=0
        for sample in "${SAMPLE_BLOCKED[@]}"; do
            if echo "$sample" | grep -q -E "$REGEX_PATTERN"; then
                echo "    ✓ '$sample' is BLOCKED"
            else
                echo "    ✗ '$sample' is NOT BLOCKED (regex did not match)"
                MATCH_ERRORS=$((MATCH_ERRORS + 1))
            fi
        done
        MISSING_RECOMMENDED=()
        for sample in "${SAMPLE_RECOMMENDED[@]}"; do
            echo "$sample" | grep -q -E "$REGEX_PATTERN" || MISSING_RECOMMENDED+=("$sample")
        done
        if [ ${#MISSING_RECOMMENDED[@]} -gt 0 ]; then
            echo "  WARNING: the deny list does not cover ${MISSING_RECOMMENDED[*]} — use the pattern of examples/public.htaccess (dumps, backups, logs)."
            WARNINGS=$((WARNINGS + 1))
        fi

        echo "  Checking for false positives on public web assets:"
        SAMPLE_ALLOWED=(
            "theme.css"
            "bundle.js"
            "logo.svg"
            "photo.webp"
            "photo.jpg"
            "photo.png"
            "font.woff2"
            "document.pdf"
            "robots.txt"
            "site.webmanifest"
        )

        FP_ERRORS=0
        for allowed in "${SAMPLE_ALLOWED[@]}"; do
            if echo "$allowed" | grep -q -E "$REGEX_PATTERN"; then
                echo "    ✗ FALSE POSITIVE: '$allowed' matches the block pattern and would be denied!"
                FP_ERRORS=$((FP_ERRORS + 1))
            fi
        done

        if [ $MATCH_ERRORS -gt 0 ]; then
            echo "  Error: $MATCH_ERRORS sensitive file patterns were not blocked."
            FAILED=1
        fi

        if [ $FP_ERRORS -gt 0 ]; then
            echo "  Error: $FP_ERRORS public asset types are erroneously blocked by the pattern."
            FAILED=1
        else
            echo "    ✓ All public assets pass safely (no false positives)"
        fi
    else
        echo "FAILED"
        [ -z "$HAS_AUTHZ" ] && echo "  - Missing <IfModule mod_authz_core.c>"
        [ -z "$HAS_DENY" ] && echo "  - Missing 'Require all denied'"
        [ -z "$FILESMATCH_LINE" ] && echo "  - Missing <FilesMatch> directive"
        FAILED=1
    fi

    # Folders and env files: FilesMatch only sees file names, so node_modules/ and .git/ need a
    # RewriteRule; .env* files need their own FilesMatch.
    if ! grep -qE "RewriteRule.*node_modules" "$PUBLIC_HTACCESS"; then
        echo "  WARNING: public/.htaccess does not deny node_modules/ (add: RewriteRule (^|/)(node_modules|\\.git)(/|\$) - [F,L])"
        WARNINGS=$((WARNINGS + 1))
    fi
    # Only the front controller may run PHP: a leftover info.php or adminer.php would execute.
    if ! grep -qE 'RewriteRule[[:space:]]+\^\(\?!index' "$PUBLIC_HTACCESS"; then
        echo "  WARNING: public/.htaccess runs any *.php in public/ (add: RewriteRule ^(?!index\\.php\$).+\\.php\$ - [F,L])"
        WARNINGS=$((WARNINGS + 1))
    fi
    if ! grep -qE "FilesMatch[[:space:]]+\"\^\\\\\.env" "$PUBLIC_HTACCESS"; then
        echo "  WARNING: public/.htaccess does not deny .env* files (add: <FilesMatch \"^\\.env\"> Require all denied </FilesMatch>)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED (public/.htaccess missing)"
    FAILED=1
fi

# -------------------------------------------------------------
# 5. Security headers for static files
# -------------------------------------------------------------
echo -n "[5/6] Checking security headers for static files... "
if [ -f "$PUBLIC_HTACCESS" ]; then
    MISSING_HEADERS=()
    grep -qE "Header[[:space:]]+always[[:space:]]+set[[:space:]]+Strict-Transport-Security" "$PUBLIC_HTACCESS" || MISSING_HEADERS+=("Strict-Transport-Security")
    grep -qE "Header[[:space:]]+(always[[:space:]]+)?unset[[:space:]]+X-Powered-By" "$PUBLIC_HTACCESS" || MISSING_HEADERS+=("unset X-Powered-By")
    grep -qE "X-Content-Type-Options" "$PUBLIC_HTACCESS" || MISSING_HEADERS+=("X-Content-Type-Options nosniff")
    grep -qE "Content-Security-Policy.*sandbox" "$PUBLIC_HTACCESS" || MISSING_HEADERS+=("sandbox policy for files/ and thumbs/")
    if [ ${#MISSING_HEADERS[@]} -eq 0 ]; then
        echo "PASSED (HSTS, X-Powered-By removed, nosniff, sandboxed uploads)"
        if grep -qE "<If \"%\{REQUEST_URI\} =~ m#\^/\(files" "$PUBLIC_HTACCESS"; then
            echo "  WARNING: the upload sandbox tests REQUEST_URI — after the root .htaccess rewrite it starts with /public/"
            echo "           and never matches. Test %{REQUEST_FILENAME} =~ m#/public/(files|thumbs)/# (SKILL.md Step 4)."
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "WARNING"
        for missing in "${MISSING_HEADERS[@]}"; do
            echo "  - Missing: $missing (SKILL.md Step 4)"
        done
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED (public/.htaccess missing)"
fi

# -------------------------------------------------------------
# 6. Live HTTP Endpoint Test (Optional if server is running)
# -------------------------------------------------------------
BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"  # set BOLT_BASE_URL to this project's running site
BASE_URL="${BASE_URL%/}"
# A local Apache (bolt-asset-caching/scripts/serve-apache.sh) answers plain HTTP: tell the root
# .htaccess HTTPS redirect that a TLS proxy is in front, as check-delivery.php does — otherwise
# every probe below only sees that redirect.
LOCAL_PROTO="X-Forwarded-Proto:"  # curl: "Name:" sends no header
echo "$BASE_URL" | grep -qE '^http://(127\.0\.0\.1|localhost|\[::1\])(:|/|$)' && LOCAL_PROTO="X-Forwarded-Proto: https"
live_curl() { curl -H "$LOCAL_PROTO" "$@"; }
echo -n "[6/6] Checking live HTTP responses against $BASE_URL... "
# 10 s: a production site on a cold cache (or behind a CDN) often needs more than 2 s; a closed
# port still fails at once.
if live_curl -s -k --max-time 10 "$BASE_URL" > /dev/null 2>&1; then
    echo "SERVER ONLINE"

    THEME_NAME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    [ -z "$THEME_NAME" ] && THEME_NAME="default"

    TEST_PATHS=(
        "/theme/$THEME_NAME/theme.yaml"
        "/theme/$THEME_NAME/package.json"
        "/theme/$THEME_NAME/index.twig"
        "/files/bolt-htaccess-probe.html"
    )

    for p in "${TEST_PATHS[@]}"; do
        STATUS=$(live_curl -s -k -o /dev/null -w "%{http_code}" "$BASE_URL$p" || true)
        if [ "$STATUS" = "403" ] || [ "$STATUS" = "404" ]; then
            echo "  $p -> HTTP $STATUS (SAFE / PROTECTED)"
        else
            echo "  $p -> HTTP $STATUS (WARNING: Expected 403 Forbidden or 404)"
            WARNINGS=$((WARNINGS + 1))
        fi
    done

    # A built asset must still be served — with the static-file headers.
    if [ -f "public/theme/$THEME_NAME/css/index.css" ]; then
        HEADERS=$(live_curl -s -k -D - -o /dev/null "$BASE_URL/theme/$THEME_NAME/css/index.css" || true)
        STATUS=$(echo "$HEADERS" | head -n 1 | awk '{print $2}')
        if [ "$STATUS" = "200" ]; then
            echo "  /theme/$THEME_NAME/css/index.css -> HTTP 200 (built asset served)"
            echo "$HEADERS" | grep -qi "^x-content-type-options: *nosniff" || {
                echo "  WARNING: static files are served without 'X-Content-Type-Options: nosniff' (Step 4; is mod_headers on?)"
                WARNINGS=$((WARNINGS + 1))
            }
        else
            echo "  WARNING: /theme/$THEME_NAME/css/index.css -> HTTP $STATUS — the allowlist blocks the built stylesheet."
            WARNINGS=$((WARNINGS + 1))
        fi
    fi

    # The front controller in the URL is redirected away before Symfony sees it (Pitfall 10).
    # Requested only when the project's public/.htaccess has the rules: on a site without them the
    # request itself puts the script path into Bolt's cached links (canonical, llms.txt) for the
    # cache lifetime — the probe would cause the bug it looks for. If the local file has the rules
    # but the server's copy does not, the probe fails and that one request has the same effect.
    if [ -z "$HAS_INDEX_PHP_REDIRECT" ]; then
        TARGET="skip"
        echo "  SKIPPED: /index.php/… not requested — without the Pitfall 10 rules in public/.htaccess (section 2)"
        echo "           the request would put the script path into Bolt's cached canonical links and llms.txt."
    else
        TARGET=$(live_curl -s -k -o /dev/null --max-time 10 -w "%{http_code} %{redirect_url}" "$BASE_URL/index.php/bolt-htaccess-probe?x=1" || true)
    fi
    case "$TARGET" in
        skip) ;;
        "301 "*"/bolt-htaccess-probe?x=1")
            if [ "${TARGET#*index.php}" = "$TARGET" ]; then
                echo "  /index.php/bolt-htaccess-probe?x=1 -> ${TARGET} (redirect OK)"
            else
                echo "  ERROR: /index.php/bolt-htaccess-probe?x=1 -> $TARGET (index.php kept in the target; Pitfall 10)"
                FAILED=1
            fi ;;
        *) echo "  ERROR: /index.php/bolt-htaccess-probe?x=1 -> $TARGET (expected 301 to /bolt-htaccess-probe?x=1;"
           echo "         the local public/.htaccess has the rules — upload it to the server. Until then Symfony"
           echo "         takes the script path as the base URL, also for this request — Pitfall 10)"
           FAILED=1 ;;
    esac

    # Production only: the www and plain-HTTP redirects land on the same path of the canonical
    # https:// host in one hop — no /domains/<domain>/ prefix (Pitfall 9).
    LIVE_HOST=$(echo "$BASE_URL" | sed -E 's#^https://([^/:]+).*#\1#')
    if [ "${BASE_URL#https://}" != "$BASE_URL" ] && ! echo "$LIVE_HOST" | grep -qE '^(localhost|127\.|www\.)|\.(test|local|localhost)$'; then
        EXPECTED="https://$LIVE_HOST/bolt-htaccess-probe?x=1"
        for FROM in "https://www.$LIVE_HOST" "http://$LIVE_HOST"; do
            TARGET=$(curl -s -o /dev/null --max-time 10 -w "%{http_code} %{redirect_url}" "$FROM/bolt-htaccess-probe?x=1" || true)
            case "$TARGET" in
                000*) echo "  $FROM/ -> no answer (SKIPPED: host does not resolve or refuses)" ;;
                "301 $EXPECTED") echo "  $FROM/bolt-htaccess-probe?x=1 -> 301 $EXPECTED (redirect OK)" ;;
                *) echo "  ERROR: $FROM/bolt-htaccess-probe?x=1 -> $TARGET (expected 301 $EXPECTED; Pitfall 9)"
                   FAILED=1 ;;
            esac
        done
    fi
else
    echo "SKIPPED (Local server not running on $BASE_URL)"
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo " Apache .htaccess files and source code protections are properly configured."
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED"
    echo " Please review the errors reported above."
    echo "=========================================================="
    exit 1
fi
