---
name: bolt-legal-cz
description: >-
  Mandatory legal information on Czech business websites, built and verified for Bolt CMS — and
  checkable on any live website. Asks first who operates the site (usually an OSVČ – živnostník;
  or a company, a regulated profession, a non-business) and what it does (sells to consumers,
  concludes contracts online, shows reviews), then renders the § 435 OZ identity (name, seat,
  IČO, Trade / Commercial Register entry, DIČ) and the consumer information (ADR body, complaints,
  terms, the withdrawal button from 1. 1. 2027, review verification) from theme.yaml, and verifies
  everything against ARES and the running site.
---

# Czech Legal Information on the Website (`bolt-legal-cz`)

Every Czech business website must say **who runs it**; a site that sells to consumers must also say **where consumers can turn** and **how to complain**; a site that sells online needs the full set of consumer-contract information. This skill:

1. asks who operates the website and what the site does (Step 0);
2. writes the answers to `theme.yaml` (`contact:` + `legal:`) and renders them from one partial in the footer of every page;
3. verifies the data (check digit, ARES), the templates and the live site — `scripts/check-site.php` also checks **any** website, Bolt or not.

The legal baseline is [`references/requirements.cs.md`](references/requirements.cs.md) (Czech, state of 19. 10. 2026). Its IDs (`OP-`, `ID-`, `SP-`, `EC-`, `REG-`, `WB-`, `AG-`) are used throughout this file, the templates and the scripts. The privacy policy and cookie banner are **not** here — they are `bolt-cookie-consent` (GDPR-01).

> **Not legal advice (AG-03).** The skill makes sure the mandatory information exists, is correct against the register and is visible. Facts come from ARES and the operator — never invent them (AG-02): leave `[DOPLNIT …]` and put the question on the handover list. The texts of terms and conditions, the complaints procedure and anything regulated belong to a lawyer.

---

## 1. Step 0 — Intake (ask before writing any file)

**The first question is always who operates the website** (AG-01). Most sites built with these skills belong to a sole trader, so offer that as the first, recommended option — but let the user answer; never assume it. Ask with your question tool if you have one, otherwise in one chat message, and record the answers in the project's `AGENTS.md` site plan (`WORKFLOWS.md`, Phase 0; `bolt-build` intake L1–L5).

| # | Question | Options (first = default) | Becomes |
| :- | :--- | :--- | :--- |
| 1 | **Who operates the website?** | **OSVČ – živnostník** (trade licence) · company in the Commercial Register (s.r.o., a.s., …) · regulated profession (advokát, lékař, architekt, daňový poradce …) · non-business (spolek, private person) | `--operator=trade \| company \| profession \| other` |
| 2 | **IČO** of the operator | — (then ARES gives name, seat, Commercial Register entry, VAT status) | `contact.ico`; `verify.sh --ares` |
| 3 | **Does the business sell products or services to consumers** (people outside their business)? A plumber, hairdresser, photographer, car service or tutor does. | yes · no, businesses only | `--consumers` / `--no-consumers` |
| 4 | Only for 3 = yes, sector-specific services: **energy, telecoms, financial services or legal services?** Otherwise the ADR body is ČOI. | no (ČOI) · energy (ERÚ) · telecoms (ČTÚ) · financial (finanční arbitr) · advokát (ČAK) | `--adr=coi \| eru \| ctu \| finarbitr \| cak` |
| 5 | **Are contracts concluded on the website** — cart, order form with payment, paid booking, subscription? (An enquiry form followed by a quote is not.) | no · yes | `--online-contracts` |
| 6 | **Does the site show reviews, ratings or client testimonials?** | no · yes — and are they verified, how? | `--reviews`, `legal.reviews.verification` |
| 7 | **Special cases:** 50+ employees, or an AML obliged person (real-estate broker, accounting / tax services …) → whistleblowing page; 10+ employees or turnover above EUR 2 M → accessibility (only with question 5); regulated profession → chamber and title. | none | `--whistleblowing`, `--not-microenterprise`, `legal.regulated` |

When the operator type from question 1 and ARES disagree (ARES shows a Commercial Register entry for someone who answered "živnostník"), ARES wins and the user is told — a sole trader can be registered in the Commercial Register, and then that entry is what the site must show (ID-04).

---

## 2. Architecture

```
theme.yaml
├── contact:  name (ID-01) · address = registered seat (ID-02) · ico (ID-03) · email · phone
└── legal:    operator · registry (ID-04) · dic (ID-07) · consumers · adr (SP-01) · complaints_url (SP-03)
              online_contracts · terms_url · withdrawal_url (EC-05) · microenterprise (EC-06)
              reviews (SP-06) · regulated (REG-01) · whistleblowing / whistleblowing_url (WB-01)
      │
      ├── partials/_legal-identity.twig ── in the footer of every page: identity, register entry,
      │                                    regulated profession, ADR body with its web address,
      │                                    links to terms / complaints / withdrawal / whistleblowing
      └── partials/_reviews-notice.twig ── below every block that shows reviews (SP-06)
```

**One source of truth (AG-04).** `contact:` already feeds the footer, contact containers, helper pages, `llms.txt` and the first controller of `bolt-cookie-consent`'s privacy policy. `legal:` adds only what the legal checks need. Templates and translation catalogs never repeat the facts; `verify.sh` warns about an IČO typed into a template and fails when the privacy policy's controller differs from `contact:`.

| File (in the theme) | Source | Role |
| :--- | :--- | :--- |
| `theme.yaml` → `legal:` | `scripts/scaffold.sh` | The profile. Shape and comments: `examples/theme.legal.yaml` |
| `partials/_legal-identity.twig` | `examples/` | Identity block; included by `bolt-menu`'s footer (`ignore missing`) |
| `partials/_reviews-notice.twig` | `examples/` | "Whether and how reviews are verified" line |
| `translations/messages.*.xlf` | `examples/translations.*.xlf` | `legal.*` units — wording only |

Register entry (`legal.registry`) by operator:

| `operator` | Keys | Rendered (cs) |
| :--- | :--- | :--- |
| `trade` | `office` (optional) | „Podnikatel zapsaný v živnostenském rejstříku[, živnostenský úřad: …].“ |
| `company` | `court`, `section`, `insert` (from ARES) | „Zapsáno v obchodním rejstříku: Městský soud v Praze, oddíl C, vložka 12345.“ |
| `profession`, `other` | `text` (localized) | the text, e.g. „Advokát zapsaný v seznamu advokátů ČAK pod ev. č. 12345“ |

---

## 3. Scaffold

From the Bolt project root:

```bash
# Typical: a sole trader offering services to consumers, with client testimonials
bash $SKILLS/bolt-legal-cz/scripts/scaffold.sh --operator=trade --consumers --reviews

# An s.r.o. with an online shop
bash $SKILLS/bolt-legal-cz/scripts/scaffold.sh --operator=company --consumers --online-contracts

# An attorney: regulated profession, ADR body is the Czech Bar Association
bash $SKILLS/bolt-legal-cz/scripts/scaffold.sh --operator=profession --consumers --adr=cak

# B2B only
bash $SKILLS/bolt-legal-cz/scripts/scaffold.sh --operator=company --no-consumers
```

The scaffold appends `legal:` to `theme.yaml` (kept when one exists), copies `partials/_legal-identity.twig` (and `_reviews-notice.twig` with `--reviews`), reports whether a footer includes the identity partial and prints the `merge-xliff.php` commands. With `--online-contracts` it proposes `/obchodni-podminky`, `/reklamacni-rad` and `/odstoupeni-od-smlouvy` — the pages themselves are content (Bolt records or static pages) with the operator's texts.

After the scaffold:
1. Fill `contact.name`, `contact.address` (the **registered seat**, not a workshop) and `contact.ico` — `bash $SKILLS/bolt-legal-cz/scripts/verify.sh --draft --ares` prints the ARES data and every difference. Quote the IČO (`'01234567'`): an unquoted number loses a leading zero.
2. Replace every `[DOPLNIT]` (Commercial Register entry, chamber, whistleblowing page).
3. Set `legal.dic` when ARES reports a VAT payer (ID-07).
4. Merge the `legal.*` units into every catalog; clear the cache (`bin/console cache:clear`).

---

## 4. Templates and pages

**Footer (ID-05).** `bolt-menu`'s footer includes the identity above the bottom bar on every page. A footer from elsewhere needs one line:

```twig
{% include 'partials/_legal-identity.twig' %}
```

It inherits the footer's text colour and uses only Integration-Contract tokens. Keep it as **text** — never an image of the company details — and keep the ADR web address **visible** (the law asks for the address, not only a link).

**Reviews (SP-06).** Directly below every block with reviews, star ratings or testimonials:

```twig
{% include 'partials/_reviews-notice.twig' %}
```

Without `legal.reviews.verification` it says the reviews are not verified. Write a verification text only when the operator really checks it (e.g. "Hodnocení mohou přidat jen zákazníci, kteří u nás službu objednali; každé ověřujeme podle objednávky.").

**Consumer pages (SP-03, EC).** For sites that sell to consumers, `complaints_url` points to where the complaints procedure is explained (a page, or an anchor in the terms). For online contracts also:
- **Terms and conditions** (`terms_url`): pre-contract information (EC-01), the ADR body (SP-01 — § 14 ZOS asks for it in the terms too), withdrawal (EC-04), accessibility information unless a microenterprise (EC-06).
- **Order button** (EC-03): „Objednávka zavazující k platbě“ — not "Odeslat".
- **Withdrawal page** (`withdrawal_url`, EC-05, **mandatory from 1. 1. 2027**): a prominent control labelled „Odstoupit od smlouvy“, available for the whole withdrawal period; a form where the consumer fills in or confirms name, contract identification and e-mail; a second button „Potvrdit odstoupení od smlouvy“; an automatic e-mail confirmation with the content and the date and time of sending. The footer link from `_legal-identity.twig` is the always-visible entry point; build the form with the project's form handling (Bolt `boltforms` or a controller) and keep the classic withdrawal options in the terms as well.

**Whistleblowing (WB-01).** Obliged entities publish a page with the ways to report (internally and to the Ministry of Justice), the competent person with phone and e-mail, and whether reports from outsiders are excluded; set `whistleblowing_url`.

**Multilingual sites (SP-07).** Czech is mandatory; merge `examples/translations.en.xlf` into further catalogs and give localized values (`{ cs: …, en: … }`) for `adr.name`, `registry.text`, `regulated.*` and `reviews.verification`.

---

## 5. Checking any website

`scripts/check-site.php` needs only PHP — no Bolt, no `vendor/`. Use it on an existing or a client's site before a rebuild, or after deployment:

```bash
php $SKILLS/bolt-legal-cz/scripts/check-site.php --url=https://www.example.cz --ares --consumers
#   --ico=12345678 --name="Jan Novák"      expected identity (default: the IČO found on the site, name from ARES)
#   --operator=trade|company|profession|other   (default with --ares: from the register)
#   --consumers | --no-consumers           without either, consumer checks only warn
#   --online-contracts --reviews           enable the e-shop and review checks
#   --pages=15                             homepage + legal links + sitemap URLs to read
```

It reads the homepage, its legal links (contact, terms, complaints, privacy …) and sitemap URLs, and reports: IČO on every page with a valid check digit (ID-03, ID-05), other IČOs outside legal documents (ID-09), name and seat next to it (against ARES with `--ares`), register entry for the operator type and the Commercial Register file number (ID-04), DIČ of VAT payers (ID-07), the privacy policy link (GDPR-01), leftovers of the closed EU ODR platform (SP-02), the ADR body with its web address (SP-01), complaints information (SP-03), prices only "bez DPH" (SP-04), discounts (SP-05, manual), reviews without a verification statement (SP-06, also by `review` / `testimonial` markup and schema.org), a non-Czech homepage (SP-07), and for online contracts the terms, withdrawal information and the „Odstoupit od smlouvy“ control (EC). It exits 1 when anything failed.

The checks read rendered HTML; a site that builds its footer with JavaScript only shows nothing to them — which is also what many crawlers see.

---

## 6. Verification

```bash
bash $SKILLS/bolt-legal-cz/scripts/verify.sh --draft          # while [DOPLNIT] remain
bash $SKILLS/bolt-legal-cz/scripts/verify.sh --ares           # sign-off: placeholders fail, data compared with ARES
```

| Step | Checks |
| :--- | :--- |
| 1 | Active theme |
| 2 | `theme.yaml` (`scripts/check-legal.php`): placeholders; name, seat, IČO and its check digit; operator; register entry by operator; DIČ format; ADR body for consumer sites; complaints, terms and withdrawal pages for online contracts (the withdrawal page fails from 1. 1. 2027); reviews flag; regulated profession; whistleblowing page; privacy controller = `contact:`; with `--ares`: name, seat, Commercial Register entry, Trade Register status, VAT status and DIČ against the register |
| 3 | `_legal-identity.twig` present, rendered from `theme.yaml`, included in the footer or master layout |
| 4 | No IČO typed into templates; no EU ODR link in templates, catalogs or config |
| 5 | Every review / testimonial template includes `_reviews-notice.twig` |
| 6 | Every `legal.*` unit in every catalog (Czech mandatory) |
| 7 | Live (`BOLT_BASE_URL`): `check-site.php` with the profile from `theme.yaml` |

What a script cannot judge — the content of the terms, whether discounts state the right 30-day price, the checkout button, the confirmation e-mail, accessibility of a non-microenterprise shop — is the manual list printed at the end and the *Akceptační checklist* in the requirements.

---

## 7. Pitfalls

- **A workshop or office address instead of the registered seat.** § 435 asks for the seat as registered; add a "provozovna" separately and label it.
- **Old data after a move or a change of legal form.** Re-run `verify.sh --ares` when the operator moves or converts from OSVČ to s.r.o.; ID-06 and ID-09 fail on the old identity.
- **A template's sample IČO.** Themes bought or copied from another site often keep the previous operator's IČO in a template — `verify.sh` step 4 and `check-site.php` (other IČO) find it.
- **"Neplátce DPH" is optional, "DIČ" is not on the list of § 435** — but a VAT payer shows it anyway (ID-07).
- **The EU ODR link** that many terms templates still contain is now misleading (SP-02) — remove it from the terms page in the database too; `verify.sh` sees only templates, `check-site.php` sees the rendered page.
- **ADR only as a link** ("Česká obchodní inspekce" linked, no address visible): print the address (SP-01).
- **Testimonials count as reviews.** Client quotes on a service site are consumer reviews for § 5a ZOS (SP-06).
- **`theme.yaml` is cached.** Clear Bolt's cache after changing `contact:` or `legal:`.
