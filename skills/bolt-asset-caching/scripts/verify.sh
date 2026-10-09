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
echo " Bolt CMS Asset & Thumbnail Caching Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Check config/packages/security.yaml for /thumbs bypass
# -------------------------------------------------------------
echo -n "[1/4] Checking security.yaml for /thumbs firewall bypass... "
SEC_FILE="config/packages/security.yaml"

if [ ! -f "$SEC_FILE" ]; then
    echo "FAILED"
    echo "  Error: $SEC_FILE not found."
    FAILED=1
else
    # Check if dev firewall pattern includes thumbs
    DEV_PATTERN=$(grep -E "pattern:\s*\^/\(_\(profiler" "$SEC_FILE" || true)

    if echo "$DEV_PATTERN" | grep -q "thumbs"; then
        echo "PASSED (dev firewall bypasses /thumbs statelessly)"
    else
        echo "FAILED"
        echo "  Error: dev firewall does not include 'thumbs' in pattern!"
        echo "  Found: '${DEV_PATTERN:-<pattern not found>}'"
        echo "  Expected: 'pattern: ^/(_(profiler|wdt)|css|images|js|thumbs)/'"
        echo "  Impact: Symfony SessionListener will overwrite thumbnail caching to 'private, max-age=0'!"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 2. Check config/bolt/config.yaml for save_files: true
# -------------------------------------------------------------
echo -n "[2/4] Checking config/bolt/config.yaml for thumbnail disk caching... "
BOLT_CONFIG="config/bolt/config.yaml"

if [ ! -f "$BOLT_CONFIG" ]; then
    echo "FAILED"
    echo "  Error: $BOLT_CONFIG not found."
    FAILED=1
else
    SAVE_FILES=$(grep -E "^\s*save_files:\s*" "$BOLT_CONFIG" | awk '{print $2}' || true)

    if [ "$SAVE_FILES" = "true" ]; then
        echo "PASSED (thumbnails.save_files: true)"
    else
        echo "FAILED"
        echo "  Expected 'save_files: true' under thumbnails, got: '${SAVE_FILES:-missing}'"
        echo "  Impact: Generated thumbnails are not saved to disk and must be re-rendered via PHP!"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 3. Check public/.htaccess for mod_expires caching
# -------------------------------------------------------------
echo -n "[3/4] Checking public/.htaccess for mod_expires static caching... "
HTACCESS="public/.htaccess"

if [ ! -f "$HTACCESS" ]; then
    echo "FAILED"
    echo "  Error: $HTACCESS not found."
    FAILED=1
else
    HAS_EXPIRES_MODULE=$(grep -E "<IfModule mod_expires\.c>" "$HTACCESS" || true)
    HAS_EXPIRES_ACTIVE=$(grep -E "ExpiresActive\s+On" "$HTACCESS" || true)
    HAS_IMAGE_EXPIRES=$(grep -E "ExpiresByType image/" "$HTACCESS" || true)

    EXPIRES_BLOCKS=$(grep -cE "<IfModule mod_expires\.c>" "$HTACCESS" || true)
    if [ -n "$HAS_EXPIRES_MODULE" ] && [ -n "$HAS_EXPIRES_ACTIVE" ] && [ -n "$HAS_IMAGE_EXPIRES" ]; then
        echo "PASSED (mod_expires active with image caching rules)"
        if grep -qE "ExpiresByType application/javascript" "$HTACCESS" && ! grep -qE "ExpiresByType text/javascript" "$HTACCESS"; then
            echo "  WARNING: only application/javascript has an expiry; newer Apache serves .js as text/javascript — add both."
            WARNINGS=$((WARNINGS + 1))
        fi
        if [ "$EXPIRES_BLOCKS" -gt 1 ]; then
            echo "  WARNING: $EXPIRES_BLOCKS <IfModule mod_expires.c> blocks found — merge them into one (bolt-htaccess + bolt-asset-caching share it)."
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "WARNING / NOTICE"
        [ -z "$HAS_EXPIRES_MODULE" ] && echo "  - Missing <IfModule mod_expires.c>"
        [ -z "$HAS_EXPIRES_ACTIVE" ] && echo "  - Missing 'ExpiresActive On'"
        [ -z "$HAS_IMAGE_EXPIRES" ] && echo "  - Missing image expiration directives (ExpiresByType image/...)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# -------------------------------------------------------------
# 4. Check Nginx configuration (if present)
# -------------------------------------------------------------
echo -n "[4/4] Checking Nginx configuration for /thumbs and assets... "
NGINX_CONF="docker/nginx/conf.d/default.conf"

if [ -f "$NGINX_CONF" ]; then
    HAS_NGINX_THUMBS=$(grep -E "location\s+\^~\s+/thumbs" "$NGINX_CONF" || true)
    HAS_THUMBS_EXPIRES=$(grep -E -A 8 "location\s+\^~\s+/thumbs" "$NGINX_CONF" | grep -E "expires\s+" || true)
    HAS_ASSET_LOCATION=$(grep -E "location\s+~\*\s+\^\.\+\\\.\(" "$NGINX_CONF" || true)

    if [ -n "$HAS_NGINX_THUMBS" ] && [ -n "$HAS_THUMBS_EXPIRES" ]; then
        echo "PASSED (Nginx has /thumbs caching and static asset rules)"
    else
        echo "WARNING / NOTICE"
        [ -z "$HAS_NGINX_THUMBS" ] && echo "  - Missing 'location ^~ /thumbs' block in Nginx"
        [ -z "$HAS_THUMBS_EXPIRES" ] && echo "  - Missing expires header in Nginx /thumbs block"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED (docker/nginx/conf.d/default.conf not present in this project)"
fi

# -------------------------------------------------------------
# Live HTTP Header Inspection (Optional if server is running for this project)
# -------------------------------------------------------------
echo -n "Checking live HTTP headers... "
IS_RUNNING=0
if command -v symfony >/dev/null 2>&1; then
    if symfony server:status --dir="$BASE_DIR" 2>/dev/null | grep -q "Listening on"; then
        IS_RUNNING=1
        SERVER_URL=$(symfony server:status --dir="$BASE_DIR" 2>/dev/null | grep -E "Listening on\s+http" | awk '{print $NF}' || true)
    fi
fi

if [ $IS_RUNNING -eq 1 ] && [ -n "$SERVER_URL" ]; then
    echo "SERVER ONLINE ($SERVER_URL)"

    # Look for an actual image in public/files/
    REAL_IMG=$(find public/files -maxdepth 3 -type f \( -name "*.jpg" -o -name "*.webp" -o -name "*.png" \) 2>/dev/null | head -1 | sed 's|public/files/||' || true)

    if [ -n "$REAL_IMG" ]; then
        SAMPLE_URL="$SERVER_URL/thumbs/320x240/$REAL_IMG"
        HEADERS=$(curl -sI "$SAMPLE_URL" 2>/dev/null || true)
        CACHE_CONTROL=$(echo "$HEADERS" | grep -i "^cache-control:" || true)

        if echo "$CACHE_CONTROL" | grep -i -q "private, max-age=0"; then
            echo "  ✗ Live Error: Response for '$REAL_IMG' returned 'private, max-age=0'!"
            echo "    $CACHE_CONTROL"
            FAILED=1
        elif echo "$CACHE_CONTROL" | grep -i -q "public"; then
            echo "  ✓ Live OK: Response returned public cache header: $CACHE_CONTROL"
        else
            echo "  Notice: Thumbnail returned: ${CACHE_CONTROL:-<no cache-control>}"
        fi
    else
        echo "  Notice: No sample image found in public/files/ to test live thumbnail generation"
    fi
else
    echo "SKIPPED (Local server not running for project $BASE_DIR)"
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo " Multi-layer asset and thumbnail caching is properly configured."
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED"
    echo " Please review the errors reported above."
    echo "=========================================================="
    exit 1
fi
