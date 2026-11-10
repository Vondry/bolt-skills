// Pencils render check (bolt-edit-links). Run it in the browser console — or a browser automation
// tool's JavaScript runner — on any frontend page while logged in to the Bolt admin in that browser.
//
// It loads the pages of the sitemap and the pages they link to (GET only), collects every pencil
// (the macro's links carry ?edit_locale=, whatever path the admin is on), then loads each editor page and confirms the tab named by the link's hash
// exists. Bolt's editor looks the hash up with the selector used here and throws when it finds
// nothing, which stops the rest of its scripts on that page.
//
// Result: { pages, pencils, pagesWithoutPencil, missingTabs: [{ pencil, tab, pages }], errors }.
// `missingTabs` and `errors` must be empty. Review `pagesWithoutPencil`: only pages without a
// record of their own belong there. Pencils found on no page at all mean you are not logged in.
(async () => {
    const LIMIT = 300;
    const NOT_PAGES = /^\/(bolt|_profiler|_wdt|api|files|thumbs|theme|bundles|assets)(\/|$)|\.[a-z0-9]{2,5}$/i;
    const pages = new Set([location.pathname]);
    const errors = [];

    const addPage = (href) => {
        let url;
        try {
            url = new URL(href, location.href);
        } catch (e) {
            return;
        }
        if (url.origin === location.origin && !NOT_PAGES.test(url.pathname) && pages.size < LIMIT) pages.add(url.pathname);
    };

    const readSitemap = async (path, depth = 0) => {
        let response;
        try {
            response = await fetch(path, { credentials: 'same-origin' });
        } catch (e) {
            return;
        }
        if (!response.ok) return;
        const xml = new DOMParser().parseFromString(await response.text(), 'application/xml');
        for (const loc of xml.getElementsByTagName('loc')) {
            const url = new URL(loc.textContent.trim(), location.href);
            if (url.pathname.endsWith('.xml')) {
                if (depth < 2) await readSitemap(url.pathname, depth + 1);
            } else if (url.pathname !== '/' || url.origin === location.origin) {
                pages.add(url.pathname);
            }
        }
    };
    await readSitemap('/sitemap.xml');

    const pencils = new Map(); // editor URL → pages showing it
    const pagesWithoutPencil = [];
    const visited = new Set();
    for (let queue = [...pages]; queue.length > 0; queue = [...pages].filter((page) => !visited.has(page))) {
        for (const page of queue) {
            visited.add(page);
            let response;
            try {
                response = await fetch(page, { credentials: 'same-origin' });
            } catch (e) {
                errors.push({ page, error: e.message });
                continue;
            }
            if (!response.ok) {
                errors.push({ page, error: `HTTP ${response.status}` });
                continue;
            }
            const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
            const onPage = doc.querySelectorAll('a[href*="edit_locale="]');
            if (onPage.length === 0) pagesWithoutPencil.push(page);
            for (const a of onPage) {
                const href = a.getAttribute('href');
                if (!pencils.has(href)) pencils.set(href, []);
                if (!pencils.get(href).includes(page)) pencils.get(href).push(page);
            }
            for (const a of doc.querySelectorAll('a[href]:not([href*="edit_locale="])')) addPage(a.getAttribute('href'));
        }
    }

    const missingTabs = [];
    const editors = new Map(); // editor page without its hash → its document
    for (const [pencil, shownOn] of pencils) {
        const url = new URL(pencil, location.href);
        const editor = url.pathname + url.search;
        if (!editors.has(editor)) {
            let response;
            try {
                response = await fetch(editor, { credentials: 'same-origin' });
            } catch (e) {
                errors.push({ page: editor, error: e.message });
                continue;
            }
            if (!response.ok) {
                errors.push({ page: editor, error: `HTTP ${response.status}` });
                continue;
            }
            editors.set(editor, new DOMParser().parseFromString(await response.text(), 'text/html'));
        }
        if (url.hash && !editors.get(editor).querySelector(`a[href="${url.hash}"]`)) {
            missingTabs.push({ pencil, tab: url.hash.slice(1), pages: shownOn });
        }
    }

    const result = { pages: visited.size, pencils: pencils.size, pagesWithoutPencil, missingTabs, errors };
    console.log('[bolt-edit-links]', result);
    return result;
})();
