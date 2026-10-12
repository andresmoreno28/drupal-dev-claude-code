---
name: upgrades
description: Drupal 10 to 11 to 12 upgrades - release dates, PHP requirements, deprecations with Upgrade Status, drupal-rector and phpstan-drupal, extensions removed in Drupal 12, contrib compatibility and the Composer commands. Use when preparing an upgrade, fixing deprecations, or checking which Drupal or PHP version a site needs.
---

# Drupal upgrades

## Where things stand (October 2026)

| | Status |
|---|---|
| Drupal 11.4 | Current minor (11.4.0 released 1 July 2026). Security support until June 2027 |
| Drupal 11.5 and 12.0 | Scheduled for the week of 7 December 2026; 12.0.0-beta1 came out on 30 September 2026 |
| Drupal 11.3 | Security support ends the week of 7 December 2026 |
| Drupal 10 | End of life 9 December 2026; 10.6 is its last minor |
| PHP | Drupal 11: 8.3 minimum (11.3+ also supports 8.5). Drupal 12: PHP 8.5, built with argon2 for password hashing |
| Drush | 13.x for Drupal 10.x/11.x; the compatibility table lists Drush 14 (in development) for 11.3+ and 12 |

Majors cannot be skipped: 10 -> 11 -> 12. Drupal 11 needs 10.3 or later as the starting
point. Drupal 12 removed all core update hooks from before 11.3.0, so be on the latest 11.x
minor (at least 11.3) first.

## Workflow

1. **Update within the current major first**: latest core minor and latest contrib releases,
   `drush updatedb`, `drush config:export`, commit. `composer outdated "drupal/*"` lists gaps.
2. **Scan**: `composer require --dev drupal/upgrade_status` (install `drupal/core-dev` too, so
   test classes scan cleanly), enable it, then `drush upgrade_status:analyze --all` or open
   *Reports > Upgrade status*. It reports deprecated API use (via PHPStan), info.yml and
   composer.json problems, Twig and library deprecations, and environment requirements for the
   next major. Run it on the old version: after the upgrade the deprecated APIs are gone.
   (4.3.x is the stable line for Drupal 9-11; 5.0.x, alpha in October 2026, lists Drupal 12.)
3. **Fix custom code automatically, then by hand**:
   ```bash
   composer require --dev palantirnet/drupal-rector
   cp vendor/palantirnet/drupal-rector/rector.php .
   vendor/bin/rector process web/modules/custom --dry-run   # review, then run without --dry-run
   ```
   If rector's parallel workers time out (seen on slow file systems), add
   `$rectorConfig->disableParallel();` to `rector.php`.
   Everything rector cannot fix: read the deprecation message, which names the replacement
   and links the change record (`... is deprecated in drupal:11.2.0 and is removed from
   drupal:12.0.0. Use X instead. See https://www.drupal.org/node/NNNNNNN`).
4. **Re-check with PHPStan** (`mglaman/phpstan-drupal` with `phpstan/phpstan-deprecation-rules`,
   both in `drupal/core-dev`), and run the test suite with deprecations reported.
5. **Declare compatibility** in each custom module or theme:
   `core_version_requirement: ^11 || ^12` (keep the lower bound the code really supports).
6. **Contrib**: check each project page's "Works with Drupal" line and its issue queue
   (Project Update Bot posts automated compatibility fixes there). To test a module that has
   a fix but no compatible release yet, use `composer require mglaman/composer-drupal-lenient`
   (`composer config --merge --json extra.drupal-lenient.allowed-list '["drupal/foo"]'`) plus
   a patch through `cweagans/composer-patches`; never ship lenient installs as the long-term
   state, and drop the patch once a release exists.
7. **Upgrade core** with Composer (Drupal 12 shown; same shape for 11):
   ```bash
   composer require 'drupal/core-recommended:^12' 'drupal/core-composer-scaffold:^12' \
     'drupal/core-project-message:^12' --no-update
   composer require 'drupal/core-dev:^12' --dev --no-update   # if used
   composer require drush/drush --no-update
   composer update --dry-run
   composer update
   drush updatedb:status && drush updatedb
   drush config:export   # commit config changes made by core updates
   ```
   Run `composer remove drupal/core --no-update` first if `drupal/core` is required directly.
   When upgrading to 11, also allow the runtime plugin: `composer config allow-plugins.symfony/runtime true`.
8. **After**: run tests, watch logs (`drush watchdog:tail`), run cron, re-run `phpcs` (Coder 9
   accompanies Drupal 12), and deploy with `drush deploy`.

## Extensions removed from core in Drupal 12

Before the code upgrade, either uninstall each one (uninstalling deletes its data and config)
or require the contributed project and keep using it:

- Modules: Ban, Contact, Field Layout, History, Search, Settings Tray, Shortcut, Telephone,
  Toolbar, Text with Summary (moved to its own module in 11.5). Migrate Drupal and Migrate
  Drupal UI are removed without a contrib replacement (the Migrate API stays in core).
- Themes: Claro (the new Default Admin theme replaces it), Olivero, Stable 9. A custom theme
  whose `base theme` is one of them needs the contrib project before upgrading.
- Libraries: Backbone and Underscore are gone; htmx moved from 2.0 to 4.0.
- Tests: PHPUnit 12.5, attributes only, `#[RunTestsInSeparateProcesses]` mandatory on Kernel and
  browser tests (see the `testing` skill).

Check the 12.0.0 release notes and the "Deprecated and obsolete extensions" page for the
final list when 12.0.0 ships.

## Making a contributed or shared module compatible with two majors

- Fix every deprecation that has a replacement available in the lowest core you support.
- If the replacement only exists in the newer core, branch on the version:
  ```php
  $result = DeprecationHelper::backwardsCompatibleCall(
    \Drupal::VERSION, '11.2.0',
    fn () => $this->newApi(),   // core >= 11.2.0
    fn () => $this->oldApi(),   // older cores
  );
  ```
  (`Drupal\Component\Utility\DeprecationHelper`).
- OOP hooks: keep `#[LegacyHook]` procedural shims while supporting cores older than 11.1.
- Drop support for an old major in a new minor or major release of the module, not a patch release.
