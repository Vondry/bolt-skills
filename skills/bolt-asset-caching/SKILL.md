---
name: bolt-asset-caching
description: >-
  Use this skill whenever setting up, optimizing, or debugging client/CDN HTTP caching
  for Bolt CMS images, thumbnails, CSS, JS, and PDFs. Resolves the critical Symfony
  SessionListener bug where stateful firewalls rewrite League Glide's public 1-year
  thumbnail cache to private/no-cache, configures Bolt's save_files thumbnail disk dump,
  sets up Apache mod_expires and Nginx static expires rules, establishes frontend
  asset cache-busting (?v=X.X), and checks end to end — Apache with the project's .htaccess
  plus PHP-FPM, or production — that every thumbnail and upload is served from disk with ETag,
  Last-Modified, max-age and 304s instead of by PHP.
---

# Bolt CMS Full-Stack Asset & Thumbnail Caching

In Bolt CMS websites, media files, thumbnails, and compiled stylesheets/scripts account for the vast majority of HTTP requests and bandwidth. Without end-to-end caching configuration across Symfony, Bolt core, and the web server (Apache/Nginx), browsers will re-download assets on every visit, degrading Core Web Vitals and overloading PHP-FPM.

This skill documents the complete multi-layer asset caching architecture established across production Bolt CMS repositories.

---

## 1. The Core Root Cause: The Symfony Thumbnail Cache Destruction Bug

### Why Thumbnails Were Not Being Cached:
1. **Glide's Intended Behavior:**
   Bolt CMS dynamically generates manipulated thumbnails on demand via `Bolt\Controller\ImageController` using **League Glide**. Under the hood, Glide sets a public one-year cache header:
   ```http
   Cache-Control: max-age=31536000, public
   Expires: ...
   ```
   It sends **no `ETag` and no `Last-Modified`**, so a browser can't revalidate a thumbnail that PHP served (no `304 Not Modified`); once the year is over, or after a hard reload, it downloads the whole image again. Only a thumbnail saved to disk and served by Apache / Nginx (Step 2) gets `ETag`, `Last-Modified` and 304s.
2. **The Default Symfony Firewall:**
   In standard Symfony and Bolt starter configurations (`config/packages/security.yaml`), the stateless `dev` firewall (which disables security tokens and session handling) only matched:
   ```yaml
   firewalls:
     dev:
       pattern: ^/(_(profiler|wdt)|css|images|js)/
       security: false
   ```
   **Notice that `/thumbs` is omitted.**
3. **The Silent Downgrade:**
   Requests for `/thumbs/320x240/hero.webp` fall through to Symfony's stateful `main` firewall (`pattern: ^/`).
   The `main` firewall initializes the security token and touches the user session. When Symfony's `SessionListener` executes on the response, it detects an active session context and **overwrites Glide's public cache header** with:
   ```http
   Cache-Control: private, must-revalidate, max-age=0
   ```
4. **The Impact:**
   Browsers and CDNs (Cloudflare, Fastly, etc.) strictly obey `private, max-age=0` and refuse to store thumbnails in disk or memory cache. Every page reload triggers full image transfers and forces PHP to repeatedly handle thumbnail requests!

---

## 2. Multi-Layer Caching Architecture

To achieve optimal performance, assets are cached through four synchronized layers:

```text
Request Path:
Browser / CDN
  │
  ├── 1. Direct Web Server Static Cache (Apache mod_expires / Nginx expires 2M)
  │      └── Serves public/files/, public/assets/, and disk-saved public/thumbs/
  │          straight from disk without booting PHP.
  │
  └── 2. First-time Thumbnail Generation (/thumbs/...)
         └── Handled by Symfony / Bolt ImageController
             │
             ├── Bypass Firewall (security.yaml): No session touched -> Glide sends public, max-age=31536000.
             └── Disk Dump (config/bolt/config.yaml save_files: true):
                 Saves to public/thumbs/ so subsequent requests hit Layer 1 directly!
```

---

## 3. Step-by-Step Implementation

### Step 1: Bypass the Security Firewall for `/thumbs`
File: `config/packages/security.yaml`

Update the `dev` firewall pattern to explicitly include `thumbs`:

```yaml
# config/packages/security.yaml

security:
  firewalls:
    dev:
      pattern: ^/(_(profiler|wdt)|css|images|js|thumbs)/
      security: false
```

* **Why this works:** The `/thumbs/` route is now processed statelessly. No security listeners or session managers run, preserving League Glide's `Cache-Control: public, max-age=31536000` header on the HTTP response.

---

### Step 2: Enable Thumbnail Disk Caching (`save_files: true`)
File: `config/bolt/config.yaml`

Ensure `save_files: true` is configured in the `thumbnails` section:

```yaml
# config/bolt/config.yaml

thumbnails:
  default_thumbnail: [ 320, 240 ]
  default_image: [ 1000, 750 ]
  quality: 80
  cropping: crop
  # Save generated thumbnails directly to public/thumbs/ on disk
  save_files: true
  allow_upscale: false

# The upload whitelist (accept_file_types / accept_media_types) is part of
# bolt-security-hardening (examples/config_snippet.yaml).
```

* **How this operates:**
  1. **First request:** The file does not exist on disk in `public/thumbs/`. The request hits PHP, generates the thumbnail, streams it back to the user, and dumps the binary to `public/thumbs/{parameters}/{filename}`.
  2. **Subsequent requests:** Apache and Nginx find the file directly on disk via standard static file rules and serve it directly with 0 ms PHP overhead!

* **bolt/core 6.0.1 – 6.1.x:** these versions save thumbnails to `public/thumbs/<w>_<h>_<q>_<fit>_<location>/` (e.g. `400_300_80_crop_files/`), a path no thumbnail URL points to. The web server never finds them, so **every `/thumbs/…` request still runs PHP** (with Glide's headers from section 1). Fixed by bolt/core PR #3828; thumbnail URLs stay the same, so after upgrading only delete the unused `public/thumbs/*_files/` folders (locally and on the server). `scripts/verify.sh` detects the affected versions in `vendor/`, and the delivery check (section 4) shows where each thumbnail actually comes from.

---

### Step 3: Configure Apache Static Expiration (`public/.htaccess`)
File: `public/.htaccess`

Add the `mod_expires` configuration block. `bolt-htaccess` owns `public/.htaccess` and ships the same block: keep **one** `<IfModule mod_expires.c>` and merge missing types into it — a second block makes it unclear which rules apply.

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

* **Without this block** Apache sends uploads and saved thumbnails with `ETag` and `Last-Modified` but without `max-age` / `Expires`, so browsers revalidate every image on every page view. `scripts/verify.sh` fails when the block is missing.
* **TTL Rationale:** A 2-month window (`access plus 2 months`) provides maximum cache hit rates while dropping `must-revalidate`, allowing browsers to serve assets instantly from disk cache.
* **JavaScript MIME types:** current Apache `mime.types` serve `.js` as `text/javascript`; older ones as `application/javascript`. List both, otherwise scripts get no expiry header on newer servers.

---

### Step 4: Configure Nginx Static Expiration (`docker/nginx/conf.d/default.conf`)
File: `docker/nginx/conf.d/default.conf`

The `/theme/`, `/files/` and `/thumbs/` locations come from **`bolt-security-hardening`** (`examples/docker/nginx_security.conf`): they serve only allowlisted file types, set `expires 2M`, and pass a thumbnail that is not on disk yet to Bolt (`try_files $uri /index.php`). Use that file; do not add a second `/thumbs` location — Nginx refuses duplicate locations.

For the rest of `public/` (Bolt's admin assets in `/assets/` and `/bundles/`, a favicon in the root) add the generic static block from [`examples/nginx_static.conf`](examples/nginx_static.conf):

```nginx
location ~* ^.+\.(?:avif|css|gif|ico|jpe?g|js|png|svg|webp|woff2?|ttf|otf|webmanifest|pdf|mp4|webm)$ {
    access_log                    off;
    log_not_found                 off;
    expires                       2M;
    try_files                     $uri =404;
}
```

* **No `add_header` in these locations.** An `add_header` inside a location drops every `add_header` of the server block for that location — the HSTS and `nosniff` headers of `bolt-security-hardening` would disappear from every image. `expires 2M` already sends `Cache-Control: max-age=5184000`; an extra `add_header Cache-Control "public"` would send a second `Cache-Control` header, and `Pragma` has no effect on modern browsers.

### Step 5: Frontend Asset Cache-Busting (`?v=X.X`)

Because CSS and JS are now served with 2-month caching, browsers will not check the server for updates until the cache expires. To ensure instant updates upon releasing new styling or scripts, append a version query string to asset paths in the theme's layout shell. The version lives in `theme.yaml` (`assets_version`), so a release changes one line:

```twig
{# public/theme/<theme_name>/partials/_master.twig (bolt-theme-init) #}

<link rel="stylesheet" href="{{ asset('css/index.css') }}?v={{ theme.assets_version|default('1.0') }}">
<script defer src="{{ asset('js/app.js') }}?v={{ theme.assets_version|default('1.0') }}"></script>
```

```yaml
# public/theme/<theme_name>/theme.yaml
assets_version: '1.4'
```

Whenever CSS or JS is rebuilt for a new release, bump `assets_version` (e.g. `'1.3'` → `'1.4'`), forcing all browsers to immediately fetch the new files while retaining long-lived caching. A hard-coded `?v=1.3` in the template works the same way but has to be changed in every layout that loads the assets (`partials/_master.twig`, `helper-pages/_helper_template_without_master.twig`). Bolt registers the active theme as the default asset package on frontend and error pages, so `asset('css/index.css')` resolves to `/theme/<theme_name>/css/index.css`.

---

## 4. Verification & Testing

### 1. Automated Verification Script
Run the automated test runner:

```bash
skills/bolt-asset-caching/scripts/verify.sh
```

The script verifies:
1. `config/packages/security.yaml` dev firewall contains `thumbs` (`^/(_(profiler|wdt)|css|images|js|thumbs)/`).
2. `config/bolt/config.yaml` has `thumbnails.save_files: true`.
3. `public/.htaccess` has `mod_expires.c` with image expiration rules (fails without them); warns when JavaScript is listed only as `application/javascript` (without `text/javascript`) or when more than one `mod_expires` block exists.
4. `docker/nginx/conf.d/default.conf` (if present) has `expires` and `try_files` for `/thumbs`.
5. `vendor/bolt/core` saves thumbnails at the path of their URL; warns on bolt/core 6.0.1 – 6.1.x (Step 2).
6. If a Symfony CLI server runs for the project: the `Cache-Control` of a generated thumbnail is `public`, not `private, max-age=0`.
7. The end-to-end delivery check below, when `scripts/serve-apache.sh` is running for the project or `BOLT_DELIVERY_URL` points at a staging / production site (fails on any thumbnail or upload not served from disk with full cache headers). It does not use `BOLT_BASE_URL`, which is usually `symfony serve`.

The configuration checks can all pass while every thumbnail still runs PHP (bolt/core 6.0.1 – 6.1.x, a read-only `public/thumbs/`, a web server rule that never looks on disk). Only the delivery check shows what the web server actually does.

### 2. End-to-End Delivery Check (`scripts/check-delivery.php`)
Crawls the running site (`/sitemap.xml` and links), collects every image the pages reference — `/thumbs/…`, `/files/…`, theme images, `srcset`, CSS `url()`, icons, `og:image` — and requests each one three times:

1. **first request** — may go to PHP, which generates and saves the thumbnail;
2. **second request** — must come from disk, with `ETag`, `Last-Modified` and a `max-age`;
3. **conditional request** with the `ETag` / `Last-Modified` of the second — must answer `304`.

It fails when a thumbnail or upload doesn't; theme images only warn, and image URLs that answer 404 are listed as broken references.

Run it against the web server the site runs on in production. `symfony serve` and PHP's built-in server ignore `.htaccess` and send uploads without `ETag` and `Cache-Control`; the check warns when the responses look like that. For an Apache site, `scripts/serve-apache.sh` serves the project locally like the production host — Apache with the project's own root and `public/` `.htaccess` files, PHP-FPM in `prod` — and sets up a PHP-FPM access log that records which requests reached PHP:

```bash
bash $SKILLS/bolt-asset-caching/scripts/serve-apache.sh start --port=8090      # prints the commands below
php $SKILLS/bolt-asset-caching/scripts/check-delivery.php \
    --base-url=http://127.0.0.1:8090 --fpm-log=var/serve-apache/logs/php-fpm-access.log
bash $SKILLS/bolt-asset-caching/scripts/serve-apache.sh stop
```

`serve-apache.sh` needs Apache (`httpd` / `apache2` with `mod_rewrite`, `mod_expires`, `mod_headers`, `mod_proxy_fcgi`) and `php-fpm`; it writes only to `var/serve-apache/` (kept out of `git status`), and Symfony builds `var/cache/prod` on the first request. Run `bin/console cache:clear --env=prod` first if that cache is stale. The check sends `X-Forwarded-Proto: https` to local URLs, so the root `.htaccess` HTTPS redirect stays quiet.

While `serve-apache.sh` runs, `scripts/verify.sh` (and `verify-all.sh`) include the delivery check automatically. The same script works against staging or production (`--base-url=https://example.com`, or `BOLT_DELIVERY_URL=https://example.com` for `verify.sh`; read-only GET requests). Without `--fpm-log` it counts a response without `ETag` and without `Accept-Ranges` as PHP — Bolt's thumbnail responses send neither, Apache and Nginx send both for static files. Add `--alias=www.example.com` when the pages link to the site under another host name, `--details` to list every URL, `--json=report.json` for the raw results.

A passing site looks like this (a thumbnail goes through PHP once, when it is generated):

```text
category  URLs  1st PHP  2nd disk  2nd PHP    broken  ETag  LastMod  max-age   304
thumbs      69       69        69        0         0    69       69       69    69
files       53        0        53        0         0    53       53       53    53
```

On bolt/core 6.0.1 – 6.1.x the same site shows `2nd PHP 69`, no `ETag` / `Last-Modified` and no 304s for thumbnails. A freshly saved thumbnail can carry a weak ETag (`W/"…"`): Apache marks files changed within the last second as weak; 304s work the same.

### 3. Manual HTTP Header Inspection
Test live response headers using `curl -I`:

```bash
# 1. Test thumbnail headers (request it twice — the first request may generate it)
curl -I https://example.com/thumbs/320x240/foto/hero.webp

# Expected Headers (served from disk):
# HTTP/2 200
# cache-control: max-age=5184000
# etag: "..."
# last-modified: ...
# A response without etag / last-modified and with max-age=31536000, public came from PHP (Glide).
# It must never contain "private, max-age=0".

# 2. Test static media headers
curl -I https://example.com/files/foto/hero.webp

# Expected Headers:
# HTTP/2 200
# cache-control: max-age=5184000 (or expires in 2 months)

# 3. Test CSS/JS cache headers
curl -I https://example.com/theme/mytheme/css/index.css?v=1.1
```

---

## 5. Common Pitfalls & Solutions

### Pitfall 1: Session Started in Custom Middleware
- **Symptom:** Even with `thumbs` in `security: false`, headers occasionally show `private`.
- **Cause:** A custom EventSubscriber or Twig extension injected `RequestStack::getSession()` without checking `hasSession()`.
- **Fix:** Never start sessions for asset routes or ensure session calls are guarded by `if ($request->hasSession())`.

### Pitfall 2: Thumbnails Still Served by PHP Despite `save_files: true`
- **Symptom:** the delivery check reports thumbnails as `2nd PHP`; their responses have `Cache-Control: max-age=31536000, public` but no `ETag` / `Last-Modified`, and `public/thumbs/` fills with folders like `400_300_80_crop_files/`.
- **Cause:** bolt/core 6.0.1 – 6.1.x save thumbnails to a path no thumbnail URL points to (Step 2).
- **Fix:** upgrade bolt/core to a release with PR #3828, then delete the unused `public/thumbs/*_files/` folders. Until then thumbnails keep working, just through PHP.

### Pitfall 3: `public/thumbs/` Directory Permissions
- **Symptom:** Bolt logs `Cannot dump file public/thumbs/... Permission denied`.
- **Cause:** the PHP process (PHP-FPM user, or the hosting account) cannot write to `public/thumbs/`.
- **Fix (server with a shell):**
  ```bash
  mkdir -p public/thumbs
  chmod -R 775 public/thumbs
  chown -R www-data:www-data public/thumbs
  ```
- **Fix (SFTP shared hosting):** PHP runs as the hosting account, which owns the uploaded files, so `chown` is neither possible nor needed. Create `public/thumbs/` in the SFTP client and give it write permission for the owner (`755`; `775` only when the host's panel says PHP runs as a different user). Never upload `public/thumbs/` from a local machine — the server generates its own.

### Pitfall 4: A Replaced Upload Keeps Its Old Version for Two Months
- **Symptom:** an editor replaces `files/logo.png` with a new file under the same name; visitors keep seeing the old one.
- **Cause:** uploads are cached for two months (`access plus 2 months`) and their URL did not change — unlike CSS and JS, they have no `?v=` version.
- **Fix:** upload the new version under a new name (`logo-2026.png`) and pick it in the record. Thumbnails of the old file stay valid for the old URL only.
