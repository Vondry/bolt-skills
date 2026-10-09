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

MENU_FILE="config/bolt/menu.yaml"
BOLT_CONFIG="config/bolt/config.yaml"
CT_FILE="config/bolt/contenttypes.yaml"

echo "=========================================================="
echo " Bolt CMS Menu Configuration & Architecture Verification"
echo " Project root: $BASE_DIR"
echo " Menu file:    $MENU_FILE"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Check config/bolt/menu.yaml existence
# -------------------------------------------------------------
echo -n "[1/5] Checking $MENU_FILE existence... "
if [ ! -f "$MENU_FILE" ]; then
    echo "FAILED"
    echo "  Error: $MENU_FILE does not exist. Run scripts/scaffold.sh to create one."
    exit 1
fi
echo "PASSED"

# -------------------------------------------------------------
# 2. Check YAML syntax
# -------------------------------------------------------------
echo -n "[2/5] Validating YAML syntax... "
if [ -f "bin/console" ] && php bin/console lint:yaml "$MENU_FILE" --parse-tags > /dev/null 2>&1; then
    echo "PASSED (bin/console lint:yaml)"
elif [ -f "vendor/autoload.php" ] && php -r "require 'vendor/autoload.php'; \Symfony\Component\Yaml\Yaml::parseFile('$MENU_FILE');" > /dev/null 2>&1; then
    echo "PASSED (Symfony Yaml parseFile)"
else
    echo "FAILED"
    echo "  YAML Syntax error in $MENU_FILE:"
    if [ -f "bin/console" ]; then
        php bin/console lint:yaml "$MENU_FILE" --parse-tags || true
    else
        php -r "require 'vendor/autoload.php'; \Symfony\Component\Yaml\Yaml::parseFile('$MENU_FILE');" || true
    fi
    exit 1
fi

# -------------------------------------------------------------
# 3. Structural validation via PHP
# -------------------------------------------------------------
echo "[3/5] Validating menu structure, schema, and architectural rules..."

PHP_CHECK_OUTPUT=$(php -r "
if (!file_exists('vendor/autoload.php')) {
    echo 'FATAL: vendor/autoload.php not found. Run composer install.' . PHP_EOL;
    exit(1);
}
require 'vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

\$menuFile = '$MENU_FILE';
\$boltConfigFile = '$BOLT_CONFIG';
\$ctFile = '$CT_FILE';

\$errors = [];
\$warnings = [];

try {
    \$menuData = Yaml::parseFile(\$menuFile);
} catch (\Throwable \$e) {
    echo 'FATAL: ' . \$e->getMessage() . PHP_EOL;
    exit(1);
}

if (!is_array(\$menuData)) {
    echo 'FATAL: ' . \$menuFile . ' must contain a valid YAML map of menus.' . PHP_EOL;
    exit(1);
}

// Configured locales: app_locales in config/services.yaml is the source of truth
// (pipe-separated, e.g. cs|en|de). Older projects may list them under `locales:` in
// config/bolt/config.yaml; that is used only as a fallback.
\$configuredLocales = [];
if (file_exists('config/services.yaml')) {
    try {
        \$services = Yaml::parseFile('config/services.yaml', Yaml::PARSE_CUSTOM_TAGS);
        \$appLocales = \$services['parameters']['app_locales'] ?? null;
        if (is_string(\$appLocales)) {
            \$configuredLocales = array_values(array_filter(array_map('trim', explode('|', \$appLocales))));
        } elseif (is_array(\$appLocales)) {
            \$configuredLocales = array_values(\$appLocales);
        }
    } catch (\Throwable \$e) {
        // ignore
    }
}
if (empty(\$configuredLocales) && file_exists(\$boltConfigFile)) {
    try {
        \$boltConfig = Yaml::parseFile(\$boltConfigFile);
        if (isset(\$boltConfig['locales']) && is_array(\$boltConfig['locales'])) {
            \$configuredLocales = array_keys(\$boltConfig['locales']);
        }
    } catch (\Throwable \$e) {
        // ignore
    }
}

// Check configured contenttypes
\$knownSlugs = [];
if (file_exists(\$ctFile)) {
    try {
        \$ctData = Yaml::parseFile(\$ctFile);
        if (is_array(\$ctData)) {
            foreach (\$ctData as \$ctKey => \$ctDef) {
                if (!is_array(\$ctDef)) continue;
                \$knownSlugs[] = strtolower(\$ctKey);
                if (isset(\$ctDef['slug'])) {
                    \$knownSlugs[] = strtolower(\$ctDef['slug']);
                }
                if (isset(\$ctDef['singular_slug'])) {
                    \$knownSlugs[] = strtolower(\$ctDef['singular_slug']);
                }
            }
        }
    } catch (\Throwable \$e) {
        // ignore
    }
}
\$knownSlugs = array_unique(\$knownSlugs);

// 1. Check primary 'main' menu presence
if (!isset(\$menuData['main'])) {
    \$errors[] = \"Mandatory menu 'main' is missing in \$menuFile.\";
} elseif (!is_array(\$menuData['main'])) {
    \$errors[] = \"Menu 'main' must be a list of menu items.\";
}

// Helper to validate items recursively
function validateItems(array \$items, string \$menuName, string \$path, array \$configuredLocales, array \$knownSlugs, array &\$errors, array &\$warnings): void {
    foreach (\$items as \$idx => \$item) {
        \$itemPath = \$path . '[' . \$idx . ']';
        if (!is_array(\$item)) {
            \$errors[] = \"\$itemPath in menu '\$menuName' must be a mapping.\";
            continue;
        }

        // Check label
        if (!isset(\$item['label'])) {
            \$errors[] = \"\$itemPath in menu '\$menuName' is missing 'label'.\";
        } else {
            if (is_array(\$item['label'])) {
                // Multilingual label
                if (!empty(\$configuredLocales)) {
                    foreach (\$configuredLocales as \$loc) {
                        if (!array_key_exists(\$loc, \$item['label'])) {
                            \$warnings[] = \"\$itemPath label is missing translation for configured locale '\$loc'.\";
                        }
                    }
                }
            } elseif (count(\$configuredLocales) > 1) {
                \$warnings[] = \"\$itemPath has string label '\" . \$item['label'] . \"' while multiple locales are configured (\" . implode(', ', \$configuredLocales) . \"). Consider using a per-locale mapping { \" . implode(': ..., ', \$configuredLocales) . \": ... }.\";
            }
        }

        // Check link or submenu
        \$hasLink = isset(\$item['link']) && \$item['link'] !== null && \$item['link'] !== '';
        \$hasSubmenu = isset(\$item['submenu']) && is_array(\$item['submenu']) && !empty(\$item['submenu']);

        if (!\$hasLink && !\$hasSubmenu) {
            \$errors[] = \"\$itemPath in menu '\$menuName' must have either 'link' or 'submenu'.\";
        }

        if (\$hasLink) {
            \$link = (string)\$item['link'];

            // Anchor check: must start with /# if it's an anchor, not bare #
            if (str_starts_with(\$link, '#') && !str_starts_with(\$link, '/#')) {
                \$errors[] = \"\$itemPath link '\$link' is a bare anchor '#...'. Anchor links must start with '/#' (e.g. '/\$link') so they resolve reliably from subpages.\";
            }

            // Check leading slash on internal links
            if (!str_starts_with(\$link, 'http://') && !str_starts_with(\$link, 'https://') && !str_starts_with(\$link, '//') && !str_starts_with(\$link, 'mailto:') && !str_starts_with(\$link, 'tel:')) {
                if (!str_starts_with(\$link, '/')) {
                    \$warnings[] = \"\$itemPath internal link '\$link' does not start with a leading '/'. Bolt links should start with '/' (e.g. '/\$link').\";
                }
            }

            // Check for hardcoded locale prefix (e.g. /cs/ or /en/)
            \$prefixCodes = !empty(\$configuredLocales) ? \$configuredLocales : ['cs', 'en', 'de', 'sk'];
            foreach (\$prefixCodes as \$code) {
                \$locPrefix = '/' . \$code . '/';
                if (str_starts_with(\$link, \$locPrefix) || \$link === '/' . \$code) {
                    \$warnings[] = \"\$itemPath link '\$link' has a hardcoded locale prefix '\$locPrefix'. Remove it; Twig's locale_link() will add locale prefixes dynamically.\";
                }
            }
        }

        // Submenu recursion
        if (\$hasSubmenu) {
            validateItems(\$item['submenu'], \$menuName, \$itemPath . '.submenu', \$configuredLocales, \$knownSlugs, \$errors, \$warnings);
        }
    }
}

foreach (\$menuData as \$menuKey => \$items) {
    if (!is_array(\$items)) continue;
    validateItems(\$items, \$menuKey, \$menuKey, \$configuredLocales, \$knownSlugs, \$errors, \$warnings);
}

// Output results
echo 'ERRORS_COUNT:' . count(\$errors) . PHP_EOL;
echo 'WARNINGS_COUNT:' . count(\$warnings) . PHP_EOL;
foreach (\$errors as \$err) {
    echo 'ERROR: ' . \$err . PHP_EOL;
}
foreach (\$warnings as \$warn) {
    echo 'WARN: ' . \$warn . PHP_EOL;
}
")

ERR_COUNT=$(echo "$PHP_CHECK_OUTPUT" | grep "^ERRORS_COUNT:" | cut -d':' -f2 || echo 0)
WARN_COUNT=$(echo "$PHP_CHECK_OUTPUT" | grep "^WARNINGS_COUNT:" | cut -d':' -f2 || echo 0)

if [ "$ERR_COUNT" -gt 0 ]; then
    echo "FAILED ($ERR_COUNT errors found)"
    echo "$PHP_CHECK_OUTPUT" | grep "^ERROR: " | sed 's/^ERROR: /  - /'
    FAILED=1
else
    echo "PASSED (0 schema errors)"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
    echo "$PHP_CHECK_OUTPUT" | grep "^WARN: " | sed 's/^WARN: /  [!] /'
    WARNINGS=$((WARNINGS + WARN_COUNT))
fi

# -------------------------------------------------------------
# 4. Check active theme integration
# -------------------------------------------------------------
echo -n "[4/5] Checking theme navigation templates... "
ACTIVE_THEME=""
if [ -f "$BOLT_CONFIG" ]; then
    ACTIVE_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
fi

if [ -n "$ACTIVE_THEME" ] && [ -d "public/theme/$ACTIVE_THEME" ]; then
    THEME_DIR="public/theme/$ACTIVE_THEME"
    # Search for menu_array in theme
    MENU_CALLS=$(grep -rn "menu_array" "$THEME_DIR" --include="*.twig" 2>/dev/null || true)
    if [ -n "$MENU_CALLS" ]; then
        echo "PASSED (Found menu_array calls in theme '$ACTIVE_THEME')"
    else
        echo "WARNING"
        echo "  Notice: Theme 'public/theme/$ACTIVE_THEME' does not call 'menu_array(...)'. Make sure header/footer templates render menu dynamically."
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED (No active theme directory detected)"
fi

# -------------------------------------------------------------
# 5. Check locale_link usage with menu links
# -------------------------------------------------------------
echo -n "[5/5] Checking locale_link wrapping on navigation URLs... "
if [ -n "$ACTIVE_THEME" ] && [ -d "public/theme/$ACTIVE_THEME" ]; then
    THEME_DIR="public/theme/$ACTIVE_THEME"
    LOCALE_LINK_CALLS=$(grep -rn "locale_link(" "$THEME_DIR" --include="*.twig" 2>/dev/null || true)
    if [ -n "$LOCALE_LINK_CALLS" ]; then
        echo "PASSED (Found locale_link calls in templates)"
    else
        echo "WARNING"
        echo "  Notice: Theme 'public/theme/$ACTIVE_THEME' does not appear to call 'locale_link(...)'. In multilingual sites, links may lose the active locale prefix."
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "SKIPPED"
fi

echo "=========================================================="
if [ $FAILED -ne 0 ]; then
    echo " VERIFICATION FAILED ($ERR_COUNT errors, $WARNINGS warnings)"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo " VERIFICATION PASSED with $WARNINGS warning(s)."
    exit 0
else
    echo " VERIFICATION PASSED (All checks green)."
    exit 0
fi
