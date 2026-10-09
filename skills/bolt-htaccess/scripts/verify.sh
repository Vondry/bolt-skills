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

# -------------------------------------------------------------
# 1. Check Root .htaccess (Tier 1: HTTPS & public/ rewrite)
# -------------------------------------------------------------
echo -n "[1/4] Checking root .htaccess... "
ROOT_HTACCESS=".htaccess"

if [ ! -f "$ROOT_HTACCESS" ]; then
    echo "FAILED"
    echo "  Error: Root .htaccess file does not exist at $BASE_DIR/.htaccess"
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

# -------------------------------------------------------------
# 2. Check public/.htaccess (Tier 2: Charset & Front Controller)
# -------------------------------------------------------------
echo -n "[2/4] Checking public/.htaccess basic directives... "
PUBLIC_HTACCESS="public/.htaccess"

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
fi

# -------------------------------------------------------------
# 3. Check Source Code Lockdown (FilesMatch rule)
# -------------------------------------------------------------
echo -n "[3/4] Checking source file access restrictions in public/.htaccess... "
if [ -f "$PUBLIC_HTACCESS" ]; then
    HAS_AUTHZ=$(grep -E "<IfModule mod_authz_core\.c>" "$PUBLIC_HTACCESS" || true)
    HAS_DENY=$(grep -E "Require all denied" "$PUBLIC_HTACCESS" || true)
    FILESMATCH_LINE=$(grep -E "<FilesMatch\s+\"" "$PUBLIC_HTACCESS" | head -1 || true)

    if [ -n "$HAS_AUTHZ" ] && [ -n "$HAS_DENY" ] && [ -n "$FILESMATCH_LINE" ]; then
        echo "PASSED"
        echo "  Configured pattern: $FILESMATCH_LINE"

        # Regex validation against sample sensitive files
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

        # Extract regex from FilesMatch
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

        # Safety check: ensure normal web assets are NOT blocked (no false positives)
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
else
    echo "SKIPPED (public/.htaccess missing)"
    FAILED=1
fi

# Folders and env files: FilesMatch only sees file names, so node_modules/ and .git/ need a
# RewriteRule; .env* files need their own FilesMatch.
if [ -f "$PUBLIC_HTACCESS" ]; then
    if ! grep -qE "RewriteRule.*node_modules" "$PUBLIC_HTACCESS"; then
        echo "  WARNING: public/.htaccess does not deny node_modules/ (add: RewriteRule (^|/)(node_modules|\\.git)(/|\$) - [F,L])"
        WARNINGS=$((WARNINGS + 1))
    fi
    if ! grep -qE "FilesMatch[[:space:]]+\"\^\\\\\.env" "$PUBLIC_HTACCESS"; then
        echo "  WARNING: public/.htaccess does not deny .env* files (add: <FilesMatch \"^\\.env\"> Require all denied </FilesMatch>)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# -------------------------------------------------------------
# 4. Live HTTP Endpoint Test (Optional if server is running)
# -------------------------------------------------------------
BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"  # set BOLT_BASE_URL to this project's running site
echo -n "[4/4] Checking live HTTP responses against $BASE_URL... "
if curl -s --max-time 2 "$BASE_URL" > /dev/null 2>&1; then
    echo "SERVER ONLINE"

    # Find active theme name if available
    THEME_NAME=$(grep -E "^\s*theme:" config/bolt/config.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    [ -z "$THEME_NAME" ] && THEME_NAME="default"

    TEST_PATHS=(
        "/theme/$THEME_NAME/theme.yaml"
        "/theme/$THEME_NAME/package.json"
        "/theme/$THEME_NAME/index.twig"
    )

    for p in "${TEST_PATHS[@]}"; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$p" || true)
        if [ "$STATUS" = "403" ] || [ "$STATUS" = "404" ]; then
            echo "  $p -> HTTP $STATUS (SAFE / PROTECTED)"
        else
            echo "  $p -> HTTP $STATUS (WARNING: Expected 403 Forbidden or 404)"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
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
