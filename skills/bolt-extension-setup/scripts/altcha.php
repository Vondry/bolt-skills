<?php

declare(strict_types=1);

/*
 * ALTCHA configuration (bolt-extension-setup section 5), run by verify.sh from the project root
 * once tomvondracek/bolt-altcha is installed.
 *
 * Checks that Bolt's login and both password reset forms are protected, that the published widget
 * matches the installed extension, that the sign-in templates of the theme keep the widget slot and
 * the field's form theme, and that a signing key can be strong. Prints one line per finding:
 * `OK|…`, `WARN|…` or `FAIL|…`.
 *
 * Usage: php altcha.php <config file> <theme dir>
 */

use Symfony\Component\Yaml\Yaml;

[, $configFile, $themeDir] = $argv + [null, 'config/extensions/tomvondracek-altcha.yaml', 'public/theme/default'];
if (! is_file('vendor/autoload.php')) {
    echo "WARN|vendor/autoload.php missing — run composer install to check the ALTCHA config\n";
    exit;
}
require 'vendor/autoload.php';

$read = static function (string $file): array {
    if (! is_file($file)) {
        return [];
    }
    try {
        $data = Yaml::parseFile($file);
    } catch (Throwable $e) {
        echo "FAIL|$file is not valid YAML: {$e->getMessage()}\n";

        return [];
    }

    return is_array($data) ? $data : [];
};

$config = $read($configFile);
$local = $read((string) preg_replace('/\.yaml$/', '_local.yaml', $configFile));

if (($config['enabled'] ?? true) === false) {
    echo "FAIL|enabled: false in $configFile — nothing is protected\n";
} elseif (($local['enabled'] ?? true) === false) {
    echo "WARN|enabled: false in the _local.yaml override — fine on a development machine, never upload it\n";
}

// Bolt's own forms: the login and both reset forms (section 5.3).
$bolt = is_array($config['bolt'] ?? null) ? $config['bolt'] : [];
$off = [];
foreach (['login' => '/bolt/login', 'reset_password' => 'the reset request', 'change_password' => 'the new-password form'] as $key => $form) {
    $value = $bolt[$key] ?? false;
    if ($value === false || $value === null || $value === '') {
        $off[] = "bolt.$key ($form)";
    }
}
echo $off === []
    ? "OK|bolt.login, bolt.reset_password and bolt.change_password are protected\n"
    : 'FAIL|not protected: ' . implode(', ', $off) . " — set them to true in $configFile (section 5.3)\n";

// The widget published by extensions:configure must be the installed extension's.
$renderer = (string) @file_get_contents('vendor/tomvondracek/bolt-altcha/src/Widget/WidgetRenderer.php');
$expected = preg_match("/ASSETS_VERSION\\s*=\\s*'([^']+)'/", $renderer, $m) ? $m[1] : null;
$published = is_file('public/assets/altcha/VERSION') ? trim((string) file_get_contents('public/assets/altcha/VERSION')) : null;
if ($published === null) {
    echo "FAIL|public/assets/altcha/ is not published — every check stands down (run: php bin/console extensions:configure)\n";
} elseif ($expected !== null && $published !== $expected) {
    echo "FAIL|public/assets/altcha/ holds widget $published, the extension expects $expected (run: php bin/console extensions:configure)\n";
} else {
    echo "OK|widget $published published in public/assets/altcha/\n";
}

// The theme's sign-in templates (theme.yaml): the login prints the `login_middle` slot, and a
// template that sets its form themes with `only` adds the ALTCHA one, or the field is a text input.
$theme = $read("$themeDir/theme.yaml");
$templates = array_filter([
    'login_template' => $theme['login_template'] ?? null,
    'reset_password_settings.request_template' => $theme['reset_password_settings']['request_template'] ?? null,
    'reset_password_settings.reset_template' => $theme['reset_password_settings']['reset_template'] ?? null,
], 'is_string');
$problems = [];
foreach ($templates as $key => $template) {
    $file = "$themeDir/" . preg_replace('{^@theme/}', '', $template);
    $source = (string) @file_get_contents($file);
    if ($source === '') {
        continue;
    }
    if ($key === 'login_template' && ! str_contains($source, "widgets('login_middle')")) {
        $problems[] = "$template has no {{ widgets('login_middle') }}, where the login widget renders";
    }
    if (preg_match('/\{%-?\s*form_theme\b[^%]*\bonly\s*-?%\}/', $source) && ! str_contains($source, '@bolt-altcha/form/altcha.html.twig')) {
        $problems[] = "$template sets its form themes with `only` without '@bolt-altcha/form/altcha.html.twig'";
    }
}
if ($problems !== []) {
    echo 'FAIL|' . implode('; ', $problems) . " (section 5.4)\n";
} elseif ($templates !== []) {
    echo 'OK|the theme\'s sign-in templates render the widget (' . implode(', ', array_keys($templates)) . ")\n";
}

// The signing key: ALTCHA_HMAC_KEY, else derived from APP_SECRET. Secrets live in the server's
// .env.local (bolt-security-hardening Step 1), so .env can only hint at it.
$env = is_file('.env') ? (string) file_get_contents('.env') : '';
$value = static fn (string $name): ?string => preg_match_all('/^\s*' . $name . '=(.*)$/m', $env, $m) ? trim(trim((string) end($m[1])), "'\"") : null;
$hmac = $value('ALTCHA_HMAC_KEY');
$secret = $value('APP_SECRET');
if ($hmac !== null && $hmac !== '' && strlen($hmac) >= 32) {
    echo "OK|ALTCHA_HMAC_KEY is set in .env\n";
} elseif ($secret !== null && $secret !== '!ChangeMe!' && strlen($secret) >= 32) {
    echo "OK|the signing key is derived from APP_SECRET (32+ characters in .env)\n";
} else {
    echo "WARN|.env has no strong APP_SECRET or ALTCHA_HMAC_KEY — the server's .env.local must set one (32+ characters), or the protection switches off (section 5.2)\n";
}
