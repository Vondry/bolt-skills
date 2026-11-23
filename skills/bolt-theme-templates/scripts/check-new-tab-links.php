<?php

declare(strict_types=1);

/*
 * bolt-theme-templates: links that open a new tab (verify.sh step 12).
 *
 * Every link that opens a new tab carries rel="noopener noreferrer". The one exception is the
 * author credit to tvondracek.cz: rel="noopener" only, so the portfolio sees the referring site.
 *
 * Checked:
 *   - <a target="_blank"> in the theme's templates;
 *   - <a target="{{ … }}"> whose target is set by Twig (a macro or variable that may print _blank);
 *   - Twig hashes with target: '_blank' (attributes passed to a component: attrs: { target: '_blank', rel: '…' });
 *   - <a target="_blank"> in the translation catalogs (translations/*.xlf, CDATA or escaped).
 * Twig comments are skipped. A rel set by Twig (rel="{{ … }}") is not checked.
 *
 * Usage: php check-new-tab-links.php <theme dir> [<translations dir>]
 * Prints one line per wrong link (file:line: reason) and exits 1 when there is one.
 */

if ($argc < 2 || !is_dir($argv[1])) {
    fwrite(STDERR, "Usage: php check-new-tab-links.php <theme dir> [<translations dir>]\n");
    exit(2);
}

/** @return list<string> */
function files(string $dir, string $extension): array
{
    $found = [];
    if (!is_dir($dir)) {
        return $found;
    }
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS));
    foreach ($iterator as $file) {
        $path = $file->getPathname();
        if ($file->isFile() && str_ends_with($path, $extension) && !str_contains($path, '/node_modules/')) {
            $found[] = $path;
        }
    }
    sort($found);

    return $found;
}

function lineOf(string $source, int $offset): int
{
    return substr_count($source, "\n", 0, $offset) + 1;
}

/** Why the rel value is wrong for this link, or null when it is right. */
function relProblem(?string $rel, string $context): ?string
{
    if ($rel !== null && str_contains($rel, '{{')) {
        return null;
    }
    $tokens = $rel === null ? [] : preg_split('/\s+/', strtolower(trim($rel)), -1, PREG_SPLIT_NO_EMPTY);
    $noopener = in_array('noopener', $tokens, true);
    $noreferrer = in_array('noreferrer', $tokens, true);
    if (str_contains($context, 'tvondracek.cz')) {
        return $noopener && !$noreferrer ? null : 'the tvondracek.cz credit needs rel="noopener" without noreferrer';
    }

    return $noopener && $noreferrer ? null : 'without rel="noopener noreferrer"';
}

/** @return list<string> */
function checkAnchors(string $file, string $source, bool $dynamicTargets): array
{
    $problems = [];
    preg_match_all('/<a\b((?:\{\{.*?\}\}|\{%.*?%\}|[^>])*)>/s', $source, $tags, PREG_OFFSET_CAPTURE);
    foreach ($tags[1] as [$tag, $offset]) {
        if (!preg_match('/\btarget\s*=\s*(["\'])(.*?)\1/s', $tag, $target)) {
            continue;
        }
        if ($target[2] === '_blank') {
            $what = 'target="_blank"';
        } elseif ($dynamicTargets && str_contains($target[2], '{{')) {
            $what = 'target set by Twig (may print _blank)';
        } else {
            continue;
        }
        $rel = preg_match('/\brel\s*=\s*(["\'])(.*?)\1/s', $tag, $m) ? $m[2] : null;
        $problem = relProblem($rel, $tag);
        if ($problem !== null) {
            $problems[] = sprintf('%s:%d: %s', $file, lineOf($source, $offset), str_starts_with($problem, 'without') ? "$what $problem" : $problem);
        }
    }

    return $problems;
}

/** @return list<string> */
function checkHashes(string $file, string $source): array
{
    $problems = [];
    preg_match_all('/\{[^{}]*\btarget["\']?\s*:\s*(["\'])_blank\1[^{}]*\}/s', $source, $hashes, PREG_OFFSET_CAPTURE);
    foreach ($hashes[0] as [$hash, $offset]) {
        $rel = preg_match('/\brel["\']?\s*:\s*(["\'])(.*?)\1/s', $hash, $m) ? $m[2] : null;
        $problem = relProblem($rel, $hash);
        if ($problem !== null) {
            $problems[] = sprintf('%s:%d: %s', $file, lineOf($source, $offset), str_starts_with($problem, 'without') ? "target: '_blank' without rel: 'noopener noreferrer'" : $problem);
        }
    }

    return $problems;
}

$problems = [];

foreach (files($argv[1], '.twig') as $file) {
    // Drop Twig comments but keep their line breaks, so line numbers stay right.
    $source = preg_replace_callback('/\{#.*?#\}/s', static fn (array $m): string => preg_replace('/[^\n]/', ' ', $m[0]), (string) file_get_contents($file));
    array_push($problems, ...checkAnchors($file, $source, true), ...checkHashes($file, $source));
}

foreach (files($argv[2] ?? '', '.xlf') as $file) {
    // Links in a catalog are either in CDATA or escaped (&lt;a …&gt;); entities never span lines.
    $source = html_entity_decode((string) file_get_contents($file), ENT_QUOTES | ENT_XML1, 'UTF-8');
    array_push($problems, ...checkAnchors($file, $source, false));
}

foreach ($problems as $problem) {
    echo $problem, "\n";
}

exit($problems === [] ? 0 : 1);
