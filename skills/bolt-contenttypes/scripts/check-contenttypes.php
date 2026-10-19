<?php

declare(strict_types=1);

/*
 * Rule checks of bolt-contenttypes for config/bolt/contenttypes.yaml. Reads the project's
 * configuration — never writes — and prints one line per result:
 *
 *   SECTION <title>
 *   PASS <message>
 *   WARN <message>
 *   FAIL <message>
 *
 * Usage: php check-contenttypes.php /path/to/bolt-project
 */

use Symfony\Component\Yaml\Yaml;

$project = $argv[1] ?? getcwd();
chdir($project);

if (! is_file('vendor/autoload.php')) {
    echo "FAIL vendor/autoload.php not found — run composer install first\n";
    exit(0);
}
require 'vendor/autoload.php';

const CT_FILE = 'config/bolt/contenttypes.yaml';

/** Field types whose value is text a visitor reads, so it differs per language. */
const TEXT_TYPES = ['text', 'textarea', 'html', 'markdown', 'redactor', 'article'];

/** Field names that hold the same value in every language (links, contacts, codes). */
const SHARED_NAME = '/(^|_)(url|link|href|email|e_?mail|phone|tel|ico|dic|code|linkedin|facebook|instagram|youtube|twitter)$/i';

function out(string $kind, string $message): void
{
    echo $kind, ' ', $message, PHP_EOL;
}

function readYaml(string $file): ?array
{
    try {
        $data = Yaml::parseFile($file, Yaml::PARSE_CUSTOM_TAGS);
    } catch (Throwable $e) {
        out('FAIL', "{$file}: YAML error — " . $e->getMessage());

        return null;
    }

    return is_array($data) ? $data : [];
}

/**
 * @param array<string, string> $findings path => [kind, message]
 */
function checkFields(array $fields, string $prefix, bool $isLocalized, array &$findings): void
{
    foreach ($fields as $name => $field) {
        if (! is_array($field)) {
            continue;
        }
        $path = $prefix . '.' . $name;
        $type = (string) ($field['type'] ?? '');

        if ($type === 'html') {
            $findings[] = ['FAIL', "{$path}: type: html — use redactor (body copy) or article (long-form); rule 1"];
        }
        if ($type === 'repeater') {
            $findings[] = ['FAIL', "{$path}: type: repeater does not exist since Bolt 5 — use collection + set; rule 4"];
        }
        if (in_array($type, ['redactor', 'article'], true) && ($field['sanitise'] ?? false) !== true) {
            $findings[] = ['FAIL', "{$path}: {$type} without sanitise: true — its HTML is printed unescaped (stored XSS); rule 7"];
        } elseif (($field['sanitise'] ?? null) === false) {
            $findings[] = ['FAIL', "{$path}: sanitise: false — its HTML is printed without cleaning (stored XSS); rule 7"];
        }
        if (! empty($field['allow_twig'])) {
            $findings[] = ['FAIL', "{$path}: allow_twig — the content runs as a server-side Twig template; rule 7"];
        }
        if ($type === 'slug' && empty($field['uses'])) {
            $findings[] = ['FAIL', "{$path}: slug without uses (e.g. uses: [ title ])"];
        }
        // A non-localized field holds one value for every language: editing it on the English
        // tab of the editor overwrites the Czech text. Fine for images, dates, numbers, links;
        // wrong for text a visitor reads.
        if ($isLocalized && in_array($type, TEXT_TYPES, true) && empty($field['localize']) && preg_match(SHARED_NAME, (string) $name) !== 1) {
            $findings[] = ['WARN', "{$path}: {$type} field without localize: true in a multilingual ContentType — one value for every language; rule 5"];
        }

        if (isset($field['fields']) && is_array($field['fields'])) {
            checkFields($field['fields'], $path, $isLocalized, $findings);
        }
    }
}

out('SECTION', 'ContentTypes and fields (' . CT_FILE . ')');

$config = readYaml(CT_FILE);
if ($config === null) {
    exit(0);
}

$services = readYaml('config/services.yaml') ?? [];
$appLocales = array_values(array_filter(array_map('trim', explode('|', (string) ($services['parameters']['app_locales'] ?? '')))));

$findings = [];
$count = 0;
foreach ($config as $key => $definition) {
    if (! is_string($key) || str_starts_with($key, '__')) {
        continue;
    }
    if (! is_array($definition)) {
        $findings[] = ['FAIL', "{$key}: not a mapping of settings"];
        continue;
    }
    ++$count;

    if (empty($definition['name']) && empty($definition['slug'])) {
        $findings[] = ['FAIL', "{$key}: neither name nor slug"];
    }
    if (empty($definition['singular_name']) && empty($definition['singular_slug'])) {
        $findings[] = ['FAIL', "{$key}: neither singular_name nor singular_slug"];
    }
    if (empty($definition['fields']) || ! is_array($definition['fields'])) {
        $findings[] = ['FAIL', "{$key}: no fields"];
        continue;
    }

    if (! empty($definition['singleton'])) {
        $order = $definition['order'] ?? $definition['sort'] ?? null;
        if ($order !== '-id' && $order !== ['-id']) {
            $findings[] = ['FAIL', "{$key}: singleton without order: -id (currently " . var_export($order, true) . ') — templates could fetch an older record; rule 2'];
        }
    }

    $locales = (array) ($definition['locales'] ?? []);
    if ($locales !== [] && $appLocales !== []) {
        $unknown = array_diff($locales, $appLocales);
        if ($unknown !== []) {
            $findings[] = ['FAIL', "{$key}: locales [" . implode(', ', $unknown) . '] are not in app_locales [' . implode(', ', $appLocales) . ']'];
        }
    }
    if ($locales === [] && count($appLocales) > 1) {
        foreach ($definition['fields'] as $name => $field) {
            if (is_array($field) && ! empty($field['localize'])) {
                $findings[] = ['WARN', "{$key}: fields are localize: true ({$name}, …) but the ContentType has no locales — they cannot be translated; add locales"];
                break;
            }
        }
    }

    checkFields($definition['fields'], $key, $locales !== [], $findings);
}

if ($findings === []) {
    out('PASS', "{$count} ContentTypes follow every rule");
} else {
    $failures = count(array_filter($findings, static fn (array $f): bool => $f[0] === 'FAIL'));
    if ($failures === 0) {
        out('PASS', "{$count} ContentTypes: no rule broken (warnings below)");
    }
    foreach ($findings as [$kind, $message]) {
        out($kind, $message);
    }
}
