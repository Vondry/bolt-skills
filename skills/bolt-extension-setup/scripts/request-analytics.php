<?php

declare(strict_types=1);

/*
 * Request analytics configuration (bolt-extension-setup section 4), run by verify.sh from the
 * project root once tomvondracek/bolt-request-analytics is installed.
 *
 * Checks that the hosts the extension answers are trusted by Symfony, that the site's own hosts
 * are listed, and that the spool and the SQLite file stay out of Git and out of public/. Prints
 * one line per finding: `OK|…`, `WARN|…` or `FAIL|…`.
 *
 * Usage: php request-analytics.php <config file>
 */

use Symfony\Component\Yaml\Yaml;

[, $configFile] = $argv + [null, 'config/extensions/tomvondracek-requestanalytics.yaml'];
if (! is_file('vendor/autoload.php')) {
    echo "WARN|vendor/autoload.php missing — run composer install to check the request analytics config\n";
    exit;
}
require 'vendor/autoload.php';

try {
    $config = Yaml::parseFile($configFile);
} catch (Throwable $e) {
    echo "FAIL|$configFile is not valid YAML: {$e->getMessage()}\n";
    exit;
}
$config = is_array($config) ? $config : [];

/**
 * Value of a variable in .env, which holds the production values (bolt-security-hardening Step 1);
 * .env.local is for local development and is not read. The last definition wins, quotes removed.
 */
$env = static function (string $name): ?string {
    $value = null;
    foreach (is_file('.env') ? (file('.env', FILE_IGNORE_NEW_LINES) ?: []) : [] as $line) {
        if (preg_match('/^\s*' . preg_quote($name, '/') . '=(.*)$/', $line, $m)) {
            $value = trim(trim($m[1]), "'\"");
        }
    }

    return $value;
};

$hosts = static fn (mixed $list): array => array_values(array_filter(
    is_array($list) ? $list : [],
    static fn (mixed $host): bool => is_string($host) && $host !== ''
));

if (($config['enabled'] ?? true) === false) {
    echo "WARN|enabled: false — nothing is collected\n";
}

// own_hosts: without them a proxy's Host or the www twin turns internal clicks into referrals.
$ownHosts = $hosts($config['own_hosts'] ?? []);
$canonicalHost = parse_url((string) $env('BOLT_CANONICAL'), PHP_URL_HOST);
if ($ownHosts === []) {
    echo "WARN|own_hosts is empty — list the canonical host and its www twin (section 4.3)\n";
} elseif (is_string($canonicalHost) && ! in_array(strtolower($canonicalHost), array_map('strtolower', $ownHosts), true)) {
    echo "WARN|own_hosts lacks the canonical host $canonicalHost (BOLT_CANONICAL) — section 4.3\n";
} else {
    echo 'OK|own_hosts: ' . implode(', ', $ownHosts) . "\n";
}

// Aliases in count mode are answered by the application itself: Symfony must trust their Host.
$aliases = is_array($config['aliases'] ?? null) ? $config['aliases'] : [];
$aliasHosts = $hosts($aliases['hosts'] ?? []);
$mode = $aliases['mode'] ?? 'count';
if ($aliasHosts !== []) {
    $target = $aliases['target'] ?? null;
    if (! is_string($target) || $target === '') {
        echo "FAIL|aliases.hosts is set but aliases.target is empty — set it to the canonical URL (section 4.4)\n";
    } elseif (is_string($canonicalHost) && parse_url($target, PHP_URL_HOST) !== $canonicalHost) {
        echo "WARN|aliases.target $target is not on the canonical host $canonicalHost (section 4.4)\n";
    }
}

$trusted = $env('SYMFONY_TRUSTED_HOSTS');
if ($trusted === null || $trusted === '') {
    echo "WARN|SYMFONY_TRUSTED_HOSTS is empty — every Host is accepted (bolt-security-hardening Step 1)\n";
} else {
    $answered = $ownHosts;
    if ($mode === 'count') {
        // In count mode every listed host must reach the application; markers like `poster-a2` are tag mode only.
        $answered = array_merge($answered, $aliasHosts);
    }
    // One pattern, matched the way Symfony's Request::getHost() does: `{<pattern>}i`.
    $untrusted = array_values(array_filter($answered, static fn (string $host): bool => @preg_match('{' . $trusted . '}i', $host) !== 1));
    if (@preg_match('{' . $trusted . '}i', '') === false) {
        echo "FAIL|SYMFONY_TRUSTED_HOSTS is not a valid regular expression\n";
    } elseif ($untrusted !== []) {
        echo 'FAIL|SYMFONY_TRUSTED_HOSTS rejects ' . implode(', ', $untrusted)
            . " (HTTP 400) — add them to the pattern (section 4.4)\n";
    } elseif ($aliasHosts !== [] && $mode === 'count') {
        echo 'OK|alias hosts trusted and counted: ' . implode(', ', $aliasHosts) . "\n";
    }
}

// The SQLite file and the spool: never in public/, never in Git.
$database = (string) ($config['storage']['database'] ?? '%kernel.project_dir%/var/data/request-analytics.db');
$spool = (string) ($config['collector']['spool_dir'] ?? '%kernel.project_dir%/var/request-analytics/spool');
foreach (['storage.database' => $database, 'collector.spool_dir' => $spool] as $key => $path) {
    $relative = str_replace('%kernel.project_dir%/', '', $path);
    if (str_starts_with($relative, 'public/')) {
        echo "FAIL|$key is in public/ — the extension refuses it; use var/ (section 4.3)\n";
    }
}

$gitignore = is_file('.gitignore') ? (string) file_get_contents('.gitignore') : '';
if (! preg_match('{^/?var/request-analytics/?\*?\s*$}m', $gitignore) && ! preg_match('{^/?var/?\*?\s*$}m', $gitignore)) {
    echo "WARN|.gitignore lacks /var/request-analytics/ — the spool of waiting visits would be committed (section 4.2)\n";
} else {
    echo "OK|.gitignore keeps the spool out of Git\n";
}
if (str_contains($database, 'var/data/') && ! preg_match('{^/?var/data/\*?\s*$}m', $gitignore) && ! preg_match('{^/?var/?\*?\s*$}m', $gitignore)) {
    echo "WARN|.gitignore lacks /var/data/* — the statistics database would be committed (section 4.2)\n";
}

// symfony/lock comes with the extension; its Flex recipe reads LOCK_DSN.
if (is_file('config/packages/lock.yaml') && str_contains((string) file_get_contents('config/packages/lock.yaml'), 'LOCK_DSN')
    && $env('LOCK_DSN') === null) {
    echo "FAIL|config/packages/lock.yaml reads LOCK_DSN, which .env does not define — add LOCK_DSN=flock (section 4.2)\n";
}
