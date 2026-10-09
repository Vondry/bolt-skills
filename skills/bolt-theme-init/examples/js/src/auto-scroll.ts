/**
 * In-page anchor scrolling.
 *
 * Dynamically measures the sticky header height so anchor jumps land exactly
 * at the top of the section without being obscured by the header bar.
 * Safely handles PhotoSwipe hashes and reflects anchors in URL without adding extra history.
 */
const header = document.querySelector<HTMLElement>('[data-sticky-header]')
    ?? document.getElementById('main-menu')
    ?? document.getElementById('hlavni-menu');

const headerHeight = (): number => (header ? header.getBoundingClientRect().height : 0);

const scrollToHash = (hash: string, behavior: ScrollBehavior): void => {
    let target: Element | null;

    try {
        target = document.querySelector(hash);
    } catch {
        // PhotoSwipe and third-party hashes (#&gid=1&pid=2) are not DOM selectors
        return;
    }

    if (!target) return;

    window.scrollTo({
        top: target.getBoundingClientRect().top + window.scrollY - headerHeight(),
        behavior,
    });
};

/** Reflects the section in the address bar without adding a new history entry. */
const setHash = (hash: string): void => {
    history.replaceState(null, '', window.location.pathname + window.location.search + hash);
};

/** A link is ours to handle only when its target lives on the same page. */
const sameDocumentHash = (link: HTMLAnchorElement): string | null => {
    const url = new URL(link.href, window.location.href);

    if (url.origin !== window.location.origin) return null;
    if (url.pathname !== window.location.pathname) return null;
    if (url.search !== window.location.search) return null;
    if (!url.hash || url.hash === '#') return null;

    return url.hash;
};

// Delegated listener covers links inside mobile dropdowns and dynamically rendered elements
document.addEventListener('click', (event) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const link = (event.target as Element | null)?.closest?.<HTMLAnchorElement>('a[href]');
    if (!link || (link.target && link.target !== '_self')) return;

    const hash = sameDocumentHash(link);
    if (!hash) return;

    event.preventDefault();
    scrollToHash(hash, 'smooth');
    setHash(hash);
});

// Landing on a hash from an external page
window.addEventListener('DOMContentLoaded', () => {
    const hash = window.location.hash;
    if (hash) requestAnimationFrame(() => scrollToHash(hash, 'auto'));
});

export {};
