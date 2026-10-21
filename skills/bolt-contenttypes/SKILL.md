---
name: bolt-contenttypes
description: >-
  Use this skill whenever you need to create, modify, or validate ContentTypes
  and fields in Bolt CMS (config/bolt/contenttypes.yaml). Enforces strict best practices:
  no raw html fields (use redactor or article), sanitise: true on every rich-text
  field and never allow_twig, mandatory order: -id on singletons, no reserved field
  names (icon, status, author, … — and label, value, name, type inside sets), an explicit
  slug on every ContentType, viewless resource blocks, collection/set structuring,
  multilingual consistency, and a clean Bolt Configuration Notices check before content.
---

# Bolt CMS ContentTypes & Fields Standard

Defining ContentTypes in Bolt CMS (`config/bolt/contenttypes.yaml`) controls the data architecture, admin editing interface, and database relationships of your website. Failing to follow Bolt CMS architectural conventions can lead to uneditable records, broken singletons, layout regressions, or localization errors.

This skill provides the official standards, required rules, and an automated verification script for creating, refactoring, and validating Bolt CMS ContentTypes.

---

## The Golden Rules of Bolt ContentTypes

### 1. Rich Text: Never Use `type: html`
> [!WARNING]
> Do **NOT** use `type: html`.

* **Why:** In Bolt CMS 6, `type: html` is a generic WYSIWYG HTML field (Trumbowyg editor in the admin) that accepts arbitrary markup, including inline styles and pasted HTML from other sites, and can even allow Twig (`allow_twig`). Content entered there drifts from the theme's design system and breaks layouts. `redactor` (and `article` for long-form content) give editors a controlled toolbar whose output the theme styles through `.cms-redactor` / `.cms-article`, and keep all rich-text fields consistent.
* **Standard Rich Text (`type: redactor`):**
  Use `type: redactor` (provided by `bolt/redactor`) for standard editorial rich text: introductions, body copy, descriptions, teasers, and sections.
* **Structured Long-Form Content (`type: article`):**
  Use `type: article` (provided by `bolt/article`) for complex, long-form editorial content (such as blog posts, case studies, news articles) where authors construct articles with imperavi modular blocks (headings, quotes, media embeds, multi-column snippets).
* **Structured Repeating Data:**
  If content has discrete fields (e.g., FAQ questions/answers, team members, timeline items), do not ask editors to format HTML. Model them cleanly with `type: collection` and `type: set`.

```yaml
# ❌ INCORRECT (Do not use raw html)
content:
  type: html
  height: 300px

# ✅ CORRECT for standard body/intro copy
introduction:
  type: redactor
  sanitise: true
  label: "Úvodní text"
  localize: true

# ✅ CORRECT for structured long-form articles
body:
  type: article
  sanitise: true
  label: "Obsah článku"
  required: true
  localize: true
```

---

### 2. Singleton ContentTypes: Always Add `order: -id`
> [!IMPORTANT]
> Official Bolt Documentation: [Making a Singleton ContentType](https://docs.boltcms.io/5.2/howto/singleton-contenttype) recommends `sort: -id` (the older name of `order`).  
> House rule: every ContentType with `singleton: true` **MUST** declare `order: -id`.

* **Why:** In Bolt CMS, setting `singleton: true` limits backend editors to one record in the admin panel. However, when fetched in Twig templates via `{% setcontent page = 'homepage' %}` or `{% setcontent settings = 'settings' %}`, Bolt queries the database table. If records have been created, deleted, or re-saved over time, auto-incremented database IDs increase. Bolt's default order is `-createdAt`, which depends on an editable date; `order: -id` makes Bolt **always return the most recently created record (highest ID)**, regardless of how dates were edited, so stale records are never fetched.

#### A. Routable Singletons (e.g. Homepage)
Singletons that serve a dedicated front-end route:
```yaml
homepage:
  name: Domovská stránka
  singular_name: Domovská stránka
  singleton: true
  order: -id                       # <-- MANDATORY
  viewless: false
  record_template: index.twig
  locales: [ 'cs', 'en' ]
  fields:
    <<: [ *common_fields, *seo_field ]
    hero_title:
      type: text
      localize: true
      required: true
```

#### B. Data Container / Settings Singletons (e.g. Site Settings, Footer, Contact Info)
Singletons that only supply data to templates across the site and do NOT have their own URL route:
* Set `viewless: true` (disables single-record public URL `/settings/1`)
* `default_status: published` and `searchable: false` are what Bolt already defaults to here (`ContentTypesParser`: `default_status` falls back to `published`, `searchable` to `! viewless`). Write them anyway, so the intent is visible in the file.
```yaml
site_settings:
  name: Nastavení webu
  singular_name: Nastavení webu
  singleton: true
  order: -id                       # <-- MANDATORY
  viewless: true                   # No standalone public route
  default_status: published        # Automatically published
  searchable: false
  locales: [ 'cs', 'en' ]
  fields:
    company_name:
      type: text
      required: true
    contact_email:
      type: email
      required: true
    phone:
      type: text
```

---

### 3. Resource & Block ContentTypes
> [!NOTE]
> Official Bolt Documentation: [Making a Resource ContentType](https://docs.boltcms.io/5.2/howto/resource-contenttype)

Resource ContentTypes store reusable snippets, 404 page content, header teasers, or sidebar callouts that are loaded into other templates via `{% setcontent block = 'blocks/slug' %}`:
* Set `viewless: true`
* Write `default_status: published` and `searchable: false` explicitly (Bolt's defaults for a viewless type, made visible)
* Optionally set `show_on_dashboard: false` if editors rarely touch them directly.

```yaml
blocks:
  name: Bloky
  singular_name: Blok
  viewless: true
  default_status: published
  searchable: false
  show_on_dashboard: false
  locales: [ 'cs', 'en' ]
  icon_one: "fa:cube"
  icon_many: "fa:cubes"
  fields:
    title:
      type: text
      required: true
      localize: true
    slug:
      type: slug
      uses: [ title ]
    content:
      type: redactor
      sanitise: true
      localize: true
```

---

### 4. Sets & Collections vs Legacy Repeaters
> [!NOTE]
> Official Bolt Documentation: [Transform Bolt 3 repeaters to Bolt 5 sets and collections](https://docs.boltcms.io/5.2/howto/transform-repeaters-to-sets-and-collections)

In Bolt 6 (as since Bolt 5), the legacy `repeater` field type is replaced by two distinct field types:
* `type: set`: Groups a fixed composite set of fields together under one parent key (e.g., a button with `label` and `href`).
* `type: collection`: Allows editors to add, reorder, and remove multiple items (e.g., list of FAQ items, slides, features).

```yaml
# A repeating list of CTA buttons
buttons:
  type: collection
  label: "Tlačítka"
  fields:
    button:
      type: set
      fields:
        label:
          type: text
          label: "Text tlačítka"
          localize: true
          required: true
        href:
          type: text
          label: "Odkaz / URL"
          required: true
        variant:
          type: select
          values: { primary: "Primární", secondary: "Sekundární" }
          default: primary
```

---

### 5. Multilingual Parity: Shared vs. Translated Fields
> [!CAUTION]
> In a ContentType with `locales: [...]`, every field a visitor **reads as text** (`text`, `textarea`, `markdown`, `redactor`, `article`, and the `seo` field) **MUST** declare `localize: true`. Fields that hold the same value in every language — images, dates, numbers, selects, URLs, e-mails, phone numbers — stay non-localized.
>
> **Why?** A non-localized field has one value for all languages. The editor shows it on every language tab with the default-locale value, and saving on the English tab writes that one value (`ContentEditController::updateField()` stores it under the default locale). An editor who "translates" the title on the English tab silently replaces the Czech title. Nothing fails — the damage shows only on the live site.

Ensure multilingual ContentTypes adhere to:
1. `locales: [ ... ]` only contains codes registered in `config/services.yaml` (`app_locales`).
2. Text fields declare `localize: true`; shared values do not.
3. `localize: true` without `locales` on the ContentType does nothing — add `locales` (Bolt then offers the language tabs).
4. `required: true` is independent of this: a required shared field (an image) is filled once for all languages, a required localized field once per language.

---

### 6. DRY Architecture with YAML Anchors (`__nodes`)
Bolt's ContentType parser (`src/Configuration/Parser/ContentTypesParser.php`) explicitly ignores any top-level YAML keys starting with double underscores `__`.

Define reusable field clusters under `__nodes` and compose them into ContentTypes using the YAML merge syntax (`<<: [ *common_fields, *seo_field ]`):

The `seo` field type comes from the `appolodev/bolt-seo` extension (`bolt-extension-setup`); without it installed, Bolt renders the field as a plain text input.

```yaml
__nodes:
  common_fields: &common_fields
    title:
      type: text
      group: meta
      label: "Název / Title"
      localize: true
      required: true
    slug:
      type: slug
      uses: [ title ]
      group: meta

  seo_field: &seo_field
    seo:
      type: seo
      group: seo
      localize: true

  image_field: &image_field
    image:
      type: image
      label: "Hlavní obrázek"
      group: content
```

---

### 7. Rich Text Is Sanitised: `sanitise: true`, Never `allow_twig`
> [!IMPORTANT]
> Every `redactor` and `article` field **MUST** declare `sanitise: true`. No field may set `allow_twig: true`, and no field may switch cleaning off with `sanitise: false`.

* **Why `sanitise`:** Bolt cleans HTML through its HTML cleaner (`htmlcleaner` in `config/bolt/config.yaml`, HTMLPurifier) only for fields with `sanitise: true`. Bolt turns it on by default for `text`, `textarea`, `html` and `markdown` — but **not** for `redactor` and `article`, which render their stored HTML unescaped. Without it, any editor (or a stolen editor account) can store `<script>` or `onerror=` in content and run it in every visitor's browser, including an administrator's (stored XSS). Cleaning happens on output, so existing content is covered as soon as the option is set.
* **What changes on the page:** nothing editors use. On a real project the only differences were `×` in thumbnail URLs being percent-encoded (still valid), Redactor's internal `data-image` attribute being removed, and images without alternative text getting the file name as `alt`. Embedded iframes are removed when `iframe` is not in `htmlcleaner.allowed_tags` (`bolt-security-hardening` removes it — embeds go through `_consent-embed.twig`); where `iframe` stays allowed, the cleaner drops `allowfullscreen` (see `bolt-security-hardening` Step 4 for the template fix).
* **Why never `allow_twig`:** it renders field content as a Twig template on the server. Whoever can edit the field can then run template code — read configuration, call functions — so an editor account becomes control of the site.

```yaml
# ✅ CORRECT
body:
  type: redactor
  sanitise: true
  localize: true

# ❌ INCORRECT — rendered unescaped, and as a server-side template
body:
  type: redactor
  allow_twig: true
```

With YAML anchors, put `sanitise: true` into the shared field node so every ContentType inherits it.

---

### 8. Never Use a Reserved Field Name
> [!CAUTION]
> Twig resolves `{{ record.icon }}` to a **method** of Bolt's `Content` entity (`getIcon()`, `getStatus()`, `getAuthor()`, …) before it looks for a field. A field named after one of them is unreachable in templates or silently returns the wrong value. Bolt's admin dashboard warns about some of them in the **Bolt Configuration Notices** box (*"A field with name icon was found inside the homepage ContentType. You may not be able to access a field with that name in Twig."*).

**Reserved at the top level, in collections and inside sets** (compared lowercase):
`array`, `author`, `authorname`, `cachekey`, `contenttype`, `createdat`, `defaultlocale`, `definition`, `definitionfromcontenttypeconfig`, `depublishedat`, `extras`, `field`, `fielddefined`, `fields`, `fieldvalue`, `fieldvalues`, **`icon`**, `id`, `listformat`, `locales`, `modifiedat`, `publishedat`, `rawfields`, `status`, `statuses`, `taxonomies`, `taxonomydefined`, `taxonomyvalues`, `toarray`, `twig`.

**Also reserved inside a `set`** — each item is a `SetField`, so `item.value` calls `getValue()`, not your sub-field:
`allowempty`, `apivalue`, `content`, `contentselect`, `count`, `current`, `currentlocale`, `defaultlocale`, `defaultvalue`, `definition`, `get`, `id`, `key`, **`label`**, `length`, `locale`, **`name`**, `new`, `newtranslations`, `next`, `parent`, `parsedvalue`, `rewind`, `set`, `sortorder`, `translatable`, `translations`, `twigvalue`, **`type`**, `usedefaultlocale`, `valid`, **`value`**, `valueforeditor`, `version`.

Sources: `Checks::$generalForbiddenFieldNames` / `$setForbiddenFieldNames` of `bolt/configuration-notices-widget` and the public getters of `Bolt\Entity\Content` and `Bolt\Entity\Field\SetField` (bolt/core 6.1). The dashboard widget only checks the set's own name against the set list, so `label` / `value` **inside** a set pass it unnoticed — the verification script catches them. `slug` is a getter too, but it is Bolt's own slug field and resolves to it.

Use a descriptive name instead — in Czech projects the Czech word reads well in the admin and never collides:

```yaml
# ❌ INCORRECT
icon: { type: select, values: { … } }
facts:
  type: collection
  fields:
    fact:
      type: set
      fields:
        label: { type: text }      # item.label → SetField method
        value: { type: text }      # item.value → SetField::getValue()

# ✅ CORRECT
ikona: { type: select, values: { … } }          # or: symbol, pictogram
facts:
  type: collection
  fields:
    fact:
      type: set
      fields:
        popisek: { type: text }    # or: caption, heading
        hodnota: { type: text }    # or: detail, amount
```

### 9. Always Set `slug:` Explicitly
Bolt keys ContentTypes by their **slug**, and without `slug:` it slugifies the `name` — not the YAML key. `homepage:` with `name: Úvod` becomes `uvod`: `{% setcontent page = 'homepage' %}` throws *"no ContentType by that name/slug exists"*, `homepage: homepage` in `config.yaml` finds nothing, `config.get('contenttypes/homepage/…')` is empty, and the listing route answers at `/uvod`. Bolt's dashboard reports it as *"There is an ambiguity in the slug of the … ContentType"*.

```yaml
homepage:
  name: Úvod                 # Czech admin label
  singular_name: Úvod
  slug: homepage             # the key templates and config use
  singular_slug: homepage    # otherwise /uvod also routes to the record
```

For a singleton page the slug **is** its URL (`/{slug}` forwards to the record), so pick the public path (`slug: podminky-sluzby`) and query it by that slug.

---

## Before Entering Content: Bolt Configuration Notices Must Be Clean

Every notice in the **Bolt Configuration Notices** box of the admin dashboard is a configuration problem that content entered now would inherit (records saved under a wrong slug, values in a field Twig cannot read). Run the same checks from the command line and resolve **every** warning before the first record is created, and again after every change to `contenttypes.yaml`:

```bash
php vendor/tomvondracek/bolt-skills/skills/bolt-build/scripts/config-notices.php --project=.
# exit 0: clean · exit 1: notices to resolve · exit 2: could not run
```

`scripts/verify.sh` runs it as its third section. Renaming a field after content exists loses that field's values (Bolt stores fields by name), so this check belongs before content entry, not after.

---

## Verification & Automated Linting

To inspect your ContentTypes configuration against all aforementioned standards, run the verification script:

```bash
vendor/tomvondracek/bolt-skills/skills/bolt-contenttypes/scripts/verify.sh
```

The rules are checked by `scripts/check-contenttypes.php` on the parsed YAML (merge keys and tags resolved), so formatting and anchors do not matter.

### What the script validates:
1. **YAML Syntax:** Executes `bin/console lint:yaml config/bolt/contenttypes.yaml --parse-tags`.
2. **Forbidden `html` Fields:** Recursively flags any field, set, or collection using `type: html` and suggests `redactor` or `article`.
3. **Singleton Ordering:** Flags any `singleton: true` ContentType missing `order: -id`.
4. **Deprecated `repeater`:** Flags legacy `type: repeater` and advises migrating to `collection` + `set`.
5. **Shared vs. Translated Fields (warning):** Flags text fields (`text`, `textarea`, `html`, `markdown`, `redactor`, `article`) without `localize: true` in multilingual ContentTypes. Fields whose name marks a shared value (`…url`, `…link`, `…email`, `…phone`, `ico`, `dic`, social network names) are skipped. Also warns when fields are `localize: true` but the ContentType has no `locales`.
6. **Valid Slugs:** Verifies all `type: slug` fields define the `uses` mapping.
7. **Permitted Locales:** Verifies ContentType `locales` are declared in `app_locales`.
8. **Sanitised Rich Text:** Flags `redactor` and `article` fields without `sanitise: true`, any `allow_twig: true`, and `sanitise: false` on any field.
9. **Reserved Field Names:** Fails on any field (top level, collection item, set sub-field) named after a method of Bolt's `Content` entity, and on set sub-fields named after a `SetField` method (rule 8).
10. **Explicit Slug:** Fails when a ContentType has no `slug:` and the slug Bolt infers from `name` differs from its key (rule 9).
11. **Bolt Configuration Notices:** Runs `bolt-build/scripts/config-notices.php` — the dashboard widget's checks — and fails on any warning or danger notice.

---

## Complete Reference Template

Here is a complete, production-ready blueprint demonstrating all rules together:

```yaml
# config/bolt/contenttypes.yaml

__nodes:
  common_fields: &common_fields
    title:
      type: text
      group: meta
      label: "Název"
      localize: true
      required: true
    slug:
      type: slug
      uses: [ title ]
      group: meta

  seo_field: &seo_field
    seo:
      type: seo
      group: seo
      localize: true

# 1. Routable Singleton
homepage:
  name: Domovská stránka
  singular_name: Domovská stránka
  singleton: true
  order: -id
  viewless: false
  record_template: index.twig
  locales: [ 'cs', 'en' ]
  fields:
    <<: [ *common_fields, *seo_field ]
    hero_title:
      type: text
      localize: true
      required: true
    hero_intro:
      type: redactor
      sanitise: true
      localize: true

# 2. Viewless Settings Singleton
settings:
  name: Nastavení webu
  singular_name: Nastavení webu
  singleton: true
  order: -id
  viewless: true
  default_status: published
  searchable: false
  locales: [ 'cs', 'en' ]
  fields:
    phone:
      type: text
    email:
      type: email

# 3. Viewless Reusable Blocks
blocks:
  name: Bloky
  singular_name: Blok
  viewless: true
  default_status: published
  searchable: false
  show_on_dashboard: false
  locales: [ 'cs', 'en' ]
  fields:
    <<: [ *common_fields ]
    content:
      type: redactor
      sanitise: true
      localize: true

# 4. Standard Routable Articles with Redactor & Article
articles:
  name: Články
  singular_name: Článek
  locales: [ 'cs', 'en' ]
  listing_template: pages/articles/articles.twig          # pages/<name>/<name>.twig (Integration Contract)
  record_template: pages/articles/articles.record.twig   # pages/<name>/<name>.record.twig
  order: -createdAt
  fields:
    <<: [ *common_fields, *seo_field ]
    teaser:
      type: redactor
      sanitise: true
      label: "Perex článku"
      localize: true
    body:
      type: article
      sanitise: true
      label: "Obsah článku"
      localize: true
      required: true
```
