#!/bin/sh
# drupal-lint.sh - PostToolUse hook of the drupal-dev Claude Code plugin.
#
# After Claude writes or edits a file, run fast read-only checks on it:
#   *.php *.module *.inc *.install *.theme *.profile
#       php -l, then phpcs with the project's phpcs.xml(.dist) or, if there is
#       none, the Drupal and DrupalPractice standards from drupal/coder
#   *.twig
#       twig-cs-fixer with the project's .twig-cs-fixer(.dist).php or, if there
#       is none, a syntax-only check
#   *.yml *.yaml
#       Symfony's yaml-lint (installed with every Composer-built Drupal site)
#
# Tools are looked up in the nearest vendor/bin above the file. Anything that
# is missing is skipped silently. The hook never blocks the tool call and never
# writes files: findings go back to Claude as additionalContext and a one-line
# summary is shown to the user. It always exits 0.
#
# Environment:
#   DRUPAL_DEV_LINT=0        disable the hook
#   DRUPAL_DEV_LINT_MAX=40   maximum number of findings reported per tool

[ "${DRUPAL_DEV_LINT:-1}" = "0" ] && exit 0

input=$(cat 2>/dev/null) || exit 0

# Cheap filter on the raw JSON so unrelated edits never start PHP.
case $input in
  *'.php"'* | *'.module"'* | *'.inc"'* | *'.install"'* | *'.theme"'* | \
  *'.profile"'* | *'.twig"'* | *'.yml"'* | *'.yaml"'*) ;;
  *) exit 0 ;;
esac

PHP=$(command -v php 2>/dev/null) || exit 0
[ -n "$PHP" ] || exit 0

max=${DRUPAL_DEV_LINT_MAX:-40}
case $max in '' | *[!0-9]*) max=40 ;; esac

plugin_dir=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}

file=$(printf '%s' "$input" | "$PHP" -r '
  $d = json_decode((string) stream_get_contents(STDIN), TRUE);
  $p = is_array($d) ? ($d["tool_input"]["file_path"] ?? "") : "";
  echo is_string($p) ? $p : "";
' 2>/dev/null) || exit 0
[ -n "$file" ] || exit 0

# Windows paths arrive with backslashes; Git Bash and PHP accept C:/x/y too.
to_slashes() {
  case $1 in
    [A-Za-z]:\\*) printf '%s\n' "$1" | tr '\\' '/' ;;
    *) printf '%s\n' "$1" ;;
  esac
}
file=$(to_slashes "$file")
case $file in
  /* | [A-Za-z]:/*) ;;
  *) file="$PWD/$file" ;;
esac

case $file in
  */vendor/* | */node_modules/*) exit 0 ;;
esac
case $file in
  *.php | *.module | *.inc | *.install | *.theme | *.profile) kind=php ;;
  *.twig) kind=twig ;;
  *.yml | *.yaml) kind=yaml ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Print the nearest vendor/bin/$1 above the file.
find_bin() {
  _dir=$(dirname "$file")
  _depth=0
  while [ "$_depth" -lt 40 ]; do
    if [ -f "$_dir/vendor/bin/$1" ]; then
      printf '%s\n' "$_dir/vendor/bin/$1"
      return 0
    fi
    _parent=$(dirname "$_dir")
    [ "$_parent" = "$_dir" ] && return 1
    _dir=$_parent
    _depth=$((_depth + 1))
  done
  return 1
}

# Print the file path relative to directory $1 when it is inside it.
rel_to() {
  case $file in
    "$1"/*) printf '%s\n' "${file#"$1"/}" ;;
    *) printf '%s\n' "$file" ;;
  esac
}

# Turn GitHub-style "::error file=F,line=L,col=C::MSG" lines into
# "L:C: error: MSG" (line and column only when the tool reports them).
github_lines() {
  awk '
    /^::(error|warning) file=/ {
      rest = substr($0, 3)
      i = index(rest, "::")
      if (i == 0) next
      head = substr(rest, 1, i - 1)
      msg = substr(rest, i + 2)
      type = head; sub(/ .*/, "", type)
      pos = ""
      if (match(head, /,line=[0-9]+/)) {
        pos = substr(head, RSTART + 6, RLENGTH - 6)
        if (match(head, /,col=[0-9]+/) && substr(head, RSTART + 5, RLENGTH - 5) != "0") {
          pos = pos ":" substr(head, RSTART + 5, RLENGTH - 5)
        }
        pos = pos ": "
      }
      print pos type ": " msg
    }
  '
}

details=''
tools=''
total=0

# add_section NAME LABEL LINES: record the findings of one tool.
add_section() {
  _count=$(printf '%s\n' "$3" | grep -c .)
  [ "$_count" -gt 0 ] || return 0
  total=$((total + _count))
  details="$details$2:
$(printf '%s\n' "$3" | head -n "$max" | sed 's/^/  /')
"
  if [ "$_count" -gt "$max" ]; then
    details="$details  ... and $((_count - max)) more
"
  fi
  tools="$tools${tools:+, }$1 $_count"
}

# Paths in messages are relative to the project when possible.
display=$file
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  display=$(rel_to "$(to_slashes "$CLAUDE_PROJECT_DIR")")
fi

if [ "$kind" = php ]; then
  lint=$("$PHP" -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -l "$file" 2>&1)
  if [ $? -ne 0 ]; then
    lines=$(printf '%s\n' "$lint" | grep -i 'error' | grep -v '^Errors parsing' |
      sed -E 's/^PHP //; s/ in .* on line ([0-9]+)$/ on line \1/' | head -n 5)
    [ -n "$lines" ] || lines='syntax error (php -l failed)'
    add_section 'php -l' 'php -l' "$lines"
  elif phpcs=$(find_bin phpcs); then
    root=${phpcs%/vendor/bin/phpcs}
    rel=$(rel_to "$root")
    standard=''
    label=''
    if [ -f "$root/phpcs.xml" ] || [ -f "$root/phpcs.xml.dist" ] ||
      [ -f "$root/.phpcs.xml" ] || [ -f "$root/.phpcs.xml.dist" ]; then
      label='phpcs (project ruleset)'
    elif [ -d "$root/vendor/drupal/coder/coder_sniffer/Drupal" ]; then
      standard='--standard=Drupal,DrupalPractice'
      label='phpcs (Drupal, DrupalPractice)'
    fi
    if [ -n "$label" ]; then
      # $standard is intentionally unquoted: it is either empty or one word.
      # shellcheck disable=SC2086
      out=$(cd "$root" && "$PHP" "$phpcs" -q -s --no-cache --report=emacs \
        --extensions=php,module,inc,install,theme,profile,test,engine \
        $standard "$rel" 2>&1)
      lines=$(printf '%s\n' "$out" |
        sed -n -E 's/^.*:([0-9]+):([0-9]+): (error|warning) - (.*)$/\1:\2: \3: \4/p')
      add_section phpcs "$label" "$lines"
    fi
  fi
elif [ "$kind" = twig ]; then
  if tcf=$(find_bin twig-cs-fixer); then
    root=${tcf%/vendor/bin/twig-cs-fixer}
    rel=$(rel_to "$root")
    if [ -f "$root/.twig-cs-fixer.php" ] || [ -f "$root/.twig-cs-fixer.dist.php" ]; then
      out=$(cd "$root" && "$PHP" "$tcf" lint --no-cache --no-ansi --report=github "$rel" 2>&1)
      label='twig-cs-fixer (project rules)'
    else
      out=$(cd "$root" && "$PHP" "$tcf" lint --no-cache --no-ansi --report=github \
        -c "$plugin_dir/hooks/twig-syntax-only.php" "$rel" 2>&1)
      label='twig-cs-fixer (syntax only)'
    fi
    add_section twig-cs-fixer "$label" "$(printf '%s\n' "$out" | github_lines)"
  fi
elif [ "$kind" = yaml ]; then
  if yl=$(find_bin yaml-lint); then
    root=${yl%/vendor/bin/yaml-lint}
    rel=$(rel_to "$root")
    out=$(cd "$root" && "$PHP" "$yl" --parse-tags --format=github --no-ansi "$rel" 2>&1)
    add_section yaml-lint yaml-lint "$(printf '%s\n' "$out" | github_lines)"
  fi
fi

[ "$total" -gt 0 ] || exit 0

if [ "$total" -eq 1 ]; then noun=problem; them=it; else noun=problems; them=them; fi
{
  printf 'drupal-dev lint: %s %s in %s (%s)\n' "$total" "$noun" "$display" "$tools"
  printf 'drupal-dev lint found %s %s in %s after this edit. Fix %s unless the project deliberately ignores these rules.\n%s' \
    "$total" "$noun" "$display" "$them" "$details"
} | "$PHP" -r '
  $all = (string) stream_get_contents(STDIN);
  [$summary, $details] = explode("\n", $all, 2) + ["", ""];
  echo json_encode([
    "systemMessage" => $summary,
    "hookSpecificOutput" => [
      "hookEventName" => "PostToolUse",
      "additionalContext" => rtrim($details),
    ],
  ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE), "\n";
' 2>/dev/null

exit 0
