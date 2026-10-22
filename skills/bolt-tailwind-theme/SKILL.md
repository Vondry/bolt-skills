---
name: bolt-tailwind-theme
description: >-
  Use this skill whenever setting up, extracting, or updating Tailwind CSS v4 design
  tokens, @theme configurations, font-face definitions, and repeating utility classes
  from handed-off designs (Figma, Penpot, or design specs) in Bolt CMS themes. Establishes
  WCAG AA contrast targets, fluid clamp() typography, Czech latin-ext font ranges, @source
  scanning safeguards, and the complete blueprint of cross-project repeating utility
  classes (wrapper, px-edge, py-section, btn variants, card, link-arrow, pagination,
  and .cms-redactor).
---

# Bolt CMS Tailwind Theme Tokens & Utilities Standard

In modern Bolt CMS frontend themes, [Tailwind CSS v4](https://tailwindcss.com) serves as the design token engine and utility vocabulary. Before any Twig templates or components are created, the CSS foundation must be systematically extracted from the design hand-off (Figma, Penpot, or design specs) and established inside `public/theme/<theme>/css/tailwind/index.css`.

This skill synthesizes the proven design token architecture, scanning rules, and repeating utility classes established across production Bolt CMS projects. The token **names** defined here are part of the Integration Contract (`WORKFLOWS.md`): `bolt-theme-init`'s baseline, `bolt-menu`, `bolt-theme-templates`, `bolt-cookie-consent` and `bolt-helper-pages` all use them, so keep the names and change only the values.

---

## 1. Core Architecture of `css/tailwind/index.css`

The theme entrypoint file `css/tailwind/index.css` is structured into five deterministic sections:

```text
css/tailwind/index.css
├── 1. Scanning Directives (@source)
│      ├── translations/ scanner
│      ├── config/bolt/menu.yaml scanner
│      └── SAFEGUARDS: ignore ../index.css output, README.md & helper-pages/
│
├── 2. Design Tokens (@theme static inline)
│      ├── Breakpoints (--breakpoint-menu, etc.)
│      ├── Layout & Header offsets (--spacing-header)
│      ├── Themed Surface & Ink scales (--color-canvas, --color-surface, --color-ink)
│      ├── Brand & Contrast Accent palettes (--color-accent, --color-brand)
│      ├── Dark Zone / Night palette (--color-night)
│      ├── Fluid Typography Curves (clamp formulas)
│      └── Keyframe Animations (fade-in, dialog, skeleton)
│
├── 3. Root Palette & Contrast Baseline (:root)
│      └── CSS variables with documented WCAG AA contrast ratios
│
├── 4. Base Layer Resets & Fonts (@layer base)
│      ├── Self-hosted Latin + Latin-ext WOFF2 font-faces (Czech glyphs)
│      ├── Sticky header anchor scroll offset (:where([id]))
│      └── Accessible focus-visible & text selection
│
└── 5. Repeating Utility Classes (@utility & @layer components)
       ├── Layout: .wrapper, .px-edge, .py-section, .no-scrollbar
       ├── Typography: .eyebrow, .eyebrow-rule, .mono, .badge, .tag
       ├── Buttons: .btn, .btn-primary, .btn-secondary, .btn-outline, .btn-on-accent
       ├── Cards & Links: .card, .link-arrow
       ├── Navigation & Pager: .pagination, .dropdown, .rotate-svg
       └── CMS Redactor Prose: .cms-redactor, .cms-article, .cms-redactor-on-accent
```

---

## 2. Scanning Directives & Compilation Safeguards

Tailwind CSS v4 replaces the v3 `content` array with `@source` directives. To ensure all classes are captured while preventing build loops, configure:

```css
@import 'tailwindcss';

/* 1. Scan the translation catalogs in the project root */
@source "../../../../../translations";

/* 2. Scan Bolt's menu configuration (classes of menu items) */
@source "../../../../../config/bolt/menu.yaml";

/* 3. CRITICAL SAFEGUARD: never scan the build output itself.
      css/index.css is the compiled file. Without this line every class that was ever
      generated would stay in the build forever. */
@source not "../index.css";

/* 4. Ignore documentation that mentions old class names */
@source not "../../README.md";

/* 5. Helper/error pages ship their own scoped styles — their one-off classes must not
      grow the main bundle (bolt-helper-pages) */
@source not "../../helper-pages";
```

---

## 3. Design Tokens Blueprint (`@theme static inline` & `:root`)

Configure tokens in `@theme static inline`:

* **`inline`** — utilities use the token's value directly. Tokens that point at a `:root` variable (`--color-ink: var(--ink)`) therefore follow that variable at runtime.
* **`static`** — every token is also emitted as a CSS variable (`--color-accent: …`) even when no utility uses it. Without it, Tailwind v4 emits only variables something references: a build where no CSS reads `var(--color-accent)` has no `--color-accent` at all (tested with Tailwind 4.3.3), and the helper pages' scoped styles — which are excluded from scanning and read `var(--color-accent)` — silently fall back to their hard-coded colours.

> [!NOTE]
> The values below are **neutral placeholders** (a slate/blue palette and the open-source fonts Source Serif 4, Source Sans 3 and JetBrains Mono) that already meet the WCAG AA rules of section 6. Replace every value with the one extracted from the design; keep the token **names** — the templates of `bolt-theme-init`, `bolt-menu`, `bolt-theme-templates`, `bolt-cookie-consent` and `bolt-add-language` use them.

```css
@theme static inline {
    /* --- Layout Breakpoints --- */
    --breakpoint-2xs: 24rem;       /* 384px */
    --breakpoint-xs: 36rem;        /* 576px */
    --breakpoint-menu: 62rem;      /* Where the desktop bar replaces the burger menu */
    --breakpoint-3xl: 112.5rem;    /* 1800px */

    /* --- Sticky header height --- */
    --spacing-header: 4.5rem;      /* Drives the header bar height and the scroll margin of anchors */

    /* --- Font families --- */
    --font-display: 'Source Serif 4', ui-serif, Georgia, serif;
    --font-body: 'Source Sans 3', ui-sans-serif, system-ui, sans-serif;
    --font-mono: 'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace;

    /* --- Povrchy a Inky (propojeno s :root) --- */
    --color-canvas: var(--canvas);
    --color-surface: var(--surface);
    --color-surface-2: var(--surface-2);
    --color-ink: var(--ink);
    --color-ink-2: var(--ink-2);
    --color-ink-3: var(--ink-3);
    --color-stroke: var(--stroke);

    /* --- Brand / primary accent --- */
    --color-accent: #1d4ed8;
    --color-accent-hover: #1e40af;
    --color-accent-soft: #dbeafe;
    --color-accent-ink: #ffffff;
    --color-accent-ink-2: #bfdbfe;

    /* --- Night zone (fixed dark palette for the footer and dark bands) --- */
    --color-night: #0f172a;
    --color-night-deep: #020617;
    --color-night-stroke: #1e293b;
    --color-night-ink: #ffffff;
    --color-night-ink-2: #cbd5e1;
    --color-night-ink-3: #94a3b8;

    /* --- Fluid heading sizes clamp(min, base + vw, max) --- */
    --text-hero: clamp(2.25rem, 1.5rem + 3vw, 4rem);
    --text-section: clamp(1.75rem, 1rem + 2.5vw, 2.75rem);
    --text-card: clamp(1.125rem, 0.95rem + 0.7vw, 1.375rem);

    /* --- Copy type scale: 11 / 13 / 15 / 17 px --- */
    --text-micro: 0.6875rem;       /* 11px — labels, badges, uppercase annotations */
    --text-meta: 0.8125rem;        /* 13px — meta, captions, compact buttons */
    --text-body: 0.9375rem;        /* 15px — body text */
    --text-lead: 1.0625rem;        /* 17px — lead paragraph */

    /* --- Easing and animations --- */
    --ease-out-soft: cubic-bezier(0.22, 1, 0.36, 1);
    --animate-fade-in: fade-in 0.5s ease-in-out;
    --animate-dialog: dialog 0.3s ease-in-out;
    --animate-skeleton: skeleton 1.8s ease-in-out infinite;

    @keyframes fade-in {
        0% { opacity: 0; }
        100% { opacity: 1; }
    }
    @keyframes dialog {
        0% { opacity: 0.2; transform: translateY(-15%); }
        100% { opacity: 1; transform: translateY(0); }
    }
    @keyframes skeleton {
        0%, 100% { background-color: var(--color-stroke, #e2e8f0); }
        50% { background-color: var(--color-surface-2, #f1f5f9); }
    }
}

:root {
    /* Hairlines and borders in rem (they scale with the root font size) */
    --hairline: 0.0625rem;

    --canvas: #ffffff;
    --surface: #f8fafc;
    --surface-2: #f1f5f9;
    --ink: #0f172a;
    --ink-2: #475569;
    /* Lightest ink: 5.44:1 on --canvas, 5.2:1 on --surface, 4.97:1 on --surface-2 (WCAG AA) */
    --ink-3: #5b6b80;
    --stroke: #e2e8f0;
}
```

### Tokens over arbitrary values
Templates use the token utilities (`rounded-card`, `text-meta`, `tracking-label`, `pt-page`), never the arbitrary form of the same value (`rounded-[var(--radius-card)]`, `text-[0.9375rem]`). When a value repeats in two or more templates with the same meaning, add it here as a token named by its role (`--tracking-label`, `--spacing-page`, `--text-page` with `--text-page--line-height`, `--breakpoint-3xs`) instead of repeating the arbitrary class. `bolt-theme-templates` checks it: the IDE's "can be written as" warning while editing, and `scripts/canonical-classes.mjs` (Tailwind's own `canonicalize`) in `verify.sh`, which also rewrites the templates with `--fix`. One-off design measurements stay arbitrary.

---

## 4. Self-Hosted Fonts with Czech Support (`unicode-range`)

Fonts are self-hosted in `public/theme/<theme>/css/fonts/`: loading them from Google Fonts sends every visitor's IP address to Google before any consent (GDPR), and late-loading fonts shift the layout (CLS).

Czech (**ě, š, č, ř, ž, ý, á, í, é, ů, ú, ň, ť, ď**) **requires** both the `Latin` and the `Latin-ext` range:

```css
@layer base {
    /* Latin (basic) — every family needs both the latin and the latin-ext file */
    @font-face {
        font-family: 'Source Sans 3';
        font-style: normal;
        font-weight: 200 900;
        font-display: swap;
        src: url(fonts/source-sans-3/source-sans-3-latin.woff2) format('woff2');
        unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
    }

    /* Latin extended (contains the Czech diacritics) */
    @font-face {
        font-family: 'Source Sans 3';
        font-style: normal;
        font-weight: 200 900;
        font-display: swap;
        src: url(fonts/source-sans-3/source-sans-3-latin-ext.woff2) format('woff2');
        unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
    }

    /* Offset of anchor targets (#section), so the sticky header does not cover them */
    :where([id]) {
        scroll-margin-top: var(--spacing-header);
    }

    /* Accessible keyboard focus */
    :focus-visible {
        outline: 0.125rem solid var(--color-accent);
        outline-offset: 0.1875rem;
    }
}
```

---

## 5. Blueprint of Recurring Utilities and Classes

These utilities and classes recur in every production theme and are the building blocks of the Twig components:

### A. Layout
```css
/* Centred container capped at the artboard width (typically 1440px / max-w-360) */
@utility wrapper {
    @apply mx-auto w-full max-w-360;
}

/* Horizontal page gutter (distance from the screen edges) */
@utility px-edge {
    @apply px-6 sm:px-10 lg:px-20;
}

/* Vertical section rhythm */
@utility py-section {
    @apply py-12 lg:py-16;
}

/* Hide the scrollbar of horizontal swipe rows while keeping them scrollable */
@utility no-scrollbar {
    scrollbar-width: none;
    &::-webkit-scrollbar {
        display: none;
    }
}

/* Two consecutive sections of the same background share their vertical space */
section:where(.bg-canvas) + section:where(.bg-canvas) > .wrapper,
section:where(.bg-surface) + section:where(.bg-surface) > .wrapper {
    padding-top: 0;
}
```

### B. Typography, Labels and Annotations
```css
/* Small label above a section heading */
@utility eyebrow {
    @apply font-body uppercase text-micro font-medium tracking-[0.12em] text-ink-3;
}

/* Decorative line before the eyebrow label */
.eyebrow-rule {
    @apply inline-block h-0.25 w-6 shrink-0 bg-accent;
}

@utility mono {
    @apply font-mono uppercase text-xs tracking-wider;
}

@utility badge {
    @apply inline-flex items-center gap-1.5 font-mono uppercase text-xs tracking-wider px-2.5 py-0.5 rounded-full;
}

@utility tag {
    @apply inline-flex items-center text-xs px-2.5 py-1 rounded bg-surface-2 text-ink-2;
}
```

### C. Buttons and CTAs
```css
@utility btn {
    @apply inline-flex items-center justify-center gap-2 rounded-sm font-body text-body font-medium px-6 py-3 transition-colors cursor-pointer disabled:pointer-events-none disabled:opacity-50;
}

@utility btn-primary {
    @apply btn bg-accent text-white hover:bg-accent-hover;
}

@utility btn-secondary {
    @apply btn border border-ink text-ink hover:bg-ink hover:text-canvas;
}

@utility btn-outline {
    @apply btn border-ink text-ink hover:bg-ink hover:text-canvas;
    border-width: var(--hairline);
    border-style: solid;
}

@utility btn-ghost {
    @apply btn bg-transparent text-ink hover:text-accent hover:bg-surface;
}

/* Contrasting button pair for dark bands (dark contact section, footer) */
@utility btn-on-accent {
    @apply btn bg-white text-accent hover:bg-accent-soft;
}

@utility btn-on-accent-outline {
    @apply btn border-white/40 text-white hover:bg-white/10;
    border-width: var(--hairline);
    border-style: solid;
}
```

### D. Cards and Interactive Links
```css
/* Karta obsahu s jemnou linkou */
@utility card {
    @apply rounded-sm bg-canvas;
    border: var(--hairline) solid var(--color-stroke);
}

/* Link whose SVG arrow moves on hover */
@utility link-arrow {
    @apply inline-flex items-center gap-1.5 font-body text-meta font-medium text-accent transition-colors hover:text-ink;
}

.link-arrow svg {
    transition: transform 0.3s var(--ease-out-soft);
}

@media (hover: hover) {
    .link-arrow:hover svg {
        transform: translateX(0.25rem);
    }
}

@media (prefers-reduced-motion: reduce) {
    .link-arrow svg {
        transition: none;
    }
}
```

### E. Bolt Pager Styling (`.pagination`)
Bolt's `{{ pager() }}` renders `<ul class="pagination">`:
```css
.pagination {
    @apply flex flex-wrap items-center justify-center gap-2 m-0 p-0;
    list-style: none;
}
.pagination li a,
.pagination li > span {
    @apply inline-flex h-9 min-w-9 items-center justify-center px-3 font-mono text-xs tracking-widest border border-stroke text-ink-2 transition-colors duration-200;
}
.pagination li a:hover {
    @apply border-ink text-ink;
}
.pagination li.active a,
.pagination li a[aria-current] {
    @apply border-ink bg-ink text-canvas;
}
/* li.disabled: the gap marker of components/ui/pagination.twig; li[disabled]: older templates. */
.pagination li.disabled,
.pagination li[disabled],
.pagination li[disabled] a {
    @apply opacity-40 pointer-events-none;
}
```

### F. CMS Redactor Typography Wrapper (`.cms-redactor`)
Editors insert arbitrary HTML through Redactor (lists, quotes, headings). The `.cms-redactor` class scopes its styles:
```css
@layer components {
    .cms-redactor, .cms-article {
        ul, ol {
            list-style: initial;
            @apply m-0 pl-5;
        }

        a {
            @apply text-accent underline underline-offset-[0.125rem] transition-colors hover:text-ink;
        }

        :where(p, ul, ol, blockquote, pre, h2, h3, h4, h5)
        + :where(p, ul, ol, blockquote, pre, h2, h3, h4, h5) {
            @apply mt-4;
        }

        h2, h3, h4, h5 {
            @apply font-display text-card font-medium text-ink;
        }

        :where(p, ul, ol, blockquote, pre) + :where(h2, h3, h4, h5) {
            @apply mt-7;
        }

        blockquote {
            @apply pl-5 text-ink;
            border-left: var(--hairline) solid var(--color-accent);
        }

        strong, b {
            @apply font-semibold text-ink;
        }

        em, i {
            font-style: italic;
        }

        small {
            @apply text-meta text-ink-3;
        }

        pre {
            @apply overflow-x-auto rounded-sm bg-surface p-4 text-meta;
        }
    }

    /* Variant for text on a dark background */
    .cms-redactor-on-accent {
        a {
            @apply text-white hover:text-accent-ink-2;
        }
        h2, h3, h4, h5, strong, b, blockquote {
            @apply text-white;
        }
        blockquote {
            border-left-color: var(--color-accent-ink-2);
        }
        small {
            @apply text-accent-ink-2;
        }
    }
}
```

### G. Mobile Menu and Accordion Animation
Dropdown panels use `.dropdown` (`components/nav/dropdown.twig` of `bolt-menu`, the language switcher): `js/src/menu.ts` of `bolt-theme-init` animates their height between `0` and `scrollHeight` and toggles `aria-expanded` and `inert`. An arrow with `.rotate-svg` turns when its button has `aria-expanded="true"`.
```css
.dropdown {
    overflow: hidden;
    height: 0;
    transition: height 0.15s ease-in-out;
    max-width: calc(100vw - 2rem);
}

.rotate-svg {
    transition: transform 0.3s ease;
}

button[aria-expanded="true"] .rotate-svg {
    transform: rotate(180deg);
}

[data-dropdown-toggle] > * {
    pointer-events: none;
}
```

### H. Gallery Lightbox Caption (`.pswp__custom-caption`)
Every photo gallery opens in the PhotoSwipe 5 lightbox (`js/src/photoswipe.ts` of `bolt-theme-init`). Keep `@import '../../node_modules/photoswipe/dist/photoswipe.css';` right after `@import 'tailwindcss';`. The module registers a caption element filled from the slide's `.photoswipe-gallery__caption` (the image alt); style it with the night tokens so it stays readable over any photo:
```css
.pswp__custom-caption {
    position: absolute;
    z-index: 10;
    right: 0;
    bottom: 0;
    left: 0;
    padding: 1rem 1.5rem;
    background: linear-gradient(transparent, color-mix(in srgb, var(--color-night) 85%, transparent));
    @apply font-body text-sm text-night-ink text-center text-pretty pointer-events-none;
}
```

---

## 6. Extracting Tokens from a Design (Figma / Penpot / Pencil)

Work in this order:

1. **Header height (`--spacing-header`)**:
   - Measure the sticky navigation in the desktop and the mobile artboard. Set `--spacing-header` (e.g. `4.5rem`) and keep `:where([id]) { scroll-margin-top: var(--spacing-header); }` in the base layer.
2. **Colour scale and contrast (WCAG AA)**:
   - Surfaces: `--canvas`, `--surface`, `--surface-2`.
   - Text (inks): `--ink` (primary), `--ink-2` (secondary), `--ink-3` (annotations, labels).
   - **Contrast rule:** `--ink-3` needs at least **4.5:1** against `--canvas`, `--surface` **and** `--surface-2` (every surface text appears on). The same for `--night-ink-3` against `--night` and `--night-deep`.
3. **Fluid type with `clamp()`**:
   - Scale smoothly between the mobile (e.g. 375px) and the desktop artboard (e.g. 1440px):
     $$\text{clamp}(\text{min}, \text{base} + \text{slope} \cdot \text{vw}, \text{max})$$
   - Example: a hero heading from 36px on mobile to 64px on desktop:
     `--text-hero: clamp(2.25rem, 1.5rem + 3vw, 4rem);`
4. **Self-hosted fonts (WOFF2)**:
   - Download the weights as WOFF2, including the Latin-ext files for Czech.
   - Put them in `public/theme/<theme>/css/fonts/` and add the `@font-face` rules with `unicode-range`.
5. **Build and verify**:
   - Run `npm run build:css` in the theme folder.
   - Run the verification:
     ```bash
     ./skills/bolt-tailwind-theme/scripts/verify.sh
     ```

---

## 7. Automated Verification (`scripts/verify.sh`)

The script checks:
1. `public/theme/<theme>/css/tailwind/index.css` exists.
2. The `@source` rules, including the safeguard against scanning the build output (`@source not "../index.css"`).
3. The `@theme` block, `--spacing-header` and the accent colours.
4. The anchor offset (`scroll-margin-top`).
5. The recurring utilities (`@utility wrapper`, `@utility btn`, `.cms-redactor`).
6. The theme compiles with `@tailwindcss/cli` — into a temporary file, so the check never changes `css/index.css` — and the output defines `--color-accent` as a CSS variable (the helper pages read it).
