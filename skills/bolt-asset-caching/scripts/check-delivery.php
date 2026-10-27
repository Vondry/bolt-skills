<?php

declare(strict_types=1);

/*
 * End-to-end delivery check for images of a running Bolt CMS site.
 *
 * Crawls the site, collects every image URL the pages reference (/thumbs/…, /files/…, theme images)
 * and requests each one three times: a first request (may generate the thumbnail), a second one
 * (must come straight from disk) and a conditional one with the ETag / Last-Modified of the second
 * (must answer 304). Fails when a thumbnail or upload is still served by PHP on the second request
 * or lacks ETag, Last-Modified, a max-age or the 304.
 *
 * usage: php check-delivery.php --base-url=URL [--fpm-log=PATH] [--max-pages=200]
 *                               [--alias=example.com,www.example.com] [--json=PATH] [--details]
 *
 *   --base-url   the running site; use Apache with the project's .htaccess files (scripts/serve-apache.sh)
 *                or production — `symfony serve` and PHP's built-in server ignore .htaccess
 *   --fpm-log    PHP-FPM access log written with access.format = "%{HTTP_X_PROBE_ID}e …" (serve-apache.sh
 *                sets it up): every request carries an X-Probe-Id header, so a probe id in the log means
 *                PHP answered. Without it, a response without ETag and Accept-Ranges counts as PHP.
 *   --alias      other host names of the site (absolute URLs to them are checked against --base-url)
 */

$options = getopt('', ['base-url:', 'fpm-log:', 'max-pages:', 'alias:', 'json:', 'details']);
if (empty($options['base-url'])) {
    fwrite(STDERR, "usage: php check-delivery.php --base-url=URL [--fpm-log=PATH] [--max-pages=200] [--alias=host,…] [--json=PATH] [--details]\n");
    exit(2);
}

$base = rtrim($options['base-url'], '/');
$baseParts = parse_url($base);
$baseHost = $baseParts['host'] . (isset($baseParts['port']) ? ':' . $baseParts['port'] : '');
$localHosts = array_filter(array_merge([$baseHost], explode(',', $options['alias'] ?? '')));
$maxPages = (int) ($options['max-pages'] ?? 200);
$fpmLog = $options['fpm-log'] ?? null;
$details = isset($options['details']);

// A local Apache answers plain HTTP; tell the root .htaccess HTTPS redirect that a TLS proxy is in front.
$extraHeaders = in_array($baseParts['host'], ['127.0.0.1', 'localhost', '::1'], true) ? ['X-Forwarded-Proto: https'] : [];

const IMAGE_EXT = '/\.(jpe?g|png|gif|webp|avif|svg|ico)$/i';
const SKIP_PAGE = '#^/(bolt|api|_profiler|_wdt|thumbs|files|theme|assets|bundles|bolt-public|login|logout)(/|$)#';

$probeCounter = 0;

/** @return array{probe: string, status: int, headers: array<string, string>, body: string} */
function fetch(string $url, array $headers = [], bool $follow = false): array
{
    global $probeCounter, $extraHeaders;
    $probe = 'probe' . (++$probeCounter);
    $responseHeaders = [];
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => $follow,
        CURLOPT_MAXREDIRS => 5,
        CURLOPT_TIMEOUT => 120,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_USERAGENT => 'bolt-asset-caching/check-delivery',
        CURLOPT_HTTPHEADER => array_merge($extraHeaders, $headers, ['X-Probe-Id: ' . $probe]),
        CURLOPT_HEADERFUNCTION => static function ($ch, string $line) use (&$responseHeaders): int {
            if (preg_match('/^HTTP\//', $line)) {
                $responseHeaders = []; // a redirect starts a new header block
            } elseif (str_contains($line, ':')) {
                [$name, $value] = explode(':', $line, 2);
                $responseHeaders[strtolower(trim($name))] = trim($value);
            }

            return strlen($line);
        },
    ]);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    return ['probe' => $probe, 'status' => $status, 'headers' => $responseHeaders, 'body' => is_string($body) ? $body : ''];
}

/** Resolve $url against $context and return a local URL (percent-encoded like a browser does), or null. */
function localize(string $url, string $context): ?string
{
    global $base, $localHosts;
    $url = html_entity_decode(trim($url));
    if ($url === '' || preg_match('/^(data|mailto|tel|javascript):|^#/i', $url)) {
        return null;
    }
    if (str_starts_with($url, '//')) {
        $url = 'https:' . $url;
    }
    if (preg_match('#^https?://#i', $url)) {
        $parts = parse_url($url);
        $host = ($parts['host'] ?? '') . (isset($parts['port']) ? ':' . $parts['port'] : '');
        if (! in_array($host, $localHosts, true)) {
            return null;
        }
        $path = $parts['path'] ?? '/';
        $query = $parts['query'] ?? '';
    } else {
        [$url, $query] = array_pad(explode('?', explode('#', $url)[0], 2), 2, '');
        if (str_starts_with($url, '/')) {
            $path = $url;
        } else {
            $contextPath = parse_url($context, PHP_URL_PATH) ?: '/';
            $path = substr($contextPath, 0, strrpos($contextPath, '/') + 1) . $url;
        }
    }
    // Resolve ./ and ../ segments.
    $segments = [];
    foreach (explode('/', $path) as $segment) {
        if ($segment === '..') {
            array_pop($segments);
        } elseif ($segment !== '.') {
            $segments[] = $segment;
        }
    }
    $path = implode('/', $segments) ?: '/';
    $encode = static fn (string $s): string => preg_replace_callback('/[^\x21-\x7E]/', static fn ($m) => rawurlencode($m[0]), $s);

    return $base . $encode($path) . ($query !== '' ? '?' . $encode($query) : '');
}

function pathOf(string $url): string
{
    return (string) parse_url($url, PHP_URL_PATH);
}

// ---------------------------------------------------------------------------------------------
// 1. Crawl
// ---------------------------------------------------------------------------------------------
$queue = ['/'];
$seen = ['/' => true];
$sitemap = fetch($base . '/sitemap.xml', [], true);
// A sitemap index (tomvondracek/bolt-sitemap) lists child sitemaps, read from the checked host.
if ($sitemap['status'] === 200 && stripos($sitemap['body'], '<sitemapindex') !== false && preg_match_all('#<loc>\s*([^<]+?)\s*</loc>#', $sitemap['body'], $children)) {
    $body = '';
    foreach (array_slice($children[1], 0, 20) as $child) {
        $childSitemap = fetch($base . pathOf(html_entity_decode($child)), [], true);
        $body .= $childSitemap['status'] === 200 ? $childSitemap['body'] : '';
    }
    $sitemap['body'] = $body;
}
if ($sitemap['status'] === 200 && preg_match_all('#<loc>\s*([^<]+?)\s*</loc>#', $sitemap['body'], $m)) {
    foreach ($m[1] as $loc) {
        $u = localize($loc, $base . '/');
        $p = $u ? pathOf($u) : null;
        if ($p && ! isset($seen[$p]) && ! preg_match(SKIP_PAGE, $p)) {
            $seen[$p] = true;
            $queue[] = $p;
        }
    }
}

$pages = [];
$images = [];
$cssSeen = [];
$addImage = static function (?string $u, string $foundOn) use (&$images): void {
    if ($u && preg_match(IMAGE_EXT, pathOf($u)) && ! isset($images[$u])) {
        $images[$u] = $foundOn;
    }
};
$cssUrls = static fn (string $css): array => preg_match_all('/url\(\s*[\'"]?([^\'")]+)[\'"]?\s*\)/', $css, $mm) ? $mm[1] : [];

while ($queue && count($pages) < $maxPages) {
    $path = array_shift($queue);
    $url = $base . $path;
    $r = fetch($url, [], true);
    $pages[$path] = $r['status'];
    if ($r['status'] !== 200 || ! str_contains($r['headers']['content-type'] ?? '', 'html')) {
        continue;
    }
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="UTF-8">' . $r['body'], LIBXML_NOERROR | LIBXML_NOWARNING);
    $xpath = new DOMXPath($doc);

    foreach ($xpath->query('//a[@href]') as $a) {
        $u = localize($a->getAttribute('href'), $url);
        if (! $u) {
            continue;
        }
        $p = pathOf($u);
        if (preg_match(IMAGE_EXT, $p)) {
            $addImage($u, $path);
        } elseif (! isset($seen[$p]) && ! preg_match(SKIP_PAGE, $p) && ! preg_match('/\.\w{2,5}$/', $p)) {
            $seen[$p] = true;
            $queue[] = $p;
        }
    }
    foreach ($xpath->query('//*[@src or @data-src or @poster]') as $el) {
        foreach (['src', 'data-src', 'poster'] as $attr) {
            if ($el->hasAttribute($attr)) {
                $addImage(localize($el->getAttribute($attr), $url), $path);
            }
        }
    }
    foreach ($xpath->query('//*[@srcset or @data-srcset or @imagesrcset]') as $el) {
        foreach (['srcset', 'data-srcset', 'imagesrcset'] as $attr) {
            foreach (array_filter(array_map('trim', explode(',', $el->getAttribute($attr)))) as $candidate) {
                $addImage(localize(explode(' ', $candidate)[0], $url), $path);
            }
        }
    }
    foreach ($xpath->query('//link[@href]') as $link) {
        $rel = strtolower($link->getAttribute('rel'));
        if (str_contains($rel, 'stylesheet')) {
            $cssUrl = localize($link->getAttribute('href'), $url);
            if ($cssUrl && ! isset($cssSeen[$cssUrl])) {
                $cssSeen[$cssUrl] = true;
                $css = fetch($cssUrl, [], true);
                foreach ($css['status'] === 200 ? $cssUrls($css['body']) : [] as $ref) {
                    $addImage(localize($ref, $cssUrl), $path);
                }
            }
        } elseif (str_contains($rel, 'icon') || $link->getAttribute('as') === 'image') {
            $addImage(localize($link->getAttribute('href'), $url), $path);
        }
    }
    foreach ($xpath->query('//meta[@property="og:image" or @name="twitter:image"]') as $meta) {
        $addImage(localize($meta->getAttribute('content'), $url), $path);
    }
    foreach ($xpath->query('//@style | //style') as $node) {
        foreach ($cssUrls($node->nodeValue) as $ref) {
            $addImage(localize($ref, $url), $path);
        }
    }
}

// ---------------------------------------------------------------------------------------------
// 2. Request every image three times
// ---------------------------------------------------------------------------------------------
ksort($images);
$results = [];
foreach ($images as $url => $foundOn) {
    $r1 = fetch($url);
    $r2 = fetch($url);
    $conditional = array_filter([
        isset($r2['headers']['etag']) ? 'If-None-Match: ' . $r2['headers']['etag'] : null,
        isset($r2['headers']['last-modified']) ? 'If-Modified-Since: ' . $r2['headers']['last-modified'] : null,
    ]);
    $r3 = $conditional ? fetch($url, $conditional) : null;
    $p = pathOf($url);
    $results[] = [
        'url' => $url,
        'category' => str_starts_with($p, '/thumbs/') ? 'thumbs' : (str_starts_with($p, '/files/') ? 'files' : 'other'),
        'found_on' => $foundOn,
        'r1' => ['probe' => $r1['probe'], 'status' => $r1['status'], 'headers' => $r1['headers'], 'sha1' => sha1($r1['body'])],
        'r2' => ['probe' => $r2['probe'], 'status' => $r2['status'], 'headers' => $r2['headers'], 'sha1' => sha1($r2['body'])],
        'r3' => $r3 ? ['probe' => $r3['probe'], 'status' => $r3['status']] : null,
    ];
}

// Which responses came from PHP?
$phpProbes = null;
if ($fpmLog !== null) {
    usleep(500000);
    $phpProbes = [];
    foreach (file($fpmLog, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        $phpProbes[strtok($line, ' ')] = true;
    }
}
$servedByPhp = static function (array $response) use ($phpProbes): bool {
    if ($phpProbes !== null) {
        return isset($phpProbes[$response['probe']]);
    }

    // Apache and Nginx send ETag and Accept-Ranges for static files; Bolt's thumbnail responses send neither.
    return ! isset($response['headers']['etag']) && ! isset($response['headers']['accept-ranges']);
};
$maxAge = static fn (array $headers): ?int => preg_match('/max-age=(\d+)/', $headers['cache-control'] ?? '', $mm) ? (int) $mm[1] : null;

// ---------------------------------------------------------------------------------------------
// 3. Report
// ---------------------------------------------------------------------------------------------
$nonOkPages = array_filter($pages, static fn (int $s): bool => $s !== 200);
echo "Pages crawled: " . count($pages) . (count($pages) >= $maxPages ? " (limit --max-pages=$maxPages reached)" : '') . ', not 200: ' . count($nonOkPages) . "\n";
// Their images were not collected, so name them: a timeout or a 5xx hides part of the site.
foreach (array_slice($nonOkPages, 0, $details ? null : 10, true) as $path => $status) {
    echo '               ' . ($status === 0 ? 'no response' : "HTTP $status") . "  $path\n";
}
if (! $details && count($nonOkPages) > 10) {
    echo '               … ' . (count($nonOkPages) - 10) . " more (--details lists all)\n";
}
echo 'Image URLs:    ' . count($results) . "\n";
echo 'PHP detection: ' . ($phpProbes !== null ? "PHP-FPM access log ($fpmLog)" : 'heuristic (no ETag and no Accept-Ranges = PHP); pass --fpm-log for an exact result') . "\n";

// Uploads without ETag and without a Server header: `symfony serve` or PHP's built-in server.
$uploads = array_filter($results, static fn ($r) => $r['category'] === 'files' && $r['r2']['status'] === 200);
if ($uploads && ! array_filter($uploads, static fn ($r) => isset($r['r2']['headers']['etag']) || isset($r['r2']['headers']['server']))) {
    echo "WARNING:       uploads come without ETag and Server header — this looks like `symfony serve` or PHP's built-in\n"
        . "               server, which ignore .htaccess. Check against Apache (scripts/serve-apache.sh), Nginx or production.\n";
}
echo "\n";

printf("%-8s %5s %8s %9s %8s %9s %5s %8s %8s %5s\n", 'category', 'URLs', '1st PHP', '2nd disk', '2nd PHP', 'broken', 'ETag', 'LastMod', 'max-age', '304');
$problems = [];
$broken = [];
foreach (['thumbs', 'files', 'other'] as $category) {
    $rows = array_values(array_filter($results, static fn ($r) => $r['category'] === $category));
    if (! $rows) {
        continue;
    }
    $count = ['firstPhp' => 0, 'disk' => 0, 'php' => 0, 'broken' => 0, 'etag' => 0, 'lastmod' => 0, 'maxage' => 0, '304' => 0];
    foreach ($rows as $r) {
        $count['firstPhp'] += (int) $servedByPhp($r['r1']);
        if ($r['r2']['status'] !== 200) {
            $count['broken']++;
            $broken[] = $r;
            continue;
        }
        $php = $servedByPhp($r['r2']);
        $count[$php ? 'php' : 'disk']++;
        $h = $r['r2']['headers'];
        $count['etag'] += (int) isset($h['etag']);
        $count['lastmod'] += (int) isset($h['last-modified']);
        $count['maxage'] += (int) ($maxAge($h) > 0);
        $count['304'] += (int) ($r['r3'] && $r['r3']['status'] === 304);

        $issues = array_filter([
            $php ? 'served by PHP' : null,
            isset($h['etag']) ? null : 'no ETag',
            isset($h['last-modified']) ? null : 'no Last-Modified',
            $maxAge($h) > 0 ? null : 'no max-age',
            $r['r3'] && $r['r3']['status'] === 304 ? null : 'no 304 on revalidation',
            $r['r1']['sha1'] === $r['r2']['sha1'] ? null : '1st and 2nd response differ',
        ]);
        if ($issues) {
            $problems[] = ['row' => $r, 'issues' => $issues];
        }
    }
    printf("%-8s %5d %8d %9d %8d %9d %5d %8d %8d %5d\n", $category, count($rows), $count['firstPhp'], $count['disk'], $count['php'], $count['broken'], $count['etag'], $count['lastmod'], $count['maxage'], $count['304']);
}

$relative = static fn (string $url): string => substr($url, strlen($base));
$failures = array_filter($problems, static fn ($p) => $p['row']['category'] !== 'other');
$warnings = array_filter($problems, static fn ($p) => $p['row']['category'] === 'other');

if ($problems) {
    echo "\nNot served from disk with ETag, Last-Modified, max-age and 304 on the 2nd request:\n";
    $byIssue = [];
    foreach ($problems as $p) {
        $byIssue[implode(', ', $p['issues'])][] = $p['row'];
    }
    foreach ($byIssue as $issue => $rows) {
        echo sprintf("  %s — %d URL(s)%s\n", $issue, count($rows), $rows[0]['category'] === 'other' && count(array_unique(array_column($rows, 'category'))) === 1 ? ' (theme / other, warning)' : '');
        foreach (array_slice($rows, 0, $details ? PHP_INT_MAX : 5) as $row) {
            echo '    ' . $relative($row['url']) . '  [Cache-Control: ' . ($row['r2']['headers']['cache-control'] ?? '-') . "]\n";
        }
        if (! $details && count($rows) > 5) {
            echo '    … ' . (count($rows) - 5) . " more (--details lists all)\n";
        }
    }
}
if ($broken) {
    echo "\nImage URLs that do not answer 200 (broken references in the pages, not a caching problem):\n";
    foreach (array_slice($broken, 0, $details ? PHP_INT_MAX : 10) as $row) {
        echo '  ' . $row['r2']['status'] . ' ' . $relative($row['url']) . '  (on ' . $row['found_on'] . ")\n";
    }
    if (! $details && count($broken) > 10) {
        echo '  … ' . (count($broken) - 10) . " more (--details lists all)\n";
    }
}

$thumbsByPhp = array_filter($failures, static fn ($p) => $p['row']['category'] === 'thumbs' && in_array('served by PHP', $p['issues'], true));
if ($thumbsByPhp) {
    echo "\nHint: thumbnails are still generated by PHP on every request. bolt/core 6.0.1 – 6.1.x save them to\n"
        . "public/thumbs/<w>_<h>_<q>_<fit>_<location>/, a path no thumbnail URL points to (fixed by bolt/core PR #3828).\n"
        . "Also check thumbnails.save_files: true and that public/thumbs/ is writable for PHP.\n";
}
if (array_filter($problems, static fn ($p) => in_array('no max-age', $p['issues'], true))) {
    echo "\nHint: images without max-age — add the mod_expires block of examples/htaccess_mod_expires.conf to public/.htaccess,\n"
        . "or an ExpiresByType line for the content type it is missing (Nginx: the expires rules of examples/nginx_static.conf).\n";
}

if (isset($options['json'])) {
    file_put_contents($options['json'], json_encode(['pages' => $pages, 'images' => $results], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
}

echo "\n" . ($failures ? 'FAILED: ' . count($failures) . ' thumbnail / upload URL(s) not delivered from disk with full cache headers.' : 'PASSED: every thumbnail and upload is served from disk with ETag, Last-Modified, max-age and 304.')
    . ($warnings ? ' ' . count($warnings) . ' theme / other image(s) with warnings.' : '') . "\n";
exit($failures ? 1 : 0);
