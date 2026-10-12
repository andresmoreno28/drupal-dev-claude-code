---
name: testing
description: Writes and runs automated tests for Drupal 10/11 modules and themes with PHPUnit - choosing between Unit, Kernel, Functional and FunctionalJavascript tests, kernel test setup (modules, entity schemas, config), PHPUnit attributes required by Drupal 12, and running tests locally or in DDEV (SIMPLETEST_DB, Selenium add-on). Use when adding or fixing tests, reproducing a bug in a test, setting up phpunit for a Drupal project, or when tests fail on deprecations, schema errors or missing attributes.
---

# Drupal testing

## Pick the cheapest test that exercises the behaviour

| Type | Base class | Has | Use for | Cost |
|---|---|---|---|---|
| Unit | `Drupal\Tests\UnitTestCase` | Plain PHP, mocks | Pure logic, value objects, a service with mocked dependencies | ms |
| Kernel | `Drupal\KernelTests\KernelTestBase` | Container, database, only the modules you list | Services, entity CRUD and queries, access logic, hooks, config and schema, render arrays, plugins | seconds |
| Functional | `Drupal\Tests\BrowserTestBase` | Installed site, HTTP requests, no JavaScript | Routes, permissions, forms, page output, redirects | 10-60 s |
| FunctionalJavascript | `Drupal\FunctionalJavascriptTests\WebDriverTestBase` | Real browser through WebDriver | AJAX forms, behaviors, dialogs | slowest |

Default to Kernel. Go Functional only for what needs an HTTP request or the full form
workflow; go FunctionalJavascript only for client-side behaviour. Core's own JavaScript tests
use Nightwatch.

## Conventions

- Location and namespace: `my_module/tests/src/Kernel/FooTest.php` declares
  `namespace Drupal\Tests\my_module\Kernel;` (same pattern for `Unit`, `Functional`,
  `FunctionalJavascript`).
- Drupal 11.4 ships PHPUnit 11.5; Drupal 12 uses PHPUnit 12.5 and accepts only PHPUnit
  attributes. Write `#[Group('my_module')]`, `#[CoversClass(Foo::class)]`, `#[DataProvider('x')]`,
  not `@group` annotations.
- Kernel, Functional and FunctionalJavascript classes need `#[RunTestsInSeparateProcesses]`:
  omitting it is deprecated since 11.3 and throws in 12.0.
- `BrowserTestBase` tests must set `protected $defaultTheme` (use `'stark'` unless markup
  from a specific theme is under test).
- Config schema is checked strictly in Kernel and Functional tests: a schema error fails the
  test. Fix the schema instead of setting `$strictConfigSchema = FALSE`.
- Kernel tests enable exactly `$modules`, not their dependencies: list them all.

## Kernel test

```php
namespace Drupal\Tests\my_module\Kernel;

use Drupal\KernelTests\KernelTestBase;
use Drupal\my_module\ArticleCounter;
use Drupal\node\Entity\Node;
use Drupal\node\Entity\NodeType;
use Drupal\Tests\user\Traits\UserCreationTrait;
use PHPUnit\Framework\Attributes\CoversClass;
use PHPUnit\Framework\Attributes\Group;
use PHPUnit\Framework\Attributes\RunTestsInSeparateProcesses;

#[CoversClass(ArticleCounter::class)]
#[Group('my_module')]
#[RunTestsInSeparateProcesses]
final class ArticleCounterTest extends KernelTestBase {

  use UserCreationTrait;

  protected static $modules = ['system', 'user', 'field', 'filter', 'text', 'node', 'my_module'];

  protected function setUp(): void {
    parent::setUp();
    $this->installEntitySchema('user');
    $this->installEntitySchema('node');
    $this->installSchema('node', ['node_access']);
    $this->installConfig(['filter', 'node', 'my_module']);
    NodeType::create(['type' => 'article', 'name' => 'Article'])->save();
  }

  public function testCountsOwnArticles(): void {
    $author = $this->setUpCurrentUser(permissions: ['access content']);
    Node::create(['type' => 'article', 'title' => 'Mine', 'uid' => $author->id()])->save();
    Node::create(['type' => 'article', 'title' => 'Theirs', 'uid' => $this->createUser()->id()])->save();

    $this->assertSame(1, $this->container->get(ArticleCounter::class)->countForCurrentUser());
  }

}
```

Setup reminders: `installEntitySchema()` for every content entity you save,
`installConfig()` for modules whose default config you rely on, `installSchema()` only for
real `hook_schema()` tables (not `sequences`, deprecated). Run code as a given user with
`setUpCurrentUser()`. Render arrays: `$this->render($build)` then `$this->assertText()`.

## Functional test

```php
#[Group('my_module')]
#[RunTestsInSeparateProcesses]
final class SettingsFormTest extends BrowserTestBase {

  protected static $modules = ['my_module'];

  protected $defaultTheme = 'stark';

  public function testAccessAndSave(): void {
    $this->drupalGet('/admin/config/content/my-module');
    $this->assertSession()->statusCodeEquals(403);

    $this->drupalLogin($this->drupalCreateUser(['administer site configuration']));
    $this->drupalGet('/admin/config/content/my-module');
    $this->submitForm(['items_per_page' => 25], 'Save configuration');
    $this->assertSession()->pageTextContains('The configuration options have been saved.');
    $this->drupalGet('/admin/config/content/my-module');
    $this->assertSession()->fieldValueEquals('items_per_page', '25');
  }

}
```

Always test the denied case too (anonymous or a user without the permission).

## Unit test

```php
#[CoversClass(ArticleNotifier::class)]
#[Group('my_module')]
final class ArticleNotifierTest extends UnitTestCase {

  public function testStoresNodeId(): void {
    $node = $this->createMock(NodeInterface::class);
    $node->method('id')->willReturn('42');
    $state = $this->createMock(StateInterface::class);
    $state->expects($this->once())->method('set')->with('my_module.last_article', 42);

    (new ArticleNotifier($state))->notify($node);
  }

}
```

## FunctionalJavascript essentials

Extend `WebDriverTestBase`; after an interaction wait instead of sleeping:
`$this->assertSession()->assertWaitOnAjaxRequest()`,
`->waitForElementVisible('css', '.my-result')`, `->waitForText('Saved')`.

## Running tests

Requirements: `composer require --dev drupal/core-dev` (PHPUnit, Mink, phpstan-drupal,
Coder). Database and base URL come from environment variables or a `phpunit.xml`.

```bash
# From the project root, using core's phpunit.xml.dist.
export SIMPLETEST_DB='mysql://user:pass@localhost/drupal_test'   # or sqlite://localhost//tmp/test.sqlite
export SIMPLETEST_BASE_URL='http://my-site.localhost'           # needed by Functional tests
vendor/bin/phpunit -c web/core web/modules/custom/my_module
vendor/bin/phpunit -c web/core --filter testCountsOwnArticles web/modules/custom/my_module
vendor/bin/phpunit -c web/core --group my_module
```

To keep settings in the repo, copy `web/core/phpunit.xml.dist` to `phpunit.xml` in the
project root and fix its relative paths (`bootstrap="web/core/tests/bootstrap.php"`, test
suite directories) before adding the `<env>` values.

### DDEV

Install the Selenium add-on; besides Chrome it sets `SIMPLETEST_DB`,
`SIMPLETEST_BASE_URL=http://web` and the WebDriver arguments in the web container:

```bash
ddev add-on get ddev/ddev-selenium-standalone-chrome   # v2 for Drupal 11+
ddev restart
ddev exec vendor/bin/phpunit -c web/core web/modules/custom/my_module
```

Without the add-on, add the variables yourself in `.ddev/config.testing.yaml` and restart:

```yaml
web_environment:
  - SIMPLETEST_DB=mysql://db:db@db/db
  - SIMPLETEST_BASE_URL=http://web
  - BROWSERTEST_OUTPUT_DIRECTORY=/tmp
```

## When a test fails

- "must specify the #[RunTestsInSeparateProcesses] attribute": add it.
- Schema errors (`Schema errors for my_module.settings ...`): fix `config/schema`.
- Deprecation failures: fix the call (see the `upgrades` skill); do not silence them.
- "Entity queries must explicitly set whether the query should be access checked": add
  `->accessCheck()` in the code under test.
- Functional test sees a 403 where 200 is expected: the test user lacks a permission, or the
  route requirement is wrong. Check both before touching the access logic.
