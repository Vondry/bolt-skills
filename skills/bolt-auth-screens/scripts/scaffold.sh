#!/usr/bin/env bash
set -e

# bolt-auth-screens scaffold: copies the shared sign-in templates, js/bolt-auth.js and the fonts
# into the active theme, the security layer into src/ and config/packages/, wires the templates
# in theme.yaml with the project's bolt_auth block, keeps bolt-auth/ out of Tailwind's class scan
# and merges the bolt_auth translation units.
# Existing files and keys are kept, so it can be repeated; --update replaces the shared files
# (templates, script, fonts) with the skill's version and never touches theme.yaml values.
#
# Usage: scaffold.sh [--brand-deep=#… --brand=#… --brand-2=#… --accent=#… [--accent-hover=#…]]
#                    [--logo=img/logo.svg] [--logo-size=WxH] [--mark=img/mark.svg|none] [--update]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../examples" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

UPDATE=0
BLOCK_OPTIONS=()
for argument in "$@"; do
    case "$argument" in
        --update) UPDATE=1 ;;
        --brand-deep=*|--brand=*|--brand-2=*|--accent=*|--accent-hover=*|--logo=*|--logo-size=*|--mark=*) BLOCK_OPTIONS+=("$argument") ;;
        *) sed -n '10,11p' "${BASH_SOURCE[0]}" | sed 's/^# //'; exit 1 ;;
    esac
done

BASE_DIR="$(pwd)"
while [ "$BASE_DIR" != "/" ] && [ ! -f "$BASE_DIR/config/services.yaml" ]; do
    BASE_DIR="$(dirname "$BASE_DIR")"
done
if [ ! -f "$BASE_DIR/config/services.yaml" ]; then
    echo "ERROR: run this inside a Bolt project (config/services.yaml not found)."
    exit 1
fi
cd "$BASE_DIR"

THEME="$(grep -E '^theme:' config/bolt/config.yaml | head -n 1 | sed -E 's/^theme:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' ")"
THEME_DIR="public/theme/$THEME"
if [ -z "$THEME" ] || [ ! -f "$THEME_DIR/theme.yaml" ]; then
    echo "ERROR: active theme not found (theme: in config/bolt/config.yaml, $THEME_DIR/theme.yaml)."
    exit 1
fi

install_file() {
    mkdir -p "$(dirname "$2")"
    if [ -e "$2" ] && [ $UPDATE -eq 0 ]; then
        echo "  kept    $2"
    elif [ -e "$2" ] && cmp -s "$1" "$2"; then
        echo "  same    $2"
    else
        [ -e "$2" ] && state="updated" || state="created"
        cp "$1" "$2"
        echo "  $state $2"
    fi
}

for template in "$EXAMPLES_DIR"/bolt-auth/*.twig; do
    install_file "$template" "$THEME_DIR/bolt-auth/$(basename "$template")"
done
install_file "$EXAMPLES_DIR/bolt-auth.js" "$THEME_DIR/js/bolt-auth.js"
# The security layer: rate limits, strict headers, password policy on the reset form.
install_file "$EXAMPLES_DIR/src/BoltAuthSecuritySubscriber.php" "src/BoltAuthSecuritySubscriber.php"
install_file "$EXAMPLES_DIR/src/BoltAuthPasswordPolicyExtension.php" "src/BoltAuthPasswordPolicyExtension.php"
install_file "$EXAMPLES_DIR/config/bolt_auth.yaml" "config/packages/bolt_auth.yaml"
if [ ! -d vendor/symfony/rate-limiter ]; then
    echo "  next    composer require symfony/rate-limiter (the rate limits need it)"
fi
if grep -q '"name": "tomvondracek/bolt-altcha"' composer.lock 2>/dev/null && ! grep -qE "^  bolt_auth.trusted_types:.*svelte-trusted-html" config/packages/bolt_auth.yaml; then
    sed -i.bak "s/^  bolt_auth.trusted_types: \[ \]$/  bolt_auth.trusted_types: [ 'svelte-trusted-html' ]/" config/packages/bolt_auth.yaml && rm -f config/packages/bolt_auth.yaml.bak
    echo "  updated config/packages/bolt_auth.yaml (Trusted Types policy of the ALTCHA login widget)"
fi
for font in "$EXAMPLES_DIR"/fonts/*; do
    install_file "$font" "$THEME_DIR/css/fonts/instrument/$(basename "$font")"
done

if grep -qE '^(login_template|bolt_auth):' "$THEME_DIR/theme.yaml"; then
    echo "  kept    login_template / bolt_auth in theme.yaml"
else
    php "$SCRIPT_DIR/auth-screens.php" block "${BLOCK_OPTIONS[@]}" >> "$THEME_DIR/theme.yaml"
    echo "  added   login_template, reset_password_settings and bolt_auth to theme.yaml"
fi

CSS_SOURCE="$THEME_DIR/css/tailwind/index.css"
if [ -f "$CSS_SOURCE" ] && ! grep -q '\.\./\.\./bolt-auth' "$CSS_SOURCE"; then
    # shellcheck disable=SC2016  # PHP code, not shell expansions
    php -r '
        $file = $argv[1];
        $rule = "\n/* The sign-in screens style themselves inline (bolt-auth-screens) */\n@source not \"../../bolt-auth\";\n";
        $css = file_get_contents($file);
        // After the last @source rule, else after the last @import, else at the top.
        if (preg_match_all("/^@(?:source|import)\b[^\n]*\n/m", $css, $matches, PREG_OFFSET_CAPTURE)) {
            $sources = array_filter($matches[0], static fn (array $m): bool => str_starts_with($m[0], "@source"));
            $last = end($sources) ?: end($matches[0]);
            $position = $last[1] + strlen($last[0]);
        } else {
            $position = 0;
            $rule = ltrim($rule) . "\n";
        }
        file_put_contents($file, substr($css, 0, $position) . $rule . substr($css, $position));
    ' "$CSS_SOURCE"
    echo "  updated $CSS_SOURCE (@source not bolt-auth)"
fi

for catalog in translations/messages.*.xlf; do
    [ -f "$catalog" ] || continue
    locale="$(basename "$catalog" .xlf)"
    locale="${locale#messages.}"
    source="$EXAMPLES_DIR/translations.$locale.xlf"
    if [ -f "$source" ]; then
        php "$SKILLS_ROOT/scripts/merge-xliff.php" "$source" "$catalog" > /dev/null
        echo "  merged  $catalog (bolt_auth.*)"
    else
        echo "  next    php $SKILLS_ROOT/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf $catalog — then translate the four targets"
    fi
done

echo ""
echo "Next:"
echo "  1. Fill in bolt_auth in $THEME_DIR/theme.yaml (SKILL.md, Step 2) — php $SCRIPT_DIR/auth-screens.php colors … checks the colours"
echo "  2. Put the logo (and the watermark mark) into $THEME_DIR/img/"
echo "  3. php bin/console cache:clear, then open the login screen"
echo "  4. bash $SCRIPT_DIR/verify.sh"
