---
name: bolt-build
description: >-
  Build a complete Bolt CMS 6 website from a supplied design — Figma (Figma MCP), Pencil / pen.dev
  (.pen via Pencil MCP), exported images or PDF, an existing website, or a brief — by running the
  whole WORKFLOWS.md (Phases 0–8, all 18 skills) autonomously. Reads the design first, asks every
  question the workflow needs in one upfront intake, writes the site plan, then builds, verifies,
  commits gate by gate and keeps a resumable progress log. Use when asked to create, build or
  implement a website (or "make this design into a Bolt site").
---

# Build a Bolt CMS Website from a Design (`bolt-build`)

`WORKFLOWS.md` describes *what* to build in which order; this skill is *how an agent runs it end
to end with as little interruption as possible*:

1. read the design before asking anything, so most answers are proposals to confirm;
2. ask **all** remaining questions in one upfront intake;
3. get one approval (Checkpoint 0), then run Phases 1–8 alone — choosing documented defaults,
   logging every decision, fixing failing gates, committing after each gate;
4. keep a progress log in the project's `AGENTS.md`, so any later session resumes where the last
   one stopped;
5. finish with a full verification, an independent audit and a handover list.

| File | Use |
| :--- | :--- |
| [`references/intake.md`](references/intake.md) | Every question the 18 skills need, in five rounds, with defaults and the phase that uses each answer |
| [`references/design-sources.md`](references/design-sources.md) | What to extract from Figma MCP, Pencil MCP, images/PDF, an existing site or a brief; token mapping; visual QA loop |
| [`references/site-plan-template.md`](references/site-plan-template.md) | Site plan, build progress, decisions log, open issues and handover — written into the project's `AGENTS.md` |
| `scripts/preflight.sh` | Tools, PHP extensions, Bolt version, console, database, git, local URL — before Phase 1 |

The phase steps themselves are **not** repeated here: for every phase follow `WORKFLOWS.md`
(Integration Contract, the phase section, its gate) and the `SKILL.md` of each skill it names.
`$SKILLS` below is `vendor/tomvondracek/bolt-skills/skills` (or a checkout of this repository).

---

## Step 0 — New build or resume?

Read the project's `AGENTS.md`. If it has a `## Build progress` table, this is a **resume**:
- re-read `## Site plan`, `## Decisions log`, `## Open issues` and `var/bolt-build/design/design-notes.md`;
- `git log --oneline -15` and `git status` to see where the last session stopped;
- continue at the first phase that is not `done` — do not repeat the intake, do not re-ask answered questions.

Otherwise start at Step 1.

## Step 1 — Preflight

```bash
bash $SKILLS/bolt-build/scripts/preflight.sh --project=<dir> [--base-url=<local URL>]
```

Resolve blockers with the user now (missing Node, PHP extension, wrong Bolt version) — they would
otherwise stop the run in Phase 4. Warnings are handled by Phase 1 or recorded in the site plan.

## Step 2 — Read the design

Follow `references/design-sources.md` for the source the user gave. Produce, before any question:
- the **inventory** (pages, sections, breakpoints), the **content model proposal** (ContentTypes, fields, menu profile, features), the **token table**, the **component list**, extracted **copy and assets**;
- reference screenshots and `design-notes.md` in `var/bolt-build/design/`.

If the design tool does not respond (MCP server not connected), say so and ask the user to start it
or to export images — never reconstruct a design from guesses.

## Step 3 — Upfront intake

Ask the rounds in `references/intake.md`:
- Round 1 (environment) and Round 2 (structure — mostly the design proposal to confirm) first;
- Round 3 only for gaps the design left; Round 4 operator facts; Round 5 autonomy.

Use the agent's structured-question tool, where it has one, for multiple-choice items (recommended
default first), and one message for free-text facts. Do not drip-feed questions across phases. What the user leaves unanswered gets
the default and a *Decisions log* entry; operator facts (legal identity, IDs, retention) stay
`[DOPLNIT]` and go to the handover list — never invented.

Secrets: never ask the user to paste passwords into the chat. Account creation is interactive, so the
user runs it themselves in their own terminal (in Claude Code: type the command with the `!` prefix,
which runs it in the user's session): on a new project
`php bin/console bolt:setup --no-fixtures` (migrations, `APP_SECRET`, first account — run it **once**:
it resets `APP_SECRET` and writes a new migration every time); on an existing database
`php bin/console bolt:add-user --admin`. `bolt:setup` writes `APP_SECRET` into the committed `.env`:
move it to `.env.local` before the baseline commit (`bolt-security-hardening` Step 1).

## Step 4 — Site plan and Checkpoint 0

Write `## Site plan`, `## Build progress`, `## Decisions log`, `## Open issues` and `## Handover`
into the project's `AGENTS.md` (`references/site-plan-template.md`). Show the plan — with the
design direction, the page/URL map, the ContentTypes and the menu — and get **one** approval.
This is the only mandatory stop. Further checkpoints only if the user chose them (A1).

## Step 5 — Run Phases 1–8 autonomously

For each phase: set its row to `in progress`, follow the `WORKFLOWS.md` section and each named
skill's `SKILL.md`, run the phase's verifications, fix, commit, set the row to `done`, move on.
Where the design and the intake answers flow in:

| Phase | Input from the intake / design | Concretely |
| :--- | :--- | :--- |
| 1 | E1, E3, E6, E7, E9, E11, E13, O10, S1 | `composer create-project bolt/project <dir>` (new); SQLite from Bolt's default `.env` for the local build (no database configuration; the production database of E13 is set on the server in `.env.local`); the user runs `php bin/console bolt:setup --no-fixtures` in their terminal (it prompts for the first account; never Bolt's sample fixtures); admin user (Step 3 secrets rule), `git init` + baseline commit (with `/var/bolt-build/` in `.gitignore`), `composer require --dev tomvondracek/bolt-skills`; timezone, `app_locales`, API disable or lock-down, code quality for the chosen CI, `bolt-security-hardening` configuration (`.env` defaults, trusted hosts from E7) |
| 2 | E5, E6, E12 | Apache vs. Nginx branch of `bolt-htaccess` / `bolt-asset-caching`; nelmio headers and baseline CSP; admin restriction if E12 asks for it |
| 3 | S6 | keep / remove `ImageDimensionsExtension` (gallery), `FileSizeExtension` (downloads); note removals as expected warnings |
| 4 | E8, D1–D5, O1, O9, L2, token table | `bolt-theme-init` scaffold `<theme>`; `theme.yaml` contact, socials, logo, `analytics:`; `bolt-menu --profile=<S4> --templates --force`; tokens and self-hosted fonts from `design-notes.md` into `css/tailwind/index.css`; JS imports per features |
| 5 | S3–S5, S1, content model proposal | `contenttypes.yaml`, static routes, `menu.yaml` with labels per locale, catalogs |
| 6 | frames, components, O2–O8, L1–L5, S7, S11 | one orchestrator per page from its frame, containers for queries, page-scoped components; **visual QA loop** (`design-sources.md`) per page; `--products=auto`; locale switcher; helper pages with the metaphor; `bolt-cookie-consent` scaffold with `--model --trackers --embeds --purposes` from O2–O7; `_privacy-form-note` beside every form; embeds through `_consent-embed`; `bolt-legal-cz` scaffold with `--operator --consumers --online-contracts --reviews` from L1–L5, identity checked with `verify.sh --ares`, `_reviews-notice` under testimonials; optionally `bolt-performance` fragment caches for pages with a high query count |
| 7 | S2, S8–S10, O11, O12, E11, copy | records from the design copy or supplied content (through the admin in a browser if S10 allows), media-library uploads, translations, SEO per locale, `llms.txt`, `npm run prod`, `assets_version`, deployment checklist (7.5) for the hosting of E11 |
| 8 | E4, E7 | linters, `verify-all.sh` with `BOLT_BASE_URL`, smoke checks, manual checks with a browser tool, Lighthouse, then the independent audit (Step 6) |

### Autonomy rules

- **Stop only for blockers**: missing credentials or access, an environment failure the agent cannot fix (database server down, network), a decision outside the site plan that changes architecture (a new language, hosting change, a feature not in the design), or anything destructive outside the project. Everything else: apply the documented default, log it, continue.
- **Decisions log**: every default applied without confirmation and every judgement call (a field added, a breakpoint chosen, a token adjusted for contrast) — one dated line each.
- **Failing gate**: diagnose with the skill's verify output and `WORKFLOWS.md` Troubleshooting, fix, re-run. After three failed attempts (A3): record it under *Open issues* with what was tried, mark the phase `done with open issues`, and continue only if later phases do not depend on the failing part; otherwise mark it `blocked` and stop with a report.
- **Verifications scheduled later** (WORKFLOWS Appendix A) are not failures — do not chase them early.
- **Commits** after every gate, in the project's commit convention (default `chore(build): phase N — <summary>`); never push unless E10 says so; never rewrite history.
- **Stay inside the project**: no global installs, no changes to other directories, no deployment.
- **No fixtures, ever**: the database is SQLite from Bolt's default `.env`, initialised once with `bolt:setup --no-fixtures`. Never run `doctrine:fixtures:load` or `bolt:setup` without `--no-fixtures`; never run `make db-reset` on a database with content (it drops everything). Schema changes after Phase 5 go through `make db-update` — on the local database only: it drops tables Doctrine does not map and marks migrations as run without running them; servers run `doctrine:migrations:migrate` (`bolt-code-quality` Step 4).
- **Operator facts are never invented** (`bolt-cookie-consent` AG-01, `bolt-legal-cz` AG-02): `[DOPLNIT]` and the handover list. The operator type (L1) is always asked, never assumed.
- **Context discipline** on long runs: re-read the phase section and the skill's `SKILL.md` at the start of each phase rather than relying on memory; keep design details in `design-notes.md`, not in the conversation. A new session resumes from the progress table.
- **Parallel agents** only if the user allowed them (A4) — e.g. independent page templates in 6.1. Each gets the site plan, the Integration Contract and its frames; the main agent integrates, builds and verifies.

## Step 6 — Final verification and audit

1. Phase 8 of `WORKFLOWS.md` in full (8.1–8.5).
2. An independent check of the finished site with the audit runner:
   ```bash
   bash $SKILLS/bolt-audit/scripts/audit.sh --base-url=<local URL>
   ```
   Every skill should be PASS, or WARN with a reason listed under *Expected verification warnings*. Fix what is not.
3. Visual sign-off: final screenshots of every page at every design breakpoint and 360 px next to the references, saved in `var/bolt-build/qa/`.

## Step 7 — Handover

Report to the user, briefly:
- the local URL, admin URL, and how to start the site;
- what was built (pages, ContentTypes, languages, features) and the final verification result;
- *Open issues* and remaining visual differences (with screenshot paths);
- the *Handover* list: every `[DOPLNIT]` and `[OVĚŘIT]` (privacy data, legal identity and consumer pages, tracker IDs, measured cookies), unconfirmed defaults, content the operator must supply;
- what is outside the workflow: deployment, DNS, mail delivery for forms, production database.

---

## Pitfalls

- **Asking question by question during the build.** Everything answerable is in the intake; new questions mid-run are a sign a default should have been applied and logged.
- **Pasting generated code from a design tool.** Figma's `get_design_context` returns React + Tailwind with arbitrary values; translate it into Twig with contract tokens and components, or the undefined-class check fails and the theme drifts from the tokens.
- **Design colours outside the contract.** Map to roles (`design-sources.md`); a new colour name renders unstyled.
- **Google Fonts from Google's CDN** violates the consent rules — self-host (`bolt-tailwind-theme`).
- **Iframes straight from the design** (YouTube, maps) — always `_consent-embed.twig`.
- **`bolt-menu` scaffold without `--force`** on a fresh `bolt/project` stops before copying templates (sample `menu.yaml` exists).
- **Seeding content before Phase 5 is final** — every ContentType change after content entry means re-entering records.
- **Skipping the progress table update** — the next session cannot resume reliably.
