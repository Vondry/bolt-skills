---
name: bolt-theme-init
description: >-
  Use this skill whenever bootstrapping, scaffolding, or structuring a new Bolt CMS
  theme from scratch. Establishes the Component/Container/Page architecture (pure components
  with zero setcontent, smart containers with CMS queries, page orchestrators with minimal
  raw HTML, and page-scoped components) and the shared layout shell partials/_master.twig,
  configures Tailwind CSS v4 CLI, Rollup for TypeScript (menu accordions and mobile drawer,
  anchor scrolling, locale switcher, PhotoSwipe), links the theme in config/bolt/config.yaml,
  binds ContentTypes to their templates (example: products → product.twig / product.record.twig),
  and verifies the result automatically.
---

# Bolt CMS Theme Initialization & Architecture Standard

When building a frontend for [Bolt CMS](https://boltcms.io), themes must be structured for high maintainability, predictable data flow, and modern asset bundling. This skill defines the complete bootstrapping runbook, build pipeline setup, the shared layout shell, and the **Component / Container / Page** design system architecture.

The folder names, layout blocks, token names and JavaScript hooks used here are the **Integration Contract** described in `WORKFLOWS.md`. The other theme-facing skills (`bolt-menu`, `bolt-theme-templates`, `bolt-tailwind-theme`, `bolt-helper-pages`, `bolt-cookie-consent`, `bolt-extension-setup`) plug into the same structure.

---

## 1. Architectural Philosophy: Components, Containers & Pages

To avoid messy templates where database queries, complex HTML markup, and business logic are mixed together, Bolt themes adhere to a strict three-tier separation of concerns:

```text
public/theme/<theme-name>/
├── partials/                     # LAYOUT SHELL & SHARED PARTIALS
│   ├── _master.twig              # HTML shell: SEO, a11y skip link, cache-busted assets,
│   │                             #   blocks seo / head / header / main / footer / scripts   (this skill)
│   ├── _locale-switcher.twig     # Language switcher                                         (bolt-add-language)
│   ├── _cookie-banner.twig       # Two-layer opt-in cookie banner                            (bolt-cookie-consent)
│   └── _consent-mode.twig        # Consent configuration (JSON) for cookie-consent.ts        (bolt-cookie-consent)
│
├── components/                   # 1. PURE / PRESENTATIONAL COMPONENTS
│   │                             # Rule: ZERO setcontent. All data passed via parameters.
│   ├── ui/                       # button, badge, card, picture, breadcrumbs, pagination,
│   │                             #   empty-state, section-header                             (bolt-theme-templates)
│   ├── nav/                      # item, dropdown                                            (bolt-menu)
│   └── brand/
│       └── logo.twig             # Logo (SVG or image, sitename fallback)                    (bolt-menu)
│
├── containers/                   # 2. SMART / CONTAINER COMPONENTS
│   │                             # Rule: Reusable, can call setcontent / menu_array(), composes pure components.
│   ├── header/_menu.twig         # Header navigation, CTA, locale switcher, mobile drawer    (bolt-menu)
│   ├── footer/_footer.twig       # Footer columns, contacts, socials, legal links            (bolt-menu)
│   ├── contact/                  # _contact-section.twig, _contact-banner.twig               (bolt-theme-templates)
│   └── products/                 # _featured-products.twig                                   (bolt-theme-templates)
│
├── pages/                        # 3. PAGE ORCHESTRATORS (Linked to ContentTypes)
│   │                             # Rule: ZERO or minimal raw HTML. Pure composition.
│   ├── homepage/
│   │   ├── components/           # Page-scoped pure components (hero, hero-metrics)
│   │   └── homepage.twig         # Placeholder from this skill, replaced by bolt-theme-templates
│   └── product/
│       ├── components/           # Page-scoped pure components (spec-table, stock-badge)
│       ├── product.twig          # Products Listing Orchestrator
│       └── product.record.twig   # Product Detail Orchestrator
│
├── static-pages/                 # Templates served by TemplateController routes (e.g. gdpr.twig)
├── helper-pages/                 # 404 / 403 / 500 / 503 pages                               (bolt-helper-pages)
├── extensions/                   # sitemap.xml.twig, llms.txt.twig                           (bolt-extension-setup)
│
├── css/
│   ├── article/                  # Bolt Article / Redactor extension styles
│   │   ├── grid.css
│   │   └── utils.css
│   ├── fonts/                    # Self-hosted WOFF2 fonts (bolt-tailwind-theme)
│   ├── splide_4.1.2.min.css      # Splide carousel stylesheet
│   ├── tailwind/
│   │   └── index.css             # Tailwind v4 source: @source rules, @theme inline tokens, utilities
│   └── index.css                 # Compiled production CSS (build output — never edit)
│
├── js/
│   ├── splide_4.1.2.min.js       # Splide carousel library
│   ├── src/                      # Standard TypeScript modules (auto-added to all themes)
│   │   ├── auto-scroll.ts        # Anchor scroll with dynamic header height subtraction
│   │   ├── menu.ts               # Dropdown accordions + mobile drawer / collapse menu with a11y
│   │   ├── locale-switcher.ts    # Language switch with scroll position preservation
│   │   ├── photoswipe.ts         # PhotoSwipe 5 lightbox with history hash deep-linking
│   │   └── index.ts              # Entrypoint importing and mounting all modules
│   └── app.js                    # Compiled production JS bundle (build output)
│
├── index.twig                    # Root Entrypoint -> {% extends 'pages/homepage/homepage.twig' %}
├── product.twig                  # Root Entrypoint -> {% extends 'pages/product/product.twig' %}         (catalog sites)
├── product.record.twig           # Root Entrypoint -> {% extends 'pages/product/product.record.twig' %}  (catalog sites)
├── record.twig                   # Generic fallback record template (any ContentType)
├── listing.twig                  # Generic fallback listing template (any ContentType)
├── macros.twig                   # Typography, currency, admin edit & link helpers
└── theme.yaml                    # Theme name, assets_version, contact, analytics, socials
```

### The Three Tiers Defined

| Tier | Role & Responsibilities | `setcontent` Allowed? | Raw HTML Allowed? |
| :--- | :--- | :---: | :---: |
| **`components/`** (Pure) | Reusable UI atoms and molecules (buttons, cards, badges, section headers). Completely decoupled from Bolt database state. Accepts pure parameters, uses macros, and nests other pure components. | ❌ **NEVER** | ✅ Yes |
| **`containers/`** (Smart) | Reusable organism-level blocks across multiple pages (site header, footer, featured products, contact banner). Queries Bolt CMS or configuration and feeds data into pure components. | ✅ **YES** | ✅ Yes |
| **`pages/`** (Orchestrators) | Top-level view coordinators linked directly to ContentTypes or routes. Declaratively stacks containers and pure components. Passes the active `record` or `records` down. Layout wrappers (`wrapper px-edge`, a grid) are acceptable; anything reusable moves to a component or container. | ⚠️ Avoid (use a container) | ❌ **Minimal/None** |
| **`pages/<page>/components/`** | **Page-Scoped Pure Components**. One-off components relevant only to a single specific page (e.g. hero metric counters, product stock badge). Keeps the root `components/` directory clean. | ❌ **NEVER** | ✅ Yes |

---

## 2. Bolt Template Naming & Routing Standard: Products Example

Bolt CMS resolves templates either from `config/bolt/contenttypes.yaml` or through convention. To support explicit naming requirements:
* **Listing template:** `product.twig`
* **Record detail template:** `product.record.twig`

The page orchestrators themselves (`pages/product/…`) and their components are shipped by **`bolt-theme-templates`**; this skill defines the binding and the architecture they follow.

### A. ContentType Definition (`config/bolt/contenttypes.yaml`)
```yaml
products:
  name: Produkty
  singular_name: Produkt
  fields:
    title: { type: text, class: large, required: true }
    slug: { type: slug, uses: [ title ] }
    teaser: { type: textarea, height: 100px }
    body: { type: redactor }
    image: { type: image }
    price: { type: number, label: 'Cena v Kč' }          # Bolt has no `integer` field type
    stock: { type: number, default: 0, label: 'Skladová zásoba' }
  show_in_menu: true
  listing_template: product.twig
  record_template: product.record.twig
  records_per_page: 9
```

### B. Thin Theme Entrypoints
In the theme root, keep entrypoints as single-line wrapper files:

```twig
{# public/theme/<theme>/product.twig #}
{% extends 'pages/product/product.twig' %}
```

```twig
{# public/theme/<theme>/product.record.twig #}
{% extends 'pages/product/product.record.twig' %}
```

Pointing `listing_template` / `record_template` directly at `pages/product/product.twig` works as well. Never point the generic root `record.twig` / `listing.twig` at one ContentType's pages: they are the fallbacks for every ContentType without its own template (see section 3G).

### C. Listing Page Orchestrator (`pages/product/product.twig`)
Composes pure components and page-scoped components; the only markup is layout wrappers:

```twig
{% extends 'partials/_master.twig' %}
{% import 'macros.twig' as macros %}

{% block main %}
    <div class="wrapper px-edge">
        {% include 'components/ui/breadcrumbs.twig' with { items: [ { label: __('products.title') } ] } %}
    </div>

    <section aria-labelledby="products-listing-title" class="wrapper px-edge pb-section">
        {% include 'components/ui/section-header.twig' with {
            title: __('products.title'),
            title_id: 'products-listing-title',
            eyebrow: __('products.eyebrow'),
            lead: __('products.perex'),
            heading_level: 1,
            layout: 'center'
        } %}

        {% if records|length > 0 %}
            {# role="list" keeps list semantics in Safari when list-style is removed #}
            <ul role="list" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6 lg:gap-8">
                {% for item in records %}
                    <li class="flex">
                        {% include 'components/ui/card.twig' with {
                            title: item|title,
                            href: item|link,
                            image: item.image|default(null),
                            description: item.teaser|default(item|excerpt(100)),
                            price: item.price is defined and item.price ? macros.formatPrice(item.price) : null,
                            badge_markup: include('pages/product/components/stock-badge.twig', { stock: item.stock|default(0) }),
                            edit_url: item|edit_link
                        } %}
                    </li>
                {% endfor %}
            </ul>

            {# Bolt's pager() with the theme's accessible pagination template #}
            {{ pager(records, template = 'components/ui/pagination.twig') }}
        {% else %}
            {% include 'components/ui/empty-state.twig' with {
                title: __('products.empty_title'),
                message: __('products.empty_message')
            } %}
        {% endif %}
    </section>

    {% include 'containers/contact/_contact-banner.twig' %}
{% endblock main %}
```

### D. Record Detail Orchestrator (`pages/product/product.record.twig`)
```twig
{% extends 'partials/_master.twig' %}
{% import 'macros.twig' as macros %}

{% block main %}
    <div class="wrapper px-edge flex items-center justify-between gap-4">
        {% include 'components/ui/breadcrumbs.twig' with {
            items: [ { label: __('products.title'), href: '/produkty' }, { label: record|title } ]
        } %}
        {{ macros.edit(record) }}
    </div>

    <article class="wrapper px-edge py-10 lg:py-16">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-start">
            {# One PhotoSwipe gallery for the main image (and thumbnails, if any) #}
            <div class="photoswipe-gallery">
                {% if record.image is not empty %}
                    {% include 'components/ui/picture.twig' with {
                        image: record.image, alt: record|title, aspect: 'aspect-4/3', loading: 'eager', pswp: true
                    } %}
                {% else %}
                    <div class="aspect-4/3 flex items-center justify-center bg-surface text-ink-3">{{ __('products.no_image') }}</div>
                {% endif %}
            </div>

            <div class="flex flex-col gap-6">
                {% include 'pages/product/components/stock-badge.twig' with { stock: record.stock|default(0) } %}

                <h1 class="font-display text-section font-semibold text-ink">{{ macros.typo(record|title) }}</h1>

                {% if record.price is defined and record.price is not empty %}
                    <p class="font-display text-section font-semibold text-accent">{{ macros.formatPrice(record.price) }}</p>
                {% endif %}

                {% if record.teaser is defined and record.teaser is not empty %}
                    <p class="text-lead text-ink-2 leading-relaxed">{{ record.teaser }}</p>
                {% endif %}

                {# '#kontakt' scrolls to the contact section; or open a contact page with the
                   product preselected: '/kontakt?produkt=' ~ record.slug #}
                {% include 'components/ui/button.twig' with {
                    label: __('products.inquire_cta'), href: '#kontakt', variant: 'primary', size: 'lg'
                } %}

                {# Redactor/article output is already safe HTML; .cms-redactor styles it (bolt-tailwind-theme).
                   Do not use Tailwind's `prose` classes: the typography plugin is not installed. #}
                {% if record.body is defined and record.body is not empty %}
                    <div class="pt-6 border-t border-stroke cms-redactor">{{ record.body }}</div>
                {% endif %}
            </div>
        </div>
    </article>

    {% include 'containers/contact/_contact-section.twig' %}
{% endblock main %}
```

---

## 3. Tooling & Build Pipeline Configuration

The theme directory encapsulates its own Node.js build environment using **Tailwind CSS v4 CLI** and **Rollup** for bundling TypeScript without heavy Webpack/Vite runtime overhead.

### A. `package.json`
```json
{
  "name": "THEME_NAME",
  "version": "1.0.0",
  "scripts": {
    "watch:css": "npx @tailwindcss/cli --input ./css/tailwind/index.css --output ./css/index.css --minify --watch",
    "watch:js": "rollup -c --watch",
    "dev": "concurrently \"npm run watch:css\" \"npm run watch:js\"",
    "build:css": "npx @tailwindcss/cli --input ./css/tailwind/index.css --output ./css/index.css --minify",
    "build:js": "rollup -c",
    "prod": "npm run build:css && npm run build:js"
  },
  "license": "ISC",
  "devDependencies": {
    "@rollup/plugin-node-resolve": "^16.0.3",
    "@rollup/plugin-terser": "^1.0.0",
    "@rollup/plugin-typescript": "^12.3.0",
    "@tailwindcss/cli": "^4.3.3",
    "@tailwindcss/postcss": "^4.3.3",
    "concurrently": "^10.0.5",
    "rollup": "^4.64.1",
    "tailwindcss": "^4.3.3",
    "tslib": "^2.8.1",
    "typescript": "^6.0.3"
  },
  "dependencies": {
    "photoswipe": "^5.4.4"
  }
}
```
The production build script is **`prod`** (`build:css` + `build:js`); there is no `build` script.

### B. Tailwind CSS v4 Scanning Safeguards & Baseline Tokens (`css/tailwind/index.css`)
```css
@import 'tailwindcss';
@import '../../node_modules/photoswipe/dist/photoswipe.css';   /* galleries only */

/* 1. Skenovat překladové soubory v kořeni projektu */
@source "../../../../../translations";

/* 2. Skenovat Bolt menu konfiguraci (třídy pro navigační položky, např. class: cta) */
@source "../../../../../config/bolt/menu.yaml";

/* 3. ZABRÁNIT ZPĚTNÉ VAZBĚ: NIKDY neskenovat vlastní vygenerovaný výstup */
@source not "../index.css";

/* 4. Ignorovat dokumentaci obsahující zastaralé názvy tříd v textu */
@source not "../../README.md";

/* 5. Helper stránky mají vlastní scoped styly (bolt-helper-pages) */
@source not "../../helper-pages";

@theme inline {
    --color-canvas: var(--canvas);
    --color-ink: var(--ink);
    --color-accent: #1d4ed8;
    --spacing-header: 4.5rem;
    /* … the full baseline uses every token NAME of bolt-tailwind-theme with neutral values */
}
```
The baseline (`examples/index.css`) already uses the token names of `bolt-tailwind-theme` (`canvas`, `surface`, `surface-2`, `ink`, `ink-2`, `ink-3`, `stroke`, `accent*`, `night*`, font and text-size tokens, `--spacing-header`, `--breakpoint-menu`) with neutral placeholder values, plus minimal `.wrapper`, `.px-edge`, `.py-section`, `.card` and `.dropdown` rules, so every template renders correctly before `bolt-tailwind-theme` replaces the values with the design's.

### C. Theme Configuration & Versioning (`theme.yaml`)
Provides theme metadata, contact details (used on privacy policy, error pages, footer and in `/llms.txt`), tracking IDs, socials, and zero-cost asset cache-busting in `partials/_master.twig` (`?v={{ theme.assets_version }}`). Read it in Twig as `theme.<key>` or `config.get('theme/<key>')`:
```yaml
name: 'THEME_NAME'

# Cache buster appended to built CSS and JS (?v=X.X)
assets_version: '1.0'

# Operator / company contact details, shown on privacy policy, error helper pages, footer, and /llms.txt
contact:
  name: ~          # legal name (privacy policy)
  ico: ~           # company ID (IČO)
  address: ~
  email: 'info@example.cz'
  phone: '+420 123 456 789'
  hours: ~
  bio: ~

# Tracking IDs (bolt-cookie-consent; its scaffold also appends the privacy: block —
# controllers, purposes, recipients and the cookie inventory)
analytics:
  ga4_id: ~
  google_ads_id: ~
  sklik_id: ~
  consent_mode: basic

# Social networks
socials:
  facebook: ~
  youtube: ~
  instagram: ~
  linkedin: ~
  twitter: ~
```

### D. Baseline Client Modules & Vendor Assets
Every theme initialized with this skill automatically receives a production-tested suite of client TypeScript modules and static assets:

1. **`js/src/auto-scroll.ts`**:
   - In-page smooth scrolling to `#anchors`.
   - Dynamically measures the sticky header height (`[data-sticky-header]`, `#main-menu`, or `#hlavni-menu`) and subtracts it so target sections are never obscured.
   - Safe against PhotoSwipe hashes (`#&gid=1&pid=2`) and updates URL without clobbering browser history.
2. **`js/src/menu.ts`** — navigation behaviour for the markup rendered by `bolt-menu`:
   - **Dropdown accordions** for every `[data-dropdown-toggle="<id>"]` → panel `#<id>` (submenus, locale switcher, breadcrumbs): sets `aria-expanded` / `aria-controls`, keeps closed panels `inert` (out of tab order and a11y tree), animates height 0 ↔ `scrollHeight` and then switches to `height: auto` so nested panels can grow, opens with click or ArrowDown (focusing the first link), closes with Escape (returning focus) or a click outside / on an in-page link. Panels use the `.dropdown` class (`overflow: hidden; height: 0; transition: height`).
   - **Mobile menu**, one opener `[data-menu-toggle]` and one panel `[data-mobile-menu]`, in two modes:
     - `data-mobile-menu="drawer"` — slide-in drawer (`translate-x-full`) with `[data-menu-backdrop]`, body scroll lock, focus trap, Escape / backdrop / `[data-menu-close]` / link click closes it, focus returns to the opener.
     - `data-mobile-menu="collapse"` (or the legacy ids `#mobile-menu` / `#mobilni-menu`) — height-animated panel below the header bar between `0` and `scrollHeight`, `.menu-icon-open` / `.menu-icon-close` icon swap, recalculates height on resize.
   - Accessible labels: the opener's `aria-label` switches between `data-label-open` and `data-label-close`; `aria-expanded` is always kept in sync.
3. **`js/src/locale-switcher.ts`**:
   - Progressive enhancement for language switchers (`[data-locale-switch]`).
   - Stores `window.scrollY` in `sessionStorage` and restores exact scroll position after the next page layout settles (waiting two `requestAnimationFrame`s).
   - Preserves active URL query parameters and hashes across locale switches.
4. **`js/src/photoswipe.ts`**:
   - Full PhotoSwipe v5 lightbox wiring for `.photoswipe-gallery` containers with `a.photoswipe-gallery__link` slides (`href` = full-size image, `data-pswp-width`, `data-pswp-height`; optional `.photoswipe-gallery__caption`).
   - Deep-linking URL hash sync (`#&gid=1&pid=2`) with browser history integration (closing on Back button).
   - Custom caption registration (`.pswp__custom-caption`) and intrinsic aspect-ratio fallbacks.
5. **`js/src/index.ts`**: imports the modules above; remove the ones the site does not need (e.g. `photoswipe` together with its npm dependency and CSS `@import`). `bolt-cookie-consent` adds `import './cookie-consent';`.
6. **`js/splide_4.1.2.min.js` & `css/splide_4.1.2.min.css`**:
   - Standard carousel library and styles ready for immediate use (load them in `{% block head %}` of the pages that use a carousel).
7. **`css/article/grid.css` & `css/article/utils.css`**:
   - Complete CSS styles for the Bolt CMS Article / Redactor extension (12-column grid and layout alignments).

### E. Layout Shell (`partials/_master.twig`)
The single layout every page, static page and 404/403 helper page extends. It defines the blocks other skills fill:

| Block / include | Filled by |
| :--- | :--- |
| `{% block seo %}` with `seo.title()` and `seo.metatags()` | `bolt-extension-setup` (AppoloDev/bolt-seo); helper and static pages override it |
| `partials/_consent-mode.twig` (include, `ignore missing`) | `bolt-cookie-consent` — consent configuration (JSON) read by `cookie-consent.ts`; trackers load only after consent |
| `{{ asset('css/index.css') }}?v={{ theme.assets_version }}` and `js/app.js` | this skill + `bolt-asset-caching` (cache-busting). Bolt registers the active theme as the default asset package, so `asset()` paths are relative to the theme folder |
| `{% block head %}` | page-specific additions (helper scene styles, carousel CSS, preloads) |
| skip link to `#obsah` (`a11y.skip_to_content`) | this skill |
| `partials/_cookie-banner.twig` (include, `ignore missing`) right after the skip link | `bolt-cookie-consent` — early in the tab order |
| `{% block header %}` → `containers/header/_menu.twig` (`ignore missing`) | `bolt-menu` |
| `{% block main %}` inside `<main id="obsah">` | page orchestrators |
| `{% block footer %}` → `containers/footer/_footer.twig` (`ignore missing`) | `bolt-menu` |
| `{% block scripts %}` | page-specific scripts |

The partials owned by other skills are included with `ignore missing`, so the shell renders as soon as this skill has run and fills in as later skills add their files. The full file is `examples/_master.twig`.

### F. Macros (`macros.twig`)
- `macros.edit(record)` — admin quick-edit button, rendered only for logged-in editors (`record|edit_link` is empty otherwise).
- `macros.typo(text)` — Czech typography glue: escapes the text and inserts `&nbsp;` after one-letter prepositions and conjunctions (`a i k o s u v z`, upper- and lowercase) and `&`. Twig string literals do not support `\u` escapes — `' '` would render literally as `u00A0` — so the macro uses the HTML entity.
- `macros.formatPrice(price)` — `1290` → `1 290 Kč`.
- `macros.linkAttributes(href)` — `href` through `locale_link()` for internal paths, `target="_blank" rel="noopener noreferrer"` for external URLs.

### G. Generic Fallbacks & Homepage Placeholder
- `record.twig` and `listing.twig` render any ContentType that has no dedicated template (title, image, excerpt; listing cards with `pager()`). They extend `partials/_master.twig` and must stay generic.
- `index.twig` extends `pages/homepage/homepage.twig`. This skill writes a **placeholder** homepage marked `{# bolt-theme-init:placeholder #}`; `bolt-theme-templates`' scaffold replaces every file that still carries the marker with its real page.

### H. Translation Units
`examples/translations.cs.xlf` / `translations.en.xlf` hold the units used by the layout shell and the fallbacks (`a11y.skip_to_content`, `listing.empty`). Merge them into the project catalogs:
```bash
php vendor/vondry/bolt-skills/scripts/merge-xliff.php \
    vendor/vondry/bolt-skills/skills/bolt-theme-init/examples/translations.cs.xlf translations/messages.cs.xlf
```

---

## 4. Step-by-Step Initialization Procedure

### Step 1: Link Theme in Bolt Config
Edit `config/bolt/config.yaml`:
```yaml
theme: <theme-name>
```

### Step 2: Scaffold Theme Directory Hierarchy
```bash
mkdir -p public/theme/<theme-name>/{partials,static-pages,helper-pages,extensions,img}
mkdir -p public/theme/<theme-name>/components/{ui,nav,brand}
mkdir -p public/theme/<theme-name>/containers/{header,footer,contact}
mkdir -p public/theme/<theme-name>/pages/homepage/components
mkdir -p public/theme/<theme-name>/css/{tailwind,article,fonts}
mkdir -p public/theme/<theme-name>/js/src
```

### Step 3: Copy Boilerplate Files
Copy starter files from `skills/bolt-theme-init/examples/`:
* `package.json`, `postcss.config.mjs`, `rollup.config.js`, `tsconfig.json`, `theme.yaml`
* `index.css` → `css/tailwind/index.css`, and `js/src/*.ts`
* Splide (`js/splide_4.1.2.min.js`, `css/splide_4.1.2.min.css`) and `css/article/*.css`
* `macros.twig` and `_master.twig` → `partials/_master.twig`
* Generic fallbacks: `record.twig`, `listing.twig`
* Homepage placeholder: `pages/homepage/homepage.twig`; root `index.twig` → `{% extends 'pages/homepage/homepage.twig' %}`

*(Or execute the automated scaffold script below.)*

### Step 4: Install Dependencies, Update & Run Initial Build
```bash
cd public/theme/<theme-name>
npm install
npm update --save
npm run prod
```

> [!IMPORTANT]
> **Always update libraries upon installation:** Run `npm update --save` immediately following `npm install`. This upgrades `@tailwindcss/cli`, `rollup`, `typescript`, and related packages to their latest semver-compatible releases and records them into `package.json`. Immediately execute `npm run prod` to verify that the build succeeds with the updated packages and that no build regressions were introduced.

Verify that `css/index.css` and `js/app.js` have been generated and are non-empty.

### Step 5: Merge Translations, Clear Bolt CMS Cache & Test Render
```bash
php vendor/vondry/bolt-skills/scripts/merge-xliff.php \
    vendor/vondry/bolt-skills/skills/bolt-theme-init/examples/translations.cs.xlf translations/messages.cs.xlf
php bin/console cache:clear
```
Open the homepage in the browser or run a test request to ensure HTTP 200 is returned (the placeholder page renders inside the layout shell).

### Step 6: Continue with the Skills That Fill the Shell
1. `bolt-menu` — `scaffold.sh --profile=<landing|catalog|conditional> --templates --force` (header, footer, nav components, logo).
2. `bolt-tailwind-theme` — design tokens and utilities from the design.
3. `bolt-theme-templates` — UI components, containers and page orchestrators (replaces the homepage placeholder).

---

## 5. Automated Scaffolding & Verification Scripts

### Automated Scaffolding Script
To bootstrap a complete theme foundation in a single command:
```bash
# From bolt-skills repo or vendor/vondry/bolt-skills:
./skills/bolt-theme-init/scripts/scaffold.sh <theme-name> [project-root] [--force]
```
Existing files are kept (reported as `[skip]`) unless `--force` is given. The script creates the directories, copies tooling, TypeScript modules, vendor assets, the layout shell, macros, fallbacks and the homepage placeholder, links the theme in `config/bolt/config.yaml`, runs `npm install`, `npm update --save` and `npm run prod`, checks that `css/index.css` and `js/app.js` are non-empty, and clears the Bolt cache.

### Verification Script
Run the automated verification test from the project root:
```bash
./skills/bolt-theme-init/scripts/verify.sh
```

The script verifies:
1. `config/bolt/config.yaml` points to the active theme.
2. `public/theme/<theme-name>/` exists.
3. Directory hierarchy (`components/`, `containers/`, `pages/`) and the layout shell `partials/_master.twig` defining the `seo`, `head` and `main` blocks; a legacy `layouts/` folder is reported.
4. **Purity Enforcement:** Zero `setcontent` calls inside `components/`.
5. **Template bindings:** every `record_template` / `listing_template` configured in `contenttypes.yaml` exists in the theme (e.g. `product.twig` and `product.record.twig` for products); viewless ContentTypes and singleton listings are skipped.
6. Tooling files (`package.json`, `theme.yaml`, `css/tailwind/index.css`) exist with required npm scripts.
7. Compiled production assets (`css/index.css` and `js/app.js`) are built and non-empty.

---

## 6. Common Pitfalls & Anti-Patterns

| Anti-Pattern | Why It Breaks | Correct Pattern |
| :--- | :--- | :--- |
| **`setcontent` in `components/`** | Destroys reusability and testability. Hardwires UI atoms to database queries. | Pass data as parameters. Move data-fetching into `containers/`. |
| **Raw HTML in `pages/`** | Makes page templates brittle and unreadable. Logic and styling leak into view coordinators. | Keep `pages/` strictly declarative; compose pure components & containers. |
| **Polluting root `components/`** | Dumping single-use widgets into `components/` causes bloat and confusion. | Scope single-use components in `pages/<page>/components/`. |
| **Second layout file** (`layouts/_master.twig`, `_base.twig`) | Skills extend `partials/_master.twig` and fill `block main`; a different file or block name renders empty pages or "template not found". | One shell: `partials/_master.twig` with `seo`, `head`, `header`, `main`, `footer`, `scripts`. |
| **Root `record.twig` / `listing.twig` extending one ContentType's page** | Every other ContentType renders with that page (prices, stock badges, wrong buttons). | Keep them generic; bind ContentTypes with `record_template` / `listing_template`. |
| **`' '` in Twig strings** | Twig has no `\u` escapes; the text renders literally as `u00A0`. | Use `&nbsp;` on escaped text (`macros.typo`). |
| **`type: integer` in contenttypes.yaml** | Not a Bolt field type. | `type: number`. |
| **`prose` classes** | The Tailwind typography plugin is not installed; the classes generate nothing. | Wrap rich text in `.cms-redactor` (bolt-tailwind-theme). |
| **Dynamic Tailwind class strings** | Classes like `bg-{{ variant }}-500` are invisible to the Tailwind scanner. | Use static lookup dictionaries (`variant_classes[...]` in Twig). |
| **Colour names outside the token set** (`stone-*`, `brand`, `ink-800`) | Undefined names generate no CSS; ad-hoc palettes drift from the design. | Use the token names of `bolt-tailwind-theme` (`canvas`, `surface`, `ink`, `accent`, `night`, …). |
| **Scanning `css/index.css` in `@source`** | Causes a feedback loop where removed utility classes stay alive forever. | Add `@source not "../index.css";` to `css/tailwind/index.css`. |
| **Hardcoding asset paths without `?v=`** | Browsers cache old stylesheets indefinitely after updates. | Use `{{ asset('css/index.css') }}?v={{ theme.assets_version }}` linked to `theme.yaml`. |
