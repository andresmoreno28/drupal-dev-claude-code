#!/bin/sh
# Repository checks for the drupal-dev plugin. POSIX sh.
#
#   sh scripts/check.sh
#
# 1. JSON files parse and the manifests have the fields this plugin relies on.
# 2. Every skills/*/SKILL.md and agents/*.md has valid frontmatter.
# 3. Shell scripts parse, use LF line endings, and the hook tests pass.
# 4. `claude plugin validate --strict` passes, when the Claude Code CLI is installed
#    (a local check; set CHECK_SKIP_CLAUDE=1 to skip it).
#
# Needs one of jq, python3, php or node for JSON parsing (CHECK_JSON_TOOL picks one).

cd "$(dirname "$0")/.." || exit 1

failures=0
fail() { failures=$((failures + 1)); printf 'FAIL %s\n' "$1"; }
pass() { printf 'ok   %s\n' "$1"; }

# --- JSON ----------------------------------------------------------------------

if [ -n "${CHECK_JSON_TOOL:-}" ]; then json_tool=$CHECK_JSON_TOOL
elif command -v jq >/dev/null 2>&1; then json_tool=jq
elif command -v python3 >/dev/null 2>&1; then json_tool=python3
elif command -v php >/dev/null 2>&1; then json_tool=php
elif command -v node >/dev/null 2>&1; then json_tool=node
else
  printf 'FAIL no JSON parser found (install jq, python3, php or node)\n'
  exit 1
fi

# json_get FILE PATH: print the value at a dot path such as plugins.0.source
# (empty output when the path is missing; exit 1 when the file is not valid JSON).
json_get() {
  case $json_tool in
    jq) jq -er --arg p "$2" 'getpath($p | split(".") | map(tonumber? // .)) // empty' "$1" 2>/dev/null ||
      jq -e . "$1" >/dev/null 2>&1 ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in sys.argv[2].split("."):
    try:
        d = d[int(k)] if isinstance(d, list) else d[k]
    except (KeyError, IndexError, ValueError, TypeError):
        sys.exit(0)
print(d if not isinstance(d, (dict, list)) else json.dumps(d))
' "$1" "$2" 2>/dev/null ;;
    php) php -r '
$d = json_decode(file_get_contents($argv[1]), TRUE, 512, JSON_THROW_ON_ERROR);
foreach (explode(".", $argv[2]) as $k) {
  if (!is_array($d) || !array_key_exists(is_numeric($k) ? (int) $k : $k, $d)) exit(0);
  $d = $d[is_numeric($k) ? (int) $k : $k];
}
echo is_array($d) ? json_encode($d) : $d, "\n";
' "$1" "$2" 2>/dev/null ;;
    node) node -e '
const d0 = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
let d = d0;
for (const k of process.argv[2].split(".")) { if (d == null || !(k in Object(d))) process.exit(0); d = d[k]; }
console.log(typeof d === "object" ? JSON.stringify(d) : String(d));
' "$1" "$2" 2>/dev/null ;;
  esac
}

expect_json() {
  _file=$1 _path=$2 _want=$3
  _got=$(json_get "$_file" "$_path")
  if [ $? -ne 0 ]; then fail "$_file is not valid JSON"; return; fi
  if [ "$_got" = "$_want" ]; then pass "$_file: $_path = $_want"; else fail "$_file: $_path is '$_got', expected '$_want'"; fi
}

expect_json_match() {
  _file=$1 _path=$2 _re=$3
  _got=$(json_get "$_file" "$_path")
  if printf '%s\n' "$_got" | grep -Eq "$_re"; then pass "$_file: $_path matches $_re"; else fail "$_file: $_path is '$_got'"; fi
}

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  if [ -f "$f" ] && json_get "$f" '__parse_only__' >/dev/null; then pass "$f parses ($json_tool)"; else fail "$f missing or invalid JSON"; fi
done

plugin_name=$(json_get .claude-plugin/plugin.json name)
expect_json_match .claude-plugin/plugin.json name '^[a-z0-9]+(-[a-z0-9]+)*$'
expect_json_match .claude-plugin/plugin.json version '^[0-9]+\.[0-9]+\.[0-9]+$'
expect_json .claude-plugin/plugin.json license MIT
expect_json_match .claude-plugin/plugin.json author.name '.+'
expect_json_match .claude-plugin/plugin.json description '.{20,}'
expect_json_match .claude-plugin/marketplace.json name '^[A-Za-z0-9][A-Za-z0-9._-]*$'
expect_json_match .claude-plugin/marketplace.json owner.name '.+'
expect_json .claude-plugin/marketplace.json plugins.0.name "$plugin_name"
expect_json .claude-plugin/marketplace.json plugins.0.source './'
expect_json hooks/hooks.json hooks.PostToolUse.0.hooks.0.type command

version=$(json_get .claude-plugin/plugin.json version)
if grep -q "^## \[$version\]" CHANGELOG.md 2>/dev/null; then pass "CHANGELOG.md has an entry for $version"; else fail "CHANGELOG.md has no '## [$version]' entry"; fi

hook_cmd=$(json_get hooks/hooks.json hooks.PostToolUse.0.hooks.0.command)
hook_script=$(printf '%s\n' "$hook_cmd" | sed -n 's|.*${CLAUDE_PLUGIN_ROOT}/\([^"]*\).*|\1|p')
if [ -n "$hook_script" ] && [ -f "$hook_script" ]; then pass "hook command points to $hook_script"; else fail "hook command target not found: $hook_cmd"; fi

# --- Frontmatter -----------------------------------------------------------------

# frontmatter_value FILE KEY: print the single-line value of KEY in the frontmatter.
frontmatter_value() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 { v = substr($0, length(key) + 2); sub(/^ +/, "", v); print v; exit }
  ' "$1"
}

check_frontmatter() {
  _file=$1 _kind=$2 _expected_name=$3
  if [ "$(head -n 1 "$_file")" != '---' ]; then fail "$_file: first line must be ---"; return; fi
  if [ "$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$_file")" = '' ]; then fail "$_file: frontmatter is not closed"; return; fi
  _name=$(frontmatter_value "$_file" name)
  _desc=$(frontmatter_value "$_file" description)
  _ok=1
  if ! printf '%s\n' "$_name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || [ ${#_name} -gt 64 ]; then
    fail "$_file: name '$_name' must be lowercase letters, digits and single hyphens (max 64)"; _ok=0
  fi
  if [ -n "$_expected_name" ] && [ "$_name" != "$_expected_name" ]; then
    fail "$_file: name '$_name' must match its directory '$_expected_name'"; _ok=0
  fi
  if [ -z "$_desc" ]; then fail "$_file: description is missing"; _ok=0; fi
  if [ ${#_desc} -gt 1024 ]; then fail "$_file: description is ${#_desc} characters (max 1024)"; _ok=0; fi
  if [ ${#_desc} -lt 80 ]; then fail "$_file: description is too short to say when to use it"; _ok=0; fi
  # Plain YAML scalars end at " #" (comment) and break on ": ".
  case $_desc in
    *' #'* | *': '* | '['* | '{'* | '>'* | '|'* | '*'* | '&'* | '!'* | '%'* | '@'* | '`'* | "'"* | '"'*)
      fail "$_file: description has YAML-sensitive characters; rephrase it"; _ok=0 ;;
  esac
  if [ "$_kind" = skill ]; then
    _lines=$(wc -l <"$_file")
    if [ "$_lines" -gt 500 ]; then fail "$_file: $_lines lines (keep SKILL.md under 500)"; _ok=0; fi
  else
    _model=$(frontmatter_value "$_file" model)
    case $_model in '' | inherit | sonnet | opus | haiku | fable | claude-*) ;; *) fail "$_file: unknown model '$_model'"; _ok=0 ;; esac
    for _field in hooks mcpServers permissionMode; do
      if [ -n "$(frontmatter_value "$_file" "$_field")" ]; then fail "$_file: '$_field' is ignored in plugin agents"; _ok=0; fi
    done
  fi
  [ "$_ok" = 1 ] && pass "$_file frontmatter ($_name, ${#_desc} chars)"
}

skill_count=0
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  skill_count=$((skill_count + 1))
  check_frontmatter "$f" skill "$(basename "$(dirname "$f")")"
done
[ "$skill_count" -gt 0 ] || fail 'no skills found'

agent_count=0
for f in agents/*.md; do
  [ -f "$f" ] || continue
  agent_count=$((agent_count + 1))
  check_frontmatter "$f" agent ''
done
[ "$agent_count" -gt 0 ] || fail 'no agents found'

# Second opinion from a real YAML parser when one is available.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  if python3 - skills/*/SKILL.md agents/*.md <<'EOF'
import sys, yaml
bad = 0
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    data = yaml.safe_load(text.split("---\n", 2)[1])
    for key in ("name", "description"):
        line = next((l for l in text.splitlines() if l.startswith(key + ":")), "")
        if not isinstance(data.get(key), str) or data[key] != line.split(":", 1)[1].strip():
            print("     %s: YAML value of %s differs from the written line" % (path, key))
            bad = 1
sys.exit(bad)
EOF
  then pass 'frontmatter parses with PyYAML'; else fail 'frontmatter does not parse as written'; fi
fi

# --- Scripts and line endings ------------------------------------------------------

# tr + cmp rather than grep: grep on Windows strips CR at the end of lines.
crlf_files=$(git ls-files -co --exclude-standard 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  tr -d '\r' <"$f" | cmp -s - "$f" || printf '%s ' "$f"
done)
if [ -z "$crlf_files" ]; then pass 'no CRLF line endings'; else fail "CRLF line endings in: $crlf_files"; fi

for f in hooks/drupal-lint.sh tests/hooks/run.sh scripts/check.sh; do
  if sh -n "$f"; then pass "$f parses (sh -n)"; else fail "$f has syntax errors"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s sh hooks/drupal-lint.sh tests/hooks/run.sh scripts/check.sh; then pass 'shellcheck'; else fail 'shellcheck'; fi
fi

printf '\n--- hook tests ---\n'
if sh tests/hooks/run.sh; then pass 'hook tests'; else fail 'hook tests'; fi
printf '\n'

# --- Claude Code validator ------------------------------------------------------------

if [ "${CHECK_SKIP_CLAUDE:-0}" != 1 ] && command -v claude >/dev/null 2>&1; then
  for target in . .claude-plugin/plugin.json ./skills ./agents; do
    if claude plugin validate "$target" --strict >/dev/null 2>&1; then
      pass "claude plugin validate $target --strict"
    else
      fail "claude plugin validate $target --strict"
      claude plugin validate "$target" --strict 2>&1 | sed 's/^/     | /'
    fi
  done
else
  printf 'skip claude plugin validate (CLI not found or CHECK_SKIP_CLAUDE=1)\n'
fi

printf '\n'
if [ "$failures" -eq 0 ]; then printf 'All checks passed.\n'; else printf '%s check(s) failed.\n' "$failures"; fi
[ "$failures" -eq 0 ]
