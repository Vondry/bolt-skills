---
name: bolt-audit
description: >-
  Read-only audit of an existing Bolt CMS 6 project against every bolt-skills skill. Profiles the
  project, runs all 18 verification scripts in workflow order, compares the project's files with
  the skills' examples, then reviews each skill one by one (logs, SKILL.md rules, references) and
  writes a prioritized AUDIT.md report — defects vs. convention deviations, severity, evidence and
  the skill step that fixes each finding. Use when asked to audit, review, check or assess an
  existing Bolt site, or before taking over or upgrading one.
---

# Bolt CMS Project Audit (`bolt-audit`)

Checks an existing Bolt CMS 6 project against all skills in this repository and reports what to improve. The audit **changes nothing** in the project: no scaffold, no installer, no edits, no cache clear. Fixing comes afterwards, through the individual skills, once the user has read the report.

The skills are applied in [`WORKFLOWS.md`](../../WORKFLOWS.md) phase order; the audit checks them in the same order. Files in this skill:

| File | Use |
| :--- | :--- |
| `scripts/audit.sh` | Profile + every skill's `verify.sh` with full logs + example comparison + summary |
| `references/example-map.tsv` | Where each skill example lives in a project, and whether drift matters (`logic`) or is expected (`design`) |
| `references/review-checklist.md` | Per skill: what the script covers, what to review by hand, severity hints, defect vs. deviation |
| `references/report-template.md` | Structure and severity scale of `AUDIT.md` |

---

## Rules

1. **Read-only.** Never run a skill's `scaffold.sh`, `privacy-config.php`, `merge-xliff.php`, `composer install/update/require`, `npm install`, `bin/console cache:clear` or any write command in the audited project, and never edit its files — even to "quickly fix" something. Exceptions, all runtime data: the report directory; `var/cache/<env>` warmed by the verify scripts' `bin/console` calls; `var/cache/ecs` (ECS keeps its cache there, as `make cscheck` does). The Tailwind build check compiles into a temporary file and the timezone check boots the kernel with temporary cache folders, so neither touches the theme or `var/cache/prod`. Live checks are GET requests, but against a running site the asset delivery check (`bolt-asset-caching`) makes Bolt generate and save the thumbnails it requests — the same as a visitor's first view.
2. **Evidence for every finding**: a file and line, a log line or an HTTP response. If you could not check something, list it under *Not checked* — do not guess.
3. **Defect or deviation.** A project built differently from the skills' conventions is not broken. Report a deviation once per skill with the cost of aligning; report defects individually (see the top of `review-checklist.md`).
4. **Live checks only against the right site.** Use `--base-url` only with a URL the user confirmed belongs to this project. For `bolt-htaccess` it must be served by Apache (staging), not `symfony serve`.
5. **Operator questions stay questions.** API consumers, the Consent Mode decision, legal facts of the privacy policy — ask, or list them under *Not checked*.

---

## Step 1 — Prepare

- Locate the skills: `SKILLS=vendor/tomvondracek/bolt-skills/skills` in a project that has the package, otherwise the path of a checkout of this repository. The audit does **not** require the package to be installed in the audited project.
- Ask the user (one message):
  - the URL of a running instance of **this** project for live checks (local, staging; none is fine);
  - whether anything consumes the REST/GraphQL API;
  - how the site is deployed (SFTP upload, git pull, CI) — it decides how `bolt-security-hardening` reads the committed `.env`;
  - which skills do not apply on purpose (for example a site that deliberately has no theme build).
- Note the git state: the audit reports the commit it saw (`profile.md`).

## Step 2 — Run the automated part

From the project root:

```bash
bash $SKILLS/bolt-audit/scripts/audit.sh --base-url=https://staging.example.cz   # or without --base-url
#   --project=/path/to/project   audit another directory
#   --delivery-url=https://…      site for the asset delivery check (default: --base-url when
#                                 Apache / Nginx / LiteSpeed answers there; never symfony serve)
#   --out=DIR                     report directory (default var/bolt-audit/<timestamp>/, kept out of git
#                                 through the clone's local .git/info/exclude)
#   --skip=bolt-htaccess          skills that do not apply on purpose
#   --only=bolt-cookie-consent    re-run selected skills
#   --strict                      exit 1 when a skill fails (CI)
```

It writes `profile.md`, `summary.md` / `summary.tsv`, `logs/<skill>.log`, `examples.md` and `diffs/`. With `--base-url` it also requests every sitemap URL (with each secondary-locale prefix), the search page and a missing URL, and lists the status codes in `http.md` (`http-smoke` row: any 5xx is a failure, any other non-200 a warning, the missing URL must answer 404) — pages that crash are invisible to the file-based checks. The asset delivery check of `bolt-asset-caching` (where each thumbnail and upload comes from, `ETag`, 304s) runs against `--delivery-url`, or against `--base-url` when its `Server` header names Apache, Nginx or LiteSpeed; `profile.md` says which (*Asset delivery check*). Against `symfony serve` it is off — pass `--delivery-url` with a staging or production URL, or start `scripts/serve-apache.sh` in the project first. Applicability is decided automatically where it can be: `bolt-htaccess` is N/A on Nginx-only sites, `bolt-add-language` runs once per secondary locale and is N/A on single-language sites. `bolt-cookie-consent` and `bolt-legal-cz` run without `--draft`: placeholders count as failures in an audit. For the register comparison run `bash $SKILLS/bolt-legal-cz/scripts/verify.sh --ares` once (it needs internet access).

## Step 3 — Read the profile

`profile.md` decides how to read everything else:
- **Bolt version.** The skills target Bolt CMS 6. On Bolt 5 or older, say so at the top of the report; findings that depend on Bolt 6 behaviour become "after the upgrade".
- **Theme generation.** No `components/`, `containers/`, `pages/` → the theme predates the convention: expect `bolt-theme-init` / `bolt-theme-templates` failures that are deviations.
- **Web server, Docker, locales, tracking found, `privacy:` block** — they decide which checklist points apply.

## Step 4 — Review the skills one by one

Go through the skills in `summary.md` order. For **each** skill:

1. Read `logs/<skill>.log` completely.
2. Read the skill's `SKILL.md` — its rules, pitfalls and the parts of `references/` it names.
3. Open its rows in `examples.md`. For `logic` files read every diff: a removed rule is a finding, a deliberate improvement is not. For `design` files check that the contract survived (data hooks, includes, required attributes), not the markup.
4. Work through its section in `references/review-checklist.md`: interpret the script result (defect or deviation?), then check the *Review* points in the project's files.
5. Write down the findings with evidence, severity and fix, and the skill's one-line assessment: *compliant*, *defects*, *deviation (convention not used)* or *not applicable*.

Do not skip a skill because its script passed — the *Review* points are exactly what scripts cannot see. Keep the notes per skill; a long audit may be continued in a new session from the report directory. Large projects: the skills are independent at this step, so the review can be split between parallel agents (one or a few skills each) if the user asks for it; merge their findings in Step 5.

Then read `http.md` (every non-200 page is a finding with the template that renders it) and check the *Beyond the skills* list at the end of the checklist.

## Step 5 — Write `AUDIT.md`

Follow `references/report-template.md`: summary with the three things to fix first, a severity count, one row per skill, findings ordered Critical → Info with evidence and fix, deviations, *Not checked*, next steps in WORKFLOWS.md phase order. Save it in the report directory next to `summary.md`.

## Step 6 — Hand over

Give the user the path of `AUDIT.md`, the severity count and the *Fix first* list in a few lines. Offer to fix findings — each through its skill (e.g. "run `bolt-disable-api` § 1–5"), one skill at a time with a commit after each, and re-run `audit.sh --only=<skill>` to confirm. Do not start fixing without the user's go-ahead.

---

## Re-auditing and CI

- After fixes, `audit.sh --only=a,b` re-runs just those skills into a new report directory; compare `summary.tsv` files.
- In CI, `audit.sh --strict --out=audit-report` fails the job on any failing skill; store the directory as an artifact. Without a reachable site the live checks are skipped, not failed.

## Pitfalls

- **Reading failures literally.** Many failures on an older project only say "not built with this convention". Decide defect vs. deviation per the checklist before rating.
- **Live checks against the wrong server.** Without `--base-url` the script points live checks at a closed port on purpose; never rely on a default URL.
- **`.htaccess` rules on PHP's built-in server.** They are not applied there — `bolt-htaccess` live results only count against Apache. Locally, `bolt-asset-caching/scripts/serve-apache.sh start` serves the project with its own `.htaccess` files; the htaccess and delivery checks send `X-Forwarded-Proto: https` to it so the root HTTPS redirect stays quiet.
- **Local live checks read `.env.local`.** A developer's `.env.local` (`APP_ENV=dev`, `APP_DEBUG=1`, empty `SYMFONY_TRUSTED_HOSTS` / `BOLT_CANONICAL`) makes a local instance fail the security live checks (debug token, stack traces, foreign `Host`) and send `X-Robots-Tag: noindex` (Symfony's `disallow_search_engine_index` follows `kernel.debug`). Those are not findings about the committed `.env`. To see production behaviour locally without editing files, start the server with the committed values as real environment variables — they win over `.env.local` — e.g. `APP_DEBUG=0 SYMFONY_TRUSTED_HOSTS='…' BOLT_CANONICAL=https://… bash serve-apache.sh start` and send `Host: <domain>`; otherwise report those live checks against production only.
- **Missing `vendor/`.** Several checks need `composer install`; the profile says so. Ask the user to install dependencies (in their environment) rather than doing it yourself.
- **The problem/warning line counts in `summary.md`** are a size indicator only — the logs are the source.
