<?php

declare(strict_types=1);

/*
 * File checks of bolt-add-language for one locale. Reads the project's configuration — never
 * writes — and prints one line per result:
 *
 *   SECTION <title>
 *   PASS <message>
 *   WARN <message>
 *   FAIL <message>
 *
 * Usage: php check-language.php /path/to/bolt-project <locale>
 */

use Symfony\Component\Yaml\Yaml;

$project = $argv[1] ?? getcwd();
$locale = $argv[2] ?? '';
chdir($project);

if ($locale === '') {
    echo "FAIL no locale given — usage: php check-language.php <project> <locale>\n";
    exit(0);
}
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

/**
 * Translation keys of an XLIFF 1.2 or 2.0 catalog, as Symfony's loader reads them:
 * the unit's `name` (2.0) / `resname` (1.2), falling back to the <source> text.
 *
 * @return list<string>|null null when the file cannot be parsed
 */
function catalogKeys(string $file): ?array
{
    $doc = new DOMDocument();
    if (! @$doc->load($file)) {
        return null;
    }
    $xpath = new DOMXPath($doc);
    $keys = [];
    foreach ($xpath->query('//*[local-name()="unit" or local-name()="trans-unit"]') ?: [] as $unit) {
        if (! $unit instanceof DOMElement) {
            continue;
        }
        $key = $unit->getAttribute('name') ?: $unit->getAttribute('resname');
        if ($key === '') {
            $source = $xpath->query('.//*[local-name()="source"]', $unit)?->item(0);
            $key = $source !== null ? trim($source->textContent) : '';
        }
        if ($key !== '') {
            $keys[] = $key;
        }
    }

    return $keys;
}

/** Menu items whose label map lacks the locale, as "menu > item" paths. */
function menuGaps(array $items, string $locale, string $path, array &$plain): array
{
    $gaps = [];
    foreach ($items as $index => $item) {
        if (! is_array($item)) {
            continue;
        }
        $label = $item['label'] ?? null;
        $name = is_array($label) ? (string) (reset($label) ?: $index) : (string) ($label ?? $index);
        $itemPath = $path . ' > ' . $name;
        if (is_array($label) && ! array_key_exists($locale, $label)) {
            $gaps[] = $itemPath;
        } elseif (is_string($label)) {
            $plain[] = $itemPath;
        }
        if (isset($item['submenu']) && is_array($item['submenu'])) {
            $gaps = array_merge($gaps, menuGaps($item['submenu'], $locale, $itemPath, $plain));
        }
    }

    return $gaps;
}

// 1. app_locales
out('SECTION', 'config/services.yaml');
$parameters = readYaml('config/services.yaml')['parameters'] ?? [];
$appLocales = array_values(array_filter(array_map('trim', explode('|', (string) ($parameters['app_locales'] ?? '')))));
$defaultLocale = (string) ($parameters['locale'] ?? '');
if (in_array($locale, $appLocales, true)) {
    out('PASS', "app_locales lists '{$locale}' (" . implode('|', $appLocales) . ')');
} else {
    out('FAIL', "app_locales does not list '{$locale}' (" . implode('|', $appLocales) . ') — Step 1');
}
if (array_key_exists('locales_array', $parameters)) {
    out('WARN', 'services.yaml defines locales_array — Bolt\'s Kernel derives it from app_locales; delete the line so the two cannot drift (Step 1)');
}

// 2. ContentTypes
out('SECTION', 'config/bolt/contenttypes.yaml');
$missing = [];
$single = [];
foreach (readYaml('config/bolt/contenttypes.yaml') as $key => $definition) {
    if (! is_string($key) || str_starts_with($key, '__') || ! is_array($definition)) {
        continue;
    }
    $locales = $definition['locales'] ?? null;
    if ($locales === null || $locales === []) {
        $single[] = $key;
    } elseif (! in_array($locale, (array) $locales, true)) {
        $missing[] = $key;
    }
}
$missing === []
    ? out('PASS', "every ContentType with locales lists '{$locale}'")
    : out('FAIL', "ContentTypes without '{$locale}' in locales: " . implode(', ', $missing) . ' — Step 2 (Bolt redirects these pages to the default locale)');
if ($single !== []) {
    out('WARN', 'ContentTypes without locales (default locale only, fields cannot be translated): ' . implode(', ', $single) . ' — add locales unless that is intended');
}

// 3–4. Catalogs
out('SECTION', 'translations/messages.*.xlf');
$target = "translations/messages.{$locale}.xlf";
$source = "translations/messages.{$defaultLocale}.xlf";
$targetKeys = is_file($target) ? catalogKeys($target) : null;
if (! is_file($target)) {
    out('FAIL', "{$target} does not exist — Step 3 (scripts/merge-xliff.php creates it)");
} elseif ($targetKeys === null) {
    out('FAIL', "{$target} is not valid XML");
} else {
    out('PASS', "{$target} exists (" . count($targetKeys) . ' units)');
}
if ($locale === $defaultLocale) {
    out('PASS', "'{$locale}' is the default locale — it is the source catalog");
} elseif (! is_file($source)) {
    out('WARN', "source catalog {$source} not found — parity not checked");
} elseif ($targetKeys !== null) {
    $sourceKeys = catalogKeys($source) ?? [];
    $absent = array_values(array_diff($sourceKeys, $targetKeys));
    $extra = array_values(array_diff($targetKeys, $sourceKeys));
    $absent === []
        ? out('PASS', "every key of {$source} is in {$target}")
        : out('FAIL', count($absent) . " key(s) of {$source} missing in {$target} (they render as the raw key): " . implode(', ', array_slice($absent, 0, 15)) . (count($absent) > 15 ? ', …' : ''));
    if ($extra !== []) {
        out('WARN', count($extra) . " key(s) only in {$target}: " . implode(', ', array_slice($extra, 0, 15)) . (count($extra) > 15 ? ', …' : ''));
    }
}

// 6. Menus
out('SECTION', 'config/bolt/menu.yaml');
$plain = [];
$gaps = [];
foreach (readYaml('config/bolt/menu.yaml') as $menu => $items) {
    if (is_array($items)) {
        $gaps = array_merge($gaps, menuGaps($items, $locale, (string) $menu, $plain));
    }
}
$gaps === []
    ? out('PASS', "every per-locale menu label has '{$locale}'")
    : out('FAIL', "menu labels without '{$locale}': " . implode('; ', $gaps) . ' — Step 4');
if ($plain !== []) {
    out('WARN', 'menu labels that are plain strings (same text in every locale): ' . implode('; ', array_slice($plain, 0, 10)));
}
