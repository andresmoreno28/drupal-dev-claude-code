---
name: security
description: Drupal secure coding and security review - XSS and escaping, SQL placeholders, access checks on routes, entities, fields and queries, CSRF tokens, file uploads, redirects, secrets and Security Team advisories. Use when code handles input, output, permissions, queries or uploads, when auditing a module, or when handling a vulnerability.
---

# Drupal security

Work through the checklist for every change that touches input, output, access or storage.
Each item names the pattern to flag and the fix.

## 1. Output and XSS

Drupal escapes by default: Twig autoescapes, render arrays are sanitized. Bugs come from
opting out.

| Flag | Fix |
|---|---|
| `{{ value\|raw }}`, `Markup::create($user_data)`, `new FormattableMarkup($user_data, [])` | Print the variable or a render array; keep `\|raw` / `Markup` for markup the code generated itself |
| `'#markup' => $untrusted` | `'#plain_text' => $untrusted` (escaped). `#markup` only runs `Xss::filterAdmin()`, meant for admin-entered HTML |
| HTML built by string concatenation in PHP | Render arrays, `#type => 'html_tag'`, or a Twig template |
| User text with formatting | `['#type' => 'processed_text', '#text' => $text, '#format' => $format_id]` |
| Plain text in a string context | `Html::escape($text)` |
| A few safe tags allowed | `Xss::filter($text)` (allows `a em strong cite blockquote code ul ol li dl dt dd`) or pass an explicit tag list |
| `t($variable)`, `t('Hi ' . $name)` | Literal string with placeholders: `@name` (escaped), `%name` (escaped, emphasized), `:url` (escaped, dangerous protocols stripped) |
| User URL printed in `href`/`src` | Build a `Url` object (`Url::fromUri()` / `Url::fromUserInput()`) or `UrlHelper::stripDangerousProtocols()`; autoescape does not stop `javascript:` |
| JS: `element.innerHTML = data` | `textContent`, or `Drupal.checkPlain()`; pass data via `drupalSettings` |

## 2. SQL injection

```php
// Static query: placeholders only.
$nids = $this->connection->query(
  'SELECT nid FROM {node_field_data} WHERE title = :title AND status = :status',
  [':title' => $title, ':status' => 1],
)->fetchCol();

// Dynamic query.
$query = $this->connection->select('node_field_data', 'n')
  ->fields('n', ['nid'])
  ->condition('n.title', '%' . $this->connection->escapeLike($search) . '%', 'LIKE')
  ->addTag('node_access');
```

Flag: variables interpolated into SQL strings, user input in `orderBy()`, `fields()` or table
names without an allowlist, `->where()` with concatenation, missing `{}` around table names,
custom queries on node tables without the `node_access` tag. Prefer entity queries for
content: they speak the entity API and enforce access when `accessCheck(TRUE)`.

## 3. Access control

- **Routes**: every route declares `_permission`, `_entity_access`, `_custom_access`, `_role`
  or a deliberate, commented `_access: 'TRUE'`. Writes and admin pages are never open.
- **Entities loaded from IDs in the request** (IDOR): check
  `$entity->access('view', $account, TRUE)` before rendering, serializing or acting, and add
  the returned result's cacheability to the response.
- **Entity queries**: `accessCheck(TRUE)` for anything a user sees. Flag `accessCheck(FALSE)`
  whose results reach output without a separate access check.
- **Fields**: `$entity->get('field_secret')->access('view', $account)` before exposing values
  in custom output (APIs, CSV exports, emails).
- **Forms**: `#access => FALSE` hides an element and blocks its submitted value; never rely
  on `#disabled`, hidden fields or client-side checks. Validate in `validateForm()`.
- **Custom access callbacks** return `AccessResultInterface` with cacheability
  (`AccessResult::allowedIfHasPermission()`, `->andIf()`, `->addCacheableDependency()`).
- **Permissions** that can escalate privileges set `restrict access: true`.

## 4. CSRF

- Form API forms carry a form token automatically. Prefer a `ConfirmFormBase` for destructive
  actions.
- A GET route that changes state needs `_csrf_token: 'TRUE'`; generate links with
  `Url`/`Link` so the token is added. Flag deletes, toggles or "approve" actions on plain GET.
- Cookie-authenticated REST/JSON:API writes require the `X-CSRF-Token` header (from
  `/session/token`).

## 5. File uploads

```php
$form['document'] = [
  '#type' => 'managed_file',
  '#title' => $this->t('Document'),
  '#upload_location' => 'private://documents',
  '#upload_validators' => [
    'FileExtension' => ['extensions' => 'pdf odt'],
    'FileSizeLimit' => ['fileLimit' => 5 * 1024 * 1024],
  ],
];
```

- Validators are constraint plugins: `FileExtension`, `FileSizeLimit`, `FileIsImage`,
  `FileImageDimensions`, `FileNameLength`. `FileExtension` without an `extensions` key
  allows every extension; flag it. Without any `FileExtension` validator core falls back to
  `jpg jpeg gif png txt doc xls pdf ppt pps odt ods odp`.
- Sensitive files go to `private://`, with access in `hook_file_download()` or field access.
- Keep `system.file:allow_insecure_uploads` FALSE so executable extensions are renamed.
- SVG can carry script: do not accept it from untrusted users unless it is sanitized.
- Validate programmatic files too: `\Drupal::service('file.validator')->validate($file, $validators)`.

## 6. Other patterns to flag

- `unserialize()` on anything user-controlled; use JSON, or `['allowed_classes' => FALSE]`.
- `new RedirectResponse($request->query->get('destination'))`: use `LocalRedirectResponse`
  for internal targets; `TrustedRedirectResponse` only for allowlisted external hosts.
- `$_GET`, `$_POST`, `$_REQUEST`: use the `Request` object and validate types.
- `exec()`, `shell_exec()`, `proc_open()` with input: avoid, or `escapeshellarg()` every argument.
- Token comparisons with `==`: use `hash_equals()`. Random tokens: `Crypt::randomBytesBase64()`.
- Secrets in code, `config/sync`, logs or `drupalSettings`: move to `settings.php` reading
  environment variables (or a secrets manager). Logger messages use placeholders
  (`$logger->warning('Login failed for @name', ['@name' => $name])`).
- Error output: `$config['system.logging']['error_level'] = 'hide';` on production.
- Twig debug, Devel or verbose errors enabled on production.

## 7. Advisories, updates and disclosure

- The Drupal Security Team publishes advisories only for stable releases of projects that
  opted into security advisory coverage; `-dev`, alpha, beta and RC releases are not covered.
  Core advisories cover the current and the previous minor release.
- Check installed packages with `composer audit` (packages.drupal.org publishes advisories
  for Drupal projects) and keep the core Update Status module enabled somewhere it can email.
- Found a vulnerability in core or a covered project? Report it privately with the
  "Report a security vulnerability" link on the project page. Do not post it in the public
  issue queue, Slack or chat, and do not disclose it before the advisory.

## Review output

Report findings as `file:line - severity - problem - fix`, severity being Critical
(exploitable by anonymous users), High (authenticated or data exposure), Medium (needs
unusual permissions or configuration) or Low (hardening).
