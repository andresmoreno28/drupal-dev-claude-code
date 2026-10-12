---
name: config-management
description: Handles Drupal configuration management and deployments - config sync (drush config:export/import), environment overrides in settings.php, Config Split and Config Ignore, module config/install vs config/optional, update hooks vs post_update vs hook_deploy_NAME, the drush deploy order, and Drupal recipes with config actions and inputs. Use when exporting or importing config, writing an update or deploy hook, preparing a release, setting up dev/stage/prod differences, creating or applying a recipe, or when a deployment reverts or loses configuration.
---

# Drupal configuration management

## The model

- Active config lives in the database; the sync directory is the deployable copy:
  `$settings['config_sync_directory'] = '../config/sync';` (outside the web root).
- Change config on a local site, `drush config:export` (`cex`), commit the YAML, deploy, import.
  A production change that is not exported is reverted by the next `drush config:import`.
- Check before importing: `drush config:status` (`cst`) and `drush config:import --diff`.
- Secrets and per-environment values do not belong in sync. Override them in `settings.php`
  (`$config['smtp.settings']['password'] = getenv('SMTP_PASSWORD');`). Overrides are not
  exported and do not show in forms as saved values.

## Per-environment config

- **Config Split** (contrib, 2.x): sets of config exported to their own folders and merged on
  import. Plain `drush cex` / `drush cim` apply the active splits. Toggle a split per
  environment in `settings.php`:
  ```php
  $config['config_split.config_split.local']['status'] = getenv('APP_ENV') === 'local';
  ```
  Keep split folders next to the sync folder, never inside it. Edit only active splits.
- **Config Ignore** (contrib): leaves selected config (for example `system.site`, editor-owned
  webforms) untouched on import. Never ignore `core.extension`.

## Config shipped by a module

- `config/install/*.yml` is imported when the module is installed (installation fails if the
  config already exists). `config/optional/` is imported only when its dependencies are met.
- Editing those files later does nothing on existing sites. Ship the change as an update.
- Every config object needs a schema (`config/schema/*.schema.yml`); tests fail without it.

## Update, post-update and deploy hooks

`drush deploy` runs, in this order: `updatedb` (all `hook_update_N()` then all
`hook_post_update_NAME()`), `config:import`, `cache:rebuild`, `deploy:hook`
(`hook_deploy_NAME()`), and on Drupal 11.2+ `cache:warm`.

| Hook | File | Runs | Use for |
|---|---|---|---|
| `hook_update_N()` | `my_module.install` | `updatedb`, before config import | Schema changes, low-level fixes. Entity CRUD is never safe here |
| `hook_post_update_NAME()` | `my_module.post_update.php` | `updatedb`, after all update_N, before config import | Data changes needing the full API (entities, services) |
| `hook_deploy_NAME()` | `my_module.deploy.php` (Drush) | after config import | Content that depends on the newly imported config |

- `N` is sequential and never renumbered: core major + module major + counter, e.g.
  `my_module_update_11101()` for the first update of a 1.x module whose lowest supported core
  is 11. Numbers lower than the installed schema version never run.
- Post-update and deploy hooks run once each, tracked by name; order within a file is
  alphabetical, so prefix names (`my_module_post_update_0001_backfill()`).
- Long jobs use `$sandbox` batching: set `$sandbox['#finished']` between 0 and 1 each pass.
- **Gotcha on config-managed sites**: config changed by an update or post-update hook is
  overwritten by the `config:import` that follows unless the sync directory already contains
  it. Run `drush updatedb` locally, `drush cex`, and commit the exported YAML with the hook.

```php
// my_module.post_update.php
function my_module_post_update_0001_backfill_summary(array &$sandbox): string {
  $storage = \Drupal::entityTypeManager()->getStorage('node');
  if (!isset($sandbox['ids'])) {
    $sandbox['ids'] = $storage->getQuery()->accessCheck(FALSE)
      ->condition('type', 'article')->notExists('field_summary')->execute();
    $sandbox['total'] = count($sandbox['ids']);
  }
  foreach ($storage->loadMultiple(array_splice($sandbox['ids'], 0, 50)) as $node) {
    $node->set('field_summary', mb_substr($node->get('body')->value ?? '', 0, 200))->save();
  }
  $sandbox['#finished'] = $sandbox['total'] ? 1 - count($sandbox['ids']) / $sandbox['total'] : 1;
  return (string) t('Backfilled article summaries.');
}
```

## Recipes (core)

A recipe is a folder with `recipe.yml` that installs extensions, imports config and runs
config actions. Applying a recipe is a one-time operation: the result becomes ordinary site
config, there is no "uninstall" and no update path, so commit the exported config afterwards.

```yaml
# recipes/newsroom/recipe.yml
name: 'Newsroom'
description: 'Article tagging, an editor role and a feedback contact.'
type: 'Site'
recipes:
  - core/recipes/article_tags      # path from the Drupal root; bare names = sibling recipes
install:
  - pathauto
config:
  strict: false                    # default true: existing config must match exactly
  import:
    pathauto: '*'                  # all config/install + config/optional of that module
  actions:
    user.role.editor:
      createIfNotExists:
        id: editor
        label: Editor
      grantPermissions:
        - 'create article content'
        - 'edit any article content'
    system.site:
      simpleConfigUpdate:
        mail: ${site_mail}
input:
  site_mail:
    data_type: email
    description: 'Address that receives site notifications.'
    constraints:
      NotBlank: []
    default:
      source: config
      config: ['system.site', 'mail']
```

Apply:

```bash
drush recipe ../recipes/newsroom --input=newsroom.site_mail=web@example.com
# without Drush, from the web root (11.4+ prefers vendor/bin/dr recipe ...)
php core/scripts/drupal recipe ../recipes/newsroom
drush cr
```

- Useful actions: `createIfNotExists`, `simpleConfigUpdate`, `grantPermissions`,
  `setComponent`/`hideComponent` (displays), `placeBlockInDefaultTheme`, `addToAllBundles`,
  `createForEach`, `setThirdPartySetting`. Older names `simple_config_update` and
  `ensure_exists` were renamed in 10.3.2.
- Input tokens work in config entity IDs (for example `node.type.${type}`) from 11.1.2, not
  in simple config names.
- Recipes installed with Composer use `"type": "drupal-recipe"` and land in `recipes/`.
  `drupal/core-recipe-unpack` (11.2+) moves their dependencies into the root `composer.json`
  (`composer drupal:recipe-unpack`).
- Drupal CMS 2.x is built from recipes; treat its recipes as a starting point, not as
  something that keeps your site updated.

## Before you deploy

- `drush config:status` is clean on the source environment and the export is committed.
- Update hooks are idempotent and tested on a copy of production data.
- No secrets or environment-specific values in the sync directory.
- Release notes mention any manual step; there should be none for a normal deploy.
