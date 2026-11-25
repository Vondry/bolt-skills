---
name: bolt-auth-screens
description: >-
  Replaces Bolt CMS 6's stock sign-in screens — login (/bolt/login), password reset request,
  "link sent" and set new password — with one premium layout shared by every project: a brand
  panel in the site's colours with its logo and a faint watermark, and a calm form side in
  Instrument Serif / Sans. A project changes only seven colours, its badge logo and the watermark
  in theme.yaml (bolt_auth); the templates stay identical across projects. At least as secure as
  Bolt's own screens and hardened beyond them: per-IP rate limits on the reset flow, a strict
  per-route Content-Security-Policy with nonce and Trusted Types, no-store / no-referrer / COOP
  headers, the admin password policy on the reset form, no |raw or inline script. Includes colour
  derivation with WCAG contrast checks, self-hosted fonts, inline icons (no CDN), a preview of
  every state and verification. Use it when building a site (Phase 6) or when asked to brand,
  redesign, customise or secure the Bolt login / admin sign-in pages.
---

# Bolt CMS Sign-in Screens

Bolt's own login and password-reset screens show the Bolt logo on a stock background. This skill
gives every project the same sign-in template — same layout, type, spacing, motion and details —
and lets each project change **only its identity**:

| The project changes (`theme.yaml` → `bolt_auth`) | Everything else is shared (`bolt-auth/` templates) |
| :--- | :--- |
| `brand_deep` — the panel base | Two-half layout, 760 px breakpoint (panel becomes a 248 px header) |
| `brand`, `brand_2` — the two glows | Instrument Serif for the site name and title, Instrument Sans for the rest |
| `accent`, `accent_hover`, `on_accent` — the button | Dot texture, glow positions, badge, rule, spacing, radii, shadows |
| `accent_line` — the checkbox | Form, focus halo, alerts, password reveal, hover motion |
| `logo` (+ size) — the white badge | Every string: Bolt's own translation keys |
| `mark` — the watermark symbol, or none | Neutral surface, ink, muted, line, danger and success colours |
| `sitename`, `domain`, `favicon` — optional overrides | |

Never edit the copied templates for one project. A change that one project needs is a change to
this skill, so every project gets it; `verify.sh` warns when a project's copy drifts.

---

## How Bolt Picks the Templates

`Bolt\TemplateChooser` looks for each screen in the theme's `theme.yaml` first, then in
`config/bolt/config.yaml`, then falls back to `@bolt/…`. The screens are rendered by Bolt's own
controllers, so routes, forms, CSRF, throttling and the reset flow stay Bolt's — only the markup
changes. No vendor override and no `templates/bundles/` copy is needed.

| Screen | Route (`%bolt.backend_url%` = `/bolt` by default) | `theme.yaml` key | Template | Variables from Bolt |
| :--- | :--- | :--- | :--- | :--- |
| Login | `/bolt/login` | `login_template` | `bolt-auth/login.twig` | `loginForm`, `error` |
| Reset request | `/bolt/reset-password` | `reset_password_settings.request_template` | `bolt-auth/reset-request.twig` | `requestForm` |
| Link sent | `/bolt/reset-password/check-email` | `reset_password_settings.check_email_template` | `bolt-auth/check-email.twig` | `tokenLifetime` |
| New password | `/bolt/reset-password/reset/{token}` | `reset_password_settings.reset_template` | `bolt-auth/reset.twig` | `resetForm` |

The `theme.yaml` key `reset_password_settings` holds only the three templates; the mail settings
stay under the same key in `config/bolt/config.yaml`.

---

## Security Model

The screens replace the most attacked page of the site, so the rule is: **nothing Bolt's own
screens do may be lost, and every gap they leave is closed**. The templates change markup only;
authentication, CSRF and the reset flow stay in Bolt's controllers. The security layer
([`examples/src/`](examples/src/), [`examples/config/bolt_auth.yaml`](examples/config/bolt_auth.yaml))
adds the rest.

| Threat | Protection | Where |
| :--- | :--- | :--- |
| Password guessing on the login | 5 attempts per 15 min per username + IP, 25 per IP (Symfony's default limiter); the screen shows Bolt's "too many attempts" message | `login_throttling` (`bolt-security-hardening` 3a) |
| Bots on the login | captcha / 2FA extensions render in the kept `login_top`, `login_middle`, `login_bottom` slots | templates |
| E-mail bombing, probing many addresses through the reset request | 5 POSTs per 15 min and IP → 303 back with „Příliš mnoho požadavků…“ and `Retry-After`; Bolt adds 1 e-mail per account and hour | `BoltAuthSecuritySubscriber`, rate limiter `bolt_auth_reset_request` |
| Guessing reset tokens | 10 opened links / submitted passwords per 15 min and IP; tokens expire after 1 h | rate limiter `bolt_auth_reset_password`, `reset_password.yaml` |
| Account enumeration | the same "link sent" screen for every address; `show_already_requested_password_notice: false` | Bolt, `bolt-security-hardening` 3d |
| Reset link pointing at a foreign host (Host-header poisoning) | `framework.trusted_hosts` from `SYMFONY_TRUSTED_HOSTS` | `bolt-security-hardening` 2 |
| Weak password set through the reset link (Bolt core allows 6 characters) | the admin policy on the new password: ≥ 12 characters, medium `PasswordStrength`, `NotCompromisedPassword`; `minlength` and `passwordrules` hints for password managers | `BoltAuthPasswordPolicyExtension` |
| CSRF | Bolt's tokens on every form (`form_end`), checked by the verification | templates |
| XSS, injected scripts or styles, DOM XSS | per-route CSP `default-src 'none'`, `script-src 'self'`, `style-src 'self' 'nonce-…'` (only the one `<style>`), `base-uri 'none'`, `form-action 'self'`, `require-trusted-types-for 'script'` (without kernel.debug); templates without `|raw`, inline script, event handler or `style=`; `theme.yaml` values printed into CSS only as `#hex`, whole numbers or plain theme paths | subscriber, templates |
| Clickjacking, cross-window attacks | `frame-ancestors 'none'`, `X-Frame-Options: DENY`, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin` | subscriber (+ nelmio) |
| Tokens, last username or flashes stored by a cache or the back button | `Cache-Control: no-store, private` | subscriber |
| The reset URL leaking through `Referer` | `Referrer-Policy: no-referrer`; Bolt moves the token from the URL into the session at once | subscriber, Bolt |
| A password shown or kept in clear text | the field is always `type="password"` without a value (Bolt's login field type would render a text input under a plain form theme); a revealed password is hidden again before submit and on `pagehide` | `_macros.twig`, `js/bolt-auth.js` |
| Third-party requests (IP leak, supply chain) | no CDN, no Google Fonts: fonts, icons and script come from the site | templates |
| Indexing | `noindex, nofollow` meta and `X-Robots-Tag` | layout, subscriber |
| Session cookie theft | `HttpOnly`, `SameSite=Lax`, `Secure` on HTTPS | Symfony session config (`bolt-security-hardening` 2), checked live |

**Known limit (upstream).** Bolt sends the reset e-mail synchronously and only when the address has
an account, so the response time of the request can hint whether an address exists. The per-IP
limit keeps this slow; the fix belongs in bolt/core (send through Messenger, or answer before
sending).

---

## Files

```text
public/theme/<theme>/
├── bolt-auth/                      shared — identical in every project (scaffold.sh copies them)
│   ├── _layout.twig                standalone page: brand panel + form side, no master layout, no setcontent
│   ├── _styles.twig                every style, inline; prints the bolt_auth values into :root
│   ├── _macros.twig                icon() (Font Awesome 5.15.4 solid, inline SVG), alert(), password(), errors()
│   ├── login.twig
│   ├── reset-request.twig
│   ├── check-email.twig
│   └── reset.twig
├── js/bolt-auth.js                 password reveal (static file, no build step)
├── css/fonts/instrument/           Instrument Sans (variable 400–700) and Serif, latin + latin-ext, OFL
├── img/<logo>, img/<mark>          the project's own files
└── theme.yaml                      template wiring + bolt_auth
src/
├── BoltAuthSecuritySubscriber.php      rate limits, nonce, strict headers on the four screens
└── BoltAuthPasswordPolicyExtension.php password policy on Bolt's ChangePasswordFormType
config/packages/bolt_auth.yaml          the two rate limiters, the minimum length, Trusted Types policies
```

Why it is built this way:

- **Standalone layout.** The sign-in must work whatever the theme does — no header, menu,
  `setcontent` or site CSS bundle. Bolt's admin CSS is not loaded either.
- **Inline styles, nothing in the bundle.** Like the helper pages, the screens add nothing to the
  site's `css/index.css`, and an inline `<style>` cannot 404. `@source not "../../bolt-auth"` keeps
  Tailwind from scanning them.
- **Self-hosted fonts and inline icons.** No Google Fonts or CDN request (no visitor IP sent to a
  third party, no CSP exception). Latin-ext keeps Czech diacritics in the real face.
- **External script for the reveal button.** It works under a strict `script-src 'self'`. The
  button starts `hidden`, so without JavaScript nothing is offered that does not work.
- **`noindex, nofollow`** on every screen.

---

## Step 1: Gather the Project's Identity

From the site's design tokens (`bolt-tailwind-theme`, `@theme` in `css/tailwind/index.css`) and
its logo files. Never invent colours: every value is a colour the site already uses.

| Value | Rule |
| :--- | :--- |
| `brand_deep` | The site's own **darkest** colour (dark sections, footer, body ink). White text on it must reach 7:1; the 70 % white domain link needs 4.5:1. |
| `brand` | The colour people know the project by. Used only as the top-right glow and the short rule — never for text. |
| `brand_2` | A supporting colour of the same site (a second brand colour, a tint, a slate). Quiet bottom-left glow — never text. |
| `accent` | The fill of the site's **primary button**. Usually equal to `brand`; when the brand colour is too light for a button, the site's darker button colour. |
| `accent_hover` | The site's own hover colour of that button. Only when it has none, `colors` derives one (12 % darker). |
| `on_accent` | Derived: white when it holds 4.5:1 on both button colours, else dark (the site's `brand_deep`, else near-black) — the way sites with light orange or gold buttons do it. |
| `accent_line` | Derived: `accent`; when that is under 3:1 on white, `accent_hover`; when that is too, a darker shade. The checkbox stays white with this border and tick — never a filled box. |
| `logo` | The **dark / colour** version of the logo: it sits on a white badge. SVG preferred, else a transparent PNG / WebP. Never the white variant. |
| `logo_width`, `logo_height` | The logo's size in the badge on desktop, in px: height 40–49 px for a symbol or stacked logo, ~24–44 px for a wide wordmark (width up to ~240 px). Phones use 78 %. |
| `mark` | A **symbol from the logo** (the pictogram, the monogram, an initial block) for the huge 6 % white watermark — a file with transparency, used only as a mask. A pure wordmark without a symbol gets `~` (no watermark). The whole logo works when it is itself a symbol. |
| `sitename` | `~` uses `general/sitename`. Set it only when the config name is not the public name. |
| `domain` | `~` uses the request host (the back-to-site link). Set it to show the production domain everywhere. |
| `favicon` | `~` uses Bolt's admin favicon; set a theme file (e.g. `img/favicon/favicon-32x32.png`) to show the site's. |

Copy the logo and the mark into the theme's `img/` (the `bolt-htaccess` allowlist serves `img/`).

---

## Step 2: Derive and Check the Colours

```bash
php $SKILLS/bolt-auth-screens/scripts/auth-screens.php colors \
    --brand-deep=#… --brand=#… --brand-2=#… --accent=#… [--accent-hover=#…]
```

It derives `on_accent` and `accent_line` (and `accent_hover` when not given), checks every
contrast the design relies on and prints the seven lines for `theme.yaml`. A ✗ means the choice
does not work: take a darker `brand_deep`, or the site's darker button colour as `accent`.

---

## Step 3: Scaffold

```bash
bash $SKILLS/bolt-auth-screens/scripts/scaffold.sh \
    --brand-deep=#… --brand=#… --brand-2=#… --accent=#… [--accent-hover=#…] \
    --logo=img/<logo>.svg --logo-size=<W>x<H> --mark=img/<mark>.svg|none
```

| Change | Detail |
| :--- | :--- |
| `bolt-auth/*.twig`, `js/bolt-auth.js`, `css/fonts/instrument/` | Copied from [`examples/`](examples/); existing files are kept |
| `theme.yaml` | `login_template`, `reset_password_settings` and `bolt_auth` appended ([`examples/theme.yaml`](examples/theme.yaml)); kept when present |
| `src/BoltAuthSecuritySubscriber.php`, `src/BoltAuthPasswordPolicyExtension.php`, `config/packages/bolt_auth.yaml` | The security layer ([`examples/src/`](examples/src/), [`examples/config/bolt_auth.yaml`](examples/config/bolt_auth.yaml)); autowired from `src/`, they pass ECS and PHPStan level max (`bolt-code-quality`). With `tomvondracek/bolt-altcha` installed, `bolt_auth.trusted_types` gets its `svelte-trusted-html` policy |
| `css/tailwind/index.css` | `@source not "../../bolt-auth";` after the other `@source` rules |
| `translations/messages.<locale>.xlf` | `bolt_auth.show_password`, `bolt_auth.hide_password`, `bolt_auth.too_many_requests` merged (cs, en); other locales: merge the English catalog and translate the three targets |

Without the colour options the block is written with `'#…'` placeholders, which `verify.sh`
reports until Step 2's values are filled in. `--update` replaces the shared files with the skill's
current version (after a skill upgrade) and never touches `theme.yaml`.

Then `php bin/console cache:clear`. `symfony/rate-limiter` must be installed (it is with Bolt 6's
login throttling; the scaffold says so when it is not). Bump `assets_version` only when
`js/bolt-auth.js` changed.

Prerequisites from `bolt-security-hardening` that the screens rely on — the verification checks
them: `login_throttling` on the `main` firewall (Step 3a), `framework.trusted_hosts` with
`SYMFONY_TRUSTED_HOSTS` (Step 2), `show_already_requested_password_notice: false` (Step 3d), the
user password policy whose minimum length `bolt_auth.password_min_length` repeats (Step 3c).

**Extensions in the login form.** The screens' policy allows only the site's own files. An
extension whose widget loads its scripts, workers and styles from the site works as is (the ALTCHA
captcha of `tomvondracek/bolt-altcha` does, with its Trusted Types policy in
`bolt_auth.trusted_types`). One that needs a foreign host does not belong on the login.

---

## Step 4: Keep Bolt's Behaviour and the Security Rules (what the templates already do)

These rules are why the templates must not be rewritten per project:

- **Forms through Symfony.** Fields are rendered with `form_widget()` under
  `form_theme … with ['form_div_layout.html.twig'] only`, so names, ids, `required`, the last
  username and the CSRF token (`form_end`) stay Bolt's.
- **Extension slots.** `widgets('login_top')`, `widgets('login_middle')`, `widgets('login_bottom')`
  stay in the login form — captcha and 2FA extensions render there.
- **Messages.** The authentication error (`error.messageKey|trans(…, 'security')`), the
  `reset_password_success` flash on the login, the `reset_password_error` flash on the reset request
  and any other flash render as `ba-alert` — always icon plus words, never colour alone.
- **Remember me.** Checked by default, with Bolt's `label.remembermeduration` and its duration;
  a hidden field when the remember-me lifetime is 0.
- **New password.** Both fields get the reveal button; one error line under the fields; only the
  field at fault is marked (the repeat field when the passwords differ — Bolt maps that error onto
  the first field — the new password for every other message).
- **Strings.** Every visible string is Bolt's own translation key, so the screens follow the
  editor's admin language: `title.login`, `label.username_or_email`, `label.password`,
  `login.forgotpassword`, `action.log_in`, `reset_password.request_header`,
  `reset_password.request_description`, `reset_password.request_send`,
  `reset_password.back-to-login`, `reset_password.check_email_sent_header`,
  `reset_password.reset_header`, `reset_password.reset_btn` and the form labels. „Bolt CMS“ in the
  eyebrow is the product name. Only the reveal button's `aria-label` has keys of its own.
- **One primary button** per screen; „Zapomenuté heslo“ and „Zpět k přihlášení“ are links.
- **Password fields** are always rendered with `type: 'password', value: ''` (`ba.password()`):
  Bolt's login uses `PasswordWithPreviewType`, which a plain form theme renders as a text input.
- **Nothing raw, nothing inline.** No `|raw`, no inline `<script>`, no `on…=` handler, no `style=`
  attribute, no `target`; the one `<style>` carries `app.request.attributes._bolt_auth_csp_nonce`.
  `verify.sh` fails on each of them.

---

## Step 5: Verify and Look

```bash
bash $SKILLS/bolt-auth-screens/scripts/verify.sh
```

| Section | Checks |
| :--- | :--- |
| 1. Templates and assets | the seven templates and `js/bolt-auth.js` equal the skill's (drift warns), the fonts, no external URL in the templates |
| 2. Wiring | the four `theme.yaml` keys point at `bolt-auth/` |
| 3. Per-project values | seven `#rrggbb` colours, every contrast, no project colour written into a template, logo and mark files and sizes |
| 4. Theme integration | the Tailwind exclusion, the reveal labels in every catalog (missing in the default locale fails) |
| 5. Security | the security layer equals the skill's, `symfony/rate-limiter`, both limiters, the password minimum (= `config/validator/user.yaml`), `login_throttling`, no enumeration notice, token lifetime ≤ 1 h, trusted hosts, the Trusted Types policy of an installed ALTCHA, and the template rules (no `|raw`, inline script, handler or `style=`, nonce on `<style>`, `type="password"` forced, CSRF, widget slots and errors kept) |
| 6. Live screens | `/…/login` and `/…/reset-password` (backend URL from `bolt.backend_url`) render the screen with Bolt's fields, password fields `type="password"` without value, no admin CSS, no foreign host; headers: the strict CSP with a nonce equal to the `<style>`'s, Trusted Types without debug, `no-store`, `no-referrer`, `DENY`, COOP, `nosniff`; session cookie `HttpOnly` + `SameSite` (+ `Secure` on HTTPS); every theme asset answers 200. Against PHP's built-in server started by `verify.sh` also the rate limit (POSTs without a valid CSRF token, so no e-mail is sent), after which the limiter pool is cleared. `BOLT_BASE_URL`, else PHP's built-in server |
| 7. Twig syntax | `lint:twig` on `bolt-auth/` |
| 8. Every state | all twelve states rendered through Bolt's controllers and form types with dummy data (`scripts/preview.php check`), including the throttled login, the rate-limited request and a new password refused by the policy; no password field rendered as text or with a value |

Then look at every state in the browser — the preview renders them with dummy forms, so it needs
no user account, no reset token and sends no e-mail:

```bash
php -S 127.0.0.1:8899 -t public $SKILLS/bolt-auth-screens/scripts/preview.php
# → http://127.0.0.1:8899/__bolt-auth/  (desktop and 390 px side by side)
```

| State | What to see |
| :--- | :--- |
| Login | panel in the site's colours, badge logo, watermark, Serif site name; form 380 px, centred |
| Login · wrong credentials / after a reset | red alert / green alert under the title |
| Reset request (+ expired link) | lead directly under the title, centred back link |
| Link sent | the success alert replaces the form, back link stays |
| Login · too many attempts | Bolt's throttling message in the red alert |
| Reset request · rate limit | „Příliš mnoho požadavků z této adresy…“ in the red alert |
| New password (+ differ / too short / weak) | the right field marked, one error line; the weak one refused by the policy |
| 390 px | the panel becomes a header: badge, site name at 40 px, back link; form below |

Finally sign in once on the real `/bolt/login`: the reveal button, remember-me and the dashboard.
In production (or locally with `APP_ENV=prod APP_DEBUG=0`), open the login with the browser's
console: no Content-Security-Policy or Trusted Types violation may appear. Run `verify.sh` with
`BOLT_BASE_URL` pointing at production after the first deployment, for the live headers and the
`Secure` cookie over HTTPS.

---

## Pitfalls

- **Default screen still shows.** `theme.yaml` is cached: `php bin/console cache:clear`. A
  `login_template` in `config/bolt/config.yaml` does not win over the theme's.
- **Fonts or logo answer 403 on Apache.** They must live in `css/`, `js/` or `img/` (the
  `bolt-htaccess` allowlist); `bolt-auth/` itself is denied, which is right for templates.
- **White label on a light button.** Never set `on_accent` by hand against the check: orange,
  yellow and gold buttons take a dark label.
- **Watermark is a rectangle.** The mark has no transparency (JPEG or a PNG with a background):
  export the symbol alone with a transparent background.
- **White logo.** The badge is white; use the dark or colour version of the logo.
- **A strict CSP.** The screens need `style-src 'unsafe-inline'` (the inline styles, as the helper
  pages) and nothing else beyond `'self'` — the baseline and strict policies of
  `bolt-security-hardening` both allow them.
- **A catalog in `translations/` rewritten after browsing the screens locally.** Not the skill:
  Bolt's stock `config/packages/translation.yaml` enables php-translation's
  `auto_add_missing_translations`, which re-dumps the catalogs in the dev environment whenever a
  rendered page uses a key they lack (new unit ids, every missing key of that page added). Discard
  such changes before committing (`git checkout translations/`, then merge the skill's units
  again). `verify.sh` restores the catalogs after its live checks.
- **PHP's built-in server ignores `APP_ENV=prod` given on the command line** and boots from
  `.env.local`: start it with `php -d variables_order=EGPCS -S …` to test production mode.
- **A CSP violation in the admin login after installing an extension.** Its widget loads a file
  from another host or creates a Trusted Types policy: allow the policy name in
  `bolt_auth.trusted_types`; never weaken the policy with `'unsafe-inline'` or a foreign host.
- **The rate limit hits a whole office.** Behind a proxy without `SYMFONY_TRUSTED_PROXIES`, every
  visitor has the proxy's IP (`bolt-security-hardening` Step 2).
- **The page is framed nowhere.** `X-Frame-Options: DENY` applies to the sign-in too; the preview
  server renders the states itself instead of framing the site.
