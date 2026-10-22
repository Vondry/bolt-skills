import PhotoSwipe from 'photoswipe';
import PhotoSwipeLightbox from 'photoswipe/lightbox';

/**
 * PhotoSwipe v5 lightbox.
 *
 * Markup contract:
 *   .photoswipe-gallery                 the container
 *     a.photoswipe-gallery__link        one per slide, href = full-size image,
 *                                       carrying data-pswp-width and data-pswp-height
 *       .photoswipe-gallery__caption    optional; innerHTML shown as lightbox caption
 *
 * UI labels (PhotoSwipe defaults to English) come from the first gallery's data attributes,
 * rendered from the translation catalog: data-pswp-close-title, data-pswp-zoom-title,
 * data-pswp-arrow-prev-title, data-pswp-arrow-next-title, data-pswp-error-msg.
 */
const GALLERY_SELECTOR = '.photoswipe-gallery';
const LINK_SELECTOR = '.photoswipe-gallery__link';
const CAPTION_SELECTOR = '.photoswipe-gallery__caption';
const HISTORY_STATE_KEY = 'photoswipe';
const MAX_CONTENT_CACHE_ITEMS = 12;
const UI_LABELS = ['closeTitle', 'zoomTitle', 'arrowPrevTitle', 'arrowNextTitle', 'errorMsg'] as const;

interface PhotoSwipeHash {
    gid: number;
    pid: number;
    baseHash: string;
}

interface PhotoSwipeHistoryState {
    baseHash: string;
    returnOnClose: boolean;
}

interface PhotoSwipeSession extends PhotoSwipeHistoryState {
    gid: number;
    openedFromHash: boolean;
    hashInitialized: boolean;
}

const galleries = Array.from(document.querySelectorAll<HTMLElement>(GALLERY_SELECTOR));

if (galleries.length > 0) {
    let session: PhotoSwipeSession | null = null;
    let closingFromHistory = false;
    let pendingHashOpen = false;

    galleries.forEach((gallery, index) => {
        gallery.dataset.pswpGid = String(index + 1);
    });

    const parseHash = (hash = window.location.hash): PhotoSwipeHash | null => {
        let gid = 0;
        let pid = 0;
        const baseParts: string[] = [];

        hash.replace(/^#/, '').split('&').forEach((part) => {
            const [name, value] = part.split('=', 2);

            if (name === 'gid') {
                gid = Number.parseInt(value ?? '', 10);
            } else if (name === 'pid') {
                pid = Number.parseInt(value ?? '', 10);
            } else if (part) {
                baseParts.push(part);
            }
        });

        if (gid < 1 || pid < 1) {
            return null;
        }

        return { gid, pid, baseHash: baseParts.length ? `#${baseParts.join('&')}` : '' };
    };

    const buildUrl = (baseHash: string, gid: number, pid: number): string => {
        const hash = `${baseHash || '#'}&gid=${gid}&pid=${pid}`;
        return `${window.location.pathname}${window.location.search}${hash}`;
    };

    const getHistoryState = (): PhotoSwipeHistoryState | null => {
        const value = window.history.state?.[HISTORY_STATE_KEY];
        return value
            && typeof value.baseHash === 'string'
            && typeof value.returnOnClose === 'boolean'
            ? value
            : null;
    };

    const setHistoryState = (state: PhotoSwipeHistoryState): Record<string, unknown> => {
        const current = window.history.state;
        return {
            ...(current && typeof current === 'object' ? current : {}),
            [HISTORY_STATE_KEY]: { baseHash: state.baseHash, returnOnClose: state.returnOnClose },
        };
    };

    const clearHistoryState = (): Record<string, unknown> | null => {
        const current = window.history.state;
        if (!current || typeof current !== 'object') {
            return null;
        }

        const next = { ...current };
        delete next[HISTORY_STATE_KEY];
        return Object.keys(next).length ? next : null;
    };

    const getGallery = (hash: PhotoSwipeHash): HTMLElement | null => {
        const gallery = galleries[hash.gid - 1];
        const link = gallery?.querySelectorAll<HTMLElement>(LINK_SELECTOR)[hash.pid - 1];
        return gallery && link ? gallery : null;
    };

    const getDataSourceGalleryId = (): number => {
        const dataSource = lightbox.options.dataSource;
        const gallery = dataSource
            && !Array.isArray(dataSource)
            && 'gallery' in dataSource
            && dataSource.gallery instanceof HTMLElement
            ? dataSource.gallery
            : null;

        return Number.parseInt(gallery?.dataset.pswpGid ?? '', 10);
    };

    const closeFromHistoryWhenReady = (pswp: PhotoSwipe): void => {
        closingFromHistory = true;

        if (pswp.opener.isOpen) {
            pswp.close();
            return;
        }

        const closeAfterOpening = (): void => {
            pswp.off('openingAnimationEnd', closeAfterOpening);
            if (closingFromHistory && (pendingHashOpen || !parseHash())) {
                pswp.close();
            }
        };

        pswp.on('openingAnimationEnd', closeAfterOpening);
    };

    const labels: Partial<Record<typeof UI_LABELS[number], string>> = {};
    UI_LABELS.forEach((option) => {
        const value = galleries[0].dataset[`pswp${option[0].toUpperCase()}${option.slice(1)}`];
        if (value) {
            labels[option] = value;
        }
    });

    const lightbox = new PhotoSwipeLightbox({
        gallery: GALLERY_SELECTOR,
        children: LINK_SELECTOR,
        pswpModule: PhotoSwipe,
        ...labels,
    });

    lightbox.on('gettingData', (event) => {
        const { data } = event;
        if (data.width && data.height) {
            return;
        }

        // Intrinsic size fallback for images missing data-pswp-* dimensions
        const thumb = data.element instanceof HTMLElement ? data.element.querySelector('img') : null;
        if (thumb?.naturalWidth && thumb.naturalHeight) {
            data.width = thumb.naturalWidth;
            data.height = thumb.naturalHeight;
        }
    });

    lightbox.on('beforeOpen', () => {
        if (session) {
            return;
        }

        session = {
            gid: getDataSourceGalleryId(),
            baseHash: window.location.hash,
            returnOnClose: false,
            openedFromHash: false,
            hashInitialized: false,
        };
    });

    lightbox.on('uiRegister', () => {
        const pswp = lightbox.pswp;
        if (!pswp?.ui) {
            return;
        }

        pswp.ui.registerElement({
            name: 'custom-caption',
            className: 'pswp__custom-caption',
            appendTo: 'root',
            order: 9,
            onInit: (element) => {
                const updateCaption = (): void => {
                    const slide = pswp.currSlide?.data.element;
                    const caption = slide instanceof HTMLElement
                        ? slide.querySelector<HTMLElement>(CAPTION_SELECTOR)
                        : null;

                    element.innerHTML = caption?.innerHTML ?? '';
                    element.hidden = !caption?.textContent?.trim();
                };

                pswp.on('change', updateCaption);
                updateCaption();
            },
        });
    });

    lightbox.on('change', () => {
        const pswp = lightbox.pswp;
        if (!pswp || !session || !Number.isInteger(session.gid) || session.gid < 1) {
            return;
        }

        const url = buildUrl(session.baseHash, session.gid, pswp.currIndex + 1);

        if (session.hashInitialized) {
            window.history.replaceState(setHistoryState(session), '', url);
            return;
        }

        if (session.openedFromHash) {
            window.history.replaceState(setHistoryState(session), '', url);
        } else {
            session.returnOnClose = true;
            window.history.pushState(setHistoryState(session), '', url);
        }

        session.hashInitialized = true;
    });

    lightbox.on('afterInit', () => {
        const pswp = lightbox.pswp;
        if (pswp) {
            // Keep a wider navigation window than PhotoSwipe's five-item default,
            // but do not retain every decoded image in very large galleries.
            pswp.contentLoader.limit = Math.min(pswp.getNumItems(), MAX_CONTENT_CACHE_ITEMS);
        }
    });

    lightbox.on('destroy', () => {
        const closed = session;
        session = null;

        if (closingFromHistory) {
            closingFromHistory = false;
        } else if (parseHash()) {
            if (closed?.returnOnClose) {
                window.history.back();
            } else {
                const base = closed?.baseHash ?? '';
                const url = `${window.location.pathname}${window.location.search}${base}`;
                window.history.replaceState(clearHistoryState(), '', url);
            }
        }

        if (pendingHashOpen) {
            pendingHashOpen = false;
            window.setTimeout(openFromHash);
        }
    });

    lightbox.init();

    function openFromHash(): void {
        const hash = parseHash();
        const gallery = hash ? getGallery(hash) : null;

        if (!hash || !gallery || lightbox.pswp) {
            return;
        }

        session = {
            gid: hash.gid,
            baseHash: hash.baseHash,
            returnOnClose: getHistoryState()?.returnOnClose ?? false,
            openedFromHash: true,
            hashInitialized: false,
        };

        if (!lightbox.loadAndOpen(hash.pid - 1, { gallery })) {
            session = null;
        }
    }

    const handleHistoryNavigation = (): void => {
        const hash = parseHash();
        const pswp = lightbox.pswp;

        if (!hash) {
            if (pswp) {
                closeFromHistoryWhenReady(pswp);
            }
            return;
        }

        if (!getGallery(hash)) {
            return;
        }

        if (!pswp) {
            openFromHash();
        } else if (pswp.isDestroying) {
            closingFromHistory = true;
            pendingHashOpen = true;
        } else if (session?.gid === hash.gid) {
            closingFromHistory = false;
            pendingHashOpen = false;
            pswp.goTo(hash.pid - 1);
        } else {
            pendingHashOpen = true;
            closeFromHistoryWhenReady(pswp);
        }
    };

    window.addEventListener('popstate', handleHistoryNavigation);
    window.addEventListener('hashchange', handleHistoryNavigation);

    openFromHash();
}

export {};
