/**
 * Cookie consent — Czech ZEK § 89/3, GDPR, ÚOOÚ / EDPB practice (references/guidelines.cs.md).
 *
 * The single implementation of consent behaviour. Imported by js/src/index.ts:
 *   import './cookie-consent';
 * There are no inline scripts: partials/_consent-mode.twig only prints the configuration as
 * JSON (#cookie-consent-config, generated from the `analytics:` and `privacy:` blocks of
 * theme.yaml), so a strict Content-Security-Policy keeps working.
 *
 * Before a choice nothing non-essential loads (CB-01). Google tags follow Consent Mode v2:
 *   basic (default)  gtag.js is injected only after analytics or marketing consent
 *   advanced         gtag.js loads on every visit with all storage denied (operator's
 *                    explicit decision only, CB-50)
 * Seznam Sklik, blocked <script type="text/plain"> tags and embeds always wait for consent.
 *
 * Markup contract (partials/_cookie-banner.twig, partials/_consent-embed.twig, footer):
 *   [data-cookie-banner]                         first layer, non-modal, never steals focus (CB-60)
 *   [data-cookie-dialog]                         <dialog> second layer (Nastavení cookies)
 *   [data-cookie-accept] / [data-cookie-reject]  accept all / reject all (both layers)
 *   [data-cookie-save]                           save the switched categories only (DP-07)
 *   [data-cookie-settings]                       opens the second layer with the current state
 *                                                (layer-1 button, footer, privacy page — CB-30)
 *   [data-cookie-close]                          closes the second layer without a choice
 *   button[role="switch"][data-cookie-category]  category switches, aria-checked="false" (CB-20)
 *   [data-cookie-banner-defer]                   on a page: do not show the first layer (PP-05)
 *   [data-consent-embed][data-consent-category]  placeholder with a <template> holding the embed
 *   [data-consent-embed-load]                    loads that embed by granting its category (CB-02)
 *   script[type="text/plain"][data-consent-category]   further trackers (Meta Pixel, …)
 *
 * Public API:
 *   window.cookieConsent.open()                  open the second layer
 *   window.cookieConsent.has('marketing')        is a category granted?
 *   window.cookieConsent.conversion({ googleAds: 'AW-…/label', sklik: 123, value, currency })
 *   window event 'cookie-consent'                CustomEvent<ConsentRecord> after every change
 */

type Category = 'preferences' | 'analytics' | 'marketing' | 'third_party';

interface ConsentConfig {
    version: number;
    validityMonths: number;
    reaskMonths: number;
    mode: 'basic' | 'advanced';
    categories: Category[];
    /** First-party cookie names per category (`_ga_*` = prefix), deleted on withdrawal (CB-31). */
    cookies: { [category: string]: string[] };
    ga4: string | null;
    googleAds: string | null;
    sklik: number | null;
    gaCookieExpires: number;
}

export interface ConsentRecord {
    id: string;
    version: number;
    categories: { [category: string]: boolean };
    /** false while only an embed was allowed and the banner has not been answered yet. */
    complete: boolean;
    decidedAt: string;
    expiresAt: string;
}

interface ConversionOptions {
    googleAds?: string;
    sklik?: number;
    value?: number;
    currency?: string;
}

declare global {
    interface Window {
        dataLayer?: unknown[];
        gtag?: (...args: unknown[]) => void;
        rc?: {
            retargetingHit?: (conf: Record<string, unknown>) => void;
            conversionHit?: (conf: Record<string, unknown>) => void;
        };
        cookieConsent?: {
            open: () => void;
            has: (category: Category) => boolean;
            conversion: (options: ConversionOptions) => void;
        };
    }
}

const STORAGE_KEY = 'bolt-cookie-consent';
const GTAG_SRC = 'https://www.googletagmanager.com/gtag/js?id=';
const SKLIK_SRC = 'https://c.seznam.cz/js/rc.js';

function readConfig(): ConsentConfig | null {
    const node = document.getElementById('cookie-consent-config');
    if (!node?.textContent) return null;
    try {
        return JSON.parse(node.textContent) as ConsentConfig;
    } catch {
        return null;
    }
}

function anyGranted(record: ConsentRecord | null): boolean {
    if (!record) return false;
    return Object.keys(record.categories).some((key) => record.categories[key] === true);
}

/**
 * The stored choice, or null when the banner must be shown again: no choice yet, expired
 * (CB-41: 12 months after consent, 6 months after rejection) or — for visitors who granted
 * anything — given for an older configVersion (CB-42). A rejection stays valid across versions
 * until it expires, so the banner never re-appears sooner than 6 months after it (DP-05).
 */
function readRecord(config: ConsentConfig): ConsentRecord | null {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return null;
        const record = JSON.parse(raw) as ConsentRecord;
        if (!record || typeof record.categories !== 'object' || !record.expiresAt) return null;
        if (Date.parse(record.expiresAt) <= Date.now()) return null;
        if (record.version !== config.version && anyGranted(record)) return null;
        return record;
    } catch {
        return null;
    }
}

function randomId(): string {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
        return crypto.randomUUID();
    }
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

/** Persists the choice with configuration version and timestamp (CB-40). */
function writeRecord(config: ConsentConfig, categories: { [category: string]: boolean }, complete: boolean, previous: ConsentRecord | null): ConsentRecord {
    const now = new Date();
    const expires = new Date(now.getTime());
    const record: ConsentRecord = {
        id: previous?.id ?? randomId(),
        version: config.version,
        categories,
        complete,
        decidedAt: now.toISOString(),
        expiresAt: '',
    };
    expires.setMonth(expires.getMonth() + (anyGranted(record) ? config.validityMonths : config.reaskMonths));
    record.expiresAt = expires.toISOString();

    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(record));
    } catch {
        /* storage disabled — the choice still applies to this page view */
    }
    return record;
}

function loadScript(src: string): Promise<void> {
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.async = true;
        script.src = src;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Failed to load ${src}`));
        document.head.appendChild(script);
    });
}

/** Deletes first-party cookies on the host and every parent domain (GA sets `.example.cz`). */
function deleteCookies(patterns: string[]): void {
    if (!patterns.length) return;
    const matches = (name: string): boolean => patterns.some((pattern) => (
        pattern.endsWith('*') ? name.startsWith(pattern.slice(0, -1)) : name === pattern
    ));
    const names = document.cookie.split(';')
        .map((cookie) => cookie.split('=')[0].trim())
        .filter((name) => name !== '' && matches(name));

    const parts = window.location.hostname.split('.');
    const domains: Array<string | null> = [null];
    for (let index = 0; index < parts.length - 1; index += 1) {
        domains.push(`.${parts.slice(index).join('.')}`);
    }

    names.forEach((name) => {
        domains.forEach((domain) => {
            document.cookie = `${name}=; Max-Age=0; Path=/${domain ? `; Domain=${domain}` : ''}; SameSite=Lax`;
        });
    });
}

class ConsentManager {
    private record: ConsentRecord | null;
    /** Categories whose scripts already run on this page view — a withdrawal needs a reload. */
    private readonly active: { [category: string]: boolean } = {};
    private gtagLoaded = false;
    private readonly googleConfigured: { [id: string]: boolean } = {};
    private sklikReady: Promise<void> | null = null;

    constructor(private readonly config: ConsentConfig) {
        this.record = readRecord(config);
    }

    get current(): ConsentRecord | null {
        return this.record;
    }

    has(category: Category): boolean {
        return this.record?.categories[category] === true;
    }

    /** Stores a choice and applies it. `complete` = the visitor answered the banner. */
    decide(categories: { [category: string]: boolean }, complete = true): void {
        const previous = this.record;
        const choice: { [category: string]: boolean } = {};
        this.config.categories.forEach((category) => {
            choice[category] = categories[category] === true;
        });
        this.record = writeRecord(this.config, choice, complete, previous);

        // Withdrawal (CB-31): delete first-party cookies, stop running scripts by reloading.
        const withdrawn = this.config.categories.filter((category) => previous?.categories[category] === true && !choice[category]);
        withdrawn.forEach((category) => deleteCookies(this.config.cookies[category] ?? []));
        if (withdrawn.some((category) => this.active[category])) {
            window.location.reload();
            return;
        }
        this.apply();
    }

    /** Runs everything the current record allows. Safe to call repeatedly. */
    apply(): void {
        const analytics = this.has('analytics');
        const marketing = this.has('marketing');

        this.applyGoogle(analytics, marketing);
        if (marketing) this.loadSklik();
        this.config.categories.forEach((category) => {
            if (this.has(category)) {
                this.activateScripts(category);
                this.activateEmbeds(category);
            }
        });

        window.dispatchEvent(new CustomEvent('cookie-consent', { detail: this.record }));
    }

    /** Google Consent Mode v2 (CB-50). Defaults are always denied; updates follow the record. */
    private applyGoogle(analytics: boolean, marketing: boolean): void {
        const { ga4, googleAds, mode } = this.config;
        if (!ga4 && !googleAds) return;

        if (!window.gtag) {
            window.dataLayer = window.dataLayer || [];
            window.gtag = function gtag() {
                // gtag.js expects the Arguments object, not an array
                // eslint-disable-next-line prefer-rest-params
                window.dataLayer!.push(arguments);
            };
            window.gtag('consent', 'default', {
                analytics_storage: 'denied',
                ad_storage: 'denied',
                ad_user_data: 'denied',
                ad_personalization: 'denied',
            });
            window.gtag('set', 'ads_data_redaction', true);
            window.gtag('js', new Date());
        }

        window.gtag('consent', 'update', {
            analytics_storage: analytics ? 'granted' : 'denied',
            ad_storage: marketing ? 'granted' : 'denied',
            ad_user_data: marketing ? 'granted' : 'denied',
            ad_personalization: marketing ? 'granted' : 'denied',
        });

        const advanced = mode === 'advanced';
        if (ga4 && (analytics || advanced)) this.configureGoogle(ga4, { cookie_expires: this.config.gaCookieExpires });
        if (googleAds && (marketing || advanced)) this.configureGoogle(googleAds, {});
        if (analytics && ga4) this.active.analytics = true;
        if (marketing && googleAds) this.active.marketing = true;
    }

    private configureGoogle(id: string, options: Record<string, unknown>): void {
        if (this.googleConfigured[id]) return;
        this.googleConfigured[id] = true;
        window.gtag!('config', id, options);
        if (!this.gtagLoaded) {
            this.gtagLoaded = true;
            loadScript(GTAG_SRC + encodeURIComponent(id)).catch(() => { /* blocked by the visitor's browser */ });
        }
    }

    /** Seznam Sklik retargeting: rc.js only with marketing consent, every hit with consent=1. */
    private loadSklik(): Promise<void> | null {
        const rtgId = this.config.sklik;
        if (!rtgId) return null;
        if (!this.sklikReady) {
            this.active.marketing = true;
            this.sklikReady = loadScript(SKLIK_SRC).then(() => {
                window.rc?.retargetingHit?.({ rtgId, consent: 1 });
            });
            this.sklikReady.catch(() => { /* blocked by the visitor's browser */ });
        }
        return this.sklikReady;
    }

    /** <script type="text/plain" data-consent-category="marketing" [src]> → real script. */
    private activateScripts(category: Category): void {
        document.querySelectorAll<HTMLScriptElement>(`script[type="text/plain"][data-consent-category="${category}"]`).forEach((blocked) => {
            const script = document.createElement('script');
            Array.from(blocked.attributes).forEach((attribute) => {
                if (attribute.name !== 'type') script.setAttribute(attribute.name, attribute.value);
            });
            // Browsers hide a nonce from getAttribute() once the page is parsed; only the property
            // keeps it. Without this, a nonce-based Content-Security-Policy blocks the new script.
            if (blocked.nonce) script.nonce = blocked.nonce;
            script.text = blocked.text;
            blocked.replaceWith(script);
            this.active[category] = true;
        });
    }

    private activateEmbeds(category: Category): void {
        document.querySelectorAll<HTMLElement>(`[data-consent-embed][data-consent-category="${category}"]`).forEach((placeholder) => {
            const template = placeholder.querySelector('template');
            if (!template) return;
            // Keep the sized wrapper (aspect ratio), swap the placeholder text for the embed.
            placeholder.replaceChildren(template.content.cloneNode(true));
            placeholder.removeAttribute('data-consent-embed');
            this.active[category] = true;
        });
    }

    conversion(options: ConversionOptions): void {
        if (!this.has('marketing')) return;
        if (options.googleAds && window.gtag) {
            window.gtag('event', 'conversion', {
                send_to: options.googleAds,
                value: options.value,
                currency: options.currency ?? 'CZK',
            });
        }
        if (options.sklik) {
            const id = options.sklik;
            this.loadSklik()?.then(() => {
                window.rc?.conversionHit?.({ id, value: options.value ?? null, consent: 1 });
            });
        }
    }
}

function initCookieConsent(): void {
    const config = readConfig();
    if (!config || !config.categories.length) return;

    const manager = new ConsentManager(config);
    const banner = document.querySelector<HTMLElement>('[data-cookie-banner]');
    const dialog = document.querySelector<HTMLDialogElement>('[data-cookie-dialog]');
    const switches = (): HTMLElement[] => Array.from(document.querySelectorAll<HTMLElement>('[data-cookie-dialog] [role="switch"][data-cookie-category]'));

    const all = (value: boolean): { [category: string]: boolean } => {
        const choice: { [category: string]: boolean } = {};
        config.categories.forEach((category) => {
            choice[category] = value;
        });
        return choice;
    };

    const finish = (choice: { [category: string]: boolean }): void => {
        if (banner) banner.hidden = true;
        if (dialog?.open) dialog.close();
        manager.decide(choice);
    };

    const open = (): void => {
        if (!dialog) return;
        switches().forEach((control) => {
            control.setAttribute('aria-checked', String(manager.has(control.dataset.cookieCategory as Category)));
        });
        if (!dialog.open) dialog.showModal();
    };

    // Event delegation: footer and privacy-page buttons may be rendered anywhere.
    document.addEventListener('click', (event) => {
        const target = event.target instanceof Element ? event.target : null;
        if (!target) return;

        const control = target.closest<HTMLElement>('[data-cookie-accept], [data-cookie-reject], [data-cookie-save], [data-cookie-settings], [data-cookie-close], [data-consent-embed-load], [role="switch"][data-cookie-category]');
        if (!control) return;

        if (control.matches('[data-cookie-accept]')) {
            finish(all(true));
        } else if (control.matches('[data-cookie-reject]')) {
            finish(all(false));
        } else if (control.matches('[data-cookie-save]')) {
            const choice = all(false);
            switches().forEach((item) => {
                choice[item.dataset.cookieCategory as string] = item.getAttribute('aria-checked') === 'true';
            });
            finish(choice);
        } else if (control.matches('[data-cookie-settings]')) {
            event.preventDefault();
            open();
        } else if (control.matches('[data-cookie-close]')) {
            dialog?.close();
        } else if (control.matches('[role="switch"]')) {
            control.setAttribute('aria-checked', String(control.getAttribute('aria-checked') !== 'true'));
        } else if (control.matches('[data-consent-embed-load]')) {
            // CB-02: loading an embed grants only that embed's category.
            const category = control.closest<HTMLElement>('[data-consent-embed]')?.dataset.consentCategory;
            if (!category) return;
            const current = manager.current;
            const choice = current ? { ...current.categories } : all(false);
            choice[category] = true;
            manager.decide(choice, current?.complete ?? false);
        }
    });

    window.cookieConsent = {
        open,
        has: (category) => manager.has(category),
        conversion: (options) => manager.conversion(options),
    };

    manager.apply();

    // First layer: only without a complete choice, and not on the privacy page (PP-05).
    const record = manager.current;
    if (banner && (!record || !record.complete) && !document.querySelector('[data-cookie-banner-defer]')) {
        banner.hidden = false;
    }
}

// Bundled with `defer`: the DOM is parsed when this runs; the guard covers other loaders.
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCookieConsent);
} else {
    initCookieConsent();
}
