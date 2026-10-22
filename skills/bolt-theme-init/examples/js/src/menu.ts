/**
 * Navigation behaviour: dropdown accordions and the mobile menu.
 *
 * Markup contract (rendered by bolt-menu's containers/header/_menu.twig and
 * components/nav/dropdown.twig, and by partials/_locale-switcher.twig):
 *
 *   Dropdown accordion (submenus, locale switcher, breadcrumbs, …)
 *     <button data-dropdown-toggle="ID">        the trigger
 *     <div id="ID" class="dropdown">            the panel; `.dropdown` sets overflow:hidden,
 *                                               height:0 and a height transition (Tailwind source)
 *
 *   Mobile menu — one opener, one panel, any number of closers:
 *     <button data-menu-toggle>                 opens (and, in collapse mode, also closes)
 *     <aside data-mobile-menu="drawer">         slide-in drawer (default mode)
 *     <div   data-mobile-menu="collapse">       height-animated panel below the header bar
 *     <div   data-menu-backdrop>                drawer backdrop (optional)
 *     <… data-menu-close>                       close button and every link inside the menu
 *
 *   Legacy ids are still recognised: #mobile-menu / #mobilni-menu (collapse panel).
 */

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

// ── Dropdown accordions ─────────────────────────────────────────────────

const DROPDOWN_TOGGLE = 'data-dropdown-toggle';
const EXPANDED_CLASS = 'dd-expanded';

/**
 * Collapse a panel. A panel that finished opening has `height: auto` (so nested
 * panels can grow); `auto` does not animate, so the pixel height is restored first
 * and the target height applied two frames later.
 *
 * @param height '0px' to animate shut, or null to drop the inline height entirely
 */
const closeDropdown = (button: Element, panel: HTMLElement, height: string | null): void => {
    panel.style.height = `${panel.scrollHeight}px`;

    requestAnimationFrame(() => { // first frame commits the pixel height
        requestAnimationFrame(() => { // second frame starts the transition
            if (height === null) {
                panel.style.removeProperty('height');
            } else {
                panel.style.height = height;
            }
            button.setAttribute('aria-expanded', 'false');
            panel.classList.remove(EXPANDED_CLASS);
            // A collapsed panel is clipped, but its links would still be focusable and
            // announced; `inert` removes them from the tab order and the a11y tree.
            panel.inert = true;
        });
    });
};

/**
 * Close the panel on any click outside it, and on clicks of in-page links
 * (links containing "#"), whose target may be on the current page.
 */
const closeOnClickInDocument = (button: Element, panel: HTMLElement): void => {
    const listener = (event: MouseEvent): void => {
        const target = event.target as HTMLElement | null;
        const isHashLink = !!target?.closest('a')?.getAttribute('href')?.includes('#');

        if ((target && button.contains(target)) || (target && panel.contains(target) && !isHashLink)) {
            return;
        }

        closeDropdown(button, panel, null);
        document.removeEventListener('click', listener);
    };

    document.addEventListener('click', listener);
};

document.querySelectorAll<HTMLElement>(`[${DROPDOWN_TOGGLE}]`).forEach((button) => {
    const panelId = button.getAttribute(DROPDOWN_TOGGLE);
    const panel = panelId ? document.getElementById(panelId) : null;

    if (!panelId || !panel) {
        console.error(`menu.ts: no element #${panelId} for [${DROPDOWN_TOGGLE}]`);
        return;
    }

    button.setAttribute('aria-expanded', 'false');
    button.setAttribute('aria-controls', panelId);
    panel.inert = true;

    const toggle = (): void => {
        if (panel.clientHeight) {
            closeDropdown(button, panel, '0px');
            return;
        }

        panel.classList.add(EXPANDED_CLASS);
        panel.inert = false;
        panel.style.height = `${panel.scrollHeight}px`;
        button.setAttribute('aria-expanded', 'true');

        panel.addEventListener('transitionend', () => {
            // `auto` lets nested panels expand their parent after the animation.
            panel.style.height = 'auto';
            closeOnClickInDocument(button, panel);
        }, { once: true });
    };

    button.addEventListener('click', toggle);

    // ArrowDown on the trigger opens the panel and focuses its first item.
    button.addEventListener('keydown', (event: KeyboardEvent) => {
        if (event.key === 'ArrowDown' && !panel.clientHeight) {
            event.preventDefault();
            toggle();
            requestAnimationFrame(() => panel.querySelector<HTMLElement>('a[href], button')?.focus());
        }
    });

    // Escape inside the panel closes it and returns focus to the trigger.
    panel.addEventListener('keydown', (event: KeyboardEvent) => {
        if (event.key !== 'Escape' || !panel.clientHeight) return;
        event.preventDefault();
        closeDropdown(button, panel, '0px');
        button.focus();
    });
});

// Menus are deliberately not closed on window resize: on iOS, scrolling fires
// resize events without a width change, which would close menus unexpectedly.

// ── Mobile menu ─────────────────────────────────────────────────────────

const opener = document.querySelector<HTMLElement>('[data-menu-toggle]');
const mobileMenu = document.querySelector<HTMLElement>('[data-mobile-menu]')
    ?? document.getElementById('mobile-menu')
    ?? document.getElementById('mobilni-menu');

if (opener && mobileMenu) {
    const mode = mobileMenu.dataset.mobileMenu === 'collapse' || !mobileMenu.hasAttribute('data-mobile-menu')
        ? 'collapse'
        : 'drawer';
    const backdrop = document.querySelector<HTMLElement>('[data-menu-backdrop]');
    const closers = document.querySelectorAll<HTMLElement>('[data-menu-close]');
    const openLabel = opener.dataset.labelOpen ?? opener.getAttribute('aria-label') ?? '';
    const closeLabel = opener.dataset.labelClose ?? openLabel;

    if (mode === 'collapse') {
        // Height-animated panel between 0 and its scrollHeight; the open state is
        // read back from the rendered height.
        const setOpen = (open: boolean): void => {
            opener.setAttribute('aria-expanded', String(open));
            if (openLabel) opener.setAttribute('aria-label', open ? closeLabel : openLabel);
            opener.querySelector('.menu-icon-open')?.classList.toggle('hidden', open);
            opener.querySelector('.menu-icon-close')?.classList.toggle('hidden', !open);
            mobileMenu.style.height = open ? `${mobileMenu.scrollHeight}px` : '0px';
            mobileMenu.inert = !open;
        };

        mobileMenu.inert = mobileMenu.clientHeight === 0;
        opener.addEventListener('click', () => setOpen(mobileMenu.clientHeight === 0));
        closers.forEach((el) => el.addEventListener('click', () => setOpen(false)));
        mobileMenu.querySelectorAll('a[href]').forEach((link) => link.addEventListener('click', () => setOpen(false)));
        // Escape closes the open panel and returns focus to the menu button.
        document.addEventListener('keydown', (event: KeyboardEvent) => {
            if (event.key !== 'Escape' || mobileMenu.clientHeight === 0) return;
            setOpen(false);
            opener.focus();
        });

        window.addEventListener('resize', () => {
            if (mobileMenu.clientHeight !== 0) {
                mobileMenu.style.height = `${mobileMenu.scrollHeight}px`;
            }
        }, { passive: true });
    } else {
        // Slide-in drawer that behaves as a modal dialog.
        const trapFocus = (event: KeyboardEvent): void => {
            if (event.key !== 'Tab') return;
            const focusables = Array.from(mobileMenu.querySelectorAll<HTMLElement>(FOCUSABLE))
                .filter((node) => !node.closest('[inert]')); // skip collapsed dropdowns inside the drawer
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

        const openDrawer = (): void => {
            mobileMenu.removeAttribute('inert');
            mobileMenu.setAttribute('aria-hidden', 'false');
            mobileMenu.classList.remove('translate-x-full');
            backdrop?.classList.remove('opacity-0', 'pointer-events-none');
            backdrop?.classList.add('opacity-100');
            document.body.style.overflow = 'hidden';
            opener.setAttribute('aria-expanded', 'true');
            if (openLabel) opener.setAttribute('aria-label', closeLabel);
            // Move focus into the dialog and keep it there.
            mobileMenu.querySelector<HTMLElement>('[data-menu-close]')?.focus();
            document.addEventListener('keydown', trapFocus);
        };

        const closeDrawer = (): void => {
            // Already closed — guards stray Escape presses from moving focus.
            if (mobileMenu.hasAttribute('inert')) return;
            mobileMenu.classList.add('translate-x-full');
            backdrop?.classList.remove('opacity-100');
            backdrop?.classList.add('opacity-0', 'pointer-events-none');
            document.body.style.overflow = '';
            opener.setAttribute('aria-expanded', 'false');
            if (openLabel) opener.setAttribute('aria-label', openLabel);
            document.removeEventListener('keydown', trapFocus);
            // Take the off-screen drawer out of the tab order and a11y tree,
            // then return focus to the opener.
            mobileMenu.setAttribute('inert', '');
            mobileMenu.setAttribute('aria-hidden', 'true');
            opener.focus();
        };

        mobileMenu.setAttribute('inert', '');
        mobileMenu.setAttribute('aria-hidden', 'true');

        opener.addEventListener('click', openDrawer);
        backdrop?.addEventListener('click', closeDrawer);
        closers.forEach((el) => el.addEventListener('click', closeDrawer));
        document.addEventListener('keydown', (event: KeyboardEvent) => {
            if (event.key === 'Escape') closeDrawer();
        });
        // Close once a link inside the drawer is followed — most mobile links are
        // same-page anchors, which would otherwise leave the drawer open.
        mobileMenu.querySelectorAll('a[href]').forEach((link) => link.addEventListener('click', closeDrawer));
    }
}

export {};
