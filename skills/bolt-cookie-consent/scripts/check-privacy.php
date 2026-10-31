<?php

declare(strict_types=1);

/*
 * bolt-cookie-consent: validates the privacy data against references/guidelines.cs.md. Called by
 * verify.sh from the Bolt project root:
 *
 *   php check-privacy.php <theme.yaml> [--draft]                        theme.yaml privacy: block
 *   php check-privacy.php <theme.yaml> --contenttype=<slug> [--draft]   a privacy ContentType
 *
 * The data model is the `privacy:` block of theme.yaml, or the published record of a ContentType
 * with a `cookies` collection (SKILL.md, "Data model in a ContentType"). The record is read through
 * the project's kernel and Doctrine, so it needs vendor/ and the database. Tracker IDs stay in
 * the `analytics:` block of theme.yaml in both models.
 *
 * Prints one finding per line — "FAIL: …", "WARN: …", "OK: …" — then
 * "CATEGORIES: analytics,marketing" (the consent categories in use, empty when none) and
 * "INVENTORY: name,name,_ga_*" (every listed name, for the live Set-Cookie comparison).
 * --draft reports [DOPLNIT] / [OVĚŘIT] placeholders as warnings instead of failures.
 */

require getcwd() . '/vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

$file = $argv[1] ?? '';
$draft = in_array('--draft', $argv, true);
$contentType = null;
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--contenttype=')) {
        $contentType = substr($arg, strlen('--contenttype='));
    }
}

$fail = static function (string $message): void { echo "FAIL: $message\n"; };
$warn = static function (string $message): void { echo "WARN: $message\n"; };
$ok = static function (string $message): void { echo "OK: $message\n"; };
$finish = static function (array $categories = [], array $inventory = []): never {
    echo 'CATEGORIES: ' . implode(',', $categories) . "\n";
    echo 'INVENTORY: ' . implode(',', $inventory) . "\n";
    exit(0);
};

/**
 * The `cookies` collection of the published record of $slug, in the shape of theme.yaml
 * privacy.cookies (values in the default locale). Sub-fields may be called `name` or
 * `cookie_name`, `purpose` or `cookie_purpose` (`name` and `label` are reserved inside a set in
 * Bolt, see bolt-contenttypes rule 8). Returns an error message instead when it cannot be read.
 *
 * @return array{cookies: list<array<string, mixed>>}|string
 */
function privacy_record(string $slug): array|string
{
    // The kernel boots outside an HTTP request: Symfony's Request emits deprecations here.
    error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv(getcwd() . '/.env');
    $kernel = new App\Kernel((string) ($_SERVER['APP_ENV'] ?? 'prod'), false);
    $kernel->boot();
    $container = $kernel->getContainer();
    $locale = (string) $container->getParameter('locale');

    $record = $container->get('doctrine')->getManager()
        ->getRepository(Bolt\Entity\Content::class)
        ->findOneBy(['contentType' => $slug, 'status' => 'published'], ['id' => 'DESC']);
    if (! $record instanceof Bolt\Entity\Content) {
        return "no published '$slug' record — create it in the admin (the privacy page and the banner read it)";
    }
    if (! $record->hasField('cookies')) {
        return "the '$slug' record has no cookies collection";
    }

    $read = static function (array $fields, string ...$names) use ($locale): mixed {
        foreach ($names as $name) {
            if (isset($fields[$name]) && $fields[$name] instanceof Bolt\Entity\Field) {
                $fields[$name]->setLocale($locale);
                $value = $fields[$name]->getParsedValue();

                return is_array($value) ? ($value[0] ?? null) : $value;
            }
        }

        return null;
    };

    $cookies = [];
    foreach ($record->getField('cookies')->getValue() as $set) {
        $fields = $set instanceof Bolt\Entity\Field\SetField ? $set->getValue() : [];
        $cookies[] = [
            'name' => trim((string) $read($fields, 'name', 'cookie_name')),
            'technology' => $read($fields, 'technology'),
            'category' => $read($fields, 'category'),
            'provider' => (string) $read($fields, 'provider'),
            'party' => $read($fields, 'party'),
            'purpose' => (string) $read($fields, 'purpose', 'cookie_purpose'),
            'expiry' => (string) $read($fields, 'expiry'),
            'transfer' => $read($fields, 'transfer'),
        ];
    }

    return ['cookies' => $cookies];
}

$theme = Yaml::parseFile($file);
$analytics = $theme['analytics'] ?? [];

if ($contentType !== null) {
    $privacy = privacy_record($contentType);
    if (is_string($privacy)) {
        $fail($privacy);
        $finish();
    }
} else {
    $privacy = $theme['privacy'] ?? null;
    if (! is_array($privacy)) {
        $fail("$file has no privacy: block (run scaffold.sh with the intake answers, or keep the data in a ContentType — SKILL.md)");
        $finish();
    }
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

$controllers = $privacy['controllers'] ?? [];
$purposes = $privacy['purposes'] ?? [];
$consentPurpose = false;

// The theme.yaml model is checked in full here. In the ContentType model controllers, purposes,
// recipients and the change history are fields of the record that the site's own templates render,
// so verify.sh checks their sections on the page instead.
if ($contentType === null) {
    // Controllers (čl. 13/1 a; § 435 OZ; AG-02; VAR-*)
    $model = $privacy['controller_model'] ?? null;
    $controllerIds = array_column($controllers, 'id');
    if (! in_array($model, ['single', 'joint', 'separate', 'hybrid'], true)) {
        $fail('privacy.controller_model must be single | joint | separate | hybrid (asked, never guessed — AG-02)');
    } elseif ($model === 'single' && count($controllers) !== 1) {
        $fail('controller_model single needs exactly one controller');
    } elseif ($model !== 'single' && count($controllers) < 2) {
        $fail("controller_model $model needs two or more controllers");
    }
    foreach ($controllers as $index => $controller) {
        // A private person who does not run a business (business: false) has no IČO or register
        // entry; name and an e-mail are the identity and contact details of čl. 13/1 a.
        $fields = ($controller['business'] ?? true) === false
            ? ['id', 'name', 'privacy_email']
            : ['id', 'name', 'address', 'ico', 'registry', 'privacy_email'];
        foreach ($fields as $field) {
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
    if (! $purposes) {
        $fail('privacy.purposes is empty — every website processes at least server logs or contact data');
    }
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
}

// Cookies and similar technologies (INV-01–INV-03, CB-21, CB-23) — both models
$categories = ['necessary', 'preferences', 'analytics', 'marketing', 'third_party'];
$cookies = $privacy['cookies'] ?? [];
$used = [];
$inventory = [];
foreach ($cookies as $index => $item) {
    $label = ($item['name'] ?? '') !== '' ? $item['name'] : "#$index";
    foreach (explode(',', (string) ($item['name'] ?? '')) as $name) {
        if (trim($name) !== '') {
            $inventory[] = trim($name);
        }
    }
    if (($item['name'] ?? '') === '') {
        $fail("cookie $label: name missing (INV-01)");
    }
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
$listsConsentRecord = in_array('bolt-cookie-consent', $inventory, true);
if (! $listsConsentRecord && $consentCategories) {
    $fail("cookies: the consent record 'bolt-cookie-consent' (necessary, localStorage) is not listed");
}
// Without a consent category there is no banner, and js/src/cookie-consent.ts writes nothing.
if ($listsConsentRecord && ! $consentCategories) {
    $warn("cookies: 'bolt-cookie-consent' is listed but no item needs consent — there is no banner, so the choice is never stored; remove the item (INV-01)");
}
if ($contentType === null && $consentCategories && ! $consentPurpose) {
    $fail('consent categories are used but no purpose has legal_basis art6_1_a');
}

// Trackers must be inventoried, otherwise they never load (and must not be added elsewhere)
$trackerCategories = ['ga4_id' => 'analytics', 'google_ads_id' => 'marketing', 'sklik_id' => 'marketing', 'meta_pixel_id' => 'marketing'];
$configured = static fn (string $key): bool => ! empty($analytics[$key]) && ! str_contains((string) $analytics[$key], '[');
foreach ($trackerCategories as $key => $category) {
    if ($configured($key) && ! isset($used[$category])) {
        $fail("analytics.$key is set but the cookie inventory has no '$category' items — inventory it (INV-01) or it never loads");
    }
}
// …and the reverse: a tracker's cookies listed while its ID is empty. The banner then asks for
// consent to something that never loads, and the policy describes processing that does not happen.
$trackerCookies = ['ga4_id' => '~^_ga(_|$)|^_gid$~', 'google_ads_id' => '~^_gcl_|^_gac_~', 'meta_pixel_id' => '~^_fb[pc]$~', 'sklik_id' => '~^sid$|^_sklik~'];
foreach ($trackerCookies as $key => $pattern) {
    $names = array_values(array_filter($inventory, static fn (string $name) => preg_match($pattern, $name) === 1));
    if ($names && ! $configured($key)) {
        $warn('the inventory lists ' . implode(', ', $names) . " but analytics.$key is empty — the tracker never loads: set the ID, or remove the items (and the purpose and recipient that describe them) (INV-01)");
    }
}
if (($analytics['consent_mode'] ?? 'basic') === 'advanced') {
    $warn('analytics.consent_mode is advanced: Google tags load before consent — allowed only as the operator\'s explicit, documented decision (CB-50)');
}

if ($contentType === null) {
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
} else {
    $ok("'$contentType' record: " . count($cookies) . ' cookie item(s) (controllers, purposes and recipients are checked on the rendered page)');
}

$finish($consentCategories, $inventory);
