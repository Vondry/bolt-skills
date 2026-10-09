/**
 * Language switcher progressive enhancement.
 *
 * Preserves scroll position across locale switches via sessionStorage.
 * Also preserves active URL query params and hashes.
 */
const SCROLL_KEY = 'locale_switch_scroll';

const readAndClearStoredScroll = (): number | null => {
    try {
        const stored = sessionStorage.getItem(SCROLL_KEY);
        sessionStorage.removeItem(SCROLL_KEY);

        return stored === null ? null : Number.parseInt(stored, 10);
    } catch {
        return null;
    }
};

const storeScroll = (): void => {
    try {
        sessionStorage.setItem(SCROLL_KEY, String(window.scrollY));
    } catch {
        // Safari private mode safe guard
    }
};

const links = document.querySelectorAll<HTMLAnchorElement>('[data-locale-switch]');

const restoreTo = readAndClearStoredScroll();

if (restoreTo !== null && !Number.isNaN(restoreTo) && window.location.hash === '') {
    window.addEventListener('load', () => {
        // Wait two animation frames for layout/images to settle
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                window.scrollTo({ top: restoreTo, behavior: 'instant' });
            });
        });
    });
}

links.forEach((link) => {
    link.addEventListener('click', () => {
        storeScroll();

        const target = new URL(link.href);
        target.search = window.location.search;
        target.hash = window.location.hash;
        link.href = target.toString();
    });
});

export {};
