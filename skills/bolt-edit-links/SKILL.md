---
name: bolt-edit-links
description: >-
  Adds the editor's pencil to a finished Bolt CMS 6 theme: installs or upgrades the `edit` macro in
  macros.twig (opens the record in the language of the page and on the tab of the section, using the
  field `group` as the URL hash), scans the templates for every place a pencil belongs, and verifies
  the result, including that every tab exists. Use it once the design is implemented and the site is
  done, or when asked to add edit links, edit pencils or "quick edit" buttons to a theme.
---

# Bolt CMS Edit Links

Logged-in editors see a small ✏️ on each section of a page. One click opens that record in the Bolt
editor, in the language of the page, on the tab that holds that section. Visitors see
nothing: the macro renders only when `|edit_link` returns a URL, which needs a logged-in user with
permission to edit that record.

Run this skill **last among the template work**, when the pages and their ContentTypes exist. It
writes `macros.twig` and the templates it applies the macro to, and adds `group:` keys when a
ContentType has none.

```
/bolt/edit/12?edit_locale=en#cenik
           │              │  └─ the tab: the field's `group` through |slug
           │              └──── the language of the page being viewed
           └─────────────────── the record
```

---

## Step 1: Install the Macro and Get the Worklist

```bash
bash $SKILLS/bolt-edit-links/scripts/scaffold.sh
```

It adds [`examples/macro-edit.twig`](examples/macro-edit.twig) to the theme's `macros.twig`, or
upgrades an older `edit` macro in place. A macro that already handles the locale and the tab is kept.
Then it prints each ContentType with its tabs, and every place without a pencil:

```
public/theme/acme/pages/homepage/homepage.twig:20  section  MISSING  title_suffix: macros.edit(record, 'Ceník')  (pricing.twig)
```

You can rerun it at any time; add `--all` to list the places that are already covered. The
worklist is a starting point. It reads Twig as text, the tab is a guess from the fields a place
reads, and **you still read every page template** for what it cannot see (Step 3).

The older macro took a label as its second parameter, and that position is now the tab. A call such
as `macros.edit(record, 'Upravit')` must become `macros.edit(record, null, '', 'Upravit')`; the
verification fails on it until then.

The macro's classes use the contract tokens (`text-card`). In a theme with other token names, change
them in `macros.twig` to what the design uses.

---

## Step 2: Make Sure the Sections Have Tabs

The tab is the field's `group` in `config/bolt/contenttypes.yaml`. A long singleton without groups
is one long form, and a pencil can only open its top. When one record feeds **two or more sections
of a page**, give each section a group named after what the editor sees on the page:

```yaml
homepage:
  fields:
    hero_title:    { type: text, group: Úvod }
    hero_lead:     { type: textarea }            # no group: stays on the tab of the field before it
    pricing_title: { type: text, group: Ceník }
    prices:        { type: collection, group: Ceník, ... }
    seo:           { type: seo, group: SEO }
```

Groups only arrange the editor, so stored content is untouched and no migration is needed; run
`php bin/console cache:clear` afterwards. Bolt carries a group over to the following fields until
another one is named, so when adding a group in the middle of a list, check the fields after it. A
ContentType with one short form needs no groups, and the pencil simply opens it.

---

## Step 3: Apply It

Every template that calls the macro imports it itself, because macros are not inherited through
`extends` or `include`:

```twig
{% import 'macros.twig' as macros %}
```

| Place | Call | Why this way |
| :--- | :--- | :--- |
| `<h1>` of a record or singleton page | `{{ macros.edit(record) }}` after the title, inside the heading | The first thing an editor looks for |
| Each section fed by a record | `title_suffix: macros.edit(record, 'Ceník')` passed to the section's component | The page knows the record, the component stays pure |
| A section component's heading | `{{ title }} {{ title_suffix|default('') }}` | Prints what the page passes, nothing for visitors |
| Hero or other section that receives the whole record | `{{ macros.edit(record, 'Úvod') }}` beside its heading | |
| Container with its own `setcontent` (contact, settings, sponsors, footer data) | `{{ macros.edit(contact, 'Patička') }}` once, beside the block's heading | One pencil per record: guard with `loop.first` inside a loop over its fields |
| List of records without pages of their own (prices, reviews, videos) | `{{ macros.editList(items|first) }}` once, on the heading of the section or table | Opens the ContentType's overview in the admin |
| Page from a singleton (privacy, legal, consumer info) | `macros.edit(record)` on the `<h1>`, plus one per tab when sections map to tabs | |

```twig
{# pages/homepage/homepage.twig — the page knows the record and which tab holds the section #}
{{ include('pages/homepage/components/pricing.twig', {
    title:  record.pricing_title,
    prices: record.prices,
    title_suffix: macros.edit(record, 'Ceník'),
}) }}
```

**One pencil per section, never one per row or card.** A table, a card grid or a search page gets at
most one, on its heading; many icons in one section only make it unclear. Cards that link to a page of
their own need none, because that page has its pencil. Verification warns about a pencil repeated for
every item of a list. The exceptions are items that are whole sections with their own heading (one price
table per machine), a carousel showing one slide at a time, and a handful of large blocks.

The tab is the group **as written** in `contenttypes.yaml`; the macro slugs it (`Ceník` → `#cenik`).
Leave it out for the first tab. Tabs that no page shows (usually SEO and Meta) get no pencil; a section
listing related records opens `Relations`. A tab that one always-rendered pencil already opens needs no
second one, but sections that render only when filled each get their own.

### Where It Does Not Go

* **On every row or card of a list.** One on the section heading (above).
* **Inside `<a>` or `<button>`.** Nested interactive elements are invalid HTML. Put the pencil beside
  the link. Verification fails on this.
* **`helper-pages/` and `extensions/`.** They have no record, and the 500 and 503 pages must render
  without a database. Verification fails on this.
* **Inside a fragment cache** (`bolt-performance`). The first visitor's output is stored for everyone:
  either every visitor gets the pencil's markup or editors never see it. Put the call beside the
  cached include, or leave that section without one. `bolt-performance`'s verification fails on this.
* **Navigation, breadcrumbs, the cookie banner, `<head>`.** Menu labels live in `menu.yaml`, not in
  a record.
* **Items of a set or collection, and `theme.yaml` values.** `|edit_link` accepts only a record or
  null, anything else is a 500. Pass the record that owns the field: `macros.edit(record, 'Ceník')`.

---

## Step 4: Build

The macro's classes must be in the compiled stylesheet:

```bash
cd public/theme/<theme> && npm run prod && cd -
```

Bump `assets_version` in `theme.yaml`, then run `php bin/console cache:clear`.

---

## Verification

```bash
bash $SKILLS/bolt-edit-links/scripts/verify.sh
```

| Checks | Result |
| :--- | :--- |
| The macro exists, uses `edit_link`, takes a tab, passes `edit_locale` | FAIL when not |
| The macro has `aria-label` and `print:hidden` | WARN when not |
| Every call imports `macros.twig` in its own file, and sits outside links, buttons, `helper-pages/`, `extensions/` | FAIL when not |
| Every literal tab exists on the ContentType of the record | FAIL when not, because Bolt's editor throws on it |
| Every record page, singleton page and the homepage has a pencil | FAIL when not |
| No pencil repeats for every item of a list, every singleton shown on the site is reachable, every tab shown has a pencil | WARN when not: fix it, or list it under "Expected verification warnings" in the site plan with the reason |

Then confirm what only a logged-in browser can. With content in the database, log in to `/bolt/`,
open any page of the site, and run
[`scripts/edit-links-browser.js`](scripts/edit-links-browser.js) in the console or a browser tool's
JavaScript runner. It walks the sitemap and the links it finds, and loads every editor page a pencil
points to. `missingTabs` and `errors` must be empty. In `pagesWithoutPencil`, expect only pages with
no record of their own.

Click one pencil per ContentType: the editor opens on the section's tab, and from a translated page
in that language. In a private window, the same pages show no pencil.

## Common Pitfalls

* **The editor opens but no tab is selected and its scripts stop** → the hash matches no tab, usually
  because a group was renamed. Bolt calls `getOrCreateInstance` on the result of its lookup and
  throws.
* **The pencil's markup appears as text** → the macro's output was joined with `~`, which turns it
  into a plain string that gets escaped. Pass it on its own, as `title_suffix: macros.edit(…)`.
* **`Variable "macros" does not exist` in dev, nothing at all in production** → the template uses the
  macro without importing it.
* **A page answers 500 for editors only** → `|edit_link` received something that is not a record:
  a set item, a field or a `theme.yaml` value.
* **The pencil is there but cannot be clicked** → a stretched link covers it; add `relative z-10`.
* **The pencil is unstyled** → the theme was not rebuilt after Step 3, or `text-card` is not one of
  its tokens.
* **A pencil appears for visitors, or never for editors** → it sits inside a `{% cache %}` fragment.
