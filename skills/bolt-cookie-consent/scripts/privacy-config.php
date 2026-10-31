<?php

declare(strict_types=1);

/*
 * bolt-cookie-consent: builds the `privacy:` block of theme.yaml (the single source of truth
 * for the cookie banner, the cookie list and the privacy policy page) from the intake answers.
 *
 * Run from the Bolt project root (uses the project's symfony/yaml):
 *
 *   php <skill>/scripts/privacy-config.php --model=single \
 *       --trackers=ga4,google_ads,sklik --embeds=youtube \
 *       --purposes=web_operation,contact_form,legal_claims \
 *       [--controllers=1] [--necessary=session] [--locales=cs,en] [--write=public/theme/<theme>/theme.yaml]
 *
 * Without --write the block is printed. With --write it is appended to theme.yaml (skipped when
 * theme.yaml already has a `privacy:` key) and missing `analytics:` ID keys are added.
 * Every value the operator must supply stays `[DOPLNIT …]` (AG-01); --model is required because
 * the controller model is never guessed (AG-02).
 */

$autoload = getcwd() . '/vendor/autoload.php';
if (! is_file($autoload)) {
    fwrite(STDERR, "ERROR: run from the Bolt project root after `composer install` (vendor/autoload.php not found).\n");
    exit(1);
}
require $autoload;

use Symfony\Component\Yaml\Yaml;

$options = getopt('', ['model:', 'trackers::', 'embeds::', 'purposes::', 'controllers::', 'necessary::', 'locales::', 'write::', 'catalog::', 'help']);

if (isset($options['help'])) {
    echo "Usage: php privacy-config.php --model=single|joint|separate|hybrid [--trackers=ga4,google_ads,sklik,meta_pixel]\n";
    echo "       [--embeds=youtube,google_maps,mapy_com] [--purposes=web_operation,contact_form,contract,accounting,newsletter,legal_claims]\n";
    echo "       [--controllers=N] [--necessary=session] [--locales=cs,en] [--write=path/to/theme.yaml]\n";
    exit(0);
}

$list = static fn (string $key, string $default = ''): array => array_values(array_filter(array_map('trim', explode(',', (string) ($options[$key] ?? $default)))));

$catalogFile = $options['catalog'] ?? __DIR__ . '/../references/cookie-catalog.yaml';
$catalog = Yaml::parseFile($catalogFile);

$model = $options['model'] ?? '';
if (! in_array($model, ['single', 'joint', 'separate', 'hybrid'], true)) {
    fwrite(STDERR, "ERROR: --model=single|joint|separate|hybrid is required. Ask the operator the two controller-model questions (SKILL.md, Step 0) — never guess it (AG-02).\n");
    exit(1);
}

$controllerCount = (int) ($options['controllers'] ?? ($model === 'single' ? 1 : 2));
if ($model === 'single' && $controllerCount !== 1) {
    fwrite(STDERR, "ERROR: --model=single means exactly one controller.\n");
    exit(1);
}
if ($model !== 'single' && $controllerCount < 2) {
    fwrite(STDERR, "ERROR: --model=$model needs --controllers=2 or more.\n");
    exit(1);
}

$trackers = $list('trackers');
$embeds = $list('embeds');
$purposeKeys = $list('purposes', 'web_operation,contact_form');
$necessaryExtra = $list('necessary');

foreach ([['trackers', $trackers], ['embeds', $embeds], ['purposes', $purposeKeys], ['necessary_optional', $necessaryExtra]] as [$section, $keys]) {
    foreach ($keys as $key) {
        if (! isset($catalog[$section][$key])) {
            fwrite(STDERR, "ERROR: unknown $section entry '$key'. Known: " . implode(', ', array_keys($catalog[$section])) . "\n");
            exit(1);
        }
    }
}

// Locales: --locales, else app_locales from config/services.yaml, else cs.
$locales = $list('locales');
if (! $locales && is_file('config/services.yaml')) {
    // services.yaml may use Symfony tags (!tagged_iterator, !service …).
    $services = Yaml::parseFile('config/services.yaml', Yaml::PARSE_CUSTOM_TAGS);
    $locales = array_values(array_filter(explode('|', (string) ($services['parameters']['app_locales'] ?? ''))));
}
if (! in_array('cs', $locales, true)) {
    array_unshift($locales, 'cs');
}

/** Keeps only the project's locales in localized maps; a locale missing in the catalog becomes a placeholder. */
$localize = static function ($value) use (&$localize, $locales) {
    if (! is_array($value)) {
        return $value;
    }
    $isLocalized = $value !== [] && isset($value['cs']) && count(array_filter(array_keys($value), static fn ($key) => ! is_string($key) || ! preg_match('/^[a-z]{2}$/', $key))) === 0;
    if ($isLocalized) {
        $out = [];
        foreach ($locales as $locale) {
            $out[$locale] = $value[$locale] ?? "[DOPLNIT překlad $locale]";
        }

        return $out;
    }

    return array_map($localize, $value);
};

// Cookies / similar technologies (INV-01, INV-02). The consent record exists only with a banner.
$cookies = ($trackers || $embeds) ? $catalog['necessary'] : [];
// A multilingual site sets the session cookie on its /<locale>/ pages (Bolt keeps the locale in
// the session whenever the URL names one); with forms as well it is still one cookie, so the form
// purpose joins that item. A single-language site sets it only for /cs/… or ?_locale= URLs.
if (count($locales) > 1) {
    $session = $catalog['necessary_optional']['locale_session'];
    if (in_array('session', $necessaryExtra, true)) {
        foreach ($catalog['necessary_optional']['session'][0]['purpose'] as $locale => $text) {
            $session[0]['purpose'][$locale] = ($session[0]['purpose'][$locale] ?? '') . ' ' . $text;
        }
        $necessaryExtra = array_values(array_diff($necessaryExtra, ['session']));
    }
    $cookies = array_merge($cookies, $session);
}
foreach (array_diff($necessaryExtra, ['locale_session']) as $key) {
    $cookies = array_merge($cookies, $catalog['necessary_optional'][$key]);
}

$consentPurposes = [];   // purpose key => recipient keys
foreach ([['trackers', $trackers], ['embeds', $embeds]] as [$section, $keys]) {
    foreach ($keys as $key) {
        $entry = $catalog[$section][$key];
        $cookies = array_merge($cookies, $entry['cookies']);
        $consentPurposes[$entry['purpose']][] = $entry['recipient'];
    }
}

// Controllers (čl. 13/1 a). The first one is prefilled from theme.yaml contact: when available.
$contact = [];
$writeTo = $options['write'] ?? null;
if ($writeTo && is_file($writeTo)) {
    $contact = (Yaml::parseFile($writeTo)['contact'] ?? []) ?: [];
}
$controllers = [];
for ($index = 1; $index <= $controllerCount; $index++) {
    $prefill = $index === 1 ? $contact : [];
    $controllers[] = [
        'id' => "ctrl-$index",
        'legal_form' => '[DOPLNIT OSVČ | s.r.o. | a.s. | advokát | …]',
        'name' => $prefill['name'] ?? '[DOPLNIT jméno nebo obchodní firma]',
        'address' => $prefill['address'] ?? '[DOPLNIT sídlo / místo podnikání]',
        'ico' => isset($prefill['ico']) ? (string) $prefill['ico'] : '[DOPLNIT IČO]',
        'registry' => '[DOPLNIT zápis v obchodním / živnostenském rejstříku nebo jiné evidenci]',
        'privacy_email' => $prefill['email'] ?? '[DOPLNIT e-mail pro dotazy k osobním údajům]',
        'dpo' => null,
    ];
}
$controllerIds = array_column($controllers, 'id');

// Purposes (čl. 13/1 c, d; 13/2 a, e)
$purposes = [];
$recipientKeys = [];
foreach (array_merge($purposeKeys, array_keys($consentPurposes)) as $key) {
    $purpose = $catalog['purposes'][$key];
    $purpose['recipients'] = array_values(array_unique(array_merge($purpose['recipients'], $consentPurposes[$key] ?? [])));
    $recipientKeys = array_merge($recipientKeys, $purpose['recipients']);
    $purposes[] = ['id' => $key, 'controllers' => $controllerIds, 'section' => 'website'] + $purpose;
}

$recipients = [];
foreach (array_values(array_unique($recipientKeys)) as $key) {
    $recipients[] = ['id' => $key] + $catalog['recipients'][$key];
}

$privacy = [
    'config_version' => 1,
    'effective_date' => '[DOPLNIT YYYY-MM-DD]',
    'controller_model' => $model,
    'controllers' => $controllers,
    'joint_arrangement' => in_array($model, ['joint', 'hybrid'], true) ? [
        'contact_controller' => 'ctrl-1',
        'summary' => ['cs' => '[DOPLNIT podstata ujednání podle čl. 26 GDPR: kdo vyřizuje žádosti, kdo plní informační povinnost, kdo spravuje cookie lištu]'],
    ] : null,
    'summary' => null,
    'purposes' => $purposes,
    'recipients' => $recipients,
    'cookies' => $cookies,
    'consent' => ['validity_months' => 12, 'reask_after_reject_months' => 6],
    'automated_decision_making' => false,
    'changelog' => [
        ['version' => 1, 'date' => '[DOPLNIT YYYY-MM-DD]', 'change' => ['cs' => 'První verze.', 'en' => 'First version.']],
    ],
];
$privacy = $localize($privacy);

$header = <<<'YAML'

# --------------------------------------------------------------------------------------------
# Privacy & cookie consent (bolt-cookie-consent). Single source of truth for the cookie banner,
# the cookie list and the privacy policy page — never duplicate these texts in templates.
#   [DOPLNIT …]  value the operator must supply (never invented)
#   [OVĚŘIT …]   value to measure in a clean browser profile (DM-02)
# Increase config_version (and add a changelog entry) whenever purposes, controllers, recipients
# or cookie categories change: visitors who consented are asked again (CB-42, DM-01).
# controller_model: single (A) | joint (B1) | separate (B2) | hybrid (B1 web + B2 clients).
# purposes[].section: `website` (shared part) or a controller id (that controller's own section,
# used for client agendas in the separate / hybrid models — VAR-20).
# --------------------------------------------------------------------------------------------

YAML;

// Block style down to the entries; localized maps and short lists stay inline ({ cs: …, en: … }).
$dumped = Yaml::dump(['privacy' => $privacy], 4, 2, Yaml::DUMP_NULL_AS_TILDE | Yaml::DUMP_EMPTY_ARRAY_AS_SEQUENCE);
$block = $header . preg_replace('/^(\s*)-\n\s+/m', '$1- ', $dumped);

if (! $writeTo) {
    echo $block;
    exit(0);
}

if (! is_file($writeTo)) {
    fwrite(STDERR, "ERROR: $writeTo not found.\n");
    exit(1);
}

$yaml = file_get_contents($writeTo);

// analytics: ID keys for the selected trackers (theme-init ships ga4_id / sklik_id / consent_mode)
$idKeys = ['consent_mode' => "basic           # basic: Google tags load only after consent | advanced: cookieless pings before consent (operator's explicit decision, CB-50)"];
foreach ($trackers as $key) {
    $idKeys[$catalog['trackers'][$key]['analytics_key']] = "~                  # {$catalog['trackers'][$key]['label']}";
}
$analytics = (Yaml::parse($yaml)['analytics'] ?? []) ?: [];
$missing = [];
foreach ($idKeys as $key => $line) {
    if (! array_key_exists($key, $analytics)) {
        $missing[] = "  $key: $line";
    }
}
if ($missing) {
    if (preg_match('/^analytics:[^\n]*\n/m', $yaml)) {
        $yaml = preg_replace('/^analytics:[^\n]*\n/m', "$0" . implode("\n", $missing) . "\n", $yaml, 1);
    } else {
        $yaml = rtrim($yaml) . "\n\n# Tracking IDs (bolt-cookie-consent)\nanalytics:\n" . implode("\n", $missing) . "\n";
    }
    echo 'Added to analytics: ' . implode(', ', array_map(static fn ($line) => trim(explode(':', $line)[0]), $missing)) . "\n";
}

if (preg_match('/^privacy:/m', $yaml)) {
    echo "Existing: $writeTo already has a privacy: block — preserved. Edit it by hand (and bump config_version).\n";
} else {
    $yaml = rtrim($yaml) . "\n" . $block;
    echo "Added: privacy: block to $writeTo\n";
}

file_put_contents($writeTo, $yaml);
