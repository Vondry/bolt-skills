# Changelog

All notable changes to `tomvondracek/bolt-skills`. Versions follow [Semantic Versioning](https://semver.org/).

## 1.6.0 — 2026-10-22

`.env` holds everything production needs, including the secret; `.env.local` is local development only. On fmautoservis.cz the upload answered 500 until `.env.local` was uploaded too, and that file then ran production with debug on.

### Changed
- `bolt-security-hardening` Step 1: the committed `.env` carries every production value. That includes a fresh `APP_SECRET`, generated per project with a one-line command in the step, and passwords in `DATABASE_URL` / `MAILER_DSN`. An SFTP upload therefore runs on its own, with no server-side `.env.local`. The repository must stay private; rotate the secret when it is shared. `examples/env` was rewritten accordingly.
- `.env.local` only switches a developer machine to `APP_ENV=dev`, `APP_DEBUG=1` and any host (new `examples/env.local`). It is never uploaded, because on the server it switches production into dev mode. Step 7, the pitfalls and "What each step stops" follow the change.
- `check-config.php` (`verify.sh` section 1):
  - fails on an empty or placeholder `APP_SECRET` in `.env` (the upload would answer 500), and prints the command to generate one;
  - passes on a real secret;
  - warns on one shorter than 32 characters;
  - no longer fails on a committed secret or on a password in a connection string;
  - warns when `.env.local` overrides `APP_SECRET`, or sets `APP_DEBUG=1` without `APP_ENV=dev`.
- `WORKFLOWS.md` 1.5, 7.5, 8.3 and the troubleshooting row, the `bolt-build` setup notes and intake E11 / E13, and the `bolt-audit` checklist and example map follow the new convention.

### Migrating a project on the 1.5 convention
1. Copy `examples/env` over `.env` and keep the project's own values: domain, database, mailer.
2. Generate a fresh secret into `.env` with the Step 1 command.
3. Reduce the local `.env.local` to `examples/env.local`.
4. Upload `.env`, then delete the server's `.env.local` and `var/cache/prod/`.

## 1.5.1 — 2026-10-22

Compression is the host's job, not the `.htaccess`'s. The 1.5.0 finding was measured on a local Apache only. On the production hosts, every page, CSS and JS file is already gzip-compressed without any rule in `.htaccess`.

### Removed
- `bolt-htaccess` Step 7 and the `mod_deflate` block in `examples/public.htaccess`, along with both checks in `verify.sh` (back to 6 sections): the static check and the live `Content-Encoding` probe. Also removed: the compression lines in the `bolt-audit` checklist and in `WORKFLOWS.md` 2.1.

### Added
- `bolt-htaccess` Pitfall 8: "Pages are sent uncompressed" on a local Apache. Neither Bolt nor Symfony compresses responses, and the hosts do it at server level, so the only check is a `curl` for `Content-Encoding` against production after the first deployment.

## 1.5.0 — 2026-10-22

Compressed pages and a maintenance page that never touches the database. Both come from the second audit of fmautoservis.cz: 204 KB of uncompressed HTML, CSS and JS per page, and a 503 page that loaded its phone and e-mail from a settings record.

### Added
- `bolt-htaccess` Step 7: a `mod_deflate` block in `examples/public.htaccess` that compresses the text responses. That covers pages rendered by Symfony and the CSS, JS, SVG, XML and JSON files Apache serves; images, WOFF2 fonts and PDFs stay out. Brotli is left to the host, and the step includes an Nginx line. `verify.sh` gets a static check (section 6, now 7 sections) and a live `Content-Encoding` probe of the homepage and `css/index.css`.

### Changed
- `bolt-helper-pages` § 5: the zero-database rule now covers the 503 page, the standalone layout and the scene, as well as the 500 page. Maintenance mode is on while the database is migrated or restored, so `setcontent`, `menu_array()` and settings records are out.
- `bolt-helper-pages`: the 503 page shows no phone numbers, e-mail addresses, status code, times or durations, and does not call the outage planned. It can be on without anyone noticing, so it only says that the site is being worked on and offers *Zkusit znovu*. The examples and the § 7 template were updated, and `_helper_scene.twig` renders the `code` watermark only when one is passed.
- `bolt-helper-pages/scripts/verify.sh`: fails on `setcontent` / `menu_array()` in the 500 and 503 pages, the layout and the scene, and when the 503 page does not extend the standalone layout. It warns on `tel:` / `mailto:` on the 503 page. A `maintenance` entry with `/` (or a missing root entrypoint) now fails instead of warning. Section counters fixed (`[1/5]`…`[5/5]`).
- `bolt-audit` checklist (bolt-htaccess, bolt-helper-pages) and `WORKFLOWS.md` 2.1 / 6.4 follow both changes.

## 1.4.1 — 2026-10-22

Admin icons that render: ContentType icons only from the Font Awesome version Bolt bundles — from fmautoservis.cz, where two FA 6 names showed empty boxes in the sidebar.

### Added
- `bolt-contenttypes` rule 11: `icon_one` / `icon_many` must be Font Awesome Free **solid** icons of the version in `bolt/assets` (5.15.4 in Bolt 6.1). Bolt prints `fas fa-<name>`, so FA 6 / 7 names (`sliders`, `screwdriver-wrench`, `house`, `gear`, …), brand icons and style prefixes render as empty boxes. The rule includes a table of where each option renders.
- `bolt-contenttypes/references/fontawesome-5.15.4-solid.tsv`: the 1,002 solid icons, each with its FA 6 / 7 names and search terms, generated from Font Awesome's `metadata/icons.yml`.
- `bolt-contenttypes/scripts/admin-icons.php`: `check` (in `verify.sh`, now 4 sections) reads the version and icon classes from Bolt's admin CSS, fails on unknown, newer-version, brand and malformed icons, names the 5.15.4 replacement, and warns on ContentTypes without icons. `list <word>` finds renderable icons by name, newer name or meaning. `generate` builds the list for another Font Awesome version.
- `bolt-contenttypes/scripts/admin-icons-browser.js`: render check in the logged-in admin. It loads the dashboard and every listing, edit and new page, and reports every icon without a CSS rule. That covers the server-rendered headings and the JSON the Vue sidebar, toolbar and dashboard listing render from. It is part of `WORKFLOWS.md` 7.1 and the `bolt-build` Phase 7 row, and Checkpoint 5's gate names rule 11.

### Fixed
- `bolt-theme-init/examples/contenttypes_snippet.yaml`: `fa:boxes-stacked` (FA 6) → `fa:boxes`.

## 1.4.0 — 2026-10-22

Every photo gallery opens in the PhotoSwipe lightbox, and template classes use their canonical token form — both from building fmautoservis.cz.

### Added
- `bolt-theme-templates/scripts/canonical-classes.mjs`: reports every template class that has a shorter canonical form — the IDE's "The class `rounded-[var(--radius-card)]` can be written as `rounded-card`" hint — using the theme's own design system (`tailwindcss canonicalize`, Tailwind CSS v4.3+). Unlike the IDE inspection it also sees classes inside Twig strings and interpolated attributes; `--fix` rewrites the templates. `verify.sh` runs it as step 8 (now 9 steps) and fails until the templates are canonical.
- Rules for canonical classes and tokens over arbitrary values (`bolt-theme-templates` section 5, `bolt-tailwind-theme` section 3, `WORKFLOWS.md` 6.1): IDE diagnostics while editing, the script before the gate; a value match is not a meaning match; a value repeated with the same meaning becomes a role-named token (`--tracking-label`, `--spacing-page`, `--text-page`, `--breakpoint-3xs`).
- `bolt-theme-init` `photoswipe.ts`: localised UI — the button titles and error message come from the first gallery's `data-pswp-close-title`, `-zoom-title`, `-arrow-prev-title`, `-arrow-next-title`, `-error-msg` (new `gallery.*` units in the `bolt-theme-templates` catalogs); up to 12 slides kept decoded.
- `bolt-tailwind-theme` 5.H: `.pswp__custom-caption` styles (the module registered the caption element, but no skill styled it).
- `bolt-theme-init/scripts/verify.sh`: fails when templates use `.photoswipe-gallery` without the `./photoswipe` import, the `photoswipe` npm dependency or the CSS `@import`.

### Changed
- Any photo gallery gets the PhotoSwipe lightbox, also when the design does not show one (a static design has no click state) — `WORKFLOWS.md` decision matrix and 6.1, `bolt-build` intake S6, `bolt-theme-init`, `bolt-theme-templates`.

## 1.3.0 — 2026-10-22

ContentType safety (reserved field names, explicit slugs, English configuration) with a config-notices gate before content, and fixes from the fmautoservis.cz audit.

### Added
- `bolt-build`: `scripts/config-notices.php` runs the checks of the admin dashboard's **Bolt Configuration Notices** box (bolt/configuration-notices-widget) from the command line. It must exit 0 before any content is entered — a new gate in `WORKFLOWS.md` (Checkpoint 5, step 7.1) and in the `bolt-build` phase table and pitfalls.
- `bolt-contenttypes` rule 8: reserved field names. Names that Twig resolves to a method of Bolt's `Content` entity (`icon`, `status`, `author`, `fields`, …) fail everywhere; names of `SetField` methods (`label`, `value`, `name`, `type`, …) fail inside sets, which the dashboard widget does not catch. The verification lists both and names a replacement.
- `bolt-contenttypes` rule 9: an explicit `slug:` on every ContentType. Without it Bolt slugifies `name`, so `homepage:` named "Úvod" becomes `uvod` and `setcontent 'homepage'` throws.
- `bolt-contenttypes/scripts/verify.sh`: third section runs `config-notices.php`.
- `bolt-contenttypes` rule 10: all configuration in English (ContentType keys, field names, select values, template paths); only names, labels and public URL slugs use the site language. A reserved name is replaced by a contextual English name (`icon_service`, `fact_label`), not a translation. The verification fails on non-ASCII identifiers.

### Fixed
- `bolt-theme-init`: the `collapse` mobile menu closes on Escape and returns focus to the menu button, as the drawer and the dropdowns already did (`examples/js/src/menu.ts`).
- `bolt-theme-templates/scripts/verify.sh` [7/8]: a utility must start a token, so ids and slugs such as `jak-to-funguje` are no longer reported as missing `to-*` gradient classes.

## 1.2.0 — 2026-10-19

New skill `bolt-legal-cz`, and fixes from a review of every skill against bolt/core 6.1.9 and four production sites.

### Added
- `bolt-legal-cz`: mandatory legal information for Czech business websites. Asks first who operates the site (OSVČ – živnostník, company, regulated profession, non-business), renders the § 435 OZ identity (name, seat, IČO, Trade / Commercial Register entry, DIČ) and the consumer information (ADR body, complaints, terms, the § 1830a withdrawal button from 1. 1. 2027, review verification) from `theme.yaml` in the footer of every page, and verifies the data against ARES and the live site. `scripts/check-site.php` checks any website without a Bolt project. Wired into `bolt-menu`'s footer, `WORKFLOWS.md` (Phase 0 decisions, step 6.6), the `bolt-build` intake (L1–L5), `verify-all.sh` and `bolt-audit`.

### Security
- `bolt-runtime-extensions`: `locale_link()` returns `#` for any scheme other than `http`, `https`, `mailto` and `tel`, so a `javascript:` link stored in an editable field never reaches an `href`.
- `bolt-htaccess`: `public/.htaccess` runs only `index.php`; any other `*.php` in `public/` answers 403. The verifier warns when the rule is missing.
- `bolt-helper-pages`: the 500 and 503 config entries name root entrypoints without `/`, because Bolt looks up `dir/template.twig` as a record (a database query) before rendering it. Documents the two core listeners that still break the branded 500 page when the database is down.
- `bolt-add-language`: the locale switcher collapses leading slashes (no off-site link from `//host` requests) and keeps the base path of sub-directory installs.
- `bolt-cookie-consent`: scripts held back as `type="text/plain"` keep their CSP nonce when activated.
- `bolt-security-hardening`: documents a nonce path for the strict CSP and the trade-off of `style` / `id` / `name` in the HTML cleaner.

### Fixed
- `bolt-runtime-extensions`: the download-size filter is now `format_file_size`. Bolt core already registers `format_bytes`, which won, so the skill's filter never ran. Sizes use decimal units (1 kB = 1000 B) and take a decimal separator.
- `bolt-runtime-extensions`: `locale_link('/')` returns `/en/` (Bolt's localized homepage route) instead of `/en`, which cost a redirect and left the menu's home item inactive.
- `bolt-extension-setup`: sitemap listing alternates use the listing route of each locale (they used the singular record slug); adds `x-default`; drops the deprecated `image:title`; llms.txt links go through `markdown_url`.
- `bolt-contenttypes`: rule 5 explains the real risk of non-localized text (the English tab overwrites the shared value) instead of a validation error that does not happen; `html` is Trumbowyg, not CKEditor.
- `bolt-timezone`: dates are stored as wall time without a zone, not UTC; adds the migration note for live sites.
- `bolt-tailwind-theme`: tokens use `@theme static inline`, so `--color-accent` and the other tokens always exist as CSS variables (helper pages read them); smooth scrolling respects reduced motion.
- `bolt-asset-caching`: one Nginx source for `/theme/`, `/files/` and `/thumbs/` (bolt-security-hardening); the static-file block no longer drops security headers with `add_header`.
- `bolt-menu`: the drawer is `role="dialog" aria-modal="true"`; dropdown ids are deterministic; CTA detection matches whole class names.
- `bolt-theme-templates`: `lead` is cleaned with `|sanitise`; pagination uses valid markup; `picture.twig` takes `sizes`; listing links come from the route instead of a hard-coded slug.
- `bolt-theme-init`: the example ContentType has `sanitise: true`; the scaffold rejects unsafe theme names.
- `bolt-code-quality`: `ecs.php` uses the successors of the deprecated `BracesFixer` and `NewWithBracesFixer` (identical output); CI pins the extension installer and checks Composer's installer signature; `make install` is marked dev-only.

### Changed
- Verifiers parse instead of grepping: `bolt-add-language` (`check-language.php`: app_locales, ContentTypes, catalog key parity, menu labels) and `bolt-contenttypes` (`check-contenttypes.php`).
- `bolt-code-quality` fails on ECS and PHPStan errors (they were notices).
- `bolt-disable-api` refuses `404` on data endpoints (only switched-off features may 404).
- `bolt-tailwind-theme` builds into a temporary file and `bolt-timezone` boots the kernel with temporary cache folders: audits no longer write into the theme or `var/cache/prod`.
- `bolt-extension-setup` checks installed packages, not `composer.json`.
- Repository CI (`.github/workflows/ci.yml`): `composer validate`, `php -l`, `bash -n`, ShellCheck and YAML parsing of the examples.

## 1.1.3 — 2026-10-10

See the git history for 1.0.0 – 1.1.3.
