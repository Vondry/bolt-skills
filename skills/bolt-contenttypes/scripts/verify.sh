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

CT_FILE="config/bolt/contenttypes.yaml"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: ContentTypes configuration file '$CT_FILE' not found in $BASE_DIR."
    exit 1
fi

echo "=========================================================="
echo " Bolt CMS ContentTypes & Fields Verification"
echo " Project root: $BASE_DIR"
echo " Config file:  $CT_FILE"
echo "=========================================================="

FAILED=0

# Step 1: YAML Linting
echo -n "[1/2] Checking YAML syntax for $CT_FILE... "
if [ -f "bin/console" ] && php bin/console lint:yaml "$CT_FILE" --parse-tags > /dev/null 2>&1; then
    echo "PASSED"
elif php -r "require 'vendor/autoload.php'; \Symfony\Component\Yaml\Yaml::parseFile('$CT_FILE');" > /dev/null 2>&1; then
    echo "PASSED"
else
    echo "FAILED"
    if [ -f "bin/console" ]; then
        php bin/console lint:yaml "$CT_FILE" --parse-tags || true
    else
        php -r "require 'vendor/autoload.php'; \Symfony\Component\Yaml\Yaml::parseFile('$CT_FILE');" || true
    fi
    exit 1
fi

# Step 2: ContentType and Field Rules Validation via PHP Runner
echo "[2/2] Validating ContentType and field rules against Bolt best practices..."

CHECK_OUTPUT=$(php -r "
if (file_exists('vendor/autoload.php')) {
    require 'vendor/autoload.php';
} else {
    echo 'ERROR: vendor/autoload.php not found. Run composer install first.' . PHP_EOL;
    exit(1);
}

use Symfony\Component\Yaml\Yaml;

\$ctFile = '$CT_FILE';
\$servicesFile = 'config/services.yaml';

try {
    \$config = Yaml::parseFile(\$ctFile);
} catch (\Throwable \$e) {
    echo 'ERROR: Failed to parse ' . \$ctFile . ': ' . \$e->getMessage() . PHP_EOL;
    exit(1);
}

// Read app_locales from services.yaml
\$appLocales = [];
if (file_exists(\$servicesFile)) {
    try {
        \$services = Yaml::parseFile(\$servicesFile);
        \$localesParam = \$services['parameters']['app_locales'] ?? \$services['parameters']['locales_array'] ?? null;
        if (is_string(\$localesParam)) {
            \$appLocales = array_filter(array_map('trim', explode('|', \$localesParam)));
        } elseif (is_array(\$localesParam)) {
            \$appLocales = \$localesParam;
        }
    } catch (\Throwable \$e) {}
}

\$errors = [];
\$warnings = [];

function validateFields(\$fields, \$prefix, \$isLocalized, &\$errors, &\$warnings) {
    foreach (\$fields as \$fieldName => \$fieldDef) {
        if (!is_array(\$fieldDef)) continue;
        \$path = \$prefix . '.' . \$fieldName;
        \$type = \$fieldDef['type'] ?? '';

        // Rule: Do not use 'html' field type
        if (\$type === 'html') {
            \$errors[] = sprintf(
                \"[FORBIDDEN FIELD TYPE] '%s' uses 'type: html'. Do not use raw 'html'. Use 'type: redactor' for standard WYSIWYG text or 'type: article' for structured editorial content.\",
                \$path
            );
        }

        // Rule: Do not use deprecated 'repeater' field type
        if (\$type === 'repeater') {
            \$errors[] = sprintf(
                \"[DEPRECATED FIELD TYPE] '%s' uses 'type: repeater'. In Bolt 6, repeaters are replaced by 'type: collection' and 'type: set'.\",
                \$path
            );
        }

        // Rule: Localized ContentType required field trap
        if (\$isLocalized && !empty(\$fieldDef['required']) && empty(\$fieldDef['localize'])) {
            // Slug, template, templateselect, relations can be non-localized if handled by router/template
            if (!in_array(\$type, ['slug', 'templateselect', 'template', 'hidden'], true)) {
                \$warnings[] = sprintf(
                    \"[MULTILINGUAL WARNING] '%s' is marked 'required: true' but lacks 'localize: true' in a localized ContentType. Translating records in secondary locales will trigger form validation errors unless this field is localized.\",
                    \$path
                );
            }
        }

        // Rule: rich text is sanitised on output (Bolt only defaults sanitise for text, textarea, html, markdown)
        if (in_array(\$type, ['redactor', 'article'], true) && (\$fieldDef['sanitise'] ?? false) !== true) {
            \$errors[] = sprintf(
                \"[UNSANITISED RICH TEXT] '%s' (type: %s) lacks 'sanitise: true'. Redactor and Article render their HTML unescaped, so an editor can store scripts that run for every visitor (stored XSS). Add 'sanitise: true' (rule 7).\",
                \$path,
                \$type
            );
        } elseif (array_key_exists('sanitise', \$fieldDef) && \$fieldDef['sanitise'] === false) {
            \$errors[] = sprintf(
                \"[SANITISE DISABLED] '%s' sets 'sanitise: false' — its HTML is output without cleaning (stored XSS). Remove the line (rule 7).\",
                \$path
            );
        }

        // Rule: never render field content as a Twig template
        if (!empty(\$fieldDef['allow_twig'])) {
            \$errors[] = sprintf(
                \"[ALLOW_TWIG] '%s' sets 'allow_twig: true' — its content runs as a server-side Twig template, so an editor account becomes control of the site. Remove it (rule 7).\",
                \$path
            );
        }

        // Rule: Slug field must specify 'uses'
        if (\$type === 'slug' && empty(\$fieldDef['uses'])) {
            \$errors[] = sprintf(
                \"[SLUG CONFIGURATION] '%s' is a slug field but is missing the 'uses' attribute (e.g. 'uses: title' or 'uses: [title]').\",
                \$path
            );
        }

        // Recurse into nested fields (sets, collections)
        if (isset(\$fieldDef['fields']) && is_array(\$fieldDef['fields'])) {
            validateFields(\$fieldDef['fields'], \$path, \$isLocalized, \$errors, \$warnings);
        }
    }
}

foreach (\$config as \$ctKey => \$ctDef) {
    // Ignore internal YAML anchors / nodes
    if (str_starts_with(\$ctKey, '__')) {
        continue;
    }

    if (!is_array(\$ctDef)) {
        \$errors[] = sprintf(\"[MALFORMED CONTENTTYPE] '%s' must be an associative mapping of settings.\", \$ctKey);
        continue;
    }

    // Check mandatory identifiers
    if (empty(\$ctDef['name']) && empty(\$ctDef['slug'])) {
        \$errors[] = sprintf(\"[MISSING NAME/SLUG] ContentType '%s' must specify either 'name' or 'slug'.\", \$ctKey);
    }
    if (empty(\$ctDef['singular_name']) && empty(\$ctDef['singular_slug'])) {
        \$errors[] = sprintf(\"[MISSING SINGULAR NAME] ContentType '%s' must specify either 'singular_name' or 'singular_slug'.\", \$ctKey);
    }
    if (empty(\$ctDef['fields']) || !is_array(\$ctDef['fields'])) {
        \$errors[] = sprintf(\"[MISSING FIELDS] ContentType '%s' must define a non-empty 'fields' mapping.\", \$ctKey);
        continue;
    }

    // Rule: Singletons must specify 'order: -id'
    \$isSingleton = !empty(\$ctDef['singleton']);
    if (\$isSingleton) {
        \$order = \$ctDef['order'] ?? \$ctDef['sort'] ?? null;
        if (\$order !== '-id' && \$order !== ['-id']) {
            \$actual = var_export(\$order, true);
            \$errors[] = sprintf(
                \"[SINGLETON ORDER MISSING] ContentType '%s' is a singleton ('singleton: true') but 'order: -id' is missing (currently %s). House rule (Bolt docs recommend 'sort: -id': https://docs.boltcms.io/5.2/howto/singleton-contenttype): singletons MUST have 'order: -id' to guarantee template fetches ({%% setcontent ... %%}) always retrieve the latest valid record if IDs increment.\",
                \$ctKey,
                \$actual
            );
        }

        if (!empty(\$ctDef['viewless']) && empty(\$ctDef['default_status'])) {
            \$warnings[] = sprintf(
                \"[SINGLETON STATUS ADVICE] Viewless singleton '%s' does not specify 'default_status: published'. Adding 'default_status: published' ensures settings records are active upon initial save.\",
                \$ctKey
            );
        }
    }

    // Check locales against app_locales
    \$isLocalized = !empty(\$ctDef['locales']);
    if (\$isLocalized && !empty(\$appLocales)) {
        \$ctLocales = (array) \$ctDef['locales'];
        \$diff = array_diff(\$ctLocales, \$appLocales);
        if (!empty(\$diff)) {
            \$errors[] = sprintf(
                \"[UNKNOWN LOCALES] ContentType '%s' requests locales [%s] which are not declared in config/services.yaml app_locales [%s].\",
                \$ctKey,
                implode(', ', \$diff),
                implode(', ', \$appLocales)
            );
        }
    }

    // Validate fields recursively
    validateFields(\$ctDef['fields'], \$ctKey, \$isLocalized, \$errors, \$warnings);
}

// Output results
if (!empty(\$errors)) {
    echo 'ERRORS_FOUND:' . count(\$errors) . PHP_EOL;
    foreach (\$errors as \$err) {
        echo '  ❌ ' . \$err . PHP_EOL;
    }
}

if (!empty(\$warnings)) {
    echo 'WARNINGS_FOUND:' . count(\$warnings) . PHP_EOL;
    foreach (\$warnings as \$warn) {
        echo '  ⚠️  ' . \$warn . PHP_EOL;
    }
}

if (empty(\$errors) && empty(\$warnings)) {
    echo 'ALL_RULES_PASSED' . PHP_EOL;
}
")

if echo "$CHECK_OUTPUT" | grep -q "ERRORS_FOUND:"; then
    echo "$CHECK_OUTPUT"
    echo ""
    echo "=========================================================="
    echo " Verification FAILED with errors. Please fix the violations listed above."
    echo "=========================================================="
    exit 1
elif echo "$CHECK_OUTPUT" | grep -q "WARNINGS_FOUND:"; then
    echo "$CHECK_OUTPUT"
    echo ""
    echo "=========================================================="
    echo " Verification PASSED with warnings. ContentTypes meet primary rules."
    echo "=========================================================="
    exit 0
else
    echo "  ✅ All ContentTypes and fields strictly conform to Bolt CMS rules & best practices!"
    echo "=========================================================="
    echo " ContentTypes verification PASSED."
    echo "=========================================================="
    exit 0
fi
