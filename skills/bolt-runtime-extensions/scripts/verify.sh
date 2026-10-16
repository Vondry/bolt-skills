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
echo " Bolt CMS Runtime Extensions Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Check LocaleLinkExtension.php
# -------------------------------------------------------------
echo -n "[1/5] Checking src/LocaleLinkExtension.php... "
LOCALE_EXT="src/LocaleLinkExtension.php"
if [ ! -f "$LOCALE_EXT" ]; then
    echo "FAILED: $LOCALE_EXT does not exist."
    FAILED=1
else
    if ! php -l "$LOCALE_EXT" > /dev/null 2>&1; then
        echo "FAILED: PHP syntax error in $LOCALE_EXT."
        FAILED=1
    elif ! grep -q "locale_link" "$LOCALE_EXT"; then
        echo "FAILED: $LOCALE_EXT is missing the 'locale_link' TwigFunction."
        FAILED=1
    else
        echo "PASSED (locale_link function verified)"
    fi
fi

# -------------------------------------------------------------
# 2. Check ImageDimensionsExtension.php
# -------------------------------------------------------------
echo -n "[2/5] Checking src/ImageDimensionsExtension.php... "
IMG_EXT="src/ImageDimensionsExtension.php"
if [ ! -f "$IMG_EXT" ]; then
    echo "WARNING: $IMG_EXT not found. Static/theme images without media DB entries may open blank in PhotoSwipe."
    WARNINGS=$((WARNINGS + 1))
else
    if ! php -l "$IMG_EXT" > /dev/null 2>&1; then
        echo "FAILED: PHP syntax error in $IMG_EXT."
        FAILED=1
    elif ! grep -q "image_dimensions" "$IMG_EXT"; then
        echo "FAILED: $IMG_EXT is missing the 'image_dimensions' TwigFunction."
        FAILED=1
    elif ! grep -q "CacheInterface" "$IMG_EXT"; then
        echo "WARNING: $IMG_EXT is missing Symfony CacheInterface integration (may degrade performance)."
        WARNINGS=$((WARNINGS + 1))
    else
        echo "PASSED (image_dimensions function with caching verified)"
    fi
fi

# -------------------------------------------------------------
# 3. Check FileSizeExtension.php
# -------------------------------------------------------------
echo -n "[3/5] Checking src/FileSizeExtension.php... "
FILE_EXT="src/FileSizeExtension.php"
if [ ! -f "$FILE_EXT" ]; then
    echo "WARNING: $FILE_EXT not found. Downloadable file attachments cannot use |file_size|format_file_size filters."
    WARNINGS=$((WARNINGS + 1))
else
    if ! php -l "$FILE_EXT" > /dev/null 2>&1; then
        echo "FAILED: PHP syntax error in $FILE_EXT."
        FAILED=1
    elif grep -q "TwigFilter('format_bytes'" "$FILE_EXT"; then
        echo "FAILED: $FILE_EXT registers 'format_bytes', which Bolt core already defines — core's filter wins, so this one never runs. Copy examples/FileSizeExtension.php (filter format_file_size) and replace |format_bytes in the theme's download templates (SKILL.md section 6)."
        FAILED=1
    elif ! grep -q "format_file_size" "$FILE_EXT"; then
        echo "FAILED: $FILE_EXT is missing 'format_file_size' filter."
        FAILED=1
    else
        echo "PASSED (file_size & format_file_size filters verified)"
    fi
fi

# -------------------------------------------------------------
# 4. Check config/services.yaml configuration
# -------------------------------------------------------------
echo -n "[4/5] Checking config/services.yaml service registration & bindings... "
SERVICES_FILE="config/services.yaml"
if [ ! -f "$SERVICES_FILE" ]; then
    echo "FAILED: $SERVICES_FILE not found."
    FAILED=1
else
    CONFIG_ERRORS=()
    # The arguments come from #[Autowire] attributes in the class, or (older projects) from an
    # explicit service definition / binding in services.yaml.
    if [ -f "$LOCALE_EXT" ] && ! grep -q "#\[Autowire('%app_locales%')\]" "$LOCALE_EXT" \
        && ! grep -q "App\\\\LocaleLinkExtension:" "$SERVICES_FILE" && ! grep -q "appLocales" "$SERVICES_FILE"; then
        CONFIG_ERRORS+=("LocaleLinkExtension gets no \$appLocales: use the #[Autowire] attributes of examples/LocaleLinkExtension.php")
    fi
    if ! grep -q "app_locales:" "$SERVICES_FILE" && ! grep -q "locales:" "$SERVICES_FILE"; then
        CONFIG_ERRORS+=("Missing app_locales parameter in services.yaml")
    fi

    if [ ${#CONFIG_ERRORS[@]} -gt 0 ]; then
        echo "FAILED"
        for err in "${CONFIG_ERRORS[@]}"; do
            echo "  - $err"
        done
        FAILED=1
    else
        echo "PASSED"
    fi
fi

# -------------------------------------------------------------
# 5. Verify Symfony Container & Twig Registration
# -------------------------------------------------------------
echo -n "[5/5] Checking Symfony container compilation & Twig registration... "
if [ -f "bin/console" ] && command -v php &>/dev/null; then
    if php bin/console lint:container > /dev/null 2>&1; then
        # Check if debug:twig lists our functions/filters
        TWIG_OUT=$(php bin/console debug:twig 2>/dev/null || true)
        if [ -n "$TWIG_OUT" ]; then
            MISSING_TAGS=()
            if [ -f "$LOCALE_EXT" ] && ! echo "$TWIG_OUT" | grep -q "locale_link"; then
                MISSING_TAGS+=("locale_link function not registered in Twig environment")
            fi
            if [ -f "$IMG_EXT" ] && ! echo "$TWIG_OUT" | grep -q "image_dimensions"; then
                MISSING_TAGS+=("image_dimensions function not registered in Twig environment")
            fi
            if [ -f "$FILE_EXT" ] && ! echo "$TWIG_OUT" | grep -q "format_file_size"; then
                MISSING_TAGS+=("format_file_size filter not registered in Twig environment")
            fi

            if [ ${#MISSING_TAGS[@]} -gt 0 ]; then
                echo "FAILED"
                for tag in "${MISSING_TAGS[@]}"; do
                    echo "  - $tag"
                done
                FAILED=1
            else
                echo "PASSED (All extensions active in Twig environment)"
            fi
        else
            echo "PASSED (Container compiled successfully)"
        fi
    else
        echo "FAILED: 'bin/console lint:container' failed (service configuration error)"
        FAILED=1
    fi
else
    echo "SKIPPED (bin/console not executable)"
fi

echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo " RESULT: ALL RUNTIME EXTENSIONS PASSED PERFECTLY!"
    else
        echo " RESULT: PASSED with $WARNINGS warning(s)."
    fi
    exit 0
else
    echo " RESULT: VERIFICATION FAILED with errors above."
    exit 1
fi
