---
name: bolt-security-hardening
description: >-
  Use this skill to secure or harden a Bolt CMS 6 website, or to check its security settings:
  a .env that holds every production value including the secret, so an SFTP upload runs on its
  own, and a .env.local for local development only; trusted hosts against
  password-reset poisoning, trusted proxies, disabled /_fragment, isolated short-lived secure
  sessions, login throttling, password policy, Bolt config (upload whitelist, HTML cleaner,
  query search, version disclosure), admin file-editor permissions, security headers and
  Content-Security-Policy through nelmio_security, dependency audits, and live checks against
  the running site.
---

# Bolt CMS Security Hardening

A stock Bolt CMS 6 project is built for getting started, not for production: it trusts every Host
header, keeps sessions for 14 days in a shared folder, lets administrators edit Twig templates in
the browser, accepts `.html`, `.js` and `.svg` uploads and ships a `.env` that says `APP_ENV=dev`.
This skill closes those gaps in the Symfony and Bolt configuration. The neighbouring skills own
the other layers:

| Layer | Skill |
| :--- | :--- |
| `.env` and secrets, Symfony framework, login and passwords, Bolt `config.yaml` and `permissions.yaml`, security headers of pages (nelmio), CSP, deployment, dependency audits | **this skill** |
| Apache: HTTPS redirect, allowlist for `theme/`, `files/`, `thumbs/`, headers of static files | [`bolt-htaccess`](../bolt-htaccess/SKILL.md) |
| REST / GraphQL API and its documentation | [`bolt-disable-api`](../bolt-disable-api/SKILL.md) |
| `sanitise: true` on rich-text fields, no `allow_twig` | [`bolt-contenttypes`](../bolt-contenttypes/SKILL.md) (rule 7) |
| `composer audit` / `npm audit` in the Makefile and CI | [`bolt-code-quality`](../bolt-code-quality/SKILL.md) |

All settings below were tested on a Bolt 6.1 project behind Apache 2.4 + PHP-FPM and Nginx: every
page renders, the admin works, and the probes in *Verification* give the expected results.

### What each step stops

| Attack | Stopped by |
| :--- | :--- |
| Password-reset link pointing to the attacker's domain (forged `Host` header) | Step 1 `SYMFONY_TRUSTED_HOSTS` |
| Debug toolbar / profiler on production, stack traces in error pages | Step 1 `.env` with `APP_ENV=prod`, `APP_DEBUG=0`; `.env.local` never uploaded |
| Forged `/_fragment` requests or remember-me cookies with a leaked `APP_SECRET` | Step 1 fresh secret per project, private repository, rotation; Step 2 fragments off |
| Password guessing on `/bolt/login` | Step 3 throttling, password policy |
| An editor storing scripts in content or uploads (stored XSS) | Step 4 upload whitelist and HTML cleaner, `bolt-contenttypes` rule 7, `bolt-htaccess` allowlist and sandbox |
| A stolen admin password becoming code execution (editing Twig in the browser) | Step 5 permissions |
| Clickjacking, mixed content, injected `<base>` / forms / plugins | Step 6 headers and CSP |
| Known vulnerabilities in Bolt, Symfony or npm packages | Step 8 audits |

---

## Step 1: Environment Files and Secrets (`.env` for production, `.env.local` for local dev)

Sites deployed over SFTP upload the committed `.env` with the code, so that file holds **everything
production needs, including the secret**. The site then runs from an upload alone: there is no
server-side `.env.local` to create, forget or lose. `.env.local` exists only on developer machines
and only switches them to dev mode.

**`.env` (committed, uploaded)** — production values ([`examples/env`](examples/env)):

```dotenv
APP_ENV=prod
APP_DEBUG=0
# Signs sessions, CSRF tokens and remember-me cookies. A new one logs everybody out.
# Generate: php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
APP_SECRET=<64 hex characters>
SYMFONY_TRUSTED_HOSTS='^(www\.)?example\.cz$'
SYMFONY_TRUSTED_PROXIES=
DATABASE_URL=sqlite:///%kernel.project_dir%/var/data/bolt.sqlite
MAILER_DSN=smtp://localhost
BOLT_CANONICAL=https://example.cz
```

Copy [`examples/env`](examples/env) to `.env`, replace `example` with the domain, then fill in a fresh secret:

```bash
php -r '$f=".env"; file_put_contents($f, preg_replace("/^APP_SECRET=.*$/m", "APP_SECRET=".bin2hex(random_bytes(32)), file_get_contents($f), 1));'
```

**`.env.local` (git-ignored, never uploaded)** — local development only ([`examples/env.local`](examples/env.local)):

```dotenv
APP_ENV=dev
APP_DEBUG=1
SYMFONY_TRUSTED_HOSTS=
BOLT_CANONICAL=
```

* **Nothing else in `.env.local`.** No `APP_SECRET` (the one in `.env` works locally too), no production values. Anything that differs only on your machine is fine (`DATABASE_URL` of a local MySQL, a local mail catcher). `verify.sh` warns when `.env.local` overrides `APP_SECRET`.
* **`APP_ENV=dev` together with `APP_DEBUG=1`.** A `.env.local` with `APP_DEBUG=1` but no `APP_ENV=dev` runs prod mode with debug: stack traces for visitors, `X-Robots-Tag: noindex`. That goes unnoticed locally and public once the file is uploaded by mistake. `verify.sh` warns about it.
* **Never upload `.env.local`.** On the server it switches production into dev mode (profiler, stack traces). Exclude it in the SFTP client (Step 7); the live checks (section 8) catch a debug token or a stack trace on production. If one was uploaded, delete it on the server and delete `var/cache/prod/`.
* **`APP_SECRET` empty in `.env`.** Symfony and Bolt refuse to start: HTTP 500, with `A non-empty secret is required` or `The secret for signing cursors must not be empty` (Pagerfanta) in `var/log/prod.log`. `verify.sh` fails on an empty or placeholder secret, so this is caught before the upload.
* **The secret is in git — keep the repository private.** Anyone with access to the repository can forge remember-me cookies and signed URLs (`/_fragment` stays off, Step 2). Generate a fresh secret per project (never copy one from another site or from Bolt's skeleton). Rotate it, by running the command above and committing, when the repository is shared, made public, or someone with access leaves. Every editor is logged out once; nothing else changes.
* **Bolt writes the secret into `.env`.** `bin/console bolt:setup` and `bin/console bolt:reset-secret` put a new `APP_SECRET` into `.env`, which is where it belongs. Commit it; it is a rotation like the one above.
* **Passwords in connection strings** (`MAILER_DSN=smtp://user:password@host`, a `DATABASE_URL` of the host's MySQL) belong in `.env` for the same reason as the secret: the upload must work on its own. The same rule applies: private repository, and change the password at the provider if the repository is ever shared.
* **`SYMFONY_TRUSTED_HOSTS`** is a regular expression of every domain the site answers to (add the staging domain if staging runs with this `.env`). Any other `Host` gets HTTP 400. Without it, a request with `Host: evil.tld` to `/bolt/reset-password` makes Bolt mail a reset link to `https://evil.tld/…` — one click by the admin hands over the token. Bolt's `framework.yaml` already reads the variable (`trusted_hosts: ['%env(default::SYMFONY_TRUSTED_HOSTS)%']`); a project whose `framework.yaml` says `trusted_hosts: ~` must get that line back.
* **Both hosts, one site.** `example.cz` and `www.example.cz` must both answer over valid HTTPS, but only one serves the site — the other redirects to it with 301 (`bolt-htaccess` Step 1, default: without www). `BOLT_CANONICAL` makes every canonical link name that host; empty, Bolt names whichever host was requested, so each page exists twice. Keep both hosts in `SYMFONY_TRUSTED_HOSTS`. The live checks (`verify.sh`, section 8) always test both.
* **`TRUSTED_PROXIES`** (Bolt's sample `.env`) is read by nothing in Symfony 6.4; delete it. `SYMFONY_TRUSTED_PROXIES` is wired up in Step 2.
* **`/.env` must never be downloadable** — it now holds the secret. The `bolt-htaccess` deny list answers 403 for `.env*` everywhere; `verify.sh` section 8 requests `/.env` on production.
* **`.env.local.php`** (`composer dump-env prod`) overrides every `.env*` file. Do not upload one generated on a developer machine.

---

## Step 2: Symfony Framework (`config/packages/security_hardening.yaml`)

Copy [`examples/security_hardening.yaml`](examples/security_hardening.yaml) to
`config/packages/security_hardening.yaml`. It loads after `framework.yaml` and overrides it, so the
stock file stays as Bolt ships it:

| Setting | Why |
| :--- | :--- |
| `trusted_proxies: '%env(default::SYMFONY_TRUSTED_PROXIES)%'` | Behind a TLS-terminating proxy, the proxy's IP would otherwise be every visitor's IP: login throttling would lock everyone out at once, and the user list in the admin would show only the proxy. Empty = no proxy. |
| `trusted_headers` without `x-forwarded-host` | A proxy request can never change the host used in absolute URLs. |
| `esi` and `fragments` disabled | Bolt uses neither; `/_fragment` disappears (404). |
| `validation.mapping.paths` | Loads the password policy of Step 3. |
| `when@prod` session: `handler_id: session.handler.native_file`, `save_path: var/sessions/prod`, `gc_*` | Sessions in the project's own folder instead of the host's shared one, with working garbage collection. |
| `cookie_secure: true`, `cookie_httponly: true`, `cookie_samesite: lax` | The session cookie only travels over HTTPS and is invisible to scripts. `auto` would drop the secure flag behind an untrusted proxy. |
| `cookie_lifetime: 28800` | 8 hours instead of 14 days. The cookie survives closing the browser for those 8 hours; `0` would end the session with the browser (remember-me still keeps editors who ask for it logged in). |

> [!WARNING]
> Do **not** put `trusted_hosts` into this file. Lists from several config files are merged, not
> replaced: `framework.yaml`'s env entry stays in the list, and when the variable is empty it
> matches every host. Use the environment variable (Step 1).

---

## Step 3: Login and Accounts

### 3a. Login throttling (`config/packages/security.yaml`)

Bolt 6 has `login_throttling: ~` (5 attempts per minute); Bolt 5 projects have none. In the `main`
firewall:

```yaml
    main:
      # …
      login_throttling:
        max_attempts: 5
        interval: '15 minutes'
```

The sixth wrong password for a username from one IP shows "Too many failed login attempts, please
try again in 15 minutes" (translated). Edit `security.yaml` directly — firewalls cannot be
overridden from a second file.

### 3b. Remember-me lifetime (`config/services.yaml`)

```yaml
parameters:
  bolt.remember_lifetime: 604800 # 7 days instead of 30
```

### 3c. Password policy (`config/validator/user.yaml`)

Copy [`examples/validator/user.yaml`](examples/validator/user.yaml). It adds, on top of Bolt's
6-character minimum: at least 12 characters, a medium `PasswordStrength` score and
`NotCompromisedPassword` (Have I Been Pwned; only 5 characters of the password's SHA-1 hash leave
the server; `skipOnError` keeps saving possible on hosts that block outgoing HTTPS). It applies to
adding and editing users in the admin (also the own profile) and to `bin/console bolt:add-user`.
The "forgotten password" form has its own 6-character rule in Bolt core and is not covered.

### 3d. Reset-password notice (`config/bolt/config.yaml`)

`reset_password_settings.show_already_requested_password_notice: false` — `true` tells a visitor
that a reset was already requested for an address, i.e. that the address has an account. Set
`mail_from` to an address on the site's own domain.

---

## Step 4: Bolt Configuration (`config/bolt/config.yaml`)

Merge [`examples/config_snippet.yaml`](examples/config_snippet.yaml):

| Key | Value | Why |
| :--- | :--- | :--- |
| `canonical` | `'%env(default::BOLT_CANONICAL)%'` | Without the key `BOLT_CANONICAL` (Step 1) is ignored. Bolt's sample config ships it; older projects have it commented out. |
| `headers.powered_by`, `omit_meta_generator_tag` | `false`, `true` | No `X-Powered-By: Bolt`, no `<meta name="generator">`: scanners do not learn the CMS. |
| `query_search.enable` | `false` | Otherwise any listing filters by any field (`/entries?title--like=a`) — fields the templates never show can be read one guess at a time. Keep it on only when a listing page filters through the query string. |
| `htmlcleaner.allowed_tags` | without `iframe` | Its `src` is not filtered (also `javascript:`); embeds use `_consent-embed.twig` (`bolt-cookie-consent`). Remove `frameborder`, `allowfullscreen`, `scrolling` from `allowed_attributes` with it. |
| `htmlcleaner.allowed_attributes` | as in the example | Trade-off to know: `style` lets an editor position content over the page (a fake login box inside trusted content); `id` and `name` can shadow global names that scripts read (DOM clobbering). Redactor uses `style` for alignment and image sizes, so the example keeps all three. Drop `style` when the theme styles alignment through classes; drop `id` / `name` when no anchors are set in content. |
| `accept_file_types` | no `html`, `js`, `css`, `scss`, `twig`, `yaml`, `svg` | Uploads are served from the site's origin (stored XSS); the file editor (Step 5) can only save these extensions. |
| `accept_media_types` | no `svg` | The Redactor / Article upload buttons accept these without cleaning SVGs. |
| `curl_options.verify_peer` | `true` | Bolt's sample config sets `false` (oEmbed fetches without TLS checks). |
| `reset_password_settings` | Step 3d | |

The HTML cleaner only runs on fields with `sanitise: true` — `bolt-contenttypes` rule 7 sets it on
every `redactor`, `article` and `html` field (Bolt does not do that by default for Redactor and
Article). On a real project the only visible changes were: `×` in thumbnail URLs percent-encoded
(still valid), Redactor's internal `data-image` attribute removed, and an image without `alt`
getting its file name as `alt` — fill alternative texts in the editor. A site that keeps
`iframe` in `allowed_tags` (trusted editors only) loses `allowfullscreen` on embedded videos — the
cleaner does not know the attribute on iframes. The template can add it back to the cleaned HTML:
`{{ record.body|replace({'<iframe ': '<iframe allowfullscreen '})|raw }}`.

---

## Step 5: Permissions (`config/bolt/permissions.yaml`)

Merge [`examples/permissions_snippet.yaml`](examples/permissions_snippet.yaml):

```yaml
assignable_roles: [ ROLE_ADMIN, ROLE_CHIEF_EDITOR, ROLE_EDITOR, ROLE_USER ]

global:
  managefiles:config: []
  managefiles:themes: []
  list_files:config: []
  list_files:themes: []
```

* With `managefiles:themes`, an administrator edits Twig templates in the browser; Twig runs on the server, so a phished admin password becomes control of the whole site. Configuration and templates are deployed with the code. The media library (`managefiles:files`, `list_files:files`) stays for editors.
* `ROLE_DEVELOPER` can switch into any account, `ROLE_WEBSERVICE` writes through the API — neither belongs in the role picker. Existing accounts keep their roles.
* The API permissions (`api:*`, `api_admin`) are handled by `bolt-disable-api`.

---

## Step 6: Security Headers and Content-Security-Policy

Every Bolt project contains NelmioSecurityBundle (`bolt/project`), which already sends
`X-Frame-Options: DENY`, `nosniff` and a referrer policy with every page. Replace
`config/packages/nelmio_security.yaml` with [`examples/nelmio_security.yaml`](examples/nelmio_security.yaml):

* removes the deprecated `X-XSS-Protection` header;
* adds `Permissions-Policy` (no camera, microphone, geolocation, payment, USB);
* adds an **enforced baseline CSP** for the whole site including the admin:
  `object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests`.
  It restricts no scripts, styles or images, so nothing breaks — it blocks plugins, `<base>`
  hijacking, forms posting elsewhere and framing. A form that posts to an external service
  (newsletter, payment gateway) needs that host in `form-action`.

HSTS and the headers of static files come from `public/.htaccess` (`bolt-htaccess`). Do **not** use
nelmio's `forced_ssl`: behind a TLS proxy whose IP is not trusted it redirects in a loop.

### 6b. Optional: strict CSP for the public site

A strict policy (scripts only from listed hosts) is the strongest protection against injected
scripts, but every tracker and embed must be listed. Introduce it in two stages:

1. **Report-Only.** Add the route from [`examples/routes_snippet.yaml`](examples/routes_snippet.yaml)
   at the top of `config/routes.yaml`, uncomment the `report:` and `report_endpoint:` blocks of the
   example, deploy, and browse the site (with consent given and refused). Nothing changes for
   visitors; violations appear in `var/log/prod.log` as
   `app.ERROR: Content-Security-Policy Violation Reported`. Add the hosts they name. Reports from
   `/bolt/…` pages are admin noise — ignore them. Starting points for the trackers of
   `bolt-cookie-consent`:

   | Service | Directives |
   | :--- | :--- |
   | GA4 / gtag | `script-src https://www.googletagmanager.com`; `connect-src https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com`; `img-src https://*.google-analytics.com https://*.googletagmanager.com` |
   | Google Ads | `script-src https://www.googleadservices.com https://googleads.g.doubleclick.net`; `img-src https://www.google.com https://www.google.cz https://googleads.g.doubleclick.net`; `frame-src https://td.doubleclick.net` |
   | Sklik | `script-src https://c.seznam.cz`; `connect-src https://c.seznam.cz` |
   | Meta Pixel | `script-src https://connect.facebook.net`; `img-src https://www.facebook.com`; `connect-src https://www.facebook.com` |
   | YouTube / Google Maps embeds | `frame-src https://www.youtube-nocookie.com https://www.google.com` |

2. **Enforce on the public site only.** When the log stays clean for a while, move the directives
   from `report:` to `enforce:` and limit the CSP to non-admin paths, because the Bolt admin needs
   inline scripts:

   ```yaml
   # config/services.yaml
   services:
     app.csp_frontend_matcher:
       class: Symfony\Component\HttpFoundation\RequestMatcher\PathRequestMatcher
       arguments: [ '^/(?!([a-z]{2}(_[A-Z]{2})?/)?bolt(/|$))' ]
   ```
   ```yaml
   # config/packages/nelmio_security.yaml
   nelmio_security:
     csp:
       request_matcher: app.csp_frontend_matcher
   ```
   The admin then has no CSP; `X-Frame-Options: DENY` still protects it. Change `bolt` in the
   pattern if `bolt.backend_url` differs.

**Inline scripts under the strict policy.** `script-src 'self'` blocks every inline `<script>`. The
skills ship none (`bolt-cookie-consent` prints its configuration as JSON and runs from `app.js`),
so the policy works as is. When a project must add one — a vendor snippet that cannot be loaded
as a file — give it nelmio's per-request nonce instead of allowing `'unsafe-inline'`:

```twig
<script nonce="{{ csp_nonce('script') }}">…</script>
```

nelmio adds the matching `'nonce-…'` to `script-src` for that response. A tracker held back as
`<script type="text/plain" data-consent-category="…">` keeps the attribute, and
`cookie-consent.ts` copies the nonce to the script it creates on consent. Styles: the strict
policy allows `'unsafe-inline'` for `style-src`, which the inline `<style>` of the helper pages
and Redactor's inline styles need.

---

## Step 7: Deployment over SFTP

| Never upload | Why |
| :--- | :--- |
| `.env.local` | Local development only: on the server it switches production into dev mode (Step 1). |
| `var/` | The live SQLite database (`var/data/`), sessions, logs and cache would be overwritten. |
| `public/files/`, `public/thumbs/` | Editors' uploads live only on the server. |
| `.git/`, `node_modules/`, `public/theme/*/node_modules/`, `.idea/`, `tests/`, `var/bolt-audit/`, `var/bolt-build/` | Not needed at runtime; `bolt-htaccess` blocks them, but they should not be there. |

* **Exclude these paths in the SFTP client** (PhpStorm: *Settings → Deployment → Excluded Paths*).
* **Document root.** If the host lets you point the domain at `public/`, do it; otherwise the root `.htaccess` of `bolt-htaccess` forwards into `public/`. Check that `/.env`, `/composer.json` and `/var/data/bolt.sqlite` answer 403 or 404 (verify.sh does).
* **Dependencies.** Prefer uploading a `vendor/` built with `composer install --no-dev --optimize-autoloader` (`make install_prod`), then restore the dev tools locally with `composer install`. With `APP_ENV=prod` the dev bundles are not loaded even if they are uploaded.
* **After every upload** delete `var/cache/prod/` on the server (or run `bin/console cache:clear` where SSH exists) — config changes, including everything in this skill, take effect only then.
* **PHP settings** in the host's panel: `display_errors` off, `expose_php` off, a supported PHP version (8.2+). `.htaccess` hides `X-Powered-By` anyway.

---

## Step 8: Dependencies and Updates

```bash
composer audit                                  # advisories for Bolt, Symfony and every PHP package
(cd public/theme/<theme> && npm audit --omit=dev)
composer outdated 'bolt/*'                      # Bolt releases security fixes in minor versions
```

`bolt-code-quality` adds both audits as `make audit` and as a CI job. Bolt 5 projects should move to
Bolt 6: the skills target 6, and Bolt 5's `security.yaml` has no login throttling at all.

---

## Step 9: Optional Extras

* **Restrict the admin by IP or HTTP basic auth** (sites edited from a fixed office IP). In `public/.htaccess`, before the rewrite block:
  ```apache
  <If "%{REQUEST_URI} =~ m#^(/public)?(/[a-z]{2})?/bolt(/|$)#">
      Require ip 203.0.113.10
  </If>
  ```
  For basic auth use `AuthType Basic` with an `AuthUserFile` outside `public/` (the absolute path comes from the host).
* **Another admin path** (`bolt.backend_url: /spravce` in `config/services.yaml`) only cuts bot noise; it is not protection. Update the CSP matcher and the `<If>` above with it.
* **Two-factor authentication** is not covered: Bolt's custom login authenticator needs integration work with `scheb/2fa-bundle`.
* **Docker / Nginx:** [`examples/docker/nginx_security.conf`](examples/docker/nginx_security.conf) mirrors the Apache allowlist and headers (mind the `add_header` inheritance note in it); [`examples/docker/php_security.ini`](examples/docker/php_security.ini) goes into `docker/php/conf.d/bolt.prod.ini`.

---

## Verification

```bash
BOLT_BASE_URL=https://staging.example.cz bash vendor/tomvondracek/bolt-skills/skills/bolt-security-hardening/scripts/verify.sh
```

Without a reachable `BOLT_BASE_URL` only the file checks run.

| # | Checks | Fails when |
| :- | :--- | :--- |
| 1 | `.env`, `.env.local`, `.env.local.php` | `.env` says `APP_ENV=dev` / `APP_DEBUG=1`, `APP_SECRET` in `.env` is empty or a placeholder, `.env.local` is tracked (warnings: `.env.local` overrides `APP_SECRET`, or sets `APP_DEBUG=1` without `APP_ENV=dev`) |
| 2 | Framework config (all `config/packages/*.yaml` merged for prod) | `trusted_hosts: ~`, fragments / ESI on, session cookie not secure |
| 3 | `security.yaml`, remember-me lifetime, password policy | no `login_throttling` |
| 4 | Bolt `config.yaml` | dangerous upload types (`html`, `js`, `twig`, `php`, …), `verify_peer: false` |
| 5 | `permissions.yaml` | — (warnings: file editor for config / themes, developer role assignable) |
| 6 | `nelmio_security.yaml` | bundle missing or no clickjacking protection |
| 7 | Dependencies (`composer audit`, Bolt major version) | — (warnings) |
| 8 | Live, on **both** the bare domain and `www` (derived from `BOLT_BASE_URL`): valid certificate, HTTP → HTTPS redirect, HSTS, exactly one host serving the site; then on every serving host: foreign `Host` header, profiler, debug token, stack traces in a 404, `/.env` and friends, headers of a page and of an upload, cookie flags, `/_fragment` | a host without a valid certificate, plain HTTP not redirected, foreign host answers 200, profiler / debug token / stack trace visible, a secret file downloadable, no clickjacking protection |

Warnings (generator tag, query search, CSP missing, …) are hardening that is still open; each line
says the fix.

---

## Common Pitfalls

* **Only one host checked.** `www.example.cz` is easily forgotten: no certificate, no redirect, or a second copy of the site. `verify.sh` derives the other host from `BOLT_BASE_URL` and checks both (a missing DNS record is a warning, an invalid certificate a failure).
* **Trusted hosts in a second config file.** Merged into the env entry, which trusts everything when the variable is empty — use `SYMFONY_TRUSTED_HOSTS` (Step 1).
* **`bolt:setup` / `bolt:reset-secret` changed `APP_SECRET` in `.env`.** That is a rotation: commit it, and everyone is logged out once (Step 1).
* **Site answers 500 after an upload.** `A non-empty secret is required` / `The secret for signing cursors must not be empty` → `APP_SECRET` in `.env` is empty (Step 1). `Untrusted Host` (400) → the domain is missing from `SYMFONY_TRUSTED_HOSTS`.
* **The site only works when `.env.local` is uploaded too.** Then `.env` is missing a production value (usually the secret) and the uploaded `.env.local` runs the server with debug on. Move the value into `.env`, delete `.env.local` on the server (Step 1).
* **Everyone is locked out after a few failed logins.** The site is behind a proxy whose IP is not in `SYMFONY_TRUSTED_PROXIES`: all visitors share the proxy's IP. Check the user list in the admin — "last IP" shows the proxy.
* **Never trust `REMOTE_ADDR` as a proxy** unless a proxy really is in front: every visitor could then set `X-Forwarded-For` and dodge the throttling.
* **Configuration changes have no effect** on an SFTP host until `var/cache/prod/` is deleted.
* **Redirect loop after enabling HTTPS in Symfony** — nelmio `forced_ssl` behind a TLS proxy. HTTPS is redirected by `.htaccess`; leave `forced_ssl` out.
* **CSP reports about Google Tag Manager never appear** — nelmio's domain filter drops them; `report_endpoint.filters.domains: false` (the example sets it).
* **A newsletter form stops submitting** — its external action URL is missing from `form-action`.
