# Upfront intake — every question the workflow needs

Ask everything here **before Phase 1**, so Phases 1–8 run without stopping. Two rules make the
intake short:

1. **Propose, don't ask, what the design answers.** Read the design first (`design-sources.md`)
   and pre-fill pages, sections, ContentTypes, menu profile, features, tokens and copy. Show these
   as a proposal to confirm or correct — not as open questions.
2. **Batch the rest.** Ask in the rounds below, one message (or one question-tool call with up to
   four multiple-choice questions plus free-text fields) per round. Offer the default as the
   first, recommended option. Questions marked *operator* need facts only the site owner knows;
   if the user cannot answer now, record `[DOPLNIT]`, continue, and list it in the handover.

Every answer goes into the site plan (`site-plan-template.md`); the right-hand column says which
phase and skill consume it.

---

## Round 1 — Environment (blocks Phase 1)

| # | Question | Default / options | Used by |
| :- | :--- | :--- | :--- |
| E1 | Project directory: an existing Bolt 6 project, or create a new one? | new: `composer create-project bolt/project <dir>` | Phase 1 prerequisites |
| — | *Not asked:* database is **SQLite** from Bolt's default `.env` (`var/data/bolt.sqlite`) — no `DATABASE_URL` to set; `bolt:setup --no-fixtures` — **never** Bolt's sample fixtures | — | Phase 1 |
| E3 | First account for the local site — created by the user in `bolt:setup --no-fixtures` (interactive; password never in the chat) | the user runs `! php bin/console bolt:setup --no-fixtures` in Phase 1 | Phase 7 (content), admin checks |
| E4 | How the site runs locally and its URL (`BOLT_BASE_URL`) | `symfony serve` → `https://127.0.0.1:8000` · Docker · Valet / other | all live checks |
| E5 | Production web server and document root | Apache, vhost on `public/` · Apache, document root = project root · Nginx | 2.1 `bolt-htaccess`, 2.2 `bolt-asset-caching` |
| E6 | Docker in production or development? | no · yes (PHP INI, compose, Nginx container) | 1.1 `bolt-timezone`, 2.2 |
| E7 | Production domain and staging URL (if any) | — | 8.3 smoke checks, SEO, `llms.txt` |
| E8 | Theme folder name | slug of the site name | 4.1 `bolt-theme-init` |
| E9 | CI platform | GitLab (skill default) · GitHub Actions (adapt the job) · none | 1.4 `bolt-code-quality` |
| E10 | Git: commit after every gate? Remote to push to? | commit locally after each gate, no push | all gates |

## Round 2 — Structure and content (confirm the design proposal)

| # | Question | Default / options | Used by |
| :- | :--- | :--- | :--- |
| S1 | Languages: default locale and secondary locales | `cs` only · `cs` + `en` · other | 1.2, 5.1, 5.4, 5.5, 6.3 `bolt-add-language` |
| S2 | Who translates secondary locales? | agent drafts, operator reviews · operator supplies · no translation yet (placeholders) | 5.5, 7.2 |
| S3 | **Proposal:** pages and URLs per locale, homepage anchor sections | from the design | 0.1, 5.3, 5.4 |
| S4 | **Proposal:** menu profile | landing (one page, `/#anchors`) · catalog (multi-page, submenus) · conditional (event site) | 4.3, 5.4 `bolt-menu` |
| S5 | **Proposal:** ContentTypes — singleton or listing, routable or not, fields | from repeated design blocks | 5.1 `bolt-contenttypes` |
| S6 | **Proposal:** features — gallery/lightbox, downloads, carousel, product catalog, articles/blog | from the design | 0.2 decision matrix, 3.2, 4.5, 6.1 |
| S7 | Forms (contact, enquiry, newsletter): how are they delivered? | none · `mailto:` link · form extension or external service (outside the skills — the agent proposes one and records it) | 6.1, privacy purposes |
| S8 | Content source | copy from the design · documents the user supplies (path) · agent writes draft copy marked for review | 7.1 seed content |
| S9 | Images | exported from the design · supplied folder (path) · placeholders | 4.2 logo, 7.1 media library |
| S10 | Who enters content into Bolt? | agent through the admin in a browser (needs E3) · operator · leave sample records | 7.1 |
| S11 | Error-page metaphor (an object or scene from the industry for 404/500/503) | agent proposes one from the brand | 6.4 `bolt-helper-pages` |

## Round 3 — Design gaps (only what the design does not answer)

| # | Question | Default / options | Used by |
| :- | :--- | :--- | :--- |
| D1 | Mobile layouts missing from the design? | agent adapts the desktop design (mobile-first, menu breakpoint from the design) | 4.4, 6.1 |
| D2 | Fonts: licence and files | free (Google Fonts / Fontsource) — download WOFF2 and self-host · commercial — user supplies WOFF2 files | 4.4 `bolt-tailwind-theme` (never load from Google: GDPR) |
| D3 | Logo files (SVG, light variant for dark backgrounds) | export from the design | 4.2 `theme.yaml` `logo:` |
| D4 | States the design does not show (hover, focus, empty lists, form errors) | derive from the tokens (accent hover, visible focus ring) | 4.4, 6.1 |
| D5 | Icons | from the design (export SVG) · an icon set (name it) | 6.1 |
| D6 | Visual fidelity target | close match at the design's breakpoints, checked by screenshots · structural match only | 6.1 visual QA loop |

## Round 4 — Operator facts (legal, tracking, contact)

| # | Question | Default / options | Used by |
| :- | :--- | :--- | :--- |
| O1 | Contact details shown on the site: name, phone, e-mail, address, opening hours, one-sentence bio, social links | — *operator* | 4.2 `theme.yaml` `contact:`, `socials:` |
| O2 | `bolt-cookie-consent` intake Q1: measuring / advertising tools | Google Ads · GA4 · Sklik · Meta Pixel · other · none | 6.5 |
| O3 | Q2: embedded third-party content | YouTube · Google Maps · Mapy.com · none | 6.5 |
| O4 | Q3: Google Consent Mode | basic (recommended) · advanced (operator's explicit decision) | 6.5 |
| O5 | Q4: more than one business on the site? (two follow-up questions → controller model) | single — never guess | 6.5 |
| O6 | Q5: controller identity for each business (legal name, form, address, IČO, registry entry, privacy e-mail, DPO) | — *operator* | 6.5 privacy page |
| O7 | Q6: processing besides cookies (forms, orders, accounting, newsletter, jobs, client agenda), retention, recipients (hosting, e-mail, accountant, tools) | web operation + contact form | 6.5 |
| O8 | Q7: anything unusual (health data, children, profiling, transfers outside the EU) | no | 6.5 (AG-06) |
| O9 | Tracker IDs (`G-…`, `AW-…`, Sklik retargeting ID, Meta pixel ID) | may come later — `[DOPLNIT]` | 6.5 `analytics:` |
| O10 | Does anything consume the REST/GraphQL API? | no → disable fully | 1.3 `bolt-disable-api` |
| O11 | SEO basics: site title, default description, social sharing image | derived from the design and brief | 3.1 `appolo-boltseo`, 7.3 |
| O12 | `llms.txt`: one-paragraph description of the business for AI crawlers | agent drafts from the brief | 6.2 `bolt-extension-setup` |

## Round 5 — Autonomy (how far the agent may go alone)

| # | Question | Default / options | Used by |
| :- | :--- | :--- | :--- |
| A1 | Checkpoints | stop only at Checkpoint 0 (site plan) · also at Checkpoint 5 (content model) · at every gate | whole run |
| A2 | Allowed without asking: `composer require`, `npm install`, `bin/console` commands, database setup | yes (needed by the workflow) | Phases 1–7 |
| A3 | When a gate keeps failing | fix up to 3 attempts, then record under *Open issues* and continue where later phases do not depend on it · stop and ask | all gates |
| A4 | Parallel agents for independent work (page templates in Phase 6, the skill reviews in Phase 8) | no · yes | 6.1, 8 |

---

## After the intake

Write the site plan, show it once (Checkpoint 0), and after approval start Phase 1. Anything the
user did not answer gets the default from this table, recorded in the *Decisions log* with
"default — not confirmed". Operator facts are never defaulted: they stay `[DOPLNIT]` and go to the
handover list.
