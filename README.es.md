# Drupal Dev para Claude Code

Un plugin de [Claude Code](https://code.claude.com/docs) para equipos Drupal. Da a Claude
conocimiento actual y verificado de cómo se escribe, revisa, prueba y despliega código para
Drupal 10, 11 y 12, además de un subagente de revisión y un hook que revisa cada fichero
PHP, Twig y YAML que Claude edita.

- **9 skills** que solo se cargan cuando la tarea las necesita: desarrollo de módulos,
  theming, gestión de configuración, seguridad, testing, actualizaciones, rendimiento,
  migraciones y headless/JSON:API.
- **Subagente `drupal-reviewer`**, que revisa un diff y ordena los hallazgos por gravedad,
  con `fichero:línea`.
- **Hook `drupal-lint`**, que ejecuta `php -l`, `phpcs` (Drupal y DrupalPractice), una
  comprobación de sintaxis de Twig y `yaml-lint` justo después de cada edición, con las
  herramientas que ya tiene el `vendor/bin` del proyecto.

La información está al día a octubre de 2026 (Drupal 11.4, Drupal 12.0 en beta) y cada dato
remite a una fuente oficial en [docs/SOURCES.md](docs/SOURCES.md). Los ejemplos de código
se han ejecutado en un sitio Drupal 11.4.

This README is also available in [English](README.md).

## Instalación

Dentro de Claude Code:

```
/plugin marketplace add andresmoreno28/drupal-dev-claude-code
/plugin install drupal-dev@drupal-dev
```

O desde la terminal:

```bash
claude plugin marketplace add andresmoreno28/drupal-dev-claude-code
claude plugin install drupal-dev@drupal-dev
```

Para proponerlo a todo el equipo de un repositorio, añade esto a `.claude/settings.json`
(cada persona sigue confirmando la instalación):

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

Claude elige la skill por su descripción; también puedes lanzarla a mano, por ejemplo
`/drupal-dev:security`.

| Skill | Qué cubre |
|---|---|
| `module-development` | Servicios y autowiring, hooks orientados a objetos con `#[Hook]` (11.1+) y su orden, plugins con atributos PHP, rutas y requisitos de acceso, formularios con `#config_target`, event subscribers y metadatos de caché (tags, contexts, max-age). |
| `theming` | Temas generados con Starterkit, reglas de Twig, preprocess (incluidos los hooks OOP de temas en 11.3+), librerías y `Drupal.behaviors` con `once()`, Single Directory Components y una lista de accesibilidad para plantillas. |
| `config-management` | Sincronización de configuración, overrides en `settings.php`, Config Split y Config Ignore, hooks de update, post-update y deploy, el orden de `drush deploy` y recipes con config actions e inputs. |
| `security` | Una lista de patrones que hay que señalar y cómo corregirlos: XSS, inyección SQL, acceso en rutas, entidades, campos y consultas, CSRF, subidas de ficheros, redirecciones, secretos y la política de avisos del Security Team. |
| `testing` | Cuándo usar Unit, Kernel, Functional o FunctionalJavascript; preparación de tests kernel; atributos de PHPUnit y `#[RunTestsInSeparateProcesses]`; cómo ejecutarlos en local y en DDEV. |
| `upgrades` | El calendario 10 -> 11 -> 12 y los requisitos de PHP, Upgrade Status, drupal-rector y phpstan-drupal, las extensiones que salen del core en Drupal 12, la compatibilidad de contrib y los comandos de Composer. |
| `performance` | Capas de caché, cabeceras de caché, lazy builders y placeholders, BigPipe, cargas N+1 de entidades, colas y batches, cron y assets de front. |
| `migrations` | Migrate API (source, process, destination), pipelines de process, fuentes JSON/XML de Migrate Plus, comandos de Drush, plugins propios y tests de migraciones. |
| `headless` | Consultas JSON:API (includes, sparse fieldsets, filtros, paginación, revisiones), escrituras, autenticación, CORS y caché de las respuestas de la API. |

## Subagente de revisión

`drupal-reviewer` lee el cambio (árbol de trabajo, rama, rango de commits o un diff pegado),
pasa los linters que encuentre en `vendor/bin` sobre los ficheros cambiados y devuelve un
veredicto, los hallazgos agrupados en Critical / High / Medium / Low con `fichero:línea` y
una corrección concreta, los resultados de las herramientas y los tests que faltan. Nunca
modifica ficheros.

Pídelo con tus palabras ("revisa mis cambios con el agente drupal-reviewer") o
menciónalo: `@agent-drupal-dev:drupal-reviewer revisa esta rama contra main`.

## Hook de lint

Cuando Claude escribe o edita un fichero, el hook lo revisa y le devuelve los problemas (y a
ti te muestra un resumen de una línea), así que se corrigen en el mismo turno.

| Ficheros | Comprobaciones |
|---|---|
| `*.php`, `*.module`, `*.inc`, `*.install`, `*.theme`, `*.profile` | `php -l`; después `phpcs` con tu `phpcs.xml(.dist)` o, si no hay, `Drupal,DrupalPractice` de `drupal/coder` |
| `*.twig` | Twig-CS-Fixer con tu `.twig-cs-fixer(.dist).php`, o solo sintaxis si no lo tienes |
| `*.yml`, `*.yaml` | `yaml-lint` de Symfony (acepta tags como `!tagged_iterator`) |

- Usa el `vendor/bin` más cercano por encima del fichero editado. Si falta una herramienta,
  se la salta sin avisar; ignora `vendor/` y `node_modules/`.
- No bloquea a Claude ni escribe ficheros (las cachés de las herramientas van desactivadas).
  Medido con la caché del sistema de ficheros caliente: 0,3-0,5 s por fichero en Linux y
  alrededor de 1 s en Windows; las ediciones de otros tipos de fichero salen en milisegundos.
- `DRUPAL_DEV_LINT=0` lo desactiva; `DRUPAL_DEV_LINT_MAX` limita los hallazgos que se
  devuelven por herramienta (40 por defecto). Defínelas en tu shell o en `env` dentro de la
  configuración de Claude Code.
- Necesita `php` en la máquina donde corre Claude Code. Si PHP solo existe dentro de DDEV u
  otro contenedor, el hook no dice nada; lanza las mismas comprobaciones con `ddev exec`.
- En Windows necesita Git Bash, que es el shell que usa Claude Code para los hooks cuando
  está instalado.

Para tener `phpcs` y Twig-CS-Fixer en un proyecto: `composer require --dev drupal/core-dev`
(trae Coder) y, para Twig, `composer require --dev vincentlanglet/twig-cs-fixer`
(`drupal/core-dev` lo incluye desde Drupal 12).

## Ejemplos de peticiones

- "Añade un bloque con los cinco últimos artículos del usuario actual, con los metadatos de caché correctos."
- "Pasa los hooks de `my_module.module` a hooks OOP. El módulo sigue soportando Drupal 10.3."
- "¿Está este sitio listo para Drupal 12? Revisa el código propio y los módulos contrib."
- "Crea un componente SDC de tarjeta en mi tema y úsalo en `node--article--teaser.html.twig`."
- "Escribe un test kernel para `ArticleCounter` y dime cómo lanzarlo en DDEV."
- "Las páginas anónimas de este sitio nunca se cachean. Averigua por qué."
- "Escribe una recipe que añada el rol Editor y etiquetas en los artículos."
- "Importa los artículos de este endpoint JSON con Migrate."
- "Expón los artículos por JSON:API a un front en otro dominio."
- "@agent-drupal-dev:drupal-reviewer revisa los cambios preparados."

## Requisitos

- Claude Code con soporte de plugins.
- Para el hook: un shell POSIX (macOS, Linux, WSL o Git Bash en Windows) y PHP; `phpcs`,
  Twig-CS-Fixer y `yaml-lint` de las dependencias de Composer del proyecto son opcionales.
- Las skills apuntan a Drupal 10.3+ y 11, y señalan lo que cambia en Drupal 12.

## Contribuir

Las issues y las merge requests son bienvenidas. Para trabajar en el plugin:

```bash
git clone https://github.com/andresmoreno28/drupal-dev-claude-code.git
cd drupal-dev-claude-code
claude --plugin-dir .          # carga tu copia de trabajo para una sesión
sh scripts/check.sh            # manifiestos, frontmatter, finales de línea, tests del hook
```

- Cada afirmación técnica necesita una fuente oficial (documentación o change records de
  drupal.org, api.drupal.org o el código del core, páginas de proyecto, notas de versión).
  Añádela a `docs/SOURCES.md` en el mismo cambio. Si no se puede verificar, fuera.
- Skills cortas y prácticas: reglas, listas de comprobación y ejemplos pequeños que funcionen.
- Los cambios en el hook llevan test en `tests/hooks/run.sh`. Para probar también las
  herramientas reales, apunta `DRUPAL_DEV_TEST_PROJECT` a un proyecto Composer que las
  tenga: `DRUPAL_DEV_TEST_PROJECT=/ruta/a/drupal sh tests/hooks/run.sh`.
- Anota los cambios visibles en `CHANGELOG.md`.

## Licencia

[MIT](LICENSE) © 2026 Andrés Moreno Rubio.

Hecho por [Andrés Moreno Rubio](https://andresmoreno.dev), desarrollador Drupal y
mantenedor de los módulos Config Guardian y Midgard en drupal.org.
