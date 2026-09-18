#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/sensitive.sh
. "$script_dir/lib/sensitive.sh"

usage() {
  cat <<'EOF'
Usage: scan.sh [--mode full|config|code] [--stale-days N] [--with-usage] [REPOSITORY]

Prints a read-only repository inventory to stdout. It does not run project
commands, inspect secret contents, or create files in the target repository.
--with-usage reads only skillUsage and pluginUsage counters from ~/.claude.json
and requires explicit user consent. It is valid only in config and full modes.
EOF
}

mode=full
stale_days=180
with_usage=false
repo=.

while (($#)); do
  case "$1" in
    --mode)
      (($# >= 2)) || { usage >&2; exit 2; }
      mode=$2
      shift 2
      ;;
    --stale-days)
      (($# >= 2)) || { usage >&2; exit 2; }
      stale_days=$2
      shift 2
      ;;
    --with-usage)
      with_usage=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      (($# <= 1)) || { usage >&2; exit 2; }
      repo=${1:-.}
      break
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      repo=$1
      shift
      (($# == 0)) || { usage >&2; exit 2; }
      ;;
  esac
done

case "$mode" in
  full|config|code) ;;
  *) printf 'Invalid mode: %s\n' "$mode" >&2; exit 2 ;;
esac
if [[ $with_usage == true && $mode == code ]]; then
  printf '%s\n' '--with-usage is valid only with --mode config or --mode full' >&2
  exit 2
fi
[[ $stale_days =~ ^[0-9]+$ ]] || {
  printf 'stale-days must be a non-negative integer\n' >&2
  exit 2
}

command -v git >/dev/null 2>&1 || {
  printf 'git is required\n' >&2
  exit 1
}
root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
  printf 'Not a Git repository: %s\n' "$repo" >&2
  exit 1
}
shallow=$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null || printf false)
if [[ $shallow == true ]]; then
  history_label=shallow
else
  history_label=complete
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/checkup-scan.XXXXXX") || {
  printf 'Unable to create temporary workspace\n' >&2
  exit 1
}
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
: > "$tmp_dir/skill-names"
: > "$tmp_dir/plugin-names"
: > "$tmp_dir/skill-listing-chars"

printf '# Checkup inventory\n\n'
printf 'repository\t%q\n' "$root"
printf 'mode\t%s\n' "$mode"
printf 'stale_days\t%s\n' "$stale_days"
printf 'history\t%s\n' "$history_label"
printf 'generated_at_epoch\t%s\n' "$(date +%s)"

printf '\n## Tools\n'
for tool in git rg grep find fd jq; do
  if path=$(command -v "$tool" 2>/dev/null); then
    printf '%s\tavailable\t%q\n' "$tool" "$path"
  else
    printf '%s\tunavailable\n' "$tool"
  fi
done

printf '\n## Worktree baseline\n'
git -C "$root" status --short --branch

if [[ $mode == full || $mode == code ]]; then
  now=$(date +%s)
  history_raw=$tmp_dir/history-raw.tsv
  history_first=$tmp_dir/history-first.tsv
  : > "$history_raw"
  history_epoch=
  history_date=
  expect_header=false
  while IFS= read -r -d '' item; do
    if [[ -z $item ]]; then
      expect_header=true
      continue
    fi
    if [[ $expect_header == true ]]; then
      history_epoch=${item%% *}
      history_date=${item#* }
      expect_header=false
      continue
    fi
    item=${item#$'\n'}
    printf '%s\t%s\t%s\n' "$item" "$history_epoch" "$history_date" >> "$history_raw"
  done < <(git -C "$root" log --format='%x00%ct %cs' --name-only -z HEAD)
  awk -F '\t' '!seen[$1]++ { print }' "$history_raw" > "$history_first"

  printf '\n## Tracked files\n'
  printf 'age_days\tlast_touch\tbytes\tpath\tflag\n'
  while IFS= read -r -d '' file; do
    if is_sensitive_path "$file"; then
      printf -- '-\t-\t-\t%q\texcluded-sensitive\n' "$file"
      continue
    fi
    history=$(awk -F '\t' -v target="$file" '$1 == target { print $2 "\t" $3; exit }' "$history_first")
    touched_epoch=${history%%$'\t'*}
    touched_date=${history#*$'\t'}
    if [[ -n $history && -n $touched_epoch ]]; then
      age_days=$(( (now - touched_epoch) / 86400 ))
    else
      age_days=-1
      touched_date=-
    fi
    if [[ -f $root/$file ]]; then
      bytes=$(wc -c < "$root/$file")
    else
      bytes=-
    fi
    if [[ $shallow == true ]]; then
      flag=age-unreliable
    else
      flag=-
      if ((age_days >= stale_days && age_days >= 0)); then
        flag=stale-signal-only
      fi
    fi
    printf '%s\t%s\t%s\t%q\t%s\n' "$age_days" "$touched_date" "$bytes" "$file" "$flag"
  done < <(git -C "$root" ls-files -z)

  printf '\n## Tracked manifests and automation\n'
  while IFS= read -r -d '' file; do
    case "$file" in
      package.json|*/package.json|pyproject.toml|*/pyproject.toml|Cargo.toml|*/Cargo.toml|go.mod|*/go.mod|Makefile|*/Makefile|justfile|*/justfile|.github/workflows/*|Dockerfile|*/Dockerfile|docker-compose.*|*/docker-compose.*)
        printf '%q\n' "$file"
        ;;
    esac
  done < <(git -C "$root" ls-files -z)
fi

print_inventory_path() {
  local path=$1
  local kib files bytes
  [[ -e $root/$path || -L $root/$path ]] || return 0
  if [[ -d $root/$path ]]; then
    kib=$(du -sk "$root/$path" 2>/dev/null | awk '{print $1}')
    files=$(find "$root/$path" \
      \( -path "$root/.claude/worktrees" -o -name .git -o -name node_modules -o -name .venv -o -name venv \
         -o -name browser-profile -o -name dist -o -name build -o -name coverage \) -prune \
      -o -type f -print 2>/dev/null | wc -l)
    printf 'directory\t%q\t%s KiB total including generated trees\t%s files excluding common generated trees\n' "$path" "$kib" "$files"
  else
    bytes=$(wc -c < "$root/$path" 2>/dev/null || printf '?')
    printf 'file\t%q\t%s bytes\n' "$path" "$bytes"
  fi
}

inspect_json() {
  local path=$1
  local error position record
  [[ -f $root/$path ]] || return 0
  if ! error=$(jq empty "$root/$path" 2>&1); then
    position=$(printf '%s\n' "$error" | sed -n 's/.* at line \([0-9][0-9]*\), column \([0-9][0-9]*\).*/line \1, column \2/p' | head -1)
    printf 'json-invalid\t%q\t%s\n' "$path" "${position:-position unavailable}"
    return 0
  fi
  printf 'json-valid\t%q\n' "$path"
  jq -c '(.mcpServers // {}) | if type == "object" then keys[]? else empty end' "$root/$path" | while IFS= read -r record; do
    printf 'mcp-server\t%q\t%q\n' "$path" "$record"
  done
  jq -r '
    (.hooks // {}) | if type == "object" then . else {} end | to_entries[]? | . as $entry |
    [$entry.key|tojson,
      ($entry.value | if type == "array" then [.[] | (.hooks? // []) | length] | add // 0 else 0 end)] |
    @tsv
  ' "$root/$path" | while IFS=$'\t' read -r event count; do
    printf 'hook-event\t%q\t%q\t%s hooks\n' "$path" "$event" "$count"
  done
  jq -c '(.enabledPlugins // {}) | if type == "object" then keys[]? else empty end' "$root/$path" | while IFS= read -r record; do
    printf 'enabled-plugin\t%q\t%q\n' "$path" "$record"
  done
  jq -c '(.enabledPlugins // {}) | if type == "object" then keys[]? else empty end' "$root/$path" >> "$tmp_dir/plugin-names"
  jq -c '(.permissions // {}) | if type == "object" then keys[]? else empty end' "$root/$path" | while IFS= read -r record; do
    printf 'permission-key\t%q\t%q\n' "$path" "$record"
  done
  jq -r '
    def pinned_package:
      type == "string" and
      (test("(^|=)(@[^/]+/)?[^@=]+@v?[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$") or
       test("(^|=)[A-Za-z0-9_.-]+==[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$"));
    (.mcpServers // {}) | if type == "object" then . else {} end | to_entries[]? | . as $entry |
    ($entry.value | if type == "object" then . else {} end) as $server |
    select(
      (($server.command // "") | split("/")[-1]) as $command |
      ($command == "npx" or $command == "uvx" or $command == "bunx") and
      (any(($server.args // []) | if type == "array" then .[] else empty end; pinned_package) | not)
    ) | [$entry.key|tojson, "runs-mutable-remote-package"] | @tsv
  ' "$root/$path" | while IFS=$'\t' read -r server risk; do
    printf 'mcp-risk\t%q\t%q\t%s\n' "$path" "$server" "$risk"
  done
}

inspect_skill() {
  local skill_file=$1
  local skill_dir expected result name_status desc_status desc_validation name_chars desc_chars resource
  skill_dir=${skill_file%/SKILL.md}
  expected=${skill_dir##*/}
  result=$(awk -v expected="$expected" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function scalar(value, quote) {
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
        quote = substr(value, 1, 1)
        if (substr(value, length(value), 1) != quote) uncertain = 1
        return substr(value, 2, length(value) - 2)
      }
      if (value ~ /^["\047]/ || value ~ /["\047]$/) uncertain = 1
      return value
    }
    NR == 1 {
      if ($0 != "---") { print "frontmatter-unparsed\t0\t0"; exit }
      front = 1
      next
    }
    front {
      if ($0 == "---") {
        closed = 1
        front = 0
        next
      }
      if (block && $0 ~ /^[[:space:]]+/) {
        value = $0
        sub(/^[[:space:]]+/, "", value)
        if (block == ">") description = description (description == "" ? "" : " ") value
        else description = description (description == "" ? "" : "\n") value
        next
      }
      block = ""
      if ($0 ~ /^name:[[:space:]]*/) {
        value = $0
        sub(/^name:[[:space:]]*/, "", value)
        name = scalar(value)
      } else if ($0 ~ /^description:[[:space:]]*/) {
        value = $0
        sub(/^description:[[:space:]]*/, "", value)
        value = trim(value)
        if (value == ">" || value == "|" || value ~ /^[>|][-+]$/) block = substr(value, 1, 1)
        else description = scalar(value)
      }
      next
    }
    END {
      if (!closed || uncertain) { print "frontmatter-unparsed\t0\t0"; exit }
      if (name == "") name_status = "name-missing"
      else if (name != expected || length(name) > 64 || name !~ /^[a-z0-9]+(-[a-z0-9]+)*$/) name_status = "name-mismatch"
      else name_status = "name-ok"
      if (description == "") {
        desc_status = "desc-missing"
        desc_validation = "desc-ok"
      } else {
        desc_status = "desc-chars=" length(description)
        desc_validation = length(description) > 1024 ? "desc-too-long" : "desc-ok"
      }
      print name_status "\t" desc_status "\t" desc_validation "\t" length(name) "\t" length(description)
    }
  ' "$root/$skill_file")
  IFS=$'\t' read -r name_status desc_status desc_validation name_chars desc_chars <<EOF
$result
EOF
  if [[ $name_status == frontmatter-unparsed ]]; then
    printf 'skill\t%q\tfrontmatter-unparsed\n' "$skill_file"
  else
    printf 'skill\t%q\t%s\t%s' "$skill_file" "$name_status" "$desc_status"
    if [[ $desc_validation != desc-ok ]]; then
      printf '\t%s' "$desc_validation"
    fi
    printf '\n'
    if [[ $name_status == name-ok ]]; then
      printf '%s\n' "$expected" >> "$tmp_dir/skill-names"
    fi
    printf '%s\n' "$((name_chars + desc_chars))" >> "$tmp_dir/skill-listing-chars"
  fi
  while IFS= read -r resource; do
    case "$resource" in
      *..*) continue ;;
    esac
    if [[ ! -e $root/$skill_dir/$resource ]]; then
      printf 'missing-referenced-resource\t%q\t%q\n' "$skill_file" "$resource"
    fi
  done < <(
    LC_ALL=C grep -Eo '(scripts|references)/[A-Za-z0-9._/-]*[A-Za-z0-9_/-]' "$root/$skill_file" 2>/dev/null |
      sort -u || true
  )
}

if [[ $mode == full || $mode == config ]]; then
  printf '\n## Project-local agent configuration\n'
  config_paths=(
    AGENTS.md CLAUDE.md CLAUDE.local.md GEMINI.md .cursorrules .windsurfrules
    .agents .claude .codex .cursor .amp .factory .omp .opencode .pi .zcode
    .mcp.json .github/instructions .github/copilot-instructions.md .vscode/mcp.json
    .claude/rules .claude/agents .claude/commands
  )
  for path in "${config_paths[@]}"; do
    print_inventory_path "$path"
  done
  {
    git -C "$root" ls-files
    git -C "$root" ls-files --others --exclude-standard
  } | while IFS= read -r path; do
    case "$path" in
      */AGENTS.md|*/CLAUDE.md) printf 'nested-instruction\t%q\n' "$path" ;;
    esac
  done

  printf '\n## JSON configuration checks\n'
  if command -v jq >/dev/null 2>&1; then
    for path in .mcp.json .vscode/mcp.json .claude/settings.json .claude/settings.local.json; do
      inspect_json "$path"
    done
  else
    printf 'jq unavailable, JSON checks skipped\n'
  fi

  printf '\n## Skill entrypoints and frontmatter\n'
  for base in .agents/skills .claude/skills .cursor/skills .codex/skills; do
    [[ -d $root/$base ]] || continue
    while IFS= read -r -d '' dir; do
      rel=${dir#"$root/"}
      if [[ -f $dir/SKILL.md ]]; then
        inspect_skill "$rel/SKILL.md"
      else
        printf 'missing-root-SKILL.md\t%q\n' "$rel"
      fi
    done < <(find "$root/$base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  done

  printf '\n## Always-loaded instruction size (est.)\n'
  printf 'path\tbytes\test_tokens (est. chars/4)\n'
  {
    git -C "$root" ls-files
    git -C "$root" ls-files --others --exclude-standard
  } | while IFS= read -r path; do
    case "$path" in
      CLAUDE.md|*/CLAUDE.md|CLAUDE.local.md|*/CLAUDE.local.md|AGENTS.md|*/AGENTS.md|GEMINI.md|*/GEMINI.md|.github/copilot-instructions.md)
        is_sensitive_path "$path" && continue
        [[ -f $root/$path ]] || continue
        bytes=$(wc -c < "$root/$path")
        chars=$(wc -m < "$root/$path")
        printf '%q\t%s\t%s est.\n' "$path" "$bytes" "$(( (chars + 3) / 4 ))"
        ;;
    esac
  done
  skill_listing_chars=$(awk '{ total += $1 } END { print total + 0 }' "$tmp_dir/skill-listing-chars")
  printf 'skill_listing_est_tokens\t%s est.\tfrom %s chars of project-local skill names + descriptions\n' "$(( (skill_listing_chars + 3) / 4 ))" "$skill_listing_chars"

  if [[ $with_usage == true ]]; then
    printf '\n## Claude Code usage counters (opt-in)\n'
    if ! command -v jq >/dev/null 2>&1; then
      printf 'usage\tunavailable (jq missing)\n'
    elif [[ ! -f ${HOME:-}/.claude.json ]]; then
      printf 'usage\tunavailable (~/.claude.json missing)\n'
    elif ! jq empty "${HOME}/.claude.json" >/dev/null 2>&1; then
      printf 'usage\tunavailable (~/.claude.json invalid)\n'
    else
      skill_names=$(sort -u "$tmp_dir/skill-names" | jq -Rn '[inputs]')
      plugin_names=$(sort -u "$tmp_dir/plugin-names" | jq -sc 'unique')
      jq -r --argjson allowed "$skill_names" '
        (.skillUsage // {}) | if type == "object" then . else {} end | to_entries[] | . as $entry |
        select($allowed | index($entry.key)) |
        [$entry.key|tojson,
          ($entry.value | if type == "object" and (.usageCount | type) == "number" then .usageCount else 0 end),
          ($entry.value | if type == "object" and (.lastUsedAt | type) == "string" then .lastUsedAt else "-" end)] |
        @tsv
      ' "${HOME}/.claude.json" | while IFS=$'\t' read -r name count last_used; do
        printf 'skill-usage\t%q\t%s\t%s\n' "$name" "$count" "$last_used"
      done
      jq -r --argjson allowed "$plugin_names" '
        (.pluginUsage // {}) | if type == "object" then . else {} end | to_entries[] | . as $entry |
        select($allowed | index($entry.key)) |
        [$entry.key|tojson,
          ($entry.value | if type == "object" and (.usageCount | type) == "number" then .usageCount else 0 end),
          ($entry.value | if type == "object" and (.lastUsedAt | type) == "string" then .lastUsedAt else "-" end)] |
        @tsv
      ' "${HOME}/.claude.json" | while IFS=$'\t' read -r name count last_used; do
        printf 'plugin-usage\t%q\t%s\t%s\n' "$name" "$count" "$last_used"
      done
      printf 'usage-source\tClaude Code cumulative counters; no time-window guarantee\n'
    fi
  fi
fi

printf '\n## Interpretation guardrails\n'
printf '%s\n' \
  'stale-signal-only is not evidence that a file is unused' \
  'age-unreliable means shallow history and must not be used as age evidence' \
  'Git last-touch follows the current path and does not follow renames' \
  'ignored or untracked paths are not deletion candidates by default' \
  'frontmatter-unparsed is uncertainty, not proof of an invalid skill' \
  'token counts are estimates; measure exact context with /context in Claude Code' \
  'MCP tool schemas may be deferred and are not estimated here' \
  'run references.sh for each plausible tracked-file candidate' \
  'obtain explicit approval before any write or deletion'
