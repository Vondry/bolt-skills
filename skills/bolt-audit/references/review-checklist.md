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

**Exception — the theme structure is required.** The Component/Container/Page structure
(`bolt-theme-init`, `bolt-theme-templates`) is not a style preference: every theme-facing skill
plugs into it. A theme without it is a **finding** (Medium, effort L) with the migration below —
never "keep, record as deviation".

---

## 1. bolt-timezone
- **Script:** `timezone` in `config/bolt/config.yaml`, `src/Kernel.php` override, Docker INI files, compose database TZ, runtime timezone after kernel boot.
- **Review:** every layer says `Europe/Prague` (or the site's zone) — none left at UTC; Twig dates use `|localdate` / `|date` without hard-coded offsets; `compose.yaml` of every environment (dev and prod overrides).
- **Severity hints:** a layer missing → High (dates shift on every save).

## 2. bolt-disable-api
- **Script:** API Platform routes still registered (the admin needs them for IRIs), YAML validity, `api_platform` flags, the `^/api(/|$)` deny-all firewall rule, live endpoints (with `--base-url`).
- **Review:** ask whether anything consumes the API (mobile app, headless frontend, integrations). If yes, the skill's lock-down variant applies and the full-disable check is expected to fail — check permissions and firewall instead (WORKFLOWS Appendix B.3).
- **Severity hints:** API reachable without a consumer → Critical; documentation (`/api/docs`, GraphiQL) public → High; `api_platform` route loader commented out → High (admin dashboard and listings fail with "Unable to generate an IRI" once the cache is cleared) — fix by restoring the loader, never by reopening the API.

## 3. bolt-code-quality
- **Script:** composer dev dependencies and scripts, `ecs.php`, `phpstan.dist.neon`, Makefile targets, CI file, live ECS / PHPStan runs.
- **Review:** `examples.md` drift of `ecs.php` / `phpstan.dist.neon` (level lowered? paths excluded? baseline hiding errors?); CI runs the checks on every push; `make db-update` / `db-reset` not used in production (Appendix B.8).
- **Severity hints:** no static analysis at all → Medium; PHPStan level lowered or broad `ignoreErrors` → Medium; style violations → Low.

## 4. bolt-htaccess *(Apache only — N/A on Nginx)*
- **Script:** root `.htaccess` (HTTPS, forward to `public/`), `public/.htaccess` directives, the allowlist for `theme/`, `files/`, `thumbs/` (tested with sample paths), the safety-net deny list, security headers for static files, the `mod_deflate` compression block, live 403s for theme sources and a fake `.html` upload and `Content-Encoding` on the homepage and CSS (with `--base-url` against **Apache**, not `symfony serve`).
- **Review:** diff of `public/.htaccess` — removed allowlist / `FilesMatch` deny rules, `node_modules/` inside `public/theme`, `.env`, `composer.*`, `*.twig`, `*.yaml`, backups and dumps reachable; theme files that browsers need outside `css/`, `js/`, `img/`, `images/`, `fonts/` (they answer 403 under the allowlist); whether the vhost document root is `public/` (then the root file is optional).
- **Severity hints:** templates / config / `.env` / dumps downloadable → Critical; no allowlist for `files/` (HTML / SVG uploads run as the site) → High; missing HTTPS redirect or HSTS → High; theme allowlist missing while the deny list exists → Medium; pages, CSS and JS sent uncompressed (no `mod_deflate` block and no `Content-Encoding` live) → Medium (performance).

## 5. bolt-asset-caching
- **Script:** `/thumbs` firewall bypass in `security.yaml`, `save_files: true`, `mod_expires` in `public/.htaccess` (fails without it), Nginx static rules, bolt/core saving thumbnails where their URL points (warns on 6.0.1 – 6.1.x).
- **Review:** run the delivery check — `scripts/serve-apache.sh start` + `scripts/check-delivery.php` for an Apache site, or `check-delivery.php --base-url=<production>` — and read where thumbnails and uploads come from on the second request (disk vs. PHP) and whether they get `ETag`, `Last-Modified`, a `max-age` and 304s; response headers of `css/index.css` (long max-age); `?v=` cache-busting in the master layout bumped on releases (`assets_version`).
- **Severity hints:** thumbnails `private, max-age=0` or served by PHP on every request → High (performance; on bolt/core 6.0.1 – 6.1.x note it as an upstream bug fixed by bolt/core #3828, not a project defect); uploads / thumbnails without `max-age` (missing `mod_expires`) → Medium; theme images without expiry → Low.

## 6. bolt-security-hardening
- **Script:** committed `.env` (APP_ENV, APP_DEBUG, APP_SECRET, SYMFONY_TRUSTED_HOSTS), `.env.local` in git, framework config merged for prod (trusted hosts / proxies, fragments, session), login throttling, remember-me, password policy, Bolt `config.yaml` (upload types, `verify_peer`, HTML cleaner, query search, version disclosure), `permissions.yaml` (file editor), nelmio headers and CSP, `composer audit`, Bolt version; with `--base-url`: foreign `Host` header, profiler / debug token, stack traces, secret files, page / upload headers, session cookie flags, `/_fragment`.
- **Review:** ask how the site is deployed (SFTP, git, CI) and whether the server's `.env.local` sets `APP_ENV=prod` and its own `APP_SECRET` — the files only show the committed defaults; with `--base-url` the live part settles it. Check `git log -p -- .env` for secrets committed earlier (rotate them even if `.env` is clean now). Read `composer audit` for the affected packages — advisories in `twig/twig`, `symfony/*` or `enshrined/svg-sanitize` matter, abandoned dev tools less. Who has admin accounts (`/bolt/users`), and are there `ROLE_DEVELOPER` accounts nobody uses.
- **Severity hints:** foreign Host header accepted, profiler / debug mode or a secret file reachable live → Critical; real `APP_SECRET` in git, `APP_ENV=dev` committed on an SFTP-deployed site, dangerous upload types, no login throttling, `verify_peer: false` → High; file editor for themes / config, sessions of 14 days, no CSP, no password policy, `composer audit` advisories → Medium; version disclosure, query search, `X-XSS-Protection` → Low.

## 7. bolt-performance *(optional — only when the theme uses `{% cache %}`)*
- **Script:** when `{% cache %}` is used: `twig/cache-extra` installed, `twig.runtime.cache` on `cache.app.taggable`, no forms / CSRF / `app.user` / `app.session` / `app.flashes` inside cached blocks, `tags()` present, GET-only rendering (`partials/_cached.twig`), literal tags are ContentType slugs.
- **Review:** save a record of each tagged ContentType in the admin and confirm the cached page changes; check that paged listings vary the key by page. A site without fragment caching is not a finding.
- **Severity hints:** fragments never invalidated (no override, wrong tags) or containing forms / user data → High; preview showing cached content → Medium; missing `tags()` → Low.

## 8. bolt-extension-setup
- **Script:** packages in `composer.json`, extension config files, recipes, SEO field in ContentTypes, SEO tags in templates, theme `extensions/` folder (sitemap override, `llms.txt.twig`).
- **Review:** `appolo-boltseo.yaml` fallback fields match real field names; every routable ContentType has the `seo` field; the sitemap override is still needed (bolt/sitemap-extension PR #5, Appendix B.6); `/llms.txt` content is real, not the blueprint.
- **Severity hints:** no SEO tags / sitemap → Medium; blueprint text left in `llms.txt` → Low.

## 9. bolt-runtime-extensions
- **Script:** the three `src/*Extension.php` files, service registration and bindings, container compilation and Twig registration.
- **Review:** drift of the PHP files against the examples (`examples.md`, kind `logic`) — security-relevant parts of `LocaleLinkExtension` (query / hash preservation, no open redirect) and the cached disk probe of `ImageDimensionsExtension`; unused extensions are fine (warning expected).
- **Severity hints:** `locale_link` dropping query strings or building external URLs → High; missing optional extension → Info.

## 10. bolt-theme-init
- **Script:** active theme, directory, Component/Container/Page structure and `partials/_master.twig`, no `setcontent` in components, ContentType template bindings, build tooling, compiled assets.
- **Review:** if the theme predates the convention (no `components/`, `containers/`, `pages/`), report **one finding** — *Theme not in the Component/Container/Page structure* — with this migration as the fix:
  1. snapshot the rendered HTML of every URL (sitemap in every locale, search, 404) before touching anything;
  2. `git mv` every template that queries (`setcontent`, `menu_array()`) to `containers/<area>/_<name>.twig`, pure templates to `components/<group>/<name>.twig`, pages to `pages/<name>/<name>.twig` / `<name>.record.twig` (page-only pieces to `pages/<name>/components/`); `partials/` keeps only the master layout, locale switcher and consent partials;
  3. move queries that sit inside pages into containers; give the master layout the `seo`, `head`, `header`, `main`, `footer`, `scripts` blocks;
  4. update every include, `homepage_template`, `search_results_template` and the ContentType `record_template` / `listing_template`;
  5. compare the snapshots — only intended changes may differ — and run `bolt-theme-init` and `bolt-theme-templates` verification.
  Inside the structure, also check the master layout's blocks and includes (SEO, consent, skip link), `assets_version` cache-busting, and a build that runs (`npm run prod` exists and the committed bundle is fresh).
- **Severity hints:** structure missing → Medium (one finding, effort L); no skip link / no `lang` → Medium (accessibility); stale or missing build → High.

## 11. bolt-tailwind-theme
- **Script:** entrypoint, `@source` scanning safeguards, `@theme` tokens, `scroll-margin-top`, repeating utilities, compilation.
- **Review:** Tailwind v4 CSS-first config (not a v3 `tailwind.config.js`); tokens named by role, not by colour; WCAG AA contrast of text tokens on their backgrounds; fonts self-hosted with `latin-ext` (no Google Fonts request — also a GDPR finding); `@source not` for `node_modules`, `vendor`, helper pages.
- **Severity hints:** Google Fonts loaded from Google → High (GDPR, also bolt-cookie-consent); contrast below 4.5:1 → Medium; naming / token structure → Low.

## 12. bolt-contenttypes
- **Script:** YAML syntax; rules: no `type: html`, singletons with `order: -id`, slug `uses`, no `repeater`, text fields without `localize: true` on multilingual ContentTypes, `localize` without `locales`; `sanitise: true` on every `redactor` / `article` field, no `allow_twig`, no `sanitise: false`.
- **Review:** each script error (they are real configuration bugs); non-localized text fields only matter on multilingual sites — a field the editors translate must be `localize: true` (otherwise the English tab overwrites the Czech value), a shared value (name, URL) may stay as it is; YAML anchors for repeated field groups.
- **Severity hints:** Redactor / Article without `sanitise: true` or any `allow_twig` → High (stored XSS / code execution by editors); singleton without `order: -id` → High (wrong record shown); `type: html` → Medium; missing `uses` → Medium; non-localized text that editors translate → Medium on multilingual sites (content in the wrong language).

## 13. bolt-menu
- **Script:** `menu.yaml` existence, YAML, structure (root-slash anchors `/#…`, label parity per locale, no locale prefixes in links, CTA flags), navigation templates, `locale_link` wrapping.
- **Review:** the header and footer render from `menu.yaml` (not hard-coded links); mobile navigation is keyboard-operable (Escape closes, focus trapped while open); footer links the privacy policy and cookie settings.
- **Severity hints:** hard-coded navigation → Low; anchors without root slash → Medium (broken on subpages); inaccessible mobile menu → Medium.

## 14. bolt-theme-templates
- **Script:** directories and master, zero `setcontent` in components, page orchestrators, `locale_link` usage, `__()|default()` misuse, classes missing from the compiled CSS, `lint:twig`.
- **Review:** raw HTML volume in `pages/` (Appendix B.1); Bolt 6 pager (`pager(records, …)`, not the Bolt 3 API); images through a picture component with `alt`, dimensions and thumbnails (no full-size originals); heading order; translated strings instead of literals on multilingual sites.
- **Severity hints:** a page answering 500 (see `http.md`) → High; classes not in the CSS → High (unstyled UI); originals served instead of thumbnails → Medium (performance); literal strings on a multilingual site → Medium.

## 15. bolt-helper-pages
- **Script:** error page mappings in `config/bolt/config.yaml`, helper templates, SEO / robustness (noindex; no `setcontent` / `menu_array()` in the 500 and 503 pages, the standalone layout or the scene; no `tel:` / `mailto:` on the 503 page), Tailwind bundle isolation, `lint:twig`.
- **Review:** the 500 and 503 templates query nothing (no `setcontent`, no menu) — they must render with the database down; the 503 page shows no contact details, numbers or time promises (it can be on without anyone noticing); 404 offers a way back (home, search); texts in the site's tone (Appendix B.5: default locale only).
- **Severity hints:** 500 or 503 page querying the database → High; contact details or time promises on the 503 page → Low; default Bolt error pages in production → Medium.

## 16. bolt-cookie-consent
- **Script:** the `theme.yaml` `privacy:` data model, banner wiring and compliance, wording, hard-coded trackers, footer, privacy page and route, translations, live HTML.
- **Review:** projects built before this skill usually have no `privacy:` block, so most script failures are a **deviation** (another banner implementation). Judge the existing banner and policy against `skills/bolt-cookie-consent/references/guidelines.cs.md` directly — that is where the **defects** are:
  - CB-01: tracker (GA, Sklik, Meta, Hotjar, embeds, Google Fonts) loaded before a choice — read the master layout and the profile's "Tracking found" line; with `--base-url`, fetch the homepage HTML.
  - CB-10–CB-12 / DP-01–DP-02: Reject in layer 1, a button, same styling as Accept.
  - CB-20 / DP-03: no pre-ticked categories; CB-30: settings link in the footer; CB-05: no "používáním webu souhlasíte".
  - Privacy page: the 11 mandatory blocks (guidelines, *Povinný obsah*), controller identity (§ 435 OZ), a cookie list matching what the site sets.
  - CB-02: YouTube / map iframes without a placeholder.
- **Severity hints:** tracking before consent, Reject missing from layer 1, no privacy page, cookies not described → Critical (ÚOOÚ fines exactly these); unequal buttons, missing footer link, English-only descriptions → High; not using the skill's data model → Medium (one deviation; migration = scaffold with the intake).

## 17. bolt-legal-cz
- **Script:** the `theme.yaml` `contact:` identity and `legal:` profile (IČO check digit, register entry by operator type, ADR body, online-contract pages, privacy controller = `contact:`), the identity partial in the footer, typed-in IČOs and EU ODR links in templates, the reviews notice, translations, and the live pages through `check-site.php`.
- **Review:** projects built before this skill have no `legal:` block — a **deviation**. The **defects** are on the rendered site, so run `php $SKILLS/bolt-legal-cz/scripts/check-site.php --url=<base-url> --ares` (it needs no `legal:` block; add `--consumers` when the operator sells to consumers) and judge against `skills/bolt-legal-cz/references/requirements.cs.md`:
  - ID-01–ID-04: name, registered seat, IČO and the Trade / Commercial Register entry on the site, matching ARES (ID-06); an IČO of someone else (template leftover, ID-09).
  - SP-01: ADR body with its web address on consumer sites; SP-02: links to the closed EU ODR platform (often in the terms page in the database); SP-06: testimonials without a verification statement.
  - EC (online shops): terms, withdrawal information, the „Odstoupit od smlouvy“ button from 1. 1. 2027.
  - Ask the operator what the script cannot know: consumers or B2B, employees (whistleblowing, accessibility), regulated profession — or list it under *Not checked*.
- **Severity hints:** IČO, name, seat or register entry missing or wrong; no ADR information on a consumer site; no withdrawal button on an online shop from 1. 1. 2027 → High (fines up to CZK 1 M / 5 M); EU ODR link, reviews without a statement, identity only on the contact page → Medium; not using the skill's data model → Low (one deviation).

## 18. bolt-add-language *(multilingual only — once per secondary locale)*
- **Script:** locale in `services.yaml`, ContentType `locales`, catalog existence and unit parity, XLIFF lint, `menu.yaml` labels, locale switcher.
- **Review:** in the browser (with `--base-url`), a few `/<code>/…` pages show translated text, not keys or Czech fallbacks (Appendix B.4); `hreflang` alternates in the SEO tags; the switcher keeps the current page instead of jumping home.
- **Severity hints:** untranslated keys visible → High; missing `hreflang` → Medium; parity gaps in rarely used units → Low.

---

## Beyond the skills

Note these too, as *Info* or higher, when you see them during the review — they are outside any
single skill but belong in an audit of a Bolt 6 site: `npm audit --omit=dev` advisories in the
theme, private keys or credentials committed anywhere in git history, backups of `var/data` /
database dumps lying around on the server, Lighthouse (mobile) scores below 90, missing
`robots.txt` / canonical URLs. (`APP_ENV` / `APP_DEBUG`, `composer audit` and committed `.env`
secrets are checked by `bolt-security-hardening`.)
