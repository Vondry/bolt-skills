<?php

declare(strict_types=1);

/*
 * bolt-legal-cz: validates the `contact:` and `legal:` blocks of theme.yaml against
 * references/requirements.cs.md. Called by verify.sh from the Bolt project root:
 *
 *   php check-legal.php <theme.yaml> [--draft] [--ares] [--today=YYYY-MM-DD]
 *
 * Prints one finding per line — "FAIL: …", "WARN: …", "OK: …" — then the profile for the live
 * check: "PROFILE: <operator> <consumers 0|1> <online_contracts 0|1> <reviews 0|1>",
 * "EXPECT_ICO: …" and "EXPECT_NAME: …".
 * --draft reports [DOPLNIT] placeholders as warnings instead of failures.
 * --ares compares the data with the public register (needs internet access).
 */

require getcwd() . '/vendor/autoload.php';
require __DIR__ . '/legal-lib.php';

use Symfony\Component\Yaml\Yaml;

$file = $argv[1] ?? '';
$draft = in_array('--draft', $argv, true);
$withAres = in_array('--ares', $argv, true);
$today = date('Y-m-d');
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--today=')) {
        $today = substr($arg, 8);
    }
}

$fail = static function (string $message): void { echo "FAIL: $message\n"; };
$warn = static function (string $message): void { echo "WARN: $message\n"; };
$ok = static function (string $message): void { echo "OK: $message\n"; };

$theme = Yaml::parseFile($file);
$contact = is_array($theme['contact'] ?? null) ? $theme['contact'] : [];
$legal = $theme['legal'] ?? null;

$filled = static fn ($value): bool => is_string($value) && trim($value) !== '' || is_int($value)
    || is_array($value) && isset($value['cs']) && trim((string) $value['cs']) !== '';
$isPlaceholder = static fn ($value): bool => is_string($value) && str_contains($value, '[DOPLNIT');

// Placeholders anywhere in the data (AG-02)
$placeholders = [];
$walk = static function ($value, string $path) use (&$walk, &$placeholders): void {
    if (is_array($value)) {
        foreach ($value as $key => $item) {
            $walk($item, "$path.$key");
        }
    } elseif (is_string($value) && str_contains($value, '[DOPLNIT')) {
        $placeholders[] = $path;
    }
};
$walk($contact, 'contact');
$walk($legal, 'legal');
if ($placeholders) {
    $message = count($placeholders) . ' placeholder(s) left: ' . implode(', ', array_slice($placeholders, 0, 8)) . (count($placeholders) > 8 ? ', …' : '');
    $draft ? $warn($message) : $fail($message . ' (use --draft while the operator is still answering)');
} else {
    $ok('no [DOPLNIT] placeholders');
}

// ID-01–ID-03: identity in contact:
foreach (['name' => 'ID-01 name', 'address' => 'ID-02 registered seat', 'ico' => 'ID-03 IČO'] as $key => $label) {
    if (! $filled($contact[$key] ?? null)) {
        $fail("contact.$key is empty — $label is mandatory on a business website (§ 435 OZ)");
    }
}
$ico = (string) ($contact['ico'] ?? '');
if ($ico !== '' && ! $isPlaceholder($ico)) {
    if (is_int($contact['ico'])) {
        $warn("contact.ico is a YAML number — quote it ('$ico'), an IČO starting with 0 would lose the zero");
    }
    legal_ico_valid($ico) ? $ok("IČO $ico has a valid check digit (ID-03)") : $fail("contact.ico '$ico' is not a valid IČO (8 digits, check digit) (ID-03)");
}

if (! is_array($legal)) {
    $fail("$file has no legal: block (run scaffold.sh with the intake answers)");
    echo "PROFILE: unknown 0 0 0\n";
    exit(0);
}

// OP — who operates the website
$operator = $legal['operator'] ?? null;
if (! in_array($operator, ['trade', 'company', 'profession', 'other'], true)) {
    $fail('legal.operator must be trade | company | profession | other — ask the operator (AG-01)');
    $operator = 'unknown';
} else {
    $ok("operator: $operator");
}

// ID-04 — registration entry
$registry = is_array($legal['registry'] ?? null) ? $legal['registry'] : [];
if ($operator === 'company') {
    foreach (['court' => 'registry court', 'section' => 'section (oddíl)', 'insert' => 'file number (vložka)'] as $key => $label) {
        if (! $filled($registry[$key] ?? null)) {
            $fail("legal.registry.$key is empty — a company states the Commercial Register entry: $label (ID-04)");
        }
    }
} elseif (in_array($operator, ['profession', 'other'], true) && ! $filled($registry['text'] ?? null)) {
    $fail('legal.registry.text is empty — state the register or chamber list the operator is entered in, with Czech text (ID-04)');
}

// ID-07 — DIČ
$dic = $legal['dic'] ?? null;
if ($filled($dic) && ! $isPlaceholder($dic) && ! preg_match('/^CZ\d{8,10}$/', (string) $dic)) {
    $fail("legal.dic '$dic' is not a Czech VAT ID (CZ + 8–10 digits) (ID-07)");
}

// SP — consumers
$consumers = $legal['consumers'] ?? null;
if (! is_bool($consumers)) {
    $fail('legal.consumers must be true or false — ask whether the operator sells to consumers (SP)');
    $consumers = false;
} elseif ($consumers) {
    $adr = is_array($legal['adr'] ?? null) ? $legal['adr'] : [];
    if (! $filled($adr['name'] ?? null) || ! preg_match('~^https?://~', (string) ($adr['url'] ?? ''))) {
        $fail('legal.adr needs name (with Czech text) and url of the ADR body — usually Česká obchodní inspekce, https://coi.gov.cz (SP-01, § 14 ZOS)');
    } else {
        $ok('ADR body set (SP-01)');
    }
    if (! $filled($legal['complaints_url'] ?? null)) {
        $warn('legal.complaints_url is empty — tell consumers where and how to file a complaint (SP-03, § 13 ZOS)');
    }
} else {
    $ok('B2B only — consumer information (SP) not required');
}

// EC — contracts concluded on the website
$online = $legal['online_contracts'] ?? null;
if (! is_bool($online)) {
    $fail('legal.online_contracts must be true or false (EC)');
    $online = false;
} elseif ($online) {
    if (! $consumers) {
        $warn('online_contracts without consumers — the EC requirements protect consumers; confirm the shop sells to businesses only');
    }
    if (! $filled($legal['terms_url'] ?? null)) {
        $fail('legal.terms_url is empty — an online shop needs its terms and conditions page (EC-01, EC-02)');
    }
    if (! $filled($legal['complaints_url'] ?? null) && $consumers) {
        $fail('legal.complaints_url is empty — an online shop needs its complaints procedure (SP-03)');
    }
    if (! $filled($legal['withdrawal_url'] ?? null) && $consumers) {
        $today >= '2027-01-01'
            ? $fail('legal.withdrawal_url is empty — the „Odstoupit od smlouvy“ button is mandatory since 1. 1. 2027 (EC-05, § 1830a OZ)')
            : $warn('legal.withdrawal_url is empty — the „Odstoupit od smlouvy“ button and form are mandatory from 1. 1. 2027 (EC-05, § 1830a OZ)');
    }
    if (($legal['microenterprise'] ?? true) === false) {
        $warn('not a microenterprise — the European Accessibility Act applies: WCAG 2.1 AA and accessibility information in the terms (EC-06, manual)');
    }
}

// SP-06 — reviews
$reviews = $legal['reviews']['shown'] ?? false;
if (! is_bool($reviews)) {
    $fail('legal.reviews.shown must be true or false (SP-06)');
    $reviews = false;
}

// REG-01 — regulated profession
$regulated = $legal['regulated'] ?? null;
if ($operator === 'profession' && empty($regulated)) {
    $warn('legal.regulated is empty — a regulated profession should name its chamber, title and rules (REG-01)');
} elseif (is_array($regulated) && (! $filled($regulated['chamber'] ?? null) || ! $filled($regulated['title'] ?? null))) {
    $fail('legal.regulated needs chamber and title with Czech text (REG-01)');
}

// WB-01 — whistleblowing
if (($legal['whistleblowing'] ?? false) === true && ! $filled($legal['whistleblowing_url'] ?? null)) {
    $fail('legal.whistleblowing is true but whistleblowing_url is empty — publish the internal reporting information (WB-01, § 9 odst. 2 zákona č. 171/2023 Sb.)');
}

// AG-04 — the privacy policy controller must match the identity
$controller = $theme['privacy']['controllers'][0] ?? null;
if (is_array($controller)) {
    $drift = [];
    foreach (['name', 'ico', 'address'] as $key) {
        if (isset($controller[$key], $contact[$key]) && ! $isPlaceholder($controller[$key]) && legal_squash((string) $controller[$key]) !== legal_squash((string) $contact[$key])) {
            $drift[] = $key;
        }
    }
    $drift ? $fail('privacy.controllers[0] differs from contact: in ' . implode(', ', $drift) . ' — one identity on the whole site (AG-04)')
        : $ok('privacy policy controller matches contact: (AG-04)');
}

// ID-06 — compare with ARES
if ($withAres && legal_ico_valid($ico)) {
    try {
        $ares = legal_ares($ico);
        if ($ares === null) {
            $fail("ARES does not know IČO $ico (ID-06)");
        } else {
            $ok("ARES: {$ares['name']}, {$ares['address']}");
            $name = (string) ($contact['name'] ?? '');
            str_contains(legal_squash($name), legal_squash($ares['name']))
                ? $ok('name matches ARES (ID-01)')
                : $fail("contact.name '$name' does not contain the registered name '{$ares['name']}' (ID-01, ID-06)");
            legal_address_matches((string) ($contact['address'] ?? ''), $ares)
                ? $ok('seat matches ARES (ID-02)')
                : $fail("contact.address does not match the registered seat '{$ares['address']}' (ID-02, ID-06)");
            // VR covers every public register; only the Commercial Register makes a "company".
            // A spolek, nadace, ústav … states its own register as text (operator other).
            $registryText = $registry['text'] ?? '';
            $registryText = is_array($registryText) ? (string) ($registryText['cs'] ?? reset($registryText)) : (string) $registryText;
            if ($ares['commercial'] && $operator !== 'company') {
                $fail("the subject is in the Commercial Register — set legal.operator: company and court {$ares['court']}, section {$ares['section']}, insert {$ares['insert']} (ID-04)");
            } elseif ($ares['vr'] && ! $ares['commercial'] && $operator === 'company') {
                $fail("legal.operator is company, but ARES lists the subject in the {$ares['register']}, not the Commercial Register — set legal.operator: other and registry.text: { cs: 'Zapsáno {$ares['register_in']}: {$ares['court']}, oddíl {$ares['section']}, vložka {$ares['insert']}' } (ID-04)");
            } elseif (! $ares['vr'] && $operator === 'company') {
                $fail('legal.operator is company, but ARES has no Commercial Register entry (ID-04, ID-09)');
            } elseif ($ares['commercial'] && ($ares['section'] !== null || $ares['insert'] !== null)) {
                (legal_squash((string) ($registry['section'] ?? '')) === legal_squash((string) $ares['section'])
                    && legal_squash((string) ($registry['insert'] ?? '')) === legal_squash((string) $ares['insert']))
                    ? $ok("Commercial Register entry matches ({$ares['section']} {$ares['insert']})")
                    : $fail("legal.registry differs from ARES: {$ares['court']}, oddíl {$ares['section']}, vložka {$ares['insert']} (ID-04, ID-06)");
            } elseif ($ares['vr'] && $ares['insert'] !== null) {
                preg_match('~\b' . preg_quote((string) $ares['section'], '~') . '\b.{0,20}?\b' . preg_quote($ares['insert'], '~') . '\b~iu', $registryText)
                    ? $ok("{$ares['register']} entry matches ({$ares['section']} {$ares['insert']})")
                    : $fail("legal.registry.text does not name the {$ares['register']} entry from ARES: 'Zapsáno {$ares['register_in']}: {$ares['court']}, oddíl {$ares['section']}, vložka {$ares['insert']}' (ID-04, ID-06)");
            }
            if ($operator === 'trade' && ! $ares['rzp']) {
                $warn('ARES has no active Trade Register entry — check that the trade licence is still valid (ID-04)');
            }
            if ($ares['vat'] && ! $filled($dic)) {
                $warn("the operator is a VAT payer ({$ares['dic']}) — show legal.dic (ID-07)");
            } elseif ($filled($dic) && $ares['dic'] !== null && $dic !== $ares['dic']) {
                $fail("legal.dic $dic differs from ARES {$ares['dic']} (ID-06)");
            }
        }
    } catch (RuntimeException $exception) {
        $warn('ARES not reachable (' . $exception->getMessage() . ') — register data not compared (ID-06)');
    }
}

printf("PROFILE: %s %d %d %d\n", $operator, $consumers ? 1 : 0, $online ? 1 : 0, $reviews ? 1 : 0);
echo 'EXPECT_ICO: ' . ($isPlaceholder($ico) ? '' : $ico) . "\n";
echo 'EXPECT_NAME: ' . ($isPlaceholder($contact['name'] ?? '') ? '' : (string) ($contact['name'] ?? '')) . "\n";
