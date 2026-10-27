---
name: bolt-extension-setup
description: >-
  Use this skill whenever installing, configuring, or verifying the trio of essential
  Bolt CMS extensions: AppoloDev/bolt-seo (SEO meta fields and tags, with the
  canonical URL override needed until bolt/core PR #3735 is released),
  Vondry/bolt-sitemap (tomvondracek/bolt-sitemap: spec-compliant XML sitemap
  index with static pages, no theme override), and
  Vondry/bolt-llms-txt (llmstxt.org dynamic endpoint).
---

# Essential Bolt CMS Extensions Setup & Verification Guide

Every modern production website built with Bolt CMS requires three foundational extensions for discoverability, search engine indexing, and AI crawler readiness:

1. **`AppoloDev/bolt-seo` (`appolodev/bolt-seo`)**: Structured SEO meta fields (`type: seo`), OpenGraph tags, JSON-LD, and robots meta tags — plus a theme override that gives `<link rel="canonical">`, `og:url` and `twitter:url` one clean URL (bolt/core PR #3735 workaround).
2. **`Vondry/bolt-sitemap` (`tomvondracek/bolt-sitemap`)**: an XML sitemap index generated from content and routes, including the theme's static pages. It needs no theme override and replaces `bolt/sitemap-extension`.
3. **`Vondry/bolt-llms-txt` (`tomvondracek/bolt-llms-txt`)**: Serves `/llms.txt` dynamically from CMS content adhering strictly to the [llmstxt.org](https://llmstxt.org/) specification.

This skill provides the end-to-end installation steps, architecture patterns, theme templates, and an automated verification script.

---

## 1. AppoloDev/bolt-seo Setup

Official repository: [AppoloDev/bolt-seo](https://github.com/AppoloDev/bolt-seo)

### 1.1 Install via Composer
```bash
composer require appolodev/bolt-seo:^2.3
```

### 1.2 Copy Config Recipes & Install Assets
```bash
php bin/console extensions:configure --with-config
php bin/console assets:install --symlink --relative public
```
This generates:
* `config/extensions/appolo-boltseo.yaml`
* `config/packages/extension_bolt-seo.yaml`
* Publishes JavaScript/CSS assets to `public/assets/seo/` for the Bolt editor backend.

### 1.3 Configure Fallback Fields
In `config/extensions/appolo-boltseo.yaml`, define field fallback chains so that if an editor leaves the SEO field blank, title, description, and preview images fall back naturally to record fields:

```yaml
# config/extensions/appolo-boltseo.yaml
title_separator: "|"
title_postfix: ''

title_length: 70
description_length: 158

fields:
  slug: [ 'slug' ]
  title: [ 'title', 'name', 'heading' ]
  description: [ 'introduction', 'teaser', 'description', 'hero_subtitle' ]
  keywords: [ ]
  image: [ 'image', 'main_image', 'photo' ]

default:
  title: ""
  description: ""
  keywords: ""
  ogtype: "website"
  robots: "index, follow"

templates:
  meta: partials/_seo_metatags.twig # canonical override: set it once the partial exists, section 1.6
```

The robots default is `default.robots`. A top-level `meta_robots` key and the commented-out `allow:` block from older recipes were never read, and bolt-seo 2.3 removed both from its own config. Delete them from projects that still carry them; nothing renders differently, because `index, follow` is also the built-in fallback.

### 1.4 Integrate Reusable SEO Field in `contenttypes.yaml`
Following the **`bolt-contenttypes`** best practice, declare a reusable anchor under `__nodes` and merge it into every routable ContentType:

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

homepage:
  name: Domovská stránka
  singular_name: Domovská stránka
  singleton: true
  order: -id
  fields:
    <<: [ *common_fields, *seo_field ]

articles:
  name: Články
  singular_name: Článek
  fields:
    <<: [ *common_fields, *seo_field ]
```

### 1.5 Include SEO Tags in Theme Base Layout
The shared layout shell `public/theme/<themename>/partials/_master.twig` created by `bolt-theme-init` already contains this block inside `<head>` (Integration Contract in `WORKFLOWS.md`); for a theme without it, place the SEO block inside the HTML `<head>` of the base layout:

```twig
{# https://github.com/AppoloDev/bolt-seo #}
{% block seo %}
    <title>{{ seo.title() }}</title>
    {{ seo.metatags() }}
{% endblock seo %}
```

For static or helper pages without a CMS record, override the block in that template:
```twig
{% block seo %}
    {% set seoTitle = __('page.title') ~ ' | ' ~ config.get("general/sitename") %}
    <title>{{ seoTitle }}</title>
    {% include '@seo/_metatags.html.twig' with {
        title: seoTitle,
        description: __('page.seo.description'),
        keywords: __('page.seo.keywords'),
        canonical: seo.canonical()
    } %}
{% endblock seo %}
```

Pass `canonical: seo.canonical()`, the URL `<link rel="canonical">` prints. Do not pass `app.request.uri`: it carries the query string (`?utm_source=…`), which the canonical drops, so `og:url` would differ from the canonical on every tagged link.

### 1.6 Canonical URL Override (bolt/core PR #3735 Workaround)
> [!IMPORTANT]
> Until [bolt/core Pull Request #3735](https://github.com/bolt/core/pull/3735) is merged **and** the project runs a bolt/core release that includes it, every Bolt 6 project needs this override. Bolt's canonical URL (bolt/core ≤ 6.1.10):
> 1. names a singleton by its record route, e.g. `/kontakt/kontakt-2`, although visitors use `/kontakt` (localized: `/en/kontakt/kontakt-2`);
> 2. keeps the listing query on a listing page, e.g. `/clanky?order=-createdAt&status=published`.
>
> bolt-seo 2.3 builds `og:url` and `twitter:url` from the same Bolt canonical, so both problems show up in `<link rel="canonical">`, `og:url` and `twitter:url`. A theme that corrects only `<link rel="canonical">` (its own `canonical_template`) makes it worse: `og:url` then names a different URL than the canonical.
>
> **The Workaround:** one macro corrects Bolt's canonical the way PR #3735 does, and both `<link rel="canonical">` and bolt-seo's `og:url` / `twitter:url` print its result. The three tags always name the same URL.

Copy the three files from `examples/` to `public/theme/<themename>/partials/` **unchanged**, before the config below names them: neither Bolt nor bolt-seo falls back when the template is missing, and every page fails to render. They are identical in every project, so the removal later is the same everywhere:

| File | Role |
| :--- | :--- |
| `_canonical.macros.twig` | The correction. On a listing or record route it drops a singleton's record slug and a listing's query. A canonical set explicitly is kept as written. |
| `_canonical.twig` | `<link rel="canonical">`, Bolt's `canonical_template`. |
| `_seo_metatags.twig` | bolt-seo's `templates.meta`. It includes the stock `@seo/_metatags.html.twig` with `canonical` replaced, so upstream template changes still arrive. |

Point Bolt and bolt-seo at them:
```yaml
# config/bolt/config.yaml
# Workaround until https://github.com/bolt/core/pull/3735 is released, see
# partials/_canonical.macros.twig in the theme.
canonical_template: 'partials/_canonical.twig'
```
```yaml
# config/extensions/appolo-boltseo.yaml
# Renders bolt-seo's own template with og:url and twitter:url set to the same URL as
# <link rel="canonical">, until https://github.com/bolt/core/pull/3735 is released.
templates:
  meta: partials/_seo_metatags.twig
```

Rules:
* **Never fix a mismatch in the admin.** The SEO field's "Canonical Link" (and `override_default.<route>.canonical`) is meant for a page that really belongs under another URL. With the override it sets `<link rel="canonical">`, `og:url` and `twitter:url` alike, as written. Without the override it sets only `og:url`/`twitter:url`. Typing the clean URL into every record per locale would hard-code the host, miss listings (no record) and go stale.
* **Pages that include `@seo/_metatags.html.twig` themselves** pass `canonical: seo.canonical()` (section 1.5). On their static routes the canonical needs no correction, and the line survives the removal.
* **Check it:** with `bin/console cache:pool:clear cache.app` first (Bolt caches canonical links for 60 seconds, and `cache:clear` doesn't empty that pool), compare `<link rel="canonical">` with `og:url` on a singleton page, its translation and a listing. They must be equal, slugless and without `?order=…`, and the URL must answer 200.

**Removing it** once the project runs a bolt/core release with PR #3735: delete the three partials, `canonical_template` from `config/bolt/config.yaml` and `templates` from `config/extensions/appolo-boltseo.yaml`, then run the check above again. Until then the macro is a safe no-op on an already clean canonical, so a forgotten copy renders the same URLs. After the removal the admin "Canonical Link" sets only `og:url` again, so leave it empty.

---

## 2. Vondry/bolt-sitemap Setup

Official repository: [Vondry/bolt-sitemap](https://github.com/Vondry/bolt-sitemap) (package [`tomvondracek/bolt-sitemap`](https://packagist.org/packages/tomvondracek/bolt-sitemap))

It replaces `bolt/sitemap-extension` and needs **no theme template**. Out of the box it lists:
- one `<url>` per page and locale with reciprocal `hreflang` alternates and `x-default`;
- singletons at their slugless URL (`/kontakt`, not `/kontakt/kontakt-2`);
- listing pages with alternates on the listing route;
- the static pages (`TemplateController` routes, section 2.4);
- images, and an honest `<lastmod>` (none where no date is known).

Pages that bolt-seo marks `noindex` or gives another canonical URL are left out. `/sitemap.xml` is a sitemap index with child sitemaps:
- `/sitemap-main.xml`: homepage, singletons and static pages;
- `/sitemap-<contenttype>.xml`: one per ContentType.

### 2.1 Install via Composer
```bash
composer require tomvondracek/bolt-sitemap:^1.0
```
`bolt/sitemap-extension` must not be installed: both serve `/sitemap.xml`, and the package declares a conflict. To migrate an existing project, see section 2.6.

### 2.2 Copy Config Recipes
```bash
php bin/console extensions:configure --with-config
```
This generates:
* `config/extensions/tomvondracek-sitemap.yaml`
* `config/packages/extension_bolt-sitemap.yaml` (cache invalidation on content changes, `@bolt-sitemap` Twig namespace)
* `config/routes/extension_bolt-sitemap.yaml` (`/sitemap.xml`, `/sitemap-<name>.xml`)

### 2.3 Configure the Extension
Replace the generated `config/extensions/tomvondracek-sitemap.yaml` with `examples/tomvondracek-sitemap.yaml`. The defaults are right for most sites, and the example documents every key a project usually sets:

```yaml
# config/extensions/tomvondracek-sitemap.yaml
listings: true                # listing pages of ContentTypes that show published records
exclude_contenttypes: []      # ContentTypes whose records are left out (their listing stays)
exclude_listings: []          # ContentTypes whose listing page is left out
taxonomies: []                # e.g. [categories, tags]

# Static pages (section 2.4): every TemplateController route without parameters.
static_routes: true
exclude_static_routes: []     # route names, e.g. [thank_you, thank_you_locale]
static_route_lastmod: {}      # route name => date of the page's last content change

images:
  enabled: true
  fields: {}                  # ContentType => image/imagelist fields; default: the record's first image

seo:
  respect_noindex: true       # leave out pages bolt-seo marks noindex or canonicalizes elsewhere

human_view:
  stylesheet: false           # browsers show the raw XML; true = styled list (/sitemap.css)
  script: false               # true = table with links (/sitemap-ui.js)
```

* **Images:** set `images.fields.<contenttype>` when the first image is not the one that represents the page. A decorative badge or icon is a bad pick; use `homepage: []` to list none, or `products: [image, gallery]` to list a gallery.
* **`exclude_contenttypes` / `exclude_listings`:** use them only for pages that exist but should not be in search, such as internal listings. Viewless ContentTypes, `viewless_listing: true` and `hide_listing_from_xml_sitemap: true` are already honoured.
* **Don't override the sitemap templates** to fix URLs. The fixes the old `extensions/sitemap.xml.twig` override carried are built in. If a URL must be added or dropped, use the extension's `SitemapUrlsEvent` (see its README).

### 2.4 Static Pages Are in the Sitemap Through Their Routes
> [!IMPORTANT]
> Static pages (`static-pages/<name>.twig` in the theme, e.g. the privacy policy `static-pages/gdpr.twig`) have no ContentType. The sitemap finds them only through their `TemplateController` routes in `config/routes.yaml` (WORKFLOWS.md, Static Routes). Every static page needs:
> 1. **a route without parameters** pointing at its template (`templateName: static-pages/<name>.twig`), above the `frontend:` import. That route is the page's URL in the default locale;
> 2. **on a multilingual site, the `<name>_locale` twin** with path `/{_locale}/…`, `requirements: { _locale: '%app_locales%' }` and the **same `templateName`**. The sitemap pairs the two by template and lists `/en/…`, `/de/…` as the page's other languages with `hreflang` alternates. A twin with another template is a different page, and a page without a twin is listed in the default locale only.

```yaml
# config/routes.yaml (above the frontend: import)
privacy:
  path: /zasady-ochrany-osobnich-udaju
  defaults:
    _controller: Bolt\Controller\Frontend\TemplateController::template
    templateName: static-pages/gdpr.twig

privacy_locale:
  path: /{_locale}/zasady-ochrany-osobnich-udaju
  requirements: { _locale: '%app_locales%' }
  defaults:
    _controller: Bolt\Controller\Frontend\TemplateController::template
    templateName: static-pages/gdpr.twig
```

Rules:
* **Keep `static_routes: true`** whenever the theme has `static-pages/`. Never list static pages by hand: a new route appears in the sitemap automatically.
* **Pages that must not be indexed** (thank-you pages, form confirmations) belong in `exclude_static_routes` (both route names), or get `robots: 'noindex, follow'` in bolt-seo's `override_default.<route name>`. The sitemap follows that too, so the page's `<meta name="robots">` and the sitemap agree.
* **`<lastmod>`:** a static page has none by default, because its template's file time is the time of the last deploy, not of a content change. To give one, set `static_route_lastmod: { privacy: 2026-10-01 }` and update the date when the page's text changes.
* Redirect routes (`RedirectController`) and routes with parameters are never listed.

### 2.5 Name the Sitemap in `robots.txt`

Crawlers look for the sitemap in `robots.txt`; without the line it is found only through Search Console. `public/robots.txt` (Symfony's default file, served by Apache as a static file) gets one absolute line — the `Sitemap:` directive does not accept a relative path:

```text
User-agent: *

Sitemap: https://example.cz/sitemap.xml
```

Use the canonical host (`BOLT_CANONICAL`). The line names the index; crawlers follow it to the child sitemaps. Don't serve a static `public/sitemap.xml`: Apache would deliver it before Bolt sees the request.

### 2.6 Migrating a Project from `bolt/sitemap-extension`
1. `composer remove bolt/sitemap-extension`, then sections 2.1–2.3.
2. Delete the theme override (`extensions/sitemap.xml.twig` or `_sitemap.xml.twig`) and `config/extensions/bolt-sitemapextension.yaml`.
3. Delete a hand-written list of static routes from the old override. Check section 2.4 instead: every static page has its route and, on multilingual sites, its `_locale` twin with the same template.
4. Check that `config/packages/extension_*.yaml` and `config/routes/extension_*.yaml` of the other extensions are still there. When Bolt's post-update script can't boot the container in the middle of the swap, it removes them; `php bin/console extensions:configure` restores them.
5. Compare the old and the new URL set. Expect the same pages, plus one `<url>` per extra locale, and without duplicate listing entries.

---

## 3. Vondry/bolt-llms-txt Setup

Official repository: [Vondry/bolt-llms-txt](https://github.com/Vondry/bolt-llms-txt) (package `tomvondracek/bolt-llms-txt`)

### 3.1 Install via Composer
```bash
composer require tomvondracek/bolt-llms-txt:^1.1
```

### 3.2 Copy Config Recipes
```bash
php bin/console extensions:configure --with-config
```
This generates:
* `config/extensions/tomvondracek-llmstxt.yaml`
* `config/packages/extension_bolt-llms-txt.yaml`
* `config/routes/extension_bolt-llms-txt.yaml`

### 3.3 Configure the Extension
In `config/extensions/tomvondracek-llmstxt.yaml`:
```yaml
# config/extensions/tomvondracek-llmstxt.yaml
enabled: true
template: '@theme/extensions/llms.txt.twig'
locale: en # 'en' when the site has English (AI crawlers read it best); otherwise leave empty for the default locale
max_age: 3600
```

### 3.4 Create `llms.txt.twig` in the Theme Extensions Folder
Place the template in the theme's extensions folder:
`public/theme/<themename>/extensions/llms.txt.twig`.

### 3.5 Specification Formatting Guidelines ([llmstxt.org](https://llmstxt.org/))
> [!IMPORTANT]
> The reference implementation parser on [llmstxt.org](https://llmstxt.org/) enforces strict syntactic rules:
> 1. **File must start with an H1 header:** `# <Sitename>`
> 2. **Immediate single-line blockquote:** `> <Brief summary of site/business>`
> 3. **Introductory Context:** Free Markdown with NO H2 or H3 headers (use bold labels like `**Contact:**`).
> 4. **H2 Sections:** Every H2 section (`## Section Title`) MUST contain ONLY bullet items in `- [Title](URL): Description` format. Any non-list lines inside an H2 block fail parser validation.
> 5. **`## Optional` Section:** Standardized bucket for secondary pages, external registers, and the sitemap.
> 6. **Twig Autoescaping:** The `.txt.twig` extension switches autoescaping off. Always run CMS values through the extension's provided filters: `|html_to_text`, `|markdown_label`, and `|markdown_url`.

### 3.6 Production Template Blueprint
The template below uses the field names of the `bolt-contenttypes` blueprint (`homepage.hero_title`, `homepage.hero_intro`, `settings.email`, `settings.phone`, `articles.teaser`) with `theme.yaml` contact fallbacks; map them to the site's ContentTypes. The extension's own generic template (`vendor/tomvondracek/bolt-llms-txt/templates/llms.txt.twig`) lists every listable ContentType automatically and is a good reference for larger sites.
```twig
{# public/theme/<themename>/extensions/llms.txt.twig #}
{#- llms.txt (https://llmstxt.org) — served at /llms.txt by tomvondracek/bolt-llms-txt
    Placed in: public/theme/<theme_name>/extensions/llms.txt.twig

    Layout follows the llmstxt.org specification:
    1. H1 title (# Sitename)
    2. A single-line blockquote (> Summary)
    3. Markdown body describing the project, services, and contacts (NO H2/H3 headings here)
    4. H2 sections (## Section Name) containing ONLY bullet items in "- [Title](URL): Description" format.
       The reference parser fails on any other line inside an H2 section.
    5. An optional ## Optional section for secondary resources and sitemap.

    Field names match the bolt-contenttypes blueprint: `homepage` singleton (hero_title,
    hero_intro), `settings` singleton (email, phone) and `articles` (teaser). Contact
    fallbacks come from theme.yaml (contact.*). Adapt the names to the site's ContentTypes.

    Autoescaping is off for .txt templates; every CMS value goes through html_to_text,
    markdown_label or markdown_url. Variables: today (Y-m-d), now, baseUrl, locale.
-#}
{%- autoescape false -%}
{#- setcontent throws for an unknown ContentType: query only the ones the site defines. -#}
{%- set homepage = null -%}
{%- set settings = null -%}
{%- set articles = [] -%}
{%- if config.get('contenttypes/homepage') -%}{%- setcontent homepage = 'homepage' -%}{%- endif -%}
{%- if config.get('contenttypes/settings') -%}{%- setcontent settings = 'settings' -%}{%- endif -%}
{#- `page 1`, so `?page=` in the URL can never select another page of records. -#}
{%- if config.get('contenttypes/articles') -%}{%- setcontent articles = 'articles' limit 50 page 1 -%}{%- endif -%}
{#- `??` keeps the template working when a singleton record does not exist yet. -#}
{%- set email = (settings.email ?? '')|default(config.get('theme/contact/email')) -%}
{%- set phone = (settings.phone ?? '')|default(config.get('theme/contact/phone')) -%}
{%- set hero_title = homepage.hero_title ?? '' -%}
{%- set hero_intro = homepage.hero_intro ?? '' -%}
{%- set address = config.get('theme/contact/address') -%}

{%- set summary = (hero_intro|default(hero_title)|default(config.get('general/payoff')))|html_to_text(200) -%}

# {{ config.get('general/sitename')|html_to_text }}

{% if summary is not empty %}
> {{ summary }}

{% endif %}
This file is generated from the website's content management system; the facts below are what the website showed on {{ today }}.

{% if hero_title is not empty %}
**About:**
- {{ hero_title|html_to_text }}
{% endif %}

{% if email or phone or address %}
**Contact:**
{% if email %}
- Email: {{ email|html_to_text }}
{% endif %}
{% if phone %}
- Phone: {{ phone|html_to_text }}
{% endif %}
{% if address %}
- Address: {{ address|html_to_text }}
{% endif %}
{% endif %}

## Website pages

- [Homepage]({{ baseUrl }}/): the website's main page.

{% if articles is not empty %}
## Articles

{% for article in articles %}
- [{{ article|title|markdown_label }}]({{ article|link(true)|markdown_url }}){{ article.teaser is defined and article.teaser is not empty ? ': ' ~ article.teaser|html_to_text(200) }}
{% endfor %}

{% endif %}
## Optional

- [Sitemap]({{ baseUrl }}/sitemap.xml): XML sitemap of all published pages.
{% endautoescape %}
```

---

## 4. Automated Verification Script

To verify that all three extensions and their theme overrides are correctly wired:

```bash
vendor/tomvondracek/bolt-skills/skills/bolt-extension-setup/scripts/verify.sh
```

### What the script verifies:
1. **Composer packages:** Verifies `appolodev/bolt-seo`, `tomvondracek/bolt-sitemap`, and `tomvondracek/bolt-llms-txt` are installed. Fails when `bolt/sitemap-extension` is still installed.
2. **Configuration files:** Confirms `appolo-boltseo.yaml`, `tomvondracek-sitemap.yaml`, and `tomvondracek-llmstxt.yaml` exist under `config/extensions/`. Warns about a leftover `bolt-sitemapextension.yaml`.
3. **Recipes:** Checks package and route configurations in `config/packages/` and `config/routes/` (bolt-seo, bolt-sitemap, bolt-llms-txt).
4. **ContentType Schema:** Validates that `type: seo` is present in `config/bolt/contenttypes.yaml` (and recommends `seo_field: &seo_field`).
5. **Theme SEO Integration:** Checks `<head>` in theme layouts for `{{ seo.metatags() }}`.
6. **Theme Extensions Directory:**
   * Warns about a leftover sitemap override (`extensions/sitemap.xml.twig` or `_sitemap.xml.twig`) from `bolt/sitemap-extension` (section 2.6).
   * **Static pages (section 2.4):** fails when a `static-pages/*.twig` template has no `TemplateController` route, because it is then neither served nor in the sitemap. On a multilingual site, warns when its `_locale` twin is missing, and warns when `static_routes: false` hides the static pages.
   * Verifies `llms.txt.twig` exists in `public/theme/<themename>/extensions/` and follows the `llmstxt.org` layout.
   * Warns when `public/robots.txt` is missing or has no absolute `Sitemap: …/sitemap.xml` line (section 2.5), or when a static `public/sitemap.xml` shadows the extension.
7. **Canonical URL override (section 1.6, until bolt/core PR #3735 is released):**
   * Fails when `partials/_canonical.twig`, `_canonical.macros.twig` or `_seo_metatags.twig` is missing, or when `canonical_template` / `templates.meta` doesn't point at them. Warns when a copy differs from the skill example.
   * Warns when a theme template passes `canonical: app.request.uri` to the meta tags (section 1.5), or `appolo-boltseo.yaml` still has the dead `meta_robots` / `allow` keys (section 1.3).
