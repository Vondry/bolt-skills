<?php

declare(strict_types=1);

/*
 * Live check of Bolt's search page: php check-search.php --base-url=URL [--locales=cs,en] [--term=WORD]
 *
 * Bolt serves /search and /{_locale}/search on every site. This proves the theme's page works:
 * (a result is a page linked more often than on the page for a term without matches — not the menu)
 *   1. /search renders the search template (a form with a `searchTerm` field), HTTP 200.
 *   2. A real term returns results: the term is the longest word of a page's <h1> (from sitemap.xml,
 *      else the homepage links), and the results must link back to that page. --term skips the guess.
 *   3. A term without matches still answers 200.
 *   4. Markup in the term (Bolt's HTML cleaner keeps <b>, <img> …) is not printed unescaped.
 *   5. Every other locale: /{locale}/search answers 200, its form submits to /{locale}/search (not
 *      the default locale's /search) and the results link to /{locale}/ pages.
 * The first locale of --locales is the default (served without a prefix). Exit code: failures.
 */

$options = getopt('', ['base-url:', 'locales::', 'term::']);
$base = rtrim((string) ($options['base-url'] ?? ''), '/');
if ($base === '') {
    fwrite(STDERR, "Usage: php check-search.php --base-url=URL [--locales=cs,en] [--term=WORD]\n");
    exit(2);
}
$locales = array_values(array_filter(explode(',', (string) ($options['locales'] ?? ''))));
$secondary = array_slice($locales, 1);
$failures = 0;

$fail = function (string $message) use (&$failures): void {
    echo "  ✗ FAILED: $message\n";
    $failures++;
};
$ok = static fn (string $message) => print("  ✓ $message\n");

/** @return array{0:int,1:string} status and body; redirects are not followed */
$get = static function (string $path) use ($base): array {
    $context = stream_context_create(['http' => ['ignore_errors' => true, 'follow_location' => 0, 'timeout' => 30, 'header' => "User-Agent: bolt-skills-check-search\r\n"]]);
    $body = @file_get_contents($base . $path, false, $context);
    $status = 0;
    foreach ($http_response_header ?? [] as $line) {
        if (preg_match('~^HTTP/\S+\s+(\d{3})~', $line, $m)) {
            $status = (int) $m[1];
        }
    }

    return [$status, $body === false ? '' : $body];
};

$searchUrl = static fn (string $prefix, string $term): string => $prefix . '/search?searchTerm=' . rawurlencode($term);

/** Paths of the links in a page, on this site only; $counted gives path => number of links */
$hrefs = static function (string $html, bool $counted = false) use ($base): array {
    preg_match_all('~href="([^"#]+)~i', $html, $m);
    $host = parse_url($base, PHP_URL_HOST);
    $paths = [];
    foreach ($m[1] as $href) {
        $href = html_entity_decode($href);
        $hrefHost = parse_url($href, PHP_URL_HOST);
        if ($hrefHost !== null && $hrefHost !== $host) {
            continue;
        }
        $paths[] = rtrim((string) parse_url($href, PHP_URL_PATH), '/') ?: '/';
    }

    return $counted ? array_count_values($paths) : array_values(array_unique($paths));
};

/** Pages linked more often than on the page for a term without matches: the results, not the menu */
$resultLinks = static function (string $html, array $chrome) use ($hrefs): array {
    return array_keys(array_filter($hrefs($html, true), static fn (int $n, string $p): bool => $n > ($chrome[$p] ?? 0), ARRAY_FILTER_USE_BOTH));
};

/** The action of the form that holds the searchTerm field, or null */
$formAction = static function (string $html): ?string {
    if (! preg_match_all('~<form\b[^>]*>.*?</form>~is', $html, $forms)) {
        return null;
    }
    foreach ($forms[0] as $form) {
        if (preg_match('~name="searchTerm"~i', $form)) {
            return preg_match('~<form\b[^>]*\baction="([^"]*)"~i', $form, $a)
                ? (string) parse_url(html_entity_decode($a[1]), PHP_URL_PATH)
                : '';
        }
    }

    return null;
};

// 1. The page itself
[$status, $html] = $get('/search');
if ($status !== 200) {
    $fail("/search answers HTTP $status — the search template is missing or broken (search_results_template)");
} elseif ($formAction($html) === null) {
    $fail('/search answers 200 but has no form with a searchTerm field — Bolt fell back to the listing template?');
} else {
    $ok('/search renders the search page (HTTP 200, search form present)');
}

// 2. A term that must return results. A result is a page linked more often than on the page for a
// term without matches, so menu and footer links do not count — a result that is also in the menu does.
[, $noMatch] = $get($searchUrl('', 'zzqxv' . random_int(1000, 9999)));
$chrome = $hrefs($noMatch, true);
$term = isset($options['term']) ? (string) $options['term'] : '';
$target = null;
$attempts = [];
if ($term !== '') {
    [$status, $html] = $get($searchUrl('', $term));
    $attempts[] = "„{$term}“ → HTTP $status";
    if ($status === 200 && $resultLinks($html, $chrome) !== []) {
        $target = '';
    }
} else {
    [, $sitemap] = $get('/sitemap.xml');
    // A sitemap index (tomvondracek/bolt-sitemap) lists child sitemaps: read the first ones.
    if (stripos($sitemap, '<sitemapindex') !== false && preg_match_all('~<loc>\s*([^<\s]+)\s*</loc>~i', $sitemap, $children)) {
        $sitemap = '';
        foreach (array_slice($children[1], 0, 5) as $child) {
            $sitemap .= $get((string) parse_url(html_entity_decode($child), PHP_URL_PATH))[1];
        }
    }
    preg_match_all('~<loc>\s*([^<\s]+)\s*</loc>~i', $sitemap, $m);
    $candidates = array_map(static fn (string $url): string => rtrim((string) parse_url(html_entity_decode($url), PHP_URL_PATH), '/') ?: '/', $m[1]);
    if ($candidates === []) {
        [, $home] = $get('/');
        $candidates = array_filter($hrefs($home), static fn (string $p): bool => ! preg_match('~\.(css|js|png|jpe?g|webp|svg|ico|xml|txt|pdf)$|^/(theme|files|thumbs|bolt)/~i', $p));
    }
    $roots = array_merge(['/'], array_map(static fn (string $l): string => "/$l", $locales));
    $candidates = array_values(array_filter(array_unique($candidates), static fn (string $p): bool => ! in_array($p, $roots, true) && ! str_contains($p, '/search')));

    foreach (array_slice($candidates, 0, 8) as $path) {
        [$status, $page] = $get($path);
        if ($status !== 200 || ! preg_match('~<h1\b[^>]*>(.*?)</h1>~is', $page, $h)) {
            continue;
        }
        $words = preg_split('~[^\p{L}\p{N}]+~u', html_entity_decode(strip_tags($h[1])), -1, PREG_SPLIT_NO_EMPTY) ?: [];
        usort($words, static fn (string $a, string $b): int => mb_strlen($b) <=> mb_strlen($a));
        $word = $words[0] ?? '';
        if (mb_strlen($word) < 4) {
            continue;
        }
        [$status, $results] = $get($searchUrl('', $word));
        // A singleton's record|link is /<contenttype>/<slug>, under its page /<contenttype>
        $found = $status === 200 && array_filter($resultLinks($results, $chrome), static fn (string $p): bool => $p === $path || str_starts_with($p, $path . '/')) !== [];
        $attempts[] = "„{$word}“ (h1 of $path) → HTTP $status" . ($status === 200 ? ($found ? ', page found' : ', page not in the results') : '');
        if ($found) {
            [$term, $target] = [$word, $path];
            break;
        }
    }
}
if ($target === null) {
    $fail('no search returned results with HTTP 200' . ($attempts === [] ? ' (no page with an <h1> found in sitemap.xml or the homepage links; pass --term=WORD)' : ': ' . implode('; ', $attempts)));
} else {
    $ok("„{$term}“ returns results with HTTP 200" . ($target !== '' ? " and finds $target" : ''));
}

// 3. No matches
[$status] = $get($searchUrl('', 'zzqxv' . random_int(1000, 9999)));
$status === 200 ? $ok('a term without matches answers HTTP 200') : $fail("a term without matches answers HTTP $status");

// 4. Markup in the term
[$status, $html] = $get($searchUrl('', '<b>zzmarkup</b>'));
if ($status !== 200) {
    echo "  - markup check skipped (HTTP $status)\n";
} elseif (str_contains($html, '<b>zzmarkup</b>')) {
    $fail('the search term is printed unescaped (<b>zzmarkup</b> appears as markup) — escape it with |e before passing it to __()');
} else {
    $ok('markup in the term is escaped');
}

// 5. Other locales
foreach ($secondary as $locale) {
    [$status, $html] = $get("/$locale/search");
    if ($status !== 200) {
        $fail("/$locale/search answers HTTP $status");
        continue;
    }
    $action = $formAction($html);
    if ($action === null || ! str_starts_with($action, "/$locale/search")) {
        $fail("the search form on /$locale/search submits to " . ($action === null ? '(no form)' : ($action === '' ? 'the current URL without a path' : $action)) . " — results would show in the default locale; use the current route (pages/search/components/search-form.twig)");
    } else {
        $ok("/$locale/search answers 200 and its form submits to $action");
    }
    if ($term !== '' && $target !== null) {
        [$status, $html] = $get($searchUrl("/$locale", $term));
        $localized = array_filter($hrefs($html), static fn (string $p): bool => str_starts_with($p, "/$locale/"));
        if ($status !== 200) {
            $fail("/$locale/search?searchTerm=$term answers HTTP $status");
        } elseif ($target !== '' && ! in_array("/$locale$target", $localized, true)) {
            echo "  ! WARNING: /$locale/search?searchTerm=$term (HTTP 200) does not link to /$locale$target — check that results stay in /$locale/ (a translated slug is fine)\n";
        } else {
            $ok("/$locale/search?searchTerm=$term returns results in /$locale/");
        }
    }
}

exit($failures);
