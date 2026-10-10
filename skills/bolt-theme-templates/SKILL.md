---
name: bolt-theme-templates
description: >-
  Use this skill whenever building, extending, or reviewing Bolt CMS Twig templates with
  Tailwind CSS v4 under the Component / Container / Page architecture: the pure UI component
  library (button, badge, card, picture with PhotoSwipe, breadcrumbs, pagination for pager(),
  empty state, section header), smart containers (contact section/banner, featured products),
  page orchestrators per ContentType with page-scoped components, their translation catalogs,
  and automated verification (layout contract, purity, translation traps, undefined classes, lint).
---

# Bolt CMS Theme Templates (`bolt-theme-templates`)

This skill establishes the production implementation standards, folder organization, and automated verification runbook for building Twig templates with Tailwind CSS v4 in Bolt CMS. It follows the **Integration Contract** in `WORKFLOWS.md`: every page extends `partials/_master.twig` (created by `bolt-theme-init`) and fills `{% block main %}`; classes use the design tokens of `bolt-tailwind-theme`; links go through `locale_link()`; visible strings are translation keys.

---

## 1. Architectural Principles: Component / Container / Page

Bolt CMS themes in this repository follow a strict three-tier architecture:

```mermaid
flowchart TD
    subgraph Pages ["Tier 3: Page Orchestrators (pages/)"]
        direction TB
        PageList["pages/product/product.twig<br/>(Listing page)"]
        PageRecord["pages/product/product.record.twig<br/>(Record detail)"]
        PageHome["pages/homepage/homepage.twig<br/>(Homepage)"]
        PageScopedComp["pages/product/components/spec-table.twig<br/>pages/product/components/stock-badge.twig<br/>pages/homepage/components/hero.twig, hero-metrics.twig<br/>(Page-scoped components)"]
    end

    subgraph Containers ["Tier 2: Smart Containers (containers/)"]
        direction TB
        ContHeader["containers/header/_menu.twig<br/>(bolt-menu: menu_array('main'))"]
        ContFooter["containers/footer/_footer.twig<br/>(bolt-menu: menu_array('footer'))"]
        ContContact["containers/contact/_contact-section.twig<br/>containers/contact/_contact-banner.twig<br/>(theme.yaml contacts)"]
        ContFeatured["containers/products/_featured-products.twig<br/>(setcontent products)"]
    end

    subgraph Components ["Tier 1: Pure Components (components/ui/)"]
        direction TB
        CompBtn["button.twig"]
        CompBadge["badge.twig"]
        CompPic["picture.twig"]
        CompCard["card.twig"]
        CompBreadcrumb["breadcrumbs.twig"]
        CompPagination["pagination.twig (pager template)"]
        CompEmpty["empty-state.twig"]
        CompHeader["section-header.twig"]
    end

    PageHome --> ContFeatured
    PageHome --> ContContact
    PageList --> CompCard
    PageList --> CompPagination
    PageList --> CompEmpty
    PageList --> CompHeader
    PageRecord --> ContContact
    PageRecord --> PageScopedComp
    PageRecord --> CompPic
    PageRecord --> CompBreadcrumb
    ContFeatured --> CompCard
    ContContact --> CompBtn
    CompCard --> CompPic
    CompCard --> CompBadge
    CompHeader --> CompBtn
```

---

### Tier 1: Pure Presentational Components (`components/`)
* **Strict Rule: ZERO `setcontent`**: Pure components **never** query the database, invoke `setcontent`, or read global request state directly.
* **Pure Props Interface**: All data must be passed in via arguments/parameters (`{ title, href, image, class, ... }`).
* **Composability**: Pure components can reuse and compose other pure components (e.g. `card.twig` composes `picture.twig` and `badge.twig`).
* **Deterministic & Reusable**: Can be rendered in any context, storybook, or test harness without requiring database fixtures.

### Tier 2: Smart Data Containers (`containers/`)
* **Data Retrieval**: Reusable sections that query data via `{% setcontent %}`, `menu_array()`, or settings from `theme.yaml` (`config.get('theme/...')`).
* **Section Encapsulation**: Designed as reusable blocks across multiple pages (e.g. `containers/header/_menu.twig`, `containers/footer/_footer.twig`, `containers/contact/_contact-section.twig`, `containers/products/_featured-products.twig`, `containers/gallery/_grid.twig`).
* **Delegation**: Containers handle data fetching and layout structure, delegating individual element rendering down to pure components.
* **Extensibility**: Containers can wrap slots or extend other containers.

### Tier 3: Page Orchestrators (`pages/`)
* **ContentType Binding**: Linked directly to Bolt ContentTypes or static routes:
  - Listing page: `pages/<contenttype>/<contenttype>.twig` (e.g. `pages/product/product.twig`)
  - Single record detail: `pages/<contenttype>/<contenttype>.record.twig` (e.g. `pages/product/product.record.twig`)
  - Homepage: `pages/homepage/homepage.twig` (bound by the root `index.twig`)
  - Bind with `listing_template` / `record_template` in `contenttypes.yaml`, either directly (`pages/product/product.twig`) or through a one-line root entrypoint (`product.twig` → `{% extends 'pages/product/product.twig' %}`).
* **Layout**: Every page `{% extends 'partials/_master.twig' %}` and fills `{% block main %}` (overriding `{% block seo %}` / `{% block head %}` only when needed).
* **Strict Rule: ZERO Raw HTML (or near-zero)**: Pages should not write extensive raw HTML markup. A page template's sole responsibility is orchestrating containers and pure components, mapping record fields, and passing data down. Layout wrappers (`wrapper px-edge`, a grid `<ul>`) are acceptable; anything reusable moves to a component; any query moves to a container.
* **Page-Scoped Components**: When a component is unique to a single page and never used elsewhere (e.g. `pages/product/components/spec-table.twig` or `pages/homepage/components/hero.twig`), it lives in a `components/` subfolder inside that page folder.

---

## 2. Directory Structure of a Compliant Theme

```text
public/theme/<theme_name>/
├── components/                       # Tier 1: Pure presentational components
│   ├── brand/
│   │   └── logo.twig                 # bolt-menu
│   ├── nav/                          # bolt-menu: item.twig, dropdown.twig
│   └── ui/                           # this skill
│       ├── badge.twig
│       ├── breadcrumbs.twig
│       ├── button.twig
│       ├── card.twig
│       ├── empty-state.twig
│       ├── pagination.twig           # template for Bolt's pager()
│       ├── picture.twig
│       └── section-header.twig
├── containers/                       # Tier 2: Smart layout containers
│   ├── contact/
│   │   ├── _contact-banner.twig      # compact CTA banner
│   │   └── _contact-section.twig     # full contact section (#kontakt)
│   ├── footer/
│   │   └── _footer.twig              # bolt-menu
│   ├── header/
│   │   └── _menu.twig                # bolt-menu
│   └── products/
│       └── _featured-products.twig   # catalog sites
├── pages/                            # Tier 3: Page orchestrators
│   ├── homepage/
│   │   ├── components/
│   │   │   ├── hero.twig             # Page-scoped component
│   │   │   └── hero-metrics.twig     # Page-scoped component
│   │   └── homepage.twig
│   └── product/                      # catalog sites
│       ├── components/
│       │   ├── spec-table.twig       # Page-scoped component
│       │   └── stock-badge.twig      # Page-scoped component
│       ├── product.record.twig       # Record detail orchestrator
│       └── product.twig              # Listing orchestrator
├── partials/                         # Layout shell and shared partials
│   ├── _master.twig                  # bolt-theme-init: blocks seo, head, header, main, footer, scripts
│   ├── _cookie-banner.twig           # bolt-cookie-consent
│   ├── _consent-mode.twig            # bolt-cookie-consent
│   └── _locale-switcher.twig         # bolt-add-language
├── helper-pages/                     # bolt-helper-pages (404/403/500/503)
├── static-pages/                     # pages served by TemplateController routes
├── css/
│   ├── tailwind/
│   │   └── index.css                 # Tailwind v4 source (@source, @theme inline tokens, utilities)
│   └── index.css                     # build output (never edit)
└── js/
    └── src/                          # TypeScript modules (Rollup bundle → js/app.js)
```

---

## 3. Implementation Blueprint & Examples

All examples use the token names of `bolt-tailwind-theme` (`canvas`, `surface`, `surface-2`, `ink`, `ink-2`, `ink-3`, `stroke`, `accent*`, `night*`, text sizes `hero` / `section` / `card` / `lead` / `body` / `meta` / `micro`) and its utilities (`wrapper`, `px-edge`, `py-section`, `card`, `eyebrow`, `link-arrow`, `pagination`, `cms-redactor`). Status colours (`emerald`, `amber` in the badge and stock badge) are Tailwind defaults used on purpose.

### A. Pure Button Component (`components/ui/button.twig`)
```twig
{#
  Pure Component: UI Button
  Rules: Zero setcontent. Purely presentational.

  Props:
    - label (string): Button label text
    - href (string|optional): If provided, renders an <a> link, else <button>.
        Internal paths go through locale_link(); external URLs (http://, https://, //)
        open in a new tab with rel="noopener noreferrer"; tel:/mailto: stay as they are.
    - variant (string|optional): 'primary' | 'secondary' | 'dark' | 'outline' | 'light-outline' | 'ghost' (default: 'primary')
        'light-outline' is the outline variant for dark backgrounds (hero, night bands).
    - size (string|optional): 'sm' | 'md' | 'lg' (default: 'md')
    - icon (string|optional): Raw SVG or icon name
    - icon_position (string|optional): 'left' | 'right' (default: 'right')
    - type (string|optional): 'button' | 'submit' (default: 'button')
    - class (string|optional): Additional Tailwind classes
    - disabled (bool|optional): Disabled state
    - aria_label (string|optional): Accessibility label

  Classes come from the design tokens of bolt-tailwind-theme (accent, ink, surface, stroke,
  night). Variant and size maps hold full static class strings so Tailwind can scan them.
#}

{% set base_styles = "inline-flex items-center justify-center font-semibold transition-all duration-200 cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 disabled:opacity-50 disabled:pointer-events-none" %}

{% set variant_map = {
    'primary':       'bg-accent hover:bg-accent-hover text-accent-ink shadow-sm focus-visible:outline-accent',
    'secondary':     'bg-surface hover:bg-surface-2 text-ink border border-stroke focus-visible:outline-ink',
    'dark':          'bg-night hover:bg-night-deep text-night-ink shadow-sm focus-visible:outline-night',
    'outline':       'bg-transparent border border-stroke hover:border-ink text-ink focus-visible:outline-ink',
    'light-outline': 'bg-transparent border border-night-ink/30 hover:border-night-ink hover:bg-night-ink/10 text-night-ink focus-visible:outline-night-ink',
    'ghost':         'bg-transparent hover:bg-surface text-ink-2 hover:text-ink focus-visible:outline-ink'
} %}
{% set variant_styles = variant_map[variant|default('primary')]|default(variant_map['primary']) %}

{% set size_map = {
    'sm': 'text-xs px-3 py-1.5 rounded-sm gap-1.5',
    'md': 'text-sm px-5 py-2.5 rounded-sm gap-2',
    'lg': 'text-base px-6 py-3.5 rounded-md gap-2.5'
} %}
{% set size_styles = size_map[size|default('md')]|default(size_map['md']) %}

{% set full_classes = [base_styles, variant_styles, size_styles, class|default('')]|join(' ')|trim %}

{% if href is defined and href is not empty %}
    {% set is_external = href starts with 'http://' or href starts with 'https://' or href starts with '//' %}
    <a href="{{ is_external ? href : locale_link(href) }}"
       class="{{ full_classes }}"
       {% if is_external %}target="_blank" rel="noopener noreferrer"{% endif %}
       {% if aria_label is defined %}aria-label="{{ aria_label }}"{% endif %}>
        {% if icon is defined and icon_position|default('right') == 'left' %}{{ icon|raw }}{% endif %}
        <span>{{ label }}</span>
        {% if icon is defined and icon_position|default('right') == 'right' %}{{ icon|raw }}{% endif %}
    </a>
{% else %}
    <button type="{{ type|default('button') }}"
            class="{{ full_classes }}"
            {% if disabled|default(false) %}disabled{% endif %}
            {% if aria_label is defined %}aria-label="{{ aria_label }}"{% endif %}>
        {% if icon is defined and icon_position|default('right') == 'left' %}{{ icon|raw }}{% endif %}
        <span>{{ label }}</span>
        {% if icon is defined and icon_position|default('right') == 'right' %}{{ icon|raw }}{% endif %}
    </button>
{% endif %}
```

### B. Pure Card Component (`components/ui/card.twig`)
The stretched link (`absolute inset-0` on the title link) makes the whole card clickable; `relative` on `<article>` keeps the overlay inside the card.
```twig
{#
  Pure Component: UI Card (Product / Blog / Service / Reference item)
  Rules: Zero setcontent. Composes pure components (picture, badge).

  Props:
    - title (string): Card headline
    - href (string): Link target (passed through locale_link)
    - image (Bolt image field|string|optional): Card image
    - badge (string|optional): Category or status text, rendered with components/ui/badge.twig
    - badge_markup (Markup|optional): Pre-rendered badge, e.g. a page-scoped component:
        badge_markup: include('pages/product/components/stock-badge.twig', { stock: item.stock })
    - description (string|optional): Excerpt / summary (HTML is stripped)
    - price (string|optional): Pre-formatted price, e.g. macros.formatPrice(item.price)
    - edit_url (string|optional): Bolt admin edit URL (item|edit_link — empty for visitors)
    - class (string|optional): Extra wrapper classes

  The whole card is clickable through a stretched link on the title: the overlay
  (`absolute inset-0`) needs the `relative` on <article> to stay inside the card.

  Translation keys: card.read_more, card.edit
#}
{% import 'macros.twig' as macros %}

<article class="card relative flex flex-col group overflow-hidden {{ class|default('') }}">
    {# Admin quick edit button (above the stretched link) #}
    {% if edit_url is defined and edit_url is not empty %}
        <div class="absolute top-3 right-3 z-20">
            <a href="{{ edit_url }}"
               class="inline-flex items-center px-2 py-0.5 text-xs font-semibold text-ink bg-surface rounded-sm border border-stroke hover:bg-surface-2 shadow-xs">
                ✏️ {{ __('card.edit') }}
            </a>
        </div>
    {% endif %}

    {% if image is defined and image is not empty %}
        <div class="relative overflow-hidden aspect-16/10 bg-surface">
            {% include 'components/ui/picture.twig' with {
                image: image,
                alt: title,
                aspect: 'aspect-16/10',
                class: 'group-hover:scale-105'
            } %}
        </div>
    {% endif %}

    {% if (badge is defined and badge is not empty) or (badge_markup is defined and badge_markup is not empty) %}
        <div class="absolute top-3 left-3 z-10">
            {% if badge_markup is defined and badge_markup is not empty %}
                {{ badge_markup|raw }}
            {% else %}
                {% include 'components/ui/badge.twig' with {
                    label: badge,
                    variant: 'accent',
                    size: 'sm'
                } %}
            {% endif %}
        </div>
    {% endif %}

    <div class="flex-1 p-6 flex flex-col justify-between gap-4">
        <div class="flex flex-col gap-2">
            <h3 class="font-display text-card font-semibold text-ink group-hover:text-accent transition-colors">
                <a href="{{ locale_link(href) }}" class="focus:outline-none">
                    <span class="absolute inset-0" aria-hidden="true"></span>
                    {{ macros.typo(title) }}
                </a>
            </h3>

            {% if description is defined and description is not empty %}
                <p class="text-body text-ink-2 line-clamp-3 leading-relaxed">
                    {{ description|striptags }}
                </p>
            {% endif %}
        </div>

        <div class="pt-2 flex items-center justify-between text-sm font-semibold">
            {% if price is defined and price is not empty %}
                <span class="text-base font-bold text-accent">{{ price }}</span>
            {% endif %}
            <span class="link-arrow">
                {{ __('card.read_more') }}
                <svg viewBox="0 0 24 24" class="size-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M5 12h14m-6-6 6 6-6 6"/>
                </svg>
            </span>
        </div>
    </div>
</article>
```

### C. Pure Picture Component (`components/ui/picture.twig`)
Dimensions come from the media library first (`image|media`), then from `image_dimensions()` (`bolt-runtime-extensions`) for images without a media entry. With `pswp: true` the picture is rendered as a PhotoSwipe slide link (`a.photoswipe-gallery__link` with `data-pswp-width` / `data-pswp-height`) — wrap the pictures of one gallery in `<div class="photoswipe-gallery">` (`js/src/photoswipe.ts`).
```twig
{#
  Pure Component: Responsive Picture / Image
  Rules: Zero setcontent. Purely presentational.

  Props:
    - image (Bolt image field|string): Pass the image field (record.image); a string is
        treated as a filename / public URL
    - alt (string|optional): Image alternative text (default: the field's alt or title)
    - width (int|optional): Intrinsic width
    - height (int|optional): Intrinsic height
    - loading (string|optional): 'lazy' | 'eager' (default: 'lazy')
    - class (string|optional): CSS classes for the <img> element
    - aspect (string|optional): Aspect ratio class e.g. 'aspect-16/9', 'aspect-4/3', 'aspect-square'
    - pswp (bool|optional): Render the picture as a PhotoSwipe 5 slide link. Wrap the
        pictures of one gallery in <div class="photoswipe-gallery"> (js/src/photoswipe.ts).

  Intrinsic dimensions (needed by PhotoSwipe and for layout stability):
    1. width/height props, if given;
    2. the media library entry (image|media — a database read, no disk access);
    3. image_dimensions() from bolt-runtime-extensions — only for images without a media
       entry (static theme assets, filenames set without picking from the library).
#}

{% set img_url = image.path is defined ? image.path : (image ~ '') %}
{% set img_alt = alt|default(image.alt|default(image.title|default(''))) %}
{% set img_width = width|default(null) %}
{% set img_height = height|default(null) %}

{% if img_width is empty or img_height is empty %}
    {% set media = image.path is defined ? image|media : null %}
    {% if media and media.width %}
        {% set img_width = media.width %}
        {% set img_height = media.height %}
    {% elseif pswp|default(false) %}
        {% set dims = image_dimensions(img_url) %}
        {% set img_width = dims.width %}
        {% set img_height = dims.height %}
    {% endif %}
{% endif %}

{% set img_tag %}
    <img src="{{ image|thumbnail(1200, 800) }}"
         srcset="{{ image|thumbnail(600, 400) }} 600w, {{ image|thumbnail(1200, 800) }} 1200w"
         sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
         alt="{{ img_alt }}"
         loading="{{ loading|default('lazy') }}"
         decoding="async"
         {% if img_width %}width="{{ img_width }}"{% endif %}
         {% if img_height %}height="{{ img_height }}"{% endif %}
         class="w-full h-full object-cover transition-transform duration-500 {{ class|default('') }}">
{% endset %}

<picture class="block overflow-hidden {{ aspect|default('') }}">
    {% if pswp|default(false) and img_width and img_height %}
        <a href="{{ img_url }}"
           class="photoswipe-gallery__link block w-full h-full"
           data-pswp-width="{{ img_width }}"
           data-pswp-height="{{ img_height }}">
            {{ img_tag }}
        </a>
    {% else %}
        {{ img_tag }}
    {% endif %}
</picture>
```

### D. Pagination for Bolt's `pager()` (`components/ui/pagination.twig`)
Bolt 6 listings receive `records` as a Pagerfanta object (`haveToPaginate`, `currentPage`, `nbPages`, `hasPreviousPage`, `previousPage`, …). Bolt's `pager()` function renders a template with `records`, `route`, `routeParams`, `surround` and `class`; this component is such a template:
```twig
{{ pager(records, template = 'components/ui/pagination.twig') }}
```
```twig
{#
  Pure Component: Accessible Pagination — a template for Bolt's pager() function.

  Usage (records is the Pagerfanta object Bolt passes to listing templates):
    {{ pager(records, template = 'components/ui/pagination.twig') }}

  pager() provides: records, route, routeParams, surround (default 3), class ('pagination'),
  previous_link_class, next_link_class. Links keep the current route, its parameters
  (including _locale) and the query string, and only change `page`.

  Styling: the `.pagination` rules from bolt-tailwind-theme (li a, li.active a,
  a[aria-current], li[disabled]).

  Translation keys: a11y.pagination, pager.previous, pager.next
#}

{% if records.haveToPaginate|default(false) %}
    {% set current = records.currentPage %}
    {% set last = records.nbPages %}
    {% set start = max(current - surround, 1) %}
    {% set end = min(current + surround, last) %}

    <nav aria-label="{{ __('a11y.pagination') }}" class="my-12">
        <ul class="{{ class|default('pagination') }}">
            {% if records.hasPreviousPage %}
                <li class="{{ previous_link_class|default('previous') }}">
                    <a href="{{ path(route, routeParams|merge({ page: records.previousPage })) }}" rel="prev" aria-label="{{ __('pager.previous') }}">
                        <svg viewBox="0 0 24 24" class="size-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7"/>
                        </svg>
                    </a>
                </li>
            {% endif %}

            {% if start > 1 %}
                <li><a href="{{ path(route, routeParams|merge({ page: 1 })) }}">1</a></li>
                {% if start > 2 %}
                    <li disabled aria-hidden="true"><a>…</a></li>
                {% endif %}
            {% endif %}

            {% for page in start..end %}
                <li {% if page == current %}class="active"{% endif %}>
                    <a href="{{ path(route, routeParams|merge({ page: page })) }}" {% if page == current %}aria-current="page"{% endif %}>{{ page }}</a>
                </li>
            {% endfor %}

            {% if end < last %}
                {% if end < last - 1 %}
                    <li disabled aria-hidden="true"><a>…</a></li>
                {% endif %}
                <li><a href="{{ path(route, routeParams|merge({ page: last })) }}">{{ last }}</a></li>
            {% endif %}

            {% if records.hasNextPage %}
                <li class="{{ next_link_class|default('next') }}">
                    <a href="{{ path(route, routeParams|merge({ page: records.nextPage })) }}" rel="next" aria-label="{{ __('pager.next') }}">
                        <svg viewBox="0 0 24 24" class="size-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                        </svg>
                    </a>
                </li>
            {% endif %}
        </ul>
    </nav>
{% endif %}
```

### E. Pure Section Header (`components/ui/section-header.twig`)
```twig
{#
  Pure Component: Section Header (eyebrow, heading, lead, optional link)
  Rules: Zero setcontent. All data passed via parameters.
  Wire it to its section with aria-labelledby="{{ title_id }}".

  Props:
    - title (string): Section heading
    - title_id (string|optional): HTML id of the heading, for aria-labelledby on the section
    - eyebrow (string|optional): Small kicker label above the heading
    - lead (string|Markup|optional): Intro paragraph
    - layout (string|optional): 'stacked' (default) | 'split' | 'center'
    - link (object|optional): { label, href } — rendered as a secondary button ('split' layout)
    - heading_level (int|optional): 2 (default) or 1 for page titles
    - class (string|optional)

  Translation keys: section.show_all (default label of the link)
#}
{% import 'macros.twig' as macros %}

{% set layout = layout|default('stacked') %}
{% set tag = heading_level|default(2) == 1 ? 'h1' : 'h2' %}

{% set heading %}
    {% if eyebrow is defined and eyebrow is not empty %}
        <p class="eyebrow mb-2">{{ eyebrow }}</p>
    {% endif %}
    <{{ tag }} {% if title_id is defined %}id="{{ title_id }}"{% endif %}
        class="font-display text-section font-semibold tracking-tight text-ink">
        {{ macros.typo(title) }}
    </{{ tag }}>
    {% if lead is defined and lead is not empty %}
        <p class="mt-3 text-lead text-ink-2">{{ lead|raw }}</p>
    {% endif %}
{% endset %}

{% if layout == 'center' %}
    <div class="max-w-3xl mx-auto text-center mb-10 {{ class|default('') }}">
        {{ heading }}
    </div>

{% elseif layout == 'split' %}
    <div class="flex flex-col md:flex-row md:items-end md:justify-between gap-6 mb-10 {{ class|default('') }}">
        <div class="max-w-2xl">
            {{ heading }}
        </div>
        {% if link is defined and link.href is defined %}
            <div class="shrink-0">
                {% include 'components/ui/button.twig' with {
                    label: link.label|default(__('section.show_all')),
                    href: link.href,
                    variant: 'secondary'
                } %}
            </div>
        {% endif %}
    </div>

{% else %}
    {# stacked (default) #}
    <div class="max-w-2xl mb-8 {{ class|default('') }}">
        {{ heading }}
    </div>
{% endif %}
```

### F. Badge, Breadcrumbs, Empty State
```twig
{#
  Pure Component: UI Badge / Chip
  Rules: Zero setcontent. Purely presentational.

  Props:
    - label (string): Badge text
    - variant (string|optional): 'accent' | 'neutral' | 'success' | 'warning' (default: 'accent')
        'brand' and 'ink' are accepted as aliases of 'accent' and 'neutral'.
        'success' / 'warning' use Tailwind's emerald / amber on purpose (status colours
        are not part of the brand palette).
    - size (string|optional): 'sm' | 'md' (default: 'md')
    - class (string|optional): Additional classes
#}

{% set variant_map = {
    'accent':  'bg-accent-soft text-accent border border-accent/20',
    'neutral': 'bg-surface text-ink-2 border border-stroke',
    'success': 'bg-emerald-50 text-emerald-700 border border-emerald-200',
    'warning': 'bg-amber-50 text-amber-700 border border-amber-200'
} %}
{% set aliases = { 'brand': 'accent', 'ink': 'neutral' } %}
{% set variant_key = aliases[variant|default('accent')]|default(variant|default('accent')) %}
{% set variant_styles = variant_map[variant_key]|default(variant_map['accent']) %}

{% set size_map = {
    'sm': 'text-micro px-2 py-0.5 font-medium tracking-wide',
    'md': 'text-xs px-2.5 py-1 font-semibold tracking-wider uppercase'
} %}
{% set size_styles = size_map[size|default('md')]|default(size_map['md']) %}

<span class="inline-flex items-center justify-center rounded-full leading-none {{ variant_styles }} {{ size_styles }} {{ class|default('') }}">
    {{ label }}
</span>
```
```twig
{#
  Pure Component: Accessible Breadcrumbs (schema.org BreadcrumbList)
  Rules: Zero setcontent.

  Props:
    - items (array): List of { label, href (optional) }; the last item is the current page
    - class (string|optional): Extra classes

  Translation keys: a11y.breadcrumbs, nav.home
#}

{% if items is defined and items|length > 0 %}
    <nav aria-label="{{ __('a11y.breadcrumbs') }}" class="text-xs text-ink-3 py-3 {{ class|default('') }}">
        <ol class="flex flex-wrap items-center gap-1.5 list-none m-0 p-0" itemscope itemtype="https://schema.org/BreadcrumbList">
            <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem" class="flex items-center gap-1.5">
                <a href="{{ locale_link('/') }}" itemprop="item" class="hover:text-accent transition-colors">
                    <span itemprop="name">{{ __('nav.home') }}</span>
                </a>
                <meta itemprop="position" content="1">
                <svg viewBox="0 0 24 24" class="size-3 text-ink-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m9 5 7 7-7 7"/>
                </svg>
            </li>

            {% for item in items %}
                <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem" class="flex items-center gap-1.5">
                    {% if item.href is defined and not loop.last %}
                        <a href="{{ locale_link(item.href) }}" itemprop="item" class="hover:text-accent transition-colors">
                            <span itemprop="name">{{ item.label }}</span>
                        </a>
                        <meta itemprop="position" content="{{ loop.index + 1 }}">
                        <svg viewBox="0 0 24 24" class="size-3 text-ink-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                            <path stroke-linecap="round" stroke-linejoin="round" d="m9 5 7 7-7 7"/>
                        </svg>
                    {% else %}
                        <span itemprop="name" class="text-ink font-medium" aria-current="page">{{ item.label }}</span>
                        <meta itemprop="position" content="{{ loop.index + 1 }}">
                    {% endif %}
                </li>
            {% endfor %}
        </ol>
    </nav>
{% endif %}
```
```twig
{#
  Pure Component: Empty State
  Rules: Zero setcontent.

  Props:
    - message (string|optional): Description of the empty state (default: empty.message)
    - title (string|optional): Heading (default: empty.title)
    - icon (string|optional): SVG or icon
    - action_label (string|optional): Button text
    - action_href (string|optional): Button link

  Translation keys: empty.title, empty.message
#}

<div class="py-16 px-6 text-center flex flex-col items-center justify-center max-w-md mx-auto">
    <div class="size-16 rounded-full bg-surface text-ink-3 flex items-center justify-center mb-4">
        {% if icon is defined and icon is not empty %}
            {{ icon|raw }}
        {% else %}
            <svg viewBox="0 0 24 24" class="size-8" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"/>
            </svg>
        {% endif %}
    </div>

    <h3 class="text-lg font-semibold text-ink mb-1">
        {{ title|default(__('empty.title')) }}
    </h3>

    <p class="text-sm text-ink-2 mb-6">
        {{ message|default(__('empty.message')) }}
    </p>

    {% if action_label is defined and action_href is defined %}
        {% include 'components/ui/button.twig' with {
            label: action_label,
            href: action_href,
            variant: 'outline',
            size: 'sm'
        } %}
    {% endif %}
</div>
```

### G. Smart Contact Containers (`containers/contact/`)
```twig
{#
  Smart Container: Reusable Contact Section
  Rules: Reads contact details from theme.yaml (contact.phone, contact.email,
         contact.address, contact.hours) and renders contact cards plus call/e-mail CTAs.
  The section id "kontakt" is the target of `/#kontakt` menu links (bolt-menu).

  Translation keys: contact.eyebrow, contact.title, contact.description, contact.phone_label,
                    contact.email_label, contact.reply_time, contact.address_label
#}

{% set phone = config.get('theme/contact/phone') %}
{% set email = config.get('theme/contact/email') %}
{% set address = config.get('theme/contact/address') %}
{% set hours = config.get('theme/contact/hours') %}

<section id="kontakt" aria-labelledby="contact-title" class="py-section bg-surface border-t border-stroke">
    <div class="wrapper px-edge flex flex-col lg:flex-row items-start justify-between gap-12">

        {# Left Column: Heading and intro #}
        <div class="flex flex-col gap-4 max-w-lg">
            <span class="eyebrow">{{ __('contact.eyebrow') }}</span>
            <h2 id="contact-title" class="font-display text-section font-semibold text-ink">
                {{ __('contact.title') }}
            </h2>
            <p class="text-lead text-ink-2 leading-relaxed">
                {{ __('contact.description') }}
            </p>

            <div class="pt-4 flex flex-wrap gap-4">
                {% if phone %}
                    {% include 'components/ui/button.twig' with {
                        label: phone,
                        href: 'tel:' ~ phone|replace({' ': ''}),
                        variant: 'primary',
                        size: 'md'
                    } %}
                {% endif %}
                {% if email %}
                    {% include 'components/ui/button.twig' with {
                        label: email,
                        href: 'mailto:' ~ email,
                        variant: 'outline',
                        size: 'md'
                    } %}
                {% endif %}
            </div>
        </div>

        {# Right Column: Contact Cards Grid #}
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 w-full lg:max-w-xl">
            {% if phone %}
                <div class="card p-6 flex flex-col gap-2">
                    <span class="eyebrow">{{ __('contact.phone_label') }}</span>
                    <a href="tel:{{ phone|replace({' ': ''}) }}" class="text-lg font-bold text-ink hover:text-accent transition-colors">
                        {{ phone }}
                    </a>
                    {% if hours %}
                        <span class="text-meta text-ink-3">{{ hours }}</span>
                    {% endif %}
                </div>
            {% endif %}

            {% if email %}
                <div class="card p-6 flex flex-col gap-2">
                    <span class="eyebrow">{{ __('contact.email_label') }}</span>
                    <a href="mailto:{{ email }}" class="text-lg font-bold text-ink hover:text-accent transition-colors break-all">
                        {{ email }}
                    </a>
                    <span class="text-meta text-ink-3">{{ __('contact.reply_time') }}</span>
                </div>
            {% endif %}

            {% if address %}
                <div class="card p-6 flex flex-col gap-2 sm:col-span-2">
                    <span class="eyebrow">{{ __('contact.address_label') }}</span>
                    <p class="text-base font-semibold text-ink leading-snug">
                        {{ address }}
                    </p>
                </div>
            {% endif %}
        </div>
    </div>
</section>
```
```twig
{#
  Smart Container: Compact Contact CTA Banner
  A lighter alternative to _contact-section.twig for the end of listing and detail pages:
  one sentence and a single button to the contact page (or the #kontakt section).

  Props:
    - href (string|optional): CTA target (default: '/kontakt')

  Translation keys: contact.banner_title, contact.banner_text, contact.banner_cta
#}

<section aria-labelledby="contact-banner-title" class="py-section">
    <div class="wrapper px-edge">
        <div class="bg-night text-night-ink rounded-md p-8 sm:p-12 flex flex-col md:flex-row items-center justify-between gap-8">
            <div class="max-w-xl">
                <h2 id="contact-banner-title" class="font-display text-section font-semibold tracking-tight">
                    {{ __('contact.banner_title') }}
                </h2>
                <p class="mt-3 text-lead text-night-ink-2">
                    {{ __('contact.banner_text') }}
                </p>
            </div>
            <div class="shrink-0 flex flex-wrap gap-4">
                {% include 'components/ui/button.twig' with {
                    label: __('contact.banner_cta'),
                    href: href|default('/kontakt'),
                    variant: 'primary',
                    size: 'lg'
                } %}
            </div>
        </div>
    </div>
</section>
```

### H. Smart Featured Products Container (`containers/products/_featured-products.twig`)
The homepage stays free of `setcontent`: the query lives in this container.
```twig
{#
  Smart Container: Featured Products
  Fetches the newest published products and renders them as cards. Used by the
  homepage; any page can include it (it owns its own query, so pages stay free of setcontent).

  Props:
    - limit (int|optional): Number of products (default: 3)
    - contenttype (string|optional): ContentType slug (default: 'products')

  Translation keys: homepage.featured_eyebrow, homepage.featured_title, homepage.all_products
#}
{% import 'macros.twig' as macros %}

{# setcontent throws for an unknown ContentType, so check that it is defined first. #}
{% set ct_slug = contenttype|default('products') %}
{% set featured_products = [] %}
{% if config.get('contenttypes/' ~ ct_slug) %}
    {% setcontent featured_products = ct_slug limit (limit|default(3)) %}
{% endif %}

{% if featured_products is not empty %}
    <section aria-labelledby="featured-products-title" class="py-section">
        <div class="wrapper px-edge">
            {% include 'components/ui/section-header.twig' with {
                title: __('homepage.featured_title'),
                title_id: 'featured-products-title',
                eyebrow: __('homepage.featured_eyebrow'),
                layout: 'split',
                link: { label: __('homepage.all_products'), href: '/produkty' }
            } %}

            <ul role="list" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                {% for item in featured_products %}
                    <li class="flex">
                        {% include 'components/ui/card.twig' with {
                            title: item|title,
                            href: item|link,
                            image: item.image|default(null),
                            badge: item.category|default(null),
                            description: item.perex|default(item.teaser|default(null)),
                            price: item.price is defined and item.price ? macros.formatPrice(item.price) : null,
                            edit_url: item|edit_link
                        } %}
                    </li>
                {% endfor %}
            </ul>
        </div>
    </section>
{% endif %}
```

### I. Homepage Orchestrator & Page-Scoped Components (`pages/homepage/`)
```twig
{% extends 'partials/_master.twig' %}

{#
  Page Orchestrator: Homepage
  Rules: Zero raw HTML. Pure composition of page-scoped components and containers;
         data queries live in containers (containers/products/_featured-products.twig).
  Bound by the root index.twig: {% extends 'pages/homepage/homepage.twig' %}
#}

{% block main %}
    {# 1. Hero Banner (page-scoped component) #}
    {% include 'pages/homepage/components/hero.twig' with { record: record } %}

    {# 2. Key numbers (page-scoped component; renders only when the record has metrics) #}
    {% if record.metrics is defined %}
        {% include 'pages/homepage/components/hero-metrics.twig' with {
            items: record.metrics,
            class: 'wrapper px-edge'
        } %}
    {% endif %}

    {# 3. Featured Products (smart container — owns its setcontent query). Scaffolded only
          for sites with a `products` ContentType, hence `ignore missing`. #}
    {% include 'containers/products/_featured-products.twig' ignore missing with { limit: 3 } %}

    {# 4. Reusable Contact Section Container #}
    {% include 'containers/contact/_contact-section.twig' %}
{% endblock main %}
```
```twig
{#
  Page-Scoped Pure Component: Homepage Hero Banner
  Scope: Exclusive to pages/homepage/homepage.twig
  Rules: Zero setcontent. Reads only the record passed in.

  Props:
    - record: the homepage singleton (fields hero_title, hero_subtitle, hero_eyebrow,
              hero_cta_label, hero_cta_link — all optional)

  Translation keys: hero.eyebrow, hero.primary_cta, hero.contact_cta
#}
{% import 'macros.twig' as macros %}

{% set title = record.hero_title|default(config.get('general/sitename')) %}
{% set subtitle = record.hero_subtitle|default(config.get('general/payoff')) %}
{% set primary_cta = record.hero_cta_label|default(__('hero.primary_cta')) %}
{% set primary_link = record.hero_cta_link|default('/produkty') %}

<section class="relative bg-night text-night-ink overflow-hidden py-20 lg:py-32">
    <div class="wrapper px-edge relative z-10 flex flex-col items-center text-center max-w-4xl mx-auto">
        <span class="text-xs sm:text-sm font-bold tracking-widest uppercase text-accent-ink-2 mb-4">
            {{ record.hero_eyebrow|default(__('hero.eyebrow')) }}
        </span>

        <h1 class="font-display text-hero font-semibold tracking-tight leading-tight mb-6">
            {{ macros.typo(title) }}
        </h1>

        {% if subtitle %}
            <p class="text-lead text-night-ink-2 max-w-2xl leading-relaxed mb-8">
                {{ subtitle }}
            </p>
        {% endif %}

        <div class="flex flex-wrap items-center justify-center gap-4">
            {% include 'components/ui/button.twig' with {
                label: primary_cta,
                href: primary_link,
                variant: 'primary',
                size: 'lg'
            } %}

            {% include 'components/ui/button.twig' with {
                label: __('hero.contact_cta'),
                href: '/#kontakt',
                variant: 'light-outline',
                size: 'lg'
            } %}
        </div>
    </div>
</section>
```
```twig
{#
  Page-Scoped Pure Component: Hero Metrics (key numbers under the hero)
  Scope: Exclusive to pages/homepage/ — keeps the root components/ folder clean.
  Rules: Zero setcontent. Data comes from the homepage record.

  Props:
    - items (iterable): list of { value, label }, e.g. a `metrics` collection on the homepage
      singleton:  metrics: { type: collection, fields: { metric: { type: set, fields:
                  { value: { type: text }, label: { type: text, localize: true } } } } }
      Example data: { value: '10+ let', label: 'Zkušenosti' }, { value: '150+', label: 'Klientů' },
                    { value: '99 %', label: 'Spokojenost' }
    - class (string|optional)
#}

{% if items is defined and items|length > 0 %}
    <dl class="grid grid-cols-2 sm:grid-cols-3 gap-6 pt-6 border-t border-stroke {{ class|default('') }}">
        {% for item in items %}
            <div>
                <dt class="eyebrow">{{ item.label }}</dt>
                <dd class="font-display text-section font-semibold text-accent mt-1">{{ item.value }}</dd>
            </div>
        {% endfor %}
    </dl>
{% endif %}
```

### J. Listing Page Orchestrator (`pages/product/product.twig`)
```twig
{% extends 'partials/_master.twig' %}

{#
  Page Orchestrator: Products Listing
  Bound by the products ContentType: listing_template: pages/product/product.twig
  (or a root entrypoint product.twig containing {% extends 'pages/product/product.twig' %}).
  Receives `records` (a Pagerfanta) from Bolt's listing route.
  Rules: Near-zero raw HTML — layout wrappers only; everything else is components/containers.
#}
{% import 'macros.twig' as macros %}

{% block main %}
    {# 1. Breadcrumbs #}
    <div class="wrapper px-edge">
        {% include 'components/ui/breadcrumbs.twig' with {
            items: [ { label: __('products.title') } ]
        } %}
    </div>

    {# 2. Listing Section #}
    <section aria-labelledby="products-listing-title" class="wrapper px-edge pb-section">
        {% include 'components/ui/section-header.twig' with {
            title: __('products.title'),
            title_id: 'products-listing-title',
            eyebrow: __('products.eyebrow'),
            lead: __('products.perex'),
            heading_level: 1,
            layout: 'center'
        } %}

        {% if records is defined and records|length > 0 %}
            {# role="list" keeps list semantics in Safari when list-style is removed #}
            <ul role="list" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                {% for item in records %}
                    <li class="flex">
                        {% include 'components/ui/card.twig' with {
                            title: item|title,
                            href: item|link,
                            image: item.image|default(item.teaser_image|default(null)),
                            badge: item.category|default(null),
                            badge_markup: item.stock is defined
                                ? include('pages/product/components/stock-badge.twig', { stock: item.stock })
                                : null,
                            description: item.perex|default(item.teaser|default(item|excerpt(100))),
                            price: item.price is defined and item.price ? macros.formatPrice(item.price) : null,
                            edit_url: item|edit_link
                        } %}
                    </li>
                {% endfor %}
            </ul>

            {# 3. Pagination — Bolt's pager() with the theme's pagination component #}
            {{ pager(records, template = 'components/ui/pagination.twig') }}
        {% else %}
            {# Empty state fallback #}
            {% include 'components/ui/empty-state.twig' with {
                title: __('products.empty_title'),
                message: __('products.empty_message'),
                action_label: __('nav.home'),
                action_href: '/'
            } %}
        {% endif %}
    </section>

    {# 4. Reusable Contact Container #}
    {% include 'containers/contact/_contact-banner.twig' %}
{% endblock main %}
```

### K. Record Detail Orchestrator (`pages/product/product.record.twig`)
```twig
{% extends 'partials/_master.twig' %}

{#
  Page Orchestrator: Product Record Detail
  Bound by the products ContentType: record_template: pages/product/product.record.twig
  (or a root entrypoint product.record.twig).
  Rules: Orchestrates shared pure components (breadcrumbs, picture, badge, button),
         page-scoped components (spec-table.twig, stock-badge.twig) and containers.
#}
{% import 'macros.twig' as macros %}

{% block main %}
    {# 1. Breadcrumbs + admin edit link #}
    <div class="wrapper px-edge flex items-center justify-between gap-4">
        {% include 'components/ui/breadcrumbs.twig' with {
            items: [
                { label: __('products.title'), href: '/produkty' },
                { label: record|title }
            ]
        } %}
        {{ macros.edit(record) }}
    </div>

    {# 2. Main Product Showcase #}
    <article class="wrapper px-edge py-10 lg:py-16">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-start">

            {# Left: Media. One PhotoSwipe gallery for the main image and the thumbnails. #}
            <div class="photoswipe-gallery flex flex-col gap-4">
                {% if record.image is defined and record.image is not empty %}
                    <div class="rounded-md overflow-hidden border border-stroke aspect-4/3 bg-surface">
                        {% include 'components/ui/picture.twig' with {
                            image: record.image,
                            alt: record|title,
                            aspect: 'aspect-4/3',
                            loading: 'eager',
                            pswp: true
                        } %}
                    </div>
                {% else %}
                    <div class="rounded-md border border-stroke aspect-4/3 bg-surface flex items-center justify-center text-ink-3">
                        {{ __('products.no_image') }}
                    </div>
                {% endif %}

                {% if record.gallery is defined and record.gallery|length > 0 %}
                    <div class="grid grid-cols-4 gap-3">
                        {% for thumb in record.gallery %}
                            <div class="rounded-sm overflow-hidden aspect-square border border-stroke hover:border-accent transition-colors">
                                {% include 'components/ui/picture.twig' with {
                                    image: thumb,
                                    alt: (record|title) ~ ' – ' ~ loop.index,
                                    aspect: 'aspect-square',
                                    pswp: true
                                } %}
                            </div>
                        {% endfor %}
                    </div>
                {% endif %}
            </div>

            {# Right: Overview, price, availability and inquiry CTA #}
            <div class="flex flex-col gap-6">
                <div class="flex flex-wrap items-center gap-3">
                    {% if record.category is defined and record.category is not empty %}
                        {% include 'components/ui/badge.twig' with {
                            label: record.category,
                            variant: 'accent',
                            size: 'md'
                        } %}
                    {% endif %}
                    {% if record.stock is defined %}
                        {% include 'pages/product/components/stock-badge.twig' with { stock: record.stock } %}
                    {% endif %}
                </div>

                <h1 class="font-display text-section font-semibold text-ink leading-tight">
                    {{ macros.typo(record|title) }}
                </h1>

                {% if record.price is defined and record.price is not empty %}
                    <p class="font-display text-section font-semibold text-accent">
                        {{ macros.formatPrice(record.price) }}
                    </p>
                {% endif %}

                {% if record.perex is defined and record.perex is not empty %}
                    <p class="text-lead text-ink-2 leading-relaxed font-medium">
                        {{ record.perex }}
                    </p>
                {% elseif record.teaser is defined and record.teaser is not empty %}
                    <p class="text-lead text-ink-2 leading-relaxed font-medium">
                        {{ record.teaser }}
                    </p>
                {% endif %}

                {# Page-Scoped Component: Specifications Table #}
                {% if record.specs is defined and record.specs|length > 0 %}
                    {% include 'pages/product/components/spec-table.twig' with {
                        specs: record.specs,
                        title: __('products.technical_specs')
                    } %}
                {% endif %}

                <div class="pt-4 flex flex-wrap gap-4">
                    {# '#kontakt' scrolls to the contact section below. To open a contact page with
                       the product preselected instead: '/kontakt?produkt=' ~ record.slug #}
                    {% include 'components/ui/button.twig' with {
                        label: __('products.inquire_cta'),
                        href: '#kontakt',
                        variant: 'primary',
                        size: 'lg'
                    } %}
                </div>
            </div>
        </div>

        {# 3. Rich Text Content (redactor/article output is already safe HTML) #}
        {% if record.body is defined and record.body is not empty %}
            <div class="mt-16 pt-12 border-t border-stroke max-w-4xl">
                <div class="cms-redactor">
                    {{ record.body }}
                </div>
            </div>
        {% endif %}
    </article>

    {# 4. Reusable Contact Section Container (target of '#kontakt') #}
    {% include 'containers/contact/_contact-section.twig' %}
{% endblock main %}
```

### L. Page-Scoped Product Components (`pages/product/components/`)
```twig
{#
  Page-Scoped Pure Component: Stock Badge
  Scope: products pages (pages/product/). Uses Tailwind's emerald on purpose: availability
  is a status colour, not part of the brand palette.

  Props:
    - stock (int|null): Number of items in stock

  Translation keys: products.in_stock (with %count%), products.on_request
#}
{% if stock is defined and stock > 0 %}
    <span class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
        <span class="size-1.5 rounded-full bg-emerald-500 motion-safe:animate-pulse" aria-hidden="true"></span>
        {{ __('products.in_stock', { '%count%': stock }) }}
    </span>
{% else %}
    <span class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-surface text-ink-2 border border-stroke">
        {{ __('products.on_request') }}
    </span>
{% endif %}
```
```twig
{#
  Page-Scoped Pure Component: Product Specifications Table
  Scope: Exclusive to pages/product/product.record.twig
  Rules: Zero setcontent. Pure presentation of specs or collection sets.

  Props:
    - specs (array|iterable): List of { label, value }
    - title (string|optional): Heading
#}

{% if specs is defined and specs|length > 0 %}
    <div class="my-8 overflow-hidden rounded-sm border border-stroke">
        {% if title is defined and title is not empty %}
            <div class="bg-surface px-5 py-3 border-b border-stroke">
                <h3 class="font-bold text-sm uppercase tracking-wider text-ink">{{ title }}</h3>
            </div>
        {% endif %}

        <table class="w-full text-left text-sm border-collapse">
            <tbody class="divide-y divide-stroke">
                {% for item in specs %}
                    <tr class="hover:bg-surface transition-colors">
                        <th scope="row" class="px-5 py-3.5 font-medium text-ink-2 w-1/3">
                            {{ item.label }}
                        </th>
                        <td class="px-5 py-3.5 font-semibold text-ink">
                            {{ item.value }}
                        </td>
                    </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
{% endif %}
```

---

## 4. Translations

Every visible string is a dotted translation key (`products.title`, `card.read_more`, `contact.title`, `a11y.breadcrumbs`, …). `examples/translations.cs.xlf` and `examples/translations.en.xlf` contain all units these templates use (XLIFF 2.0, Czech defaults and English). Merge them into each catalog of the project:

```bash
php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php \
    vendor/tomvondracek/bolt-skills/skills/bolt-theme-templates/examples/translations.cs.xlf translations/messages.cs.xlf
php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php \
    vendor/tomvondracek/bolt-skills/skills/bolt-theme-templates/examples/translations.en.xlf translations/messages.en.xlf
```

The helper only adds missing units (by key) and never changes existing translations. For other locales, merge the English catalog into `messages.<locale>.xlf` and translate the targets.

> [!WARNING]
> Do not write `__('key')|default('Text')`. The translator returns the key itself when a translation is missing, so the default never renders and the page shows `key`. Add the key to every catalog instead (the verification script reports this pattern).

---

## 5. Automation & Verification Runbook

### Scaffolding Command (`scripts/scaffold.sh`)
Scaffolds the pure UI component library, the contact containers, the homepage orchestrator with its page-scoped components and — for catalog sites — the product pages:

```bash
bash skills/bolt-theme-templates/scripts/scaffold.sh [--force] [--products=auto|yes|no]
```

- Existing files are kept; files still carrying `bolt-theme-init`'s `{# bolt-theme-init:placeholder #}` marker (the placeholder homepage) are replaced. `--force` replaces everything.
- `--products=auto` (default) adds `pages/product/`, `containers/products/_featured-products.twig` and the root entrypoints `product.twig` / `product.record.twig` only when `contenttypes.yaml` defines a top-level `products:` ContentType.

### Verification Command (`scripts/verify.sh`)
Audits theme architecture compliance:

```bash
bash skills/bolt-theme-templates/scripts/verify.sh
```

**Automated Audits:**
1. **Active theme** detected from `config/bolt/config.yaml`.
2. **Architectural Structure**: `components/`, `containers/`, `pages/`, and `partials/_master.twig` defining `{% block main %}`.
3. **Pure Component Rule**: Greps all `.twig` files in every `components/` folder (root and page-scoped) and **fails if any `setcontent` is detected**.
4. **Page Orchestrator Conventions**: every template in `pages/` (outside `components/`) `{% extends %}` a layout.
5. **Locale Link Safety**: Audits `locale_link(...)` wrapping on template URLs.
6. **Translation trap**: reports `__('key')|default(...)`.
7. **Undefined classes**: colour/token utilities used in templates but missing from the compiled `css/index.css` (e.g. a token name that `bolt-tailwind-theme` does not define).
8. **Twig Syntax Linting**: Runs `bin/console lint:twig public/theme/<active_theme>` to catch any syntax bugs.

Raw HTML in page orchestrators is a judgement call and is not checked automatically; review pages against the rule in section 1.

---

## 6. Common Pitfalls & Solutions

| Pitfall | Symptom | Fix |
| :--- | :--- | :--- |
| **`setcontent` in a pure component** | Component breaks or queries DB multiple times when rendered in a loop. | Move the query to a smart container in `containers/` or page orchestrator; pass data to component via props. |
| **Raw HTML in page orchestrators** | Inconsistent markup, duplication between pages, difficult responsive refactoring. | Extract reusable HTML sections into `containers/` and presentational elements into `components/ui/`. |
| **Un-scoped one-off components** | Global `components/` folder gets cluttered with one-time tables or hero banners. | Scope page-specific components in `pages/<page>/components/<comp>.twig`. |
| **Hardcoded URLs without `locale_link()`** | Language switcher breaks or user jumps back to default language. | Always wrap links in `{{ locale_link(item.href) }}` (the button component does it for `href`). |
| **Dynamic Tailwind class interpolation** | `bg-{{ color }}-500` classes are purged by Tailwind v4. | Use lookup maps (e.g. `variant_map = { 'primary': 'bg-accent' }`) with full static class strings. |
| **Colour names outside the token set** (`brand`, `ink-800`, `zinc-*`) | No CSS is generated; components render unstyled. | Use the `bolt-tailwind-theme` tokens; the verification lists missing classes. |
| **Stretched link without `relative`** | The click overlay covers the whole section or page. | `relative` on the card root. |
| **Bolt 3 pager API** (`records.pager`, `pager.totalpages`, `makelink`) | Pagination never renders on Bolt 5/6. | `{{ pager(records, template = 'components/ui/pagination.twig') }}` (Pagerfanta). |
| **PhotoSwipe attributes on `<img>`** | The lightbox never opens. | `a.photoswipe-gallery__link` inside `.photoswipe-gallery` (`picture.twig` with `pswp: true`). |
| **`__('key')\|default('…')`** | The key is shown instead of the text. | Add the key to every catalog. |
