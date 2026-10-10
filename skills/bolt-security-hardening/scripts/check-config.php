<?php

declare(strict_types=1);

/*
 * File checks of bolt-security-hardening (sections 1–6 of verify.sh). Reads the project's
 * configuration — never writes — and prints one line per result:
 *
 *   SECTION <title>
 *   PASS <message>
 *   WARN <message>
 *   FAIL <message>
 *
 * Usage: php check-config.php /path/to/bolt-project
 */

use Symfony\Component\Dotenv\Dotenv;
use Symfony\Component\Yaml\Yaml;

$project = $argv[1] ?? getcwd();
chdir($project);

if (! is_file('vendor/autoload.php')) {
    echo "FAIL vendor/autoload.php not found — run composer install first\n";
    exit(0);
}
require 'vendor/autoload.php';

function out(string $kind, string $message): void
{
    echo $kind, ' ', $message, PHP_EOL;
}

function readYaml(string $file): array
{
    if (! is_file($file)) {
        return [];
    }
    try {
        $data = Yaml::parseFile($file, Yaml::PARSE_CUSTOM_TAGS);
    } catch (Throwable $e) {
        out('FAIL', "{$file}: YAML error — " . $e->getMessage());

        return [];
    }

    return is_array($data) ? $data : [];
}

function merge(array $base, array $over): array
{
    foreach ($over as $key => $value) {
        if (is_array($value) && isset($base[$key]) && is_array($base[$key]) && ! array_is_list($value)) {
            $base[$key] = merge($base[$key], $value);
        } else {
            $base[$key] = $value;
        }
    }

    return $base;
}

function gitTracked(string $file): ?bool
{
    exec('git rev-parse --is-inside-work-tree 2>/dev/null', $output, $status);
    if ($status !== 0) {
        return null;
    }
    exec('git ls-files --error-unmatch ' . escapeshellarg($file) . ' 2>/dev/null', $output, $status);

    return $status === 0;
}

/** Merges config/packages/*.yaml the way the kernel loads them for one environment. */
function packageConfig(string $env, array &$trustedHosts): array
{
    $files = glob('config/packages/*.yaml') ?: [];
    sort($files);
    $envFiles = glob("config/packages/{$env}/*.yaml") ?: [];
    sort($envFiles);

    $merged = [];
    foreach (array_merge($files, $envFiles) as $file) {
        $data = readYaml($file);
        $parts = [];
        foreach ($data as $key => $value) {
            if (! str_starts_with((string) $key, 'when@')) {
                $parts[] = [$key => $value];
            }
        }
        if (isset($data["when@{$env}"]) && is_array($data["when@{$env}"])) {
            $parts[] = $data["when@{$env}"];
        }
        foreach ($parts as $part) {
            if (isset($part['framework']) && is_array($part['framework']) && array_key_exists('trusted_hosts', $part['framework'])) {
                $trustedHosts[] = [$file, $part['framework']['trusted_hosts']];
            }
            $merged = merge($merged, $part);
        }
    }

    return $merged;
}

// ------------------------------------------------------------------ 1. environment files
out('SECTION', 'Environment files and secrets (.env)');

$env = [];
if (is_file('.env')) {
    try {
        $env = (new Dotenv())->parse((string) file_get_contents('.env'), '.env');
    } catch (Throwable $e) {
        out('FAIL', '.env cannot be parsed — ' . $e->getMessage());
    }
} else {
    out('WARN', '.env not found — the committed defaults belong there (examples/env).');
}

$appEnv = $env['APP_ENV'] ?? '';
if (in_array($appEnv, ['dev', 'test'], true)) {
    out('FAIL', ".env sets APP_ENV={$appEnv}. It is uploaded with the code: if the server's .env.local is missing, the site runs in {$appEnv} mode (profiler, stack traces). Set APP_ENV=prod in .env and APP_ENV=dev in your local .env.local.");
} elseif ($appEnv !== '') {
    out('PASS', ".env: APP_ENV={$appEnv}");
}

$appDebug = strtolower((string) ($env['APP_DEBUG'] ?? ''));
if (in_array($appDebug, ['1', 'true', 'on', 'yes'], true)) {
    out('FAIL', '.env sets APP_DEBUG=1 — set APP_DEBUG=0 in .env, enable debug only in your local .env.local.');
}

$secret = (string) ($env['APP_SECRET'] ?? '');
$placeholder = $secret === '' || preg_match('/^!?change.?me!?$/i', $secret) === 1;
$envTracked = gitTracked('.env');
if (! $placeholder && $envTracked === true) {
    out('FAIL', '.env (tracked by git) contains a real APP_SECRET. Generate a new secret into the server\'s .env.local, empty the line in .env — the old value stays in git history, so it must not be used any more.');
} elseif (! $placeholder && $envTracked === null) {
    out('WARN', '.env contains an APP_SECRET; keep secrets in .env.local only (not a git repository, so tracking was not checked).');
} else {
    out('PASS', '.env contains no APP_SECRET (it lives in .env.local)');
}

// Credentials inside connection strings (MAILER_DSN, DATABASE_URL, …): scheme://user:password@host.
foreach ($env as $name => $value) {
    if (! is_string($value) || preg_match('#^[a-z][a-z0-9+.-]*://[^/\s]*:[^/\s]*@#i', $value) !== 1) {
        continue;
    }
    if (preg_match('#://[^:/]*:"?(|db_password|password|pass|secret|changeme|!changeme!)"?@#i', $value) === 1) {
        continue;
    }
    $tracked = $envTracked === true ? ' (tracked by git)' : '';
    out('FAIL', ".env{$tracked} sets {$name} with a password in it. Move the line to the server's .env.local, keep a password-less default in .env (e.g. MAILER_DSN=smtp://localhost), and change the password at the provider — it stays in git history.");
}

if (is_file('.env.local') && gitTracked('.env.local') === true) {
    out('FAIL', '.env.local is tracked by git — remove it from the repository (git rm --cached .env.local) and rotate its secrets.');
}

$hosts = (string) ($env['SYMFONY_TRUSTED_HOSTS'] ?? '');
if ($hosts !== '') {
    out('PASS', ".env: SYMFONY_TRUSTED_HOSTS={$hosts}");
} else {
    out('WARN', 'SYMFONY_TRUSTED_HOSTS is not set in .env — without it every Host header is accepted (password-reset poisoning). Set it in .env (or on the server); the live check confirms.');
}

if (array_key_exists('TRUSTED_PROXIES', $env)) {
    out('WARN', '.env sets TRUSTED_PROXIES, which Symfony 6.4 never reads — delete it; use SYMFONY_TRUSTED_PROXIES (Step 2).');
}
if (is_file('.env.local.php')) {
    out('WARN', '.env.local.php exists and overrides every .env file — do not upload one built on a developer machine.');
}

// ------------------------------------------------------------------ 2. framework
out('SECTION', 'Symfony framework (config/packages, prod)');

$trustedHosts = [];
$packages = packageConfig('prod', $trustedHosts);
$framework = $packages['framework'] ?? [];

if ($trustedHosts === []) {
    out('FAIL', 'framework.trusted_hosts is not configured — add trusted_hosts: [\'%env(default::SYMFONY_TRUSTED_HOSTS)%\'] to config/packages/framework.yaml.');
} else {
    foreach ($trustedHosts as [$file, $value]) {
        if ($value === null || $value === []) {
            out('FAIL', "{$file}: trusted_hosts: ~ disables host validation — use trusted_hosts: ['%env(default::SYMFONY_TRUSTED_HOSTS)%'].");
        } elseif (! str_contains($file, 'framework.yaml')) {
            out('WARN', "{$file} sets trusted_hosts too — the lists are merged, so an empty SYMFONY_TRUSTED_HOSTS entry elsewhere still trusts every host. Keep it in framework.yaml only.");
        } else {
            out('PASS', "{$file}: trusted_hosts configured (" . json_encode($value, JSON_UNESCAPED_SLASHES) . ')');
        }
    }
}

$proxies = (string) ($framework['trusted_proxies'] ?? '');
if ($proxies === '') {
    out('WARN', 'framework.trusted_proxies is not set — copy examples/security_hardening.yaml (SYMFONY_TRUSTED_PROXIES for sites behind a TLS proxy).');
} elseif (str_contains($proxies, 'REMOTE_ADDR')) {
    out('WARN', 'trusted_proxies contains REMOTE_ADDR — only correct when a proxy really is in front; otherwise any visitor can fake X-Forwarded-For.');
} else {
    out('PASS', "trusted_proxies: {$proxies}");
}
if (in_array('x-forwarded-host', array_map('strtolower', (array) ($framework['trusted_headers'] ?? [])), true)) {
    out('WARN', 'trusted_headers includes x-forwarded-host — a proxied request could change the host of absolute URLs.');
}

$esi = $framework['esi']['enabled'] ?? ($framework['esi'] ?? false);
$fragments = $framework['fragments']['enabled'] ?? ($framework['fragments'] ?? false);
if ($esi === true || $fragments === true) {
    out('WARN', 'framework esi / fragments are enabled — Bolt uses neither; disable them so /_fragment does not exist (examples/security_hardening.yaml).');
} else {
    out('PASS', 'esi and fragments disabled');
}

$session = $framework['session'] ?? [];
if (($session['cookie_secure'] ?? null) !== true) {
    out('WARN', 'prod session cookie_secure is not true (' . json_encode($session['cookie_secure'] ?? null) . ') — set it in when@prod (examples/security_hardening.yaml).');
} else {
    out('PASS', 'session cookie_secure: true');
}
if (($session['cookie_httponly'] ?? true) !== true) {
    out('FAIL', 'session cookie_httponly is false — scripts could read the session cookie.');
}
$lifetime = (int) ($session['cookie_lifetime'] ?? 0);
if ($lifetime > 86400) {
    out('WARN', "session cookie_lifetime is {$lifetime} s (" . round($lifetime / 86400, 1) . ' days) — 28800 (8 h) is enough with remember-me.');
}
if (empty($session['save_path'])) {
    out('WARN', 'session save_path not set — sessions live in the host\'s shared session folder; use var/sessions/%kernel.environment% (examples/security_hardening.yaml).');
}

// ------------------------------------------------------------------ 3. login and accounts
out('SECTION', 'Login throttling, remember-me, password policy');

$main = $packages['security']['firewalls']['main'] ?? null;
if (! is_array($main)) {
    out('WARN', 'security.firewalls.main not found — cannot check login throttling.');
} elseif (! array_key_exists('login_throttling', $main)) {
    out('FAIL', 'No login_throttling on the main firewall — unlimited password guessing on /bolt/login. Add max_attempts: 5, interval: \'15 minutes\'.');
} elseif (! is_array($main['login_throttling'])) {
    out('WARN', 'login_throttling: ~ allows 5 attempts per minute — set interval: \'15 minutes\'.');
} else {
    $throttle = $main['login_throttling'];
    out('PASS', sprintf('login_throttling: %s attempts per %s', $throttle['max_attempts'] ?? 5, $throttle['interval'] ?? '1 minute'));
}

$services = readYaml('config/services.yaml');
$remember = (int) ($services['parameters']['bolt.remember_lifetime'] ?? 0);
if ($remember > 604800) {
    out('WARN', "bolt.remember_lifetime is {$remember} s (" . round($remember / 86400) . ' days) — 604800 (7 days) in config/services.yaml.');
} elseif ($remember > 0) {
    out('PASS', "remember-me lifetime {$remember} s");
}

$minLength = 0;
foreach (glob('config/validator/*.yaml') ?: [] as $file) {
    foreach ((readYaml($file)['Bolt\Entity\User']['properties']['plainPassword'] ?? []) as $constraint) {
        if (is_array($constraint) && isset($constraint['Length']['min'])) {
            $minLength = max($minLength, (int) $constraint['Length']['min']);
        }
    }
}
$mappingPaths = (array) ($framework['validation']['mapping']['paths'] ?? []);
if ($minLength === 0) {
    out('WARN', 'No password policy for Bolt users (Bolt accepts 6 characters) — copy examples/validator/user.yaml to config/validator/user.yaml.');
} elseif ($mappingPaths === []) {
    out('WARN', 'config/validator/ has a password policy, but framework.validation.mapping.paths does not load it.');
} elseif ($minLength < 12) {
    out('WARN', "password minimum length is {$minLength} — use at least 12.");
} else {
    out('PASS', "password policy: at least {$minLength} characters");
}

// ------------------------------------------------------------------ 4. bolt config.yaml
out('SECTION', 'Bolt configuration (config/bolt/config.yaml)');

$bolt = readYaml('config/bolt/config.yaml');

$dangerous = ['html', 'htm', 'xhtml', 'shtml', 'js', 'mjs', 'css', 'scss', 'sass', 'less', 'twig', 'yaml', 'yml', 'php', 'phtml', 'phar', 'svg', 'svgz', 'xml', 'json', 'sh', 'exe', 'htaccess'];
// Bolt's built-in default list (used when the key is missing) contains twig, html, js, css, scss and svg.
$fileTypes = array_map('strtolower', (array) ($bolt['accept_file_types'] ?? ['twig', 'html', 'js', 'css', 'scss', 'svg']));
$bad = array_values(array_intersect($fileTypes, $dangerous));
if ($bad !== []) {
    out('FAIL', 'accept_file_types allows ' . implode(', ', $bad) . ' — uploads are served from the site\'s origin (stored XSS) and the admin file editor can save these. Use the list from examples/config_snippet.yaml.');
} else {
    out('PASS', 'accept_file_types has no script or source types');
}
$mediaTypes = array_map('strtolower', (array) ($bolt['accept_media_types'] ?? ['svg']));
if (array_intersect($mediaTypes, ['svg', 'svgz', 'html', 'htm', 'js']) !== []) {
    out('WARN', 'accept_media_types allows svg — the Redactor / Article upload buttons do not clean SVGs. Remove it.');
}

if (($bolt['curl_options']['verify_peer'] ?? true) === false) {
    out('FAIL', 'curl_options.verify_peer: false — Bolt fetches embeds without checking TLS certificates. Set true.');
}
if (($bolt['headers']['powered_by'] ?? true) !== false) {
    out('WARN', 'headers.powered_by is not false — Bolt sends "X-Powered-By: Bolt".');
}
if (($bolt['omit_meta_generator_tag'] ?? false) !== true) {
    out('WARN', 'omit_meta_generator_tag is not true — every page names Bolt in <meta name="generator">.');
}
$canonical = (string) ($bolt['canonical'] ?? '');
if ($canonical === '') {
    out('WARN', 'config/bolt/config.yaml has no canonical — canonical links name whichever host was requested (www and the bare domain both). Add canonical: \'%env(default::BOLT_CANONICAL)%\' and set BOLT_CANONICAL.');
}
$querySearch = $bolt['query_search'] ?? true;
$querySearchOn = is_array($querySearch) ? ($querySearch['enable'] ?? true) : (bool) $querySearch;
if ($querySearchOn) {
    out('WARN', 'query_search is enabled — any listing can be filtered by any field (?field--like=…). Disable it unless a listing page filters through the query string.');
} else {
    out('PASS', 'query_search disabled');
}
$tags = array_map('strtolower', (array) ($bolt['htmlcleaner']['allowed_tags'] ?? []));
$badTags = array_values(array_intersect($tags, ['script', 'style', 'object', 'embed', 'form', 'input', 'button', 'base', 'link', 'meta']));
if ($badTags !== []) {
    out('FAIL', 'htmlcleaner.allowed_tags allows ' . implode(', ', $badTags) . ' — remove them.');
}
if (in_array('iframe', $tags, true)) {
    out('WARN', 'htmlcleaner.allowed_tags allows iframe (its src is not filtered) — remove it; embeds use _consent-embed.twig.');
}
if (($bolt['reset_password_settings']['show_already_requested_password_notice'] ?? false) === true) {
    out('WARN', 'reset_password_settings.show_already_requested_password_notice: true reveals which e-mail addresses have an account — set false.');
}

// ------------------------------------------------------------------ 5. permissions
out('SECTION', 'Permissions (config/bolt/permissions.yaml)');

$permissions = readYaml('config/bolt/permissions.yaml');
$global = $permissions['global'] ?? [];
$editor = [];
foreach (['managefiles:config', 'managefiles:themes', 'list_files:config', 'list_files:themes'] as $permission) {
    if (! empty($global[$permission])) {
        $editor[] = $permission . ' [' . implode(', ', (array) $global[$permission]) . ']';
    }
}
if ($editor !== []) {
    out('WARN', 'The admin file editor can change configuration / templates (' . implode('; ', $editor) . ') — a stolen admin password becomes code execution. Set them to [].');
} else {
    out('PASS', 'file editor for config and themes disabled');
}
if (in_array('ROLE_DEVELOPER', (array) ($permissions['assignable_roles'] ?? []), true)) {
    out('WARN', 'assignable_roles contains ROLE_DEVELOPER (can impersonate any user) — remove it from the role picker.');
}

// ------------------------------------------------------------------ 6. security headers
out('SECTION', 'Security headers (nelmio_security, public/.htaccess)');

$bundles = is_file('config/bundles.php') ? (string) file_get_contents('config/bundles.php') : '';
$nelmio = $packages['nelmio_security'] ?? null;
if (! str_contains($bundles, 'NelmioSecurityBundle') || ! is_array($nelmio)) {
    out('FAIL', 'NelmioSecurityBundle is not enabled — pages have no clickjacking protection. composer require nelmio/security-bundle and copy examples/nelmio_security.yaml.');
} else {
    if (empty($nelmio['clickjacking']['paths'])) {
        out('FAIL', 'nelmio_security.clickjacking is not configured — the site and the admin can be framed.');
    } else {
        out('PASS', 'clickjacking protection configured');
    }
    if (($nelmio['content_type']['nosniff'] ?? false) !== true) {
        out('WARN', 'nelmio_security.content_type.nosniff is not true.');
    }
    if (isset($nelmio['xss_protection'])) {
        out('WARN', 'nelmio_security.xss_protection is deprecated and does nothing in current browsers — remove it.');
    }
    if (isset($nelmio['forced_ssl']) && ($nelmio['forced_ssl']['enabled'] ?? true) !== false) {
        out('WARN', 'nelmio_security.forced_ssl redirects in a loop behind a TLS proxy — remove it; HTTPS and HSTS come from .htaccess.');
    }
    $enforce = $nelmio['csp']['enforce'] ?? [];
    if (($nelmio['csp']['enabled'] ?? true) === false || ! is_array($enforce) || $enforce === []) {
        out('WARN', 'No enforced Content-Security-Policy — add the baseline from examples/nelmio_security.yaml.');
    } else {
        $missing = array_diff(['object-src', 'base-uri', 'frame-ancestors'], array_keys($enforce));
        $missing === []
            ? out('PASS', 'baseline CSP enforced (object-src, base-uri, frame-ancestors)')
            : out('WARN', 'CSP enforce lacks ' . implode(', ', $missing) . '.');
    }
}

if (is_file('public/.htaccess')) {
    $htaccess = (string) file_get_contents('public/.htaccess');
    if (! str_contains($htaccess, 'Strict-Transport-Security')) {
        out('WARN', 'public/.htaccess sends no Strict-Transport-Security header — see bolt-htaccess (security headers).');
    }
    if (! str_contains($htaccess, 'sandbox')) {
        out('WARN', 'public/.htaccess does not sandbox uploads in files/ — see bolt-htaccess (security headers).');
    }
}
