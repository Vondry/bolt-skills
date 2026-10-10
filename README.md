# Bolt CMS Agent Skills (`tomvondracek/bolt-skills`)

A curated collection of production-tested AI agent skills, task procedures, and verification runbooks for building, securing, and maintaining websites with [Bolt CMS](https://boltcms.io) **6**.

Compatible with **Google Antigravity**, **Claude Code**, **Gemini**, **Cursor**, **IBM Bob**, and other LLM agent frameworks.

---

## Available Skills

| Skill | Description | Location |
| :--- | :--- | :--- |
| **`bolt-disable-api`** | Complete procedure to safely disable or lock down API Platform, GraphQL, and OpenAPI documentation across Dev and Prod environments. | [`skills/bolt-disable-api/`](skills/bolt-disable-api/SKILL.md) |
| **`bolt-add-language`** | End-to-end procedure to add a new language/locale across routing, ContentTypes, XLIFF catalogs, menus, and theme switchers. | [`skills/bolt-add-language/`](skills/bolt-add-language/SKILL.md) |
| **`bolt-contenttypes`** | Standards, best practices, and automated validator for creating/updating ContentTypes and fields (no raw HTML, sanitised rich text, mandatory singleton ordering, viewless blocks, sets/collections). | [`skills/bolt-contenttypes/`](skills/bolt-contenttypes/SKILL.md) |
| **`bolt-extension-setup`** | Complete setup and verification for essential Bolt extensions: AppoloDev/bolt-seo, bolt/sitemap-extension (with PR #5 singleton override), and Vondry/bolt-llms-txt. | [`skills/bolt-extension-setup/`](skills/bolt-extension-setup/SKILL.md) |
| **`bolt-helper-pages`** | Architecture, dual-base layouts, zero-database safety rules, and brand-aligned visual scenes for 404, 403, 500, and 503 maintenance pages. | [`skills/bolt-helper-pages/`](skills/bolt-helper-pages/SKILL.md) |
| **`bolt-timezone`** | Timezone parity (Europe/Prague) across Bolt config, Kernel boot override, Docker INI, and compose environment to prevent the date-shifting save bug. | [`skills/bolt-timezone/`](skills/bolt-timezone/SKILL.md) |
| **`bolt-htaccess`** | Two-tier Apache .htaccess setup: root HTTPS redirect and ./public forwarding, plus an allowlist for theme/, files/ and thumbs/, a safety-net deny list, and security headers for static files (HSTS, nosniff, sandboxed uploads). | [`skills/bolt-htaccess/`](skills/bolt-htaccess/SKILL.md) |
| **`bolt-code-quality`** | Complete setup for Easy Coding Standard (PSR-12/cleanCode), PHPStan Level 8 static analysis on src/, unified Makefile commands (cscheck, csfix, stancheck, csclear, audit), safe Bolt migration sync, and GitLab CI matrix (PHP 8.2–8.5) with composer / npm audit. | [`skills/bolt-code-quality/`](skills/bolt-code-quality/SKILL.md) |
| **`bolt-security-hardening`** | Application security: fail-safe `.env` with secrets only on the server (SFTP deployments), trusted hosts, sessions, login throttling, password policy, upload whitelist and HTML cleaner, file-editor permissions, security headers and CSP (nelmio), deployment checklist, dependency audits, live checks. | [`skills/bolt-security-hardening/`](skills/bolt-security-hardening/SKILL.md) |
| **`bolt-asset-caching`** | Multi-layer asset and thumbnail caching setup: resolves the Symfony firewall /thumbs session-listener cache bug, configures Bolt save_files disk caching, Apache mod_expires, Nginx static expires, and frontend ?v=X.X cache-busting. | [`skills/bolt-asset-caching/`](skills/bolt-asset-caching/SKILL.md) |
| **`bolt-theme-init`** | Bootstrap, scaffold, and verify a new Bolt CMS theme from scratch with Component/Container/Page architecture, Tailwind CSS v4 CLI, and Rollup TypeScript build pipeline. | [`skills/bolt-theme-init/`](skills/bolt-theme-init/SKILL.md) |
| **`bolt-tailwind-theme`** | Extract and configure Tailwind CSS v4 design tokens (@theme inline), WCAG AA contrast scales, Czech font-faces, and reusable utility blueprints (.wrapper, .btn, .card, .cms-redactor). | [`skills/bolt-tailwind-theme/`](skills/bolt-tailwind-theme/SKILL.md) |
| **`bolt-runtime-extensions`** | Deploy, register, and verify custom runtime PHP Twig extensions in `src/` (LocaleLinkExtension, ImageDimensionsExtension, FileSizeExtension). | [`skills/bolt-runtime-extensions/`](skills/bolt-runtime-extensions/SKILL.md) |
| **`bolt-menu`** | Configure, structure, and verify navigation menus in `config/bolt/menu.yaml` (header, footer, submenus, anchors, CTAs) with Twig Component/Container patterns. | [`skills/bolt-menu/`](skills/bolt-menu/SKILL.md) |
| **`bolt-cookie-consent`** | Asks which trackers (Google Ads, GA4, Sklik, Meta), embeds and controller model the site uses, then builds a Czech ZEK § 89 / GDPR two-layer opt-in cookie banner (equal Accept / Reject, Google Consent Mode v2) and the Privacy Policy page from one `theme.yaml` data model, verified against ÚOOÚ / EDPB guidelines. | [`skills/bolt-cookie-consent/`](skills/bolt-cookie-consent/SKILL.md) |
| **`bolt-theme-templates`** | Build and verify Twig + Tailwind v4 templates under Component/Container/Page architecture (pure UI components, smart containers, zero-HTML page orchestrators). | [`skills/bolt-theme-templates/`](skills/bolt-theme-templates/SKILL.md) |
| **`bolt-build`** | Build a complete website from a design (Figma MCP, Pencil .pen MCP, images/PDF, an existing site or a brief): reads the design, asks every question upfront, then runs the whole workflow autonomously with progress tracking, visual QA and a final audit. | [`skills/bolt-build/`](skills/bolt-build/SKILL.md) |
| **`bolt-audit`** | Read-only audit of an existing Bolt CMS 6 project against all skills: profile, every verification script, comparison with the examples, per-skill review and a prioritized `AUDIT.md` report. | [`skills/bolt-audit/`](skills/bolt-audit/SKILL.md) |

---

## End-to-End Website Scaffolding Workflow

To orchestrate and scaffold a complete, production-grade Bolt CMS website from a Figma design, tokens, or project brief:
- Ask your agent to build the site with the **`bolt-build`** skill and give it the design: a Figma link (Figma MCP), a `.pen` file (Pencil MCP), exported images or PDF, an existing website or a brief. It reads the design, asks all questions in one upfront intake, gets your approval of the site plan, and then runs every phase below on its own — progress is logged in the project's `AGENTS.md`, so a later session continues where it stopped.
- Read **[`WORKFLOWS.md`](WORKFLOWS.md)** for the phase-by-phase execution graph (Phase 0 intake through Phase 8 sign-off), the Integration Contract shared by all theme skills, the decision matrix, the skill-to-phase map, and troubleshooting tips.
- Execute the master verification suite **`scripts/verify-all.sh`** to validate the skills in workflow order:
  ```bash
  ./scripts/verify-all.sh --project=/path/to/bolt-project \
      --base-url=http://localhost:8080 \
      --skip=bolt-htaccess                # only skills that do not apply to this site (e.g. Nginx)
  ```
  `bolt-add-language` is verified once per secondary locale read from `app_locales` in `config/services.yaml` (override with `--locales=en,de`) and skipped on single-language sites.
- Merge the translation units shipped by the skills (`skills/<skill>/examples/translations.<locale>.xlf`) into the project catalogs:
  ```bash
  php vendor/tomvondracek/bolt-skills/scripts/merge-xliff.php \
      vendor/tomvondracek/bolt-skills/skills/bolt-theme-templates/examples/translations.cs.xlf translations/messages.cs.xlf
  ```
  Missing units are added; existing translations are never changed.

---

## Auditing an Existing Project

Point an agent at an existing site and ask for an audit (`bolt-audit` skill), or run the automated part yourself:

```bash
bash vendor/tomvondracek/bolt-skills/skills/bolt-audit/scripts/audit.sh \
    --base-url=https://staging.example.cz      # optional: live HTTP checks against this project
```

The audit changes nothing in the project. It writes a profile, the logs of all verification scripts, a comparison of the project's files with the skills' examples and a summary to `var/bolt-audit/<timestamp>/` (kept out of `git status` through the clone's local `.git/info/exclude`); the agent then reviews each skill and writes `AUDIT.md` with findings by severity and the skill step that fixes each one.

---

## Installation via Composer

```bash
composer require --dev tomvondracek/bolt-skills
```

The package is a Composer plugin, so on the first install Composer asks you to trust it (`Do you trust "tomvondracek/bolt-skills" to execute code?`). Answer `y`; the choice is stored in `config.allow-plugins`.

That is all. On every `composer install` / `composer update` the plugin:

- symlinks each skill into `.claude/skills/<skill>` (Claude Code) and `.agents/skills/<skill>` (other agents), pointing to `vendor/tomvondracek/bolt-skills/skills/<skill>`;
- adds those links to a managed block in `.gitignore`, so they are never committed (teammates get them from their own `composer install`);
- adds a managed "Bolt CMS Agent Skills" block to the project's `AGENTS.md` (created if missing) listing the skills and `WORKFLOWS.md`;
- removes links to skills that no longer exist in the installed version.

Skills of your own in the same folders are left untouched; an existing file or folder with the same name as a bundled skill is skipped with a warning.

### Removal

```bash
composer remove --dev tomvondracek/bolt-skills
```

removes every skill link, the managed blocks in `.gitignore` and `AGENTS.md`, and any file or folder the plugin created that is now empty. Your own content is kept as it was.

### Configuration (optional)

In the project's `composer.json`:

```json
"extra": {
    "bolt-skills": {
        "targets": [".claude/skills", ".agents/skills"],
        "agents-md": true,
        "gitignore": true
    }
}
```

- `targets`: skill folders to link into, relative to the project root.
- `agents-md`: set to `false` to leave `AGENTS.md` alone.
- `gitignore`: set to `false` to leave `.gitignore` alone (for example, to commit the links).

---

## Updating Skills

Whenever new skills or updates are released, update with Composer:

```bash
composer update tomvondracek/bolt-skills
```

---

## Structure of a Skill

Every skill in this repository follows open agent guidelines:

```text
skills/<skill_name>/
├── SKILL.md          # Step-by-step instructions with YAML frontmatter
├── scripts/          # Optional executable test/verification scripts
│   └── verify.sh
├── examples/         # Optional templates and code snippets
└── references/       # Optional detailed documentation
```

### Writing New Skills
When adding a new skill:
1. Create a new directory under `skills/<skill_name>/`.
2. Add a `SKILL.md` with standard YAML frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: >-
     Describe what the skill does and when an agent should activate it.
   ---
   ```
3. Include exact file paths, before/after snippets, and an automated verification script under `scripts/`.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
