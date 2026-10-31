---
name: bolt-cookie-consent
description: >-
  Intake-driven cookie banner and privacy policy page for Czech Bolt CMS sites (ZEK § 89/3, GDPR,
  ÚOOÚ / EDPB practice). Asks which trackers (Google Analytics 4, Google Ads, Seznam Sklik, Meta
  Pixel, …), embeds and controller model the site uses, writes one data model into theme.yaml (or
  validates one kept in a privacy ContentType), and renders from it a two-layer opt-in banner
  (Consent Mode v2, equal Accept / Reject, per-category settings), consent-gated embeds and the
  /zasady-ochrany-osobnich-udaju page — styled with the theme's design tokens and verified by
  scripts/verify.sh.
---

# Bolt CMS Cookie Consent & Privacy Policy (`bolt-cookie-consent`)

This skill builds two things for a Czech website, both from **one data model** — in `theme.yaml`, or in a privacy ContentType the editors maintain ([§ 2](#data-model-in-a-contenttype-alternative)):

1. a **cookie banner** — only when the site uses something that needs consent (analytics, ads, retargeting, embedded video or maps);
2. the **privacy policy page** `/zasady-ochrany-osobnich-udaju` — on every site, with or without trackers.

The legal baseline is [`references/guidelines.cs.md`](references/guidelines.cs.md) (Czech, state of 10. 10. 2026). Its requirement IDs (`INV-`, `CB-`, `DP-`, `PP-`, `VAR-`, `DM-`, `AG-`) are used throughout this file, the templates and `scripts/verify.sh`. Read its sections *Cookie lišta*, *Zakázané designové vzory* and *Pravidla pro agenta* before you change any template.

> **Not legal advice (AG-06).** The skill builds structure, design and behaviour. Facts — who the controller is, purposes, legal bases, retention periods, recipients — come from the operator. Never invent them (AG-01): leave `[DOPLNIT …]` and put the question on the handover list. For unusual processing (health data, children, profiling, transfers outside the EU without an adequacy decision) recommend a lawyer.

---

## 1. Step 0 — Intake (ask before writing any file)

Ask the operator (or the user acting for them) these questions — with your question tool if you have one, otherwise in chat — and record the answers in the project's `AGENTS.md` site plan (`WORKFLOWS.md`, Phase 0). Do not start the scaffold until questions 1–4 are answered.

| # | Question | Typical answer | Becomes |
| :- | :--- | :--- | :--- |
| 1 | **Which measuring and advertising tools will the site use?** Google Analytics 4 · Google Ads (conversions, remarketing) · Seznam Sklik (retargeting, conversions) · Meta Pixel · other (Hotjar, Microsoft Clarity, LinkedIn, TikTok …) · none | Google Ads, often GA4; Sklik optional | `--trackers=ga4,google_ads,sklik,meta_pixel` |
| 2 | **Is third-party content embedded?** YouTube / Vimeo video · Google Maps · Mapy.com · social widgets · none. (External fonts and CDNs: self-host them instead — `bolt-tailwind-theme`.) | a YouTube video, a map on the contact page | `--embeds=youtube,google_maps,mapy_com` |
| 3 | **Google Consent Mode: basic or advanced?** Basic = Google tags load only after consent (recommended, matches CB-01). Advanced = tags load before consent and send cookieless pings with IP address and browser data — only on the operator's explicit decision (CB-50). | basic | `analytics.consent_mode` |
| 4 | **Is more than one business presented on the website?** If yes: (a) Do they decide **together** about the website (content, forms, analytics, cookie banner)? (b) Does each handle **its own clients** (contracts, invoicing, files)? Never guess the answer (AG-02). | one business | `--model=` (table below) |
| 5 | **Controller identity**, for every business: legal name or trade name, legal form, registered office / place of business, IČO, registry entry (obchodní / živnostenský rejstřík, ČAK …), e-mail for privacy questions, data protection officer (if appointed). A private person without a business (a personal website): name and e-mail only — ask before publishing a home address. | from the operator; `contact:` in `theme.yaml` prefills the first one | `privacy.controllers` (`business: false` for a private person) |
| 6 | **What personal data does the site handle besides cookies?** Contact form / e-mail · orders and contracts · accounting · newsletter · job applications · client agenda per business. For each: retention period, and who receives it (hosting, e-mail provider, accountant, newsletter tool, CRM). | contact form + server logs | `--purposes=…`, `privacy.recipients` |
| 7 | **Anything unusual?** Health data, children, profiling, automated decisions, transfers outside the EU/EEA. | no | `automated_decision_making`; AG-06 warning |

Controller model from question 4 (guidelines, *Varianty*):

| Businesses | Website & cookies | Client agenda | Variant | `--model=` |
| :--- | :--- | :--- | :--- | :--- |
| 1 | – | – | A — single controller | `single` |
| 2+ | together | together | B1 — joint controllers (čl. 26) | `joint` |
| 2+ | each separately (shared shop window) | each separately | B2 — separate controllers | `separate` |
| 2+ | together | each separately | B1 + B2 | `hybrid` |

Purposes for `--purposes=` (from `references/cookie-catalog.yaml`): `web_operation` (server logs — every site), `contact_form`, `contract`, `accounting`, `newsletter`, `legal_claims`. The consent purposes `analytics`, `marketing` and `third_party` are added automatically from the trackers and embeds.

---

## 2. Architecture

```
theme.yaml
├── analytics:  ga4_id, google_ads_id, sklik_id, consent_mode
└── privacy:    controllers, purposes, recipients, cookies (inventory), consent rules, changelog
      │
      ├── partials/_consent-mode.twig ── <script type="application/json" id="cookie-consent-config">
      │                                   └── js/src/cookie-consent.ts  (the only behaviour; loads trackers after consent)
      ├── partials/_cookie-banner.twig ── layer 1 bar + layer 2 <dialog> (+ partials/_cookie-table.twig)
      ├── static-pages/gdpr.twig ──────── privacy policy (+ partials/_cookie-table.twig)
      ├── partials/_privacy-form-note.twig  notice next to every form's submit button (PP-02)
      └── containers/footer/_footer.twig ─ "Nastavení cookies" button when privacy.cookies needs consent (bolt-menu)
```

**One source of truth (data model, DM-01).** The banner text (controllers, purposes, named third parties), the cookie list in both layers and on the page, the purposes table and the recipients table are all rendered from `privacy:`. Never copy these facts into templates or translation catalogs — the two would drift apart, which is exactly what ÚOOÚ fined (cookies on the site that the banner did not describe). Translation catalogs (`cookie.*`, `privacy.*`) hold only the fixed wording: labels, rights, legal references.

**A tracker runs only when it is inventoried.** `_consent-mode.twig` passes an ID to the script only if `privacy.cookies` has items in the tracker's category (GA4 → `analytics`; Google Ads, Sklik, Meta → `marketing`). An ID without inventory never loads, and `verify.sh` reports it (INV-01, INV-03).

**No inline JavaScript.** The head partial prints JSON only, the banner has no `onclick`, so a strict Content-Security-Policy keeps working. Nothing contacts a third party before consent — no `preconnect` / `dns-prefetch` to tracker domains either (CB-01).

| File (in the theme) | Source | Role |
| :--- | :--- | :--- |
| `theme.yaml` → `analytics:`, `privacy:` | `scripts/privacy-config.php` (via scaffold) | The data model. Shape: `examples/theme.privacy.yaml` |
| `partials/_consent-mode.twig` | `examples/` | Consent configuration as JSON, in `<head>` of `partials/_master.twig` |
| `partials/_cookie-banner.twig` | `examples/` | Layer 1 bar and layer 2 dialog; included right after the skip link in `partials/_master.twig` |
| `partials/_cookie-table.twig` | `examples/` | Items of one category — shared by the banner and the page |
| `partials/_privacy-macros.twig` | `examples/` | `privacy_ui.t(value)` (localized value), `privacy_ui.date(value)` |
| `partials/_consent-embed.twig` | `examples/` | Video / map placeholder that loads after consent (CB-02) |
| `partials/_privacy-form-note.twig` | `examples/` | Form notice: who, why, link to the policy (PP-02) |
| `js/src/cookie-consent.ts` | `examples/` | All behaviour; imported by `js/src/index.ts` |
| `static-pages/gdpr.twig` + routes | `examples/`, scaffold | The privacy policy page |

### The data model (`privacy:`)

| Key | Content | Guideline |
| :--- | :--- | :--- |
| `config_version`, `effective_date`, `changelog` | Policy version and history. **Bump `config_version` and add a changelog entry** when purposes, controllers, recipients or cookie categories change — visitors who consented are asked again | PP-06, CB-42, DM-01 |
| `controller_model`, `controllers[]` | `id`, `legal_form`, `name`, `address`, `ico`, `registry`, `privacy_email`, `dpo` (`~`, a name, or `{ name, email }`). A private person who runs no business sets `business: false`: then only `name` and `privacy_email` are required, and `address`, `ico` and `registry` may be `~` (the page leaves those rows out) | čl. 13/1 a, b; § 435 OZ; VAR-30 |
| `joint_arrangement` | `contact_controller`, `summary` (essence of the čl. 26 arrangement) — `joint` / `hybrid` only | VAR-10–VAR-12 |
| `summary` | Optional 3–5 sentence summary; `~` uses the generic `privacy.summary.*` text | PP-04 |
| `purposes[]` | `id`, `controllers`, `section` (`website` or a controller id), `title`, `data`, `legal_basis` (`art6_1_a/b/c/f`), `legitimate_interest`, `retention`, `recipients`, `provision` | čl. 13/1 c, d; 13/2 a, e; VAR-20, VAR-31 |
| `recipients[]` | `id`, `name`, `role` (`processor`, `controller`, `joint_controller`), `purpose`, `country`, `transfer` (`~`, `adequacy`, `scc`) | čl. 13/1 e, f |
| `cookies[]` | `name` (`_ga_*` = prefix; comma-separated names allowed), `technology`, `category` (`necessary`, `preferences`, `analytics`, `marketing`, `third_party`), `provider`, `party` (`first`, `third`), `purpose`, `expiry`, `transfer` | INV-01–INV-03, CB-21, CB-24 |
| `consent` | `validity_months: 12`, `reask_after_reject_months: 6` | CB-41, DP-05 |
| `automated_decision_making` | `false`, or a localized description | čl. 13/2 f |

Texts are localized maps — `{ cs: '…', en: '…' }` — with Czech mandatory (CB-23); a plain string is used for every locale. The generator writes one key per locale in `app_locales` and `[DOPLNIT překlad xx]` where the catalog has no text.

### Data model in a ContentType (alternative)

When the editors should maintain the policy in the admin, the same data can live in one record instead of `theme.yaml`: usually a singleton ContentType (e.g. `privacy`, `localize: true` texts) whose `record_template` renders `/zasady-ochrany-osobnich-udaju`. Both models are valid; pick one per site and never split the data between them. The contract `verify.sh` relies on:

| Part | Requirement |
| :--- | :--- |
| `cookies` collection | One set per item with `category` (`necessary`, `preferences`, `analytics`, `marketing`, `third_party`), a name (`name` or `cookie_name`; `name` and `label` are reserved inside a set — bolt-contenttypes rule 8), `technology`, `party` (`first`, `third`), `provider`, purpose (`purpose` or `cookie_purpose`), `expiry`, optional `transfer`. The same rules as `privacy.cookies` (INV-01–INV-03, CB-21) |
| Controllers, purposes, recipients, joint arrangement, change history | Fields of the record, rendered by the site's templates; the page must still have every section anchor (`#spravce` … `#historie-zmen`) |
| Banner | `partials/_master.twig` (or `_consent-mode.twig`) reads the consent categories from the **same record** (`{% setcontent privacy_policy = 'privacy' returnsingle %}`), so the banner, the cookie table and the page never disagree |
| Tracker IDs | Stay in the `analytics:` block of `theme.yaml` |

`verify.sh` detects the model: a `theme.yaml` without `privacy:` and a ContentType whose `cookies` collection has a `category` field. It reads the published record through the project's kernel and Doctrine, validates the inventory like `privacy.cookies`, and checks the sections, the footer link and the cookies on the rendered page. Content of the record lives in the database: a change made locally must be repeated in the production admin, because the database is not uploaded.

---

## 3. Scaffold

Run from the Bolt project root (needs `vendor/` — the generator uses the project's `symfony/yaml`):

```bash
# Typical: Google Ads + GA4 + Sklik, a YouTube video, one business, contact form
bash $SKILLS/bolt-cookie-consent/scripts/scaffold.sh --model=single \
    --trackers=google_ads,ga4,sklik --embeds=youtube \
    --purposes=web_operation,contact_form,legal_claims

# Two lawyers sharing the website and analytics, each with own clients
bash $SKILLS/bolt-cookie-consent/scripts/scaffold.sh --model=hybrid --controllers=2 \
    --trackers=google_ads --purposes=web_operation,contact_form,contract,legal_claims

# No trackers, no embeds: privacy page only
bash $SKILLS/bolt-cookie-consent/scripts/scaffold.sh --model=single --no-banner \
    --purposes=web_operation,contact_form
```

The scaffold:
- appends the `privacy:` block to `theme.yaml` (skipped when one exists — then edit it by hand) and adds the missing `analytics:` keys for the chosen trackers;
- copies the partials, `js/src/cookie-consent.ts` and `static-pages/gdpr.twig` (existing files are kept; `--no-banner` skips the banner, consent and embed files) and enables `import './cookie-consent'` in `js/src/index.ts`;
- inserts the `privacy` / `privacy_locale` routes **above** Bolt's `frontend:` import in `config/routes.yaml` (below it, Bolt's catch-all answers 404);
- prints the `merge-xliff.php` commands for the `cookie.*` / `privacy.*` units.

`php scripts/privacy-config.php … ` (without `--write`) prints the block instead, e.g. to compare with an existing one. `--necessary=session` adds a session-cookie item for forms with CSRF protection; measure its real name.

After the scaffold:
1. Set the IDs under `analytics:` (`G-…`, `AW-…`, Sklik retargeting ID as a number).
2. Go through `privacy:` with the operator; replace every `[DOPLNIT …]`. For `separate` / `hybrid`, move each business's client purposes to `section: <controller id>` with `controllers: [<that id>]`.
3. Measure every `[OVĚŘIT …]` item (section 7) and correct names and lifetimes that differ from the catalog.
4. Clear Bolt's cache (`bin/console cache:clear`) — `theme.yaml` is cached.

---

## 4. Adapting the banner to the design

The banner uses only Integration-Contract tokens (`night`, `canvas`, `accent`, `ink`, `stroke` … from `bolt-tailwind-theme`), so it already follows the theme. To match the design more closely, edit the class variables at the top of `partials/_cookie-banner.twig` and the wrappers:

- **`consent_button`** is shared by Reject, Accept (layer 1) and Reject, Save, Accept (layer 2). Change it freely — `btn-primary`-like, outlined, rounded — but keep it **one variable**: same size, font, padding, colour and element type for all of them (CB-12; `verify.sh` compares the classes). Text contrast ≥ 4.5 : 1. Never give Reject a warning colour, grey it out or turn it into a link (DP-01, DP-02).
- **`settings_button`** ("Nastavení cookies") may look secondary, but stays a button in layer 1 (CB-13).
- **Panel**: background, border, radius, shadow and max width of the bar; light (`bg-canvas text-ink`) or dark (`bg-night text-night-ink`) to match the footer or header.
- **Position**: keep the non-blocking bar at the bottom (CB-04). A centred modal variant needs a close button that counts as "no consent", must move focus into the dialog and must not block the page behind it (CB-03, CB-04, CB-60) — the bar is the safer default.
- **360 px** (CB-15): the text scrolls (`max-h-[38vh]`), Reject and Accept sit side by side, so both are visible without scrolling. Keep that when shortening or lengthening the text.
- **Copy**: `cookie.*` units. Keep it short and factual; no "Používáním webu souhlasíte" (CB-05), no guilt or fear ("bez cookies web nebude fungovat", DP-04), one name for the settings everywhere — "Nastavení cookies" (DP-08).

Never: pre-enabled switches (DP-03), "legitimate interest" toggles switched on (DP-06), a Save button that accepts everything (DP-07), the withdrawal link only deep in the policy (DP-09), auto-hiding the bar (CB-62), a cookie wall (CB-03).

---

## 5. Trackers, embeds and consent behaviour

### Google Analytics 4 and Google Ads (Consent Mode v2)

`cookie-consent.ts` defines `gtag` with all four consent signals **denied** (`analytics_storage`, `ad_storage`, `ad_user_data`, `ad_personalization`) and `ads_data_redaction`, then follows the stored choice:

| | `basic` (default) | `advanced` |
| :--- | :--- | :--- |
| Before consent | `gtag.js` is not loaded | `gtag.js` loads, GA4 and Ads configured with everything denied (cookieless pings) |
| Analytics consent | loads `gtag.js`, configures GA4 (`cookie_expires` 13 months, CB-24) | consent update |
| Marketing consent | loads `gtag.js`, configures Google Ads (conversions, remarketing) | consent update |

The privacy page describes the active mode automatically (`privacy.cookies.consent_mode_*`). Do not paste Google's gtag or Google Tag Manager snippet into a template — `verify.sh` fails on it. GTM is deliberately not supported: tags inside a container would bypass the per-category loading; configure GA4 and Google Ads through `analytics:` instead.

**Conversions** (form sent, order placed) go through the module, which does nothing without marketing consent:

```typescript
window.cookieConsent?.conversion({ googleAds: 'AW-XXXXXXXXX/conversion-label', sklik: 100012345, value: 1500, currency: 'CZK' });
```

### Seznam Sklik

With marketing consent the module loads `https://c.seznam.cz/js/rc.js` and sends `rc.retargetingHit({ rtgId, consent: 1 })` on every page view; `conversion({ sklik: id })` sends `rc.conversionHit(…)`. Without consent nothing is loaded — Sklik has no "advanced" mode here. Seznam is listed as an independent controller in the recipients (confirm with the operator's Sklik terms).

### Other trackers (Meta Pixel, Hotjar, Clarity, LinkedIn, TikTok …)

Add them as blocked scripts; the module turns them into real scripts when their category is granted:

```twig
{# partials/_master.twig, before </body> — prefer an external file over inline code (CSP) #}
<script type="text/plain" data-consent-category="marketing" src="{{ asset('js/meta-pixel.js') }}"></script>
```

Then add their items to `privacy.cookies` (the catalog has Meta Pixel), their recipient to `privacy.recipients` and to the `marketing` purpose, and bump `config_version`.

### Embedded video and maps (CB-02)

Never write a YouTube, Vimeo or map iframe directly into a template. Use the placeholder; it names the provider, loads the embed only after the visitor clicks "Načíst obsah" (which grants the `third_party` category only), and shows it right away to visitors who already granted the category:

```twig
{% include 'partials/_consent-embed.twig' with {
    src: 'https://www.youtube-nocookie.com/embed/VIDEO_ID',
    title: 'Prohlídka dílny',
    provider: 'YouTube (Google Ireland Limited)'
} only %}
```

### Consent record, re-asking and withdrawal

- The choice is stored in `localStorage` `bolt-cookie-consent`: categories, `config_version`, time of decision, expiry, random id (CB-40). It is a necessary item and listed as such.
- **Proving consent.** CB-40 asks that the controller can demonstrate consent. The record above lives only in the visitor's browser, so on its own it proves nothing to an authority. What the site can show is the configuration history: which banner text, categories and trackers were live at which `config_version` (`privacy.changelog` in `theme.yaml`, plus git history), and that trackers cannot load without the stored choice (`verify.sh`). A site that must prove individual consents (high-risk tracking, disputes expected) needs a server-side log of the consent record — `id`, `version`, categories, timestamp, no IP address — which this skill does not ship; listen to the `cookie-consent` window event and post it to an endpoint of the project.
- Consent is valid 12 months; after "Odmítnout vše" the banner stays away for 6 months (CB-41, DP-05). A higher `config_version` asks again everyone who consented to anything, while a rejection stays valid until it expires (CB-42).
- "Nastavení cookies" (footer, layer 1, privacy page, embed placeholders) opens layer 2 with the current state (CB-30). Withdrawing a category deletes its first-party cookies (names from `privacy.cookies`, on every parent domain) and reloads the page so already running scripts stop (CB-31).
- Choosing never depends on browser settings (CB-43); closing layer 2 without saving changes nothing.

### JavaScript API

| | |
| :--- | :--- |
| `window.cookieConsent.open()` | open layer 2 |
| `window.cookieConsent.has('marketing')` | is a category granted? |
| `window.cookieConsent.conversion({ … })` | Google Ads / Sklik conversion, only with marketing consent |
| `window` event `cookie-consent` | `CustomEvent` with the record after every change |

Markup hooks (`data-cookie-*`, `data-consent-*`) are listed at the top of `examples/cookie-consent.ts` and in `WORKFLOWS.md` (Integration Contract).

---

## 6. The privacy policy page

`static-pages/gdpr.twig` is served by `TemplateController` at `/zasady-ochrany-osobnich-udaju` and `/{_locale}/zasady-ochrany-osobnich-udaju`. It follows the guidelines' recommended order and fills every mandatory block from `privacy:` — or states explicitly that it does not apply:

| Mandatory block | On the page | Data |
| :--- | :--- | :--- |
| 1. Controller | `#spravce` — one card per controller | `controllers` |
| 2. Data protection officer | in each card ("nebyl jmenován" when `dpo: ~`) | `controllers[].dpo` |
| 3. Processing by purpose | `#ucely` — table: purpose, (controller), data, legal basis + legitimate interest, retention, obligation to provide | `purposes` |
| 4. Recipients | `#prijemci` — table with role | `recipients` |
| 5. Transfers outside the EU/EEA | `#prijemci` — basis per recipient | `recipients[].transfer` |
| 6. Rights, complaint to ÚOOÚ | `#prava` | `privacy.rights.*` |
| 7. Right to object | `#namitka` — separate, visually distinct block (čl. 21/4) | `privacy.objection.*` |
| 8. Automated decision-making | end of `#ucely` | `automated_decision_making` |
| 9. Cookies | `#cookies` — same tables as layer 2, Consent Mode note, "Nastavení cookies" button | `cookies`, `analytics.consent_mode` |
| 10. Exercising rights | `#kontakt` — one contact channel, reply within one month (VAR-32) | `joint_arrangement.contact_controller` or the first controller |
| 11. Joint controllers | `#spolecne-spravcovstvi` — essence of the arrangement, rights against any controller | `joint_arrangement` |

Also: effective date and version (PP-06), summary (PP-04), table of contents, change history, and `data-cookie-banner-defer` so the bar never covers the page (PP-05).

**More than one controller.** Every controller gets an identical card (VAR-30); the purposes table gains a "Správce" column (VAR-31); purposes with `section: <controller id>` appear in that controller's own section (B2 / hybrid, VAR-20); the banner names all controllers (VAR-13). For a form where the visitor chooses the recipient, pass `controller_text` to the form note (VAR-21).

**Forms (PP-02).** Next to every submit button:

```twig
{% include 'partials/_privacy-form-note.twig' with { purpose: 'contact_form' } %}
```

No consent checkbox for contract or legitimate-interest purposes; where the basis is consent (newsletter), add an **unticked** checkbox.

**Footer (PP-01, CB-30).** `bolt-menu`'s footer links the policy on every page and shows "Nastavení cookies" whenever `privacy.cookies` contains an item that needs consent.

**Languages.** Czech is mandatory for every text (CB-23). For each further locale, merge `examples/translations.en.xlf` into `messages.<code>.xlf` and translate it, and add the locale key to every localized map in `privacy:`.

---

## 7. Measuring, filling in and handing over

**Measure (DM-02).** The catalog's cookie names and lifetimes are the providers' documented defaults, not a measurement. On the running site, in a clean browser profile without extensions:
1. Load the homepage: DevTools → Application shows no cookie and no storage key (the consent record appears only after a choice); Network shows no request to Google, Seznam, Meta or embed domains (CB-01).
2. "Přijmout vše", visit a few pages, play the embed. List every cookie and storage key per domain with its expiry.
3. Make `privacy.cookies` match: add what is missing (with a Czech purpose — nothing unclassified, INV-03), remove what does not appear, fix `expiry`, replace each `[OVĚŘIT …]`.

**Hand over (AG-05)** to the operator:
- the inventory (the `privacy.cookies` table — or the `#cookies` section of the page);
- the filled `theme.yaml` blocks;
- the list of every remaining `[DOPLNIT]` question;
- the result of `verify.sh` and of the manual acceptance checklist (guidelines, *Akceptační checklist*);
- the AG-06 note that this is not a legal assessment.

---

## 8. Verification

```bash
bash $SKILLS/bolt-cookie-consent/scripts/verify.sh --draft   # while [DOPLNIT] / [OVĚŘIT] remain
bash $SKILLS/bolt-cookie-consent/scripts/verify.sh           # sign-off: placeholders fail
```

| Step | Checks |
| :--- | :--- |
| 1 | Active theme |
| 2 | Privacy data (`scripts/check-privacy.php`) from `theme.yaml` `privacy:` or the privacy ContentType's record: placeholders; every cookie item classified with Czech purpose, provider and expiry; consent record listed when a banner exists — and not listed without one; tracker IDs inventoried; tracker cookies (`_ga`, `_gcl_*`, `_fbp`, …) listed while their ID is empty (warning: the banner asks for consent to nothing). For `theme.yaml` also: controller model and identity; joint arrangement; purposes with Czech texts, valid legal basis, concrete legitimate interest; recipients; consent lifetimes; version, date, changelog; automated decisions stated |
| 3 | Banner partials present, `_consent-mode.twig` in `<head>`, banner included in the master layout |
| 4 | Reject / Accept (layer 1) and Reject / Save / Accept (layer 2) share identical classes; settings button; layer-2 dialog; switches start off; `role="dialog"`, `aria-labelledby`, `role="switch"` |
| 5 | No implied-consent wording; one label for "Nastavení cookies" |
| 6 | No tracker script, gtag call or third-party iframe hard-coded in any template |
| 7 | `cookie-consent.ts` present and imported; no auto-hide |
| 8 | Footer links the policy (or, in the ContentType model, a record with `|link`) and has `[data-cookie-settings]` |
| 9 | Privacy page: `theme.yaml` model — route, rendered from `privacy:`, all section anchors; ContentType model — `record_template` exists, the layout reads the same record; banner deferred on the page |
| 10 | Every `cookie.*` / `privacy.*` unit in every catalog (Czech mandatory); live checks with `BOLT_BASE_URL`: no tracker script in the homepage HTML, consent configuration rendered, policy returns 200 without placeholders, the homepage links it, its sections (ContentType model), and every cookie that `/`, the policy and each `/<locale>/` homepage set is in the inventory (INV-01) |

Without trackers and embeds the banner checks are skipped and the privacy page is still verified — run this skill on every site. The behaviour that a script cannot see (DevTools before and after a choice, 360 px, keyboard and screen reader) is the manual checklist printed at the end of the run.

---

## 9. Pitfalls

- **No banner, no consent configuration, privacy page 500.** `theme.yaml` blocks come as Bolt collections: `|column('category')` finds nothing in them (no consent categories, so the banner and `_consent-mode.twig` render nothing) and a key set to `~` (`summary: ~`, `dpo: ~`) throws on access. Every template converts `privacy:` and `analytics:` with `toArray()` before use; `verify.sh` step 3 fails on a copy that does not. Found 2026-10-22 by rendering the examples with their own `theme.privacy.yaml` in Bolt 6.1.9.
- **A tracker ID without inventory never loads.** That is intended: add the items to `privacy.cookies` first.
- **…and inventory without a tracker ID asks for consent to nothing.** `_ga` items with an empty `analytics.ga4_id` still make the banner ask for analytics consent, and the policy describes processing (and a transfer to Google) that never happens. When the tracker is not used, remove its cookies together with the purpose and recipient that describe it; the banner and "Nastavení cookies" then disappear on their own. `verify.sh` step 2 warns. Found 2026-10-31 in an audit of a site prepared for GA that never got an ID.
- **Multilingual sites set a session cookie.** Bolt's `LocaleSubscriber` writes the request's locale into the session (`PHPSESSID`, lifetime `framework.session.cookie_lifetime`, 8 h with bolt-security-hardening) whenever the URL names one, even on a site without forms. Bolt's documentation does not mention it. Measured on bolt/core 6.1.10, `APP_ENV=prod`:

  | Request | Session cookie |
  | :--- | :--- |
  | Default-locale pages without a prefix (`/`, `/o-nas/…`, the policy, search, 404, sitemap, `llms.txt`) | no |
  | Every `/<locale>/…` page — and an explicit `/<default>/…` such as `/cs/…` | yes |
  | Any URL with `?_locale=xx` (any value; an unknown one redirects to the default locale) | yes |
  | A record under `/<locale>/…` that its ContentType's `locales` lack (redirect to the default locale) | yes |
  | `/<locale>/…` that matches no route (`/en/neexistuje`, `/de/` without `de` in `app_locales`) | no |
  | `/bolt/login` and the admin | yes (editors only) |

  The frontend never reads the value back — the locale always comes from the URL — but the cookie is set, so list it as necessary (language preference, § 89/3 ZEK). On a multilingual site every secondary-locale page sets it, so it is always listed: `privacy-config.php` adds it whenever `app_locales` has more than one locale, and `verify.sh` step 10 compares the `Set-Cookie` headers of `/`, the policy and every `/<locale>/` homepage with the inventory. A single-language site sets it only for a typed or linked `/cs/…` or `?_locale=` URL; list it there only when the site links such URLs. With no consent category there is no banner, so `bolt-cookie-consent` (localStorage) is never written — do not list it.
- **`theme.yaml` is cached.** Clear Bolt's cache after every change, or the banner keeps the old configuration (and the old `config_version`).
- **Changing purposes, controllers, recipients or categories** without bumping `config_version` leaves earlier consents in force for processing they never covered (CB-42).
- **`preconnect` / `dns-prefetch` to `googletagmanager.com`, `c.seznam.cz` …** contacts the provider before consent. Do not add them.
- **Inline blocked scripts** (`<script type="text/plain">…code…</script>`) need `'unsafe-inline'` or a nonce under a strict CSP; prefer `src=` files.
- **Analytics on a subdomain or with a custom cookie domain**: deletion on withdrawal covers the host and its parent domains; cookies set for other hosts cannot be deleted from this site.
- **Advanced Consent Mode** is the operator's documented decision, not a default (CB-50); `verify.sh` warns while it is on.
- **The banner include sits right after the skip link** in `partials/_master.twig` (bolt-theme-init) so keyboard users reach it early; it never takes focus on its own (CB-60).
