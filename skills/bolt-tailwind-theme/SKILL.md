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
├── 2. Design Tokens (@theme inline)
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

/* 1. Skenovat překladové soubory v kořeni projektu */
@source "../../../../../translations";

/* 2. Skenovat Bolt menu konfiguraci (třídy pro navigační položky) */
@source "../../../../../config/bolt/menu.yaml";

/* 3. KRITICKÝ SAFEGUARD: Zabránit zpětné vazbě s vlastním vygenerovaným výstupem.
      css/index.css je výsledný build. Bez této direktivy by každá jednou vygenerovaná
      třída zůstávala v buildu navždy aktivní! */
@source not "../index.css";

/* 4. Ignorovat dokumentaci obsahující zastaralé názvy tříd v textu */
@source not "../../README.md";

/* 5. Helper/error stránky mají vlastní scoped styly — jejich jednorázové třídy
      nesmí zvětšovat hlavní bundle (bolt-helper-pages) */
@source not "../../helper-pages";
```

---

## 3. Design Tokens Blueprint (`@theme inline` & `:root`)

Configure tokens directly in `@theme inline` so they resolve instantly into Tailwind utility classes:

> [!NOTE]
> The values below are **neutral placeholders** (a slate/blue palette and the open-source fonts Source Serif 4, Source Sans 3 and JetBrains Mono) that already meet the WCAG AA rules of section 6. Replace every value with the one extracted from the design; keep the token **names** — the templates of `bolt-theme-init`, `bolt-menu`, `bolt-theme-templates`, `bolt-cookie-consent` and `bolt-add-language` use them.

```css
@theme inline {
    /* --- Layout Breakpoints --- */
    --breakpoint-2xs: 24rem;       /* 384px */
    --breakpoint-xs: 36rem;        /* 576px */
    --breakpoint-menu: 62rem;      /* Bod zlomu, kde desktopová lišta nahrazuje burger menu */
    --breakpoint-3xl: 112.5rem;    /* 1800px */

    /* --- Výška sticky hlavičky --- */
    --spacing-header: 4.5rem;      /* Určuje výšku navigační lišty a scroll-margin kotev */

    /* --- Typografické rodiny --- */
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

    /* --- Značka / Primární akcent --- */
    --color-accent: #1d4ed8;
    --color-accent-hover: #1e40af;
    --color-accent-soft: #dbeafe;
    --color-accent-ink: #ffffff;
    --color-accent-ink-2: #bfdbfe;

    /* --- Noční zóna (fixní tmavá paleta pro patičku a tmavé pruhy) --- */
    --color-night: #0f172a;
    --color-night-deep: #020617;
    --color-night-stroke: #1e293b;
    --color-night-ink: #ffffff;
    --color-night-ink-2: #cbd5e1;
    --color-night-ink-3: #94a3b8;

    /* --- Fluidní velikosti nadpisů clamp(min, základ + vw, max) --- */
    --text-hero: clamp(2.25rem, 1.5rem + 3vw, 4rem);
    --text-section: clamp(1.75rem, 1rem + 2.5vw, 2.75rem);
    --text-card: clamp(1.125rem, 0.95rem + 0.7vw, 1.375rem);

    /* --- Typografická stupnice textu: 11 / 13 / 15 / 17 px --- */
    --text-micro: 0.6875rem;       /* 11px — štítky, badge, uppercase anotace */
    --text-meta: 0.8125rem;        /* 13px — doplňující popisky, kompaktní tlačítka */
    --text-body: 0.9375rem;        /* 15px — standardní odstavec */
    --text-lead: 1.0625rem;        /* 17px — úvodní perex */

    /* --- Plynulé přechody a animace --- */
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
        0%, 100% { background-color: var(--color-ink-200, #e2e8f0); }
        50% { background-color: var(--color-ink-100, #f1f5f9); }
    }
}

:root {
    /* Vlasové linky a ohraničení v rem (škálují se s root fontem) */
    --hairline: 0.0625rem;

    --canvas: #ffffff;
    --surface: #f8fafc;
    --surface-2: #f1f5f9;
    --ink: #0f172a;
    --ink-2: #475569;
    /* Nejsvětlejší inkoust: ověřeno na 5.44:1 na --canvas, 5.2:1 na --surface a 4.97:1 na --surface-2 (WCAG AA) */
    --ink-3: #5b6b80;
    --stroke: #e2e8f0;
}
```

---

## 4. Lokální fonty s podporou češtiny (`unicode-range`)

Aby se předešlo externím požadavkům na Google Fonts (ochrana soukromí, GDPR) a layout shiftům (CLS), fonty se hostují lokálně v `public/theme/<theme>/css/fonts/`.

Pro českou abecedu (**ě, š, č, ř, ž, ý, á, í, é, ů, ú, ň, ť, ď**) je **nezbytné** definovat jak rozsah `Latin`, tak `Latin-ext`:

```css
@layer base {
    /* Latinka (základní) — každá rodina potřebuje latin i latin-ext soubor */
    @font-face {
        font-family: 'Source Sans 3';
        font-style: normal;
        font-weight: 200 900;
        font-display: swap;
        src: url(fonts/source-sans-3/source-sans-3-latin.woff2) format('woff2');
        unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
    }

    /* Latinka rozšířená (obsahuje české háčky a čárky) */
    @font-face {
        font-family: 'Source Sans 3';
        font-style: normal;
        font-weight: 200 900;
        font-display: swap;
        src: url(fonts/source-sans-3/source-sans-3-latin-ext.woff2) format('woff2');
        unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
    }

    /* Odsazení cílů kotev (#sekce), aby je nepřekrývala sticky hlavička */
    :where([id]) {
        scroll-margin-top: var(--spacing-header);
    }

    /* Přístupný fokus pro klávesnici */
    :focus-visible {
        outline: 0.125rem solid var(--color-accent);
        outline-offset: 0.1875rem;
    }
}
```

---

## 5. Blueprint opakujících se utilit a tříd

Následující utility a třídy se opakují ve všech produkčních tématech a tvoří standardní stavební kameny pro Twig komponenty:

### A. Layout a rozložení
```css
/* Vycentrovaný kontejner limitovaný šířkou artboardu (typicky 1440px / 360 / max-w-7xl) */
@utility wrapper {
    @apply mx-auto w-full max-w-360;
}

/* Vodorovné odsazení stránky (margin od okrajů obrazovky) */
@utility px-edge {
    @apply px-6 sm:px-10 lg:px-20;
}

/* Vertikální rytmus sekcí */
@utility py-section {
    @apply py-12 lg:py-16;
}

/* Skrytí scrollbaru u vodorovných swipe listů při zachování posouvání */
@utility no-scrollbar {
    scrollbar-width: none;
    &::-webkit-scrollbar {
        display: none;
    }
}

/* Dvě za sebou jdoucí sekce stejné barvy spojí vertikální prostor */
section:where(.bg-canvas) + section:where(.bg-canvas) > .wrapper,
section:where(.bg-surface) + section:where(.bg-surface) > .wrapper {
    padding-top: 0;
}
```

### B. Typografie, štítky a anotace
```css
/* Drobný štítek nad hlavním nadpisem sekce */
@utility eyebrow {
    @apply font-body uppercase text-micro font-medium tracking-[0.12em] text-ink-3;
}

/* Dekorační linka před eyebrow štítkem */
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

### C. Tlačítka a CTA prvky
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

/* Kontrastní pár tlačítek pro tmavé pásy (např. tmavý kontakt nebo patička) */
@utility btn-on-accent {
    @apply btn bg-white text-accent hover:bg-accent-soft;
}

@utility btn-on-accent-outline {
    @apply btn border-white/40 text-white hover:bg-white/10;
    border-width: var(--hairline);
    border-style: solid;
}
```

### D. Karty a interaktivní odkazy
```css
/* Karta obsahu s jemnou linkou */
@utility card {
    @apply rounded-sm bg-canvas;
    border: var(--hairline) solid var(--color-stroke);
}

/* Odkaz s posouvající se SVG šipkou při hoveru */
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

### E. Stylování Bolt Pageru (`.pagination`)
Nativní Twig funkce `{{ pager() }}` generuje `<ul class="pagination">`:
```css
.pagination {
    @apply flex flex-wrap items-center justify-center gap-2 m-0 p-0;
    list-style: none;
}
.pagination li a {
    @apply inline-flex h-9 min-w-9 items-center justify-center px-3 font-mono text-xs tracking-widest border border-stroke text-ink-2 transition-colors duration-200;
}
.pagination li a:hover {
    @apply border-ink text-ink;
}
.pagination li.active a,
.pagination li a[aria-current] {
    @apply border-ink bg-ink text-canvas;
}
.pagination li[disabled],
.pagination li[disabled] a {
    @apply opacity-40 pointer-events-none;
}
```

### F. CMS Redactor Typography Wrapper (`.cms-redactor`)
Editor v Bolt CMS vkládá libovolné HTML z Redactoru (seznamy, citace, nadpisy). Třída `.cms-redactor` izoluje jejich styly:
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

    /* Varianta pro text na tmavém pozadí */
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

### G. Mobilní menu a animace akordeonů
Třídu `.dropdown` používají panely rozbalovacích nabídek (`components/nav/dropdown.twig` z `bolt-menu`, přepínač jazyků): `js/src/menu.ts` z `bolt-theme-init` animuje jejich výšku mezi `0` a `scrollHeight`, přepíná `aria-expanded` a `inert`. Šipka s třídou `.rotate-svg` se otočí, když má tlačítko `aria-expanded="true"`.
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

---

## 6. Postup při extrakci tokenů z grafického návrhu (Figma / Penpot)

Při převodu z designu postupujte v tomto pořadí:

1. **Určete výšku hlavičky (`--spacing-header`)**:
   - Změřte výšku fixní/sticky navigace v desktopovém i mobilním artboardu. Nastavte `--spacing-header: 4.5rem;` a ujistěte se, že `:where([id]) { scroll-margin-top: var(--spacing-header); }` je aktivní.
2. **Extrahujte škálu barev a ověřte kontrast (WCAG AA)**:
   - Povrchy: `--canvas`, `--surface`, `--surface-2`.
   - Text (Inky): `--ink` (primární), `--ink-2` (sekundární), `--ink-3` (anotace/štítky).
   - **Pravidlo kontrastu:** `--ink-3` musí mít kontrastní poměr alespoň **4.5:1** vůči `--canvas`, `--surface` **i** `--surface-2` (všem plochám, na kterých se objevuje text). Totéž platí pro `--night-ink-3` vůči `--night` a `--night-deep`.
3. **Vypočítejte fluidní typografii `clamp()`**:
   - Vzorec pro plynulé škálování mezi mobilem (např. 375px) a desktopem (např. 1440px):
     $$\text{clamp}(\text{min}, \text{base} + \text{slope} \cdot \text{vw}, \text{max})$$
   - Příklad: Hero nadpis od 36px na mobilu po 64px na desktopu:
     `--text-hero: clamp(2.25rem, 1.5rem + 3vw, 4rem);`
4. **Připravte lokální fonty (WOFF2)**:
   - Stáhněte řezy ve formátu WOFF2 (včetně podpory Latin-ext pro češtinu).
   - Umístěte do `public/theme/<theme>/css/fonts/` a doplňte `@font-face` s `unicode-range`.
5. **Kompilace a verifikace**:
   - Spusťte `npm run build:css` v adresáři tématu.
   - Spusťte ověřovací skript:
     ```bash
     ./skills/bolt-tailwind-theme/scripts/verify.sh
     ```

---

## 7. Automatizovaná verifikace (`scripts/verify.sh`)

Verifikační skript kontroluje:
1. Existenci souboru `public/theme/<theme>/css/tailwind/index.css`.
2. Přítomnost `@source` pravidel včetně ochran proti zacyklení (`@source not "../index.css"`).
3. Přítomnost `@theme inline` bloku, `--spacing-header` a brand/accent barev.
4. Přítomnost offsetu pro kotvy (`scroll-margin-top`).
5. Přítomnost opakujících se utilit (`wrapper`, `btn`, `.cms-redactor`).
6. Úspěšnou kompilaci pomocí `@tailwindcss/cli` (`npm run build:css`).
