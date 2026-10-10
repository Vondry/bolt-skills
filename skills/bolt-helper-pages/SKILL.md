---
name: bolt-helper-pages
description: >-
  Use this skill whenever creating, styling, or validating helper and error pages
  in Bolt CMS: 404 (Not Found), 403 (Forbidden), 500 (Internal Server Error), and
  503 (Maintenance Mode). Enforces configuration mappings in config/bolt/config.yaml,
  dual-base layout strategy, zero-database 500 safety rule, noindex SEO directives,
  and bespoke brand-aligned visual scenes.
---

# Bolt CMS Helper & Error Pages Architecture

Bolt CMS provides configurable fallbacks for HTTP error states and planned maintenance. Instead of generic unbranded screens or blank error outputs, production websites require cohesive, helpful, and visually engaging helper screens.

This skill outlines the unified architectural pattern, configuration linkage, safety guidelines, and visual metaphor guidelines used across production Bolt CMS themes.

---

## 1. Master Configuration (`config/bolt/config.yaml`)

Bolt looks up error and maintenance templates in `config/bolt/config.yaml`. Map each condition to a template within the active theme's `helper-pages/` directory:

```yaml
# config/bolt/config.yaml

# The default content for the "Not Found" (404) page.
notfound: [ 'helper-pages/notfound.404.twig' ]

# Toggle maintenance mode on or off.
# Note: Logged-in editors will still see the website normally. Test via Incognito mode.
maintenance_mode: false

# The default for the "Maintenance mode" (503) page.
maintenance: [ 'helper-pages/maintenance.503.twig' ]

# The default content for the "Forbidden" (403) page.
forbidden: [ 'helper-pages/forbidden.403.twig' ]

# The default content for the "Internal Server Error" (500) page.
# Note: Active only in APP_ENV=prod. Must stay simple with zero database queries!
internal_server_error: [ 'helper-pages/internal-server-error.500.twig' ]
```

## 2. Single-Locale Limitation (Pending bolt/core#3726)

> [!IMPORTANT]
> **Helper and error pages can currently be created in only ONE locale (the default site locale).**
>
> In stock Bolt CMS, the error directives in `config/bolt/config.yaml` (`notfound`, `maintenance`, `forbidden`, `internal_server_error`) do not accept per-locale mappings. Furthermore, when an unrouted 404 or 403 occurs (such as hitting `/en/non-existent-page` on a Czech-default site), Symfony's `LocaleListener` does not run for the unrouted URL, causing Bolt's `ErrorController` to render the error template strictly in the system default locale.
>
> **Pending Core Enhancement:**
> * Pull Request: [bolt/core#3726 – Propagate current locale to custom 404/403/500 error pages](https://github.com/bolt/core/pull/3726)
> * **Status:** Until PR #3726 is merged and available in your Bolt CMS release, helper pages can only be created for a single locale.
> * **Best Practice:** Author your helper pages in the primary/default language of the website (or craft a clean bilingual layout if multi-language coverage is essential before PR #3726 is merged). Do not configure separate language subdirectories in `config/bolt/config.yaml`.
>
> Once PR #3726 is available in core, `ErrorController` will propagate the URL's locale to custom error pages, enabling localized `__('...')` strings, `htmllang()`, and language-aware navigation links.

---

## 3. The Dual-Base Layout Strategy

In production themes (`public/theme/<themename>/helper-pages/`), helper pages fall into two distinct operational states:

```text
public/theme/<themename>/helper-pages/
├── _helper_template_with_master.twig     # Base for 404, 403 (preserves nav & footer)
├── _helper_template_without_master.twig  # Standalone base for 503 and 500 (no header/footer, no database)
├── _helper_scene.twig                   # Reusable visual scene component
├── _helper_scene_styles.twig            # Isolated scoped styling & animations
├── notfound.404.twig                    # 404 error page
├── forbidden.403.twig                   # 403 error page
├── internal-server-error.500.twig       # 500 error page
└── maintenance.503.twig                 # 503 maintenance page
```

### A. Layout with Master (`_helper_template_with_master.twig`)
* **Used by:** `notfound.404.twig` and `forbidden.403.twig`.
* **Rationale:** The application is functioning normally. Preserving the site's header, navigation, and footer allows visitors to easily recover, search, or navigate to other sections.
* **Parent:** `partials/_master.twig` from `bolt-theme-init` — the shared layout shell with the `seo`, `head` and `main` blocks (Integration Contract in `WORKFLOWS.md`).
* **SEO Directive:** Overrides the SEO block to enforce `<meta name="robots" content="noindex, follow">`, ensuring search engines do not index broken URLs.

```twig
{# public/theme/<themename>/helper-pages/_helper_template_with_master.twig #}
{% extends 'partials/_master.twig' %}

{% block seo %}
    <title>{{ title|default('Chyba · ' ~ config.get('general/sitename')) }}</title>
    <meta name="robots" content="noindex, follow">
{% endblock seo %}

{% block main %}
{% endblock main %}
```

### B. Layout without Master (`_helper_template_without_master.twig`)
* **Used by:** `maintenance.503.twig` and `internal-server-error.500.twig`.
* **Rationale:** During scheduled maintenance or deployment, database tables, search indexes, or APIs may be migrating. Normal header navigation links or search forms would lead to secondary errors. A self-contained standalone page (`<!DOCTYPE html>`) provides an elegant offline experience while displaying direct fallback communication channels (phone, email).
* **Why the 500 page uses it too:** a 500 is often caused by a failing database or cache. The with-master layout renders the header and footer containers (`menu_array()`, possibly `{% setcontent %}`), which would fail with the same cause and turn the error page itself into a white screen.

```twig
{# public/theme/<themename>/helper-pages/_helper_template_without_master.twig #}
<!DOCTYPE html>
<html lang="{{ htmllang() }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title|default('Probíhá údržba · ' ~ config.get('general/sitename')) }}</title>
    <meta name="robots" content="noindex, follow">
    <link rel="stylesheet" href="{{ asset('css/index.css') }}?v={{ theme.assets_version|default('1.0') }}">
    <script defer src="{{ asset('js/app.js') }}?v={{ theme.assets_version|default('1.0') }}"></script>
    {% block head %}{% endblock head %}
</head>
<body class="helper-standalone-page">
<main class="helper-standalone-main">
    {% block mainHelper %}{% endblock mainHelper %}
</main>
</body>
</html>
```

---

## 4. Strict Zero-Bundle-Pollution Rule for Tailwind CSS

> [!CAUTION]
> **Classes used specifically on helper pages MUST NOT end up in the production app bundle (`css/index.css`)!**
>
> 99.9% of visitors browse normal public pages and will never encounter an error screen. If helper pages introduce one-off Tailwind utilities (e.g. `text-[13rem]`, `w-[32rem]`, custom keyframe animations, arbitrary colors), Tailwind will scan and compile those classes into the main site bundle, needlessly increasing CSS file weight for every single visitor!

### The Two-Layer Protection Strategy:

#### Layer 1: Self-Contained Scoped CSS in `_helper_scene_styles.twig`
* **Rule:** All scene layout rules, watermarks (`.helper-ghost`), cards, progress bars, and animations **must be declared inside a `<style>` block in `_helper_scene_styles.twig`** using semantic or BEM class names (`.helper-*`, `.term-*`, `.nf-*`).
* **Why:** Because `_helper_scene_styles.twig` is injected via `{% block head %}` ONLY on helper pages, this CSS is delivered **on-demand exclusively to visitors seeing an error**. It never touches the main app CSS file.
* **Buttons & Utilities:** Helper templates should only reference existing global theme buttons (e.g. `.btn-primary` or scoped `.helper-btn--primary`) and CSS design tokens (`var(--color-accent)`). Never write arbitrary one-off Tailwind utility classes in helper Twig files.

#### Layer 2: Explicit Tailwind Scanner Exclusion
Configure Tailwind to explicitly ignore `helper-pages/`:

* **Tailwind CSS v4 (`public/theme/<themename>/css/tailwind/index.css`):**
  Add an exclusion directive:
  ```css
  /* Exclude helper pages from the global build to prevent one-off classes in the app bundle */
  @source not "../../helper-pages";
  ```

### Theme Token Inheritance & CSS Delivery Architecture

#### 1. How Theme Tokens are Imported/Used (No `@import` Needed)
* **Do NOT attempt to `@import` the theme CSS or SCSS inside helper templates.**
* Both base templates (`_helper_template_with_master.twig` via `partials/_master.twig`, and `_helper_template_without_master.twig` directly) include the main compiled site stylesheet in `<head>`:
  ```html
  <link rel="stylesheet" href="{{ asset('css/index.css') }}">
  ```
* Because Tailwind CSS (v3 and v4) compiles your theme design tokens into standard CSS Custom Properties on the global `:root` scope (e.g. `--color-accent`, `--color-canvas`, `--color-surface`, `--color-ink`, `--color-stroke`, `--font-display`, `--radius-lg`), **these variables are automatically available everywhere on the page**.
* The helper scene CSS in `_helper_scene_styles.twig` simply references these custom properties directly with graceful fallbacks:
  ```css
  .helper-card {
      background-color: var(--color-surface, #ffffff);
      border: 1px solid var(--color-stroke, rgba(0, 0, 0, 0.08));
  }
  .helper-btn--primary {
      background-color: var(--color-accent, #0f172a);
      color: #ffffff;
  }
  ```

#### 2. Why an Inline `<style>` Block in a Twig Partial vs. a Separate `.css` File?
Instead of creating a separate compiled `css/helper-pages.css` file in your asset pipeline, styles are placed directly in `helper-pages/_helper_scene_styles.twig` inside an inline `<style>` tag and injected via `{% block head %}`:
1. **Zero build pipeline overhead:** No need to configure an extra entry point or output build step in Vite, Webpack Encore, or Tailwind CLI.
2. **Zero extra HTTP requests:** The helper styles arrive inline with the HTML document in a single HTTP response.
3. **Outage & maintenance resilience:** If a 500 error or 503 maintenance mode is triggered during asset pipeline deployment, CDN cache purging, or misconfigured static symlinks, a separate external CSS file could fail to load (returning a 404). An inline `<style>` tag delivered with the Twig template will **never fail to load or 404**.
4. **100% on-demand payload:** Regular visitors never download a single byte of helper page styles; only users who actually encounter an error receive the inline styles.

---

## 5. The 500 Safety Rule: Zero Database Lookups

> [!CAUTION]
> In `APP_ENV=prod`, Bolt renders `internal-server-error.500.twig` when an uncaught exception occurs.
>
> **CRITICAL RULE:** Never execute `{% setcontent %}`, database queries, or external API calls inside `internal-server-error.500.twig` or any template it includes.
>
> **Why?** If the server error was caused by a database failure, running `{% setcontent %}` inside the 500 error handler triggers a secondary unhandled fatal exception, crashing the error page itself into an ugly white screen.
>
> Keep `internal-server-error.500.twig` strictly static or using safe request parameters (`app.request.uri`), and let it extend `_helper_template_without_master.twig`: the rule covers every template the 500 page renders, including the header and footer containers a with-master layout would pull in.

---

## 6. Brand-Aligned Visual Metaphor Pattern

Helper pages should not look generic. Use `_helper_scene.twig` to weave the client's brand into the visual presentation:

| Client Domain | Visual Metaphor | 404 (Not Found) | 403 (Forbidden) | 500 (Server Error) | 503 (Maintenance) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bakery / café** | The **Display Counter** | Empty tray with a crumb-covered label (*"Tenhle koláč už je pryč"*) | Kitchen door with a *"Jen pro personál"* sign | Smoking oven with the alarm light on (*"Něco se připálilo"*) | *"Pečeme"* sign on the door, dough rising as an indeterminate progress bar |
| **Library / bookshop** | The **Shelf** | Gap on the shelf with an empty catalogue card (*"Kniha nenalezena"*) | Rare-books glass cabinet with a key lock (*"Jen se svolením"*) | Toppled stack of books | *"Inventura"* notice with opening hours and a quiet progress bar |
| **Logistics / shipping** | The **Parcel** | Parcel with an unreadable address label (*"Adresát neznámý"*) | Sealed parcel stamped *"Neotvírat"* | Crushed parcel on the conveyor belt with an urgent phone contact | Paused sorting line with an indeterminate progress bar |

### Adapting to New Projects
When building for a new client (e.g. dental clinic, fitness studio, e-shop):
1. **Choose an iconic physical metaphor** from their industry (e.g. appointment card, locker with a combination lock, shopping basket).
2. Use `code` (e.g. 404, 403, 500, 503) as an oversized background watermark (`.helper-ghost`).
3. Include clear, friendly next steps: a primary recovery button (`Zpět na úvod`), secondary contact action, and the requested path when applicable (`app.request.pathinfo`).

---

## 7. Template Implementations

### A. 404 Not Found (`notfound.404.twig`)
```twig
{% extends 'helper-pages/_helper_template_with_master.twig' %}

{% set title = '404 – Stránka nenalezena' %}
{% set origin = app.request.scheme ~ '://' ~ app.request.host %}
{% set path = app.request.pathinfo %}

{% block head %}
    {{ include('helper-pages/_helper_scene_styles.twig') }}
{% endblock head %}

{% block main %}
    {{ include('helper-pages/_helper_scene.twig', {
        code: '404',
        eyebrow: 'Chyba 404 · Stránka nenalezena',
        heading: 'Tuto stránku se nám nepodařilo najít',
        lead: 'Odkaz je nejspíš zastaralý nebo obsahuje překlep. Zkuste se vrátit na úvodní stránku — a pokud hledáte něco konkrétního, ozvěte se nám.',
        field_key: 'Požadovaná adresa',
        field_val: origin ~ '<strong>' ~ path|e('html') ~ '</strong>',
        buttons: [
            { label: 'Zpět na úvod', href: '/', variant: 'primary' },
            { label: 'Kontakt', href: '/kontakt', variant: 'secondary' }
        ]
    }) }}
{% endblock main %}
```

### B. 403 Forbidden (`forbidden.403.twig`)
```twig
{% extends 'helper-pages/_helper_template_with_master.twig' %}

{% set title = '403 – Přístup odepřen' %}
{% set origin = app.request.scheme ~ '://' ~ app.request.host %}
{% set path = app.request.pathinfo %}

{% block head %}
    {{ include('helper-pages/_helper_scene_styles.twig') }}
{% endblock head %}

{% block main %}
    {{ include('helper-pages/_helper_scene.twig', {
        code: '403',
        eyebrow: 'Chyba 403 · Přístup odepřen',
        heading: 'Do této části webu nemáte přístup',
        lead: 'Tato sekce není veřejně přístupná. Pokud se domníváte, že byste k ní měli mít přístup, kontaktujte nás.',
        field_key: 'Požadovaná adresa',
        field_val: origin ~ '<strong>' ~ path|e('html') ~ '</strong>',
        buttons: [
            { label: 'Zpět na úvod', href: '/', variant: 'primary' },
            { label: 'Kontakt', href: '/kontakt', variant: 'secondary' }
        ]
    }) }}
{% endblock main %}
```

### C. 500 Internal Server Error (`internal-server-error.500.twig`)
```twig
{#
  500 — Internal Server Error.
  Rendered in APP_ENV=prod mode when an unexpected exception occurs.

  CRITICAL: Kept strictly simple and static. DO NOT call {% setcontent %} or
  rely on database queries here — if the database or cache is failing, any query
  will throw a secondary fatal error!

  That is also why it extends the STANDALONE layout: the with-master layout renders the
  header and footer containers (menu_array(), possibly setcontent), which would fail
  together with whatever caused the error.
#}
{% extends 'helper-pages/_helper_template_without_master.twig' %}

{% set title = '500 – Došlo k chybě' %}

{% block head %}
    {{ include('helper-pages/_helper_scene_styles.twig') }}
{% endblock head %}

{% block mainHelper %}
    {{ include('helper-pages/_helper_scene.twig', {
        code: '500',
        eyebrow: 'Chyba 500 · Chyba serveru',
        heading: 'Něco se pokazilo na naší straně',
        lead: 'Omlouváme se — stránku se nepodařilo načíst. Chyba není na vaší straně. Zkuste požadavek zopakovat za okamžik.',
        buttons: [
            { label: 'Zkusit znovu', href: app.request.uri, variant: 'primary' },
            { label: 'Zpět na úvod', href: '/', variant: 'secondary' }
        ],
        note: 'Pokud potíže přetrvávají, kontaktujte prosím správce webu.'
    }) }}
{% endblock mainHelper %}
```

### D. 503 Maintenance Mode (`maintenance.503.twig`)
```twig
{% extends 'helper-pages/_helper_template_without_master.twig' %}

{% set title = 'Probíhá údržba webu' %}

{% block head %}
    {{ include('helper-pages/_helper_scene_styles.twig') }}
{% endblock head %}

{% block mainHelper %}
    {{ include('helper-pages/_helper_scene.twig', {
        code: '503',
        eyebrow: 'Plánovaná odstávka',
        heading: 'Chvíli pracujeme na webu',
        lead: 'Provádíme krátkou plánovanou údržbu. Za několik minut bude vše zpět v provozu. Děkujeme za trpělivost.',
        progress: true,
        buttons: [
            { label: 'Zavolat +420 123 456 789', href: 'tel:+420123456789', variant: 'primary' },
            { label: 'info@example.cz', href: 'mailto:info@example.cz', variant: 'secondary' }
        ],
        note: 'Telefonicky i e-mailem nás zastihnete běžně bez omezení.'
    }) }}
{% endblock mainHelper %}
```

---

## 8. Automated Verification Script

To verify that all helper pages, configuration mappings, safety rules, and Tailwind bundle isolation are properly established:

```bash
vendor/tomvondracek/bolt-skills/skills/bolt-helper-pages/scripts/verify.sh
```

### What the script verifies:
1. **Config mappings:** Verifies `notfound`, `maintenance`, `forbidden`, and `internal_server_error` in `config/bolt/config.yaml`.
2. **Template files:** Confirms all 4 error templates and the 2 base layouts exist under `public/theme/<themename>/helper-pages/`.
3. **Tailwind Bundle Isolation:** Scans helper templates to confirm they do NOT introduce rogue one-off Tailwind utilities, and checks whether Tailwind build config excludes `helper-pages/` (preventing bundle bloat).
4. **SEO Protection:** Checks for `<meta name="robots" content="noindex, follow">`.
5. **500 Safety Check:** Validates that `internal-server-error.500.twig` contains zero database lookups (`setcontent`) and extends `_helper_template_without_master.twig`.
6. **Twig Syntax:** Runs `php bin/console lint:twig public/theme/<themename>/helper-pages` to guarantee error-free Twig compilation.
