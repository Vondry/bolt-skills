---
name: bolt-helper-pages
description: >-
  Use this skill whenever creating, styling, or validating helper and error pages
  in Bolt CMS: 404 (Not Found), 403 (Forbidden), 500 (Internal Server Error), and
  503 (Maintenance Mode). Enforces configuration mappings in config/bolt/config.yaml,
  dual-base layout strategy, the zero-database rule for the 500 and 503 pages (a
  503 without contact details, numbers or time promises), noindex SEO directives,
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
# A root entrypoint (no '/'): Bolt looks up items with '/' as records first (section 5).
maintenance: [ 'maintenance.503.twig' ]

# The default content for the "Forbidden" (403) page.
forbidden: [ 'helper-pages/forbidden.403.twig' ]

# The default content for the "Internal Server Error" (500) page.
# Note: Active only in APP_ENV=prod. Must stay simple with zero database queries!
# A root entrypoint (no '/'), extending helper-pages/internal-server-error.500.twig (section 5).
internal_server_error: [ 'internal-server-error.500.twig' ]
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

public/theme/<themename>/
├── internal-server-error.500.twig       # one line: extends helper-pages/internal-server-error.500.twig (section 5)
└── maintenance.503.twig                 # one line: extends helper-pages/maintenance.503.twig
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
* **Rationale:** During maintenance or deployment, database tables, search indexes, or APIs may be migrating. Header navigation links or search forms would lead to secondary errors. A self-contained standalone page (`<!DOCTYPE html>`) renders without them and says only that the site is being worked on (section 5).
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

(Content-Security-Policy: inline `<style>` needs `style-src 'unsafe-inline'` or a nonce. The baseline CSP of `bolt-security-hardening` does not restrict styles, and its optional strict policy allows `'unsafe-inline'` for styles, so both work.)
Instead of creating a separate compiled `css/helper-pages.css` file in your asset pipeline, styles are placed directly in `helper-pages/_helper_scene_styles.twig` inside an inline `<style>` tag and injected via `{% block head %}`:
1. **Zero build pipeline overhead:** No need to configure an extra entry point or output build step in Vite, Webpack Encore, or Tailwind CLI.
2. **Zero extra HTTP requests:** The helper styles arrive inline with the HTML document in a single HTTP response.
3. **Outage & maintenance resilience:** If a 500 error or 503 maintenance mode is triggered during asset pipeline deployment, CDN cache purging, or misconfigured static symlinks, a separate external CSS file could fail to load (returning a 404). An inline `<style>` tag delivered with the Twig template will **never fail to load or 404**.
4. **100% on-demand payload:** Regular visitors never download a single byte of helper page styles; only users who actually encounter an error receive the inline styles.

---

## 5. The 500 and 503 Safety Rule: Zero Database Lookups

> [!CAUTION]
> In `APP_ENV=prod`, Bolt renders `internal-server-error.500.twig` when an uncaught exception occurs, and `maintenance.503.twig` while maintenance mode is on.
>
> **CRITICAL RULE:** Never execute `{% setcontent %}`, `menu_array()`, database queries, or external API calls inside `internal-server-error.500.twig`, `maintenance.503.twig` or any template they include (the standalone layout, the scene).
>
> **Why?** The database can be down. A 500 is often caused by a database failure, and maintenance mode is switched on while the database is migrated or restored. Running `{% setcontent %}` there triggers a secondary unhandled fatal exception, crashing the error page itself into an ugly white screen.
>
> Keep both templates strictly static or using safe request parameters (`app.request.uri`), and let them extend `_helper_template_without_master.twig`: the rule covers every template they render, including the header and footer containers a with-master layout would pull in. That also rules out a "site settings" record for contact details on these pages.

### The 503 page says only that the site is being worked on

The maintenance page can be shown without anyone noticing: maintenance mode left on after a deployment, or switched on by a colleague or a script during an outage. Whatever it promises is then wrong for hours. So the 503 page:

- shows **no phone numbers, e-mail addresses or other contact details**: they would need the settings record (a database query) or a copy of CMS data in the template that silently goes stale;
- shows **no times, durations or dates** ("back in 10 minutes", "planned until 14:00") and does not call the outage *planned*;
- shows **no status code**: the `503` watermark means nothing to a visitor. `_helper_scene.twig` renders the ghost only when `code` is passed;
- says that the site is being worked on, asks the visitor to try again later, and offers a *Zkusit znovu* button (`app.request.uri`).

`verify.sh` fails on `setcontent` / `menu_array()` in either page, the layout or the scene, and warns on `tel:` / `mailto:` links in the 503 page — also when they come from the translation catalog (`__('error.503.note')` resolved in `translations/*.xlf`) or from `theme/contact/…` in `theme.yaml`. A time promise inside a translated text ("back within a few hours") is not detected; read the 503 units of the catalogs.

### Point the 500 and 503 config at a root entrypoint (no `/`)

`ErrorController::attemptToRender()` splits each configured item on `/` and first tries it as a `contenttype/slug` record: `helper-pages/internal-server-error.500.twig` becomes a database query for a record with the slug `internal-server-error.500.twig`, run **before** the template is rendered. Only a missing record is caught, so with the database down that query throws and the branded page never appears. An item without `/` skips the lookup.

So the 500 and 503 entries name a one-line file in the theme root that extends the real template:

```twig
{# public/theme/<themename>/internal-server-error.500.twig #}
{% extends 'helper-pages/internal-server-error.500.twig' %}
```

```twig
{# public/theme/<themename>/maintenance.503.twig #}
{% extends 'helper-pages/maintenance.503.twig' %}
```

```yaml
# config/bolt/config.yaml
maintenance: [ 'maintenance.503.twig' ]
internal_server_error: [ 'internal-server-error.500.twig' ]
```

The 404 and 403 pages keep `helper-pages/…`: they render while the database works, and the extra lookup costs one query.

### Bolt core limits (bolt/core 6.1.9)

Tested by pointing `DATABASE_URL` of a production-mode copy at a missing SQLite file: visitors get Symfony's generic "An Error Occurred: Internal Server Error" instead of the branded page, whatever the theme does. Two core listeners touch the database on the error sub-request:

1. `TimedPublishSubscriber::onKernelRequest()` runs its publish/depublish `UPDATE` queries on every request, including the error page's sub-request. It catches the failure and logs it…
2. …and `Bolt\Log\LogHandler` writes that log record into the same database, which throws again.

With both patched, the root entrypoint above renders the branded 500 page with the database down; the `helper-pages/…` item still fails on the record lookup. These are upstream fixes (skip sub-requests in `TimedPublishSubscriber`, never throw from `LogHandler`, skip the record lookup for `*.twig` items in `ErrorController`) — do not patch `vendor/`. Until they are released, the zero-database rule and the root entrypoints still matter: they are what keeps the page working once core is fixed, and they already cover every 500 that is not a database outage.

## 6. Brand-Aligned Visual Metaphor Pattern

Helper pages should not look generic. Use `_helper_scene.twig` to weave the client's brand into the visual presentation:

| Client Domain | Visual Metaphor | 404 (Not Found) | 403 (Forbidden) | 500 (Server Error) | 503 (Maintenance) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bakery / café** | The **Display Counter** | Empty tray with a crumb-covered label (*"Tenhle koláč už je pryč"*) | Kitchen door with a *"Jen pro personál"* sign | Smoking oven with the alarm light on (*"Něco se připálilo"*) | *"Pečeme"* sign on the door, dough rising as an indeterminate progress bar |
| **Library / bookshop** | The **Shelf** | Gap on the shelf with an empty catalogue card (*"Kniha nenalezena"*) | Rare-books glass cabinet with a key lock (*"Jen se svolením"*) | Toppled stack of books | *"Inventura"* notice and a quiet progress bar |
| **Logistics / shipping** | The **Parcel** | Parcel with an unreadable address label (*"Adresát neznámý"*) | Sealed parcel stamped *"Neotvírat"* | Crushed parcel on the conveyor belt with a *"Zkusit znovu"* button | Paused sorting line with an indeterminate progress bar |

### Adapting to New Projects
When building for a new client (e.g. dental clinic, fitness studio, e-shop):
1. **Choose an iconic physical metaphor** from their industry (e.g. appointment card, locker with a combination lock, shopping basket).
2. Use `code` (404, 403, 500) as an oversized background watermark (`.helper-ghost`); the 503 page has none (section 5).
3. Include clear, friendly next steps: a primary recovery button (`Zpět na úvod`, `Zkusit znovu`) and the requested path when applicable (`app.request.pathinfo`). The 500 and 503 pages carry no contact details from the database (section 5).

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
        field_val: origin,
        field_val_strong: path,
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
        field_val: origin,
        field_val_strong: path,
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

{% set title = 'Na webu se pracuje' %}

{% block head %}
    {{ include('helper-pages/_helper_scene_styles.twig') }}
{% endblock head %}

{# No setcontent, no contact details, no numbers, no time promises (section 5). #}
{% block mainHelper %}
    {{ include('helper-pages/_helper_scene.twig', {
        eyebrow: 'Údržba webu',
        heading: 'Na webu právě pracujeme',
        lead: 'Web je dočasně nedostupný, protože na něm probíhají úpravy. Zkuste to prosím znovu o něco později. Děkujeme za trpělivost.',
        progress: true,
        buttons: [
            { label: 'Zkusit znovu', href: app.request.uri, variant: 'primary' }
        ]
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
5. **500 / 503 Safety Check:** Validates that `internal-server-error.500.twig`, `maintenance.503.twig`, the standalone layout and the scene contain zero database lookups (`setcontent`, `menu_array()`), and that both pages extend `_helper_template_without_master.twig`. Warns on `tel:` / `mailto:` contact links in the 503 page, in the catalog units its `__()` keys resolve to, and on `theme/contact/…` passed into it.
   It also fails when `internal_server_error` or `maintenance` names a path with `/` (Bolt looks it up as a record first) or its root entrypoint is missing.
6. **Twig Syntax:** Runs `php bin/console lint:twig public/theme/<themename>/helper-pages` to guarantee error-free Twig compilation.
