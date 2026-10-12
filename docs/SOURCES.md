# Sources

Every non-obvious fact in the skills, the agent and the hook was checked against the sources
below in October 2026. Code-level details (class names, attribute parameters, service IDs,
defaults) were also checked in the Drupal 11.4.9 source, and the code examples were run on a
Drupal 11.4.9 site (Drush 13.8, PHPUnit 11.5, Coder 8.3 and 9.0).

When you change a fact, update its source here in the same commit.

## Releases and requirements

| Fact | Source |
|---|---|
| 11.4.0 released 1 July 2026; security support for 11.4 until June 2027 | https://www.drupal.org/project/drupal/releases/11.4.0 |
| 11.5.0 and 12.0.0 scheduled for the week of 7 December 2026; Drupal 10 end of life 9 December 2026; 11.3 security support ends that week | https://www.drupal.org/about/core/policies/core-release-cycles/schedule |
| 12.0.0-beta1 released 30 September 2026; PHP 8.5; PHPUnit 12.5, attributes required; removed modules and themes; Default Admin replaces Claro; Backbone and Underscore removed; htmx 4.0; Coder 9 | https://www.drupal.org/project/drupal/releases/12.0.0-beta1 |
| PHP versions per Drupal minor; argon2 for Drupal 12 | https://www.drupal.org/docs/getting-started/system-requirements/php-requirements |
| Latest core, core-dev, Coder, phpstan-drupal, drupal-rector, Twig-CS-Fixer releases | https://packagist.org/packages/drupal/core-recommended, https://packagist.org/packages/drupal/core-dev, https://packagist.org/packages/drupal/coder |
| Drush/Drupal compatibility table (Drush 13, Drush 14) | https://www.drush.org/13.x/install/ |
| Drush 13.8.0 is the latest release; 14.x in development | https://github.com/drush-ops/drush/releases |
| Deprecated and removed core extensions, contrib replacements | https://www.drupal.org/node/3223395 |
| Upgrade steps and Composer commands to Drupal 11 | https://www.drupal.org/docs/upgrading-drupal/upgrading-from-drupal-8-or-later/how-to-upgrade-from-drupal-10-to-drupal-11 |
| Upgrade steps to Drupal 12; core updates before 11.3.0 removed | https://www.drupal.org/docs/upgrading-drupal/upgrading-from-drupal-8-or-later/how-to-upgrade-from-drupal-11-to-drupal-12 |
| Drupal CMS 2.0 (28 January 2026): Canvas, Mercury, site templates, recipes; 2.2.4 latest | https://www.drupal.org/project/cms/releases/2.0.0, https://www.drupal.org/project/cms |

## Module development

| Fact | Source |
|---|---|
| OOP hooks with `#[Hook]` since 11.1, auto-registered classes in `src/Hook`, hooks that stay procedural, `#[LegacyHook]` and the services.yml registration for 10.1-11.0, removal of procedural hooks not before Drupal 13 | https://www.drupal.org/node/3442349 |
| Hook ordering `order:` with `Order`, `OrderBefore`, `OrderAfter` (11.2) | https://www.drupal.org/node/3493962 |
| `#[ReorderHook]` | https://www.drupal.org/node/3497308 |
| Replacement for `hook_module_implements_alter()` | https://www.drupal.org/node/3496788 |
| OOP hooks in themes (11.3) and their limits | https://www.drupal.org/node/3551652 |
| `skip_procedural_hook_scan` is optional | https://www.drupal.org/node/3498595 |
| Plugin types must provide an attribute class (Drupal 12) | https://www.drupal.org/node/3395582 |
| Annotation parsing kept until Drupal 13 | https://www.drupal.org/node/3551049 |
| Private properties and `DependencySerializationTrait` | https://www.drupal.org/node/3110266 |
| `#config_target` (10.2), `AutowireTrait` on `ControllerBase` (10.2) and `FormBase` (11.4), autowired plugin `create()` (11.3), interface aliases, `accessCheck()` exception, event subscriber autoconfiguration | Drupal core source: `core/lib/Drupal/Core/Form/ConfigFormBase.php`, `Controller/ControllerBase.php`, `Form/FormBase.php`, `Plugin/PluginBase.php`, `core.services.yml`, `Entity/Query/Sql/Query.php`, `CoreServiceProvider.php` (branches 10.1.x to 11.4.x on https://git.drupalcode.org/project/drupal) |
| `hook_update_N()` numbering and the rule against entity CRUD in updates | `core/lib/Drupal/Core/Extension/module.api.php` |
| Cache max-age limits with the Internal Page Cache | https://www.drupal.org/docs/drupal-apis/cache-api/cache-max-age |

## Theming

| Fact | Source |
|---|---|
| SDC part of core since 10.3 | https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components |
| Component folder layout; schemas mandatory in modules, optional in themes; `enforce_prop_schemas` | https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components/creating-a-single-directory-component |
| `component.yml` keys (`status`, `props`, `slots`, `libraryOverrides`, `replaces`) | https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components/annotated-example-componentyml |
| `include()`/`embed`/`#type => component` usage | https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components/using-your-new-single-directory-component |
| Metadata JSON schema URL | https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json |
| `generate-theme` options; `core/scripts/drupal` deprecated in 11.4 in favour of `vendor/bin/dr` | `core/lib/Drupal/Core/Command/GenerateTheme.php`, https://www.drupal.org/node/3584928 |
| Twig development settings page | `core/modules/system/system.routing.yml` (`system.development_settings`) |

## Configuration and deployment

| Fact | Source |
|---|---|
| `drush deploy` order and `cache:warm` on 11.2+ | https://www.drush.org/13.x/deploycommand/, https://github.com/drush-ops/drush/blob/13.x/src/Commands/core/DeployCommands.php |
| `hook_deploy_NAME()` in `MODULE.deploy.php` | https://github.com/drush-ops/drush/blob/13.x/drush.api.php |
| `config:import --diff`, `config:status` | https://github.com/drush-ops/drush/blob/13.x/src/Commands/config/ConfigImportCommands.php |
| Config Split usage and settings.php override | https://git.drupalcode.org/project/config_split/-/blob/2.0.x/README.md, https://www.drupal.org/project/config_split |
| Config Ignore; do not ignore `core.extension` | https://www.drupal.org/project/config_ignore |
| Recipe structure, `strict`, inputs, config actions | https://project.pages.drupalcode.org/distributions_recipes/recipe_author_guide.html, https://project.pages.drupalcode.org/distributions_recipes/config_action_list.html |
| Config action renames in 10.3.2 | https://www.drupal.org/node/3458273 |
| Applying recipes from the web root | https://project.pages.drupalcode.org/distributions_recipes/getting_started.html |
| `drush recipe` and `--input=RECIPE.INPUT=VALUE` | https://www.drush.org/13.x/commands/recipe_apply/ |
| Recipe unpacking (11.2) | https://www.drupal.org/node/3522189 |
| Recipe install path `recipes/{$name}` | https://git.drupalcode.org/project/drupal/-/blob/11.4.x/composer/Template/RecommendedProject/composer.json |

## Security

| Fact | Source |
|---|---|
| Advisory coverage only for stable releases of opted-in projects; core covers current and previous minor | https://www.drupal.org/drupal-security-team/security-advisory-process-and-permissions-policy |
| Reporting vulnerabilities privately | https://www.drupal.org/node/101494 |
| `composer audit` uses advisories from packages.drupal.org | https://blog.packagist.com/discover-security-advisories-with-composers-audit-command/ |
| `Xss::filter()` default tags, `#markup` through `Xss::filterAdmin()`, `#plain_text`, placeholder types, CSRF route requirement, file validation constraints and default extensions, `allow_insecure_uploads` | Drupal core source: `Component/Utility/Xss.php`, `Core/Render/Renderer.php`, `Component/Render/FormattableMarkup.php`, `Core/Access/CsrfAccessCheck.php`, `modules/file/src/Upload/FileUploadHandler.php`, `modules/system/config/install/system.file.yml` |

## Testing

| Fact | Source |
|---|---|
| Test types and base classes | https://www.drupal.org/docs/develop/automated-testing/types-of-tests |
| Running PHPUnit, `SIMPLETEST_DB`, DDEV commands | https://www.drupal.org/docs/develop/automated-testing/phpunit-in-drupal/running-phpunit-tests |
| `#[RunTestsInSeparateProcesses]` required (deprecated to omit in 11.3, exception in 12) | `core/tests/Drupal/KernelTests/KernelTestBase.php`, `core/tests/Drupal/Tests/BrowserTestBase.php`, https://www.drupal.org/node/3548485 |
| Kernel tests do not resolve module dependencies; strict config schema by default | `KernelTestBase::enableModules()`, `core/lib/Drupal/Core/Test/TestSetupTrait.php` |
| PHPUnit versions in core-dev (11.5 for 11.4, 12.5 for 12) | https://packagist.org/packages/drupal/core-dev |
| DDEV Selenium add-on and its test environment variables | https://github.com/ddev/ddev-selenium-standalone-chrome |
| DDEV `web_environment` values used for Drupal tests | https://github.com/ddev/ddev-drupal-contrib |

## Upgrades and code quality

| Fact | Source |
|---|---|
| Upgrade Status checks, Drush command, release lines | https://www.drupal.org/project/upgrade_status, https://www.drupal.org/project/upgrade_status/releases/5.0.0-alpha1 |
| drupal-rector installation and usage | https://github.com/palantirnet/drupal-rector |
| phpstan-drupal setup and deprecation rules | https://github.com/mglaman/phpstan-drupal |
| Coder standards and `phpcs` usage | https://github.com/pfrenssen/coder (mirror of https://www.drupal.org/project/coder) |
| Lenient Composer plugin | https://www.drupal.org/node/3240297 |
| Twig-CS-Fixer in core for 11.5 and 12 | https://www.drupal.org/project/drupal/releases/12.0.0-beta1, https://github.com/VincentLanglet/Twig-CS-Fixer |

## Performance and headless

| Fact | Source |
|---|---|
| Auto-placeholder conditions, cacheability headers, local cache overrides | `sites/default/default.services.yml`, `sites/development.services.yml`, `sites/example.settings.local.php` |
| Cache headers `X-Drupal-Cache`, `X-Drupal-Dynamic-Cache`; Internal Page Cache stores only cacheable responses | `core/modules/page_cache/src/StackMiddleware/PageCache.php`, `core/modules/dynamic_page_cache/src/EventSubscriber/DynamicPageCacheSubscriber.php` |
| Entity memory cache is LRU since 11.2 | `core/core.services.yml` (`entity.memory_cache`) on 11.1.x and 11.2.x |
| Brotli-compressed aggregates (11.4) | https://www.drupal.org/project/drupal/releases/11.4.0 |
| JSON:API read-only default, page limit 50, `meta.omitted`, `resourceVersion` | `core/modules/jsonapi/config/install/jsonapi.settings.yml`, `src/Query/OffsetPage.php`, `src/Normalizer/JsonApiDocumentTopLevelNormalizer.php`, `src/Revisions/ResourceVersionRouteEnhancer.php` |
| JSON:API filtering and pagination guidance | https://www.drupal.org/docs/core-modules-and-themes/core-modules/jsonapi-module/filtering, https://www.drupal.org/docs/core-modules-and-themes/core-modules/jsonapi-module/pagination |
| CORS settings | `sites/default/default.services.yml` (`cors.config`) |

## Migrations

| Fact | Source |
|---|---|
| Migrate API stays; Migrate Drupal and Migrate Drupal UI removed in 12 | https://www.drupal.org/node/3223395 |
| Core source, process and destination plugins and their options | `core/modules/migrate/src/Plugin/migrate/` |
| Migrate Plus `url` source with HTTP fetcher and JSON/XML/SOAP parsers | https://git.drupalcode.org/project/migrate_plus |
| Drush migrate commands and options | https://github.com/drush-ops/drush/blob/13.x/src/Commands/core/MigrateRunnerCommands.php |

## Claude Code plugin format

| Fact | Source |
|---|---|
| `plugin.json` fields, path rules, `${CLAUDE_PLUGIN_ROOT}`, `claude plugin validate` | https://code.claude.com/docs/en/plugins-reference |
| `marketplace.json` fields, relative plugin source, reserved names | https://code.claude.com/docs/en/plugins/marketplace-reference |
| Plugin components (skills, agents, hooks) | https://code.claude.com/docs/en/plugins/components |
| Skill frontmatter, description limits, size guidance | https://code.claude.com/docs/en/skills, https://agentskills.io/specification |
| Subagent frontmatter and fields ignored in plugin agents | https://code.claude.com/docs/en/sub-agents |
| Hook input, `PostToolUse` output (`additionalContext`, `systemMessage`), exit codes | https://code.claude.com/docs/en/hooks |
| `enabledPlugins`, `extraKnownMarketplaces`, `env` settings | https://code.claude.com/docs/en/settings-reference |
