<?php

declare(strict_types=1);

/*
 * Admin icons of ContentTypes (rule 11). Bolt renders `icon_one` / `icon_many` as
 * `<i class="fas fa-<name>">` — Font Awesome Free *solid*, in the version bundled with
 * bolt/assets (5.15.4 in Bolt 6.1). Font Awesome 6 / 7 names (`sliders`, `house`,
 * `screwdriver-wrench`, `gear`, …) and regular-only or brand icons render as an empty box.
 *
 * The version and the icon classes are read from the admin CSS the project serves
 * (public/assets/*.css); which names have a solid glyph comes from
 * references/fontawesome-<version>-solid.tsv, generated from Font Awesome's own metadata.
 *
 * Usage:
 *   php admin-icons.php check /path/to/bolt-project
 *       Checks every icon_one / icon_many of config/bolt/contenttypes.yaml; prints
 *       SECTION / PASS / WARN / FAIL lines (verify.sh reads them).
 *   php admin-icons.php list [--project=/path] [term …]
 *       Lists the icons that render in the admin, filtered by name or search term
 *       (`list car`, `list settings`, `list invoice`).
 *   php admin-icons.php generate --version=5.15.4 <5.x icons.yml> [<6.x icons.yml> <7.x icons.yml> …]
 *       Writes references/fontawesome-<version>-solid.tsv from the metadata/icons.yml of
 *       `npm pack @fortawesome/fontawesome-free@<version>`; newer major versions add the
 *       names that replaced each icon. Run it when bolt/assets ships another Font Awesome.
 */

use Symfony\Component\Yaml\Yaml;

const CT_FILE = 'config/bolt/contenttypes.yaml';

/** Bolt's fallback when a ContentType sets no icon (ContentTypesParser). */
const BOLT_DEFAULT_ICONS = ['icon_one' => 'file', 'icon_many' => 'copy'];

$referenceDir = dirname(__DIR__) . '/references';

function out(string $kind, string $message): void
{
    echo $kind, ' ', $message, PHP_EOL;
}

function requireAutoload(string $project): bool
{
    foreach ([$project . '/vendor/autoload.php', dirname(__DIR__, 3) . '/vendor/autoload.php'] as $autoload) {
        if (is_file($autoload)) {
            require_once $autoload;

            return true;
        }
    }

    return false;
}

/**
 * Bolt's compiled admin stylesheets: the copy the web server serves, else the package.
 *
 * @return list<string>
 */
function adminStylesheets(string $project): array
{
    foreach (['public/assets', 'vendor/bolt/assets/assets'] as $dir) {
        $files = glob($project . '/' . $dir . '/*.css') ?: [];
        $files = array_values(array_filter($files, static fn (string $f): bool => str_contains((string) file_get_contents($f), 'Font Awesome')));
        if ($files !== []) {
            return $files;
        }
    }

    return [];
}

/**
 * @param list<string> $stylesheets
 *
 * @return array{0: ?string, 1: array<string, true>} [version, icon class names]
 */
function readStylesheets(array $stylesheets): array
{
    $version = null;
    $classes = [];
    foreach ($stylesheets as $file) {
        $css = (string) file_get_contents($file);
        if ($version === null && preg_match('/Font Awesome Free (\d+\.\d+\.\d+)/', $css, $m) === 1) {
            $version = $m[1];
        }
        preg_match_all('/\.fa-([a-z0-9-]+):{1,2}before/', $css, $m);
        foreach ($m[1] as $name) {
            $classes[$name] = true;
        }
    }

    return [$version, $classes];
}

/**
 * @return array<string, array{newer: list<string>, terms: list<string>}>|null
 */
function readReference(string $referenceDir, string $version): ?array
{
    $file = "{$referenceDir}/fontawesome-{$version}-solid.tsv";
    if (! is_file($file)) {
        return null;
    }
    $icons = [];
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (str_starts_with($line, '#')) {
            continue;
        }
        [$name, $newer, $terms] = array_pad(explode("\t", $line), 3, '');
        $icons[$name] = [
            'newer' => $newer === '' ? [] : explode(',', $newer),
            'terms' => $terms === '' ? [] : explode(',', $terms),
        ];
    }

    return $icons;
}

/**
 * What Bolt makes of the configured value: `fa:` becomes `fa-` (ContentTypesParser), then every
 * `fa-` is removed and the rest printed as `fas fa-<rest>` (_macro.html.twig icon(), ContentExtension::icon()).
 */
function renderedName(string $value): string
{
    return str_replace('fa-', '', str_replace('fa:', 'fa-', trim($value)));
}

/**
 * @param array<string, array{newer: list<string>, terms: list<string>}> $icons
 */
function suggest(string $name, array $icons, string $version): string
{
    $renamed = [];
    foreach ($icons as $icon => $data) {
        if (in_array($name, $data['newer'], true)) {
            $renamed[] = $icon;
        }
    }
    if ($renamed !== []) {
        return "'{$name}' is a newer Font Awesome name — Bolt bundles {$version}, use fa:" . implode(' or fa:', $renamed);
    }

    $similar = [];
    $tokens = explode('-', $name);
    foreach (array_keys($icons) as $icon) {
        $distance = levenshtein($name, $icon);
        $shared = count(array_intersect($tokens, explode('-', $icon)));
        if ($distance <= 2 || $shared > 0 || in_array($name, $icons[$icon]['terms'], true)) {
            $similar[$icon] = $distance - 3 * $shared;
        }
    }
    asort($similar);
    $similar = array_slice(array_keys($similar), 0, 6);

    $search = "search by meaning: php admin-icons.php list <word>";

    return $similar === []
        ? "no solid icon '{$name}' in Font Awesome {$version}; {$search}"
        : "no solid icon '{$name}' in Font Awesome {$version} — similar names: fa:" . implode(', fa:', $similar) . "; {$search}";
}

function check(string $project, string $referenceDir): void
{
    out('SECTION', 'Admin icons (icon_one / icon_many → Font Awesome solid)');

    if (! requireAutoload($project)) {
        out('FAIL', 'vendor/autoload.php not found — run composer install first');

        return;
    }

    $stylesheets = adminStylesheets($project);
    if ($stylesheets === []) {
        out('WARN', 'Bolt admin CSS with Font Awesome not found in public/assets/ or vendor/bolt/assets/assets/ — run composer install (bolt/assets); icons not checked');

        return;
    }
    [$version, $classes] = readStylesheets($stylesheets);
    $icons = $version === null ? null : readReference($referenceDir, $version);
    if ($icons === null) {
        out('WARN', 'Font Awesome ' . ($version ?? '(unknown version)') . " in Bolt's admin CSS has no icon list in references/ — only the CSS classes are checked; generate the list (admin-icons.php generate), rule 11");
    }

    try {
        $config = Yaml::parseFile($project . '/' . CT_FILE, Yaml::PARSE_CUSTOM_TAGS);
    } catch (Throwable $e) {
        out('FAIL', CT_FILE . ': YAML error — ' . $e->getMessage());

        return;
    }

    $findings = [];
    $checked = [];
    foreach (is_array($config) ? $config : [] as $key => $definition) {
        if (! is_string($key) || str_starts_with($key, '__') || ! is_array($definition)) {
            continue;
        }
        foreach (BOLT_DEFAULT_ICONS as $option => $default) {
            if (! isset($definition[$option]) || trim((string) $definition[$option]) === '') {
                $findings[] = ['WARN', "{$key}: no {$option} — Bolt shows fa:{$default} for every type without one; pick a solid icon, rule 11"];
                continue;
            }
            $value = (string) $definition[$option];
            if (preg_match('/^fa:[a-z0-9]+(-[a-z0-9]+)*$/', $value) !== 1) {
                $findings[] = ['FAIL', "{$key}.{$option}: '{$value}' — write fa:<name> (Bolt prints `fas fa-<name>` itself; style prefixes like fas / far / fab or a second class break the class), rule 11"];
                continue;
            }
            $name = renderedName($value);
            if (! isset($classes[$name])) {
                $findings[] = ['FAIL', "{$key}.{$option}: fa:{$name} has no class in Bolt's admin CSS (Font Awesome {$version}) — it renders as an empty box; " . ($icons === null ? 'pick another icon' : suggest($name, $icons, (string) $version)) . ', rule 11'];
            } elseif ($icons !== null && ! isset($icons[$name])) {
                $findings[] = ['FAIL', "{$key}.{$option}: fa:{$name} is a brand or regular-only icon — Bolt renders it as solid (fas), where it has no glyph; " . suggest($name, $icons, (string) $version) . ', rule 11'];
            } else {
                $checked[$name] = true;
            }
        }
    }

    $failures = count(array_filter($findings, static fn (array $f): bool => $f[0] === 'FAIL'));
    if ($failures === 0) {
        out('PASS', count($checked) . " distinct icons are solid icons of Font Awesome {$version} (Bolt's admin CSS: " . implode(', ', array_map('basename', $stylesheets)) . ')');
    }
    foreach ($findings as [$kind, $message]) {
        out($kind, $message);
    }
}

/**
 * @param list<string> $terms
 */
function listIcons(string $project, string $referenceDir, array $terms): int
{
    $version = null;
    if (requireAutoload($project) && ($stylesheets = adminStylesheets($project)) !== []) {
        [$version] = readStylesheets($stylesheets);
    }
    if ($version === null) {
        $files = glob($referenceDir . '/fontawesome-*-solid.tsv') ?: [];
        natsort($files);
        $version = preg_replace('/^fontawesome-(.+)-solid\.tsv$/', '$1', basename((string) end($files)));
        fwrite(STDERR, "Bolt's admin CSS not found in {$project} — listing Font Awesome {$version}\n");
    }
    $icons = readReference($referenceDir, (string) $version);
    if ($icons === null) {
        fwrite(STDERR, "No icon list for Font Awesome {$version} in references/ — run: php admin-icons.php generate --version={$version} …\n");

        return 1;
    }

    $count = 0;
    foreach ($icons as $name => $data) {
        // Whole words of the name, the newer names and the search terms: `car` finds car-side,
        // taxi (term "car"), not caret or card.
        $words = preg_split('/[\s-]+/', mb_strtolower(implode(' ', array_merge([$name], $data['newer'], $data['terms']))));
        foreach ($terms as $term) {
            $term = mb_strtolower($term);
            if (! in_array($term, $words, true) && ! in_array($term, array_merge([$name], $data['newer']), true)) {
                continue 2;
            }
        }
        ++$count;
        $newer = $data['newer'] === [] ? '' : ' (newer: ' . implode(', ', $data['newer']) . ')';
        printf("fa:%-28s %s%s\n", $name, implode(', ', array_slice($data['terms'], 0, 8)), $newer);
    }
    fwrite(STDERR, "{$count} solid icons of Font Awesome {$version} render in Bolt's admin" . ($terms === [] ? '' : ' and match ' . implode(' ', $terms)) . "\n");

    return 0;
}

/**
 * @param list<string> $sources
 */
function generate(string $referenceDir, string $version, array $sources): int
{
    if (! requireAutoload((string) getcwd())) {
        fwrite(STDERR, "symfony/yaml not found — run it from a Bolt project or after composer install in bolt-skills\n");

        return 1;
    }
    $base = Yaml::parseFile((string) array_shift($sources));
    $newer = [];
    $unicodes = [];
    foreach ($sources as $source) {
        foreach (Yaml::parseFile($source) as $name => $icon) {
            $name = (string) $name;
            foreach ($icon['aliases']['names'] ?? [] as $alias) {
                $newer[$alias][$name] = true;
            }
            $unicodes[strtolower((string) ($icon['unicode'] ?? ''))][$name] = true;
        }
    }

    $lines = [
        "# Font Awesome Free {$version} solid icons — the names Bolt's admin renders for icon_one / icon_many.",
        '# Generated by bolt-contenttypes/scripts/admin-icons.php generate from @fortawesome/fontawesome-free metadata/icons.yml.',
        '# Columns: name <TAB> names in newer major versions (comma-separated) <TAB> search terms (comma-separated)',
    ];
    $count = 0;
    foreach ($base as $name => $icon) {
        if (! in_array('solid', $icon['styles'] ?? [], true)) {
            continue;
        }
        $name = (string) $name;
        // A renamed icon keeps its code point; newer metadata lists the old name as an alias.
        $renamed = array_keys(($newer[$name] ?? []) + ($unicodes[strtolower((string) $icon['unicode'])] ?? []));
        $renamed = array_values(array_diff($renamed, [$name]));
        $terms = array_map(static fn ($t): string => str_replace([',', "\t"], ' ', (string) $t), $icon['search']['terms'] ?? []);
        $lines[] = $name . "\t" . implode(',', $renamed) . "\t" . implode(',', array_unique($terms));
        ++$count;
    }

    $file = "{$referenceDir}/fontawesome-{$version}-solid.tsv";
    file_put_contents($file, implode("\n", $lines) . "\n");
    fwrite(STDERR, "{$count} solid icons written to {$file}\n");

    return 0;
}

$command = $argv[1] ?? 'check';
$args = array_slice($argv, 2);

switch ($command) {
    case 'check':
        check(realpath($args[0] ?? '.') ?: '.', $referenceDir);
        exit(0);
    case 'list':
        $project = '.';
        $terms = [];
        foreach ($args as $arg) {
            if (str_starts_with($arg, '--project=')) {
                $project = substr($arg, 10);
            } else {
                $terms[] = $arg;
            }
        }
        exit(listIcons(realpath($project) ?: $project, $referenceDir, $terms));
    case 'generate':
        $version = null;
        $sources = [];
        foreach ($args as $arg) {
            if (str_starts_with($arg, '--version=')) {
                $version = substr($arg, 10);
            } else {
                $sources[] = $arg;
            }
        }
        if ($version === null || $sources === []) {
            fwrite(STDERR, "Usage: php admin-icons.php generate --version=5.15.4 <5.x icons.yml> [<newer icons.yml> …]\n");
            exit(1);
        }
        exit(generate($referenceDir, $version, $sources));
    default:
        fwrite(STDERR, "Usage: php admin-icons.php check <project> | list [--project=<path>] [term …] | generate --version=<x.y.z> <icons.yml> …\n");
        exit(1);
}
