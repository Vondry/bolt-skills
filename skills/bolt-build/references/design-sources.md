# Reading the design

Whatever the source, the agent extracts the same six things, **before the intake**, so it can
propose instead of ask:

| # | Extract | Becomes | Phase |
| :- | :--- | :--- | :--- |
| 1 | **Inventory** — pages/frames, their sections, breakpoints present | sitemap, URLs, homepage anchors, menu profile | 0, 5.3, 5.4 |
| 2 | **Content model** — blocks that repeat (cards, team, events, products, FAQ), global blocks (header, footer, contact) | ContentTypes (listing vs. singleton), fields, settings singleton, menu items | 5.1, 5.4 |
| 3 | **Tokens** — colours, fonts and weights, type scale, spacing, radius, shadows, container width, header height, menu breakpoint | contract tokens in `css/tailwind/index.css` | 4.4 |
| 4 | **Components** — buttons and their states, cards, badges, form fields, nav, footer | contract components and utilities (`.btn-*`, `.card`, `components/ui/*`) | 4.3, 4.4, 6.1 |
| 5 | **Copy and assets** — texts per section, logo, icons, photos | translation units (UI strings), seed content (records), `theme.yaml` logo, media library | 4.2, 5.5, 7.1 |
| 6 | **Reference screenshots** — every page at every breakpoint the design has | visual QA in Phase 6 | 6.1 |

Save the reference screenshots and a short `design-notes.md` (token table, inventory, open
questions) in `var/bolt-build/design/` of the project (git-ignored runtime folder), so later
sessions can re-read them without calling the design tool again.

---

## Mapping design values to the contract tokens

Keep the contract token **names** (`bolt-tailwind-theme`); only the values come from the design.

| Design role | Contract token |
| :--- | :--- |
| page background | `canvas` |
| card / section background, a second one | `surface`, `surface-2` |
| primary, secondary, muted text | `ink`, `ink-2`, `ink-3` |
| borders, dividers | `stroke` |
| brand / action colour, its hover, a soft tint, text on it, accent-coloured text on dark | `accent`, `accent-hover`, `accent-soft`, `accent-ink`, `accent-ink-2` |
| dark band (footer, hero), its deeper shade, borders and text on it | `night`, `night-deep`, `night-stroke`, `night-ink`, `night-ink-2`, `night-ink-3` |
| headline, body and monospace font | `font-display`, `font-body`, `font-mono` |
| type scale | `text-hero`, `text-section`, `text-card`, `text-lead`, `text-body`, `text-meta`, `text-micro` — fluid `clamp()` between the mobile and desktop frames (`bolt-tailwind-theme` § 6) |
| fixed header height | `--spacing-header` |
| breakpoint where the menu collapses | `--breakpoint-menu` |

If the design has more colours than roles, map the extras to the nearest role and note it in
`design-notes.md`; never add colour names outside the contract (templates using them render
unstyled). Check WCAG AA contrast (4.5 : 1 for text) for every text token on every background it
appears on; adjust the value minimally and record the change when the design fails it.

---

## Figma (Figma MCP server)

Works with the Figma desktop app's Dev Mode MCP server or Figma's remote MCP server. If the server
does not respond, tell the user it failed to connect (the desktop app must be running with the MCP
server enabled) instead of guessing the design.

- **Before the first `get_design_context` call**, load the `figma-design-to-code` skill (`figma:figma-design-to-code`) when it is available — it carries Figma's own rules for that tool.
- **Node IDs** come from the URL the user gives (`…?node-id=12-345` → `12:345`). Ask for the URL of the page or top frame, not only the file.
- **Inventory:** `get_metadata` on the page — frame names, sizes (breakpoints), section layers. Work frame by frame; do not request the whole file at once.
- **Tokens:** `get_variable_defs` — colour, typography, spacing and radius variables with their names; map them with the table above. Styles without variables: read them from `get_design_context` of a representative frame.
- **Components and sections:** `get_design_context` per section node — layout, spacing, text styles, component instances. Translate to Twig + the contract tokens, never paste the generated React/Tailwind code: it uses arbitrary values and class names outside the token set.
- **Code Connect:** `get_code_connect_map`, if the file uses it, says which design components already map to code.
- **Screenshots:** `get_screenshot` of every frame for the reference set (item 6).
- **Assets:** export logo and icons as SVG, photos as the largest available raster; put decorative theme images in `public/theme/<theme>/img/`, content images into the media library in Phase 7.

## Pencil / pen.dev (`.pen` files, Pencil MCP server)

`.pen` files are encrypted — access them only through the Pencil MCP tools, never by reading the
file.

- Call `get_app_state` first (it returns the current document and the `execute` documentation); `read_skill` explains the canvas API in more depth.
- **Inventory, tokens, components, copy:** `execute` with `filePath` and a **read-only** snippet that walks the document — top-level frames (pages, breakpoints), their children (sections), text nodes (copy), fills / strokes / font properties (tokens), components and their instances. Never modify the user's design.
- **Screenshots:** export frames as images through `execute`, or use the reference frames the user names.
- **Visual QA:** the Pencil `browser` tool can `load-page` the local site and `return-screenshot` (full page or a `querySelector` section) to compare the build with the design frame.

## Images or PDF (screenshots, exported artboards, a printed design)

- Read every file; one file = one page/breakpoint unless the user says otherwise.
- Colours, sizes and spacing are **estimates** — say so in `design-notes.md`, prefer round token values, and ask in Round 3 for the brand's exact colours and fonts if the user has them (brand manual, CSS of an existing site).
- The files themselves are the reference screenshots.

## An existing website (redesign or migration)

- Use a browser tool (Chrome, Pencil `browser`, Playwright) to screenshot each page at desktop and 360 px, and read computed styles of representative elements (body, headings, buttons, links, header, footer) for the tokens.
- Crawl the navigation for the inventory and the URLs; keep old URLs that have search traffic, or list redirects for the operator.
- Copy and images come from the live pages — confirm in Round 2 that they may be reused.

## A brief without a design

- Propose a design direction (palette, type pairing, layout rhythm) before the intake — with the `frontend-design` skill when available — and show it in Checkpoint 0 with the site plan.
- The approved direction is the reference; there are no screenshots to compare against, so the visual QA step checks consistency and accessibility only.

---

## Visual QA loop (Phase 6)

For every page template, after `npm run prod`:
1. Screenshot the local page at each breakpoint the design has (and 360 px always).
2. Compare with the reference: layout and order of sections, spacing rhythm, type sizes, colours, alignment, images. Ignore content differences (real copy vs. design copy) and pixel-level anti-aliasing.
3. Fix with tokens and contract utilities — never one-off arbitrary values unless the design really needs one (then add it as a token).
4. At most three rounds per page; record remaining differences in the progress log with a screenshot path.
