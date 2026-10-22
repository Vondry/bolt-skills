---
name: bolt-disable-api
description: >-
  Use this skill when the user wants to disable, turn off, or lock down Bolt CMS API endpoints,
  GraphQL, OpenAPI documentation (Swagger UI, ReDoc, Scalar), GraphiQL, or prevent data exposure
  via the API in development and/or production environments.
---

# Disabling API, GraphQL, and OpenAPI Docs in Bolt CMS

This skill guides an agent on how to completely turn off the REST API, GraphQL, and OpenAPI documentation in Bolt CMS across Development and Production environments, or lock down permissions to eliminate unauthorized data exposure.

## Core Architecture Context

Bolt CMS bundles API Platform (`api-platform/core` v4) and Webonyx GraphQL (`webonyx/graphql-php`). By default:
- OpenAPI / Swagger UI is served at `/api/docs.html` and raw schema at `/api/docs.jsonopenapi`.
- GraphiQL IDE is served at `/api/graphql/graphiql`.
- The GraphQL endpoint is active at `/api/graphql`.
- Core entities (`Content`, `Field`, `Relation`) grant read permissions (`api:get`) to `PUBLIC_ACCESS`.
- **The backend depends on the API Platform routes.** The admin listings (dashboard, content overviews) normalise records with the `json_records` Twig filter, which runs API Platform's normalizer, and that normalizer generates an IRI (`/api/contents/{id}`) for every record from the `_api_*` routes. Without those routes every listing fails with `Unable to generate an IRI for the item of type "Bolt\Entity\Content"`.

So the API is shut down by **blocking requests, never by removing routes**: the routes stay registered for IRI generation, the firewall (Step 4) denies every request to `/api`, the documentation engines and GraphiQL are off (Step 2) and the permissions are revoked (Step 3); Step 5 also limits CORS to the API.

---

## Step-by-Step Procedure

### 1. Keep the API Platform Routes Registered
File: `config/routes/api_platform.yaml`

Leave the `api_platform` resource loader **active** and keep `api_entrypoint` (Bolt's backend menu references that route name; removing it causes `RouteNotFoundException`). Do not comment out the loader: the admin needs the `_api_*` routes to generate IRIs (see Core Architecture Context), and the routes expose nothing once Step 4 blocks `/api`. Add a comment so nobody "cleans it up" later:

```yaml
# config/routes/api_platform.yaml

# Must stay registered: Bolt's admin listings generate IRIs from these routes
# ("Unable to generate an IRI" otherwise). The public API is blocked by the
# '^/api(/|$)' ROLE_NO_ACCESS rule in security.yaml (bolt-disable-api).
api_platform:
  resource: .
  type: api_platform
  prefix: /api

api_entrypoint:
  path: '%bolt.backend_url%/api'
  controller: api_platform.action.documentation
```

If an earlier run of this skill commented out the loader, restore it and run `bin/console cache:clear`.

---

### 2. Disable Documentation Engines & GraphiQL Master Flags
File: `config/packages/api_platform.yaml`

Add the documentation and GraphiQL disable flags under the root `api_platform:` key to apply across both development and production environments:

```yaml
# config/packages/api_platform.yaml

api_platform:
  enable_entrypoint: false
  enable_docs: false
  enable_swagger: false
  enable_swagger_ui: false
  enable_re_doc: false
  enable_scalar: false
  graphql:
    graphiql:
      enabled: false
    introspection: false
  mapping:
    # Keep Bolt core's entities: removing this path drops Bolt's API resources and differs
    # from every stock Bolt project. Disabling happens through flags, permissions and the firewall.
    paths: [ '%kernel.project_dir%/vendor/bolt/core/src/Entity', '%kernel.project_dir%/src/Entity' ]
  formats:
    json: [ 'application/json' ]
    jsonld: [ 'application/ld+json' ]
    jsonapi: [ 'application/vnd.api+json' ]
  serializer:
    hydra_prefix: true
  defaults:
    normalization_context:
      skip_null_values: false
    pagination:
      client_items_per_page: true
      items_per_page_parameter_name: 'pageSize'

when@prod:
  api_platform:
    graphql:
      introspection: false
```

The `when@prod` block repeats the root setting on purpose: it is Bolt's stock block, and keeping it unchanged makes the diff against `bolt/project` smaller.

*(Note: Do not set `api_platform.graphql.enabled: false` because in API Platform 4.3, entity attributes declaring `graphQlOperations` without explicit class options trigger a TypeError during Doctrine parameter compilation. The firewall rule in Step 4 achieves full disabling cleanly without this bug).*

---

### 3. Revoke API Permissions & Hide Admin Maintenance Menu Link
File: `config/bolt/permissions.yaml`

1. Change `api_admin: [ ROLE_ADMIN ]` to `api_admin: []` (or `!*`) so the "Bolt API" item is hidden from the Bolt Admin Maintenance menu.
2. Change `api:get: [ PUBLIC_ACCESS ]` to `[ ROLE_ADMIN ]` (or `[]`) to block unauthorized data reading.

```yaml
# config/bolt/permissions.yaml

  # Hide "Bolt API" link from admin menu
  api_admin: []

  # Revoke public data reading
  api:get: [ ROLE_ADMIN ]
  api:post: [ ROLE_ADMIN ]
  api:delete: [ ROLE_ADMIN ]
```

---

### 4. Firewall Lockdown (the Block)
File: `config/packages/security.yaml`

This rule is what turns the API off. Add it as the **first** entry of `security.access_control` so it rejects every request to the `/api` path segment. Nothing grants `ROLE_NO_ACCESS` (keep it out of `role_hierarchy`), so logged-in admins are refused too: anonymous requests get `401`, authenticated ones `403`.

```yaml
# config/packages/security.yaml

security:
  access_control:
    # Public REST/GraphQL API disabled (bolt-disable-api). (/|$) limits the rule to /api and /api/… —
    # a bare '^/api' would also block pages such as /apiary.
    - { path: '^/api(/|$)', roles: ROLE_NO_ACCESS }
```

The backend does not call `/api/*` from the browser (it uses `/bolt/*` and `/bolt/async/*`), so this rule never affects the admin.

---

### 5. Limit CORS to the API
File: `config/packages/nelmio_cors.yaml`

Bolt's stock configuration applies the CORS defaults to every path (`'^/': ~`). Nothing but the API needs cross-origin access, so limit it — with the API blocked, the rule only ever applies to denied responses:

```yaml
# config/packages/nelmio_cors.yaml
nelmio_cors:
  defaults:
    origin_regex: true
    allow_origin: [ '%env(CORS_ALLOW_ORIGIN)%' ]
    allow_methods: [ 'GET', 'OPTIONS', 'POST', 'PUT', 'PATCH', 'DELETE' ]
    allow_headers: [ 'Content-Type', 'Authorization' ]
    expose_headers: [ 'Link' ]
    max_age: 3600
  paths:
    '^/api/': ~
```

Keep `CORS_ALLOW_ORIGIN` at its localhost default unless a real consumer on another origin exists (the lock-down variant); never `*`.

---

### 6. Validate YAML & Clear Caches

Always validate YAML configs and clear Symfony caches:

```bash
bin/console lint:yaml config --parse-tags
bin/console cache:clear
APP_ENV=prod bin/console cache:clear
```

---

## Verification & Testing

Verify that the lockdown succeeded using the following checks:

### 1. Check Routing
Run:
```bash
bin/console debug:router | grep -c " _api_"
```
Expect a non-zero count: the API Platform routes must stay registered (Step 1). `0` means the loader was commented out and the admin listings will fail with "Unable to generate an IRI".

### 2. Check the Firewall Rule
Run:
```bash
bin/console debug:config security access_control
```
The first entry must be `path: ^/api(/|$)` with `roles: [ROLE_NO_ACCESS]`, and no other rule matching `/api` may come before it.

### 3. Run Verification Script
Execute the bundled test script (set `BOLT_BASE_URL` to this project's running site for the HTTP checks; default `http://127.0.0.1:8000`):
```bash
BOLT_BASE_URL=http://localhost:8080 vendor/tomvondracek/bolt-skills/skills/bolt-disable-api/scripts/verify.sh
```
Or verify manually via `curl` (every endpoint must be refused; `404` is acceptable only where the feature is switched off — the documentation and GraphiQL. A `404` on a data endpoint means the routes are gone, which breaks the admin):
- `curl -i http://127.0.0.1:8000/api` -> Expect `404` (the entrypoint is off; routing answers before the firewall)
- `curl -i http://127.0.0.1:8000/api/contents` -> Expect `401` or `403`
- `curl -i http://127.0.0.1:8000/api/contents/1` -> Expect `401` or `403`
- `curl -i http://127.0.0.1:8000/api/docs.html` -> Expect `401`, `403` or `404`
- `curl -i http://127.0.0.1:8000/api/docs.jsonopenapi` -> Expect `401`, `403` or `404`
- `curl -i http://127.0.0.1:8000/api/graphql/graphiql` -> Expect `401`, `403` or `404`
- `curl -i -X POST http://127.0.0.1:8000/api/graphql -H "Content-Type: application/json" -d '{"query":"{ contents { edges { node { id } } } }"}'` -> Expect `401` or `403`
- `curl -i http://127.0.0.1:8000/index.php/api/contents` -> Expect `401` or `403` (front-controller path), or on Apache with `bolt-htaccess` a `301` to `/api/contents`. A `200` HTML page is not the API but a front-controller path that is not redirected — fix it with `bolt-htaccess` Pitfall 10.

### 4. Check the Backend
Log in to `/bolt/` and open the dashboard and at least one content listing (`/bolt/content/<contenttype>`). Both must render. A 500 with "Unable to generate an IRI" means the API Platform routes were removed (Step 1). Clear the cache first (`bin/console cache:clear`): Bolt caches normalised records, so a warm cache can hide the error until the next deploy.

## Pitfalls

- **Commenting out the `api_platform` route loader breaks the admin.** It looks like the cleanest way to remove the API, and older versions of this skill recommended it, but the admin generates IRIs from those routes. Block `/api` in the firewall instead.
- **A warm cache hides the breakage.** The error appears only after `cache:clear` or a deploy, often days later and after unrelated commits. Always clear the cache and open the admin listings after changing API configuration.
- **The firewall rule is the only thing blocking requests.** Removing or narrowing `^/api(/|$)` reopens the API (protected only by the `api:*` permissions). `verify.sh` checks the rule and the live endpoints; keep it in the audit.
