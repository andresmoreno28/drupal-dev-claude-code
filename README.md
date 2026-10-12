# Drupal Dev for Claude Code

A [Claude Code](https://code.claude.com/docs) plugin for Drupal teams. It gives Claude
current, verified knowledge of how Drupal 10, 11 and 12 code is written, reviewed, tested
and shipped, plus a review subagent and a lint hook that checks every PHP, Twig and YAML
file Claude edits.

- **9 skills** that load only when the task needs them: module development, theming,
  configuration management, security, testing, upgrades, performance, migrations and
  headless/JSON:API.
- **`drupal-reviewer` subagent** that reviews a diff and ranks findings by severity, with
  `file:line`.
- **`drupal-lint` hook** that runs `php -l`, `phpcs` (Drupal and DrupalPractice), a Twig
  syntax check and `yaml-lint` right after each edit, using the tools already in your
  project's `vendor/bin`.

Facts are current as of October 2026 (Drupal 11.4, Drupal 12.0 beta) and each one is
traced to an official source in [docs/SOURCES.md](docs/SOURCES.md). The code examples were
run on a Drupal 11.4 site.

Read this in [Spanish](README.es.md).

## Install

Inside Claude Code:

```
/plugin marketplace add andresmoreno28/drupal-dev-claude-code
/plugin install drupal-dev@drupal-dev
```

Or from a terminal:

```bash
claude plugin marketplace add andresmoreno28/drupal-dev-claude-code
claude plugin install drupal-dev@drupal-dev
```

To suggest it to everyone working on a repository, commit this to `.claude/settings.json`
(each person still confirms the install):

```json
{
  "extraKnownMarketplaces": {
    "drupal-dev": {
      "source": { "source": "github", "repo": "andresmoreno28/drupal-dev-claude-code" }
    }
  },
  "enabledPlugins": {
    "drupal-dev@drupal-dev": true
  }
}
```

## Skills

Claude picks a skill automatically from its description; you can also run one directly,
for example `/drupal-dev:security`.

| Skill | What it covers |
|---|---|
| `module-development` | Services and autowiring, OOP hooks with `#[Hook]` (11.1+) and hook ordering, plugins with PHP attributes, routes and access requirements, forms with `#config_target`, event subscribers, and cache metadata (tags, contexts, max-age). |
| `theming` | Starterkit-generated themes, Twig rules, preprocess (including OOP theme hooks in 11.3+), libraries and `Drupal.behaviors` with `once()`, Single Directory Components, and an accessibility checklist for templates. |
| `config-management` | Config sync, `settings.php` overrides, Config Split and Config Ignore, update vs post-update vs deploy hooks, the `drush deploy` order, and recipes with config actions and inputs. |
| `security` | A checklist of patterns to flag and how to fix them: XSS, SQL injection, access on routes/entities/fields/queries, CSRF, uploads, redirects, secrets, and the Security Team's advisory policy. |
| `testing` | Choosing Unit, Kernel, Functional or FunctionalJavascript; kernel test setup; PHPUnit attributes and `#[RunTestsInSeparateProcesses]`; running tests locally and in DDEV. |
| `upgrades` | The 10 -> 11 -> 12 timeline and PHP requirements, Upgrade Status, drupal-rector and phpstan-drupal, extensions removed in Drupal 12, contrib compatibility and the Composer upgrade commands. |
| `performance` | Caching layers, cache headers, lazy builders and placeholders, BigPipe, N+1 entity loads, queues and batches, cron and front-end assets. |
| `migrations` | Migrate API source/process/destination, process pipelines, Migrate Plus JSON/XML sources, Drush migrate commands, custom plugins and migration tests. |
| `headless` | JSON:API queries (includes, sparse fieldsets, filters, pagination, revisions), writes, authentication, CORS, and caching of API responses. |

## Review subagent

`drupal-reviewer` reads the change (working tree, branch, commit range or pasted diff),
runs the linters it finds in `vendor/bin` on the changed files, and reports:
a verdict, findings grouped as Critical / High / Medium / Low with `file:line` and a
concrete fix, tool results, and missing tests. It never edits files.

Ask for it in plain language ("review my changes with the drupal-reviewer agent") or
mention it: `@agent-drupal-dev:drupal-reviewer review this branch against main`.

## Lint hook

After Claude writes or edits a file, the hook checks it and passes any problems back to
Claude (and shows you a one-line summary), so they get fixed in the same turn.

| Files | Checks |
|---|---|
| `*.php`, `*.module`, `*.inc`, `*.install`, `*.theme`, `*.profile` | `php -l`; then `phpcs` with your `phpcs.xml(.dist)` or, without one, `Drupal,DrupalPractice` from `drupal/coder` |
| `*.twig` | Twig-CS-Fixer with your `.twig-cs-fixer(.dist).php`, or a syntax-only check without one |
| `*.yml`, `*.yaml` | Symfony `yaml-lint` (with custom tags such as `!tagged_iterator`) |

- Uses the nearest `vendor/bin` above the edited file. Missing tools are skipped silently;
  files under `vendor/` and `node_modules/` are ignored.
- Never blocks Claude and never writes files (tool caches are disabled). Measured on a warm
  file system: 0.3-0.5 s per file on Linux, about 1 s on Windows; edits to other file types
  exit in a few milliseconds.
- `DRUPAL_DEV_LINT=0` turns it off; `DRUPAL_DEV_LINT_MAX` caps the findings reported per tool
  (default 40). Set them in your shell or under `env` in Claude Code settings.
- Needs `php` on the machine where Claude Code runs. If PHP only exists inside DDEV or
  another container, the hook stays silent; run the same checks with `ddev exec`.
- On Windows the hook needs Git Bash, the shell Claude Code uses for hooks when it is installed.

To get `phpcs` and Twig-CS-Fixer in a project: `composer require --dev drupal/core-dev`
(brings Coder) and, for Twig, `composer require --dev vincentlanglet/twig-cs-fixer`
(`drupal/core-dev` includes it from Drupal 12).

## Example prompts

- "Add a block that shows the current user's five latest articles, with correct cache metadata."
- "Convert the hooks in `my_module.module` to OOP hooks. The module still supports Drupal 10.3."
- "Is this site ready for Drupal 12? Check our custom code and contrib modules."
- "Create an SDC card component in my theme and use it in `node--article--teaser.html.twig`."
- "Write a kernel test for `ArticleCounter` and tell me how to run it in DDEV."
- "Anonymous pages are never cached on this site. Find out why."
- "Write a recipe that adds an Editor role and tags on articles."
- "Import the articles from this JSON endpoint with Migrate."
- "Expose articles over JSON:API to a front end on another domain."
- "@agent-drupal-dev:drupal-reviewer review the staged changes."

## Requirements

- Claude Code with plugin support.
- For the hook: a POSIX shell (macOS, Linux, WSL, or Git Bash on Windows) and PHP; `phpcs`,
  Twig-CS-Fixer and `yaml-lint` from the project's Composer dependencies are optional.
- The skills target Drupal 10.3+ and 11, and flag what changes in Drupal 12.

## Contributing

Issues and merge requests are welcome. To work on the plugin:

```bash
git clone https://github.com/andresmoreno28/drupal-dev-claude-code.git
cd drupal-dev-claude-code
claude --plugin-dir .          # load your working copy for one session
sh scripts/check.sh            # manifests, frontmatter, line endings, hook tests
```

- Every technical claim needs an official source (drupal.org documentation or change
  records, api.drupal.org or the core source, project pages, release notes). Add it to
  `docs/SOURCES.md` in the same change. If it cannot be verified, leave it out.
- Keep skills short and practical: rules, checklists and small examples that run.
- Hook changes need a test in `tests/hooks/run.sh`. To also exercise the real tools, point
  `DRUPAL_DEV_TEST_PROJECT` at a Composer project that has them:
  `DRUPAL_DEV_TEST_PROJECT=/path/to/drupal sh tests/hooks/run.sh`.
- Record user-facing changes in `CHANGELOG.md`.

## License

[MIT](LICENSE) © 2026 Andrés Moreno Rubio.

Built by [Andrés Moreno Rubio](https://andresmoreno.dev), Drupal developer and maintainer of
the Config Guardian and Midgard modules on drupal.org.
