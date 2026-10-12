#!/bin/sh
# Tests for hooks/drupal-lint.sh. POSIX sh; runs on Linux, macOS, WSL and Git Bash.
#
#   sh tests/hooks/run.sh
#
# Unit cases use small PHP stubs in place of phpcs, twig-cs-fixer and
# yaml-lint, so they need only `php` (they are skipped without it; the
# missing-tools cases always run).
#
# Integration cases run the real tools when DRUPAL_DEV_TEST_PROJECT points to a
# Composer project whose vendor/bin has phpcs (with drupal/coder), yaml-lint and,
# optionally, twig-cs-fixer. They create and remove a temporary folder inside
# that project.

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
hook="$repo/hooks/drupal-lint.sh"
work="$here/.tmp"

pass=0
fail=0
skip=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /'; }
skipped() { skip=$((skip + 1)); printf 'skip %s\n' "$1"; }

# json_input PATH: hook input for an Edit of PATH.
json_input() {
  _escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"session_id":"test","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"tool_response":{"filePath":"%s"}}' "$_escaped" "$_escaped"
}

# run_hook PATH [ENV=VALUE...]: run the hook, store stdout in $out, status in $rc.
run_hook() {
  _path=$1
  shift
  out=$(json_input "$_path" | env CLAUDE_PLUGIN_ROOT="$repo" "$@" sh "$hook" 2>&1)
  rc=$?
}

expect_silent() {
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "$1"; else ko "$1" "exit=$rc output=$out"; fi
}

expect_contains() {
  _name=$1
  shift
  if [ "$rc" -ne 0 ]; then ko "$_name" "exit=$rc"; return; fi
  for _needle in "$@"; do
    case $out in
      *"$_needle"*) ;;
      *) ko "$_name" "missing: $_needle
output: $out"; return ;;
    esac
  done
  ok "$_name"
}

# expect_json NAME: output is one JSON object with the documented PostToolUse fields.
expect_json() {
  if printf '%s' "$out" | php -r '
    $d = json_decode(stream_get_contents(STDIN), TRUE);
    exit(is_array($d)
      && is_string($d["systemMessage"] ?? NULL)
      && ($d["hookSpecificOutput"]["hookEventName"] ?? NULL) === "PostToolUse"
      && is_string($d["hookSpecificOutput"]["additionalContext"] ?? NULL) ? 0 : 1);
  '; then ok "$1"; else ko "$1" "$out"; fi
}

checksum() { find "$1" -type f ! -name '*.log' -exec cksum {} + 2>/dev/null | sort; }

rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT INT TERM

# --- Fixtures -----------------------------------------------------------------

proj="$work/project"
mod="$proj/web/modules/custom/demo"
mkdir -p "$mod/templates" "$mod/config" "$proj/vendor/bin" \
  "$proj/vendor/drupal/coder/coder_sniffer/Drupal" "$proj/vendor/acme/lib"

cat >"$mod/Good.php" <<'EOF'
<?php

declare(strict_types=1);

namespace Drupal\demo;

/**
 * Says hello.
 */
final class Good {

  /**
   * Returns a greeting.
   */
  public function hello(string $name): string {
    return 'Hello ' . $name;
  }

}
EOF

cat >"$mod/demo.module" <<'EOF'
<?php

function demo_help($route_name) {
  // BADSTYLE
  $x = array(1,2);
  return $x;
}
EOF

cat >"$mod/broken.inc" <<'EOF'
<?php

function demo_broken( {
EOF

cat >"$mod/many.install" <<'EOF'
<?php
// MANY
EOF

printf 'a\n' >"$mod/notes.txt"
printf '<p>{{ label }}</p>\n' >"$mod/templates/ok.html.twig"
printf '<p>{{ label }</p>\n' >"$mod/templates/bad.html.twig"
printf 'name: Demo\ntype: module\n' >"$mod/demo.info.yml"
printf 'name: Demo\n  type: module\n' >"$mod/config/bad.yml"
printf '<?php\nfunction x( {\n' >"$proj/vendor/acme/lib/Broken.php"

# Stub tools. Each logs its argv and prints findings for marker files.
cat >"$proj/vendor/bin/phpcs" <<'EOF'
<?php
file_put_contents(__DIR__ . '/phpcs.log', implode(' ', array_slice($argv, 1)) . "\n");
$file = end($argv);
$code = is_file($file) ? file_get_contents($file) : '';
if (str_contains($code, 'BADSTYLE')) {
  echo getcwd() . "/$file:3:1: error - Missing function doc comment (Drupal.Commenting.FunctionComment.Missing)\n";
  echo getcwd() . "/$file:5:8: warning - Short array syntax must be used (Drupal.Arrays.DisallowLongArraySyntax.Found)\n";
  exit(2);
}
if (str_contains($code, 'MANY')) {
  for ($i = 1; $i <= 60; $i++) {
    echo getcwd() . "/$file:$i:1: error - Finding $i (Test.Many)\n";
  }
  exit(2);
}
exit(0);
EOF

cat >"$proj/vendor/bin/twig-cs-fixer" <<'EOF'
<?php
file_put_contents(__DIR__ . '/twig.log', implode(' ', array_slice($argv, 1)) . "\n");
$file = end($argv);
if (str_contains((string) @file_get_contents($file), '{{ label }<')) {
  echo "::error file=$file::Unable to tokenize file: Unexpected character \"}\" at line 1.\n";
  exit(1);
}
exit(0);
EOF

cat >"$proj/vendor/bin/yaml-lint" <<'EOF'
<?php
file_put_contents(__DIR__ . '/yaml.log', implode(' ', array_slice($argv, 1)) . "\n");
$file = end($argv);
if (str_contains((string) @file_get_contents($file), "\n  type")) {
  echo "  ERROR  in $file\n";
  echo "::error file=$file,line=2,col=0::A colon cannot be used in an unquoted mapping value at line 2.\n";
  exit(1);
}
exit(0);
EOF

before=$(checksum "$proj")

# --- Cases that need no PHP -----------------------------------------------------

out=$(printf '{"tool_input":{"file_path":"%s/Good.php"}}' "$mod" | env DRUPAL_DEV_LINT=0 sh "$hook" 2>&1)
rc=$?
expect_silent 'disabled with DRUPAL_DEV_LINT=0'

run_hook "$mod/notes.txt"
expect_silent 'ignores files that are not PHP, Twig or YAML'

out=$(printf 'not json at all .php"' | sh "$hook" 2>&1)
rc=$?
expect_silent 'malformed input JSON is ignored'

out=$(printf '' | sh "$hook" 2>&1)
rc=$?
expect_silent 'empty input is ignored'

# A PATH without any php binary (keep the directories of the basic utilities).
nophp_path=''
old_ifs=$IFS
IFS=:
for d in $PATH; do
  [ -n "$d" ] || continue
  if [ -x "$d/php" ] || [ -x "$d/php.exe" ]; then continue; fi
  nophp_path="$nophp_path${nophp_path:+:}$d"
done
IFS=$old_ifs
if env PATH="$nophp_path" sh -c 'command -v php' >/dev/null 2>&1; then
  skipped 'missing-php case (could not hide php from PATH)'
else
  run_hook "$mod/broken.inc" PATH="$nophp_path"
  expect_silent 'skips silently when php is not installed'
fi

# --- Cases with PHP and stub tools ----------------------------------------------

if ! command -v php >/dev/null 2>&1; then
  skipped 'php not found: stub and integration cases'
else
  run_hook "$mod/Missing.php"
  expect_silent 'ignores a file that no longer exists'

  run_hook "$proj/vendor/acme/lib/Broken.php"
  expect_silent 'ignores files under vendor/'

  run_hook "$mod/Good.php"
  expect_silent 'clean PHP produces no output'

  run_hook "$mod/broken.inc" CLAUDE_PROJECT_DIR="$proj"
  expect_contains 'reports php -l syntax errors' 'php -l' 'Parse error' 'on line 3' \
    'web/modules/custom/demo/broken.inc'
  expect_json 'syntax error output is valid hook JSON'
  case $(cat "$proj/vendor/bin/phpcs.log" 2>/dev/null) in
    *broken.inc*) ko 'phpcs is not run on files with syntax errors' ;;
    *) ok 'phpcs is not run on files with syntax errors' ;;
  esac

  run_hook "$mod/demo.module"
  expect_contains 'reports phpcs findings with sniff codes' 'phpcs (Drupal, DrupalPractice)' \
    '3:1: error: Missing function doc comment (Drupal.Commenting.FunctionComment.Missing)' \
    '5:8: warning: Short array syntax' 'problems in'
  expect_json 'phpcs output is valid hook JSON'
  args=$(cat "$proj/vendor/bin/phpcs.log")
  case $args in
    *--standard=Drupal,DrupalPractice*--no-cache* | *--no-cache*--standard=Drupal,DrupalPractice*)
      case $args in
        *--extensions=php,module,inc,install,theme,profile*) ok 'phpcs gets Drupal standards, --no-cache and extensions' ;;
        *) ko 'phpcs gets Drupal standards, --no-cache and extensions' "$args" ;;
      esac ;;
    *) ko 'phpcs gets Drupal standards, --no-cache and extensions' "$args" ;;
  esac

  run_hook "$mod/many.install" DRUPAL_DEV_LINT_MAX=5
  expect_contains 'caps the number of reported findings' '5:1: error: Finding 5' '... and 55 more' '60 problems'
  case $out in
    *'Finding 6 '*) ko 'does not print findings beyond the cap' ;;
    *) ok 'does not print findings beyond the cap' ;;
  esac

  printf '<?xml version="1.0"?><ruleset name="p"><rule ref="Drupal"/></ruleset>\n' >"$proj/phpcs.xml.dist"
  run_hook "$mod/demo.module"
  expect_contains 'uses the project ruleset when present' 'phpcs (project ruleset)'
  case $(cat "$proj/vendor/bin/phpcs.log") in
    *--standard=*) ko 'does not force --standard with a project ruleset' ;;
    *) ok 'does not force --standard with a project ruleset' ;;
  esac
  rm -f "$proj/phpcs.xml.dist"

  mv "$proj/vendor/drupal" "$work/drupal-coder-away"
  rm -f "$proj/vendor/bin/phpcs.log"
  run_hook "$mod/demo.module"
  expect_silent 'skips phpcs without drupal/coder or a project ruleset'
  if [ -f "$proj/vendor/bin/phpcs.log" ]; then ko 'phpcs not started without standards'; else ok 'phpcs not started without standards'; fi
  mv "$work/drupal-coder-away" "$proj/vendor/drupal"

  run_hook "$mod/templates/ok.html.twig"
  expect_silent 'clean Twig produces no output'
  case $(cat "$proj/vendor/bin/twig.log") in
    *twig-syntax-only.php*--no-cache* | *--no-cache*twig-syntax-only.php*) ok 'twig-cs-fixer runs syntax-only without project config' ;;
    *) ko 'twig-cs-fixer runs syntax-only without project config' "$(cat "$proj/vendor/bin/twig.log")" ;;
  esac

  run_hook "$mod/templates/bad.html.twig"
  expect_contains 'reports Twig tokenizer errors' 'twig-cs-fixer (syntax only)' 'error: Unable to tokenize file'
  expect_json 'Twig output is valid hook JSON'

  printf '<?php return new TwigCsFixer\\Config\\Config();\n' >"$proj/.twig-cs-fixer.dist.php"
  run_hook "$mod/templates/bad.html.twig"
  expect_contains 'uses the project Twig config when present' 'twig-cs-fixer (project rules)'
  rm -f "$proj/.twig-cs-fixer.dist.php"

  run_hook "$mod/demo.info.yml"
  expect_silent 'valid YAML produces no output'
  case $(cat "$proj/vendor/bin/yaml.log") in
    *--parse-tags*) ok 'yaml-lint parses Symfony tags such as !tagged_iterator' ;;
    *) ko 'yaml-lint parses Symfony tags such as !tagged_iterator' ;;
  esac

  run_hook "$mod/config/bad.yml"
  expect_contains 'reports YAML syntax errors' 'yaml-lint' '2: error: A colon cannot be used'
  case $out in
    *'ERROR  in'*) ko 'only parses the machine-readable yaml-lint lines' ;;
    *) ok 'only parses the machine-readable yaml-lint lines' ;;
  esac

  if command -v cygpath >/dev/null 2>&1; then
    run_hook "$(cygpath -w "$mod/demo.module")"
    expect_contains 'accepts Windows paths with backslashes' 'Missing function doc comment'
  else
    skipped 'Windows path case (no cygpath)'
  fi

  start=$(date +%s)
  run_hook "$mod/demo.module"
  elapsed=$(($(date +%s) - start))
  if [ "$elapsed" -le 3 ]; then ok "finishes quickly with stub tools (${elapsed}s)"; else ko "finishes quickly with stub tools (${elapsed}s)"; fi
fi

after=$(checksum "$proj")
if [ "$before" = "$after" ]; then ok 'never modifies the linted files'; else ko 'never modifies the linted files'; fi

# --- Integration with real tools ---------------------------------------------------

if [ -n "${DRUPAL_DEV_TEST_PROJECT:-}" ] && command -v php >/dev/null 2>&1; then
  real=$(cd "$DRUPAL_DEV_TEST_PROJECT" && pwd)
  tmp="$real/.drupal-dev-test-tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  cp "$mod/Good.php" "$mod/demo.module" "$mod/broken.inc" "$tmp/"
  printf '{%% trans %%}Hello {{ name }}{%% endtrans %%}\n<p{{ attributes.addClass("x") }}>{{ "Read more"|t }}</p>\n' >"$tmp/ok.html.twig"
  printf '<p>{{ label }</p>\n' >"$tmp/bad.html.twig"
  printf 'services:\n  demo.thing:\n    class: Drupal\\demo\\Thing\n    arguments: [!tagged_iterator demo.plugin]\n' >"$tmp/demo.services.yml"
  printf 'name: Demo\ntype: module\n  core_version_requirement: ^11\n' >"$tmp/demo.info.yml"
  tbefore=$(checksum "$tmp")
  cache_before=$(ls -a "$real" | grep -c 'cache')

  if [ -f "$real/vendor/bin/phpcs" ]; then
    run_hook "$tmp/demo.module"
    expect_contains 'real phpcs: Drupal findings' 'Drupal.Commenting.FunctionComment.Missing' 'DisallowLongArraySyntax'
    run_hook "$tmp/Good.php"
    expect_silent 'real phpcs: clean class passes'
  else
    skipped 'real phpcs (not installed)'
  fi
  run_hook "$tmp/broken.inc"
  expect_contains 'real php -l: syntax error' 'Parse error'
  if [ -f "$real/vendor/bin/twig-cs-fixer" ]; then
    run_hook "$tmp/ok.html.twig"
    expect_silent 'real twig-cs-fixer: Drupal Twig (trans, |t, attributes) passes'
    run_hook "$tmp/bad.html.twig"
    expect_contains 'real twig-cs-fixer: tokenizer error' 'Unable to tokenize'
  else
    skipped 'real twig-cs-fixer (not installed)'
  fi
  if [ -f "$real/vendor/bin/yaml-lint" ]; then
    run_hook "$tmp/demo.services.yml"
    expect_silent 'real yaml-lint: services with !tagged_iterator pass'
    run_hook "$tmp/demo.info.yml"
    expect_contains 'real yaml-lint: syntax error' 'line' 'colon cannot be used'
  else
    skipped 'real yaml-lint (not installed)'
  fi
  tafter=$(checksum "$tmp")
  if [ "$tbefore" = "$tafter" ]; then ok 'real tools never modify files'; else ko 'real tools never modify files'; fi
  if [ "$(ls -a "$real" | grep -c 'cache')" = "$cache_before" ]; then
    ok 'real tools write no cache files into the project'
  else
    ko 'real tools write no cache files into the project'
  fi
  rm -rf "$tmp"
else
  skipped 'integration with real tools (set DRUPAL_DEV_TEST_PROJECT)'
fi

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
