# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-12

### Added

- Skills: `module-development`, `theming`, `config-management`, `security`, `testing`,
  `upgrades`, `performance`, `migrations` and `headless`, written against Drupal 11.4 and
  the Drupal 12.0 beta.
- `drupal-reviewer` subagent that reviews a diff and reports findings by severity with
  `file:line`.
- `PostToolUse` hook (`hooks/drupal-lint.sh`) that runs `php -l`, `phpcs`, a Twig syntax
  check through Twig-CS-Fixer and Symfony `yaml-lint` on edited files, using the project's
  own `vendor/bin` tools.
- Marketplace manifest, so the plugin installs with `/plugin marketplace add`.
- `scripts/check.sh` and `tests/hooks/run.sh`.
- `docs/SOURCES.md` with the official source for each non-obvious fact.

[1.0.0]: https://github.com/andresmoreno28/drupal-dev-claude-code/releases/tag/v1.0.0
