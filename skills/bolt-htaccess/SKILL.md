---
name: bolt-htaccess
description: >-
  Use this skill whenever creating, configuring, or hardening Apache .htaccess
  files in a Bolt CMS repository. Implements the production two-tier .htaccess
  architecture: root-level HTTPS redirection and ./public directory forwarding
  for web hosts, plus public/.htaccess protection — an allowlist for theme/,
  files/ and thumbs/ (only built assets and accepted upload types are served,
  everything else is 403), a safety-net deny list for sources, configs, dumps
  and .env files elsewhere in public/, and security headers for static files
  (HSTS, nosniff, sandboxed uploads).
---

# Bolt CMS Apache `.htaccess` Configuration & Source Code Hardening

In Bolt CMS deployments running on Apache (such as shared hosting, VPS setups, or traditional virtual hosts), proper `.htaccess` configuration is critical for both routing and security.

This skill documents the production-tested two-tier `.htaccess` architecture established across active Bolt CMS installations:
1. **Root `/.htaccess`**: Enforces HTTPS and transparently routes all requests into the `./public/` document root.
2. **Public `/public/.htaccess`**: Hardens Symfony's front controller rewrite rules, enforces UTF-8 character encoding, serves only known static files from the theme, upload and thumbnail folders (allowlist), denies sources, configuration, dumps and `.env*` files everywhere else, and sends security headers with the files Apache serves itself.

Pages rendered by Symfony get their security headers from `nelmio_security`; that configuration, secrets and the rest of the application hardening are in [`bolt-security-hardening`](../bolt-security-hardening/SKILL.md).

---

## Architecture Overview

```text
Project Root (/)
├── .htaccess                       # Tier 1: HTTPS redirect & rewrite traffic into public/
├── .env, composer.json, src/, ...  # Protected behind project root (never exposed)
└── public/                         # Web Document Root
    ├── .htaccess                   # Tier 2: front controller, allowlist, deny list, headers
    ├── index.php                   # Front controller entrypoint
    ├── assets/                     # Bolt admin assets (deny list applies)
    ├── files/                      # Uploads — allowlist: accepted upload types only, sandboxed
    ├── thumbs/                     # Thumbnails — allowlist: same types; missing ones go to Bolt
    └── theme/<theme_name>/         # Theme — allowlist: only css/, js/, img/, images/, fonts/
        ├── css/index.css           # ✅ served
        ├── js/app.js               # ✅ served
        ├── img/logo.svg            # ✅ served
        ├── js/src/app.ts           # 🛑 403 (not a static file type)
        ├── theme.yaml              # 🛑 403 (outside the public folders)
        ├── index.twig              # 🛑 403
        ├── package.json            # 🛑 403
        ├── rollup.config.js        # 🛑 403
        └── node_modules/           # 🛑 403
```

---

## The Core Problems Solved

### Problem 1: Unpointed DocumentRoot (Root Directory Exposure)
Many shared hosting providers (e.g. Wedos, Český hosting, Active24, cPanel) default the domain's document root to the project root directory rather than `./public/`.

Without a root `/.htaccess`:
- Visitors must type `example.com/public/` to reach the website.
- Sensitive root files (`.env`, `composer.json`, `composer.lock`, `src/`, `config/bolt/`, `var/`) could be browsed and downloaded over plain HTTP if Apache directory indexing or direct file access is allowed.

### Problem 2: Bolt Theme Source Code Leakage (`public/theme/`)
In Bolt CMS, theme assets and templates reside under `public/theme/<themename>/`. Modern frontend workflows bundle development files alongside the theme: Twig templates, `theme.yaml`, `package.json`, `tsconfig.json`, TypeScript and SCSS sources, bundler configs, `node_modules/`, docs, design files and `.DS_Store`.

By default, Symfony's `public/.htaccess` rule (`RewriteCond %{REQUEST_FILENAME} !-f`) tells Apache: **if a requested file exists on disk, serve it directly** — `https://example.com/theme/<themename>/theme.yaml` and `…/package.json` download for anyone.

### Problem 3: Scripts in Uploads (`public/files/`)
Uploads are served from the site's own origin. An `.html` or `.svg` file uploaded by an editor (or placed there over SFTP) runs its scripts as the site when opened directly — next to a logged-in administrator's session (stored XSS).

### Why an allowlist, not only a deny list
A deny list leaks every file type nobody thought of (`.scss`, `.vue`, `.bak`, a new bundler's config). In the folders that mix public files with sources or uploads, the allowlist serves only what browsers need and answers 403 for everything else, so a forgotten type stays private.

**Performance:** neither approach costs anything measurable. Apache compiles each pattern once and tests it against a short path in microseconds; re-reading the `.htaccess` files on every request costs more, and a PHP page takes tens of milliseconds. A missing theme asset even gets cheaper: Apache answers 403 itself instead of booting Bolt for a 404 page.

---

## Step-by-Step Implementation

### Step 1: Create or Update Root `.htaccess`

Create `/.htaccess` at the root of the project (alongside `composer.json` and `config/`) — only when the domain's document root is the project root. If the host lets you point the domain at `public/`, do that instead and skip this file:

```apache
# /.htaccess
RewriteEngine on

# HSTS also on the redirects below (www → canonical host, HTTP → HTTPS): they are answered here,
# before public/.htaccess adds its headers. Browsers ignore the header on plain HTTP.
<IfModule mod_headers.c>
    Header always set Strict-Transport-Security "max-age=31536000"
</IfModule>

# Canonical host: the site answers on one host; the other one redirects to it in a single hop
# (straight to HTTPS). Default: without www — www.example.cz → https://example.cz. For a site whose
# canonical host is www, replace the two lines with (it also redirects localhost and staging hosts —
# add a RewriteCond %{HTTP_HOST} !^(localhost|staging\.) [NC] for those):
#   RewriteCond %{HTTP_HOST} !^www\. [NC]
#   RewriteRule (.*) https://www.%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
RewriteCond %{HTTP_HOST} ^www\.(.+)$ [NC]
RewriteRule (.*) https://%1%{REQUEST_URI} [L,R=301]

# HTTPS redirect — works both on direct Apache TLS and behind a TLS-terminating proxy:
# redirect when Apache itself did not receive HTTPS AND no proxy reported an HTTPS request.
RewriteCond %{HTTPS} off
RewriteCond %{HTTP:X-Forwarded-Proto} !https
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# Redirect all traffic to ./public folder
RewriteRule (.*) public/$1 [QSA,L]
```

#### Directive Breakdown:
- **HSTS block:** the redirects below are answered by this file, before `public/.htaccess` adds its headers — without it the `www` → canonical and HTTP → HTTPS redirects carry no `Strict-Transport-Security`.
- **Canonical host (`www` → without `www`):** both `example.cz` and `www.example.cz` must work, but only one may serve the site. Otherwise every page exists twice (Bolt's canonical link follows the requested host when `BOLT_CANONICAL` is empty), sessions and HSTS are split between two origins, and the second host is easily forgotten in checks. The rule needs no domain name, so the file is identical in every project; it redirects straight to `https://`, one hop. Also set `BOLT_CANONICAL=https://example.cz` (`bolt-security-hardening`, Step 1). The certificate must cover both hosts (`example.cz` + `www.example.cz`, or a wildcard).
- `RewriteEngine on`: Initializes the Apache rewrite engine. Without `mod_rewrite` the file causes an error 500 for every request — the site fails closed instead of exposing the project root.
- `RewriteCond %{HTTPS} off`: Apache itself did not receive the request over TLS (plain HTTP on a direct connection — or any request behind a proxy that terminates TLS).
- `RewriteCond %{HTTP:X-Forwarded-Proto} !https`: No reverse proxy, load balancer or Cloudflare reported that the visitor used HTTPS. A missing header also matches, so direct HTTP requests are redirected.
- The two conditions are combined with AND: redirect only when neither Apache nor a proxy saw HTTPS. Do **not** use `^http$` for the header condition — without a proxy the header is absent, the condition never matches, and plain HTTP is never redirected.
- `RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]`: Issues an HTTP 301 Permanent Redirect to HTTPS.
- `RewriteRule (.*) public/$1 [QSA,L]`: Transparently rewrites the URL into the `public/` directory without changing the URL visible in the user's browser. `QSA` preserves query parameters (`?page=2`), and `L` stops further rewriting in the root context.

**Document root on `public/`** (no root file): put the canonical-host and HTTPS rules at the top of the `<IfModule mod_rewrite.c>` block of `public/.htaccess` instead:

```apache
    RewriteCond %{HTTP_HOST} ^www\.(.+)$ [NC]
    RewriteRule ^ https://%1%{REQUEST_URI} [L,R=301]
    RewriteCond %{HTTPS} off
    RewriteCond %{HTTP:X-Forwarded-Proto} !https
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
```

---

### Step 2: Allowlist for `theme/`, `files/` and `thumbs/`

In `public/.htaccess`, inside `<IfModule mod_rewrite.c>` directly after `RewriteEngine On` and the `node_modules` / `.git` rule — before Symfony's front-controller rules:

```apache
    # Theme build folders: node_modules/ and .git/ are never served.
    RewriteRule (^|/)(node_modules|\.git)(/|$) - [F,L]

    # theme/<theme>/: the built assets in css/, js/, img/, images/ and fonts/. Templates, theme.yaml,
    # package.json, build configs, TypeScript sources and anything at the theme root are denied.
    RewriteCond $0 !^theme/[^/]+/(css|js|img|images|fonts)/([^/]+/)*[^/]+\.(css|js|avif|gif|ico|jpe?g|png|svg|webp|woff2?|ttf|otf|webmanifest|xml|pdf|mp4|webm)$ [NC]
    RewriteRule ^theme/.* - [F,L]

    # files/ (uploads) and thumbs/ (thumbnails): only the file types an upload may have.
    RewriteCond $0 !\.(avif|gif|ico|jpe?g|png|svg|tiff?|webp|pdf|txt|docx?|xlsx?|pptx?|epub|zip|tgz|mp3|ogg|wav|m4a|mp4|m4v|ogv|webm|wmv|avi)$ [NC]
    RewriteRule ^(files|thumbs)/.* - [F,L]
```

| Folder | Served | Everything else |
| :--- | :--- | :--- |
| `theme/<theme>/` | files in `css/`, `js/`, `img/`, `images/`, `fonts/` (any depth) with a static type: styles, scripts, images, fonts, `webmanifest`, `xml` (browserconfig), `pdf`, `mp4`, `webm` | 403 — templates, `theme.yaml`, `package.json`, `*.config.js`, `js/src/*.ts`, the theme root, `node_modules/` |
| `files/` | the upload types of `accept_file_types` / `accept_media_types` (`bolt-security-hardening`) plus `svg` for SVGs uploaded earlier | 403 — `.html`, `.php`, `.js`, `.sql`, … even if they get there over SFTP |
| `thumbs/` | the same types; a thumbnail that does not exist yet passes on to Bolt, which generates it | 403 |

* **How it works:** `$0` is the path relative to `public/` (`theme/acme/css/index.css`). The `RewriteCond` lets allowlisted paths through to the normal rules; every other path under the folder is answered with `[F]` (403).
* **Theme folders:** the convention of `bolt-theme-init` puts browser files in `css/`, `js/` and `img/`. A theme that keeps public files elsewhere (a favicon at the theme root, `dist/`) — move them, or add the folder to the list.
* **Upload types:** keep the `files/` list in line with `accept_file_types` in `config/bolt/config.yaml`. A type the site accepts but this list lacks uploads fine and then answers 403.
* `css/tailwind/index.css` (the Tailwind source) stays reachable: it is CSS, contains nothing private, and the allowlist works by folder and type, not by file.

---

### Step 3: Safety Net for the Rest of `public/`

The public root, `assets/` and `bundles/` are not covered by the allowlist. Directly below `AddDefaultCharset UTF-8` add the deny list — it also protects the theme a second time:

```apache
<IfModule mod_authz_core.c>
    <FilesMatch "(\.(twig|ya?ml|neon|lock|ts|md|psd|ini|sql|sqlite3?|bak|old|orig|swp|log|sh|dist)|^\.DS_Store|^(composer|package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
        Require all denied
    </FilesMatch>
    # Environment files (.env, .env.local, …) must never be served, wherever they end up.
    <FilesMatch "^\.env">
        Require all denied
    </FilesMatch>
</IfModule>
```

(The full template repeats both blocks with `Order allow,deny` / `Deny from all` for Apache 2.2.)

| Pattern | Matched files |
| :--- | :--- |
| `twig`, `ya?ml`, `neon`, `md` | Templates, configuration, docs copied into `public/` |
| `lock`, `^(composer\|package\|package-lock\|tsconfig)\.json`, `\.config\.[cm]?js`, `ts` | Dependency manifests and build tooling |
| `sql`, `sqlite3?`, `bak`, `old`, `orig`, `swp`, `log`, `sh`, `dist` | Database dumps, backups, editor leftovers, logs, scripts |
| `ini` | `.user.ini` (per-directory PHP settings on PHP-FPM hosts) |
| `psd`, `^\.DS_Store` | Design sources, macOS folder metadata (lists file names) |
| `^\.env` | `.env`, `.env.local`, `.env.prod.local` |

---

### Step 4: Security Headers for Static Files

Pages rendered by Symfony get `X-Frame-Options`, `nosniff`, `Referrer-Policy`, `Permissions-Policy` and CSP from `nelmio_security` (`bolt-security-hardening`, Step 6). Files Apache serves itself get none of them — add this block after the deny list:

```apache
<IfModule mod_headers.c>
    # HTTPS only from now on. Browsers ignore the header on plain HTTP, so sending it always is safe.
    # Add "; includeSubDomains" only when every subdomain has a certificate.
    Header always set Strict-Transport-Security "max-age=31536000"

    # Do not advertise the PHP version.
    Header unset X-Powered-By
    Header always unset X-Powered-By

    # Files Apache serves itself get the basics nelmio_security sends with every page.
    <If "%{REQUEST_FILENAME} !~ m#\.php$#">
        Header always set X-Content-Type-Options "nosniff"
        Header always set Referrer-Policy "strict-origin-when-cross-origin"
    </If>

    # Uploads and thumbnails never run scripts — not even an HTML or SVG file opened directly.
    # PDFs are left out: Chrome refuses to show a PDF under a sandbox policy.
    <If "%{REQUEST_FILENAME} =~ m#/public/(files|thumbs)/# && %{REQUEST_FILENAME} !~ m#\.pdf$#i">
        Header always set Content-Security-Policy "default-src 'none'; img-src 'self' data:; media-src 'self'; style-src 'unsafe-inline'; sandbox"
    </If>
</IfModule>
```

* **HSTS** comes from Apache, not from nelmio's `forced_ssl` (which loops behind TLS proxies). Start with `max-age=31536000`; add `includeSubDomains` / `preload` only when every subdomain serves HTTPS.
* **Sandboxed uploads:** with `sandbox`, an SVG or HTML file opened directly has no origin and cannot run scripts — it cannot touch the admin session even if a malicious file got into `files/`. Images embedded with `<img>` are unaffected.
* **Why the conditions test `REQUEST_FILENAME`:** after the root `.htaccess` rewrite, Apache's `REQUEST_URI` is `/public/files/…`, so `^/files/` would never match; the file path on disk works with both document-root layouts. PHP responses (`index.php`) are skipped so their nelmio headers are not sent twice.
* Needs `mod_headers` (enabled on practically every host); without it the block is skipped.

---

### Step 5: Project-Specific Customization Guidelines

- **More theme folders:** add the folder name to `(css|js|img|images|fonts)` in Step 2 (e.g. `dist`).
- **More file types in the theme** (e.g. `json` for a web app manifest named `manifest.json`): add the extension to the theme allowlist — never `twig`, `yaml`, `ts` or `json` in general.
- **More upload types:** add them to `accept_file_types` (`bolt-security-hardening`) and to the `files/` allowlist together. Never `html`, `htm`, `js`, `css`, `php`, `phtml`, `svgz`, `xml`.
- **Another front-end stack** (SCSS, Vue, Svelte sources inside the theme): nothing to do — they are not in an allowlisted folder or not a static type.

---

### Step 6: Asset Caching & Expiration (`mod_expires.c`)

In high-performance production projects, static media assets in `public/` are served with aggressive 2-month caching. This is the **only** `mod_expires` block of the file: `bolt-asset-caching` documents the same block (CSS/JS are safe to cache long because `partials/_master.twig` appends `?v={{ theme.assets_version }}`), so never add a second one:

```apache
# public/.htaccess

<IfModule mod_expires.c>
    ExpiresActive On

    # Images (uploads in public/files/ and disk thumbnails in public/thumbs/)
    ExpiresByType image/avif "access plus 2 months"
    ExpiresByType image/gif "access plus 2 months"
    ExpiresByType image/jpeg "access plus 2 months"
    ExpiresByType image/png "access plus 2 months"
    ExpiresByType image/svg+xml "access plus 2 months"
    ExpiresByType image/webp "access plus 2 months"

    # Documents
    ExpiresByType application/pdf "access plus 2 months"

    # Frontend assets (styles, scripts) — cache-busted with ?v={{ theme.assets_version }}.
    # Apache serves .js as text/javascript (newer mime.types) or application/javascript (older).
    ExpiresByType text/css "access plus 2 months"
    ExpiresByType text/javascript "access plus 2 months"
    ExpiresByType application/javascript "access plus 2 months"

    # Fonts
    ExpiresByType font/woff2 "access plus 1 year"
    ExpiresByType font/woff "access plus 1 year"
</IfModule>
```

---

### Step 7: Full Reference Template for `public/.htaccess`

The complete, production-verified `public/.htaccess` file is available at
[`examples/public.htaccess`](examples/public.htaccess). Tested with Apache 2.4 + PHP-FPM, with the
document root on the project root (root `.htaccess`) and on `public/`.

Key structural sections:
1. `AddDefaultCharset UTF-8`
2. `<FilesMatch …>` safety-net deny list and `.env*` block (Step 3)
3. `<IfModule mod_headers.c>` security headers (Step 4)
4. `<IfModule mod_expires.c>` asset caching headers (Step 6)
5. `<IfModule mod_rewrite.c>`:
   - `node_modules/` and `.git/` denied, allowlist for `theme/`, `files/`, `thumbs/` (Step 2)
   - Base URI detection, Authorization header propagation
   - Redirection of direct `/index.php` queries (prevents duplicate content)
   - Fallback rewrite of all missing files (`RewriteCond %{REQUEST_FILENAME} !-f`) to `%{ENV:BASE}/index.php [END]`

---

## Verification & Testing

### 1. Automated Verification Script
Run the built-in verification script to test both `/.htaccess` and `public/.htaccess`:

```bash
BOLT_BASE_URL=https://staging.example.cz skills/bolt-htaccess/scripts/verify.sh
```

The script performs:
- **Root `.htaccess` Check:** Confirms `RewriteEngine on`, HTTPS redirect rules, the canonical-host redirect (`www`), and rewrite to `./public`.
- **Public `.htaccess` Check:** Confirms `AddDefaultCharset UTF-8` and the front controller rules.
- **Allowlist Check:** Tests sample paths against the theme and upload allowlists — built assets and accepted uploads pass, templates, configs, sources, the theme root and `.html` / `.php` uploads are denied.
- **Safety-net Check:** Tests the `FilesMatch` deny list against sensitive file names, confirms no public asset type is blocked, and that `node_modules`, `.git` and `.env*` are denied.
- **Security Headers Check:** HSTS, `X-Powered-By` removal, nosniff for static files, sandboxed uploads.
- **Live HTTP Check (if `BOLT_BASE_URL` answers):** theme sources and a fake upload path answer 403 / 404, a built asset answers 200, the headers of a static file. Run it against Apache — PHP's built-in server and `symfony serve` ignore `.htaccess`.

### 2. Manual HTTP Testing
If the site is running on staging (Apache):

```bash
# Theme sources: 403
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/theme.yaml
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/package.json
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/js/src/index.ts
# Built assets: 200
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/css/index.css
# Uploads of a forbidden type: 403, whether the file exists or not
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/files/anything.html
# Headers of an upload: Content-Security-Policy … sandbox, X-Content-Type-Options: nosniff
curl -sI https://example.com/files/<an uploaded image> | grep -iE "content-security|nosniff|strict-transport"
# Plain HTTP: 301 to https:// — on both hosts; www: 301 straight to https://example.com/
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://example.com/
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://www.example.com/
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" https://www.example.com/
# Secrets and the project root: 403 / 404
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/.env
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/var/data/bolt.sqlite
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Over-broad Regex Blocking Compiled Assets
- **Mistake:** Writing `(\.(js|json|css))` in `FilesMatch`.
- **Consequence:** Breaks the entire frontend because browsers cannot load compiled `.js` bundles or `.css` stylesheets.
- **Fix:** Target only source files and specific configuration filenames: `\.config\.[cm]?js`, `^(package|package-lock|tsconfig)\.json`, `\.ts`. Never block generic `.js` or `.css` extensions.

### Pitfall 2: Infinite Redirect Loop on Front Controller
- **Symptom:** Apache logs `Request exceeded the limit of 10 internal redirects`.
- **Cause:** In older Apache versions or without `[END]` flags, `RewriteRule ^index\.php` redirects repeatedly.
- **Fix:** Keep `RewriteCond %{ENV:REDIRECT_STATUS} =""` before the `index.php` redirect rule and use the `[END]` flag on Apache 2.4+.

### Pitfall 3: Direct SSL vs Proxy SSL
- **Symptom A:** On a host without a TLS proxy, `http://` URLs are never redirected to `https://`.
  - **Cause:** `RewriteCond %{HTTP:X-Forwarded-Proto} ^http$` combined (AND) with `RewriteCond %{HTTPS} off` — without a proxy the header is absent, so the first condition never matches.
- **Symptom B:** Behind a TLS-terminating proxy (Cloudflare, load balancer), every request redirects to itself (`ERR_TOO_MANY_REDIRECTS`).
  - **Cause:** `RewriteCond %{HTTP:X-Forwarded-Proto} ^http$ [OR]` + `RewriteCond %{HTTPS} off` — behind the proxy Apache always sees `HTTPS off`, so the `[OR]` matches even for HTTPS visitors.
- **Fix:** Redirect only when neither Apache nor the proxy saw HTTPS:
  ```apache
  RewriteCond %{HTTPS} off
  RewriteCond %{HTTP:X-Forwarded-Proto} !https
  RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
  ```

### Pitfall 4: `node_modules/` Inside the Public Theme
- **Symptom:** `https://example.com/theme/<theme>/node_modules/photoswipe/package.json` is blocked, but every `.js` file of every dependency downloads.
- **Cause:** `FilesMatch` matches file names, not folders; the theme's `npm install` writes `node_modules/` into `public/`.
- **Fix:** The `RewriteRule (^|/)(node_modules|\.git)(/|$) - [F,L]` rule and the theme allowlist, and do not deploy `node_modules/` to production (build locally, upload the built `css/index.css` and `js/app.js`).

### Pitfall 5: A Theme Image or Font Suddenly Answers 403
- **Cause:** It lives outside `css/`, `js/`, `img/`, `images/`, `fonts/` (e.g. `theme/<theme>/favicon.ico`) or has a type the allowlist does not list.
- **Fix:** Move the file into an allowlisted folder, or extend the folder / type list (Step 5). Never allow the whole theme.

### Pitfall 6: Header Conditions on `REQUEST_URI` Never Match
- **Cause:** After the root `.htaccess` forwards a request into `public/`, Apache processes it as `/public/files/…`; after the front-controller rewrite, as `/public/index.php`.
- **Fix:** Test the file on disk — `%{REQUEST_FILENAME} =~ m#/public/(files|thumbs)/#` — as the template does.

### Pitfall 7: Headers Sent Twice
- **Cause:** `Header setifempty` does not see headers set by PHP-FPM, so nosniff and Referrer-Policy were added to pages that already had them from nelmio.
- **Fix:** Limit those headers to non-PHP files (`<If "%{REQUEST_FILENAME} !~ m#\.php$#">`), as the template does.
