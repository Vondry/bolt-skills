# Per-skill review checklist

For each skill, in this order: read its `logs/<skill>.log`, its rows in `examples.md`, then its
`SKILL.md`, and check the points below. "Script" lists what `verify.sh` already decided — do not
repeat it, interpret it. "Review" lists what only reading the project shows. "Severity hints"
say how to rate typical findings (levels in `report-template.md`).

**Defect or deviation?** A *defect* breaks something the skill exists to prevent (security,
legal, data loss, broken pages, performance). A *deviation* is a project that works but is built
differently from the skill's convention (another folder layout, other names, another menu
profile). Report defects with a fix; report deviations once per skill with the cost of aligning,
and never inflate them into many findings. A failing script line on a project that does not use
the convention is a deviation, not a defect.

---

## 1. bolt-timezone
- **Script:** `timezone` in `config/bolt/config.yaml`, `src/Kernel.php` override, Docker INI files, compose database TZ, runtime timezone after kernel boot.
- **Review:** every layer says `Europe/Prague` (or the site's zone) — none left at UTC; Twig dates use `|localdate` / `|date` without hard-coded offsets; `compose.yaml` of every environment (dev and prod overrides).
- **Severity hints:** a layer missing → High (dates shift on every save).

## 2. bolt-disable-api
- **Script:** API Platform / GraphQL routes in the router, YAML validity, `api_platform` flags, live endpoints (with `--base-url`).
- **Review:** ask whether anything consumes the API (mobile app, headless frontend, integrations). If yes, the skill's lock-down variant applies and the full-disable check is expected to fail — check permissions and firewall instead (WORKFLOWS Appendix B.3).
- **Severity hints:** API reachable without a consumer → Critical; documentation (`/api/docs`, GraphiQL) public → High.

## 3. bolt-code-quality
- **Script:** composer dev dependencies and scripts, `ecs.php`, `phpstan.dist.neon`, Makefile targets, CI file, live ECS / PHPStan runs.
- **Review:** `examples.md` drift of `ecs.php` / `phpstan.dist.neon` (level lowered? paths excluded? baseline hiding errors?); CI runs the checks on every push; `make db-update` / `db-reset` not used in production (Appendix B.8).
- **Severity hints:** no static analysis at all → Medium; PHPStan level lowered or broad `ignoreErrors` → Medium; style violations → Low.

## 4. bolt-htaccess *(Apache only — N/A on Nginx)*
- **Script:** root `.htaccess` (HTTPS, forward to `public/`), `public/.htaccess` directives and source shielding, live 403s for theme sources (with `--base-url` against **Apache**, not `symfony serve`).
- **Review:** diff of `public/.htaccess` — removed `FilesMatch` / `RedirectMatch` deny rules, `node_modules/` inside `public/theme`, `.env`, `composer.*`, `*.twig`, `*.yaml`, backups and dumps reachable; whether the vhost document root is `public/` (then the root file is optional).
- **Severity hints:** templates / config / `.env` / dumps downloadable → Critical; missing HTTPS redirect → High.

## 5. bolt-asset-caching
- **Script:** `/thumbs` firewall bypass in `security.yaml`, `save_files: true`, `mod_expires` in `public/.htaccess`, Nginx static rules.
- **Review:** with `--base-url`, response headers of a `/thumbs/…` URL (`Cache-Control: public`, no `Set-Cookie`) and of `css/index.css` (long max-age); `?v=` cache-busting in the master layout bumped on releases (`assets_version`).
- **Severity hints:** thumbnails `private, max-age=0` or regenerated per request → High (performance); missing expires on static assets → Medium.

## 6. bolt-extension-setup
- **Script:** packages in `composer.json`, extension config files, recipes, SEO field in ContentTypes, SEO tags in templates, theme `extensions/` folder (sitemap override, `llms.txt.twig`).
- **Review:** `appolo-boltseo.yaml` fallback fields match real field names; every routable ContentType has the `seo` field; the sitemap override is still needed (bolt/sitemap-extension PR #5, Appendix B.6); `/llms.txt` content is real, not the blueprint.
- **Severity hints:** no SEO tags / sitemap → Medium; blueprint text left in `llms.txt` → Low.

## 7. bolt-runtime-extensions
- **Script:** the three `src/*Extension.php` files, service registration and bindings, container compilation and Twig registration.
- **Review:** drift of the PHP files against the examples (`examples.md`, kind `logic`) — security-relevant parts of `LocaleLinkExtension` (query / hash preservation, no open redirect) and the cached disk probe of `ImageDimensionsExtension`; unused extensions are fine (warning expected).
- **Severity hints:** `locale_link` dropping query strings or building external URLs → High; missing optional extension → Info.

## 8. bolt-theme-init
- **Script:** active theme, directory, Component/Container/Page structure and `partials/_master.twig`, no `setcontent` in components, ContentType template bindings, build tooling, compiled assets.
- **Review:** if the theme predates the convention (no `components/`, `containers/`, `pages/`), report **one** deviation with the cost of migrating; inside the existing structure check what the convention protects: queries (`setcontent`) inside reusable includes, the master layout's blocks and includes (SEO, consent, skip link), `assets_version` cache-busting, a build that runs (`npm run prod` exists and the committed bundle is fresh).
- **Severity hints:** convention deviation → Medium (one finding); no skip link / no `lang` → Medium (accessibility); stale or missing build → High.

## 9. bolt-tailwind-theme
- **Script:** entrypoint, `@source` scanning safeguards, `@theme` tokens, `scroll-margin-top`, repeating utilities, compilation.
- **Review:** Tailwind v4 CSS-first config (not a v3 `tailwind.config.js`); tokens named by role, not by colour; WCAG AA contrast of text tokens on their backgrounds; fonts self-hosted with `latin-ext` (no Google Fonts request — also a GDPR finding); `@source not` for `node_modules`, `vendor`, helper pages.
- **Severity hints:** Google Fonts loaded from Google → High (GDPR, also bolt-cookie-consent); contrast below 4.5:1 → Medium; naming / token structure → Low.

## 10. bolt-contenttypes
- **Script:** YAML syntax; rules: no `type: html`, singletons with `order: -id`, slug `uses`, no `repeater`, required-but-not-localized fields, `default_status` of viewless singletons.
- **Review:** each script error (they are real configuration bugs); required non-localized fields only matter on multilingual sites — confirm with how editors translate; YAML anchors for repeated field groups.
- **Severity hints:** singleton without `order: -id` → High (wrong record shown); `type: html` → Medium; missing `uses` → Medium; multilingual required-field warnings → Medium on multilingual sites.

## 11. bolt-menu
- **Script:** `menu.yaml` existence, YAML, structure (root-slash anchors `/#…`, label parity per locale, no locale prefixes in links, CTA flags), navigation templates, `locale_link` wrapping.
- **Review:** the header and footer render from `menu.yaml` (not hard-coded links); mobile navigation is keyboard-operable (Escape closes, focus trapped while open); footer links the privacy policy and cookie settings.
- **Severity hints:** hard-coded navigation → Low; anchors without root slash → Medium (broken on subpages); inaccessible mobile menu → Medium.

## 12. bolt-theme-templates
- **Script:** directories and master, zero `setcontent` in components, page orchestrators, `locale_link` usage, `__()|default()` misuse, classes missing from the compiled CSS, `lint:twig`.
- **Review:** raw HTML volume in `pages/` (Appendix B.1); Bolt 6 pager (`pager(records, …)`, not the Bolt 3 API); images through a picture component with `alt`, dimensions and thumbnails (no full-size originals); heading order; translated strings instead of literals on multilingual sites.
- **Severity hints:** classes not in the CSS → High (unstyled UI); originals served instead of thumbnails → Medium (performance); literal strings on a multilingual site → Medium.

## 13. bolt-helper-pages
- **Script:** error page mappings in `config/bolt/config.yaml`, helper templates, SEO / robustness (noindex, no DB on 500), Tailwind bundle isolation, `lint:twig`.
- **Review:** the 500 and 503 templates query nothing (no `setcontent`, no menu) — they must render with the database down; 404 offers a way back (home, search); texts in the site's tone (Appendix B.5: default locale only).
- **Severity hints:** 500 page querying the database → High; default Bolt error pages in production → Medium.

## 14. bolt-cookie-consent
- **Script:** the `theme.yaml` `privacy:` data model, banner wiring and compliance, wording, hard-coded trackers, footer, privacy page and route, translations, live HTML.
- **Review:** projects built before this skill usually have no `privacy:` block, so most script failures are a **deviation** (another banner implementation). Judge the existing banner and policy against `skills/bolt-cookie-consent/references/guidelines.cs.md` directly — that is where the **defects** are:
  - CB-01: tracker (GA, Sklik, Meta, Hotjar, embeds, Google Fonts) loaded before a choice — read the master layout and the profile's "Tracking found" line; with `--base-url`, fetch the homepage HTML.
  - CB-10–CB-12 / DP-01–DP-02: Reject in layer 1, a button, same styling as Accept.
  - CB-20 / DP-03: no pre-ticked categories; CB-30: settings link in the footer; CB-05: no "používáním webu souhlasíte".
  - Privacy page: the 11 mandatory blocks (guidelines, *Povinný obsah*), controller identity (§ 435 OZ), a cookie list matching what the site sets.
  - CB-02: YouTube / map iframes without a placeholder.
- **Severity hints:** tracking before consent, Reject missing from layer 1, no privacy page, cookies not described → Critical (ÚOOÚ fines exactly these); unequal buttons, missing footer link, English-only descriptions → High; not using the skill's data model → Medium (one deviation; migration = scaffold with the intake).

## 15. bolt-add-language *(multilingual only — once per secondary locale)*
- **Script:** locale in `services.yaml`, ContentType `locales`, catalog existence and unit parity, XLIFF lint, `menu.yaml` labels, locale switcher.
- **Review:** in the browser (with `--base-url`), a few `/<code>/…` pages show translated text, not keys or Czech fallbacks (Appendix B.4); `hreflang` alternates in the SEO tags; the switcher keeps the current page instead of jumping home.
- **Severity hints:** untranslated keys visible → High; missing `hreflang` → Medium; parity gaps in rarely used units → Low.

---

## Beyond the skills

Note these too, as *Info* or higher, when you see them during the review — they are outside any
single skill but belong in an audit of a Bolt 6 site: `APP_ENV=prod` / `APP_DEBUG=0` on
production, `composer audit` and `npm audit` advisories, secrets committed to git (`.env.local`,
keys), backups of `var/data` / database dumps inside `public/`, Lighthouse (mobile) scores below
90, missing `robots.txt` / canonical URLs.
