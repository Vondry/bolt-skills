# Changelog

All notable changes to `tomvondracek/bolt-skills`. Versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

The sites move to PHP 8.4: they require `"php": "^8.4"`, and the CI template tests 8.4 and 8.5. Bolt 6 itself still runs on 8.2, and so does this plugin.

### Changed
- `bolt-code-quality` `examples/gitlab-ci.yml` and Step 5: PHPStan on 8.4 and 8.5. ECS and the single jobs (Twig, XLIFF, YAML, `composer audit`) run on 8.4. ECS results depend on the PHP version (`MbStrFunctionsFixer` asks for `mb_trim()` only on 8.4+), so its comment no longer says they don't. Step 5 says the matrix starts at the project's required PHP. The description and the pipeline summary now say 8.4–8.5.
- `bolt-runtime-extensions` examples use `mb_trim()` and `mb_rtrim()` where they used `trim()`, `rtrim()` and `ltrim()` (`LocaleLinkExtension`, `FileSizeExtension`), so ECS passes on 8.4. On 8.2 and 8.3 the functions come from `symfony/polyfill-php84`, which `bolt/core` requires.
- `bolt-build` `preflight.sh` warns below PHP 8.4. It still blocks below 8.2.
- WORKFLOWS Phase 1 prerequisites: the project boots on PHP 8.4 with `"php": "^8.4"`. `bolt-security-hardening` asks for PHP 8.4+ in the host's panel.

### Added
- Pitfall 5 in `bolt-code-quality`: switching a project to a new PHP version. Change every pin together, run `composer update` on the new PHP, then `make csfix`. Keep `symfony.lock`: without it Flex re-runs every recipe and adds skeleton files. Production must run the new PHP before the deploy.

### Migrating a project
- Run Pitfall 5 of `bolt-code-quality`: set `"php": "^8.4"`, drop a direct `symfony/polyfill-php84` requirement, set `ARG PHP_VERSION=8.4` in the `Dockerfile`, take the CI versions from `examples/gitlab-ci.yml`, run `composer update` on 8.4, then `make csfix` and `make stancheck`.

## 1.11.0 — 2026-10-30

`bolt-code-quality` sets PHPStan to `level: max` instead of `level: 8`. Max adds one thing to level 8: no unchecked `mixed`, so values PHPStan can't type (Bolt config, `Content::getFieldValue()`, decoded JSON, Doctrine query results) are narrowed before use.

### Changed
- `examples/phpstan.dist.neon` and Step 3 of the skill: `level: max`.
- `verify.sh` passes on `level: max`. `level: 8` is a warning that asks to raise it, so existing projects keep passing; any other level fails.
- The `(level max on src/)` comment in `examples/gitlab-ci.yml` and the skill's CI block, the skill's description, README, AGENTS and WORKFLOWS 8.1.

### Added
- Pitfall 4 in the skill: the usual level-max errors and how to fix them (type checks with a default for config, field values and JSON; a typed `@var` on Doctrine results; check before casting `mixed`; no baseline or `@phpstan-ignore`).

### Migrating a project
- Set `level: max` in `phpstan.dist.neon` and run `make stancheck`. Fix what it reports as in Pitfall 4, then update the comment in `.gitlab-ci.yml`.

## 1.10.0 — 2026-10-27

`bolt-extension-setup` installs [`tomvondracek/bolt-sitemap`](https://packagist.org/packages/tomvondracek/bolt-sitemap) instead of `bolt/sitemap-extension`. The theme override is no longer needed, and the theme's static pages get into the sitemap through their routes.

### Changed
- `bolt-extension-setup` section 2: `composer require tomvondracek/bolt-sitemap:^1.0` and `examples/tomvondracek-sitemap.yaml`. The extension serves `/sitemap.xml` as a sitemap index:
  - one `<url>` per page and locale with `hreflang` alternates;
  - slugless singletons;
  - listing pages;
  - images and an honest `<lastmod>`;
  - no pages that bolt-seo marks `noindex`.

  `examples/sitemap.xml.twig` and `examples/bolt-sitemapextension.yaml` are removed.
- Section 2.4: static pages (`static-pages/*.twig`) are listed through their `TemplateController` routes. Each needs a route without parameters and, on multilingual sites, its `<name>_locale` twin with the same `templateName`. Pages not to index go into `exclude_static_routes`. WORKFLOWS Static Routes and 5.3 say the same.
- `verify.sh`:
  - checks `tomvondracek/bolt-sitemap`, its config and its recipes;
  - fails while `bolt/sitemap-extension` is installed, or a static `public/sitemap.xml` shadows the extension;
  - warns about the old override and config;
  - checks every static page: no route → failure, no `_locale` twin on a multilingual site → warning, `static_routes: false` → warning (new `scripts/static-pages.php`).
- WORKFLOWS 3.1, 6.2, 7.3 and Appendix B.6, the `bolt-audit` checklist and example map, and the `bolt-theme-init` folder tree follow the new extension.

### Fixed
- The scripts that read `/sitemap.xml` follow a sitemap index to its child sitemaps, read from the checked host:
  - `bolt-legal-cz/check-site.php`;
  - `bolt-theme-templates/check-search.php`;
  - `bolt-asset-caching/check-delivery.php`;
  - `bolt-audit`'s HTTP smoke test.

  Before, they took the child sitemaps for pages. The smoke test no longer adds a locale prefix to URLs that already have one (`/de/en/…`).

### Migrating a project
- `bolt-extension-setup` section 2.6:
  1. `composer remove bolt/sitemap-extension`, then `composer require tomvondracek/bolt-sitemap:^1.0` and `php bin/console extensions:configure --with-config`.
  2. Delete `extensions/sitemap.xml.twig` (or `_sitemap.xml.twig`) and `config/extensions/bolt-sitemapextension.yaml`.
  3. Run `verify.sh`, which lists static pages without a route or `_locale` twin.
  4. Check that the other extensions' `config/packages/extension_*.yaml` are still there.

## 1.9.1 — 2026-10-26

### Changed
- `bolt-extension-setup` sitemap template (`examples/sitemap.xml.twig`, section 2.5): no `<?xml-stylesheet … sitemap.xsl?>` line. Browsers are removing XSLT, and Chrome already shows a warning bar on a sitemap that uses it. Without the line, `/sitemap.xml` shows as plain XML; search engines never used the stylesheet.

### Migrating a project
- Delete the `<?xml-stylesheet type="text/xsl" …?>` line (line 2) from the theme's `extensions/sitemap.xml.twig` (or `_sitemap.xml.twig`). `templates.xsl` in `bolt-sitemapextension.yaml` can stay; it only serves `/sitemap.xsl`.

## 1.9.0 — 2026-10-26

The canonical URL override every Bolt 6 project needs until bolt/core PR #3735 is released, and bolt-seo 2.3. Both found while updating five sites to bolt-seo 2.3.0 and bolt/core 6.1.10.

### Added
- `bolt-extension-setup` section 1.6 and `examples/_canonical.macros.twig`, `_canonical.twig`, `_seo_metatags.twig`. Up to bolt/core 6.1.10, Bolt's canonical names a singleton by its record route (`/kontakt/kontakt-2` instead of `/kontakt`) and keeps the listing query (`/clanky?order=-createdAt&status=published`). bolt-seo 2.3 builds `og:url` and `twitter:url` from that canonical. The macro corrects the canonical the way [bolt/core#3735](https://github.com/bolt/core/pull/3735) does. `<link rel="canonical">` (Bolt's `canonical_template`) and bolt-seo's meta tags (`templates.meta`, the stock template with `canonical` replaced) both print it, so the three tags always name the same URL. The section says when and how to remove it: once the project runs a bolt/core release with #3735.
- `verify.sh` step 7 (now 7 steps): fails without the three partials, `canonical_template` or `templates.meta`, and warns when a copy differs from the example or a template passes `canonical: app.request.uri`. Step 2 warns about the dead `meta_robots` / `allow` keys.
- WORKFLOWS 6.2 copies the partials, Appendix B.10 tracks the workaround, and the `bolt-audit` checklist reviews it.

### Changed
- `appolodev/bolt-seo:^2.3` (SKILL.md 1.1, WORKFLOWS 3.1). The example config and section 1.3 set the robots default with `default.robots`. The top-level `meta_robots` they used was never read, and bolt-seo 2.3 removed it, along with the commented-out `allow` block, from its own config.
- Section 1.5: pages that include `@seo/_metatags.html.twig` themselves pass `canonical: seo.canonical()`. `app.request.uri` carries the query string (`?utm_source=…`), which `<link rel="canonical">` drops.

### Migrating a project
- `composer update` and `composer bump` for `appolodev/bolt-seo` ^2.3. Delete `meta_robots` and the `allow` block from `config/extensions/appolo-boltseo.yaml`, and set `default.robots: "index, follow"`. That is also the built-in fallback, so the output doesn't change.
- Copy the three partials to `partials/` (they replace an own `_canonical.twig`), and set `canonical_template: 'partials/_canonical.twig'` and bolt-seo's `templates.meta: partials/_seo_metatags.twig`. Run `bin/console cache:pool:clear cache.app`, then compare `<link rel="canonical">` with `og:url` on a singleton page, its translation and a listing.
- Replace `canonical: app.request.uri` with `canonical: seo.canonical()` in templates that include the meta tags themselves.

## 1.8.3 — 2026-10-24

False positives in the `bolt-theme-templates` class checks, found by installing 1.8.2 in akvelmez and eurodeck.

### Fixed
- `verify.sh` step 7 cut class names at the first digit or bracket: `text-h2` and `text-h2-sm` were reported as an undefined `text-h`, `border-b-(length:--hairline)` as `border-b`. The name is now read whole, and classes with an arbitrary value (`-(…)`, `-[…]`) are skipped — they name no token.
- `canonical-classes.mjs` (step 8) no longer reports a spacing-scale step as shortenable to a named token of the same value (`size-18` → `size-header`, `w-18` → `w-header` with `--spacing-header: 4.5rem`). Same value, other meaning; `--fix` would have tied a button's size to the header height. Arbitrary values are still rewritten to tokens.

## 1.8.2 — 2026-10-24

### Fixed
- `bolt-runtime-extensions` `scaffold.sh` no longer appends an `App\LocaleLinkExtension` definition to `config/services.yaml`. The class gets its arguments from `#[Autowire]` attributes, so the definition only duplicated them; projects that were scaffolded earlier and then had the class replaced by an audit carried both.
- `verify.sh` step 4 warns when the class has the attributes and `services.yaml` still defines the service. SKILL.md (description, sections 3 and 5, pitfall table) and WORKFLOWS 3.2 no longer describe the definition as required.

### Migrating a project
- If `src/LocaleLinkExtension.php` has `#[Autowire('%app_locales%')]`, delete the `App\LocaleLinkExtension:` block (its `arguments` and `twig.extension` tag) from `config/services.yaml`. `bin/console lint:container` must still pass.

## 1.8.1 — 2026-10-23

Fixes found by rolling the 1.8.0 search page out to existing sites with their own design systems.

### Fixed
- `bolt-theme-templates` search example: the term was escaped twice. `term|e` went into `__()` results that `section-header` (`typo()` escapes) and `empty-state` escape again, so a term like `<b>x</b>` showed as `&lt;b&gt;…` and `&` as `&amp;amp;`. The term is now escaped once, where it is printed: `|e` only for `{{ __() }}` printed directly (the `<title>`), the plain term for components that escape. Section 3 M and the pitfall describe the rule, including components that print a parameter with `|raw` (those need `|e` again).
- `verify.sh` step 10 checks only direct prints for an unescaped term: `{{ __(…) }}`, not `{{ include(…, { title: __(…) }) }}`, whose result the component escapes. The live check still catches a term reflected as markup on any path.
- `verify.sh` step 10 read the locales from the end of the line, so `app_locales: cs|en # app_locales: en|nl|…` tested the 18 locales in the comment. Comments after the value are stripped first.
- Search results: long words without spaces (URLs, a JSON string) overflowed the result on phones. The excerpt wraps them (`wrap-break-word`).

### Migrating a project
- If you copied the 1.8.0 search page, drop `|e` from the `'%term%'` parameters passed to `section-header` and `empty-state` (keep it in the `<title>`).
- **Twig cache warm-up and `node_modules`:** Symfony's warm-up compiles every file in the theme folder, `node_modules` included (`typescript.js` alone is 18 MB). On themes close to PHP's 128 MB limit, a few new templates make `bin/console cache:clear` run out of memory in development. `file_name_pattern: '*.twig'` under `twig:` in `config/packages/twig.yaml` limits it to templates. Production is not affected because `node_modules` is never uploaded.

## 1.8.0 — 2026-10-23

A search page on every site. Bolt serves `/search` and `/{_locale}/search` whether the design shows a search box or not, and on sites without a fitting template it answered 500 or rendered the listing template.

### Added
- `bolt-theme-templates`: the search results page — `pages/search/search.twig` with the page-scoped `search-form.twig` and `search-result.twig`, built from the Integration Contract tokens, plus the root entrypoint `search.twig` that Bolt's default `search_results_template: search.twig` renders. `scaffold.sh` always installs them. The page has its own `<title>` and `noindex, follow`, highlights the term in the excerpts, counts results with Czech and English plural rules, and shows an empty state.
- `bolt-theme-templates` `verify.sh` step 10 checks the search page on every run:
  - The template Bolt will render exists, no form posts to `path('search')`, and the term is escaped before `__()`.
  - Live (`scripts/check-search.php`): `/search` answers 200 with a search form; a real term returns results with HTTP 200; a term without matches answers 200; markup in the term is not reflected; on every secondary locale, `/<locale>/search` answers 200, its form submits to `/<locale>/search` and the results link to `/<locale>/` pages.
  - The term is the longest word of a page's `<h1>` from `sitemap.xml`, and the results must link to that page more often than a page without matches does, so menu links don't count. `BOLT_SEARCH_TERM` overrides the guess.
  - The live part runs against `BOLT_BASE_URL`, or against PHP's built-in server that the step starts itself (`scripts/php-server-router.php`). It fails when no site can be reached.
- `WORKFLOWS.md`: the search page in 6.1, Gate 6 and the Definition of Done.

### Fixed
- Search forms copied from older themes posted to `path('search')`, which is always the default locale: on `/en/search`, pressing Search showed the Czech results. The example submits to the current route, and step 10 fails on `action="{{ path('search') }}"`.
- The term went into `__()` unescaped. Bolt's HTML cleaner keeps its allowed tags (`<b>`, `<img>`, `<a>` …) and `__()` prints unescaped, so markup from the URL appeared in the results heading. The example writes `term|e`; step 10 fails on an unescaped parameter and checks the live page.

### Migrating a project
- Run `scaffold.sh` (existing files are kept) and merge `examples/translations.<locale>.xlf` (the new `search.*` units). If `config/bolt/config.yaml` names a `search_results_template` that does not exist, set it to `search.twig`.
- A theme with its own search page keeps it. Fix what step 10 reports: submit the form to the current route, `path(app.request.attributes.get('_route'), app.request.attributes.get('_route_params'))`, and pass the term to `__()` as `searchTerm|e`.
- Step 10 needs a reachable site: the project's database for the built-in server, or `BOLT_BASE_URL`.

## 1.7.1 — 2026-10-23

Fixes found by comparing a site's pages before and after its audit fixes, screenshot by screenshot.

### Fixed
- `bolt-theme-templates` `verify.sh` step 7: the class check looked only at colour and token utilities (`bg-*`, `text-*` …). The Integration Contract utilities the skills' shared partials use (`py-section`, `btn-primary`, `card` …) went unchecked, so in a theme that never defined them the privacy page had no section padding and its „Nastavení cookies“ button looked like plain text. The step now warns about every contract utility used in a `class="…"` or a `{% set … = '…' %}` class variable that the build does not contain.
- `bolt-cookie-consent` `gdpr.twig`: the page had no `{% block seo %}`, so `seo.title()` gave only the site name in the browser tab. It sets „Ochrana osobních údajů | <site name>“ (or the English title) and keeps the hreflang alternates.
- `bolt-cookie-consent` `gdpr.twig` and catalogs: the Consent Mode paragraph always named „Google Analytics, Google Ads“. It names only the tools the site loads (`analytics.ga4_id`, `analytics.google_ads_id`), through a new `%tools%` parameter.
- `bolt-cookie-consent` `_cookie-banner.twig`: the layer-1 heading had no colour of its own, so a theme whose base styles colour `h2` with the ink colour showed it dark on the dark bar, invisible. It uses `text-night-ink`.
- `bolt-cookie-consent` `_cookie-table.twig`: cookie names broke mid-word (`break-all`, „bolt-cookie-c / onsent“). They stay on one line; the table scrolls sideways on narrow screens as before.

### Migrating a project
- Copy `gdpr.twig`, `_cookie-table.twig` and the heading class of `_cookie-banner.twig` from the examples (keep your own design hooks).
- `merge-xliff.php` never overwrites existing units: in `translations/messages.cs.xlf` and `messages.en.xlf`, replace „(Google Analytics, Google Ads)“ with „(%tools%)“ in `privacy.cookies.consent_mode_basic` and `privacy.cookies.consent_mode_advanced`.
- If `bolt-theme-templates` now warns about `py-section` or `btn-primary`, define them in `css/tailwind/index.css` in the theme's own style (see `bolt-tailwind-theme`).

## 1.7.0 — 2026-10-23

Fixes found by auditing a site with `bolt-audit` and fixing the findings.

### Added
- `bolt-cookie-consent`: a private person who runs no business can be the controller. With `business: false`, `check-privacy.php` requires only `name` and `privacy_email`; `address`, `ico` and `registry` may be `~`, and `gdpr.twig` leaves those rows out. The intake (question 5) says to ask before publishing a home address.

### Fixed
- `bolt-cookie-consent` `scaffold.sh`: `privacy-config.php` failed on a `config/services.yaml` with Symfony tags (`!tagged_iterator`, `!service` …). It now parses them as custom tags.
- `bolt-cookie-consent` examples: `_cookie-table.twig` and `gdpr.twig` used arbitrary `min-w-[…rem]` widths, which `canonical-classes.mjs --fix` rewrites in every project. They use the canonical `min-w-xl`, `min-w-176` and `min-w-160` now.
- `bolt-legal-cz` `check-site.php`: GDPR-01 counted a link to another site's policy (a cookie banner's `policies.google.com/privacy`) as the operator's privacy policy. Only links on the site's own host count.
- `bolt-htaccess` and `bolt-asset-caching`: the `mod_expires` block had no rule for `favicon.ico`, so it was served without `Cache-Control` (the delivery check's „no max-age“ warning). It gets one week for `image/vnd.microsoft.icon` and `image/x-icon`, which is shorter than the other images because favicons keep a fixed URL.

### Migrating a project
- Add the two `ExpiresByType … icon` lines to `public/.htaccess` (see `bolt-htaccess/examples/public.htaccess`).
- Projects that copied `gdpr.twig` or `_cookie-table.twig` need no change; `canonical-classes.mjs --fix` already rewrote the widths.

## 1.6.3 — 2026-10-22

Fixes to the audit tooling, found by auditing a site behind a CDN with `bolt-audit`.

### Fixed
- `bolt-audit`: `audit.sh --base-url` never ran the asset delivery check. `verify.sh` reads only `BOLT_DELIVERY_URL`, which the audit did not set. The audit now sets it from the new `--delivery-url=`, or from `--base-url` when the `Server` header names Apache, Nginx or LiteSpeed (`symfony serve` and PHP's built-in server keep it off), and `profile.md` has an *Asset delivery check* row.
- `bolt-audit` and `verify-all.sh`: a pass line containing a warning word rated the skill `WARN` — `bolt-contenttypes` on „✓ no warning or danger notice“, `bolt-legal-cz` on „withdrawal notice“ in its manual checklist. Pass lines (`✓ …`, `PASSED: …`, `OK: …`) and zero counts („0 advisory warnings“) are ignored; `audit.sh` counts „Notice:“ lines, not every „notice“.
- `bolt-cookie-consent`, `bolt-legal-cz`, `bolt-disable-api`, `bolt-htaccess` `verify.sh`: the reachability probe gave the site 2 s, so a production site on a cold cache reported „not reachable“ and its live checks were skipped. The probe now waits 10 s; a closed port still fails at once.
- `bolt-htaccess` and `bolt-disable-api` `verify.sh`: their live `/index.php/…` probes caused the bug they look for. On a site without the Pitfall 10 rules, the request puts the hosting path into Bolt's cached canonical links and `llms.txt` for the cache lifetime (seen during an audit). The probes now run only when the project's `public/.htaccess` has the rules, and say why they were skipped. If the local file has the rules but the server's copy does not, the htaccess check says to upload it.
- `bolt-asset-caching` `check-delivery.php`: names the crawled pages that did not answer 200 (status or „no response“). Before, it only counted them, so a timeout or a 5xx hid part of the site without saying which part.
- `bolt-asset-caching` `verify.sh`: the live header check looked only for the project's `symfony serve` and skipped on staging / production. It now uses `BOLT_BASE_URL` when it answers, and reports a sample image the site does not have (HTTP 404) instead of „no cache-control“.

### Migrating a project
- Nothing changes in projects; the fixes are in the audit and verification scripts.
- **Before checking a live site after adding the Pitfall 10 rules:** upload `public/.htaccess` first. The checks now request `/index.php/…` whenever the local file has the rules, and on a server without them that request poisons Bolt's cached links for the `caching: canonical` lifetime.
- **Audits:** when `--base-url` is `symfony serve`, pass `--delivery-url=` with a staging or production URL to include the delivery check.

## 1.6.2 — 2026-10-22

Fixes found by auditing a site with `bolt-audit` and fixing the findings. They were checked on a local Apache with the project's `.htaccess` and in Bolt 6.1.9's own Twig environment.

### Fixed
- `bolt-htaccess`: `/index.php/<page>` answered 200 with the homepage. Symfony then took the hosting path as its base URL, and Bolt cached it into the canonical links, `/sitemap.xml` and `/llms.txt` (`https://example.cz/domains/example.cz/public/index.php/…`). Any visitor could trigger this. `examples/public.htaccess` now redirects `/…/index.php/page` to `/…/page` and `/domains/<host>[/public]/page` to `/page`, and answers 404 to any other path naming `index.php`. All three rules match `%{THE_REQUEST}`, so internal rewrites never trigger them. New Pitfall 10. `verify.sh` section 2 fails without the rules; section 6 expects `/index.php/bolt-htaccess-probe?x=1` → 301. Pitfall 9 no longer claims a site on the same host sits directly in `www/`.
- `bolt-legal-cz`: with `dic: ~` (the scaffold default) or any other `~` value, `_legal-identity.twig` made every page answer 500 (`Method Bolt\Collection\DeepCollection::dic does not exist`). The partial now converts `contact:` and `legal:` with `toArray()`, and `verify.sh` step 3 fails on a copy without it.
- `bolt-legal-cz`: ARES reports every public register as one source (VR). `check-site.php` and `check-legal.php` therefore treated a spolek, nadace, ústav, o.p.s. or SVJ as a Commercial Register company and asked for „Zapsáno v obchodním rejstříku“. The register is now derived from the section of the spisová značka (L = spolkový rejstřík, …), such operators are `other`, and the scripts print the sentence to use and compare `registry.text` with ARES. The scaffold's placeholder for `other` is an association example, not an attorney's.
- `bolt-cookie-consent`: in Bolt, `theme.yaml` blocks are collections. `|column('category')` found no consent categories in them, so `_consent-mode.twig` and `_cookie-banner.twig` rendered nothing. `gdpr.twig` threw on `summary: ~`. Every template now converts `privacy:` / `analytics:` with `toArray()`, and `verify.sh` step 3 fails on a copy without it.
- `bolt-menu` `verify.sh`: a backtick in the embedded PHP ran as a shell command (`locales:: command not found`).
- `bolt-disable-api` `verify.sh`: `/index.php/api/contents` may answer a redirect to `/api/contents`. A 200 with HTML (the homepage) is reported as the `bolt-htaccess` Pitfall 10 problem, not as an exposed API.

### Added
- `bolt-add-language`: `examples/_hreflang.twig`, `<link rel="alternate" hreflang>` for every locale plus `x-default`. Neither Bolt nor bolt-seo prints these. The `bolt-theme-init` master layout (and the `WORKFLOWS.md` skeleton) includes it in the `seo` block, so the 404 / 403 pages carry none. `verify.sh` section 7 checks the include and the locale list.
- `bolt-extension-setup` § 2.6: `robots.txt` names the sitemap. `verify.sh` warns without the line.
- `bolt-runtime-extensions` `verify.sh`: calls `locale_link()` and fails when `javascript:` / `data:` URLs pass or the query string and hash are lost.
- `bolt-helper-pages` `verify.sh`: catches contact details on the 503 page that come from the catalog units it uses or from `theme/contact/…`.
- `bolt-menu` `verify.sh`: warns when `js/src/menu.ts` has no Escape handling.
- `bolt-code-quality` `verify.sh`: warns on the deprecated `BracesFixer` / `NewWithBracesFixer` in `ecs.php`.
- `bolt-audit`: example-map row for `_hreflang.twig`; checklist points for the hosting path in canonical / sitemap / llms.txt, the 503 catalog texts and hreflang.
- `WORKFLOWS.md` Integration Contract: read whole `theme.yaml` blocks through `toArray()`.

### Migrating a project
- **`bolt-legal-cz` / `bolt-cookie-consent` in use:** copy the current `_legal-identity.twig`, `_consent-mode.twig`, `_cookie-banner.twig`, `_privacy-form-note.twig` and `gdpr.twig` from the skills' `examples/`. A copy without `toArray()` now fails `verify.sh`.
- **Apache sites:** add the three `%{THE_REQUEST}` rules from `examples/public.htaccess` right after `RewriteEngine On` in `public/.htaccess`, upload it, and purge `/llms.txt` in any CDN.
- **Multilingual sites:** copy `examples/_hreflang.twig` to `partials/`, set its `locales` list, and include it after `{{ seo.metatags() }}` in the master layout's `seo` block.

## 1.6.1 — 2026-10-22

The www and HTTPS redirects work on hosts that serve the domain from a webroot subfolder. On a host serving from `www/domains/example.cz/` (WEDOS), `https://www.example.cz/` redirected to `https://example.cz/domains/example.cz/` (404), and plain-HTTP links did the same.

### Fixed
- `bolt-htaccess` `examples/root.htaccess` and Step 1, including the variant for a document root on `public/`: the redirect targets use `/$1` instead of `%{REQUEST_URI}`. The host forwards the request into the subfolder with an internal rewrite, so `REQUEST_URI` carried the prefix. `$1` is relative to the `.htaccess` folder on every layout. New Pitfall 9.
- `verify.sh` section 1 fails on `%{REQUEST_URI}` in a redirect target of the root or `public/` `.htaccess`.
- With `BOLT_BASE_URL` set to a production `https://` address, `verify.sh` section 6 checks that `https://www.<host>/…?x=1` and `http://<host>/…?x=1` answer one `301` to `https://<host>/…?x=1`.

### Migrating a project
Replace the two redirect rules of the root `.htaccess` with the ones in `examples/root.htaccess` and upload it. Browsers cache the broken 301, so test in a private window.

## 1.6.0 — 2026-10-22

`.env` holds everything production needs, including the secret; `.env.local` is local development only. On an SFTP deployment the upload answered 500 until `.env.local` was uploaded too, and that file then ran production with debug on.

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

Compressed pages and a maintenance page that never touches the database. Both come from a site audit: 204 KB of uncompressed HTML, CSS and JS per page, and a 503 page that loaded its phone and e-mail from a settings record.

### Added
- `bolt-htaccess` Step 7: a `mod_deflate` block in `examples/public.htaccess` that compresses the text responses. That covers pages rendered by Symfony and the CSS, JS, SVG, XML and JSON files Apache serves; images, WOFF2 fonts and PDFs stay out. Brotli is left to the host, and the step includes an Nginx line. `verify.sh` gets a static check (section 6, now 7 sections) and a live `Content-Encoding` probe of the homepage and `css/index.css`.

### Changed
- `bolt-helper-pages` § 5: the zero-database rule now covers the 503 page, the standalone layout and the scene, as well as the 500 page. Maintenance mode is on while the database is migrated or restored, so `setcontent`, `menu_array()` and settings records are out.
- `bolt-helper-pages`: the 503 page shows no phone numbers, e-mail addresses, status code, times or durations, and does not call the outage planned. It can be on without anyone noticing, so it only says that the site is being worked on and offers *Zkusit znovu*. The examples and the § 7 template were updated, and `_helper_scene.twig` renders the `code` watermark only when one is passed.
- `bolt-helper-pages/scripts/verify.sh`: fails on `setcontent` / `menu_array()` in the 500 and 503 pages, the layout and the scene, and when the 503 page does not extend the standalone layout. It warns on `tel:` / `mailto:` on the 503 page. A `maintenance` entry with `/` (or a missing root entrypoint) now fails instead of warning. Section counters fixed (`[1/5]`…`[5/5]`).
- `bolt-audit` checklist (bolt-htaccess, bolt-helper-pages) and `WORKFLOWS.md` 2.1 / 6.4 follow both changes.

## 1.4.1 — 2026-10-22

Admin icons that render: ContentType icons only from the Font Awesome version Bolt bundles: FA 6 names show empty boxes in the sidebar.

### Added
- `bolt-contenttypes` rule 11: `icon_one` / `icon_many` must be Font Awesome Free **solid** icons of the version in `bolt/assets` (5.15.4 in Bolt 6.1). Bolt prints `fas fa-<name>`, so FA 6 / 7 names (`sliders`, `screwdriver-wrench`, `house`, `gear`, …), brand icons and style prefixes render as empty boxes. The rule includes a table of where each option renders.
- `bolt-contenttypes/references/fontawesome-5.15.4-solid.tsv`: the 1,002 solid icons, each with its FA 6 / 7 names and search terms, generated from Font Awesome's `metadata/icons.yml`.
- `bolt-contenttypes/scripts/admin-icons.php`: `check` (in `verify.sh`, now 4 sections) reads the version and icon classes from Bolt's admin CSS, fails on unknown, newer-version, brand and malformed icons, names the 5.15.4 replacement, and warns on ContentTypes without icons. `list <word>` finds renderable icons by name, newer name or meaning. `generate` builds the list for another Font Awesome version.
- `bolt-contenttypes/scripts/admin-icons-browser.js`: render check in the logged-in admin. It loads the dashboard and every listing, edit and new page, and reports every icon without a CSS rule. That covers the server-rendered headings and the JSON the Vue sidebar, toolbar and dashboard listing render from. It is part of `WORKFLOWS.md` 7.1 and the `bolt-build` Phase 7 row, and Checkpoint 5's gate names rule 11.

### Fixed
- `bolt-theme-init/examples/contenttypes_snippet.yaml`: `fa:boxes-stacked` (FA 6) → `fa:boxes`.

## 1.4.0 — 2026-10-22

Every photo gallery opens in the PhotoSwipe lightbox, and template classes use their canonical token form — both from building a site with the skills.

### Added
- `bolt-theme-templates/scripts/canonical-classes.mjs`: reports every template class that has a shorter canonical form — the IDE's "The class `rounded-[var(--radius-card)]` can be written as `rounded-card`" hint — using the theme's own design system (`tailwindcss canonicalize`, Tailwind CSS v4.3+). Unlike the IDE inspection it also sees classes inside Twig strings and interpolated attributes; `--fix` rewrites the templates. `verify.sh` runs it as step 8 (now 9 steps) and fails until the templates are canonical.
- Rules for canonical classes and tokens over arbitrary values (`bolt-theme-templates` section 5, `bolt-tailwind-theme` section 3, `WORKFLOWS.md` 6.1): IDE diagnostics while editing, the script before the gate; a value match is not a meaning match; a value repeated with the same meaning becomes a role-named token (`--tracking-label`, `--spacing-page`, `--text-page`, `--breakpoint-3xs`).
- `bolt-theme-init` `photoswipe.ts`: localised UI — the button titles and error message come from the first gallery's `data-pswp-close-title`, `-zoom-title`, `-arrow-prev-title`, `-arrow-next-title`, `-error-msg` (new `gallery.*` units in the `bolt-theme-templates` catalogs); up to 12 slides kept decoded.
- `bolt-tailwind-theme` 5.H: `.pswp__custom-caption` styles (the module registered the caption element, but no skill styled it).
- `bolt-theme-init/scripts/verify.sh`: fails when templates use `.photoswipe-gallery` without the `./photoswipe` import, the `photoswipe` npm dependency or the CSS `@import`.

### Changed
- Any photo gallery gets the PhotoSwipe lightbox, also when the design does not show one (a static design has no click state) — `WORKFLOWS.md` decision matrix and 6.1, `bolt-build` intake S6, `bolt-theme-init`, `bolt-theme-templates`.

## 1.3.0 — 2026-10-22

ContentType safety (reserved field names, explicit slugs, English configuration) with a config-notices gate before content, and fixes from a site audit.

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
