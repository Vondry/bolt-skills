// Admin icons render check (bolt-contenttypes rule 11). Run it in the browser console — or a
// browser automation tool's JavaScript runner — on any page of the logged-in Bolt admin (/bolt/).
//
// It reads the Font Awesome icon classes the admin's own stylesheets define, then loads the
// dashboard and every content listing, edit and new page linked from the sidebar (GET only)
// and reports every <i class="fa-…"> whose icon class has no ::before rule — rendered as an
// empty box. ContentType icons appear on all of them: the sidebar (icon_many), the listing and
// edit headings, the dashboard rows and the sidebar submenus (icon_one).
//
// Result: { fontAwesome, pages, icons, missing: [{ icon, where, pages }], errors } — `missing` and
// `errors` must be empty.
(async () => {
    // Size, animation and layout modifiers are not icons.
    const MODIFIER = /^fa-(fw|xs|sm|lg|[0-9]+x|spin|pulse|border|inverse|li|ul|stack(-[12]x)?|pull-(left|right)|rotate-[0-9]+|flip-(horizontal|vertical|both))$/;

    const defined = new Set();
    let version = null;
    const walk = (rules) => {
        for (const rule of rules) {
            if (rule.cssRules) walk(rule.cssRules);
            for (const m of (rule.selectorText || '').matchAll(/\.fa-([a-z0-9-]+)::?before/g)) defined.add(m[1]);
        }
    };
    for (const sheet of document.styleSheets) {
        try {
            walk(sheet.cssRules);
        } catch (e) {
            continue; // cross-origin stylesheet
        }
    }
    for (const link of document.querySelectorAll('link[rel="stylesheet"][href*="/assets/"]')) {
        const css = await (await fetch(link.href)).text();
        version = version || (css.match(/Font Awesome Free (\d+\.\d+\.\d+)/) || [])[1] || null;
    }

    const pages = new Set(['/bolt/']);
    for (const a of document.querySelectorAll('a[href]')) {
        const url = new URL(a.href, location.href);
        if (url.origin === location.origin && /^\/bolt\/(content|edit|new)\//.test(url.pathname)) {
            pages.add(url.pathname + url.search);
        }
    }

    const missing = new Map(); // "icon @ where" → { icon, where, pages }
    const errors = [];
    let icons = 0;
    for (const page of pages) {
        let response;
        try {
            // A singleton's listing redirects to its edit page, which the sidebar links too.
            response = await fetch(page, { credentials: 'same-origin', redirect: 'manual' });
        } catch (e) {
            errors.push({ page, error: e.message });
            continue;
        }
        if (response.type === 'opaqueredirect') continue;
        if (!response.ok) {
            errors.push({ page, error: `HTTP ${response.status}` });
            continue;
        }
        const html = await response.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const check = (classes, where) => {
            for (const name of classes.filter((c) => c.startsWith('fa-') && !MODIFIER.test(c))) {
                icons++;
                if (defined.has(name.slice(3))) continue;
                const key = `${name} @ ${where}`;
                if (!missing.has(key)) missing.set(key, { icon: name, where, pages: [] });
                if (!missing.get(key).pages.includes(page)) missing.get(key).pages.push(page);
            }
        };

        // Icons in the server-rendered HTML: headings, listings, buttons.
        for (const el of doc.querySelectorAll('i[class*="fa-"], span[class*="fa-"]')) {
            check([...el.classList], (el.closest('a, h1, h2, button, li') || el.parentElement).textContent.trim().replace(/\s+/g, ' ').slice(0, 60));
        }

        // Icons the Vue components render in the browser — the sidebar and toolbar menus and the
        // dashboard listing — arrive as JSON in their attributes (<admin-sidebar :menu='…'>).
        // Empty values are field definitions (Bolt's FieldType defaults `icon` to ''), not icons.
        for (const el of doc.querySelectorAll('*')) {
            if (!el.tagName.includes('-')) continue;
            for (const attr of el.attributes) {
                for (const m of attr.value.matchAll(/"icon"\s*:\s*"((?:[^"\\]|\\.)+)"/g)) {
                    check(JSON.parse(`"${m[1]}"`).replace('fa:', 'fa-').split(/\s+/), `<${el.tagName.toLowerCase()} ${attr.name}>`);
                }
            }
        }
    }

    return { fontAwesome: version, pages: pages.size, icons, missing: [...missing.values()], errors };
})();
