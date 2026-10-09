---
name: bolt-cookie-consent
description: >-
  Legal standards, architectural blueprints, and automated verification for deploying a Czech
  ZEK § 89 / GDPR compliant opt-in cookie banner, Google Consent Mode v2, and multilingual
  Privacy Policy page (/zasady-ochrany-osobnich-udaju) in Bolt CMS.
---

# Bolt CMS Cookie Consent & Privacy Policy (`bolt-cookie-consent`)

This skill defines the legal rules, UI architecture, and verification runbook for deploying a GDPR and Czech Electronic Communications Act (ZEK) compliant cookie banner and Privacy Policy page in Bolt CMS.

---

## 1. Legal Requirements (Czech Republic & EU)

In the Czech Republic, cookies and user tracking are governed by:
- **Act No. 127/2005 Coll. (Zákon o elektronických komunikacích - ZEK), § 89 odst. 3** (amended by Act No. 374/2021 Sb. effective January 1, 2022).
- **Regulation (EU) 2016/679 (GDPR)**, Articles 4(11), 6(1)(a), 7, and 12–14.
- **Act No. 110/2019 Coll. on Personal Data Processing (ZZOU)**.
- **Official guidance from ÚOOÚ (Úřad pro ochranu osobních údajů)** and the EDPB Cookie Banner Taskforce.

### Key Rules from ZEK & ÚOOÚ:

1. **Strict Opt-In Principle**:
   - All non-essential cookies and tracking scripts (Google Analytics, Seznam Sklik, Meta Pixel, heatmaps) **must not execute or set cookies** before the user grants prior, active consent.
   - Only strictly necessary technical cookies (session, security, CSRF, storing consent choice) are exempt from consent under § 89 odst. 3 ZEK.

2. **Equal Visual Prominence (No Dark Patterns)**:
   - The button to reject cookies (**„Odmítnout vše“**) must have **equal visual weight, font size, and contrast** as the accept button (**„Přijmout vše“**).
   - "Odmítnout" must be located in the **first layer** of the banner. Forcing the user into a secondary settings sub-menu to reject tracking while allowing one-click acceptance is an illegal dark pattern penalized by ÚOOÚ.

3. **No Pre-Ticked Checkboxes**:
   - In granular preference settings, non-essential categories (Analytics, Marketing) must be **unchecked by default**.

4. **No Implied Consent**:
   - Scrolling, clicking anywhere else on the page, or closing the banner by clicking an 'X' button does **not** constitute consent.

5. **Revocation As Easy As Giving Consent**:
   - Under Art. 7(3) GDPR, users must be able to withdraw consent at any time as easily as they gave it.
   - The website must provide a persistent link in the footer (e.g. **„Nastavení cookies“**) that re-opens the banner / preferences dialog.

6. **No Cookie Walls**:
   - Access to general website content must not be made conditional on accepting cookies.

---

## 2. Privacy Policy Page Content (`/zasady-ochrany-osobnich-udaju`)

Under GDPR Articles 12, 13, and 14, the Privacy Policy page must provide clear, concise, and transparent information:

### What MUST be on the page:
- **Data Controller Identity (Správce osobních údajů)**:
  - Legal business name / Operator name
  - Company ID (IČO) and registered address (Sídlo)
  - Contact details (email, phone, contact person)
  - Statement whether a Data Protection Officer (DPO / Pověřenec) is appointed.
- **Purposes and Legal Grounds for Processing**:
  - *Technical cookies / Website operation*: Art. 6(1)(f) GDPR (Legitimate interest) + § 89 ZEK.
  - *Web traffic analytics (Google Analytics)*: Art. 6(1)(a) GDPR (Consent) + § 89 ZEK.
  - *Marketing & Retargeting (Sklik, Meta)*: Art. 6(1)(a) GDPR (Consent) + § 89 ZEK.
  - *Contact / inquiry forms*: Art. 6(1)(b) GDPR (Negotiating a contract) or 6(1)(f).
- **Concrete Tracking Technologies & Cookie Table**:
  - Name of cookie / tool (e.g. `bolt-cookie-consent`, `_ga`, `rc.js` / Sklik)
  - Provider (First-party / Google Ireland Ltd. / Seznam.cz, a.s.)
  - Purpose (Technické, statistika návštěvnosti, retargeting)
  - Retention duration (e.g. 1 year, 2 years, session, 90 days)
  - Type & consent requirement.
- **Google Consent Mode v2 & Sklik Explanation**:
  - Explanation that GA4 runs with `analytics_storage=denied` before consent.
  - Explanation that Sklik retargeting loads only with marketing consent (basic mode) and that every hit carries `consent=1` / `consent=0`.
- **International Data Transfers (Předávání údajů mimo EU)**:
  - Statement on processing by Google Ireland Ltd. under EU-U.S. Data Privacy Framework.
- **Data Subject Rights (Práva subjektů údajů)**:
  - Right of access (Art. 15), rectification (Art. 16), erasure (Art. 17).
  - Right to restriction of processing (Art. 18) and data portability (Art. 20).
  - Right to object (Art. 21).
  - **Right to withdraw consent anytime**: Interactive button calling `resetCookieConsent()`.
  - Right to lodge a complaint with the Czech supervisory authority:
    **Úřad pro ochranu osobních údajů (ÚOOÚ)**, Pplk. Sochora 27, 170 00 Praha 7, [uoou.gov.cz](https://uoou.gov.cz).
- **Effective Date**: Date of last update.

---

## 3. Architecture in Bolt CMS

Bolt CMS themes implement privacy pages and cookie banners via two architectural patterns:

### Pattern A: Static Page with XLIFF Translation (Preferred for speed & parity)
- Template: `public/theme/<theme>/static-pages/gdpr.twig`, extending `partials/_master.twig` (`{% block main %}`).
- Route: `/zasady-ochrany-osobnich-udaju` served by Bolt's `TemplateController`. The routes must sit in `config/routes.yaml` **above** the `frontend:` import, otherwise Bolt's catch-all frontend routes answer with 404 (`scripts/scaffold.sh` inserts them):
  ```yaml
  # config/routes.yaml
  privacy:
    path: /zasady-ochrany-osobnich-udaju
    defaults:
      _controller: Bolt\Controller\Frontend\TemplateController::template
      templateName: static-pages/gdpr.twig

  # Locale-prefixed variant (e.g. /en/zasady-ochrany-osobnich-udaju). Symfony sets the request
  # locale from {_locale}, which __() / |trans and locale_link() pick up.
  privacy_locale:
    path: /{_locale}/zasady-ochrany-osobnich-udaju
    requirements: { _locale: '%app_locales%' }
    defaults:
      _controller: Bolt\Controller\Frontend\TemplateController::template
      templateName: static-pages/gdpr.twig
  ```
- Strings: Fully translated via XLIFF 2.0 catalogs (`translations/messages.cs.xlf` and `messages.en.xlf`, units `privacy.*` and `cookie.*` in `examples/translations.*.xlf`).
- Automatic locale switching: `/zasady-ochrany-osobnich-udaju` on Czech, `/en/zasady-ochrany-osobnich-udaju` on English.
- Dynamic contacts: Controller name, company ID (IČO), address, email and phone pulled from `theme.yaml` (`contact.name`, `contact.ico`, `contact.address`, `contact.email`, `contact.phone`); tracking IDs from `analytics.ga4_id` / `analytics.sklik_id`.

### Pattern B: Singleton ContentType with Redactor (Preferred for client CMS editing)
- ContentType: `privacy_policy` singleton defined in `config/bolt/contenttypes.yaml` (with `order: -id`, `slug` set so the page is served at `/zasady-ochrany-osobnich-udaju`).
- Fields: `intro_section` (eyebrow, title, description), `effective_date`, and `sections` (collection of sets with `title` and `body` redactor).
- Localized: `locales:` equal to `app_locales`.
- Template: `public/theme/<theme>/pages/<name>/<name>.twig` (e.g. `pages/zasady/zasady.twig`) with auto-generated sticky Table of Contents and scroll-spy.

### Files

| File | Role |
| :--- | :--- |
| `partials/_consent-mode.twig` | Consent Mode v2 defaults + `window.loadAnalytics()` / `window.loadSklik()`, included in `<head>` of `partials/_master.twig` before any tracking script |
| `partials/_cookie-banner.twig` | Banner markup (included at the end of `<body>` by `partials/_master.twig`) |
| `js/src/cookie-consent.ts` | The only implementation of the banner behaviour; imported by `js/src/index.ts` |
| `static-pages/gdpr.twig` | Privacy policy page (Pattern A) |
| footer `[data-cookie-settings]` button | Re-opens the banner (`bolt-menu` footer container; also on the privacy page) |

---

## 4. Technical Integration: Google Consent Mode v2 & Sklik

### Step 1: Head Initialization (`partials/_consent-mode.twig`)
`partials/_master.twig` includes this partial in `<head>` before any other script. It reads the IDs from `theme.yaml` (`analytics.ga4_id`, `analytics.sklik_id`, `analytics.consent_mode`) and the stored consent record, sets the Consent Mode defaults, and defines the loaders.

**Choose the Consent Mode variant in the site plan:**
- **`basic` (default)** — strict opt-in matching rule 1 above: neither `gtag.js` nor Sklik's `rc.js` is loaded before consent; `cookie-consent.ts` calls `window.loadAnalytics()` / `window.loadSklik()` when the visitor grants the category (and on later visits with stored consent).
- **`advanced`** — `gtag.js` loads on every visit with storage denied and sends cookieless pings until consent; `rc.js` sends hits with `consent=0`. This transmits data (IP address, user agent) before consent, which many supervisory authorities regard as requiring consent as well. If chosen, describe it in the privacy policy.

```twig
{#
  partials/_consent-mode.twig — Google Consent Mode v2 defaults and tracking loaders.
  Included in <head> of partials/_master.twig BEFORE any other tracking script.
  IDs come from theme.yaml:  analytics: { ga4_id: 'G-…', sklik_id: 123456 }

  Two Consent Mode variants (decide in the site plan, describe the choice in the privacy policy):

    basic (default, strict opt-in)  gtag.js and Sklik's rc.js are NOT loaded before consent.
                                    js/src/cookie-consent.ts calls window.loadAnalytics() /
                                    window.loadSklik() once the visitor grants analytics / marketing
                                    consent (and on every later visit with stored consent).
    advanced                        gtag.js loads on every visit with all storage denied and sends
                                    cookieless pings until consent (rc.js sends consent=0 hits).
                                    Set analytics.consent_mode: 'advanced' in theme.yaml.
                                    This transmits data (IP, user agent) to Google before consent;
                                    many authorities regard that as requiring consent too.

  The stored consent record (localStorage 'bolt-cookie-consent', version 1) is read here so
  returning visitors start with their previous choice.
#}
{% set ga4_id = config.get('theme/analytics/ga4_id') %}
{% set sklik_id = config.get('theme/analytics/sklik_id') %}
{% set consent_mode = config.get('theme/analytics/consent_mode')|default('basic') %}

{% if ga4_id or sklik_id %}
<script>
    (function () {
        var STORAGE_KEY = 'bolt-cookie-consent';
        var CONSENT_VERSION = 1;
        var GA_ID = {{ ga4_id|default('')|json_encode|raw }};
        var MODE = {{ consent_mode|json_encode|raw }};

        window.dataLayer = window.dataLayer || [];
        function gtag() { dataLayer.push(arguments); }
        window.gtag = gtag;

        var analytics = false;
        var marketing = false;
        try {
            var stored = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
            if (stored.version === CONSENT_VERSION) {
                analytics = stored.analytics === true;
                marketing = stored.marketing === true;
            }
        } catch (e) {}

        gtag('consent', 'default', {
            analytics_storage: analytics ? 'granted' : 'denied',
            ad_storage: marketing ? 'granted' : 'denied',
            ad_user_data: marketing ? 'granted' : 'denied',
            ad_personalization: marketing ? 'granted' : 'denied'
        });
        gtag('set', 'ads_data_redaction', true);

        var loaded = false;
        window.loadAnalytics = function () {
            if (loaded || !GA_ID) return;
            loaded = true;
            gtag('js', new Date());
            gtag('config', GA_ID, {
                allow_ad_personalization_signals: false,
                allow_google_signals: false
            });
            var s = document.createElement('script');
            s.async = true;
            s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_ID);
            document.head.appendChild(s);
        };

        // Advanced mode loads immediately (denied until consent); basic mode only with consent.
        if (MODE === 'advanced' || analytics) {
            window.loadAnalytics();
        }

        {% if sklik_id %}
        // Seznam Sklik retargeting: the consent flag is sent with every hit;
        // js/src/cookie-consent.ts updates it and re-sends after a decision.
        window.retargetingConf = { rtgId: {{ sklik_id|json_encode|raw }}, consent: marketing ? 1 : 0 };

        var sklikLoaded = false;
        window.loadSklik = function () {
            if (sklikLoaded) return;
            sklikLoaded = true;
            var r = document.createElement('script');
            r.async = true;
            r.src = 'https://c.seznam.cz/js/rc.js';
            r.onload = function () {
                if (window.rc && window.rc.retargetingHit) {
                    window.rc.retargetingHit(window.retargetingConf);
                }
            };
            document.head.appendChild(r);
        };

        // Same rule as analytics: basic mode loads rc.js only with marketing consent.
        if (MODE === 'advanced' || marketing) {
            window.loadSklik();
        }
        {% endif %}
    })();
</script>
{% endif %}
```

### Step 2: Banner & Consent Updates (`js/src/cookie-consent.ts`)
The banner (`partials/_cookie-banner.twig`) contains markup only — no inline scripts or `onclick` handlers, so a strict Content-Security-Policy keeps working. `cookie-consent.ts` wires it through data attributes:

| Attribute | Element |
| :--- | :--- |
| `[data-cookie-banner]` | the banner (`role="dialog"`, starts `hidden` + `translate-y-full`) |
| `[data-cookie-accept]`, `[data-cookie-reject]` | first-layer buttons — **identical classes**, only the label differs |
| `[data-cookie-toggle-prefs]` | shows the granular preferences; `data-label-open` / `data-label-close` hold its labels |
| `[data-cookie-pref="analytics" \| "marketing"]` | preference checkboxes, unchecked by default |
| `[data-cookie-save]` | saves the toggled preferences (replaces Accept while preferences are open) |
| `[data-cookie-settings]` | any button that re-opens the banner (footer, privacy page) |

When the visitor decides, the module persists the record (localStorage `bolt-cookie-consent`, version 1), then:

```typescript
export function applyConsent(data: Pick<CookieConsentData, 'analytics' | 'marketing'>): void {
    // 1. Update Google Consent Mode v2
    window.gtag?.('consent', 'update', {
        analytics_storage: data.analytics ? 'granted' : 'denied',
        ad_storage: data.marketing ? 'granted' : 'denied',
        ad_user_data: data.marketing ? 'granted' : 'denied',
        ad_personalization: data.marketing ? 'granted' : 'denied',
    });

    // Basic mode: load gtag.js only now
    if (data.analytics) window.loadAnalytics?.();

    // Refused or withdrawn: delete _ga* cookies on the host AND every parent domain
    // (GA sets them on the registrable domain, e.g. .example.cz while browsing www.example.cz)
    if (!data.analytics) removeTrackingCookies();

    // 2. Seznam Sklik retargeting: load rc.js with marketing consent, send the consent flag with the hit
    if (data.marketing) window.loadSklik?.();
    if (window.retargetingConf) {
        window.retargetingConf.consent = data.marketing ? 1 : 0;
        window.rc?.retargetingHit?.(window.retargetingConf);
    }

    // 3. Dispatch global event for other scripts
    window.dispatchEvent(new CustomEvent('cookie-consent', { detail: data }));
}
```

The module also exposes `window.cookieConsent` (`acceptAll`, `rejectAll`, `savePreferences`, `togglePrefs`, `reset`) and `window.resetCookieConsent()`, traps focus inside the banner while it is open, and returns focus to the previously focused element when it closes. The full file is `examples/cookie-consent.ts`.

### Step 3: Footer Revocation Link
The `bolt-menu` footer container renders the button when `theme.yaml` lists a tracking ID; any template can add one:

```twig
<button type="button" data-cookie-settings class="hover:underline cursor-pointer">
    {{ __('footer.cookie_settings') }}
</button>
```

---

## 5. Automation & Verification

### Scaffolding Script (`scripts/scaffold.sh`)
Scaffolds the banner, the Consent Mode partial, the TypeScript module, the privacy page and its routes:

```bash
bash skills/bolt-cookie-consent/scripts/scaffold.sh              # site with tracking
bash skills/bolt-cookie-consent/scripts/scaffold.sh --no-banner  # privacy page only (no tracking)
```

- Copies `partials/_cookie-banner.twig`, `partials/_consent-mode.twig`, `js/src/cookie-consent.ts` and `static-pages/gdpr.twig` (existing files are preserved).
- Enables `import './cookie-consent';` in `js/src/index.ts`.
- Inserts the `privacy` / `privacy_locale` routes above `frontend:` in `config/routes.yaml` (skipped when the path is already routed).
- Reminds you to merge `examples/translations.<locale>.xlf` with `scripts/merge-xliff.php` and to set the IDs in `theme.yaml`.

### Verification Script (`scripts/verify.sh`)
Runs strict automated compliance checks against Czech regulations and Bolt CMS standards:

```bash
bash skills/bolt-cookie-consent/scripts/verify.sh
```

**Verification Steps:**
1. Detects active theme from `config/bolt/config.yaml`.
2. Verifies `_cookie-banner.twig` exists.
3. Audits banner compliance: verifies Reject ("Odmítnout") and Accept exist in the first layer and that `#cookie-btn-reject` and `#cookie-btn-accept` carry **identical classes** (only `order-*` may differ) — equal visual prominence, no dark pattern.
4. Verifies inclusion of the banner in `_master.twig` / `_base.twig`.
5. Verifies a persistent revocation trigger (`resetCookieConsent()`, `cookieConsent.reset` or `[data-cookie-settings]`) in theme templates or scripts.
6. Verifies presence of the Privacy Policy page (`/zasady-ochrany-osobnich-udaju`) — and, for the static template, its route in `config/routes.yaml`.
7. Checks XLIFF translation catalogs (`messages.cs.xlf`) for required `cookie.*` and `privacy.*` units.
