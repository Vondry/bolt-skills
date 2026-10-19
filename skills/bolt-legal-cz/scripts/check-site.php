<?php

declare(strict_types=1);

/*
 * bolt-legal-cz: checks a running website — any website, Bolt or not — for the legal information
 * in references/requirements.cs.md. Reads the homepage, up to --pages URLs from /sitemap.xml and
 * the homepage's legal links (contact, terms, complaints …), then reports per requirement.
 *
 *   php check-site.php --url=https://www.example.cz [--ico=12345678] [--name="Jan Novák"]
 *       [--operator=trade|company|profession|other] [--consumers | --no-consumers]
 *       [--online-contracts] [--reviews] [--ares] [--pages=15] [--today=YYYY-MM-DD]
 *
 * Without --ico the IČO found on the site is used. --ares (internet) compares name, seat,
 * register entry and VAT status with ARES and derives the operator type. Without --consumers /
 * --no-consumers the consumer checks (SP) report warnings only.
 * Prints "FAIL: …", "WARN: …", "OK: …" lines; exits 1 when anything failed.
 */

require __DIR__ . '/legal-lib.php';

$options = ['url' => '', 'ico' => '', 'name' => '', 'operator' => '', 'pages' => '15', 'today' => date('Y-m-d')];
$consumers = null;
$online = false;
$reviewsShown = false;
$withAres = false;
foreach (array_slice($argv, 1) as $arg) {
    if (preg_match('/^--(url|ico|name|operator|pages|today)=(.*)$/s', $arg, $match)) {
        $options[$match[1]] = $match[2];
    } elseif ($arg === '--consumers') {
        $consumers = true;
    } elseif ($arg === '--no-consumers') {
        $consumers = false;
    } elseif ($arg === '--online-contracts') {
        $online = true;
    } elseif ($arg === '--reviews') {
        $reviewsShown = true;
    } elseif ($arg === '--ares') {
        $withAres = true;
    } else {
        fwrite(STDERR, "Unknown argument: $arg\n");
        exit(2);
    }
}
if (! preg_match('~^https?://[^/]+~', $options['url'])) {
    fwrite(STDERR, "Usage: php check-site.php --url=https://www.example.cz [options] (see the header of this file)\n");
    exit(2);
}

$failed = 0;
$warnings = 0;
$fail = static function (string $message) use (&$failed): void { echo "FAIL: $message\n"; $failed++; };
$warn = static function (string $message) use (&$warnings): void { echo "WARN: $message\n"; $warnings++; };
$ok = static function (string $message): void { echo "OK: $message\n"; };

$base = rtrim($options['url'], '/');
$host = parse_url($base, PHP_URL_HOST);
[$status, $homeHtml, $finalUrl] = legal_http_get($base . '/');
if ($status !== 200) {
    $fail("$base/ answered HTTP $status — nothing checked");
    exit(1);
}
$finalHost = parse_url($finalUrl, PHP_URL_HOST) ?: $host;
$origin = preg_replace('~^(https?://[^/]+).*$~', '$1', $finalUrl);

// ---------------------------------------------------------------- pages to read
$sameHost = static fn (string $url): bool => in_array(parse_url($url, PHP_URL_HOST), [$host, $finalHost], true);
$links = static function (string $html, string $pageUrl): array {
    preg_match_all('~<a\b[^>]*\bhref\s*=\s*["\']([^"\'#]+)[^"\']*["\'][^>]*>(.*?)</a>~is', $html, $matches, PREG_SET_ORDER);
    $result = [];
    foreach ($matches as $match) {
        if (preg_match('~^(mailto|tel|javascript):~i', $match[1])) {
            continue;
        }
        $result[] = ['url' => legal_absolute_url(html_entity_decode($match[1]), $pageUrl), 'text' => trim(preg_replace('/\s+/u', ' ', strip_tags($match[2])) ?? '')];
    }

    return $result;
};

// Downloads and images are not pages; legal documents (terms, privacy) name other businesses and
// quote prices and discounts in a contractual context, so some checks skip them.
$files = '~\.(xml|pdf|jpe?g|png|gif|webp|svg|zip|docx?|xlsx?)(\?|$)~i';
$legalDocument = static fn (string $url): bool => preg_match('~podmink|osobnich|udaju|gdpr|zasady|privacy|cookie|smlouv|dpa|reklamac|odstoup|terms~i', $url) === 1;
$legalWords = '~kontakt|o-nas|o-mne|obchodni|podmink|reklama|odstoup|gdpr|osobnich|ochrana|impressum|pravni|vop|terms|contact|about|complaint|withdraw~i';
$queue = [$finalUrl];
foreach ($links($homeHtml, $finalUrl) as $link) {
    if ($sameHost($link['url']) && ! preg_match($files, $link['url']) && preg_match($legalWords, $link['url'] . ' ' . $link['text'])) {
        $queue[] = $link['url'];
    }
}
[$sitemapStatus, $sitemap] = legal_http_get($origin . '/sitemap.xml', 15, 'application/xml,text/xml');
if ($sitemapStatus === 200 && preg_match_all('~<loc>\s*([^<\s]+)\s*</loc>~i', $sitemap, $locs)) {
    foreach ($locs[1] as $loc) {
        $loc = html_entity_decode($loc);
        if ($sameHost($loc) && ! preg_match($files, $loc)) {
            $queue[] = $loc;
        }
    }
}
$queue = array_values(array_unique($queue));
$limit = max(1, (int) $options['pages']);
$legalQueue = array_values(array_filter($queue, static fn ($url) => preg_match($legalWords, $url) === 1));
$queue = array_slice(array_values(array_unique(array_merge([$finalUrl], $legalQueue, $queue))), 0, $limit);

$pages = [];
foreach ($queue as $url) {
    if ($url === $finalUrl) {
        $html = $homeHtml;
    } else {
        [$pageStatus, $html] = legal_http_get($url);
        if ($pageStatus !== 200) {
            continue;
        }
    }
    $clean = preg_replace('~<(script|style|noscript|template)\b.*?</\1>~is', ' ', $html) ?? $html;
    $text = html_entity_decode(strip_tags(str_replace('<', ' <', $clean)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $text = trim(preg_replace('/[\s\x{00A0}]+/u', ' ', $text) ?? '');
    $pages[$url] = ['html' => $html, 'text' => $text];
}
$path = static fn (string $url): string => (parse_url($url, PHP_URL_PATH) ?: '/') . (parse_url($url, PHP_URL_QUERY) ? '?' . parse_url($url, PHP_URL_QUERY) : '');
echo 'INFO: read ' . count($pages) . ' page(s): ' . implode(', ', array_map($path, array_keys($pages))) . "\n";

$pagesMatching = static function (string $pattern, bool $html = false) use ($pages): array {
    return array_keys(array_filter($pages, static fn ($page) => preg_match($pattern, $html ? $page['html'] : $page['text']) === 1));
};
$allText = implode("\n", array_column($pages, 'text'));

// ---------------------------------------------------------------- ID-03 IČO
$icoPattern = '~\bI\.?\s?Č\.?\s?(?:O\.?)?\s*[:.]?\s*((?:\d\s?){7}\d)\b~u';
$found = [];
$icoPages = [];
foreach ($pages as $url => $page) {
    if (preg_match_all($icoPattern, $page['text'], $matches)) {
        foreach ($matches[1] as $value) {
            $value = (string) preg_replace('/\s+/', '', $value);
            $found[$value] = $value;
            $icoPages[$value][] = $url;
        }
    }
}
// Array keys of numeric strings become integers; the values keep the IČO as a string.
$ico = $options['ico'] !== '' ? (string) preg_replace('/\s+/', '', $options['ico']) : (string) (array_values($found)[0] ?? '');
if ($ico === '') {
    $fail('no IČO found on the site (ID-03, § 435 OZ) — state „IČO 12345678“ in the footer of every page');
} else {
    if (! legal_ico_valid($ico)) {
        $fail("IČO $ico has no valid check digit (ID-03)");
    }
    $onPages = count(array_unique($icoPages[$ico] ?? []));
    if ($onPages === 0) {
        $fail("IČO $ico is not on the site" . ($found ? ' (found: ' . implode(', ', $found) . ')' : '') . ' (ID-03)');
    } elseif ($onPages < count($pages)) {
        $warn("IČO $ico on $onPages of " . count($pages) . ' pages — put the identity in the footer so every page has it (ID-05)');
    } else {
        $ok("IČO $ico on every page read (ID-03, ID-05)");
    }
    $others = [];
    foreach ($found as $other) {
        $where = array_filter(array_unique($icoPages[$other]), static fn ($url) => ! $legalDocument($url));
        if ($other !== $ico && $where !== []) {
            $others[] = "$other (" . implode(', ', array_map($path, $where)) . ')';
        }
    }
    if ($others !== []) {
        $warn('other IČO on the site: ' . implode('; ', $others) . ' — a second business, or a leftover from a template? (ID-09)');
    }
}

// ---------------------------------------------------------------- ID-06 ARES
$ares = null;
if ($withAres && legal_ico_valid($ico)) {
    try {
        $ares = legal_ares($ico);
        $ares === null ? $fail("ARES does not know IČO $ico (ID-06)") : $ok("ARES: {$ares['name']}, {$ares['address']}");
    } catch (RuntimeException $exception) {
        $warn('ARES not reachable (' . $exception->getMessage() . ') — register data not compared');
    }
}
$operator = $options['operator'];
if ($operator === '' && $ares !== null) {
    $operator = $ares['vr'] ? 'company' : ($ares['rzp'] ? 'trade' : '');
}

// ---------------------------------------------------------------- ID-01 name, ID-02 seat
$identityPages = $ico !== '' && isset($icoPages[$ico]) ? array_unique($icoPages[$ico]) : array_keys($pages);
$identityText = implode("\n", array_map(static fn ($url) => $pages[$url]['text'], $identityPages));
$name = $options['name'] !== '' ? $options['name'] : ($ares['name'] ?? '');
if ($name !== '') {
    str_contains(legal_squash($identityText), legal_squash($name))
        ? $ok("name „{$name}“ next to the IČO (ID-01)")
        : $fail("name „{$name}“ not found on the pages with the IČO (ID-01, § 435 OZ)");
} else {
    $warn('name not checked — pass --name= or --ares (ID-01)');
}
if ($ares !== null) {
    legal_address_matches($identityText, $ares)
        ? $ok("registered seat {$ares['address']} found (ID-02)")
        : $fail("registered seat „{$ares['address']}“ not found on the pages with the IČO — an old or different address? (ID-02, ID-06)");
} elseif (preg_match('/\b\d{3}\s?\d{2}\b/u', $identityText)) {
    $ok('an address (PSČ) next to the IČO — seat not compared with the register (use --ares) (ID-02)');
} else {
    $fail('no address next to the IČO — state the registered seat (ID-02, § 435 OZ)');
}

// ---------------------------------------------------------------- ID-04 registration entry
$registryPatterns = [
    'trade' => '~živnostensk\w*\s+rejstř|živnostensk\w*\s+úřad|zapsan\w*\s+v\s+živnost~iu',
    'company' => '~obchodní\w*\s+rejstř|spisov\w+\s+značk|oddíl\s+[A-Z][a-z]?\b.{0,20}vložk~iu',
    'profession' => '~komor\w*|seznam\w*\s+advokát|evidenc\w*|registr\w*~iu',
    'other' => '~rejstř\w*|evidenc\w*|komor\w*~iu',
];
if (isset($registryPatterns[$operator])) {
    $pattern = $registryPatterns[$operator];
    preg_match($pattern, $identityText) ? $ok("registration entry stated ($operator) (ID-04)")
        : $fail("no registration entry for operator type „{$operator}“ — " . match ($operator) {
            'trade' => '„Podnikatel zapsaný v živnostenském rejstříku“',
            'company' => '„Zapsáno v obchodním rejstříku: <soud>, oddíl <X>, vložka <N>“',
            default => 'the register or chamber list and number',
        } . ' (ID-04, § 435 OZ)');
} else {
    preg_match('~rejstř|evidenc|spisov\w+\s+značk~iu', $identityText) ? $ok('a registration entry is stated (ID-04)')
        : $fail('no registration entry next to the IČO — živnostenský / obchodní rejstřík or other register (ID-04, § 435 OZ)');
}
if ($ares !== null && $ares['vr'] && $ares['insert'] !== null) {
    preg_match('~vložk\w*\s*(č\.\s*)?' . preg_quote($ares['insert'], '~') . '\b|\b' . preg_quote((string) $ares['section'], '~') . '\s+' . preg_quote($ares['insert'], '~') . '\b~iu', $identityText)
        ? $ok("Commercial Register file {$ares['section']} {$ares['insert']} matches ARES")
        : $fail("Commercial Register file {$ares['section']} {$ares['insert']} ({$ares['court']}) not found (ID-04, ID-06)");
}

// ---------------------------------------------------------------- ID-07 DIČ
if ($ares !== null && $ares['vat']) {
    preg_match('~DIČ\s*:?\s*CZ\s?\d{8,10}~u', $allText) ? $ok('VAT payer shows DIČ (ID-07)')
        : $warn("the operator is a VAT payer ({$ares['dic']}) — show the DIČ (ID-07)");
}

// ---------------------------------------------------------------- GDPR-01 privacy policy link
$privacyLink = false;
$cookieLink = false;
foreach ($links($homeHtml, $finalUrl) as $link) {
    $privacyLink = $privacyLink || preg_match('~osobních\s+údaj|osobnich-udaj|gdpr|soukrom|privacy~iu', $link['text'] . ' ' . $link['url']) === 1;
    $cookieLink = $cookieLink || preg_match('~cookie~i', $link['text'] . ' ' . $link['url']) === 1;
}
$privacyLink ? $ok('homepage links the privacy policy (GDPR-01)')
    : $fail('no link to the privacy policy on the homepage' . ($cookieLink ? ' (only a cookies page — the policy covers all processing, not just cookies)' : '') . ' (GDPR-01 — bolt-cookie-consent)');

// ---------------------------------------------------------------- SP-02 ODR link
$odr = $pagesMatching('~ec\.europa\.eu/consumers/odr|platform\w*\s+(pro\s+)?(řešení\s+sporů\s+)?online|\bODR\s+platform~iu', true);
$odr ? $fail('link or reference to the EU ODR platform (closed on 20. 7. 2025) on ' . implode(', ', array_map($path, $odr)) . ' — remove it (SP-02)')
    : $ok('no reference to the closed EU ODR platform (SP-02)');

// ---------------------------------------------------------------- SP consumers
$consumerCheck = static function (bool $missing, string $message) use ($consumers, $fail, $warn): void {
    if (! $missing || $consumers === false) {
        return;
    }
    $consumers === true ? $fail($message) : $warn($message . ' — applies when the operator sells to consumers');
};
if ($consumers !== false) {
    $adrBody = '~coi\.(gov\.)?cz|česk\w+\s+obchodní\s+inspekc|eru\.(gov\.)?cz|energetick\w+\s+regulační|ctu\.(gov\.)?cz|telekomunikační\s+úřad|finarbitr\.cz|finanční\w*\s+arbitr|cak\.cz|advokátní\s+komor~iu';
    $adrPages = $pagesMatching($adrBody);
    $consumerCheck($adrPages === [], 'no out-of-court dispute resolution body (ADR) on the site — e.g. „Mimosoudní řešení spotřebitelských sporů: Česká obchodní inspekce, coi.gov.cz“ (SP-01, § 14 ZOS)');
    if ($adrPages !== []) {
        preg_match('~(coi|eru|ctu)\.(gov\.)?cz|finarbitr\.cz|cak\.cz~iu', $allText)
            ? $ok('ADR body with its web address (SP-01)')
            : $warn('ADR body named, but its web address is not printed — the law asks for the internet address (SP-01)');
    }
    $consumerCheck($pagesMatching('~reklamac|reklamační|vadného\s+plnění~iu') === [], 'no information on complaints (reklamace) found (SP-03, § 13 ZOS)');

    $net = [];
    foreach ($pages as $url => $page) {
        if (! $legalDocument($url) && preg_match('~\bbez\s+DPH\b~iu', $page['text']) && ! preg_match('~\b(s|vč\.?|včetně)\s+DPH\b~iu', $page['text'])) {
            $net[] = $path($url);
        }
    }
    if ($net !== []) {
        $warn('prices „bez DPH“ only on ' . implode(', ', $net) . ' — consumers must see final prices with VAT (SP-04)');
    }
    $discounts = array_values(array_filter($pagesMatching('~\bslev\w*|zlevněn\w*|původní\s+cen\w*|(?<![\d,.])-\s?\d{1,2}\s?%~iu'), static fn ($url) => ! $legalDocument($url)));
    if ($discounts !== []) {
        $warn('discounts mentioned on ' . implode(', ', array_map($path, array_slice($discounts, 0, 5))) . ' — each must state the lowest price of the 30 days before (SP-05, manual)');
    }
    $lang = preg_match('~<html\b[^>]*\blang\s*=\s*["\']?([a-z]{2})~i', $homeHtml, $langMatch) ? strtolower($langMatch[1]) : '';
    if ($lang !== '' && $lang !== 'cs') {
        $warn("homepage language is „{$lang}“ — consumer information (ADR, complaints, terms) must exist in Czech (SP-07)");
    }
}

// ---------------------------------------------------------------- SP-06 reviews
$reviewPages = array_values(array_unique(array_merge(
    $pagesMatching('~recenz\w*|hodnocení\s+zákazník|napsali\s+o\s+nás|co\s+o\s+nás\s+(říkají|píší)|reference\s+klient|spokojen\w+\s+klient|★|testimonial~iu'),
    // Markup: review / testimonial components, schema.org Review or AggregateRating
    $pagesMatching('~class\s*=\s*["\'][^"\']*\b(review|testimonial|recenz)|"@type"\s*:\s*"(Review|AggregateRating)"|itemtype\s*=\s*["\'][^"\']*schema\.org/(Review|AggregateRating)~i', true)
)));
$noticePages = $pagesMatching('~ověřuj\w*|neověřuj\w*|ověřen\w+\s+(recenz|hodnocen|zákazn)|data-reviews-notice~iu', true);
$withoutNotice = array_values(array_diff($reviewPages, $noticePages));
if ($reviewsShown && ($noticePages === [] || $withoutNotice !== [])) {
    $fail('reviews without a statement whether and how they are verified' . ($withoutNotice ? ' on ' . implode(', ', array_map($path, array_slice($withoutNotice, 0, 5))) : '') . ' (SP-06, § 5a ZOS) — partials/_reviews-notice.twig');
} elseif ($withoutNotice !== [] && $consumers !== false) {
    $warn('reviews or testimonials on ' . implode(', ', array_map($path, array_slice($withoutNotice, 0, 5))) . ' without a statement whether and how they are verified (SP-06, § 5a ZOS)');
} elseif ($reviewPages !== [] || $reviewsShown) {
    $ok('reviews come with a verification statement (SP-06)');
}

// ---------------------------------------------------------------- EC online contracts
$shopPages = $pagesMatching('~do\s+košíku|nákupní\s+košík|\bkošík\b|pokladn[ay]\b|add\s+to\s+cart|checkout~iu');
if (! $online && $shopPages !== []) {
    $warn('looks like an online shop (' . implode(', ', array_map($path, array_slice($shopPages, 0, 3))) . ') — run with --online-contracts (EC)');
}
if ($online) {
    $ecMessage = static function (bool $present, string $message, bool $hard = true) use ($ok, $fail, $warn): void {
        if ($present) {
            $ok($message);
        } else {
            $hard ? $fail("missing: $message") : $warn("missing: $message");
        }
    };
    $ecMessage($pagesMatching('~obchodní\w*\s+podmínk~iu') !== [], 'terms and conditions (EC-01, EC-02)');
    $ecMessage($pagesMatching('~odstoupen\w*\s+od\s+smlouv~iu') !== [], 'information on the 14-day withdrawal right and the model form (EC-04)');
    $button = $pagesMatching('~>\s*Odstoupit\s+od\s+smlouvy\s*<~iu', true) !== [];
    $ecMessage($button, '„Odstoupit od smlouvy“ button or link (EC-05, § 1830a OZ' . ($options['today'] < '2027-01-01' ? ', mandatory from 1. 1. 2027)' : ')'), $options['today'] >= '2027-01-01');
    echo "INFO: check by hand in the checkout: „Objednávka zavazující k platbě“ button (EC-03), price recap with VAT and delivery (EC-01), withdrawal confirmation e-mail (EC-05).\n";
}

echo "SUMMARY: $failed failure(s), $warnings warning(s)\n";
exit($failed > 0 ? 1 : 0);
