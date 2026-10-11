# Bolt CMS Agent Skills

This repository provides curated AI agent skills, task procedures, and verification runbooks for projects using [Bolt CMS](https://boltcms.io) 6.

## Available Skills

- [`bolt-disable-api`](skills/bolt-disable-api/SKILL.md): Comprehensive procedure to disable or lock down API Platform, GraphQL, and OpenAPI documentation endpoints in Bolt CMS across both development and production environments.
- [`bolt-add-language`](skills/bolt-add-language/SKILL.md): Step-by-step procedure to add a new language/locale with full parity across routing parameters, ContentTypes, XLIFF 2.0 catalogs, navigation menus, and theme switchers.
- [`bolt-contenttypes`](skills/bolt-contenttypes/SKILL.md): Comprehensive guidelines, architectural rules, and verification script for creating, modifying, and validating Bolt CMS ContentTypes and fields in `config/bolt/contenttypes.yaml` (including `sanitise: true` on every rich-text field and no `allow_twig`).
- [`bolt-extension-setup`](skills/bolt-extension-setup/SKILL.md): Complete setup, configuration recipes, templates, and verification script for AppoloDev/bolt-seo, bolt/sitemap-extension (with PR #5 singleton override), and Vondry/bolt-llms-txt.
- [`bolt-helper-pages`](skills/bolt-helper-pages/SKILL.md): Comprehensive architecture, dual-base layout strategy, zero-database safety rules, and brand-aligned visual scenes for 404, 403, 500, and 503 maintenance screens.
- [`bolt-timezone`](skills/bolt-timezone/SKILL.md): Timezone parity (Europe/Prague) across Bolt config, Kernel boot override, Docker INI, and compose environment to prevent the date-shifting save bug.
- [`bolt-htaccess`](skills/bolt-htaccess/SKILL.md): Two-tier Apache .htaccess setup: root HTTPS redirect and ./public forwarding, plus public/.htaccess protection — an allowlist for theme/, files/ and thumbs/ (only built assets and accepted upload types are served), a safety-net deny list for sources, configs and dumps, and security headers for static files (HSTS, nosniff, sandboxed uploads).
- [`bolt-code-quality`](skills/bolt-code-quality/SKILL.md): Complete setup for Easy Coding Standard (PSR-12/cleanCode), PHPStan Level 8 static analysis on src/, unified Makefile commands (cscheck, csfix, stancheck, csclear, audit), safe Bolt migration sync, and GitLab CI matrix (PHP 8.2–8.5) with composer / npm audit jobs.
- [`bolt-security-hardening`](skills/bolt-security-hardening/SKILL.md): Application security for Bolt CMS 6: fail-safe `.env` with secrets only on the server (SFTP deployments), trusted hosts against password-reset poisoning, trusted proxies, no /_fragment, isolated secure sessions, login throttling, password policy, Bolt config (upload whitelist, HTML cleaner, query search, version disclosure), file-editor permissions, nelmio security headers and Content-Security-Policy, deployment checklist, dependency audits, and live checks against the running site.
- [`bolt-asset-caching`](skills/bolt-asset-caching/SKILL.md): Multi-layer asset and thumbnail caching setup: resolves the Symfony firewall /thumbs session-listener cache bug, configures Bolt save_files disk caching, Apache mod_expires, Nginx static expires, and frontend ?v=X.X cache-busting.
- [`bolt-performance`](skills/bolt-performance/SKILL.md): Optional Twig fragment cache for heavy pages: `{% cache %}` from twig/cache-extra wired to `cache.app.taggable`, so Bolt's content-save events invalidate it, a reusable `partials/_cached.twig` that caches on GET only (preview and forms render live), tagging rules (ContentType slugs, `record.cacheKey`) and a verification of the setup.
- [`bolt-theme-init`](skills/bolt-theme-init/SKILL.md): Bootstrap, scaffold, and verify a new Bolt CMS theme from scratch with Component/Container/Page architecture (pure components with zero setcontent, smart containers, page orchestrators with zero raw HTML, page-scoped components, and product listing/record detail examples), Tailwind CSS v4 CLI, and Rollup TypeScript build pipeline.
- [`bolt-tailwind-theme`](skills/bolt-tailwind-theme/SKILL.md): Extract and configure Tailwind CSS v4 design tokens (@theme inline), WCAG AA contrast scales, Czech latin-ext font-faces, scanning safeguards, and the complete blueprint of repeating cross-project utilities (.wrapper, .btn variants, .card, .link-arrow, .pagination, and .cms-redactor).
- [`bolt-runtime-extensions`](skills/bolt-runtime-extensions/SKILL.md): Deploy, register, and verify custom runtime PHP Twig extensions in `src/` (LocaleLinkExtension with query/hash preservation, ImageDimensionsExtension with cached disk probe for PhotoSwipe v5, FileSizeExtension for human-readable downloads).
- [`bolt-menu`](skills/bolt-menu/SKILL.md): Configure, structure, and verify Bolt CMS navigation menus in `config/bolt/menu.yaml` (header `main`, footer columns, nested submenus, multilingual labels, `/#anchor` formatting, and CTA classes) with Twig Component/Container integration.
- [`bolt-cookie-consent`](skills/bolt-cookie-consent/SKILL.md): Intake-driven (trackers such as Google Ads, GA4, Sklik, Meta; embeds; controller model) Czech ZEK § 89 / GDPR cookie banner and Privacy Policy page (/zasady-ochrany-osobnich-udaju), both rendered from one `theme.yaml` data model: two-layer opt-in banner with equal Accept / Reject, Google Consent Mode v2, consent-gated embeds, and verification against the ÚOOÚ / EDPB guidelines in `references/guidelines.cs.md`.
- [`bolt-theme-templates`](skills/bolt-theme-templates/SKILL.md): Production standards, component libraries, and automated verification for Twig + Tailwind CSS v4 templates under Component/Container/Page architecture (zero-setcontent pure UI components, smart containers, zero-HTML page orchestrators, and page-scoped components).
- [`bolt-build`](skills/bolt-build/SKILL.md): Builds a complete Bolt CMS 6 website from a design (Figma MCP, Pencil .pen MCP, images/PDF, an existing site or a brief) by running WORKFLOWS.md end to end — reads the design first, asks every question in one upfront intake, then runs Phases 1–8 autonomously with a resumable progress log, visual QA and a final audit.
- [`bolt-audit`](skills/bolt-audit/SKILL.md): Read-only audit of an existing Bolt CMS 6 project against all the skills above — project profile, every verification script with full logs, comparison with the skills' examples, a one-by-one review per skill, and a prioritized `AUDIT.md` (defects vs. convention deviations, severity, evidence, fix).

## End-to-End Orchestration Workflow

When building a complete website from scratch or based on a design (Figma, Pencil, tokens, brief), agents run [`bolt-build`](skills/bolt-build/SKILL.md), which executes the master runbook:
- [`WORKFLOWS.md`](WORKFLOWS.md): Phase-by-phase execution graph guiding agents through all 17 skills in dependency order, with an Integration Contract (shared layout, folders, tokens, JS hooks, URLs, translation keys) that every theme-facing skill follows:
  0. **Phase 0: Intake & Site Plan** (decisions recorded in the project's `AGENTS.md`, including `bolt-cookie-consent`'s privacy intake; user checkpoint)
  1. **Phase 1: Environment & Security Baseline** (`bolt-timezone`, `bolt-add-language` step 1 — locale parameters, `bolt-disable-api`, `bolt-code-quality` setup, `bolt-security-hardening` configuration)
  2. **Phase 2: Web Server Delivery & Caching** (`bolt-htaccess` [Apache], `bolt-asset-caching`, `bolt-security-hardening` headers & CSP)
  3. **Phase 3: Extensions & Runtime PHP** (`bolt-extension-setup` packages & config, `bolt-runtime-extensions`)
  4. **Phase 4: Theme Foundation, Layout Shell & Design Tokens** (`bolt-theme-init`, contract master layout, `bolt-menu` templates, `bolt-tailwind-theme`, JS wiring)
  5. **Phase 5: Content Model & Navigation** (`bolt-contenttypes`, static routes, `bolt-menu` content, XLIFF catalogs; user checkpoint)
  6. **Phase 6: Templates & Features** (`bolt-theme-templates`, `bolt-extension-setup` theme overrides, locale switcher, `bolt-helper-pages`, `bolt-cookie-consent`, optional `bolt-performance` fragment cache)
  7. **Phase 7: Content, Translations & Production Build** (seed records, translations, SEO per locale, `npm run prod`, deployment per `bolt-security-hardening`)
  8. **Phase 8: QA & Sign-Off** (`bolt-code-quality` run, `scripts/verify-all.sh`, live smoke checks, Definition of Done)
- **Translation Merge Helper**: `php scripts/merge-xliff.php <skill>/examples/translations.<locale>.xlf translations/messages.<locale>.xlf` adds the units a skill's templates use to a project catalog (never overwrites existing translations).
- **Master Verification Runner**: Execute `./scripts/verify-all.sh --project=/path/to/project` to validate the skills in workflow order. Use `--skip=` for skills that do not apply, `--base-url=` for live HTTP checks; `bolt-add-language` is verified once per secondary locale from `app_locales`.

## Skill Standard

All skills in this repository follow the open agent standard:
- Documented in `skills/<skill_name>/SKILL.md` with YAML frontmatter (`name`, `description`).
- Deterministic steps with concrete file paths, configuration diffs, and pitfalls.
- Executable verification scripts under `scripts/verify.sh`.

## Auditing an Existing Project

To check an existing site against the skills instead of building one, use [`bolt-audit`](skills/bolt-audit/SKILL.md): `bash skills/bolt-audit/scripts/audit.sh --project=/path/to/project [--base-url=…]` runs the automated part (read-only, report in `var/bolt-audit/<timestamp>/`); the skill then guides the per-skill review and the `AUDIT.md` report.
