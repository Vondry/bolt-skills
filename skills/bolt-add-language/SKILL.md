---
name: bolt-add-language
description: >-
  Use this skill whenever you need to add a new language/locale to a Bolt CMS site,
  configure multilingual routing, or maintain full parity across all translations,
  ContentTypes, navigation menus, and theme language switchers.
---

# Adding a New Language / Locale to Bolt CMS

Adding a new language (e.g. `de`, `en`, `pl`, `fr`, `sk`) to a Bolt CMS site requires synchronized configuration across **five separate subsystems**: routing parameters, ContentType schemas, XLIFF message catalogs, navigation menus, and theme switchers. Missing any one of these steps results in 404 errors, pages redirected back to the default language, untranslated keys, or un-editable content.

This skill provides the end-to-end procedure and verification to roll out a new language completely with zero configuration drift.

---

## Pre-flight: Identify the Locales

1. **Read the source/default locale** from `config/services.yaml`:
   ```bash
   grep -E '^\s*locale:' config/services.yaml
   ```
2. **Read the currently registered locales**:
   ```bash
   grep -E 'app_locales' config/services.yaml
   ```
3. Let `<target_code>` be the new 2-letter ISO code to add (e.g., `de`, `fr`, `pl`).

---

## Step 1: Register Locale in `config/services.yaml`

File: `config/services.yaml`  
Official Doc Reference: [Bolt Localization: Locales](https://docs.boltcms.io/5.2/localization/locales)

In Bolt CMS, `app_locales` is the master parameter defining all allowed interface and routing languages for the application. Bolt's kernel (`src/Kernel.php`) automatically splits `app_locales` by pipe (`|`) to populate `%locales_array%`, which is used by Symfony's translation component (`config/packages/translation.yaml`).

Add `<target_code>` (e.g. `de` or regional code like `de_DE`) to `app_locales`. Do **not** define `locales_array` yourself: the kernel overwrites it from `app_locales`, so a hand-written copy can only drift. If an older project has the line, delete it.

```yaml
# config/services.yaml
parameters:
  locale: cs                               # Default site language (remains unchanged)
  app_locales: cs|en|de                    # Pipe-separated codes (required for routing)
```

> [!WARNING]
> If `app_locales` is not updated, visiting any route with the `/<target_code>/` prefix will fail with a 404 Not Found error: every localized route requires `_locale` to match `%app_locales%`, so the prefix matches no route.

---

## Step 2: Enable Locale on Every ContentType

File: `config/bolt/contenttypes.yaml`  
Official Doc Reference: [Bolt ContentTypes: Defining ContentTypes](https://docs.boltcms.io/5.2/contenttypes/intro)

In Bolt CMS, the `locales` setting on a ContentType defines which languages the content can be entered in (e.g. `locales: ['en', 'nl', 'de']`). Individual fields must have `localize: true` to allow separate values per locale. If a ContentType does not list the new locale, editors cannot create/edit records in that language, and Bolt redirects its frontend pages in that language to the default locale (`TwigAwareController::validLocaleForContentType()` → `redirectToDefaultLocale()`). A visitor who switches language lands back on the default one.

Add `'<target_code>'` to the `locales:` array of **every** ContentType:

```yaml
# config/bolt/contenttypes.yaml
pages:
  name: Pages
  singular_name: Page
  locales: [ 'cs', 'en', 'de' ]            # Add target code here
  fields:
    title:
      type: text
      localize: true

entries:
  name: Entries
  singular_name: Entry
  locales: [ 'cs', 'en', 'de' ]            # Add target code here
```

### Verification Command:
Confirm no ContentType was missed:
```bash
grep -n "locales:" config/bolt/contenttypes.yaml | grep -v "'<target_code>'"
# (Should return no results)
```

---

## Step 3: Create XLIFF 2.0 Message Catalog (`messages.<target_code>.xlf`)

File: `translations/messages.<target_code>.xlf`

Bolt uses Symfony's Translation component with **XLIFF 2.0** format. The new catalog must mirror the structure and unit keys of the source catalog (`translations/messages.<source_code>.xlf`) at **1:1 parity**.

```xml
<?xml version="1.0" encoding="utf-8"?>
<xliff xmlns="urn:oasis:names:tc:xliff:document:2.0" version="2.0" srcLang="cs" trgLang="de">
  <file id="messages.de">
    <unit id="card_read_more" name="card.read_more">
      <segment>
        <source>card.read_more</source>
        <target>Mehr erfahren</target>
      </segment>
    </unit>
    <unit id="contact_banner_cta" name="contact.banner_cta">
      <segment>
        <source>contact.banner_cta</source>
        <target>Kontaktieren Sie uns</target>
      </segment>
    </unit>
  </file>
</xliff>
```

Keys follow the Integration Contract (`WORKFLOWS.md`): **dotted keys** (`card.read_more`) stored in the unit's `name` attribute and repeated in `<source>`; templates call `{{ __('card.read_more') }}` or `{{ 'card.read_more'|trans }}`. Symfony uses the `name` attribute as the translation key (falling back to `<source>`).

The quickest way to create a new catalog with full parity is to merge the English catalog of the project into it and translate the targets:

```bash
php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php translations/messages.en.xlf translations/messages.<target_code>.xlf
```

The helper creates `messages.<target_code>.xlf` (setting `trgLang` and the file id) or adds only the missing units to an existing catalog — it never overwrites translations. Every skill that renders text ships its units in `examples/translations.<locale>.xlf` (`bolt-theme-init`, `bolt-menu`, `bolt-theme-templates`, `bolt-cookie-consent`, this skill); merge them the same way.

### Critical Catalog Rules:
1. **Match `name` and `<source>` exactly**: Keep the unit key identical to the source catalog; only translate `<target>`.
2. **Preserve HTML / CDATA**: If the source has `<![CDATA[ ... ]]>`, preserve the CDATA wrapper in the target.
3. **Preserve placeholders**: Keep placeholders like `%count%`, `%url%`, or tokens intact.
4. **Unit Parity**: Unit count must match the source catalog. A key missing from a catalog renders as the key itself (or as the fallback locale's text when `framework.translator.fallbacks` is configured); `|default()` after `__()` does not help, because the key is returned instead of null.

---

## Step 4: Update Navigation Menus (`config/bolt/menu.yaml`)

File: `config/bolt/menu.yaml`

Bolt navigation menus use per-locale label maps. Add the `<target_code>:` entry to **every** menu item in all menus (`main`, `footer`, and submenus):

```yaml
# config/bolt/menu.yaml
main:
  - label: { cs: 'O nás', en: 'About us', de: 'Über uns' }
    link: /o-nas
  - label: { cs: 'Kontakt', en: 'Contact', de: 'Kontakt' }
    link: /kontakt
```

> **Note:** `link:` values do not need locale prefixes; Bolt and Twig routing automatically handle URL prefixes per locale.

---

## Step 5: Update SEO Overrides (If `appolodev/bolt-seo` is installed)

File: `config/extensions/appolo-boltseo.yaml`

If your project uses the Bolt SEO extension, check `config/extensions/appolo-boltseo.yaml`. Each entry under `override_default:` includes a `locales:` map. Add a `<target_code>:` block with translated `title`, `description`, and `keywords`:

```yaml
# config/extensions/appolo-boltseo.yaml
override_default:
  homepage:
    title: 'Hlavní strana'
    locales:
      en:
        title: 'Home'
        description: '...'
      de:
        title: 'Startseite'
        description: '...'
        keywords: '...'
```

*(If this file does not exist in the project, skip this step).*

---

## Step 6: Update Theme Language Switcher (`_locale-switcher.twig`)

The header and the mobile drawer of `bolt-menu` include `partials/_locale-switcher.twig` (`{ mobile: false }` / `{ mobile: true }`). If the theme does not have it yet, copy the example shipped with this skill and merge its translation unit (`locale.switch`):

```bash
cp vendor/tomvondracek/bolt-skills/skills/bolt-add-language/examples/_locale-switcher.twig public/theme/<theme_name>/partials/
php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php \
    vendor/tomvondracek/bolt-skills/skills/bolt-add-language/examples/translations.cs.xlf translations/messages.cs.xlf
```

Locate the theme's locale switcher partial:
```bash
find public/theme -name '_locale-switcher.twig'
```

Add the new locale to the `locales` dictionary using its **endonym** (the language's native name in its own language, e.g. `'de': 'Deutsch'`, `'fr': 'Français'`, `'pl': 'Polski'`).

```twig
{# public/theme/<theme_name>/partials/_locale-switcher.twig #}
{% set locales = {
    'cs': 'Čeština',
    'en': 'English',
    'de': 'Deutsch',
} %}
```

> **Why endonyms?** Visitors who cannot read the current language will always recognize the native name of their own language.

How the shipped partial builds the links:
- It strips the current locale prefix from `app.request.pathinfo` and re-prefixes `/<code>` for every non-default locale (after `app.request.basePath`, so sub-directory installs work; repeated leading slashes are collapsed, so a request for `//other.host` cannot turn into an off-site link) (the default locale stays unprefixed; the homepage becomes `/<code>/`, matching Bolt's `homepage_locale` route), and appends the query string.
- Every link carries `data-locale-switch`, `hreflang`, `lang`, and `aria-current="page"` on the active locale; `js/src/locale-switcher.ts` (from `bolt-theme-init`) re-appends the URL hash and restores the scroll position after the switch.
- The dropdown uses `data-dropdown-toggle` and a `.dropdown` panel, driven by `js/src/menu.ts`.
- Record slugs are not translated by this path-based switch: when slugs differ per locale, link records with `record|link(true, code)` instead (as the sitemap does: `tomvondracek/bolt-sitemap` lists every record in each locale).

### hreflang alternates in `<head>`

Search engines learn about the other language versions from `<link rel="alternate" hreflang>` in `<head>` — the `hreflang` attribute on the switcher links is not enough, and neither Bolt nor `appolodev/bolt-seo` prints these tags. The master layout of `bolt-theme-init` includes `partials/_hreflang.twig` in its `seo` block (`ignore missing`); copy it from this skill and add the new code to its `locales` list:

```bash
cp vendor/tomvondracek/bolt-skills/skills/bolt-add-language/examples/_hreflang.twig public/theme/<theme_name>/partials/
```

```twig
{# public/theme/<theme_name>/partials/_hreflang.twig #}
{% set locales = ['cs', 'en', 'de'] %}
```

An older master layout without the include gets it after `{{ seo.metatags() }}`:

```twig
{% block seo %}
    <title>{{ seo.title() }}</title>
    {{ seo.metatags() }}
    {% include 'partials/_hreflang.twig' ignore missing %}
{% endblock seo %}
```

The partial prints one `<link rel="alternate">` per locale plus `x-default` (the default locale), with the same paths as the switcher, on the host from `canonical` in `config/bolt/config.yaml` (`BOLT_CANONICAL`) and without the query string. The 404 / 403 helper pages override the `seo` block, so they carry no alternates. Check one page: `curl -s https://example.cz/en/<page> | grep hreflang` lists every locale and `x-default`.

## Step 7: Validate & Clear Cache

Always run standard validation to ensure zero syntax or translation errors:

```bash
# 1. Validate XLIFF XML syntax
bin/console lint:xliff translations

# 2. Validate YAML configuration
bin/console lint:yaml config --parse-tags

# 3. Clear Symfony cache
bin/console cache:clear
APP_ENV=prod bin/console cache:clear
```

---

## Verification & Parity Checks

Run the bundled test script to verify that the new language is completely wired up:

```bash
vendor/tomvondracek/bolt-skills/skills/bolt-add-language/scripts/verify.sh <target_code>
```

It parses the files instead of searching their text (`scripts/check-language.php`):

| Check | Fails when |
| :--- | :--- |
| `app_locales` in `config/services.yaml` | the code is not one of the `|`-separated locales (warns when `locales_array` is defined by hand) |
| `config/bolt/contenttypes.yaml` | a ContentType with `locales` does not list the code (warns about ContentTypes without `locales`) |
| `translations/messages.<code>.xlf` | the catalog is missing, or a key of the default locale's catalog is missing in it (warns about extra keys) |
| `config/bolt/menu.yaml` | a per-locale `label` map has no entry for the code (warns about plain-string labels) |
| `bin/console lint:xliff translations` | any catalog is invalid |
| `partials/_locale-switcher.twig` | — (warns when the code is not in the `locales` map) |
| `partials/_hreflang.twig` and the master layout | no `rel="alternate" hreflang` output in the theme's layouts, or the code is not in the partial's `locales` list |

To check the router by hand: `bin/console debug:router record_locale` shows the `_locale` requirement with the new code.
