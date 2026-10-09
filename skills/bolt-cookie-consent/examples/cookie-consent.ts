/**
 * Cookie Consent Manager — Czech ZEK § 89 / GDPR / Google Consent Mode v2 / Seznam Sklik.
 *
 * The single implementation of the consent banner (partials/_cookie-banner.twig).
 * Imported by js/src/index.ts:  import './cookie-consent';
 *
 * Markup contract:
 *   [data-cookie-banner]          the banner (role="dialog", starts `hidden` + translate-y-full)
 *   [data-cookie-accept]          accept all
 *   [data-cookie-reject]          reject all (same styling as accept — no dark pattern)
 *   [data-cookie-save]            save the toggled preferences (shown while preferences are open)
 *   [data-cookie-toggle-prefs]    show/hide the granular preferences (#cookie-prefs);
 *                                 data-label-open / data-label-close hold the button labels
 *   [data-cookie-pref="analytics" | "marketing"]   preference checkboxes (unchecked by default)
 *   [data-cookie-settings]        any button that re-opens the banner (footer, privacy page)
 *
 * Public API (kept for templates and third-party code):
 *   window.cookieConsent.{ acceptAll, rejectAll, savePreferences, togglePrefs, reset }
 *   window.resetCookieConsent()   — re-open the banner (withdraw consent as easily as giving it)
 *   window event 'cookie-consent' — CustomEvent<CookieConsentData> after every decision
 *
 * The consent record is stored in localStorage (key 'bolt-cookie-consent', versioned) and read
 * by partials/_consent-mode.twig in <head>, before any tracking script runs.
 */

export interface CookieConsentData {
    version: number;
    analytics: boolean;
    marketing: boolean;
    timestamp: string;
}

declare global {
    interface Window {
        dataLayer?: unknown[];
        gtag?: (...args: unknown[]) => void;
        rc?: {
            retargetingHit?: (conf: Record<string, unknown>) => void;
        };
        retargetingConf?: {
            rtgId: number;
            consent: number;
            [key: string]: unknown;
        };
        cookieConsent?: {
            acceptAll: () => void;
            rejectAll: () => void;
            savePreferences: () => void;
            togglePrefs: () => void;
            reset: () => void;
        };
        resetCookieConsent?: () => void;
        loadAnalytics?: () => void;
        loadSklik?: () => void;
    }
}

const STORAGE_KEY = 'bolt-cookie-consent';
const CONSENT_VERSION = 1;
const FOCUSABLE = 'button:not([hidden]):not([disabled]), input:not([hidden]):not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';

export function readConsent(): CookieConsentData | null {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) {
            const parsed = JSON.parse(raw) as Partial<CookieConsentData>;
            if (parsed && parsed.version === CONSENT_VERSION) {
                return parsed as CookieConsentData;
            }
        }
    } catch {
        /* storage disabled or corrupted value */
    }
    return null;
}

export function persistConsent(analytics: boolean, marketing: boolean): CookieConsentData {
    const data: CookieConsentData = {
        version: CONSENT_VERSION,
        analytics: Boolean(analytics),
        marketing: Boolean(marketing),
        timestamp: new Date().toISOString(),
    };

    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch {
        /* storage disabled or quota exceeded — consent still applies to this page view */
    }

    return data;
}

/**
 * Delete Google Analytics cookies after consent is refused or withdrawn.
 * GA sets its cookies on the registrable domain (e.g. `.example.cz` while browsing
 * `www.example.cz`), so every parent domain is tried, not only the current host.
 */
export function removeTrackingCookies(): void {
    const prefixes = ['_ga', '_gid', '_gat', '_gac_'];
    const names = document.cookie
        .split(';')
        .map((cookie) => cookie.split('=')[0]?.trim())
        .filter((name): name is string => Boolean(name) && prefixes.some((prefix) => name.startsWith(prefix)));

    const hostname = window.location.hostname;
    const domains = new Set<string | undefined>([undefined, hostname, `.${hostname}`]);
    const parts = hostname.split('.');
    for (let index = 1; index < parts.length - 1; index += 1) {
        domains.add(`.${parts.slice(index).join('.')}`);
    }

    for (const name of names) {
        for (const domain of domains) {
            const domainPart = domain ? `; Domain=${domain}` : '';
            document.cookie = `${name}=; Max-Age=0; Path=/${domainPart}; SameSite=Lax`;
        }
    }
}

export function applyConsent(data: Pick<CookieConsentData, 'analytics' | 'marketing'>): void {
    // 1. Google Consent Mode v2
    if (typeof window.gtag === 'function') {
        window.gtag('consent', 'update', {
            analytics_storage: data.analytics ? 'granted' : 'denied',
            ad_storage: data.marketing ? 'granted' : 'denied',
            ad_user_data: data.marketing ? 'granted' : 'denied',
            ad_personalization: data.marketing ? 'granted' : 'denied',
        });
    }

    // Basic Consent Mode: partials/_consent-mode.twig defines window.loadAnalytics(), which
    // injects gtag.js only now — after the visitor granted analytics consent.
    if (data.analytics && typeof window.loadAnalytics === 'function') {
        window.loadAnalytics();
    }

    // If analytics was refused or withdrawn, wipe its cookies
    if (!data.analytics) {
        removeTrackingCookies();
    }

    // 2. Seznam Sklik retargeting: the consent flag travels with every hit. In basic mode
    //    rc.js is injected only now (window.loadSklik from partials/_consent-mode.twig).
    if (data.marketing && typeof window.loadSklik === 'function') {
        window.loadSklik();
    }
    if (window.retargetingConf) {
        window.retargetingConf.consent = data.marketing ? 1 : 0;
        if (typeof window.rc === 'object' && typeof window.rc.retargetingHit === 'function') {
            window.rc.retargetingHit(window.retargetingConf);
        }
    }

    // 3. Dispatch global CustomEvent for other tracking scripts
    window.dispatchEvent(new CustomEvent('cookie-consent', { detail: data }));
}

function initCookieConsent(): void {
    const banner = document.querySelector<HTMLElement>('[data-cookie-banner]');
    if (!banner) return;

    const prefs = banner.querySelector<HTMLElement>('#cookie-prefs');
    const analyticsBox = banner.querySelector<HTMLInputElement>('[data-cookie-pref="analytics"]');
    const marketingBox = banner.querySelector<HTMLInputElement>('[data-cookie-pref="marketing"]');
    const btnAccept = banner.querySelector<HTMLElement>('[data-cookie-accept]');
    const btnSave = banner.querySelector<HTMLElement>('[data-cookie-save]');
    const btnToggle = banner.querySelector<HTMLElement>('[data-cookie-toggle-prefs]');

    let lastFocused: HTMLElement | null = null;

    const trapFocus = (event: KeyboardEvent): void => {
        if (event.key !== 'Tab' || banner.hidden) return;
        const focusables = Array.from(banner.querySelectorAll<HTMLElement>(FOCUSABLE))
            .filter((el) => el.offsetParent !== null);
        if (!focusables.length) return;

        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
        }
    };

    const showBanner = (): void => {
        lastFocused = document.activeElement instanceof HTMLElement ? document.activeElement : null;
        banner.hidden = false;
        // Two frames: the first commits `hidden=false`, the second starts the slide-in transition.
        requestAnimationFrame(() => requestAnimationFrame(() => {
            banner.classList.remove('translate-y-full');
            banner.focus();
        }));
        document.addEventListener('keydown', trapFocus);
    };

    const hideBanner = (): void => {
        banner.classList.add('translate-y-full');
        document.removeEventListener('keydown', trapFocus);

        let done = false;
        const finish = (): void => {
            if (done) return;
            done = true;
            banner.hidden = true;
            lastFocused?.focus();
            lastFocused = null;
        };
        banner.addEventListener('transitionend', (event) => {
            if (event.target === banner) finish();
        }, { once: true });
        // Fallback for reduced motion (no transition fires)
        window.setTimeout(finish, 600);
    };

    const decide = (analytics: boolean, marketing: boolean): void => {
        applyConsent(persistConsent(analytics, marketing));
        hideBanner();
    };

    const setPrefsOpen = (open: boolean): void => {
        if (!prefs) return;
        prefs.hidden = !open;
        if (btnSave) btnSave.hidden = !open;
        if (btnAccept) btnAccept.hidden = open;
        if (btnToggle) {
            btnToggle.setAttribute('aria-expanded', String(open));
            const label = open ? btnToggle.dataset.labelClose : btnToggle.dataset.labelOpen;
            if (label) btnToggle.textContent = label;
        }
    };

    const api = {
        acceptAll: (): void => decide(true, true),
        rejectAll: (): void => decide(false, false),
        savePreferences: (): void => decide(Boolean(analyticsBox?.checked), Boolean(marketingBox?.checked)),
        togglePrefs: (): void => setPrefsOpen(Boolean(prefs?.hidden)),
        reset: (): void => {
            try {
                localStorage.removeItem(STORAGE_KEY);
            } catch {
                /* ignore */
            }
            if (analyticsBox) analyticsBox.checked = false;
            if (marketingBox) marketingBox.checked = false;
            setPrefsOpen(false);
            applyConsent({ analytics: false, marketing: false });
            showBanner();
        },
    };

    window.cookieConsent = api;
    window.resetCookieConsent = api.reset;

    banner.querySelector('[data-cookie-accept]')?.addEventListener('click', api.acceptAll);
    banner.querySelector('[data-cookie-reject]')?.addEventListener('click', api.rejectAll);
    banner.querySelector('[data-cookie-save]')?.addEventListener('click', api.savePreferences);
    btnToggle?.addEventListener('click', api.togglePrefs);
    document.querySelectorAll<HTMLElement>('[data-cookie-settings]').forEach((button) => {
        button.addEventListener('click', api.reset);
    });

    const stored = readConsent();
    if (stored) {
        if (analyticsBox) analyticsBox.checked = stored.analytics;
        if (marketingBox) marketingBox.checked = stored.marketing;
        applyConsent(stored);
    } else {
        showBanner();
    }
}

// Bundled with `defer`: the DOM is parsed when this runs; the guard covers other loaders.
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCookieConsent);
} else {
    initCookieConsent();
}
