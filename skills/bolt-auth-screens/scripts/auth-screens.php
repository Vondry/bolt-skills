<?php

declare(strict_types=1);

/*
 * bolt-auth-screens helper.
 *
 *   php auth-screens.php colors --brand-deep=#… --brand=#… --brand-2=#… --accent=#… [--accent-hover=#…]
 *       Derives accent_hover (when not given), on_accent and accent_line, checks every contrast
 *       the design relies on and prints the bolt_auth colour block for theme.yaml.
 *
 *   php auth-screens.php block [the colour options] [--logo=img/…] [--logo-size=WxH] [--mark=img/…|none]
 *       Prints the theme.yaml block (template wiring + bolt_auth) for scaffold.sh. Without the
 *       colours it writes placeholders, which verify.sh reports until they are filled in.
 *
 *   php auth-screens.php check <project-root> [--base-url=http://…] [--rate-limit-test=1]
 *       Verification used by verify.sh. Prints lines starting with SECTION, PASS, WARN or FAIL.
 *       With --base-url it also requests the login and reset-request screens from that site and
 *       checks their security headers and cookies; --rate-limit-test=1 (a local site only) sends
 *       reset requests until the limiter answers, without a valid CSRF token, so no e-mail is sent.
 */

const COLOR_KEYS = ['brand_deep', 'brand', 'brand_2', 'accent', 'accent_hover', 'on_accent', 'accent_line'];
const TEMPLATES = ['_layout.twig', '_macros.twig', '_styles.twig', 'login.twig', 'reset-request.twig', 'check-email.twig', 'reset.twig'];
const FONTS = ['instrument-sans-latin.woff2', 'instrument-sans-latin-ext.woff2', 'instrument-serif-latin.woff2', 'instrument-serif-latin-ext.woff2'];
const WIRING = [
    'login_template' => 'bolt-auth/login.twig',
    'reset_password_settings.request_template' => 'bolt-auth/reset-request.twig',
    'reset_password_settings.check_email_template' => 'bolt-auth/check-email.twig',
    'reset_password_settings.reset_template' => 'bolt-auth/reset.twig',
];
const FIELD = '#ffffff';
const DARK_LABEL = '#09090b';

$mode = $argv[1] ?? '';
$options = [];
$positional = [];
foreach (array_slice($argv, 2) as $argument) {
    if (preg_match('/^--([a-z0-9-]+)=(.*)$/', $argument, $match)) {
        $options[$match[1]] = $match[2];
    } else {
        $positional[] = $argument;
    }
}

exit(match ($mode) {
    'colors' => colors($options),
    'block' => block($options),
    'check' => check($positional[0] ?? getcwd(), $options['base-url'] ?? '', ($options['rate-limit-test'] ?? '') === '1'),
    default => usage(),
});

function usage(): int
{
    fwrite(STDERR, "Usage: php auth-screens.php colors --brand-deep=#… --brand=#… --brand-2=#… --accent=#… [--accent-hover=#…]\n");
    fwrite(STDERR, "       php auth-screens.php check <project-root> [--base-url=http://…]\n");

    return 2;
}

// ------------------------------------------------------------------------------------------------
// Colour maths (WCAG 2.x relative luminance)
// ------------------------------------------------------------------------------------------------

function normalizeHex(string $value): ?string
{
    $value = strtolower(trim($value, " \t'\""));
    if (preg_match('/^#([0-9a-f])([0-9a-f])([0-9a-f])$/', $value, $m)) {
        return '#' . $m[1] . $m[1] . $m[2] . $m[2] . $m[3] . $m[3];
    }

    return preg_match('/^#[0-9a-f]{6}$/', $value) ? $value : null;
}

/** @return array{float, float, float} */
function rgb(string $hex): array
{
    return [hexdec(substr($hex, 1, 2)), hexdec(substr($hex, 3, 2)), hexdec(substr($hex, 5, 2))];
}

/** @param array{float, float, float} $rgb */
function toHex(array $rgb): string
{
    return sprintf('#%02x%02x%02x', ...array_map(static fn (float $c): int => (int) round(max(0, min(255, $c))), $rgb));
}

function luminance(string $hex): float
{
    $channels = array_map(static function (float $c): float {
        $c /= 255;

        return $c <= 0.03928 ? $c / 12.92 : (($c + 0.055) / 1.055) ** 2.4;
    }, rgb($hex));

    return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2];
}

function contrast(string $a, string $b): float
{
    $la = luminance($a);
    $lb = luminance($b);

    return (max($la, $lb) + 0.05) / (min($la, $lb) + 0.05);
}

/** A colour at `alpha` laid over `base`. */
function over(string $color, float $alpha, string $base): string
{
    $c = rgb($color);
    $b = rgb($base);

    return toHex([$c[0] * $alpha + $b[0] * (1 - $alpha), $c[1] * $alpha + $b[1] * (1 - $alpha), $c[2] * $alpha + $b[2] * (1 - $alpha)]);
}

/** One step darker, for a site without its own hover colour: towards black by `amount`. */
function darken(string $hex, float $amount): string
{
    return toHex(array_map(static fn (float $c): float => $c * (1 - $amount), rgb($hex)));
}

/**
 * Derives the dependent tokens from the four the site gives.
 *
 * @return array<string, string>
 */
function derive(string $brandDeep, string $brand, string $brand2, string $accent, ?string $accentHover): array
{
    $accentHover ??= darken($accent, 0.12);

    // Label: white when it holds 4.5:1 on both button states, else dark — the site's own darkest
    // colour when that passes, else near-black.
    $onAccent = FIELD;
    if (contrast(FIELD, $accent) < 4.5 || contrast(FIELD, $accentHover) < 4.5) {
        $onAccent = contrast($brandDeep, $accent) >= 4.5 && contrast($brandDeep, $accentHover) >= 4.5 ? $brandDeep : DARK_LABEL;
    }

    // Checkbox border and tick on white: 3:1 (non-text contrast).
    $accentLine = $accent;
    if (contrast($accent, FIELD) < 3) {
        $accentLine = $accentHover;
        while (contrast($accentLine, FIELD) < 3) {
            $accentLine = darken($accentLine, 0.04);
        }
    }

    return [
        'brand_deep' => $brandDeep,
        'brand' => $brand,
        'brand_2' => $brand2,
        'accent' => $accent,
        'accent_hover' => $accentHover,
        'on_accent' => $onAccent,
        'accent_line' => $accentLine,
    ];
}

/**
 * Every contrast the design relies on: [level, message] with level PASS, WARN or FAIL.
 *
 * @param array<string, string> $c
 *
 * @return list<array{string, string}>
 */
function contrastFindings(array $c): array
{
    $findings = [];
    $add = static function (string $level, string $message) use (&$findings): void {
        $findings[] = [$level, $message];
    };

    $panelMuted = over(FIELD, 0.7, $c['brand_deep']);
    $ratio = contrast($panelMuted, $c['brand_deep']);
    $add($ratio >= 4.5 ? 'PASS' : 'FAIL', sprintf('domain link (white 70%%) on brand_deep %s: %.2f:1 (needs 4.5)', $c['brand_deep'], $ratio));

    $ratio = contrast(FIELD, $c['brand_deep']);
    $add($ratio >= 7 ? 'PASS' : 'WARN', sprintf('site name (white) on brand_deep: %.2f:1 (aim for 7; take the site\'s darkest colour)', $ratio));

    foreach (['accent', 'accent_hover'] as $key) {
        $ratio = contrast($c['on_accent'], $c[$key]);
        $add($ratio >= 4.5 ? 'PASS' : 'FAIL', sprintf('button label on_accent %s on %s %s: %.2f:1 (needs 4.5)', $c['on_accent'], $key, $c[$key], $ratio));
    }

    $ratio = contrast($c['accent_line'], FIELD);
    $add($ratio >= 3 ? 'PASS' : 'FAIL', sprintf('checkbox accent_line %s on white: %.2f:1 (needs 3)', $c['accent_line'], $ratio));
    // accent_line is the accent; when that is under 3:1 on white, accent_hover; when that is too,
    // a darker shade of it (what `colors` derives).
    if (contrast($c['accent'], FIELD) >= 3) {
        if ($c['accent_line'] !== $c['accent']) {
            $add('WARN', 'accent_line differs from accent although accent holds 3:1 on white — use accent');
        }
    } elseif (contrast($c['accent_hover'], FIELD) >= 3 && $c['accent_line'] !== $c['accent_hover']) {
        $add('WARN', 'accent is under 3:1 on white, so accent_line takes accent_hover');
    }

    if ($c['accent_hover'] === $c['accent']) {
        $add('WARN', 'accent_hover equals accent — the button needs a visible hover step');
    }

    return $findings;
}

/** @param array<string, string> $options */
function colors(array $options): int
{
    $values = [];
    foreach (['brand-deep', 'brand', 'brand-2', 'accent'] as $name) {
        $values[$name] = normalizeHex($options[$name] ?? '');
        if ($values[$name] === null) {
            fwrite(STDERR, "ERROR: --$name=#rrggbb is required\n");

            return usage();
        }
    }
    $hover = isset($options['accent-hover']) ? normalizeHex($options['accent-hover']) : null;
    if (isset($options['accent-hover']) && $hover === null) {
        fwrite(STDERR, "ERROR: --accent-hover must be #rrggbb\n");

        return 2;
    }

    $c = derive($values['brand-deep'], $values['brand'], $values['brand-2'], $values['accent'], $hover);
    $failed = false;
    echo "Contrast:\n";
    foreach (contrastFindings($c) as [$level, $message]) {
        echo '  ' . ['PASS' => '✓', 'WARN' => '⚠', 'FAIL' => '✗'][$level] . " $message\n";
        $failed = $failed || $level === 'FAIL';
    }
    if ($hover === null) {
        echo "  ⚠ accent_hover derived ({$c['accent_hover']}); prefer the site's own hover colour (--accent-hover=)\n";
    }

    echo "\ntheme.yaml → bolt_auth:\n";
    foreach ($c as $key => $value) {
        printf("  %-13s '%s'\n", $key . ':', $value);
    }
    if ($failed) {
        echo "\nA contrast fails: take a darker brand_deep, or another accent from the site.\n";
    }

    return $failed ? 1 : 0;
}

/** @param array<string, string> $options */
function block(array $options): int
{
    $given = array_map(static fn (string $name): ?string => normalizeHex($options[$name] ?? ''), ['brand-deep' => 'brand-deep', 'brand' => 'brand', 'brand-2' => 'brand-2', 'accent' => 'accent']);
    $colors = array_fill_keys(COLOR_KEYS, '#…');
    if (! in_array(null, $given, true)) {
        $colors = derive($given['brand-deep'], $given['brand'], $given['brand-2'], $given['accent'], normalizeHex($options['accent-hover'] ?? ''));
    }
    [$width, $height] = preg_match('/^(\d+)x(\d+)$/', $options['logo-size'] ?? '', $m) ? [$m[1], $m[2]] : ['48', '48'];
    $mark = $options['mark'] ?? 'none';
    $mark = $mark === 'none' || $mark === '' ? '~' : "'$mark'";
    $logo = $options['logo'] ?? 'img/logo.svg';

    $comments = [
        'brand_deep' => 'panel base: the site\'s own darkest colour, white text on it',
        'brand' => 'main glow, top right: the colour people know the site by (never text)',
        'brand_2' => 'quieter glow, bottom left: a supporting colour of the site (never text)',
        'accent' => 'primary button, link underline, focus halo, eyebrow lock',
        'accent_hover' => 'button hover: the site\'s own hover step of the accent',
        'on_accent' => 'button label: white, or dark when white fails 4.5:1 on the accent',
        'accent_line' => 'checkbox border and tick: accent, or accent_hover when accent < 3:1 on white',
    ];
    echo "\n# bolt-auth-screens: Bolt's sign-in screens render from the theme's bolt-auth/ templates.\n";
    echo "login_template: '" . WIRING['login_template'] . "'\n";
    echo "reset_password_settings:\n";
    foreach (WIRING as $path => $template) {
        if (str_starts_with($path, 'reset_password_settings.')) {
            echo '  ' . substr($path, strlen('reset_password_settings.')) . ": '$template'\n";
        }
    }
    echo "\n# bolt-auth-screens: the only things a project changes on those screens (SKILL.md, Step 2).\n";
    echo "bolt_auth:\n";
    foreach ($colors as $key => $value) {
        printf("  %-23s # %s\n", "$key: '$value'", $comments[$key]);
    }
    printf("  %-23s # %s\n", "logo: '$logo'", 'the dark / colour logo: it sits on a white badge');
    printf("  %-23s # %s\n", "logo_width: $width", 'px in the badge on desktop (x0.78 on phones)');
    printf("  %-23s # %s\n", "logo_height: $height", 'aim for 40-49 px');
    printf("  %-23s # %s\n", "mark: $mark", 'symbol for the faint watermark (shape with transparency), or ~');
    printf("  %-23s # %s\n", 'sitename: ~', '~ = general/sitename');
    printf("  %-23s # %s\n", 'domain: ~', '~ = the host of the request');
    printf("  %-23s # %s\n", 'favicon: ~', '~ = Bolt\'s admin favicon');

    return 0;
}

// ------------------------------------------------------------------------------------------------
// Verification
// ------------------------------------------------------------------------------------------------

function out(string $level, string $message): void
{
    echo "$level $message\n";
}

/** @return array<mixed> */
function readYaml(string $file): array
{
    if (! is_file($file)) {
        return [];
    }
    try {
        $data = Symfony\Component\Yaml\Yaml::parseFile($file);
    } catch (Throwable $e) {
        out('FAIL', "$file: " . $e->getMessage());

        return [];
    }

    return is_array($data) ? $data : [];
}

function dig(array $data, string $path): mixed
{
    foreach (explode('.', $path) as $key) {
        if (! is_array($data) || ! array_key_exists($key, $data)) {
            return null;
        }
        $data = $data[$key];
    }

    return $data;
}

function stripTwigComments(string $source): string
{
    return (string) preg_replace('/\{#.*?#\}/s', '', $source);
}

function check(string $root, string $baseUrl, bool $rateLimitTest = false): int
{
    $root = rtrim((string) realpath($root), '/');
    if ($root === '' || ! is_file("$root/config/services.yaml")) {
        out('FAIL', 'Bolt project root not found (config/services.yaml)');

        return 1;
    }
    chdir($root);
    if (! is_file('vendor/autoload.php')) {
        out('FAIL', 'vendor/autoload.php not found — run composer install first');

        return 1;
    }
    require 'vendor/autoload.php';

    $config = array_replace_recursive(readYaml('config/bolt/config.yaml'), readYaml('config/bolt/config_local.yaml'));
    $theme = (string) ($config['theme'] ?? '');
    $themeDir = "public/theme/$theme";
    if ($theme === '' || ! is_file("$themeDir/theme.yaml")) {
        out('FAIL', "active theme not found ($themeDir/theme.yaml)");

        return 1;
    }
    $themeYaml = readYaml("$themeDir/theme.yaml");
    $examples = dirname(__DIR__) . '/examples';

    // 1. Files ------------------------------------------------------------------------------------
    out('SECTION', "Templates and assets in $themeDir");
    foreach (TEMPLATES as $template) {
        $file = "$themeDir/bolt-auth/$template";
        if (! is_file($file)) {
            out('FAIL', "missing bolt-auth/$template — run scaffold.sh");
        } elseif (hash_file('sha256', $file) !== hash_file('sha256', "$examples/bolt-auth/$template")) {
            out('WARN', "bolt-auth/$template differs from the skill's version — the templates are shared by every project; per-project values belong in theme.yaml (scaffold.sh --update replaces it)");
        } else {
            out('PASS', "bolt-auth/$template");
        }
    }
    $script = "$themeDir/js/bolt-auth.js";
    if (! is_file($script)) {
        out('FAIL', 'missing js/bolt-auth.js — run scaffold.sh');
    } else {
        out(hash_file('sha256', $script) === hash_file('sha256', "$examples/bolt-auth.js") ? 'PASS' : 'WARN', 'js/bolt-auth.js' . (hash_file('sha256', $script) === hash_file('sha256', "$examples/bolt-auth.js") ? '' : ' differs from the skill\'s version'));
    }
    $missingFonts = array_filter(FONTS, static fn (string $font): bool => ! is_file("$themeDir/css/fonts/instrument/$font"));
    out($missingFonts === [] ? 'PASS' : 'FAIL', $missingFonts === [] ? 'self-hosted Instrument Sans / Serif (latin + latin-ext) in css/fonts/instrument/' : 'missing fonts in css/fonts/instrument/: ' . implode(', ', $missingFonts));

    $external = [];
    $sources = [];
    foreach (glob("$themeDir/bolt-auth/*.twig") ?: [] as $file) {
        $sources[$file] = stripTwigComments((string) file_get_contents($file));
        if (preg_match_all('#https?://[^\s"\')]+#', $sources[$file], $m)) {
            foreach ($m[0] as $url) {
                $external[] = basename($file) . ": $url";
            }
        }
    }
    out($external === [] ? 'PASS' : 'FAIL', $external === [] ? 'no external hosts (fonts, icons and scripts are self-hosted)' : 'external URLs in the templates: ' . implode(', ', $external));

    // 2. Wiring -----------------------------------------------------------------------------------
    out('SECTION', 'Wiring in theme.yaml (Bolt\'s TemplateChooser reads these first)');
    foreach (WIRING as $path => $expected) {
        $value = dig($themeYaml, $path);
        if ($value === $expected) {
            out('PASS', "$path: $expected");
        } else {
            out('FAIL', "$path: " . ($value === null ? 'not set' : var_export($value, true)) . " — expected '$expected'");
        }
    }

    // 3. Per-project values -----------------------------------------------------------------------
    out('SECTION', 'Per-project values (theme.yaml → bolt_auth)');
    $auth = is_array($themeYaml['bolt_auth'] ?? null) ? $themeYaml['bolt_auth'] : null;
    if ($auth === null) {
        out('FAIL', 'bolt_auth: block missing in theme.yaml — see examples/theme.yaml');
    } else {
        checkValues($auth, $themeDir, $sources);
    }

    // 4. Theme integration ------------------------------------------------------------------------
    out('SECTION', 'Theme integration (Tailwind scan, translations)');
    checkIntegration($themeDir);

    // 5. Security ---------------------------------------------------------------------------------
    out('SECTION', 'Security (rate limits, login throttling, headers, password policy, templates)');
    checkSecurity($root, $themeDir, $examples, $sources);

    $services = (string) file_get_contents('config/services.yaml');
    if ($baseUrl === '') {
        return 0;
    }

    // 6. Live -------------------------------------------------------------------------------------
    $backend = preg_match('/^\s*bolt\.backend_url:\s*[\'"]?([^\s\'"#]+)/m', $services, $m) ? rtrim($m[1], '/') : '/bolt';
    checkLive($baseUrl, $backend, $rateLimitTest);

    return 0;
}

/**
 * @param array<mixed>          $auth
 * @param array<string, string> $sources
 */
function checkValues(array $auth, string $themeDir, array $sources): void
{
    $colors = [];
    foreach (COLOR_KEYS as $key) {
        $hex = normalizeHex((string) ($auth[$key] ?? ''));
        if ($hex === null) {
            out('FAIL', "bolt_auth.$key: " . var_export($auth[$key] ?? null, true) . ' — must be #rrggbb');
        } else {
            $colors[$key] = $hex;
        }
    }
    if (count($colors) === count(COLOR_KEYS)) {
        out('PASS', 'seven colours set: ' . implode(' ', $colors));
        foreach (contrastFindings($colors) as [$level, $message]) {
            out($level, $message);
        }
        // The colours live in theme.yaml only: a copy in a template would not follow a change.
        // A project colour that equals a shared value of the skill's own template (--danger, a
        // neutral, a fallback) is not a copy: only colours the skill's version lacks count.
        $hardCoded = [];
        $examples = dirname(__DIR__) . '/examples/bolt-auth';
        foreach ($sources as $file => $source) {
            $shared = strtolower(stripTwigComments((string) @file_get_contents($examples . '/' . basename($file))));
            foreach (array_unique(array_values($colors)) as $hex) {
                if (stripos($source, $hex) !== false && ! str_contains($shared, $hex)) {
                    $hardCoded[] = basename($file) . " ($hex)";
                }
            }
        }
        out($hardCoded === [] ? 'PASS' : 'FAIL', $hardCoded === [] ? 'no project colour written into the templates' : 'project colours written into the templates: ' . implode(', ', $hardCoded) . ' — they belong in theme.yaml only');
    }

    $logo = (string) ($auth['logo'] ?? '');
    if ($logo === '' || ! is_file("$themeDir/$logo")) {
        out('FAIL', "bolt_auth.logo: '$logo' not found in the theme folder");
    } elseif (! preg_match('/\.(svg|png|webp)$/i', $logo)) {
        out('WARN', "bolt_auth.logo: $logo — use SVG, or PNG / WebP with transparency (it sits on the white badge)");
    } else {
        out('PASS', "logo $logo");
    }
    $width = $auth['logo_width'] ?? null;
    $height = $auth['logo_height'] ?? null;
    if (! is_int($width) || ! is_int($height) || $width < 1 || $height < 1) {
        out('FAIL', 'bolt_auth.logo_width / logo_height must be whole pixels');
    } elseif ($height < 24 || $height > 56 || $width > 260) {
        out('WARN', "logo {$width}×{$height}px — the badge is designed for a height of 24–49 px and a width up to ~240 px");
    } else {
        out('PASS', "logo size {$width}×{$height}px");
    }
    $mark = $auth['mark'] ?? null;
    if ($mark === null || $mark === '' || $mark === 'none') {
        out('PASS', 'no watermark (mark: ~)');
    } elseif (! is_file("$themeDir/$mark")) {
        out('FAIL', "bolt_auth.mark: '$mark' not found in the theme folder");
    } elseif (! preg_match('/\.(svg|png|webp)$/i', (string) $mark)) {
        out('FAIL', "bolt_auth.mark: $mark — the watermark is a CSS mask and needs transparency (SVG, PNG or WebP)");
    } else {
        out('PASS', "watermark $mark");
    }
    $favicon = $auth['favicon'] ?? null;
    if ($favicon !== null && $favicon !== '' && ! is_file("$themeDir/$favicon")) {
        out('FAIL', "bolt_auth.favicon: '$favicon' not found in the theme folder");
    }

}

function checkIntegration(string $themeDir): void
{
    $tailwind = "$themeDir/css/tailwind/index.css";
    if (is_file($tailwind)) {
        $css = (string) file_get_contents($tailwind);
        out(preg_match('#@source\s+not\s+["\']\.\./\.\./bolt-auth["\']#', $css) ? 'PASS' : 'FAIL', 'css/tailwind/index.css excludes bolt-auth/ from the class scan (@source not "../../bolt-auth")');
    } else {
        out('PASS', 'no css/tailwind/index.css — nothing to exclude');
    }

    $services = (string) file_get_contents('config/services.yaml');
    $default = preg_match('/^\s*locale:\s*[\'"]?([A-Za-z_]+)/m', $services, $m) ? $m[1] : 'en';
    foreach (glob('translations/messages.*.xlf') ?: [] as $catalog) {
        $locale = (string) preg_replace('/^messages\.(.+)\.xlf$/', '$1', basename($catalog));
        $xml = (string) file_get_contents($catalog);
        $missing = array_filter(['bolt_auth.show_password', 'bolt_auth.hide_password', 'bolt_auth.too_many_requests', 'bolt_auth.reset_unavailable'], static fn (string $key): bool => ! str_contains($xml, ">$key<") && ! str_contains($xml, "\"$key\""));
        if ($missing === []) {
            out('PASS', "$catalog has the bolt_auth units (reveal button, rate-limit message, reset without mailer)");
        } else {
            out($locale === $default ? 'FAIL' : 'WARN', "$catalog misses " . implode(', ', $missing) . ' — merge examples/translations.' . ($locale === 'cs' ? 'cs' : 'en') . '.xlf');
        }
    }

}

/**
 * @param array<string, string> $sources template sources without Twig comments
 */
function checkSecurity(string $root, string $themeDir, string $examples, array $sources): void
{
    // Project code of the security layer: identical in every project.
    foreach (['src/BoltAuthSecuritySubscriber.php' => 'src/BoltAuthSecuritySubscriber.php', 'src/BoltAuthPasswordPolicyExtension.php' => 'src/BoltAuthPasswordPolicyExtension.php', 'config/packages/bolt_auth.yaml' => 'config/bolt_auth.yaml'] as $file => $example) {
        if (! is_file($file)) {
            out('FAIL', "missing $file — run scaffold.sh (rate limits, strict headers, password policy)");
        } elseif (normalized($file) !== normalized("$examples/$example")) {
            out('WARN', "$file differs from the skill's version — keep it shared; scaffold.sh --update replaces it");
        } else {
            out('PASS', $file);
        }
    }
    if (! is_dir('vendor/symfony/rate-limiter')) {
        out('FAIL', 'symfony/rate-limiter is not installed — composer require symfony/rate-limiter');
    }

    $packages = readYaml('config/packages/bolt_auth.yaml');
    foreach (['bolt_auth_reset_request' => 5, 'bolt_auth_reset_password' => 10] as $name => $max) {
        $limiter = $packages['framework']['rate_limiter'][$name] ?? null;
        $limit = is_array($limiter) ? (int) ($limiter['limit'] ?? 0) : 0;
        if ($limit < 1) {
            out('FAIL', "rate limiter $name missing in config/packages/bolt_auth.yaml");
        } elseif ($limit > $max) {
            out('FAIL', "rate limiter $name allows $limit requests — at most $max per 15 minutes");
        } else {
            out('PASS', "rate limiter $name: $limit per " . ($limiter['interval'] ?? '?') . ' and IP address');
        }
    }
    $minimum = (int) ($packages['parameters']['bolt_auth.password_min_length'] ?? 0);
    $userPolicy = (string) @file_get_contents('config/validator/user.yaml');
    $userMinimum = preg_match('/Length:\s*\n\s*min:\s*(\d+)/', $userPolicy, $m) ? (int) $m[1] : 0;
    if ($minimum < 12) {
        out('FAIL', "bolt_auth.password_min_length is $minimum — at least 12, as for users edited in the admin");
    } elseif ($userMinimum !== 0 && $userMinimum !== $minimum) {
        out('WARN', "bolt_auth.password_min_length ($minimum) differs from config/validator/user.yaml ($userMinimum)");
    } else {
        out('PASS', "new passwords from a reset link: at least $minimum characters, medium strength, not in known breaches");
    }

    // Login throttling (Symfony's firewall; the custom screen only shows its message).
    $security = readYaml('config/packages/security.yaml');
    $main = $security['security']['firewalls']['main'] ?? [];
    $throttling = is_array($main) && array_key_exists('login_throttling', $main) ? ($main['login_throttling'] ?? []) : null;
    if ($throttling === null) {
        out('FAIL', 'security.firewalls.main has no login_throttling — bolt-security-hardening Step 3a');
    } else {
        $attempts = (int) ($throttling['max_attempts'] ?? 5);
        $interval = (string) ($throttling['interval'] ?? '1 minute');
        out($attempts <= 5 && $interval !== '1 minute' ? 'PASS' : 'WARN', "login throttling: $attempts attempts per $interval per username and IP" . ($interval === '1 minute' ? ' — use 15 minutes (bolt-security-hardening Step 3a)' : ''));
    }

    // Reset flow: no account enumeration, short-lived tokens, no Host-header poisoning of the link.
    $config = array_replace_recursive(readYaml('config/bolt/config.yaml'), readYaml('config/bolt/config_local.yaml'));
    $notice = $config['reset_password_settings']['show_already_requested_password_notice'] ?? false;
    out($notice === true ? 'FAIL' : 'PASS', 'reset_password_settings.show_already_requested_password_notice: ' . ($notice === true ? 'true reveals which addresses have an account — set false' : 'false (no account enumeration)'));
    $reset = readYaml('config/packages/reset_password.yaml')['symfonycasts_reset_password'] ?? [];
    $lifetime = (int) ($reset['lifetime'] ?? 3600);
    out($lifetime <= 3600 ? 'PASS' : 'WARN', "reset links expire after {$lifetime} s" . ($lifetime > 3600 ? ' — keep it at 3600 or less' : ''));
    $framework = readYaml('config/packages/framework.yaml')['framework'] ?? [];
    $env = (string) @file_get_contents('.env');
    $hosts = preg_match('/^SYMFONY_TRUSTED_HOSTS=(.*)$/m', $env, $m) ? trim($m[1], " '\"") : '';
    if (! array_key_exists('trusted_hosts', is_array($framework) ? $framework : [])) {
        out('FAIL', 'framework.trusted_hosts is not configured: the reset e-mail builds its link from the Host header (password-reset poisoning) — bolt-security-hardening Step 2');
    } elseif ($hosts === '') {
        out('WARN', 'SYMFONY_TRUSTED_HOSTS is empty in .env — set it for production, or the reset link can point at a foreign host');
    } else {
        out('PASS', 'trusted hosts set (the reset link cannot be pointed at a foreign host)');
    }

    // The reset e-mail needs a mailer: without one the screens hide the reset (SKILL.md Step 4).
    $dsn = preg_match_all('/^\s*MAILER_DSN=(.*)$/m', (string) @file_get_contents('.env'), $m) ? trim(trim((string) end($m[1])), "'\"") : null;
    $subscriber = 'App\\BoltAuthSecuritySubscriber';
    if (class_exists($subscriber) && method_exists($subscriber, 'canSendMail')) {
        $scheme = $dsn === null || $dsn === '' ? 'unset' : (parse_url($dsn, PHP_URL_SCHEME) ?: 'composite') . '://' . (parse_url($dsn, PHP_URL_HOST) ?: '…');
        out(
            $subscriber::canSendMail($dsn) ? 'PASS' : 'WARN',
            $subscriber::canSendMail($dsn)
                ? "MAILER_DSN in .env can send ($scheme): the login offers the password reset"
                : "MAILER_DSN in .env cannot send ($scheme): the login hides the password reset unless the server's .env.local sets a real mailer (smtp://user:pass@host, or sendmail://default)"
        );
    }

    // Trusted Types: an extension in the login form must have its policy allowed.
    $trustedTypes = $packages['parameters']['bolt_auth.trusted_types'] ?? [];
    $lock = (string) @file_get_contents('composer.lock');
    $missing = array_diff(['svelte-trusted-html', 'default'], is_array($trustedTypes) ? $trustedTypes : []);
    if (str_contains($lock, '"name": "tomvondracek/bolt-altcha"') && $missing !== []) {
        out('FAIL', "tomvondracek/bolt-altcha is installed: add '" . implode("', '", $missing) . "' to bolt_auth.trusted_types, or its login widget cannot render in production and nobody can log in");
    }
    // Form themes: `only` drops the extension's global form theme, so the templates add it back for an ALTCHA field.
    foreach (['login.twig', 'reset-request.twig', 'reset.twig'] as $template) {
        $source = $sources["$themeDir/bolt-auth/$template"] ?? '';
        if ($source !== '' && ! str_contains($source, "'@bolt-altcha/form/altcha.html.twig'")) {
            out('FAIL', "$template sets its form themes with `only` but not the ALTCHA one: a protected form renders the field as a text input — scaffold.sh --update");
        }
    }

    // Templates: nothing that could carry injected markup or script.
    $problems = [];
    foreach ($sources as $file => $source) {
        $name = basename($file);
        if (preg_match('/\|\s*raw\b/', $source)) {
            $problems[] = "$name prints with |raw";
        }
        if (preg_match('/<script(?![^>]*\bsrc=)/i', $source)) {
            $problems[] = "$name has an inline <script>";
        }
        if (preg_match('/\son[a-z]+\s*=/i', $source)) {
            $problems[] = "$name has an inline event handler";
        }
        if (preg_match('/\sstyle\s*=/i', $source)) {
            $problems[] = "$name has a style attribute (the policy allows none)";
        }
        if (preg_match('/<style(?![^>]*nonce)/i', $source)) {
            $problems[] = "$name has a <style> without the nonce";
        }
        if (preg_match('/\b(?:target\s*=|javascript:)/i', $source)) {
            $problems[] = "$name opens a new window or uses javascript:";
        }
    }
    $macros = $sources["$themeDir/bolt-auth/_macros.twig"] ?? '';
    if ($macros !== '' && ! str_contains($macros, "type: 'password', value: ''")) {
        $problems[] = "_macros.twig does not force type=\"password\" without a value on password fields";
    }
    foreach (['login.twig' => ['form_end(loginForm', "widgets('login_top')", "widgets('login_middle')", "widgets('login_bottom')", 'error.messageKey'], 'reset-request.twig' => ['form_end(requestForm'], 'reset.twig' => ['form_end(resetForm']] as $template => $needles) {
        $source = $sources["$themeDir/bolt-auth/$template"] ?? '';
        foreach ($needles as $needle) {
            if ($source !== '' && ! str_contains($source, $needle)) {
                $problems[] = "$template lost $needle (CSRF token, extension slots or Bolt's error)";
            }
        }
    }
    out($problems === [] ? 'PASS' : 'FAIL', $problems === [] ? 'templates: no |raw, inline script, event handler or style attribute; CSRF, widget slots and errors kept' : 'templates: ' . implode('; ', $problems));
}

/** A shared file's content, without the one line a project sets itself (its Trusted Types policies). */
function normalized(string $file): string
{
    return (string) preg_replace('/^(\s*bolt_auth\.trusted_types:).*$/m', '$1', (string) file_get_contents($file));
}

function checkLive(string $baseUrl, string $backend, bool $rateLimitTest): void
{
    out('SECTION', "Live screens on $baseUrl (backend $backend)");
    $screens = [
        "$backend/login" => ['login[username]', 'login[password]', 'login[_token]'],
        "$backend/reset-password" => ['reset_password_request_form[email]', 'reset_password_request_form[_token]'],
    ];
    $assets = [];
    // Without a mailer the reset screens redirect to the login, and the login shows a hint instead.
    [$resetStatus, , $resetHeaders] = fetch($baseUrl . "$backend/reset-password");
    $resetOff = in_array($resetStatus, [302, 303], true) && str_ends_with((string) parse_url($resetHeaders['location'][0] ?? '', PHP_URL_PATH), "$backend/login");
    if ($resetOff) {
        unset($screens["$backend/reset-password"]);
        $rateLimitTest = false;
        [, $login] = fetch($baseUrl . "$backend/login");
        $hidden = ! str_contains($login, 'reset-password') && str_contains($login, '<p class="ba-help">');
        out($hidden ? 'WARN' : 'FAIL', $hidden
            ? "password reset is off on $baseUrl: MAILER_DSN cannot send, so $backend/reset-password redirects to the login, which asks to contact the administrator — set a real mailer to offer it"
            : "$backend/reset-password redirects to the login, but the login still links to it or lacks the hint");
    }
    foreach ($screens as $path => $fields) {
        [$status, $html, $headers] = fetch($baseUrl . $path);
        if ($status !== 200) {
            out('FAIL', "$path answers $status");
            continue;
        }
        $problems = [];
        foreach (['class="ba-screen"', 'class="ba-panel"', 'class="ba-form"', 'name="robots" content="noindex'] as $marker) {
            if (! str_contains($html, $marker)) {
                $problems[] = "no $marker";
            }
        }
        foreach ($fields as $field) {
            if (! str_contains($html, "name=\"$field\"")) {
                $problems[] = "no field $field";
            }
        }
        preg_match_all('/<input[^>]*name="[^"]*(?:\[password\]|\[plainPassword\]\[[a-z]+\])"[^>]*>/', $html, $inputs);
        if ($path === "$backend/login" && count($inputs[0]) !== 1) {
            $problems[] = 'no login[password] field found';
        }
        foreach ($inputs[0] as $input) {
            if (! str_contains($input, 'type="password"') || preg_match('/\svalue="[^"]/', $input) === 1) {
                $problems[] = 'a password field is not type="password" or carries a value';
            }
        }
        if (preg_match('#<(?:link|script|img)[^>]+(?:href|src)="(?:https?:)?//#i', $html)) {
            $problems[] = 'loads a file from another host';
        }
        if (str_contains($html, '/assets/bolt.css') || str_contains($html, 'encore')) {
            $problems[] = "still loads Bolt's admin stylesheet — the theme template is not used";
        }
        out($problems === [] ? 'PASS' : 'FAIL', "$path renders the bolt-auth screen" . ($problems === [] ? '' : ': ' . implode('; ', $problems)));
        checkHeaders($path, $html, $headers, str_starts_with($baseUrl, 'https://'));
        preg_match_all('#(?:src|href)="(/[^"]+)"|url\("(/[^"]+)"\)#', $html, $m);
        foreach (array_merge($m[1], $m[2]) as $url) {
            if ($url !== '' && str_contains($url, '/theme/')) {
                $assets[html_entity_decode($url)] = true;
            }
        }
    }
    foreach (array_keys($assets) as $url) {
        [$status] = fetch($baseUrl . $url);
        out($status === 200 ? 'PASS' : 'FAIL', "$url answers $status");
    }

    if ($rateLimitTest) {
        // Without a valid CSRF token Bolt sends no e-mail; the limiter counts every POST anyway.
        $limited = 0;
        for ($i = 1; $i <= 7 && $limited === 0; $i++) {
            [$status, , $headers] = fetch($baseUrl . "$backend/reset-password", 'POST', 'reset_password_request_form%5Bemail%5D=nobody%40example.invalid&reset_password_request_form%5B_token%5D=x');
            if ($status === 303 && isset($headers['retry-after'])) {
                $limited = $i;
            }
        }
        out($limited !== 0 ? 'PASS' : 'FAIL', $limited !== 0 ? "reset request limited after " . ($limited - 1) . " requests (303 to the request screen, Retry-After {$headers['retry-after'][0]} s)" : 'reset request: 7 POSTs from one IP were not limited');
    }
}

/**
 * @param array<string, list<string>> $headers lower-case names
 */
function checkHeaders(string $path, string $html, array $headers, bool $https): void
{
    $problems = [];
    $policies = $headers['content-security-policy'] ?? [];
    $strict = array_values(array_filter($policies, static fn (string $policy): bool => str_contains($policy, "default-src 'none'")));
    if ($strict === []) {
        $problems[] = "no strict Content-Security-Policy (default-src 'none') — is src/BoltAuthSecuritySubscriber.php loaded?";
    } else {
        $policy = $strict[0];
        foreach (["script-src 'self'", "frame-ancestors 'none'", "base-uri 'none'", "object-src 'none'", "form-action 'self'"] as $directive) {
            if (! str_contains($policy, $directive)) {
                $problems[] = "CSP lacks $directive";
            }
        }
        if (str_contains($policy, 'unsafe-inline') || str_contains($policy, 'unsafe-eval')) {
            $problems[] = "CSP allows 'unsafe-inline' or 'unsafe-eval'";
        }
        if (! preg_match('/<style nonce="([^"]+)"/', $html, $m) || ! str_contains($policy, "'nonce-{$m[1]}'")) {
            $problems[] = 'the inline <style> nonce does not match the policy';
        }
        // Trusted Types are sent without kernel.debug only (the dev toolbar writes HTML itself);
        // a response with X-Debug-Token comes from a debug kernel.
        if (! str_contains($policy, "require-trusted-types-for 'script'") && ! isset($headers['x-debug-token'])) {
            $problems[] = 'no Trusted Types (require-trusted-types-for) although the site runs without debug';
        }
    }
    $cache = strtolower(implode(',', $headers['cache-control'] ?? []));
    if (! str_contains($cache, 'no-store')) {
        $problems[] = "Cache-Control without no-store ($cache)";
    }
    if (($headers['referrer-policy'][0] ?? '') !== 'no-referrer') {
        $problems[] = 'Referrer-Policy is not no-referrer';
    }
    if (strtoupper($headers['x-frame-options'][0] ?? '') !== 'DENY') {
        $problems[] = 'X-Frame-Options is not DENY';
    }
    if (($headers['cross-origin-opener-policy'][0] ?? '') !== 'same-origin') {
        $problems[] = 'no Cross-Origin-Opener-Policy: same-origin';
    }
    if (($headers['x-content-type-options'][0] ?? '') !== 'nosniff') {
        $problems[] = 'no X-Content-Type-Options: nosniff';
    }
    foreach ($headers['set-cookie'] ?? [] as $cookie) {
        $lower = strtolower($cookie);
        $name = strtok($cookie, '=');
        if (! str_contains($lower, 'httponly')) {
            $problems[] = "cookie $name without HttpOnly";
        }
        if (! str_contains($lower, 'samesite=lax') && ! str_contains($lower, 'samesite=strict')) {
            $problems[] = "cookie $name without SameSite";
        }
        if ($https && ! str_contains($lower, 'secure')) {
            $problems[] = "cookie $name without Secure on HTTPS";
        }
    }
    out($problems === [] ? 'PASS' : 'FAIL', "$path headers: strict CSP with nonce, no-store, no-referrer, DENY, COOP, nosniff" . ($headers['set-cookie'] ?? [] ? ', session cookie HttpOnly + SameSite' . ($https ? ' + Secure' : '') : '') . ($problems === [] ? '' : ' — ' . implode('; ', $problems)));
}

/** @return array{int, string, array<string, list<string>>} status, body, headers by lower-case name */
function fetch(string $url, string $method = 'GET', string $body = ''): array
{
    $header = "User-Agent: bolt-auth-screens verify\r\n" . ($method === 'POST' ? "Content-Type: application/x-www-form-urlencoded\r\n" : '');
    $context = stream_context_create(['http' => ['method' => $method, 'content' => $body, 'ignore_errors' => true, 'follow_location' => 0, 'timeout' => 20, 'header' => $header]]);
    $content = @file_get_contents($url, false, $context);
    $status = 0;
    $headers = [];
    $lines = function_exists('http_get_last_response_headers') ? (http_get_last_response_headers() ?? []) : ($http_response_header ?? []);
    foreach ($lines as $line) {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $line, $m)) {
            $status = (int) $m[1];
            $headers = [];
        } elseif (str_contains($line, ':')) {
            [$name, $value] = explode(':', $line, 2);
            $headers[strtolower(trim($name))][] = trim($value);
        }
    }

    return [$status, $content === false ? '' : $content, $headers];
}
