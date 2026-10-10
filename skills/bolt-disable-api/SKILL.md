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

To completely shut down the API and documentation without breaking Bolt's backend admin panel, changes must be applied across four layers; Step 5 also limits CORS to the API.

---

## Step-by-Step Procedure

### 1. Unregister API Platform Routes
File: `config/routes/api_platform.yaml`

Comment out the `api_platform` resource loader to unregister all `/api/*` routes (`/api/graphql`, `/api/graphql/graphiql`, `/api/docs.*`, `/api/contents`, etc.).

> **Important**: Keep the `api_entrypoint` route definition intact (`path: '%bolt.backend_url%/api'`). Bolt's backend admin menu references this route name; leaving the route defined prevents `RouteNotFoundException`.

```yaml
# config/routes/api_platform.yaml

# api_platform:
#   resource: .
#   type: api_platform
#   prefix: /api

api_entrypoint:
  path: '%bolt.backend_url%/api'
  controller: api_platform.action.documentation
```

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
    # from every stock Bolt project. Disabling happens through routes, flags and the firewall.
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

*(Note: Do not set `api_platform.graphql.enabled: false` because in API Platform 4.3, entity attributes declaring `graphQlOperations` without explicit class options trigger a TypeError during Doctrine parameter compilation. Route unregistration and firewall rules achieve full disabling cleanly without this bug).*

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

### 4. Firewall Lockdown (Defense in Depth)
File: `config/packages/security.yaml`

Add an access control rule at the top of `security.access_control` to reject any incoming request to the `/api` path segment:

```yaml
# config/packages/security.yaml

security:
  access_control:
    # (/|$) limits the rule to /api and /api/… — a bare '^/api' would also block pages such as /apiary
    - { path: '^/api(/|$)', roles: ROLE_NO_ACCESS }
```

---

### 5. Limit CORS to the API
File: `config/packages/nelmio_cors.yaml`

Bolt's stock configuration applies the CORS defaults to every path (`'^/': ~`). Nothing but the API needs cross-origin access, so limit it — with the API removed, the rule simply never matches:

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
bin/console debug:router | grep -E "api|graphql|doc"
```
Ensure that no `/api/graphql`, `/api/graphql/graphiql`, or `/api/docs` routes are present. Only `api_entrypoint` (`/bolt/api`) should remain.

### 2. Run Verification Script
Execute the bundled test script (set `BOLT_BASE_URL` to this project's running site for the HTTP checks; default `http://127.0.0.1:8000`):
```bash
BOLT_BASE_URL=http://localhost:8080 vendor/tomvondracek/bolt-skills/skills/bolt-disable-api/scripts/verify.sh
```
Or verify manually via `curl`:
- `curl -i http://127.0.0.1:8000/api/docs.html` -> Expect `401` or `404`
- `curl -i http://127.0.0.1:8000/api/docs.jsonopenapi` -> Expect `401` or `404`
- `curl -i http://127.0.0.1:8000/api/graphql/graphiql` -> Expect `401` or `404`
- `curl -i -X POST http://127.0.0.1:8000/api/graphql -H "Content-Type: application/json" -d '{"query":"{ contents { edges { node { id } } } }"}'` -> Expect `401` or `404`
- `curl -i http://127.0.0.1:8000/api/contents` -> Expect `401` or `404`
