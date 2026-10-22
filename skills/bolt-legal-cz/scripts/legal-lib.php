<?php

declare(strict_types=1);

/*
 * bolt-legal-cz: helpers shared by check-legal.php (theme.yaml data) and check-site.php (live
 * website). No dependencies besides PHP itself, so check-site.php runs outside a Bolt project.
 */

const LEGAL_ARES = 'https://ares.gov.cz/ekonomicke-subjekty-v-be/rest';
const LEGAL_USER_AGENT = 'bolt-legal-cz/1.0 (+https://github.com/Vondry/bolt-skills)';

// Registry court codes used by ARES (spisovaZnacka.soud) → name as printed on documents.
const LEGAL_COURTS = [
    'MSPH' => 'Městský soud v Praze',
    'KSCB' => 'Krajský soud v Českých Budějovicích',
    'KSPL' => 'Krajský soud v Plzni',
    'KSUL' => 'Krajský soud v Ústí nad Labem',
    'KSHK' => 'Krajský soud v Hradci Králové',
    'KSBR' => 'Krajský soud v Brně',
    'KSOS' => 'Krajský soud v Ostravě',
];

// ARES reports every public register (veřejný rejstřík) as one source, VR. The section (oddíl) of
// the spisová značka tells which register it is: the Commercial Register uses A, B, C, Dr, Pr …,
// the others have their own letters. Name as in a sentence: „Zapsáno ve spolkovém rejstříku: …“.
const LEGAL_PUBLIC_REGISTERS = [
    'L' => ['spolkový rejstřík', 've spolkovém rejstříku'],
    'N' => ['nadační rejstřík', 'v nadačním rejstříku'],
    'NF' => ['nadační rejstřík', 'v nadačním rejstříku'],
    'O' => ['rejstřík obecně prospěšných společností', 'v rejstříku obecně prospěšných společností'],
    'U' => ['rejstřík ústavů', 'v rejstříku ústavů'],
    'S' => ['rejstřík společenství vlastníků jednotek', 'v rejstříku společenství vlastníků jednotek'],
];
const LEGAL_COMMERCIAL_REGISTER = ['obchodní rejstřík', 'v obchodním rejstříku'];

/** ID-04: [name, locative] of the public register a section (oddíl) belongs to. */
function legal_public_register(?string $section): array
{
    return LEGAL_PUBLIC_REGISTERS[strtoupper((string) $section)] ?? LEGAL_COMMERCIAL_REGISTER;
}

/** ID-03: 8 digits, weights 8…2, check digit (11 - sum mod 11) mod 10. */
function legal_ico_valid(string $ico): bool
{
    if (! preg_match('/^\d{8}$/', $ico)) {
        return false;
    }
    $sum = 0;
    for ($i = 0; $i < 7; $i++) {
        $sum += (int) $ico[$i] * (8 - $i);
    }

    return (11 - $sum % 11) % 10 === (int) $ico[7];
}

/** Lower-case letters and digits only — "Example, s.r.o." and "EXAMPLE s. r. o." compare equal. */
function legal_squash(string $text): string
{
    return preg_replace('/[^\p{L}\p{N}]+/u', '', mb_strtolower($text)) ?? '';
}

/**
 * GET a URL. Returns [status, body, final URL]; status 0 when the request failed.
 *
 * @return array{0: int, 1: string, 2: string}
 */
function legal_http_get(string $url, int $timeout = 15, string $accept = 'text/html,application/xhtml+xml'): array
{
    $context = stream_context_create(['http' => [
        'method' => 'GET',
        'timeout' => $timeout,
        'follow_location' => 1,
        'max_redirects' => 5,
        'ignore_errors' => true,
        'header' => "User-Agent: " . LEGAL_USER_AGENT . "\r\nAccept: $accept\r\nAccept-Language: cs,en;q=0.5\r\n",
    ]]);
    $body = @file_get_contents($url, false, $context);
    $headers = function_exists('http_get_last_response_headers') ? (http_get_last_response_headers() ?? []) : ($http_response_header ?? []);
    $status = 0;
    $final = $url;
    foreach ($headers as $header) {
        if (preg_match('~^HTTP/\S+\s+(\d{3})~', $header, $match)) {
            $status = (int) $match[1];
        } elseif (preg_match('~^Location:\s*(\S+)~i', $header, $match)) {
            $final = legal_absolute_url($match[1], $final);
        }
    }

    return [$body === false ? 0 : $status, $body === false ? '' : $body, $final];
}

function legal_absolute_url(string $href, string $base): string
{
    if (preg_match('~^https?://~i', $href)) {
        return $href;
    }
    $parts = parse_url($base);
    $origin = ($parts['scheme'] ?? 'https') . '://' . ($parts['host'] ?? '') . (isset($parts['port']) ? ':' . $parts['port'] : '');
    if (str_starts_with($href, '//')) {
        return ($parts['scheme'] ?? 'https') . ':' . $href;
    }
    if (str_starts_with($href, '/')) {
        return $origin . $href;
    }
    $dir = preg_replace('~/[^/]*$~', '/', $parts['path'] ?? '/');

    return $origin . $dir . $href;
}

/**
 * Public data of an economic subject from ARES. Returns null when the IČO is unknown, throws
 * RuntimeException when ARES cannot be reached.
 *
 * @return array{name: string, address: string, street: string, number: string, psc: string,
 *               vr: bool, rzp: bool, vat: bool, dic: ?string, court: ?string, section: ?string, insert: ?string}|null
 */
function legal_ares(string $ico): ?array
{
    [$status, $body] = legal_http_get(LEGAL_ARES . "/ekonomicke-subjekty/$ico", 15, 'application/json');
    if ($status === 404) {
        return null;
    }
    $data = json_decode($body, true);
    if ($status !== 200 || ! is_array($data)) {
        throw new RuntimeException("ARES answered HTTP $status");
    }
    $seat = $data['sidlo'] ?? [];
    $registrations = $data['seznamRegistraci'] ?? [];
    $result = [
        'name' => (string) ($data['obchodniJmeno'] ?? ''),
        'address' => (string) ($seat['textovaAdresa'] ?? ''),
        'street' => (string) ($seat['nazevUlice'] ?? $seat['nazevCastiObce'] ?? $seat['nazevObce'] ?? ''),
        'number' => (string) ($seat['cisloDomovni'] ?? ''),
        'psc' => (string) ($seat['psc'] ?? ''),
        'vr' => ($registrations['stavZdrojeVr'] ?? '') === 'AKTIVNI',
        'rzp' => ($registrations['stavZdrojeRzp'] ?? '') === 'AKTIVNI',
        'vat' => ($registrations['stavZdrojeDph'] ?? '') === 'AKTIVNI',
        'dic' => isset($data['dic']) ? (string) $data['dic'] : null,
        'court' => null,
        'section' => null,
        'insert' => null,
        // Which public register (VR covers all of them) and whether it is the Commercial Register.
        'register' => null,
        'register_in' => null,
        'commercial' => false,
    ];
    if ($result['vr']) {
        [$vrStatus, $vrBody] = legal_http_get(LEGAL_ARES . "/ekonomicke-subjekty-vr/$ico", 15, 'application/json');
        $vr = $vrStatus === 200 ? json_decode($vrBody, true) : null;
        foreach ($vr['zaznamy'] ?? [] as $record) {
            if (! ($record['primarniZaznam'] ?? false)) {
                continue;
            }
            foreach ($record['spisovaZnacka'] ?? [] as $mark) {
                if (empty($mark['datumVymazu'])) {
                    $result['court'] = LEGAL_COURTS[$mark['soud'] ?? ''] ?? ($mark['soud'] ?? null);
                    $result['section'] = isset($mark['oddil']) ? (string) $mark['oddil'] : null;
                    $result['insert'] = isset($mark['vlozka']) ? (string) $mark['vlozka'] : null;
                }
            }
        }
        [$result['register'], $result['register_in']] = legal_public_register($result['section']);
        $result['commercial'] = $result['register'] === LEGAL_COMMERCIAL_REGISTER[0];
    }

    return $result;
}

/** ID-02: does an address written on the site name the ARES seat (street or place, house number, PSČ)? */
function legal_address_matches(string $text, array $ares): bool
{
    $digits = preg_replace('/\D+/', '', $text) ?? '';
    $squashed = legal_squash($text);

    return ($ares['psc'] === '' || str_contains($digits, $ares['psc']))
        && ($ares['number'] === '' || preg_match('/(?<!\d)' . preg_quote($ares['number'], '/') . '(?!\d)/', $text) === 1)
        && ($ares['street'] === '' || str_contains($squashed, legal_squash($ares['street'])));
}
