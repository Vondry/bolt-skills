---
name: bolt-asset-caching
description: >-
  Use this skill whenever setting up, optimizing, or debugging client/CDN HTTP caching
  for Bolt CMS images, thumbnails, CSS, JS, and PDFs. Resolves the critical Symfony
  SessionListener bug where stateful firewalls rewrite League Glide's public 1-year
  thumbnail cache to private/no-cache, configures Bolt's save_files thumbnail disk dump,
  sets up Apache mod_expires and Nginx static expires rules, and establishes frontend
  asset cache-busting (?v=X.X).
---

# Bolt CMS Full-Stack Asset & Thumbnail Caching

In Bolt CMS websites, media files, thumbnails, and compiled stylesheets/scripts account for the vast majority of HTTP requests and bandwidth. Without end-to-end caching configuration across Symfony, Bolt core, and the web server (Apache/Nginx), browsers will re-download assets on every visit, degrading Core Web Vitals and overloading PHP-FPM.

This skill documents the complete multi-layer asset caching architecture established across production Bolt CMS repositories.

---

## 1. The Core Root Cause: The Symfony Thumbnail Cache Destruction Bug

### Why Thumbnails Were Not Being Cached:
1. **Glide's Intended Behavior:**
   Bolt CMS dynamically generates manipulated thumbnails on demand via `Bolt\Controller\ImageController` using **League Glide**. Under the hood, Glide sets optimal public HTTP cache headers:
   ```http
   Cache-Control: public, max-age=31536000
   ETag: "..."
   ```
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

* **TTL Rationale:** A 2-month window (`access plus 2 months`) provides maximum cache hit rates while dropping `must-revalidate`, allowing browsers to serve assets instantly from disk cache.
* **JavaScript MIME types:** current Apache `mime.types` serve `.js` as `text/javascript`; older ones as `application/javascript`. List both, otherwise scripts get no expiry header on newer servers.

---

### Step 4: Configure Nginx Static Expiration (`docker/nginx/conf.d/default.conf`)
File: `docker/nginx/conf.d/default.conf`

Ensure both the `/thumbs` location and the generic static asset regex block define aggressive expiration:

```nginx
# Generated thumbnail images
location ^~ /thumbs {
    try_files                     $uri /index.php?$query_string;

    access_log                    off;
    log_not_found                 off;
    expires                       2M;
    add_header                    Pragma public;
    add_header                    Cache-Control "public";
}

# Don't log, and do cache, asset files
location ~* ^.+\.(?:atom|avif|bmp|bz2|css|doc|eot|exe|gif|gz|ico|jpe?g|jpeg|jpg|js|map|mid|midi|mp4|ogg|ogv|otf|pdf|png|ppt|rar|rtf|svg|svgz|tar|tgz|ttf|wav|webp|woff|woff2|xls|zip)$ {
    access_log                    off;
    log_not_found                 off;
    expires                       2M;
    add_header                    Pragma public;
    add_header                    Cache-Control "public";
}
```

* **`try_files $uri /index.php?$query_string;`**: Checks if the thumbnail already exists on disk in `public/thumbs/`. If yes, serves it statically. If not, passes to Symfony's front controller to generate it.

---

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
3. `public/.htaccess` has `mod_expires.c` with image expiration rules; warns when JavaScript is listed only as `application/javascript` (without `text/javascript`) or when more than one `mod_expires` block exists.
4. `docker/nginx/conf.d/default.conf` (if present) has `expires` and `try_files` for `/thumbs`.
5. Performs live HTTP curl inspection on `/thumbs/...` and static assets to assert `Cache-Control: public` and absence of `private, max-age=0`.

### 2. Manual HTTP Header Inspection
Test live response headers using `curl -I`:

```bash
# 1. Test thumbnail headers (must NOT contain "private, max-age=0")
curl -I https://example.com/thumbs/320x240/foto/hero.webp

# Expected Headers:
# HTTP/2 200
# cache-control: public, max-age=...
# pragma: public

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

### Pitfall 2: `public/thumbs/` Directory Permissions
- **Symptom:** Bolt logs `Cannot dump file public/thumbs/... Permission denied`.
- **Cause:** Web server user (`www-data` or PHP-FPM user) lacks write permissions to `public/thumbs/`.
- **Fix:** Ensure directory permissions match `config/bolt/config.yaml`:
  ```bash
  mkdir -p public/thumbs
  chmod -R 775 public/thumbs
  chown -R www-data:www-data public/thumbs
  ```
