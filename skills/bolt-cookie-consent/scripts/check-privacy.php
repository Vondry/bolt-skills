<?php

declare(strict_types=1);

/*
 * bolt-cookie-consent: validates the `analytics:` and `privacy:` blocks of theme.yaml against
 * references/guidelines.cs.md. Called by verify.sh from the Bolt project root:
 *
 *   php check-privacy.php <theme.yaml> [--draft]
 *
 * Prints one finding per line — "FAIL: …", "WARN: …", "OK: …" — and finally
 * "CATEGORIES: analytics,marketing" (the consent categories in use, empty when none).
 * --draft reports [DOPLNIT] / [OVĚŘIT] placeholders as warnings instead of failures.
 */

require getcwd() . '/vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

$file = $argv[1] ?? '';
$draft = in_array('--draft', $argv, true);

$fail = static function (string $message): void { echo "FAIL: $message\n"; };
$warn = static function (string $message): void { echo "WARN: $message\n"; };
$ok = static function (string $message): void { echo "OK: $message\n"; };

$theme = Yaml::parseFile($file);
$privacy = $theme['privacy'] ?? null;
$analytics = $theme['analytics'] ?? [];

if (! is_array($privacy)) {
    $fail("$file has no privacy: block (run scaffold.sh with the intake answers)");
    echo "CATEGORIES: \n";
    exit(0);
}

$isLocalized = static fn ($value): bool => is_string($value) && trim($value) !== '' || is_array($value) && isset($value['cs']) && trim((string) $value['cs']) !== '';

// Placeholders anywhere in the data (AG-01, DM-02; "Žádný [DOPLNIT] v produkčním buildu")
$placeholders = [];
$walk = static function ($value, string $path) use (&$walk, &$placeholders): void {
    if (is_array($value)) {
        foreach ($value as $key => $item) {
            $walk($item, $path === '' ? (string) $key : "$path.$key");
        }
    } elseif (is_string($value) && preg_match('/\[(DOPLNIT|OVĚŘIT)/u', $value)) {
        $placeholders[] = $path;
    }
};
$walk(['privacy' => $privacy, 'analytics' => $analytics], '');
if ($placeholders) {
    $message = count($placeholders) . ' placeholder(s) left: ' . implode(', ', array_slice($placeholders, 0, 8)) . (count($placeholders) > 8 ? ', …' : '');
    $draft ? $warn($message) : $fail($message . ' (use --draft while the operator is still answering)');
} else {
    $ok('no [DOPLNIT] / [OVĚŘIT] placeholders');
}

// Controllers (čl. 13/1 a; § 435 OZ; AG-02; VAR-*)
$model = $privacy['controller_model'] ?? null;
$controllers = $privacy['controllers'] ?? [];
$controllerIds = array_column($controllers, 'id');
if (! in_array($model, ['single', 'joint', 'separate', 'hybrid'], true)) {
    $fail('privacy.controller_model must be single | joint | separate | hybrid (asked, never guessed — AG-02)');
} elseif ($model === 'single' && count($controllers) !== 1) {
    $fail('controller_model single needs exactly one controller');
} elseif ($model !== 'single' && count($controllers) < 2) {
    $fail("controller_model $model needs two or more controllers");
}
foreach ($controllers as $index => $controller) {
    foreach (['id', 'name', 'address', 'ico', 'registry', 'privacy_email'] as $field) {
        if (empty($controller[$field])) {
            $fail("privacy.controllers.$index.$field is empty (§ 435 OZ, VAR-30)");
        }
    }
}
if (in_array($model, ['joint', 'hybrid'], true)) {
    $joint = $privacy['joint_arrangement'] ?? [];
    if (! $isLocalized($joint['summary'] ?? null) || ! in_array($joint['contact_controller'] ?? null, $controllerIds, true)) {
        $fail('joint controllers need joint_arrangement.summary and a contact_controller from controllers (VAR-11)');
    }
}

// Recipients (čl. 13/1 e, f)
$recipientIds = [];
foreach ($privacy['recipients'] ?? [] as $index => $recipient) {
    $recipientIds[] = $recipient['id'] ?? null;
    if (empty($recipient['name']) || ! in_array($recipient['role'] ?? null, ['processor', 'controller', 'joint_controller'], true)) {
        $fail("privacy.recipients.$index needs name and role processor | controller | joint_controller");
    }
    if (! in_array($recipient['transfer'] ?? null, [null, 'adequacy', 'scc'], true)) {
        $fail("privacy.recipients.$index.transfer must be ~, adequacy or scc");
    }
}

// Purposes (čl. 13/1 c, d; 13/2 a, e)
$purposes = $privacy['purposes'] ?? [];
if (! $purposes) {
    $fail('privacy.purposes is empty — every website processes at least server logs or contact data');
}
$consentPurpose = false;
foreach ($purposes as $index => $purpose) {
    $label = $purpose['id'] ?? $index;
    foreach (['title', 'data', 'retention', 'provision'] as $field) {
        if (! $isLocalized($purpose[$field] ?? null)) {
            $fail("purpose $label: $field missing or without Czech text (CB-23)");
        }
    }
    $basis = $purpose['legal_basis'] ?? '';
    if (! in_array($basis, ['art6_1_a', 'art6_1_b', 'art6_1_c', 'art6_1_f'], true) && ! str_contains((string) $basis, '[DOPLNIT')) {
        $fail("purpose $label: legal_basis must be art6_1_a | art6_1_b | art6_1_c | art6_1_f");
    }
    if ($basis === 'art6_1_f' && ! $isLocalized($purpose['legitimate_interest'] ?? null)) {
        $fail("purpose $label: legitimate interest basis needs the concrete legitimate_interest");
    }
    $consentPurpose = $consentPurpose || $basis === 'art6_1_a';
    foreach ($purpose['controllers'] ?? [] as $id) {
        if (! in_array($id, $controllerIds, true)) {
            $fail("purpose $label: unknown controller '$id'");
        }
    }
    foreach ($purpose['recipients'] ?? [] as $id) {
        if (! in_array($id, $recipientIds, true)) {
            $fail("purpose $label: unknown recipient '$id'");
        }
    }
    $section = $purpose['section'] ?? 'website';
    if ($section !== 'website' && ! in_array($section, $controllerIds, true)) {
        $fail("purpose $label: section must be 'website' or a controller id");
    }
}

// Cookies and similar technologies (INV-01–INV-03, CB-21, CB-23)
$categories = ['necessary', 'preferences', 'analytics', 'marketing', 'third_party'];
$cookies = $privacy['cookies'] ?? [];
$used = [];
foreach ($cookies as $index => $item) {
    $label = $item['name'] ?? "#$index";
    if (! in_array($item['category'] ?? null, $categories, true)) {
        $fail("cookie $label: category must be one of " . implode(', ', $categories) . ' (INV-03: nothing unclassified)');
        continue;
    }
    $used[$item['category']] = true;
    foreach (['purpose', 'provider', 'expiry'] as $field) {
        if (! $isLocalized($item[$field] ?? null)) {
            $fail("cookie $label: $field missing or without Czech text (CB-21, CB-23)");
        }
    }
    if (! in_array($item['party'] ?? null, ['first', 'third'], true)) {
        $fail("cookie $label: party must be first | third");
    }
}
$consentCategories = array_values(array_filter(['preferences', 'analytics', 'marketing', 'third_party'], static fn ($category) => isset($used[$category])));
if (! in_array('bolt-cookie-consent', array_column($cookies, 'name'), true) && $consentCategories) {
    $fail("cookies: the consent record 'bolt-cookie-consent' (necessary, localStorage) is not listed");
}
if ($consentCategories && ! $consentPurpose) {
    $fail('consent categories are used but no purpose has legal_basis art6_1_a');
}

// Trackers must be inventoried, otherwise they never load (and must not be added elsewhere)
$trackerCategories = ['ga4_id' => 'analytics', 'google_ads_id' => 'marketing', 'sklik_id' => 'marketing', 'meta_pixel_id' => 'marketing'];
foreach ($trackerCategories as $key => $category) {
    if (! empty($analytics[$key]) && ! str_contains((string) $analytics[$key], '[') && ! isset($used[$category])) {
        $fail("analytics.$key is set but privacy.cookies has no '$category' items — inventory it (INV-01) or it never loads");
    }
}
if (($analytics['consent_mode'] ?? 'basic') === 'advanced') {
    $warn('analytics.consent_mode is advanced: Google tags load before consent — allowed only as the operator\'s explicit, documented decision (CB-50)');
}

// Consent lifetime (CB-41, DP-05)
$consent = $privacy['consent'] ?? [];
if (($consent['validity_months'] ?? 12) > 12) {
    $warn('consent.validity_months above 12 — ÚOOÚ practice is 12 months (CB-41)');
}
if (($consent['reask_after_reject_months'] ?? 6) < 6) {
    $fail('consent.reask_after_reject_months below 6 — re-asking sooner after a rejection is a dark pattern (DP-05)');
}

// Version and history (PP-06, DM-01)
if (empty($privacy['config_version']) || empty($privacy['effective_date']) || empty($privacy['changelog'])) {
    $fail('config_version, effective_date and changelog are required (PP-06)');
}

if (! array_key_exists('automated_decision_making', $privacy)) {
    $fail('automated_decision_making must be stated explicitly (false or a description, čl. 13/2 f)');
}

$ok(count($controllers) . ' controller(s), ' . count($purposes) . ' purpose(s), ' . count($privacy['recipients'] ?? []) . ' recipient(s), ' . count($cookies) . ' cookie item(s)');
echo 'CATEGORIES: ' . implode(',', $consentCategories) . "\n";
