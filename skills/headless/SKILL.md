---
name: headless
description: Exposes Drupal 10/11 content to decoupled front ends and other systems - core JSON:API (resource URLs, include, sparse fieldsets, filters, sorting, pagination, revisions, writes), choosing between JSON:API, REST resources and custom JSON controllers, authentication (cookie plus CSRF token, OAuth via Simple OAuth), CORS, access and caching of API responses. Use when building or consuming a Drupal API, connecting a JavaScript or mobile front end, enabling JSON:API writes, or debugging missing, slow or leaking API data.
---

# Headless and APIs

## Pick the interface

| Need | Use |
|---|---|
| Read/write entities with a standard format | Core **JSON:API** (`jsonapi` module): zero configuration, follows entity and field access |
| A few custom operations or aggregated data | A controller returning `CacheableJsonResponse` (see `module-development`) or a REST resource plugin (`rest` module) |
| GraphQL | Contrib (GraphQL module), not covered here |

## JSON:API essentials

- Resources: `/jsonapi/{entity_type}/{bundle}` and `/jsonapi/{entity_type}/{bundle}/{uuid}`
  (UUIDs, not numeric IDs); types are named `node--article`, `taxonomy_term--tags`.
  The prefix is the `jsonapi.base_path` container parameter.
- Read-only by default (`jsonapi.settings:read_only`); allow writes at
  `/admin/config/services/jsonapi` only if clients really create or update content.
- Ask only for what you render:
  ```
  GET /jsonapi/node/article
      ?filter[status]=1
      &filter[tags][condition][path]=field_tags.name
      &filter[tags][condition][operator]=IN
      &filter[tags][condition][value][]=Drupal
      &sort=-created
      &include=field_image,uid
      &fields[node--article]=title,created,field_image,uid
      &fields[file--file]=uri,filemime
      &fields[user--user]=display_name
      &page[limit]=20
  ```
- Pagination: `page[limit]` is capped at 50. Follow `links.next`; do not compute offsets.
- Filters are not access control. Inaccessible resources are left out of collections and
  listed under `meta.omitted`; add `filter[status]=1` so anonymous clients do not trigger
  omissions for unpublished content.
- Revisions: `?resourceVersion=rel:latest-version` or `rel:working-copy` (for preview with
  content moderation), subject to revision access.
- Writes use `Content-Type: application/vnd.api+json` and a JSON:API document with `type`,
  `attributes` and `relationships`. Validation errors come back as JSON:API errors with 422.

## Authentication

- Same-site JavaScript with a Drupal session: cookie auth plus the `X-CSRF-Token` header,
  fetched from `/session/token`, on every unsafe request.
- Other clients: OAuth 2 with Simple OAuth (contrib, uses Consumers). Basic Auth (core
  `basic_auth`) only for server-to-server calls over HTTPS with a dedicated low-privilege user.
- Give API users a role with the minimum permissions; JSON:API exposes whatever that role can
  see, including fields you did not think about (email, revision log, internal flags).

## Limit and shape the surface

- JSON:API Extras (contrib) can disable resource types, rename paths and fields, and set
  default includes. Disable what front ends do not need (users, configuration entities).
- Entity types defined as internal (`internal: TRUE` in the entity type attribute) get no
  resource. Hide sensitive fields with field access (`hook_entity_field_access()`) so every
  output path respects it, and check `$items->access('view')` in custom normalizers.
- Path aliases to entities: Decoupled Router (contrib) resolves a URL path to the JSON:API
  resource of the entity behind it.

## CORS for browser clients on another origin

In `services.yml` (per environment):

```yaml
parameters:
  cors.config:
    enabled: true
    allowedHeaders: ['content-type', 'authorization', 'x-csrf-token']
    allowedMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS']
    allowedOrigins: ['https://www.example.com']
    allowedOriginsPatterns: []
    exposedHeaders: false
    maxAge: false
    supportsCredentials: true
```

Never combine `allowedOrigins: ['*']` with credentials. List exact origins per environment.

## Caching API responses

- JSON:API responses carry cache tags and contexts like pages do: anonymous GETs are served
  by the Internal Page Cache, authenticated ones by the Dynamic Page Cache. Includes add the
  tags of every included entity.
- Put a CDN or reverse proxy in front and purge by cache tag (Purge module plus a purger for
  your CDN) instead of short TTLs.
- Keep includes shallow and bounded; deep include chains on large collections are the most
  common cause of slow responses.
- Custom endpoints: return `CacheableJsonResponse` and add every entity, config object and
  access result you used with `addCacheableDependency()`; plain `JsonResponse` is never cached.

## Review checklist for API work

- [ ] Writes disabled unless needed; write permissions granted to a dedicated role only.
- [ ] No sensitive fields or entity types exposed to anonymous users (check `/jsonapi` as
      anonymous).
- [ ] CSRF token or OAuth on every unsafe method; CORS limited to known origins.
- [ ] Responses cacheable (`X-Drupal-Cache` / `X-Drupal-Dynamic-Cache` HIT on repeat).
- [ ] Clients use sparse fieldsets and follow `links.next`.
