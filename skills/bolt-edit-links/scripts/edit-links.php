<?php

declare(strict_types=1);

/*
 * bolt-edit-links: installs the edit macro, lists where the theme still needs a pencil, and checks
 * the result.
 *
 *   php edit-links.php install /path/to/project   adds or upgrades `edit` in macros.twig
 *   php edit-links.php scan /path/to/project      worklist of places without a pencil (--all: every place)
 *   php edit-links.php check /path/to/project     SECTION / PASS / WARN / FAIL lines for verify.sh
 *
 * Only `install` writes, and only to macros.twig. The analysis reads Twig as text: variables are
 * followed through setcontent, loops, includes and extends, which covers the contract's
 * Component / Container / Page layout. What it cannot resolve it leaves alone.
 */

use Symfony\Component\Yaml\Yaml;

$arguments = array_slice($argv, 1);
$showAll = in_array('--all', $arguments, true);
$positional = array_values(array_filter($arguments, static fn (string $a): bool => ! str_starts_with($a, '--')));
$mode = $positional[0] ?? '';
$project = $positional[1] ?? (string) getcwd();

if (! in_array($mode, ['install', 'scan', 'check'], true)) {
    fwrite(STDERR, "Usage: php edit-links.php install|scan|check [/path/to/project] [--all]\n");
    exit(2);
}

$macroExample = __DIR__ . '/../examples/macro-edit.twig';
chdir($project);

if (! is_file('vendor/autoload.php')) {
    echo $mode === 'check' ? "FAIL vendor/autoload.php not found — run composer install first\n" : "ERROR: vendor/autoload.php not found — run composer install first\n";
    exit($mode === 'check' ? 0 : 1);
}
require 'vendor/autoload.php';

const NOT_RENDERED_TABS = ['seo', 'meta', 'relations'];
const NOT_RENDERED_TYPES = ['seo', 'hidden', 'slug'];
const NO_DATABASE_FOLDERS = ['helper-pages/', 'extensions/'];
// Filters that turn a record into something else: `record|taxonomies` is not a list of records.
const VALUE_FILTERS = 'title|link|image|excerpt|thumbnail|taxonomies|related_by_type|edit_link|date|length|media|json_encode';

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

function slugOf(string $text): string
{
    return Bolt\Common\Str::slug($text);
}

function lineOf(string $source, int $offset): int
{
    return substr_count(substr($source, 0, $offset), "\n") + 1;
}

/** Blanks Twig comments, keeping every offset and line number. */
function blankComments(string $source): string
{
    return (string) preg_replace_callback('/\{#.*?#\}/s', static fn (array $m): string => (string) preg_replace('/[^\n]/', ' ', $m[0]), $source);
}

/** Offset of the bracket closing the one at $open, or -1. Skips quoted strings. */
function closing(string $source, int $open): int
{
    $pairs = ['(' => ')', '[' => ']', '{' => '}'];
    $stack = [];
    $quote = null;
    for ($i = $open, $n = strlen($source); $i < $n; $i++) {
        $char = $source[$i];
        if ($quote !== null) {
            if ($char === '\\') {
                $i++;
            } elseif ($char === $quote) {
                $quote = null;
            }
        } elseif ($char === '"' || $char === "'") {
            $quote = $char;
        } elseif (isset($pairs[$char])) {
            $stack[] = $pairs[$char];
        } elseif ($stack !== [] && $char === end($stack)) {
            array_pop($stack);
            if ($stack === []) {
                return $i;
            }
        }
    }

    return -1;
}

/** @return list<string> the arguments of a call, split at its top-level commas */
function splitArguments(string $text): array
{
    $parts = [];
    $start = 0;
    $quote = null;
    for ($i = 0, $n = strlen($text); $i < $n; $i++) {
        $char = $text[$i];
        if ($quote !== null) {
            if ($char === '\\') {
                $i++;
            } elseif ($char === $quote) {
                $quote = null;
            }
        } elseif ($char === '"' || $char === "'") {
            $quote = $char;
        } elseif (in_array($char, ['(', '[', '{'], true)) {
            $end = closing($text, $i);
            if ($end > 0) {
                $i = $end;
            }
        } elseif ($char === ',') {
            $parts[] = trim(substr($text, $start, $i - $start));
            $start = $i + 1;
        }
    }
    $parts[] = trim(substr($text, $start));

    return $parts;
}

/** @return array<string, array> ContentTypes by slug, with their tabs as Bolt derives them */
function loadContentTypes(): array
{
    $types = [];
    foreach (readYaml('config/bolt/contenttypes.yaml') as $key => $definition) {
        if (! is_array($definition) || str_starts_with((string) $key, '__') || ! is_array($definition['fields'] ?? null)) {
            continue;
        }
        $name = is_string($definition['name'] ?? null) ? $definition['name'] : (string) $key;
        $slug = is_string($definition['slug'] ?? null) && $definition['slug'] !== '' ? $definition['slug'] : slugOf($name);

        // ContentTypesParser: a field without `group` stays in the group of the field before it.
        $current = 'content';
        $groups = [];
        $fieldGroups = [];
        $rendered = [];
        foreach ($definition['fields'] as $field => $settings) {
            $settings = is_array($settings) ? $settings : [];
            $current = is_string($settings['group'] ?? null) && $settings['group'] !== '' ? $settings['group'] : $current;
            $groups[$current] = $current;
            $fieldGroups[(string) $field] = $current;
            if (! in_array($settings['type'] ?? 'text', NOT_RENDERED_TYPES, true) && empty($settings['hidden'])) {
                $rendered[$current] = true;
            }
        }
        if (! empty($definition['relations']) || ! empty($definition['taxonomy'])) {
            $groups['Relations'] = 'Relations';
        }

        $types[$slug] = [
            'key' => (string) $key,
            'name' => $name,
            'singular_slug' => is_string($definition['singular_slug'] ?? null) ? $definition['singular_slug'] : slugOf((string) ($definition['singular_name'] ?? $name)),
            'singleton' => ! empty($definition['singleton']),
            'viewless' => ! empty($definition['viewless']),
            'record_template' => $definition['record_template'] ?? null,
            'listing_template' => $definition['listing_template'] ?? null,
            'groups' => array_values($groups),
            'fieldGroups' => $fieldGroups,
            'renderedGroups' => array_keys($rendered),
        ];
    }

    return $types;
}

/** @return array<string, string> theme-relative template name => source without comments */
function loadTemplates(string $themeDir): array
{
    $templates = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($themeDir, FilesystemIterator::SKIP_DOTS));
    foreach ($iterator as $file) {
        $path = $file->getPathname();
        if (str_ends_with($path, '.twig') && ! str_contains($path, '/node_modules/')) {
            $templates[substr($path, strlen($themeDir) + 1)] = blankComments((string) file_get_contents($path));
        }
    }
    ksort($templates);

    return $templates;
}

function templateNames(string $text): array
{
    preg_match_all('/[\'"](?:@theme\/)?([^\'"]+\.twig)[\'"]/', $text, $names);

    return $names[1];
}

/** @return list<array{names: list<string>, args: string, offset: int, end: int, context: bool}> */
function includesOf(string $source): array
{
    $found = [];
    preg_match_all('/(?<![\w.])include\s*\(/', $source, $calls, PREG_OFFSET_CAPTURE);
    foreach ($calls[0] as [$text, $offset]) {
        $open = $offset + strlen($text) - 1;
        $close = closing($source, $open);
        if ($close < 0) {
            continue;
        }
        $parts = splitArguments(substr($source, $open + 1, $close - $open - 1));
        $found[] = [
            'names' => templateNames($parts[0]),
            'args' => $parts[1] ?? '',
            'offset' => $offset,
            'end' => $close + 1,
            'context' => ! preg_match('/with_context\s*=\s*false/', implode(',', $parts)),
        ];
    }
    preg_match_all('/\{%-?\s*(?:include|embed)\s+(.*?)-?%\}/s', $source, $tags, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
    foreach ($tags as $tag) {
        $parts = preg_split('/\swith\s/', $tag[1][0], 2) ?: [$tag[1][0]];
        $found[] = [
            'names' => templateNames($parts[0]),
            'args' => $parts[1] ?? '',
            'offset' => $tag[0][1],
            'end' => $tag[0][1] + strlen($tag[0][0]),
            'context' => ! preg_match('/\bonly\s*$/', $tag[1][0]),
        ];
    }
    foreach ($found as $i => $include) {
        // partials/_cached.twig (bolt-performance) renders the template named in its arguments.
        if (array_filter($include['names'], static fn (string $n): bool => str_ends_with($n, '_cached.twig')) !== []
            && preg_match('/\btemplate\s*:\s*[\'"](?:@theme\/)?([^\'"]+\.twig)[\'"]/', $include['args'], $target)) {
            $found[$i]['names'][] = $target[1];
        }
    }

    return $found;
}

function extendsOf(string $source): ?string
{
    return preg_match('/\{%-?\s*extends\s+[\'"](?:@theme\/)?([^\'"]+)[\'"]/', $source, $match) ? $match[1] : null;
}

function isLayout(string $template): bool
{
    return str_starts_with($template, 'partials/') || str_starts_with($template, 'helper-pages/');
}

function firstExisting(array $candidates, array $templates): ?string
{
    foreach ($candidates as $candidate) {
        if (is_string($candidate) && isset($templates[$candidate])) {
            return $candidate;
        }
    }

    return null;
}

/** @return array<string, array{record: ?string, home: ?string, listing: ?string}> entry templates per ContentType */
function entryTemplates(array $types, array $config, array $templates): array
{
    $homepage = is_string($config['homepage'] ?? null) ? explode('/', $config['homepage'])[0] : '';
    $entries = [];
    foreach ($types as $slug => $type) {
        if ($type['viewless']) {
            continue;
        }
        $isHome = $homepage !== '' && in_array($homepage, [$slug, $type['singular_slug'], $type['key']], true);
        $home = $isHome ? firstExisting([$config['homepage_template'] ?? null], $templates) : null;
        $entries[$slug] = [
            // TemplateChooser: the homepage template comes first, the record templates are its fallback.
            'record' => $home !== null ? null : firstExisting([$type['record_template'], $type['singular_slug'] . '.twig', $config['record_template'] ?? null, 'record.twig'], $templates),
            'home' => $home,
            'listing' => $type['singleton'] ? null : firstExisting([$type['listing_template'], $slug . '.twig', $config['listing_template'] ?? null, 'listing.twig'], $templates),
        ];
    }

    return $entries;
}

/** Which ContentTypes each template variable can hold: template => var => [slug => true]. */
function variableTypes(array $templates, array $types, array $entries, array $config): array
{
    $env = array_fill_keys(array_keys($templates), []);
    // Search results can be records of any ContentType with a page of its own.
    $search = firstExisting([$config['search_results_template'] ?? null, 'search.twig'], $templates);
    if ($search !== null) {
        foreach (array_keys($entries) as $slug) {
            $env[$search]['records'][$slug] = true;
        }
    }
    foreach ($entries as $slug => $entry) {
        foreach (array_filter([$entry['record'], $entry['home']]) as $template) {
            $env[$template]['record'][$slug] = true;
        }
        if ($entry['listing'] !== null) {
            $env[$entry['listing']]['records'][$slug] = true;
        }
    }
    foreach ($templates as $template => $source) {
        preg_match_all('/\{%-?\s*setcontent\s+(\w+)\s*=\s*[\'"]([\w-]+)|\{%-?\s*set\s+(\w+)\s*=[^%]*?\|\s*related\(\s*[\'"]([\w-]+)/', $source, $queries, PREG_SET_ORDER | PREG_UNMATCHED_AS_NULL);
        foreach ($queries as $found) {
            $variable = $found[1] ?? $found[3];
            $query = $found[2] ?? $found[4];
            foreach ($types as $slug => $type) {
                if (in_array($query, [$slug, $type['singular_slug'], $type['key']], true)) {
                    $env[$template][$variable][$slug] = true;
                }
            }
        }
    }

    // Follow loops, includes and extends until nothing new turns up.
    for ($pass = 0; $pass < 10; $pass++) {
        $before = serialize($env);
        foreach ($templates as $template => $source) {
            preg_match_all('/\{%-?\s*for\s+(?:\w+\s*,\s*)?(\w+)\s+in\s+(\w+)(?![\w.\[])(?!\s*\|\s*(?:' . VALUE_FILTERS . '))/', $source, $loops, PREG_SET_ORDER);
            foreach ($loops as [, $item, $list]) {
                $env[$template][$item] = ($env[$template][$item] ?? []) + ($env[$template][$list] ?? []);
            }
            // {% set sorted = bands|sortBands %} still holds the same records; record|title does not.
            preg_match_all('/\{%-?\s*set\s+(\w+)\s*=\s*(\w+)\s*(?:\|\s*(?!' . VALUE_FILTERS . ')|-?%\})/', $source, $copies, PREG_SET_ORDER);
            foreach ($copies as [, $copy, $original]) {
                $env[$template][$copy] = ($env[$template][$copy] ?? []) + ($env[$template][$original] ?? []);
            }
            $parent = extendsOf($source);
            if ($parent !== null && isset($env[$parent])) {
                // A page shares its record with its page-level parent; a layout shares its own
                // queries (`settings`) with the blocks of the pages that extend it.
                [$from, $to] = isLayout($parent) ? [$parent, $template] : [$template, $parent];
                foreach ($env[$from] as $variable => $slugs) {
                    $env[$to][$variable] = ($env[$to][$variable] ?? []) + $slugs;
                }
            }
            foreach (includesOf($source) as $include) {
                preg_match_all('/(?<![\w.])(\w+)\s*:\s*([a-zA-Z_]\w*)\s*(?=,|\}|$)/', $include['args'], $mapped, PREG_SET_ORDER);
                foreach ($include['names'] as $name) {
                    if (! isset($env[$name])) {
                        continue;
                    }
                    if ($include['context']) {
                        foreach ($env[$template] as $variable => $slugs) {
                            $env[$name][$variable] = ($env[$name][$variable] ?? []) + $slugs;
                        }
                    }
                    foreach ($mapped as [, $parameter, $value]) {
                        $env[$name][$parameter] = ($env[$name][$parameter] ?? []) + ($env[$template][$value] ?? []);
                    }
                }
            }
        }
        if ($before === serialize($env)) {
            break;
        }
    }

    return array_map(static fn (array $variables): array => array_filter($variables), $env);
}

/** @return array{dotted: list<string>, bare: list<string>} how this template imports `edit` */
function macroNames(string $source): array
{
    preg_match_all('/\{%-?\s*import\s+[\'"](?:@theme\/)?macros\.twig[\'"]\s+as\s+(\w+)/', $source, $imports);
    $bare = [];
    preg_match_all('/\{%-?\s*from\s+[\'"](?:@theme\/)?macros\.twig[\'"]\s+import\s+(.*?)-?%\}/s', $source, $froms);
    foreach ($froms[1] as $list) {
        foreach (explode(',', $list) as $item) {
            if (preg_match('/^\s*edit(?:\s+as\s+(\w+))?\s*$/', $item, $match)) {
                $bare[] = $match[1] ?? 'edit';
            }
        }
    }

    return ['dotted' => $imports[1], 'bare' => $bare];
}

/** @return list<array{offset: int, alias: string, imported: bool, args: list<string>, target: string, tab: ?string}> */
function editCalls(string $source, ?array $names = null): array
{
    $names ??= macroNames($source);
    $calls = [];
    $collect = static function (int $offset, int $open, string $alias, bool $imported) use (&$calls, $source): void {
        $close = closing($source, $open);
        if ($close < 0) {
            return;
        }
        $args = splitArguments(substr($source, $open + 1, $close - $open - 1));
        $tab = (string) preg_replace('/^tab\s*=\s*/', '', $args[1] ?? '');
        $calls[] = [
            'offset' => $offset,
            'alias' => $alias,
            'imported' => $imported,
            'args' => $args,
            'target' => $args[0],
            'tab' => preg_match('/^([\'"])(.+)\1$/', $tab, $literal) ? $literal[2] : null,
        ];
    };
    preg_match_all('/(?<![\w.])(\w+)\.edit\s*\(/', $source, $dotted, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
    foreach ($dotted as $call) {
        $collect($call[0][1], $call[0][1] + strlen($call[0][0]) - 1, $call[1][0] . '.edit', in_array($call[1][0], $names['dotted'], true));
    }
    foreach ($names['bare'] as $name) {
        preg_match_all('/(?<![\w.])' . preg_quote($name, '/') . '\s*\(/', $source, $bare, PREG_OFFSET_CAPTURE);
        foreach ($bare[0] as [$text, $offset]) {
            $collect($offset, $offset + strlen($text) - 1, $name, true);
        }
    }
    usort($calls, static fn (array $a, array $b): int => $a['offset'] <=> $b['offset']);

    return $calls;
}

/** A pencil is rendered here: a macro call, or edit_link used directly. */
function rendersPencilItself(string $text): bool
{
    return (bool) preg_match('/(?<![\w.])(?:\w+\.)?edit(?:List)?\s*\(|edit_link/', $text);
}

/** A heading or include that has a pencil, or prints the one its caller passes in. */
function hasPencil(string $text): bool
{
    return rendersPencilItself($text) || str_contains($text, 'title_suffix');
}

/** Templates a template renders: itself, its includes and its page-level parents, at any depth. */
function reachable(string $template, array $templates, array &$seen = []): array
{
    if (isset($seen[$template]) || ! isset($templates[$template])) {
        return $seen;
    }
    $seen[$template] = true;
    $parent = extendsOf($templates[$template]);
    if ($parent !== null && ! isLayout($parent)) {
        reachable($parent, $templates, $seen);
    }
    foreach (includesOf($templates[$template]) as $include) {
        foreach ($include['names'] as $name) {
            reachable($name, $templates, $seen);
        }
    }

    return $seen;
}

/** True when a template, or anything it renders, shows a pencil. */
function rendersPencil(string $template, array $templates): bool
{
    foreach (array_keys(reachable($template, $templates)) as $name) {
        if ($name !== 'macros.twig' && rendersPencilItself($templates[$name])) {
            return true;
        }
    }

    return false;
}

function isOpenTag(string $source, int $offset, string $tag): bool
{
    $before = substr($source, 0, $offset);
    preg_match_all('/<' . $tag . '[\s>]/i', $before, $opens, PREG_OFFSET_CAPTURE);
    if ($opens[0] === []) {
        return false;
    }
    $close = strripos($before, '</' . $tag . '>');

    return $close === false || end($opens[0])[1] > $close;
}

/** The tab most of the given fields live on, among those a page shows. */
function likelyTab(array $type, array $fields): ?string
{
    $count = [];
    foreach ($fields as $field) {
        $group = $type['fieldGroups'][$field] ?? null;
        if ($group !== null && ! in_array(slugOf($group), NOT_RENDERED_TABS, true)) {
            $count[$group] = ($count[$group] ?? 0) + 1;
        }
    }
    arsort($count);

    return array_key_first($count);
}

/** Fields of the known record variables that $text reads: [[variable, slug, [fields]]…]. */
function fieldsRead(string $text, array $variables, array $types): array
{
    $result = [];
    foreach ($variables as $variable => $slugs) {
        if (! preg_match_all('/(?<![\w.])' . preg_quote($variable, '/') . '\.(\w+)/', $text, $reads)) {
            continue;
        }
        foreach (array_keys($slugs) as $slug) {
            $fields = array_values(array_unique(array_filter($reads[1], static fn (string $f): bool => isset($types[$slug]['fieldGroups'][$f]))));
            if ($fields !== []) {
                $result[] = [$variable, $slug, $fields];
            }
        }
    }

    return $result;
}

/** @return list<array{template: string, line: int, kind: string, covered: bool, suggestion: string}> */
function worklist(array $templates, array $env, array $types): array
{
    $items = [];
    foreach ($templates as $template => $source) {
        if ($template === 'macros.twig' || $env[$template] === []) {
            continue;
        }
        foreach (NO_DATABASE_FOLDERS as $folder) {
            if (str_starts_with($template, $folder)) {
                continue 2;
            }
        }
        $names = macroNames($source);
        $alias = $names['dotted'][0] ?? ($names['bare'] !== [] ? null : 'macros');
        $fileCalls = editCalls($source);
        // List items never get a pencil of their own.
        $loops = outerLoops($source);
        $inLoop = static function (int $offset) use ($loops): bool {
            foreach ($loops as $loop) {
                if ($offset > $loop['offset'] && $offset < $loop['end']) {
                    return true;
                }
            }

            return false;
        };
        $sameTabInFile = static function (string $variable, string $slug, array $fields) use ($fileCalls, $types): bool {
            $groups = $types[$slug]['groups'];
            $wanted = likelyTab($types[$slug], $fields) ?? $groups[0];
            foreach ($fileCalls as $fileCall) {
                if ($fileCall['target'] !== $variable) {
                    continue;
                }
                $opened = $fileCall['tab'] ?? $groups[0];
                if (count($groups) < 2 || slugOf($opened) === slugOf($wanted)) {
                    return true;
                }
            }

            return false;
        };
        $call = static function (string $variable, string $slug, array $fields) use ($alias, $names, $types): string {
            $tab = count($types[$slug]['groups']) > 1 ? likelyTab($types[$slug], $fields) : null;
            $arguments = $variable . ($tab !== null ? ", '{$tab}'" : '');

            return ($alias !== null ? $alias . '.edit' : $names['bare'][0]) . '(' . $arguments . ')';
        };

        // A section fed from a record's fields through an include.
        foreach (includesOf($source) as $include) {
            if ($inLoop($include['offset'])) {
                continue;
            }
            foreach (fieldsRead($include['args'], $env[$template], $types) as [$variable, $slug, $fields]) {
                $items[] = [
                    'template' => $template,
                    'line' => lineOf($source, $include['offset']),
                    'kind' => 'section',
                    'covered' => hasPencil($include['args']) || $sameTabInFile($variable, $slug, $fields),
                    'suggestion' => 'title_suffix: ' . $call($variable, $slug, $fields) . '  (' . basename((string) ($include['names'][0] ?? '')) . ')',
                ];
                break;
            }
        }

        // A heading printing a record's fields.
        preg_match_all('/<h([1-3])\b[^>]*>(.*?)<\/h\1>/is', $source, $headings, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
        foreach ($headings as $heading) {
            if ($inLoop($heading[0][1])) {
                continue;
            }
            foreach (fieldsRead($heading[2][0], $env[$template], $types) as [$variable, $slug, $fields]) {
                $items[] = [
                    'template' => $template,
                    'line' => lineOf($source, $heading[0][1]),
                    'kind' => 'heading',
                    'covered' => hasPencil($heading[2][0]) || $sameTabInFile($variable, $slug, $fields),
                    'suggestion' => $call($variable, $slug, $fields) . '  after the text inside <h' . $heading[1][0] . '>',
                ];
                break;
            }
        }
    }

    return $items;
}

/** @return list<array{offset: int, end: int, head: string, body: string}> outermost {% for %} loops */
function outerLoops(string $source): array
{
    preg_match_all('/\{%-?\s*(for\b[^%]*|endfor\s*)-?%\}/', $source, $tags, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
    $loops = [];
    $stack = [];
    foreach ($tags as $tag) {
        if (! str_starts_with($tag[1][0], 'endfor')) {
            $stack[] = $tag;

            continue;
        }
        $open = array_pop($stack);
        if ($open !== null && $stack === []) {
            $start = $open[0][1] + strlen($open[0][0]);
            $loops[] = ['offset' => $open[0][1], 'end' => $tag[0][1], 'head' => trim($open[1][0]), 'body' => substr($source, $start, $tag[0][1] - $start)];
        }
    }

    return $loops;
}

/** What a loop repeats for every item: a macro call, or a template that renders one. */
function repeatedPencil(array $loop, array $names, array $templates): ?string
{
    // A call limited to one round is fine, and so is a loop whose items are whole sections.
    $body = (string) preg_replace('/\{%-?\s*if\s+loop\.(?:first|last)\s*-?%\}.*?\{%-?\s*endif\s*-?%\}/s', '', $loop['body']);
    if (preg_match('/^(?:\s|\{%.*?%\})*<section\b/is', $body)) {
        return null;
    }
    foreach (editCalls($body, $names) as $call) {
        return $call['alias'] . '(' . implode(', ', $call['args']) . ')';
    }
    foreach (includesOf($body) as $include) {
        foreach ($include['names'] as $name) {
            foreach (array_keys(reachable($name, $templates)) as $reached) {
                if (editCalls($templates[$reached]) !== []) {
                    return "{$reached} (included for every item)";
                }
            }
        }
    }

    return null;
}

const EDIT_MACRO = '/\{%-?\s*macro\s+edit\s*\(.*?\{%-?\s*endmacro\s*-?%\}/s';
const LIST_MACRO = '/\{#(?:(?!#\}).)*#\}\s*\{%-?\s*macro\s+editList\s*\(.*?\{%-?\s*endmacro\s*-?%\}/s';

function install(string $themeDir, string $example): int
{
    $macros = trim((string) file_get_contents($example));
    $file = "{$themeDir}/macros.twig";
    if (! is_file($file)) {
        file_put_contents($file, $macros . "\n");
        echo "Created {$file} with the edit macros.\n";

        return 0;
    }
    $source = (string) file_get_contents($file);
    preg_match(LIST_MACRO, $macros, $list);
    $edit = trim((string) preg_replace(LIST_MACRO, '', $macros));
    if (! preg_match(EDIT_MACRO, $source, $match, PREG_OFFSET_CAPTURE)) {
        $source = rtrim($source) . "\n\n" . $edit . "\n";
        echo "Added the edit macro to {$file}.\n";
    } elseif (str_contains($match[0][0], 'edit_locale') && str_contains($match[0][0], '|slug')) {
        echo "{$file}: the edit macro already opens the page's locale and a tab — kept as it is.\n";
    } else {
        [$current, $offset] = $match[0];
        $end = $offset + strlen($current);
        // Replace the comment documenting the old macro together with it.
        if (preg_match('/\{#(?:(?!#\}).)*#\}\s*$/s', substr($source, 0, $offset), $comment, PREG_OFFSET_CAPTURE)
            && preg_match('/edit_link|quick edit|pencil/i', $comment[0][0])) {
            $offset = $comment[0][1];
        }
        $source = substr($source, 0, $offset) . $edit . substr($source, $end);
        echo "Upgraded the edit macro in {$file}. Its second parameter is now the tab: review any call that passes a label.\n";
    }
    if (! str_contains($source, 'macro editList')) {
        $source = rtrim($source) . "\n\n" . $list[0] . "\n";
        echo "Added the editList macro to {$file}.\n";
    }
    file_put_contents($file, $source);

    return 0;
}

// -------------------------------------------------------------------------------------------
$config = array_replace_recursive(readYaml('config/bolt/config.yaml'), readYaml('config/bolt/config_local.yaml'));
$theme = $config['theme'] ?? null;
$themeDir = is_string($theme) ? "public/theme/{$theme}" : '';
if ($themeDir === '' || ! is_dir($themeDir)) {
    echo $mode === 'check' ? "FAIL active theme folder not found (config/bolt/config.yaml theme:)\n" : "ERROR: active theme folder not found (config/bolt/config.yaml theme:)\n";
    exit($mode === 'check' ? 0 : 1);
}

if ($mode === 'install') {
    exit(install($themeDir, $macroExample));
}

$types = loadContentTypes();
$templates = loadTemplates($themeDir);
$entries = entryTemplates($types, $config, $templates);
$env = variableTypes($templates, $types, $entries, $config);
$items = worklist($templates, $env, $types);

if ($mode === 'scan') {
    echo "ContentTypes and their editor tabs (the second argument of the macro):\n";
    foreach ($types as $slug => $type) {
        echo '  ', $slug, $type['singleton'] ? ' (singleton)' : '', $type['viewless'] ? ' (viewless)' : '', ': ', implode(', ', $type['groups']), "\n";
    }
    usort($items, static fn (array $a, array $b): int => [$a['template'], $a['line']] <=> [$b['template'], $b['line']]);
    $missing = array_filter($items, static fn (array $item): bool => ! $item['covered']);
    echo "\nPlaces a pencil belongs (", count($missing), ' missing of ', count($items), "). The tab is a guess from the fields the place reads — check it:\n";
    foreach ($showAll ? $items : $missing as $item) {
        printf("  %s:%d  %s  %s  %s\n", "{$themeDir}/{$item['template']}", $item['line'], $item['kind'], $item['covered'] ? 'ok' : 'MISSING', $item['suggestion']);
    }
    exit(0);
}

// check --------------------------------------------------------------------------------------
out('SECTION', 'The edit macro (macros.twig)');
$macroSource = $templates['macros.twig'] ?? '';
if (! preg_match('/\{%-?\s*macro\s+edit\s*\((.*?)\).*?\{%-?\s*endmacro\s*-?%\}/s', $macroSource, $macro)) {
    out('FAIL', 'macros.twig has no `edit` macro — run scripts/scaffold.sh');
    exit(0);
}
str_contains($macro[0], 'edit_link')
    ? out('PASS', 'renders only for editors who may edit the record (edit_link)')
    : out('FAIL', 'the macro does not use edit_link — visitors would see it, or it would link past Bolt\'s permission check');
str_contains($macro[1], 'tab') && str_contains($macro[0], '|slug')
    ? out('PASS', 'opens the tab of the section (#tab|slug)')
    : out('FAIL', 'the macro takes no tab — the editor always opens on the first tab (examples/macro-edit.twig)');
str_contains($macro[0], 'edit_locale')
    ? out('PASS', 'opens the language of the page (edit_locale)')
    : out('FAIL', 'the macro has no ?edit_locale= — the editor opens the default language from a translated page');
str_contains($macro[0], 'aria-label') ? out('PASS', 'has an accessible name') : out('WARN', 'the macro has no aria-label — an emoji is not an accessible name');
str_contains($macro[0], 'print:hidden') ? out('PASS', 'hidden in print') : out('WARN', 'the macro has no print:hidden');

// -------------------------------------------------------------------------------------------
out('SECTION', 'Calls of the macro');
$allCalls = [];
foreach ($templates as $template => $source) {
    if ($template === 'macros.twig') {
        continue;
    }
    foreach (editCalls($source) as $call) {
        $call['template'] = $template;
        $call['line'] = lineOf($source, $call['offset']);
        $call['where'] = "{$themeDir}/{$template}:{$call['line']}";
        $allCalls[] = $call;
    }
}
$callProblems = 0;
foreach ($allCalls as $call) {
    $source = $templates[$call['template']];
    if (! $call['imported']) {
        out('FAIL', "{$call['where']}: {$call['alias']}() without importing macros.twig in this file — macros are not inherited");
        $callProblems++;
    }
    foreach (NO_DATABASE_FOLDERS as $folder) {
        if (str_starts_with($call['template'], $folder)) {
            out('FAIL', "{$call['where']}: a pencil in {$folder} — these templates run without a record, some without a database");
            $callProblems++;
        }
    }
    foreach (['a' => 'link', 'button' => 'button'] as $tag => $label) {
        if (isOpenTag($source, $call['offset'], $tag)) {
            out('FAIL', "{$call['where']}: a pencil inside a {$label} — nested interactive elements are invalid HTML; move it outside and use `relative z-10`");
            $callProblems++;
        }
    }
}
foreach ($templates as $template => $source) {
    preg_match_all('/\{\{-?\s*title_suffix/', $source, $prints, PREG_OFFSET_CAPTURE);
    foreach ($prints[0] as [, $offset]) {
        if (isOpenTag($source, $offset, 'a')) {
            out('FAIL', "{$themeDir}/{$template}:" . lineOf($source, $offset) . ': title_suffix printed inside a link — nested interactive elements are invalid HTML');
            $callProblems++;
        }
    }
}
if ($allCalls === []) {
    out('FAIL', 'the theme never calls the macro — run scripts/edit-links.php scan and apply it');
} elseif ($callProblems === 0) {
    out('PASS', count($allCalls) . ' call(s), each imported and outside links and buttons');
}

// -------------------------------------------------------------------------------------------
out('SECTION', 'Tabs exist on the ContentType');
$anyGroup = [];
foreach ($types as $type) {
    foreach ($type['groups'] as $group) {
        $anyGroup[slugOf($group)] = true;
    }
}
$tabCalls = array_filter($allCalls, static fn (array $call): bool => $call['tab'] !== null);
$tabProblems = 0;
foreach ($tabCalls as $call) {
    $slugs = array_keys($env[$call['template']][$call['target']] ?? []);
    $tab = slugOf($call['tab']);
    if ($slugs === []) {
        $valid = isset($anyGroup[$tab]);
        $known = 'no ContentType has it';
    } else {
        $groups = array_merge(...array_map(static fn (string $slug): array => $types[$slug]['groups'], $slugs));
        $valid = in_array($tab, array_map('slugOf', $groups), true);
        $known = implode(' / ', $slugs) . ' has: ' . implode(', ', $groups);
    }
    if (! $valid) {
        out('FAIL', "{$call['where']}: tab '{$call['tab']}' does not exist ({$known}) — Bolt's editor throws on a hash that matches no tab; an older macro took a label here");
        $tabProblems++;
    }
}
if ($tabProblems === 0) {
    out('PASS', $tabCalls === [] ? 'no call opens a tab' : count($tabCalls) . ' tab link(s), all on existing tabs');
}

// -------------------------------------------------------------------------------------------
out('SECTION', 'Every place an editor would look for one');
$pageProblems = 0;
foreach ($entries as $slug => $entry) {
    foreach (array_unique(array_filter([$entry['record'], $entry['home']])) as $template) {
        if (! rendersPencil($template, $templates)) {
            out('FAIL', "{$themeDir}/{$template}: the {$slug} page has no pencil");
            $pageProblems++;
        }
    }
}
if ($pageProblems === 0) {
    out('PASS', 'every record page and singleton page has a pencil');
}
// One pencil per section: scan lists the sections and headings, this catches the opposite mistake.
$repeats = 0;
foreach ($templates as $template => $source) {
    if ($template === 'macros.twig') {
        continue;
    }
    foreach (outerLoops($source) as $loop) {
        $found = repeatedPencil($loop, macroNames($source), $templates);
        if ($found !== null) {
            out('WARN', "{$themeDir}/{$template}:" . lineOf($source, $loop['offset']) . ": a pencil repeats for every item of `{% {$loop['head']} %}` — {$found}. One per section is enough; put it on the section heading");
            $repeats++;
        }
    }
}
if ($repeats === 0) {
    out('PASS', 'no pencil repeats for every item of a list');
}

$targeted = [];
$untargeted = [];
foreach ($allCalls as $call) {
    foreach (array_keys($env[$call['template']][$call['target']] ?? []) as $slug) {
        if ($call['tab'] === null) {
            $untargeted[$slug] = true;
        } else {
            $targeted[$slug][slugOf($call['tab'])] = true;
        }
    }
}
$printed = [];
foreach ($templates as $template => $source) {
    foreach (fieldsRead($source, $env[$template], $types) as [, $slug, $fields]) {
        foreach ($fields as $field) {
            $printed[$slug][$types[$slug]['fieldGroups'][$field]] = true;
        }
    }
}
$tabGaps = 0;
foreach ($printed as $slug => $groups) {
    if (! isset($targeted[$slug]) && ! isset($untargeted[$slug])) {
        // A list reaches the editor through its items' pages or one editList; a singleton has nothing else.
        if ($types[$slug]['singleton']) {
            out('WARN', "{$slug}: shown on the site, but no pencil is known to reach this singleton");
            $tabGaps++;
        }

        continue;
    }
    if (count($types[$slug]['groups']) < 2) {
        continue;
    }
    $firstTab = slugOf($types[$slug]['groups'][0]);
    foreach (array_keys($groups) as $group) {
        $tab = slugOf($group);
        $covered = isset($targeted[$slug][$tab]) || ($tab === $firstTab && isset($untargeted[$slug]));
        if ($covered || in_array($tab, NOT_RENDERED_TABS, true) || ! in_array($group, $types[$slug]['renderedGroups'], true)) {
            continue;
        }
        out('WARN', "{$slug}: tab '{$group}' is shown on the site, but no pencil opens it");
        $tabGaps++;
    }
}
if ($tabGaps === 0) {
    out('PASS', 'every singleton shown on the site is reachable, and every tab it shows has a pencil');
}
