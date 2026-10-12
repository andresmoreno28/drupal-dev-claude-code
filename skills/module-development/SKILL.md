---
name: module-development
description: Writes and refactors custom Drupal 10/11 module code the current way - services and dependency injection, object-oriented hooks with the Hook attribute, plugins declared with PHP attributes, event subscribers, routes and controllers, forms and ConfigFormBase, entity queries, and render cache metadata (tags, contexts, max-age). Use when creating or changing PHP in a Drupal module, adding a hook, block, service, route, form, queue worker or event subscriber, or when rendered output is stale, leaks between users or ignores permissions.
---

# Drupal module development

Target Drupal 11 (11.4 is the current minor; 11.5 and 12.0 are scheduled for the week of
7 December 2026). Check `core_version_requirement` in the module's `*.info.yml` before picking
an API: if it still includes `^10`, use the backwards-compatible variants marked **BC** below.

## Ground rules

- New PHP files: `declare(strict_types=1);`, typed parameters, properties and returns,
  constructor property promotion, `final` classes unless extension is intended.
- Classes get dependencies injected. `\Drupal::service()` is for procedural code only
  (`.module`, `.install`, hooks that must stay procedural).
- Plugins and forms use `DependencySerializationTrait`, which cannot restore `private`
  service properties after serialization (core issue #3110266; phpstan-drupal reports it).
  Inject into `protected` properties there; `private` is fine in plain services and hooks.
- Entity queries must call `->accessCheck(TRUE|FALSE)`; core throws a `QueryException`
  otherwise. Use `TRUE` for anything shown to a user; `FALSE` only for system work, with a comment.
- Every render array that depends on data carries cache metadata (see the last section).
- Scaffold with `drush generate` if you like, then align the output with this skill.

## Layout

```
my_module/
  my_module.info.yml         my_module.services.yml   my_module.routing.yml
  my_module.permissions.yml  my_module.libraries.yml  my_module.install
  config/install/            config/schema/my_module.schema.yml
  src/Hook/  src/Controller/  src/Form/  src/Plugin/Block/  src/EventSubscriber/
  tests/src/Unit/  tests/src/Kernel/  tests/src/Functional/
```

```yaml
# my_module.info.yml
name: My module
type: module
description: 'Counts articles per author.'
package: Custom
core_version_requirement: ^11
dependencies:
  - drupal:node
```

## Services and dependency injection

```yaml
# my_module.services.yml
services:
  _defaults:
    autowire: true       # constructor arguments resolved by type
    autoconfigure: true  # e.g. event subscribers are tagged automatically
  Drupal\my_module\ArticleCounter: ~
```

```php
final class ArticleCounter {

  public function __construct(
    private readonly EntityTypeManagerInterface $entityTypeManager,
    private readonly AccountProxyInterface $currentUser,
  ) {}

  public function countForCurrentUser(): int {
    return (int) $this->entityTypeManager->getStorage('node')->getQuery()
      ->accessCheck(TRUE)
      ->condition('type', 'article')
      ->condition('uid', $this->currentUser->id())
      ->count()
      ->execute();
  }

}
```

Core aliases its main interfaces (`EntityTypeManagerInterface`, `ConfigFactoryInterface`,
`AccountProxyInterface`, `Connection`, `TimeInterface`, ...) for autowiring. For a service
without an alias, use `#[Autowire(service: 'service.id')]` on the parameter.
`ControllerBase` autowires its constructor (Drupal 10.2+); so do plugins that extend core's
`PluginBase` and implement `ContainerFactoryPluginInterface` (11.3+), and `FormBase` (11.4).
**BC**: on older cores add the classic `create(ContainerInterface $container)` factory.

## Hooks: OOP with `#[Hook]` (Drupal 11.1+)

Classes in `src/Hook/` are registered as autowired services automatically.

```php
namespace Drupal\my_module\Hook;

use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Hook\Attribute\Hook;
use Drupal\Core\StringTranslation\StringTranslationTrait;
use Drupal\my_module\ArticleNotifier;
use Drupal\node\NodeInterface;

final class MyModuleHooks {

  use StringTranslationTrait;

  public function __construct(private readonly ArticleNotifier $notifier) {}

  #[Hook('node_insert')]
  public function nodeInsert(NodeInterface $node): void {
    if ($node->bundle() === 'article') {
      $this->notifier->notify($node);
    }
  }

  #[Hook('form_node_form_alter')]
  public function nodeFormAlter(array &$form, FormStateInterface $form_state, string $form_id): void {
    $form['revision_log']['#access'] = FALSE;
  }

}
```

- Ordering (11.2+): `#[Hook('entity_presave', order: Order::First)]`, or
  `order: new OrderBefore(['other_module'])` / `new OrderAfter([...])`
  (`Drupal\Core\Hook\Order\*`). `#[ReorderHook]` and `#[RemoveHook]` act on other modules'
  implementations and replace most uses of `hook_module_implements_alter()`.
- Must stay procedural: `hook_install`, `hook_uninstall`, `hook_schema`, `hook_update_N`,
  `hook_post_update_NAME`, `hook_update_last_removed`, `hook_hook_info`,
  `hook_module_implements_alter`, install tasks. Keep them in `.install` / `.post_update.php`.
- Themes can use OOP hooks from 11.3 (`src/Hook/` in the theme, no `order`/`module` params).
- Procedural hooks still work; the change record expects removal no earlier than Drupal 13.
- **BC (10.1-11.0)**: keep a procedural shim marked `#[LegacyHook]` that calls
  `\Drupal::service(MyModuleHooks::class)->nodeInsert($node)`, and register the class in
  `services.yml` (`Drupal\my_module\Hook\MyModuleHooks: { class: ..., autowire: true }`).

## Plugins: PHP attributes, not annotations

```php
#[Block(
  id: 'my_module_article_count',
  admin_label: new TranslatableMarkup('My article count'),
)]
final class ArticleCountBlock extends BlockBase implements ContainerFactoryPluginInterface {

  public function __construct(array $configuration, $plugin_id, $plugin_definition,
    protected readonly ArticleCounter $counter,
  ) {
    parent::__construct($configuration, $plugin_id, $plugin_definition);
  }

  public function build(): array {
    return [
      '#markup' => $this->t('You wrote @count articles.', ['@count' => $this->counter->countForCurrentUser()]),
      '#cache' => ['contexts' => ['user'], 'tags' => ['node_list:article']],
    ];
  }

}
```

Other core attributes follow the same shape: `#[FieldFormatter(...)]`, `#[FieldWidget(...)]`,
`#[FieldType(...)]`, `#[QueueWorker(id: ..., title: ..., cron: ['time' => 30])]`,
`#[MigrateProcess(...)]`. Annotation parsing for plugins is supported until Drupal 13; a
custom plugin *type* must provide an attribute class (required in Drupal 12).

## Routes, controllers, permissions

```yaml
# my_module.routing.yml
my_module.report:
  path: '/node/{node}/report'
  defaults:
    _controller: '\Drupal\my_module\Controller\ReportController::build'
    _title: 'Article report'
  requirements:
    _permission: 'view my_module reports'
    _entity_access: 'node.view'
    node: \d+
```

Requirements are ANDed. `{node}` is upcast to the entity. Other checks: `_custom_access`,
`_csrf_token: 'TRUE'` (state-changing GET links), `_format`. Never ship a route without a
requirement; `_access: 'TRUE'` must be a deliberate, commented choice.

```yaml
# my_module.permissions.yml
view my_module reports:
  title: 'View My module reports'
  restrict access: true
```

## Forms

```php
final class SettingsForm extends ConfigFormBase {

  public function getFormId(): string {
    return 'my_module_settings';
  }

  protected function getEditableConfigNames(): array {
    return ['my_module.settings'];
  }

  public function buildForm(array $form, FormStateInterface $form_state): array {
    $form['items_per_page'] = [
      '#type' => 'number',
      '#title' => $this->t('Items per page'),
      '#min' => 1,
      '#config_target' => 'my_module.settings:items_per_page',
    ];
    return parent::buildForm($form, $form_state);
  }

}
```

`#config_target` (10.2+) loads and saves the value, so no `submitForm()` is needed. Every config
object needs a schema in `config/schema/my_module.schema.yml` (`type: config_object`, typed
`mapping`); kernel and functional tests fail on schema errors by default.

## Event subscribers

Use hooks for Drupal extension points and Symfony events for kernel and config events
(`KernelEvents::REQUEST`, `ConfigEvents::SAVE`, ...). With `autoconfigure: true` a class
implementing `EventSubscriberInterface` needs no tag; otherwise tag it `event_subscriber`.

## Cache metadata: the most common source of bugs

Every render array, block, access result and cacheable response answers three questions:

| Question | Metadata | Typical values |
|---|---|---|
| Which data does it show? | `tags` | `node:5`, `node_list`, `node_list:article`, `config:system.site`, custom `my_module:stats` |
| What does it vary by? | `contexts` | `user.permissions`, `user.roles`, `user`, `url.path`, `url.query_args:page`, `languages:language_interface`, `route`, `theme` |
| How long is it valid? | `max-age` | `Cache::PERMANENT` (default), seconds, `0` = uncacheable |

- Output built from an entity or config object: add it as a dependency,
  `CacheableMetadata::createFromObject($node)->applyTo($build)` or
  `$renderer->addCacheableDependency($build, $node)`.
- Lists: add `ENTITY_TYPE_list` (or `ENTITY_TYPE_list:BUNDLE`) so new items appear.
- Access: `AccessResult::allowedIfHasPermission()` adds `user.permissions` itself; when you
  decide from an entity, `->addCacheableDependency($entity)`; when per user, `->cachePerUser()`.
- Blocks: override `getCacheContexts()` / `getCacheTags()` / `getCacheMaxAge()` and merge
  with the parent (`Cache::mergeContexts(parent::getCacheContexts(), ['url.path'])`).
- Elements built by a `#lazy_builder` (blocks are) whose metadata has the `user` or `session`
  context or `max-age: 0` are auto-placeholdered: rendered late, streamed by BigPipe when it is
  enabled. Put per-user fragments behind a `#lazy_builder` so the rest of the page stays cached.
- `max-age` does not reach the Internal Page Cache for anonymous users. Use tags and invalidate
  them (`Cache::invalidateTags(['my_module:stats'])`, or inject `CacheTagsInvalidatorInterface`),
  or inject `Drupal\Core\PageCache\ResponsePolicy\KillSwitch` (`page_cache_kill_switch`) and
  call `trigger()` for responses that must never be cached for anonymous users.
- JSON controllers: return `CacheableJsonResponse` and add dependencies to it.
- Twig that reaches into references (`node.field_tags.entity.label`) skips the referenced
  entity's cache tags; render `content.field_tags` or add the dependency in preprocess.
- Debug: `http.response.debug_cacheability_headers: true` in `development.services.yml` exposes
  `X-Drupal-Cache-Tags`/`-Contexts`/`-Max-Age`. Reproduce with two users with different roles.

See the `performance` skill for caching layers and N+1 loads, `security` for output and access
rules, and `testing` to lock the behaviour in.
