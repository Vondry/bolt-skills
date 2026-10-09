---
name: bolt-htaccess
description: >-
  Use this skill whenever creating, configuring, or hardening Apache .htaccess
  files in a Bolt CMS repository. Implements the production two-tier .htaccess
  architecture: root-level HTTPS redirection and ./public directory forwarding
  for web hosts, plus public/.htaccess source code shielding (blocking .twig,
  .yaml, .neon, .lock, .ts, .md, .psd, .DS_Store, package.json, tsconfig.json,
  and build configs) to prevent public data and source code leakage.
---

# Bolt CMS Apache `.htaccess` Configuration & Source Code Hardening

In Bolt CMS deployments running on Apache (such as shared hosting, VPS setups, or traditional virtual hosts), proper `.htaccess` configuration is critical for both routing and security.

This skill documents the production-tested two-tier `.htaccess` architecture established across active Bolt CMS installations:
1. **Root `/.htaccess`**: Enforces HTTPS and transparently routes all requests into the `./public/` document root.
2. **Public `/public/.htaccess`**: Hardens Symfony's front controller rewrite rules, enforces UTF-8 character encoding, and blocks public HTTP access to theme templates, configuration files, TypeScript sources, build tooling, design assets, `node_modules/`, `.git/` and `.env*` files.

---

## Architecture Overview

```text
Project Root (/)
├── .htaccess                       # Tier 1: HTTPS redirect & rewrite traffic into public/
├── .env, composer.json, src/, ...  # Protected behind project root (never exposed)
└── public/                         # Web Document Root
    ├── .htaccess                   # Tier 2: Front controller + source code lockdown
    ├── index.php                   # Front controller entrypoint
    ├── assets/                     # Compiled public assets (CSS, JS, fonts)
    ├── files/                      # Uploaded media (images, PDFs)
    └── theme/<theme_name>/         # Theme directory (contains templates & source files!)
        ├── theme.yaml              # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
        ├── index.twig              # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
        ├── package.json            # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
        ├── tsconfig.json           # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
        ├── rollup.config.js        # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
        └── src/app.ts              # 🛑 MUST NOT BE ACCESSIBLE OVER HTTP
```

---

## The Core Problems Solved

### Problem 1: Unpointed DocumentRoot (Root Directory Exposure)
Many shared hosting providers (e.g. Wedos, Český hosting, Active24, cPanel) default the domain's document root to the project root directory rather than `./public/`. 

Without a root `/.htaccess`:
- Visitors must type `example.com/public/` to reach the website.
- Sensitive root files (`.env`, `composer.json`, `composer.lock`, `src/`, `config/bolt/`, `var/`) could be browsed and downloaded over plain HTTP if Apache directory indexing or direct file access is allowed.

### Problem 2: Bolt Theme Source Code Leakage (`public/theme/`)
In Bolt CMS, theme assets and templates reside under `public/theme/<themename>/`. Modern frontend workflows bundle development files alongside the theme:
- Twig templates (`.twig`)
- Theme configurations (`theme.yaml`, `.neon`)
- Build dependencies and manifests (`package.json`, `package-lock.json`, `tsconfig.json`)
- Source code (`.ts`, `.scss`) and bundler configs (`rollup.config.js`, `postcss.config.mjs`, `vite.config.*`)
- Documentation (`README.md`, `.md`) and design files (`.psd`)
- macOS filesystem metadata (`.DS_Store`)

By default, Symfony's `public/.htaccess` rule (`RewriteCond %{REQUEST_FILENAME} !-f`) tells Apache: **if a requested file exists on disk, serve it directly**.

Without an explicit deny rule, any browser or web crawler can request:
`https://example.com/theme/<themename>/theme.yaml`
`https://example.com/theme/<themename>/index.twig`
`https://example.com/theme/<themename>/package.json`

This exposes private template logic, database structure clues, internal paths, and third-party dependency lists.

---

## Step-by-Step Implementation

### Step 1: Create or Update Root `.htaccess`

Create `/.htaccess` at the root of the project (alongside `composer.json` and `config/`):

```apache
# /.htaccess
RewriteEngine on

# HTTPS redirect — works both on direct Apache TLS and behind a TLS-terminating proxy:
# redirect when Apache itself did not receive HTTPS AND no proxy reported an HTTPS request.
RewriteCond %{HTTPS} off
RewriteCond %{HTTP:X-Forwarded-Proto} !https
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# Redirect all traffic to ./public folder
RewriteRule (.*) public/$1 [QSA,L]
```

#### Directive Breakdown:
- `RewriteEngine on`: Initializes the Apache rewrite engine.
- `RewriteCond %{HTTPS} off`: Apache itself did not receive the request over TLS (plain HTTP on a direct connection — or any request behind a proxy that terminates TLS).
- `RewriteCond %{HTTP:X-Forwarded-Proto} !https`: No reverse proxy, load balancer or Cloudflare reported that the visitor used HTTPS. A missing header also matches, so direct HTTP requests are redirected.
- The two conditions are combined with AND: redirect only when neither Apache nor a proxy saw HTTPS. Do **not** use `^http$` for the header condition — without a proxy the header is absent, the condition never matches, and plain HTTP is never redirected.
- `RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]`: Issues an HTTP 301 Permanent Redirect to HTTPS.
- `RewriteRule (.*) public/$1 [QSA,L]`: Transparently rewrites the URL into the `public/` directory without changing the URL visible in the user's browser. `QSA` preserves query parameters (`?page=2`), and `L` stops further rewriting in the root context.

---

### Step 2: Update `public/.htaccess` with Source Protection

Open `public/.htaccess`. Directly below `AddDefaultCharset UTF-8` (and above `mod_rewrite.c`), add the access restriction block:

```apache
# public/.htaccess

# Static text files served directly by Apache (e.g. robots.txt) are UTF-8.
# Responses from Symfony, such as /llms.txt, set their own charset.
AddDefaultCharset UTF-8

# Theme sources sit in the public folder but are never needed by browsers: Twig templates and
# theme.yaml are read by PHP from disk, and the build tooling (package.json, tsconfig.json, rollup /
# postcss configs, TypeScript sources, docs) only produces the built CSS/JS. The same goes for
# Photoshop sources (.psd) and macOS folder metadata (.DS_Store, which lists file names). Never
# serve them.
<IfModule mod_authz_core.c>
    <FilesMatch "(\.(twig|ya?ml|neon|lock|ts|md|psd)|^\.DS_Store|^(package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
        Require all denied
    </FilesMatch>
    # Environment files (.env, .env.local, …) must never be served, wherever they end up.
    <FilesMatch "^\.env">
        Require all denied
    </FilesMatch>
</IfModule>
<IfModule !mod_authz_core.c>
    <FilesMatch "(\.(twig|ya?ml|neon|lock|ts|md|psd)|^\.DS_Store|^(package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
        Order allow,deny
        Deny from all
    </FilesMatch>
    <FilesMatch "^\.env">
        Order allow,deny
        Deny from all
    </FilesMatch>
</IfModule>

<IfModule mod_rewrite.c>
    RewriteEngine On

    # Theme build folders: node_modules/ (created by npm inside public/theme/<theme>/) exposes
    # every dependency's sources and versions; .git/ exposes the repository. Deny both.
    RewriteRule (^|/)(node_modules|\.git)(/|$) - [F,L]

    # … Symfony front-controller rules follow (see the full template) …
</IfModule>
```

#### What is blocked and why:
| Pattern | Matched Files | Why It Must Be Denied |
| :--- | :--- | :--- |
| `\.twig` | `index.twig`, `record.twig`, `_header.twig` | Twig templates are read by PHP from disk. Exposing them reveals markup structure and data contracts. |
| `\.ya?ml` | `theme.yaml`, `config.yaml` | Theme configuration files reveal content bindings and internal settings. |
| `\.neon` | `phpstan.neon`, Nette configs | Linter/static analysis configurations. |
| `\.lock` | `composer.lock`, `package-lock.json` | Lockfiles list exact library versions and hashes, enabling vulnerability profiling. |
| `\.ts` | `app.ts`, `menu.ts`, `gallery.ts` | TypeScript sources. Browsers only need the compiled JavaScript in `assets/`. |
| `\.md` | `README.md`, `CHANGELOG.md` | Repository documentation, author notes, and internal instructions. |
| `\.psd` | `banner.psd`, `logo.psd` | Proprietary Photoshop design files mistakenly left in media or theme folders. |
| `^\.DS_Store` | `.DS_Store` | macOS directory metadata files. Downloadable `.DS_Store` files expose directory listings. |
| `^(package\|package-lock\|tsconfig)\.json` | `package.json`, `tsconfig.json` | Node package manifests and TypeScript configuration files. |
| `\.config\.[cm]?js` | `rollup.config.js`, `postcss.config.mjs`, `vite.config.cjs`, `tailwind.config.js` | Frontend build tooling configurations. |
| `^\.env` (separate `FilesMatch`) | `.env`, `.env.local`, `.env.prod.local` | Secrets (database credentials, `APP_SECRET`, API keys) if an env file is ever copied into `public/`. |
| `RewriteRule (^\|/)(node_modules\|\.git)(/\|$) - [F]` | `theme/<theme>/node_modules/…`, `.git/config` | `npm install` creates `node_modules/` inside the public theme folder; it exposes every dependency's sources and versions. `.git/` exposes the whole repository history. `FilesMatch` matches file names only, so folders need a rewrite rule. |

> [!NOTE]
> `<IfModule mod_authz_core.c>` is the modern Apache 2.4+ authorization standard (`Require all denied`). The `<IfModule !mod_authz_core.c>` fallback (`Deny from all`) ensures full protection on legacy Apache 2.2 hosts.

---

### Step 3: Project-Specific Customization Guidelines

The baseline regex is designed to be easily tailored to each project's frontend stack and directory layout. Review the project's `public/theme/` and `public/` directories to add any relevant extensions:

#### A. SCSS / Sass / Less Sources
If the theme writes styles in preprocessor formats rather than compiling to CSS externally:
```apache
<FilesMatch "(\.(twig|ya?ml|neon|lock|ts|scss|sass|less|md|psd)|^\.DS_Store|^(package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
```

#### B. Component Frameworks (Vue / Svelte / JSX)
If using Vue, Svelte, or React/JSX components in theme development:
```apache
<FilesMatch "(\.(twig|ya?ml|neon|lock|ts|tsx|jsx|vue|svelte|md|psd)|^\.DS_Store|^(package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
```

#### C. Vite or Modern Bundlers
If the project uses Vite (`vite.config.ts`), Biome (`biome.json`), or ESLint (`eslint.config.js`):
- `\.config\.[cm]?js` already matches `vite.config.js` and `vite.config.mjs`.
- `\.ts` already matches `vite.config.ts`.
- To block `biome.json` or `.eslintrc.*`:
```apache
<FilesMatch "(\.(twig|ya?ml|neon|lock|ts|md|psd)|^\.DS_Store|^(package|package-lock|tsconfig|biome)\.json|\.config\.[cm]?js|^\.eslint.*)$">
```

#### D. Accidental Dumps, Scripts & Backups
To protect against accidental database dumps, shell scripts, or editor backup files placed in `public/` or `public/files/`:
```apache
<FilesMatch "(\.(twig|ya?ml|neon|lock|ts|md|psd|sql|sh|bash|bak|swp|old)|^\.DS_Store|^(package|package-lock|tsconfig)\.json|\.config\.[cm]?js)$">
```

---

### Step 4: Asset Caching & Expiration (`mod_expires.c`)

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

### Step 5: Full Reference Template for `public/.htaccess`

The complete, production-verified `public/.htaccess` file combining UTF-8 charset, source protection, cache headers, and Symfony front controller rewrite rules is available at:
[`examples/public.htaccess`](examples/public.htaccess).

Key structural sections:
1. `AddDefaultCharset UTF-8`
2. `<FilesMatch ...>` Source shielding block
3. `<IfModule mod_expires.c>` Asset caching headers
4. `<IfModule mod_rewrite.c>` Symfony Front Controller routing:
   - Base URI detection
   - Authorization header propagation
   - Redirection of direct `/index.php` queries (prevents duplicate content)
   - Fallback rewrite of all missing files (`RewriteCond %{REQUEST_FILENAME} !-f`) to `%{ENV:BASE}/index.php [END]`

---

## Verification & Testing

### 1. Automated Verification Script
Run the built-in verification script to test both `/.htaccess` and `public/.htaccess`:

```bash
skills/bolt-htaccess/scripts/verify.sh
```

The script performs:
- **Root `.htaccess` Check:** Confirms `RewriteEngine on`, HTTPS redirect rules, and rewrite to `./public`.
- **Public `.htaccess` Check:** Confirms `AddDefaultCharset UTF-8`, presence of the `<FilesMatch>` deny block, and front controller rules.
- **HTTPS Redirect Check:** Warns when the root redirect uses the `X-Forwarded-Proto ^http$` condition (never redirects without a proxy).
- **Folder & Env Shielding:** Warns when `node_modules`, `.git` or `.env` are not denied.
- **Regex Rule Validation:** Tests standard blocked filenames (`theme.yaml`, `index.twig`, `package.json`, `app.ts`, `rollup.config.mjs`, `design.psd`, `.DS_Store`) against the configured pattern to verify they match.
- **Allowlist Safety Validation:** Confirms that normal public assets (`theme.css`, `bundle.js`, `logo.svg`, `photo.webp`, `font.woff2`) are **NOT** blocked.
- **Live HTTP Check (if server is running):** Executes curl requests against sample protected endpoints to assert `HTTP 403 Forbidden`.

### 2. Manual HTTP Testing
If the site is running locally or on staging:

```bash
# Test 1: Theme config must return 403 Forbidden
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/theme.yaml
# Expected: 403

# Test 2: Twig template must return 403 Forbidden
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/index.twig
# Expected: 403

# Test 3: package.json must return 403 Forbidden
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/package.json
# Expected: 403

# Test 4: Compiled assets must return 200 OK
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/css/theme.css
# Expected: 200

# Test 5: Plain HTTP request must return 301 Redirect to HTTPS
curl -s -o /dev/null -w "%{http_code}\n" http://example.com/
# Expected: 301

# Test 6: Dependency folders and env files must return 403
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/theme/mytheme/node_modules/photoswipe/package.json
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/.env
# Expected: 403 (or 404 when the file does not exist)
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
- **Fix:** The `RewriteRule (^|/)(node_modules|\.git)(/|$) - [F,L]` rule above, and do not deploy `node_modules/` to production (build in CI or locally, upload the built `css/index.css` and `js/app.js`).
