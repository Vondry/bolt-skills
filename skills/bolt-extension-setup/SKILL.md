---
name: bolt-extension-setup
description: >-
  Use this skill whenever installing, configuring, or verifying the trio of essential
  Bolt CMS extensions: AppoloDev/bolt-seo (SEO meta fields and tags),
  bolt/sitemap-extension (with custom singleton slug override), and
  Vondry/bolt-llms-txt (llmstxt.org dynamic endpoint).
---

# Essential Bolt CMS Extensions Setup & Verification Guide

Every modern production website built with Bolt CMS requires three foundational extensions for discoverability, search engine indexing, and AI crawler readiness:

1. **`AppoloDev/bolt-seo` (`appolodev/bolt-seo`)**: Structured SEO meta fields (`type: seo`), OpenGraph tags, JSON-LD, and robots meta tags.
2. **`bolt/sitemap-extension` (`bolt/sitemap-extension`)**: XML sitemap generation with an essential theme override addressing singleton slug routing (PR #5 workaround).
3. **`Vondry/bolt-llms-txt` (`tomvondracek/bolt-llms-txt`)**: Serves `/llms.txt` dynamically from CMS content adhering strictly to the [llmstxt.org](https://llmstxt.org/) specification.

This skill provides the end-to-end installation steps, architecture patterns, theme templates, and an automated verification script.

---

## 1. AppoloDev/bolt-seo Setup

Official repository: [AppoloDev/bolt-seo](https://github.com/AppoloDev/bolt-seo)

### 1.1 Install via Composer
```bash
composer require appolodev/bolt-seo:^2.2
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

meta_robots: "index, follow"
```

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
        keywords: __('page.seo.keywords')
    } %}
{% endblock seo %}
```

---

## 2. bolt/sitemap-extension Setup & Singleton Override

Official repository: [bolt/sitemap-extension](https://github.com/bolt/sitemap-extension)

### 2.1 Install via Composer
```bash
composer require bolt/sitemap-extension:^2.0
```

### 2.2 Copy Config Recipes
```bash
php bin/console extensions:configure --with-config
```
This generates `config/extensions/bolt-sitemapextension.yaml`.

### 2.3 The Singleton Slug Bug & PR #5 Workaround
> [!IMPORTANT]
> Until [bolt/sitemap-extension Pull Request #5](https://github.com/bolt/sitemap-extension/pull/5) is merged upstream, the native sitemap template has a critical bug:
> 1. It appends the record slug to singleton URLs (e.g. `/contact/contact` instead of `/contact`).
> 2. It outputs duplicate listing entries for singletons.
> 3. It creates broken alternate language links (`xhtml:link`) for localized singletons.
>
> **The Workaround:** Configure the extension to use a custom XML template in your theme's extensions directory.

### 2.4 Configure the Override Template
In `config/extensions/bolt-sitemapextension.yaml`:
```yaml
# config/extensions/bolt-sitemapextension.yaml
show_listings: true
limit: 10000

templates:
  xml: "@theme/extensions/sitemap.xml.twig"
  xsl: "@sitemap/sitemap.xsl"
```

### 2.5 Place Template Override in Theme
Create the file `public/theme/<themename>/extensions/sitemap.xml.twig` with the following content:

```twig
{# public/theme/<themename>/extensions/sitemap.xml.twig #}
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>
<urlset
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd"
    xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
>
    {%- set lastContentTypeSlug = null -%}
    {%- for record in records -%}
        {%- set isListing = false -%}
        {%- set contentType = record.definition -%}
        {%- set isSingleton = contentType.singleton -%}
        {%- set isHomepage = (record|link) == '/' -%}
        {# Singletons are served at their slugless page; skip duplicate listings #}
        {% if showListings and not isSingleton %}
            {%- if lastContentTypeSlug != contentType.slug and not contentType.viewless_listing and contentType.slug not in excludeListings -%}
                {%- if (contentType.hide_listing_from_xml_sitemap is not defined) or (not contentType.hide_listing_from_xml_sitemap) -%}
                    {%- set lastContentTypeSlug = contentType.slug -%}
                    {%- set url = path('listing', { contentTypeSlug: contentType.slug }) -%}
                    {%- set priority = 0.8 -%}
                    {%- set isListing = true -%}
                    {{ block('urlBlock') }}
                    {%- set isListing = false -%}
                {%- endif -%}
            {%- endif -%}
        {%- endif -%}
        {%- if record|link is not empty and contentType.slug not in excludeContentTypes -%}
            {%- set url = record|link -%}
            {# Strip trailing /{slug} on singletons so URL matches the slugless page #}
            {%- if isSingleton and not isHomepage and url ends with ('/' ~ record.slug) -%}
                {%- set url = url|split('/')|slice(0, -1)|join('/') -%}
            {%- endif -%}
            {%- set priority = 0.8 -%}
            {{ block('urlBlock') }}
        {%- endif -%}
    {%- endfor -%}

    {%- if taxonomies is defined -%}
        {%- for taxonomy in taxonomies -%}
            {%- if taxonomy|link is not empty -%}
                {%- set url = taxonomy|link -%}
                {%- set priority = 0.7 -%}
                {{ block('urlBlock') }}
            {%- endif -%}
        {%- endfor -%}
    {%- endif -%}
</urlset>

{%- block urlBlock %}
    {%- if url is defined -%}
        <url>
        {% block loc -%}
            <loc>{{ absolute_url(url) }}</loc>
        {% endblock loc -%}
        <changefreq>weekly</changefreq>
        <lastmod>{{ (record.modifiedAt is defined ? record.modifiedAt : 'now')|date('Y-m-d\\TH:i:sP') }}</lastmod>
        {% block priority -%}
            <priority>{{ url == '/' ? 1 : priority }}</priority>
        {% endblock priority -%}
        {% if record is defined and record.definition.locales.all|length > 1 %}
            {% for locale in record.definition.locales %}
                {%- set altUrl = record|link(true, locale) -%}
                {# Strip trailing /{slug} on alternate singleton URLs #}
                {%- if (record.definition.singleton or isListing) and altUrl ends with ('/' ~ record.getSlug(locale)) -%}
                    {%- set altUrl = altUrl|split('/')|slice(0, -1)|join('/') -%}
                {%- endif -%}
                <xhtml:link rel="alternate" hreflang="{{ locale }}" href="{{ altUrl }}"/>
            {% endfor %}
        {% endif %}
        {% if record is defined and record|image is not empty and not isListing -%}
            <image:image>
                <image:loc>{{ absolute_url(record|image) }}</image:loc>
                {% if record.image.alt|default() -%}
                    <image:title><![CDATA[{{ record.image.alt }}]]></image:title>
                {% endif -%}
            </image:image>
        {% endif -%}
        </url>
    {% endif -%}
{% endblock urlBlock -%}
```

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
locale: en # Keep set to 'en' so AI models and crawlers receive English responses
max_age: 3600
```

### 3.4 Create `llms.txt.twig` in the Theme Extensions Folder
Place the template in the **same extensions folder** as the sitemap override:
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
- [{{ article|title|markdown_label }}]({{ article|link(true) }}){{ article.teaser is defined and article.teaser is not empty ? ': ' ~ article.teaser|html_to_text(200) }}
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
vendor/vondry/bolt-skills/skills/bolt-extension-setup/scripts/verify.sh
```

### What the script verifies:
1. **Composer packages:** Verifies `appolodev/bolt-seo`, `bolt/sitemap-extension`, and `tomvondracek/bolt-llms-txt` in `composer.json`.
2. **Configuration files:** Confirms `appolo-boltseo.yaml`, `bolt-sitemapextension.yaml`, and `tomvondracek-llmstxt.yaml` exist under `config/extensions/`.
3. **Recipes:** Checks package and route configurations in `config/packages/` and `config/routes/`.
4. **ContentType Schema:** Validates that `type: seo` is present in `config/bolt/contenttypes.yaml` (and recommends `seo_field: &seo_field`).
5. **Theme SEO Integration:** Checks `<head>` in theme layouts for `{{ seo.metatags() }}`.
6. **Theme Extensions Directory:**
   * Verifies `sitemap.xml.twig` exists in `public/theme/<themename>/extensions/` and contains the singleton slug fix.
   * Verifies `llms.txt.twig` exists in `public/theme/<themename>/extensions/` and follows the `llmstxt.org` layout.
