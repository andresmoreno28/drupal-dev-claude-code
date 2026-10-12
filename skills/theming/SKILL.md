---
name: theming
description: Builds and fixes Drupal 10/11 front ends - Single Directory Components (component.yml props and slots, Twig include/embed, render arrays), Twig templates and suggestions, preprocess (including OOP theme hooks), asset libraries and Drupal.behaviors with once(), generating a theme from the core Starterkit, and accessible markup. Use when creating or editing a Drupal theme, *.html.twig or *.component.yml files, *.libraries.yml, *.theme files, front-end JavaScript behaviors, or when markup, assets or Twig debug output are wrong.
---

# Drupal theming

## Start a custom theme from Starterkit

Generate a standalone copy of core's `starterkit_theme` (no runtime base-theme dependency):

```bash
# Drupal 11.4+, from the project root
vendor/bin/dr generate-theme my_theme --path=themes/custom
# Drupal 10.3-11.3, from the web root
php core/scripts/drupal generate-theme my_theme --path=themes/custom
```

`--path` is relative to the Drupal root; `--starterkit` picks another starterkit-enabled theme.
Do not base new themes on Classy or Stable 9 (Stable 9 is deprecated and leaves core in 12).
Breakpoints belong in `my_theme.breakpoints.yml` and CSS custom properties chosen for the
design; do not import framework breakpoint presets by default.

## Twig rules

- Autoescape is on. Print variables as `{{ var }}`; `|raw` only for markup that is already
  sanitized (and say why in a comment). Never build HTML strings in preprocess.
- Translate: `{{ 'Read more'|t }}`, `{% trans %}Submitted by {{ author }}{% endtrans %}`.
- Use the `attributes` object: `<div{{ attributes.addClass('teaser', 'teaser--' ~ view_mode|clean_class) }}>`;
  create extra ones with `create_attribute()`.
- Print render arrays (`{{ content.field_image }}`, `{{ content|without('links') }}`), not raw
  field values like `node.field_image.entity.uri.value`: you lose formatters, access and cache
  metadata.
- Template names: `node--article--teaser.html.twig`, `field--node--body.html.twig`,
  `block--system-branding-block.html.twig`. Add suggestions in
  `hook_theme_suggestions_HOOK_alter()`.
- Debug: enable Twig development mode at `/admin/config/development/settings` (local only) to
  see template suggestions as HTML comments; run `drush cr` after adding templates.

## Preprocess

```php
// my_theme.theme (all versions)
function my_theme_preprocess_node(array &$variables): void {
  $variables['is_featured'] = (bool) $variables['node']->get('promote')->value;
}
```

Drupal 11.3+ themes may use OOP hooks: a class in `src/Hook/` (`Drupal\my_theme\Hook`) with
`#[Hook('preprocess_node')]` methods and autowired constructor services. Themes cannot use
`order`, `#[ReorderHook]` or `#[RemoveHook]`. Keep the procedural version, marked
`#[LegacyHook]`, if the theme must run on cores older than 11.3.

## Libraries and JavaScript

```yaml
# my_theme.libraries.yml
global:
  css:
    theme:
      css/base.css: {}
  js:
    js/menu.js: {}
  dependencies:
    - core/drupal
    - core/once
```

```js
((Drupal, once) => {
  Drupal.behaviors.myThemeMenu = {
    attach(context) {
      once('my-theme-menu', '.js-menu-toggle', context).forEach((button) => {
        button.addEventListener('click', () => {
          const expanded = button.getAttribute('aria-expanded') === 'true';
          button.setAttribute('aria-expanded', String(!expanded));
        });
      });
    },
  };
})(Drupal, once);
```

- Attach globally in `my_theme.info.yml` (`libraries:`), per template with
  `{{ attach_library('my_theme/menu') }}`, or per render array with `#attached`.
- Behaviors run on every AJAX/BigPipe insert: always scope to `context` and guard with `once()`.
- Pass server data with `#attached['drupalSettings']`, never by printing inline `<script>`.

## Single Directory Components (core since 10.3)

```
my_theme/components/card/
  card.component.yml   card.twig   card.css   card.js   (CSS/JS named after the component load automatically)
```

```yaml
# card.component.yml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Card
status: stable
props:
  type: object
  required: [heading]
  properties:
    heading:
      type: string
      title: Heading
    url:
      type: string
      title: Link URL
    heading_level:
      type: integer
      enum: [2, 3, 4]
slots:
  body:
    title: Body
```

```twig
{# card.twig - "attributes" is provided automatically #}
{% set level = heading_level|default(2) %}
<article{{ attributes.addClass('card') }}>
  <h{{ level }} class="card__heading">
    {% if url %}<a href="{{ url }}">{{ heading }}</a>{% else %}{{ heading }}{% endif %}
  </h{{ level }}>
  <div class="card__body">{% block body %}{% endblock %}</div>
</article>
```

Use it:

```twig
{{ include('my_theme:card', { heading: label, url: url }, with_context = false) }}

{% embed 'my_theme:card' with { heading: label } only %}
  {% block body %}{{ content.body }}{% endblock %}
{% endembed %}
```

```php
$build = [
  '#type' => 'component',
  '#component' => 'my_theme:card',
  '#props' => ['heading' => $node->label(), 'url' => $node->toUrl()->toString()],
  '#slots' => ['body' => $node->get('body')->view('default')],
];
```

- Component IDs are `provider:machine_name`; the provider prefix is required.
- Schemas are mandatory for components in modules and optional in themes; set
  `enforce_prop_schemas: true` in the theme's info file to require them. Props must validate
  against the schema, so keep types honest (string vs integer vs object).
- Prop names become Twig variables: use `snake_case`, never dashes.
- Variables used inside an `{% embed %}` block must be passed in; the component has its own scope.
- `default` in the schema is documentation only; apply defaults in Twig (`|default()`).
- Only themes can override another provider's component (`replaces: 'other:card'`).
- Run `drush cr` after adding a component; discovery is cached.

## Accessibility checklist for templates

- One `h1` per page; heading levels follow the outline. Make levels configurable in reusable
  components instead of hard-coding `h2`.
- Links navigate, buttons act. Interactive elements are reachable and operable by keyboard,
  with a visible focus style (`:focus-visible`); never remove outlines without a replacement.
- Images: meaningful `alt` from the media/image field; decorative images get `alt=""`.
  Use image styles or responsive image styles instead of hand-written `<img>` sizes.
- Hidden-but-announced text: `class="visually-hidden"`; skip links:
  `class="visually-hidden focusable"` (both from core's `system/base` library).
- Toggles expose state (`aria-expanded`, `aria-controls`); live updates use
  `Drupal.announce()` (library `core/drupal.announce`).
- Forms: let Form API render labels, descriptions and error messages; do not strip them in
  templates. Keep visible labels when restyling.
- Colour contrast and text spacing must meet WCAG 2.2 AA; respect `prefers-reduced-motion`
  for animations.
- Language: keep `lang`/`dir` from `html.html.twig`; mark inline foreign text with `lang`.

See `performance` for asset aggregation and render caching, `security` for escaping rules.
