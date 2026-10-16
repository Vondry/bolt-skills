---
name: bolt-performance
description: >-
  Optional performance step for Bolt CMS 6: Twig fragment caching ({% cache %} from
  twig/cache-extra) wired to the cache pool that Bolt invalidates on content save, a reusable
  partials/_cached.twig that caches on GET only (Bolt's preview and forms render live), tagging
  rules (ContentType slugs, record.cacheKey), what never to cache, and a verification of the
  setup. Use it for pages with a high query count — homepages that aggregate several
  ContentTypes, record pages with relations — or when auditing existing {% cache %} usage.
---

# Bolt CMS Twig Fragment Cache (optional)

Bolt 6 loads every field of a record, then each field's translations with **one query per
field**, the taxonomies with one query per record and relations with one query per `related()`
call. A homepage that lists projects, companies and their positions reaches 200+ queries. For
such pages, cache the rendered HTML of the heavy containers; Bolt's own content-save events then
clear it, so editors never see stale content.

This step is **optional**. Small pages do not need it, and a site without any `{% cache %}` passes
the verification.

Measured on a production Bolt 6.1.8 site (PHP 8.2, OPcache, SQLite, `APP_ENV=prod`): the portfolio
homepage (projects, companies, positions, experiences) went from **79 ms / 234 queries to 23 ms /
21 queries** on a cache hit. Saving a company record in the admin cleared the fragment; the next
request rebuilt it with the change, in every locale.

---

## Step 1: Decide Which Pages Need It

In dev, open the Symfony toolbar's Doctrine panel (`/_profiler`) on the homepage and each page
orchestrator and note the query count. Pages above roughly **100 queries** are candidates; below
that the gain is small. Typical sources:

| Template does | Queries |
| :--- | :--- |
| Load one record | ~4 + one per field (translations) |
| `setcontent` listing of N records | 2–4 (paging) + per record: one per field + one for taxonomies |
| `record|related` / `related_by_field` | one per call, plus the related records' fields |
| `record.taxonomies` inside a loop | one per record |

---

## Step 2: Install and Wire It to Bolt's Pool

```bash
composer require twig/cache-extra        # twig/extra-bundle is already part of bolt/project
```

Add to `config/services.yaml` ([`examples/services_twig_cache.yaml`](examples/services_twig_cache.yaml)):

```yaml
services:
  # {% cache %} must use the pool Bolt invalidates on content save (cache.app.taggable);
  # twig/extra-bundle's default is a separate pool that Bolt never clears.
  twig.runtime.cache:
    class: Twig\Extra\Cache\CacheRuntime
    arguments: ['@cache.app.taggable']
    tags: ['twig.runtime']
```

Why: saving or deleting a record makes Bolt (`ContentSaveSubscriber`) invalidate the tags
`frontendmenu`, `backendmenu`, the record's ContentType slug and `record-<id>` — in
`cache.app.taggable`. twig/extra-bundle's own `twig.cache` pool is a different pool, so without
this override fragments are refreshed only by their TTL.

---

## Step 3: The Reusable Partial

Copy [`examples/_cached.twig`](examples/_cached.twig) to `public/theme/<theme>/partials/_cached.twig`.
It renders a container through `{% cache %}` on GET (and HEAD) requests and live on everything else — Bolt's
preview is `POST /preview/{id}`, and forms post back:

```twig
{# pages/homepage/homepage.twig — page orchestrator #}
{% block main %}
    {% include 'pages/homepage/components/hero.twig' with { record: record } %}

    {{ include('partials/_cached.twig', {
        key: 'home.featured-products;v1',
        tags: ['products'],
        template: 'containers/products/_featured-products.twig',
        with: { limit: 3 }
    }) }}
{% endblock main %}
```

Parameters: `key` (required), `tags` (required), `template` (required), `with`, `vary`, `ttl`
(default 3600). More patterns — paged listing, record detail with relations, date-dependent
content — are in [`examples/fragment-cache.twig`](examples/fragment-cache.twig).

---

## Step 4: Rules

* **`tags`** — every ContentType whose records the fragment shows, by its **slug**: the `slug:` in
  `contenttypes.yaml`, or the slugified `name` when there is none — not the YAML key (`projects:`
  with `slug: projekty` is tagged `projekty`), and with its hyphens (`ke-stazeni`, not
  `kestazeni`). For a fragment of one record add `record.cacheKey` (`record-00015`), which Bolt
  invalidates when that record is saved. A ContentType missing from `tags` shows its edits only
  after the TTL.
* **`key`** — unique per fragment; the partial adds the locale. Fragments that print absolute URLs (`url()`, `absolute_url()`, `record|link(true)`) also depend on the host: cache them only on a site that answers on one host (the other one redirects, `bolt-htaccess`), or print relative paths inside the fragment. Add everything else the output
  depends on through `vary` (`'p' ~ app.request.query.getInt('page', 1)` for paged listings). No
  `{}()/\@:` characters — never a raw URL path.
* **`ttl`** — the safety net (default 3600 s). Timed publishing and depublishing change records
  through plain SQL without a save event; the passing of time (upcoming events) does not fire one
  either — use a short `ttl` or put the date into the key.
* **Never cache** anything with a form or CSRF token, `app.user`, `app.session`, `app.flashes`, the
  header / menus (their active state depends on the current URL) or the `seo` block. Cache
  containers inside `{% block main %}`, not the layout.
* **Deploys clear it.** The pool lives in `var/cache/prod/`, which is deleted after each upload
  (`bolt-security-hardening` Step 7). Bump `;v1` → `;v2` only if a template change must show
  without that.
* **Test the invalidation once per site:** load the page twice (the second is fast), save a record
  of each tagged ContentType in the admin, reload — the change must be there.

---

## Verification

```bash
bash $SKILLS/bolt-performance/scripts/verify.sh
```

Passes without further checks when the theme has no `{% cache %}`. Otherwise:

| Checks | Fails when |
| :--- | :--- |
| `twig/cache-extra` installed | missing — templates with `{% cache %}` do not compile |
| `twig.runtime.cache` overridden to `@cache.app.taggable` | missing — fragments ignore content saves |
| contents of every `{% cache %}` block, and the `template:` of every `partials/_cached.twig` call, following literal includes to any depth | a form, `csrf_token`, `app.user`, `app.session`, `app.flashes` or `is_granted` inside |
| `tags()` present, GET-only rendering, literal tags are ContentType slugs | — (warnings) |

## Common Pitfalls

* **Edits do not show up** → the `twig.runtime.cache` override is missing (Step 2), or a ContentType
  is missing from `tags`, or it is written as the YAML key / without its `-` instead of the slug.
* **Preview shows the saved version** → the fragment uses `{% cache %}` directly instead of
  `partials/_cached.twig` (preview is a POST).
* **`Unknown "cache" tag`** → `composer require twig/cache-extra` was not run or `vendor/` was not
  uploaded.
* **`Cache key … contains reserved characters`** → a key with `/` or `:`; use names, not URLs.
* **Template changes do not appear on the server** → `var/cache/prod/` was not deleted after the
  upload; Twig does not check timestamps in prod.
