<?php

declare(strict_types=1);

/*
 * File checks of bolt-performance (Twig fragment cache). Reads the project's configuration
 * and theme — never writes — and prints one line per result:
 *
 *   SECTION <title>
 *   PASS <message>
 *   WARN <message>
 *   FAIL <message>
 *
 * Usage: php check-performance.php /path/to/bolt-project
 */

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

/** All files of the active theme with the given extension, relative to the project. */
function themeFiles(string $themeDir, string $extension): array
{
    if (! is_dir($themeDir)) {
        return [];
    }
    $files = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($themeDir, FilesystemIterator::SKIP_DOTS));
    foreach ($iterator as $file) {
        $path = $file->getPathname();
        if (str_contains($path, '/node_modules/') || ! str_ends_with($path, '.' . $extension)) {
            continue;
        }
        $files[] = $path;
    }
    sort($files);

    return $files;
}

const UNCACHEABLE = '/csrf_token|form_start|form\(|app\.user|app\.session|app\.flashes|is_granted/';

/**
 * Searches $source and every theme template it includes (literal names only, any depth) for
 * output that must not be cached. Returns "file: hit" or null.
 *
 * @param array<string, true> $seen
 */
function uncacheableIn(string $themeDir, string $source, string $file, array &$seen = []): ?string
{
    if (preg_match(UNCACHEABLE, $source, $hit)) {
        return "{$file}: `{$hit[0]}`";
    }
    preg_match_all('/(?:\binclude\(\s*|\{%-?\s*(?:include|embed)\s+)[\'"]([^\'"]+\.twig)[\'"]|\btemplate\s*:\s*[\'"]([^\'"]+\.twig)[\'"]/', $source, $names, PREG_SET_ORDER);
    foreach ($names as $name) {
        $template = $name[1] !== '' ? $name[1] : ($name[2] ?? '');
        $path = $themeDir . '/' . $template;
        if ($template === '' || isset($seen[$path]) || ! is_file($path)) {
            continue;
        }
        $seen[$path] = true;
        $found = uncacheableIn($themeDir, (string) file_get_contents($path), $path, $seen);
        if ($found !== null) {
            return $found;
        }
    }

    return null;
}

function lineOf(string $source, int $offset): int
{
    return substr_count(substr($source, 0, $offset), "\n") + 1;
}

$boltConfig = array_replace_recursive(readYaml('config/bolt/config.yaml'), readYaml('config/bolt/config_local.yaml'));
// ContentType slugs as Bolt derives them (ContentTypesParser): `slug:`, otherwise the slugified
// `name`. Bolt tags and invalidates caches with these, not with the YAML keys.
$contentTypes = [];
foreach (readYaml('config/bolt/contenttypes.yaml') as $key => $definition) {
    $definition = is_array($definition) ? $definition : [];
    $slug = $definition['slug'] ?? null;
    if (! is_string($slug) || $slug === '') {
        $name = is_string($definition['name'] ?? null) ? $definition['name'] : (string) $key;
        $slug = class_exists(Bolt\Common\Str::class) ? Bolt\Common\Str::slug($name) : trim((string) preg_replace('/[^a-z0-9]+/', '-', strtolower($name)), '-');
    }
    $contentTypes[] = $slug;
}
$composer = is_file('composer.json') ? (json_decode((string) file_get_contents('composer.json'), true) ?: []) : [];

$serviceSources = '';
foreach (array_merge(glob('config/services*.yaml') ?: [], glob('config/packages/*.yaml') ?: []) as $file) {
    $serviceSources .= file_get_contents($file) . "\n";
}

// -------------------------------------------------------------------------------------------
out('SECTION', 'Twig fragment cache ({% cache %})');

$theme = $boltConfig['theme'] ?? null;
$themeDir = is_string($theme) ? "public/theme/{$theme}" : '';
$twigFiles = $themeDir !== '' ? themeFiles($themeDir, 'twig') : [];

$cacheFiles = [];
foreach ($twigFiles as $file) {
    $source = (string) file_get_contents($file);
    if (preg_match('/\{%-?\s*cache\s/', $source)) {
        $cacheFiles[$file] = $source;
    }
}

if ($themeDir === '' || ! is_dir($themeDir)) {
    out('WARN', 'active theme folder not found (config/bolt/config.yaml theme:) — template checks skipped');
} elseif ($cacheFiles === []) {
    out('PASS', 'no {% cache %} in the theme — fragment caching is optional (pages above ~100 queries)');
} else {
    $installed = isset($composer['require']['twig/cache-extra']) || is_dir('vendor/twig/cache-extra');
    $installed
        ? out('PASS', 'twig/cache-extra installed')
        : out('FAIL', '{% cache %} is used but twig/cache-extra is not installed — composer require twig/cache-extra');

    (bool) preg_match('/twig\.runtime\.cache:\s*\n(?:\s+.*\n)*?\s+arguments:\s*\[\s*[\'"]@cache\.app\.taggable[\'"]\s*\]/', $serviceSources)
        ? out('PASS', 'twig.runtime.cache uses cache.app.taggable — Bolt\'s save events clear the fragments')
        : out('FAIL', 'twig.runtime.cache is not overridden to @cache.app.taggable — cached fragments ignore content saves (examples/services_twig_cache.yaml)');

    $knownTags = array_map('strval', $contentTypes);
    foreach ($cacheFiles as $file => $source) {
        preg_match_all('/\{%-?\s*cache\s(.*?)%\}(.*?)\{%-?\s*endcache\s*-?%\}/s', $source, $blocks, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
        foreach ($blocks as $block) {
            $line = lineOf($source, $block[0][1]);
            $head = $block[1][0];
            $body = $block[2][0];
            $found = uncacheableIn($themeDir, $body, $file);
            if ($found !== null) {
                out('FAIL', "{$file}:{$line}: cached block renders {$found} — user- or request-specific output must not be cached");
            }
            if (! str_contains($head, 'tags(')) {
                out('WARN', "{$file}:{$line}: {% cache %} without tags() — refreshed only by its TTL or a deploy (Step 4)");
            }
            if (! str_contains($source, 'app.request.method')) {
                out('WARN', "{$file}:{$line}: {% cache %} also caches Bolt's preview (POST) — render through partials/_cached.twig (examples/_cached.twig)");
            }
        }
    }

    // Containers cached through partials/_cached.twig: the {% cache %} block there only shows
    // include(template), so look into the template each call passes.
    foreach ($twigFiles as $file) {
        $source = (string) file_get_contents($file);
        if (! preg_match_all('/include\(\s*[\'"]partials\/_cached\.twig[\'"]\s*,\s*\{(.*?)\}\s*\)/s', $source, $calls, PREG_SET_ORDER | PREG_OFFSET_CAPTURE)) {
            continue;
        }
        foreach ($calls as $call) {
            $found = uncacheableIn($themeDir, $call[1][0], $file);
            if ($found !== null) {
                out('FAIL', "{$file}:" . lineOf($source, $call[0][1]) . ": cached container renders {$found} — user- or request-specific output must not be cached");
            }
        }
    }

    // Literal tags passed to partials/_cached.twig or tags([...]) must be ContentType slugs as written.
    foreach ($twigFiles as $file) {
        $source = (string) file_get_contents($file);
        if (! preg_match_all('/tags(?:\s*:\s*|\()\s*\[([^\]]*)\]/', $source, $lists, PREG_OFFSET_CAPTURE)) {
            continue;
        }
        foreach ($lists[1] as [$list, $offset]) {
            preg_match_all('/[\'"]([^\'"]+)[\'"]/', $list, $literals);
            foreach ($literals[1] as $tag) {
                if (in_array($tag, $knownTags, true) || str_starts_with($tag, 'record-') || in_array($tag, ['frontendmenu', 'backendmenu', 'fileslisting'], true)) {
                    continue;
                }
                $match = array_filter($knownTags, static fn (string $slug): bool => str_replace('-', '', $slug) === $tag);
                $hint = $match !== [] ? ' — Bolt invalidates \'' . reset($match) . '\' (with the hyphen)' : ' — not the slug of a ContentType (' . implode(', ', $knownTags) . ')';
                out('WARN', "{$file}:" . lineOf($source, $offset) . ": cache tag '{$tag}' is never invalidated by Bolt{$hint}");
            }
        }
    }
}
