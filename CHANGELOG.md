# Changelog

All notable changes to `tomvondracek/bolt-skills`. Versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added
- `bolt-build`: `scripts/config-notices.php` runs the checks of the admin dashboard's **Bolt Configuration Notices** box (bolt/configuration-notices-widget) from the command line. It must exit 0 before any content is entered — a new gate in `WORKFLOWS.md` (Checkpoint 5, step 7.1) and in the `bolt-build` phase table and pitfalls.
- `bolt-contenttypes` rule 8: reserved field names. Names that Twig resolves to a method of Bolt's `Content` entity (`icon`, `status`, `author`, `fields`, …) fail everywhere; names of `SetField` methods (`label`, `value`, `name`, `type`, …) fail inside sets, which the dashboard widget does not catch. The verification lists both and names a replacement.
- `bolt-contenttypes` rule 9: an explicit `slug:` on every ContentType. Without it Bolt slugifies `name`, so `homepage:` named "Úvod" becomes `uvod` and `setcontent 'homepage'` throws.
- `bolt-contenttypes/scripts/verify.sh`: third section runs `config-notices.php`.
- `bolt-contenttypes` rule 10: all configuration in English (ContentType keys, field names, select values, template paths); only names, labels and public URL slugs use the site language. A reserved name is replaced by a contextual English name (`icon_service`, `fact_label`), not a translation. The verification fails on non-ASCII identifiers.

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
