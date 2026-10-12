---
name: performance
description: Diagnoses and fixes Drupal 10/11 performance problems - the caching layers (CDN and reverse proxy, Internal Page Cache, Dynamic Page Cache, BigPipe, render cache, cache backends), lazy builders and placeholders, cache debugging headers, avoiding N+1 entity loads and heavy entity queries, batch and queue work, cron, and front-end assets. Use when a Drupal page or API is slow, the cache hit rate is low, pages are uncacheable for anonymous users, memory runs out in loops, or before shipping code that renders lists or per-user content.
---

# Drupal performance

Measure first: response time with and without cache, cache headers, query count and a
profiler (XHProf, Blackfire, Tideways or similar). Fix the biggest cause, then measure again.

## Caching layers, outermost first

| Layer | Serves | Breaks when |
|---|---|---|
| CDN / reverse proxy | Anonymous pages, using `Cache-Control` from *Performance > Browser and proxy cache maximum age* (`system.performance:cache.page.max_age`) | The page sets cookies or a session; max age is 0 |
| Internal Page Cache (`page_cache`) | Whole responses for anonymous users | Something starts a session for anonymous users; `page_cache_kill_switch` is triggered |
| Dynamic Page Cache (`dynamic_page_cache`) | Responses for every user, with personalized parts as placeholders | High-cardinality contexts or `max-age: 0` bubble to the page without a placeholder |
| BigPipe (`big_pipe`) | Streams placeholders after the cached page shell | Placeholders that are slow to build still delay the end of the response |
| Render cache | Elements with `#cache['keys']`; blocks and entities have keys | Missing tags (stale), contexts that are too broad (low hit rate) |
| Cache backends | The `cache_*` bins in the database by default | Large sites: move bins to Redis or Memcache (contrib) |

Read the headers: `X-Drupal-Cache: HIT|MISS` (page cache) and
`X-Drupal-Dynamic-Cache: HIT|MISS|UNCACHEABLE`. Locally, set
`http.response.debug_cacheability_headers: true` in `development.services.yml` to see
`X-Drupal-Cache-Tags`, `X-Drupal-Cache-Contexts` and `X-Drupal-Cache-Max-Age`. `UNCACHEABLE`
almost always means a context such as `user` or `session`, or `max-age: 0`, reached the page.
The `max-age` of render arrays does not reach the Internal Page Cache; expire anonymous pages
with cache tags.

## Keep the page cacheable: placeholders for per-user parts

```php
// In a block build() or controller: the rest of the page stays cacheable.
$build['greeting'] = [
  '#lazy_builder' => [GreetingLazyBuilder::class . ':build', []],
  '#create_placeholder' => TRUE,
];
```

```php
final class GreetingLazyBuilder implements TrustedCallbackInterface {

  use StringTranslationTrait;

  public function __construct(private readonly AccountProxyInterface $currentUser) {}

  public static function trustedCallbacks(): array {
    return ['build'];
  }

  public function build(): array {
    return [
      '#markup' => $this->t('Hello @name', ['@name' => $this->currentUser->getDisplayName()]),
      '#cache' => ['contexts' => ['user']],
    ];
  }

}
```

Register the class as a service (`Drupal\my_module\GreetingLazyBuilder: ~` with autowiring).
Lazy builder arguments may only be scalars or NULL; pass IDs, not objects. Elements built by
a lazy builder with the `user`/`session` context or `max-age: 0` are placeholdered
automatically (`renderer.config: auto_placeholder_conditions`).

## Cache metadata hygiene

- Choose the narrowest context that is correct: `user.permissions` or `user.roles` before
  `user`; `url.query_args:page` before `url.query_args`; `url.path` before `url`.
- Tag what you show (`node:5`, `node_list:article`, `config:my_module.settings`) and
  invalidate custom tags when the underlying data changes (`Cache::invalidateTags()`).
- Never `max-age: 0` for "it changes sometimes": use tags, or a time-based max-age plus a
  placeholder.
- Avoid `drupal_flush_all_caches()` / `drush cr` as a runtime fix; it hides missing tags.

## N+1 entity loads and heavy queries

```php
// Bad: one query per row, entity hooks per row.
foreach ($nids as $nid) {
  $titles[] = Node::load($nid)->label();
}

// Good: one multiple load.
foreach ($this->entityTypeManager->getStorage('node')->loadMultiple($nids) as $node) {
  $titles[] = $node->label();
}

// Good: collect referenced IDs across all rows, then load once.
$tids = [];
foreach ($nodes as $node) {
  foreach ($node->get('field_tags') as $item) {
    $tids[$item->target_id] = $item->target_id;
  }
}
$terms = $this->entityTypeManager->getStorage('taxonomy_term')->loadMultiple($tids);
```

- Need only a number or IDs? `->count()->execute()` or `->execute()` on the entity query;
  do not load entities to count them. Page with `->range()` or `->pager()`.
- `$entity->get('field_x')->referencedEntities()` loads the references of one entity in one
  query; across many entities, collect IDs first as above.
- Render lists through the view builder (`viewMultiple()`) and a view mode, so each item is
  render-cached on its own.
- Reports over large tables: use the Database API with an aggregate query, but keep access
  rules (`node_access` tag, or explicit checks) when the result reaches users.
- Long-running work goes to the Batch API (interactive) or a `#[QueueWorker]` with `cron`
  (background). Since 11.2 the entity static cache is an LRU memory cache, but still process
  large sets in chunks (and call `resetCache()` on older cores).
- Watch for queries inside `hook_entity_load`, `hook_node_access`, preprocess and Twig
  extensions; they run per entity.

## Cron, assets and other quick wins

- Run cron from the system scheduler (`drush cron`) on busy sites; Automated Cron runs at the
  end of a visitor's request.
- Keep CSS and JS aggregation on in production (`system.performance` `css.preprocess`,
  `js.preprocess`); Drupal 11.4 also serves Brotli-compressed aggregates when the PHP brotli
  extension is installed.
- Images: image styles or responsive image styles, the formatter's lazy loading setting, and
  width/height attributes to avoid layout shift.
- Attach libraries only where they are used (`attach_library` or `#attached`), not globally.
- After deploys, `drush deploy` warms caches on Drupal 11.2+ (`drush cache:warm`).
- Never ship the local cache overrides from `example.settings.local.php`
  (`cache.backend.null` for render, page and dynamic page cache bins) to production.
