---
name: migrations
description: Drupal Migrate API - migration YAML with source, process and destination, core process plugins, Migrate Plus JSON and XML sources, Drush migrate commands, custom plugins and tests. Use when importing content into Drupal from another system or an older site, or writing or debugging a migration.
---

# Drupal migrations

The Migrate API (`migrate` module) stays in core in Drupal 12. Migrate Drupal and Migrate
Drupal UI (upgrades from Drupal 6/7) are removed in 12 with no contrib replacement: run
Drupal 7 upgrades on Drupal 11.

## Pieces

- **Source**: yields rows with IDs. Core: `embedded_data` (fixtures, tests), `content_entity`,
  `sql`-based plugins. Contrib: Migrate Plus `url` (HTTP/file with `json`, `xml`,
  `simple_xml`, `soap` parsers), `migrate_source_csv`.
- **Process**: per destination property, a pipeline of plugins. A plain string is
  shorthand for the `get` plugin.
- **Destination**: `entity:node`, `entity:taxonomy_term`, `entity:user`, `entity:file`,
  `entity:media`, `config`, ...
- **Map and messages**: Migrate stores source ID -> destination ID per migration, which is
  what makes `migration_lookup`, `--update` and rollback work.

Where migrations live:

- `my_module/migrations/*.yml`: plugin migrations, discovered on cache rebuild. Simple,
  ideal for one-off imports.
- `config/install/migrate_plus.migration.*.yml` with Migrate Plus: config entities, with
  migration groups and shared configuration. Changes need a config import or reinstall.

## Example: articles from a JSON API with tags

```yaml
# my_module/migrations/news_articles.yml
id: news_articles
label: News articles
migration_tags: [news]
source:
  plugin: url                       # Migrate Plus
  data_fetcher_plugin: http
  data_parser_plugin: json
  urls:
    - 'https://legacy.example.com/api/news.json'
  item_selector: items
  fields:
    - { name: id, label: 'Legacy ID', selector: id }
    - { name: title, label: Title, selector: title }
    - { name: body, label: Body, selector: body_html }
    - { name: published, label: Published, selector: published_at }
    - { name: tags, label: Tags, selector: tags }
  ids:
    id: { type: integer }
process:
  title:
    plugin: skip_on_empty
    method: row                     # skip the whole row, log a message
    source: title
    message: 'Missing title'
  body/value: body
  body/format:
    plugin: default_value
    default_value: basic_html
  created:
    plugin: format_date
    from_format: 'Y-m-d\TH:i:sP'
    to_format: 'U'
    source: published
  status:
    plugin: default_value
    default_value: 1
  uid:
    plugin: default_value
    default_value: 1
  field_tags:
    plugin: sub_process             # one item per tag: [{ id: 3 }, { id: 7 }]
    source: tags
    process:
      target_id:
        plugin: migration_lookup
        migration: news_tags
        source: id
destination:
  plugin: 'entity:node'
  default_bundle: article
migration_dependencies:
  required:
    - news_tags
```

`news_tags` is a sibling migration (`destination: entity:taxonomy_term`, `vid` set with
`default_value`) that runs first because of `migration_dependencies`.

Pipeline rules worth remembering:

- The first plugin receives the whole source value. An array of IDs is treated as one
  composite ID by `migration_lookup`, so iterate with `sub_process` (keyed items) or produce
  multiple values first (for example `explode` on a delimited string).
- `skip_on_empty` with `method: process` stops only this property; `method: row` skips the
  row and records the message.
- Sub-properties use slashes: `body/value`, `body/format`, `field_image/alt`.
- Prefer `migration_lookup` to `entity_lookup` (Migrate Plus) when the target was itself
  migrated: it uses the map table and keeps rollbacks consistent.
- Files: migrate them into `entity:file` first (`file_copy` or `download` process plugins),
  then reference them by `migration_lookup`.

## Running and debugging (Drush 13 ships the migrate commands)

```bash
drush migrate:status --tag=news
drush migrate:import --tag=news                   # runs in dependency order
drush migrate:import news_articles --execute-dependencies
drush migrate:import news_articles --update      # re-import already imported rows
drush migrate:import news_articles --limit=10 --idlist=101,102
drush migrate:messages news_articles             # skipped rows and errors
drush migrate:rollback --tag=news
drush migrate:reset-status news_articles         # after an interrupted run ("Importing")
```

- Change a YAML file? Rebuild caches (`drush cr`) so the plugin definition is reloaded.
- Recurring imports: set `track_changes: true` on the source (hash-based) or
  `high_water_property` (only newer rows) and run with cron or a scheduled `drush` call.
- Inspect a row while developing: temporarily add the `log` process plugin to a pipeline,
  or import a single ID with `--idlist`.

## Custom plugins

```php
#[MigrateProcess('my_module_slug')]
final class Slug extends ProcessPluginBase {

  public function transform($value, MigrateExecutableInterface $migrate_executable, Row $row, $destination_property) {
    return trim(preg_replace('/[^a-z0-9]+/', '-', mb_strtolower((string) $value)), '-');
  }

}
```

Place it in `src/Plugin/migrate/process/`. Source plugins use `#[MigrateSource('id')]`
and extend `SourcePluginBase` (or `SqlBase` for a database); they must define `fields()`,
`getIds()` and `__toString()`.

## Testing

Extend `Drupal\Tests\migrate\Kernel\MigrateTestBase`, list the modules and entity schemas the
destination needs, switch the source to `embedded_data` in the test (or ship fixture
files), run `$this->executeMigration('news_articles')` and assert on the created entities and
on `$this->migration->getIdMap()` messages.
