#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/sensitive.sh
. "$script_dir/lib/sensitive.sh"

usage() {
  cat <<'EOF'
Usage: references.sh [--repo REPOSITORY] [--symbol NAME ...] TRACKED_FILE

Prints repository-local reference evidence without printing matched content.
The target must be a non-sensitive, Git-tracked, repository-relative file.
EOF
}

repo=.
target=
symbols=()

while (($#)); do
  case "$1" in
    --repo)
      (($# >= 2)) || { usage >&2; exit 2; }
      repo=$2
      shift 2
      ;;
    --symbol)
      (($# >= 2)) || { usage >&2; exit 2; }
      symbols+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z $target ]] || { usage >&2; exit 2; }
      target=$1
      shift
      ;;
  esac
done

[[ -n $target ]] || { usage >&2; exit 2; }
[[ $target != /* && $target != .. && $target != ../* && $target != */../* && $target != */.. ]] || {
  printf 'TRACKED_FILE must be repository-relative and may not contain ..\n' >&2
  exit 2
}

command -v git >/dev/null 2>&1 || { printf 'git is required\n' >&2; exit 1; }
root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
  printf 'Not a Git repository: %s\n' "$repo" >&2
  exit 1
}

if is_sensitive_path "$target"; then
  printf 'Refusing to inspect a potentially sensitive path: %s\n' "$target" >&2
  exit 2
fi

git -C "$root" ls-files --error-unmatch -- "$target" >/dev/null 2>&1 || {
  printf 'Target is not a tracked file: %s\n' "$target" >&2
  exit 2
}

search_pathspecs=(. ":(exclude)$target")
excluded_sensitive_files=0
while IFS= read -r -d '' file; do
  if is_sensitive_path "$file"; then
    search_pathspecs+=(":(exclude)$file")
    ((excluded_sensitive_files += 1))
  fi
done < <(git -C "$root" ls-files -z)

print_matches() {
  local kind=$1
  local needle=$2
  local word=${3:-false}
  local -a args=(-I -l)
  local -a matches=()
  if [[ $word == true ]]; then
    args+=(-w)
  else
    args+=(-F)
  fi
  while IFS= read -r match; do
    matches+=("$match")
  done < <(
    git -C "$root" grep "${args[@]}" -e "$needle" -- "${search_pathspecs[@]}" 2>/dev/null || true
  )
  printf '\n%s\t%q\t%d matching files\n' "$kind" "$needle" "${#matches[@]}"
  if ((${#matches[@]})); then
    printf '  %q\n' "${matches[@]}"
  fi
}

relative_path() {
  local from_dir=$1
  local to=$2
  local result='' part
  local from_count to_count common index
  local -a from_parts=()
  local -a to_parts=()

  if [[ $from_dir != . ]]; then
    IFS=/ read -r -a from_parts <<< "$from_dir"
  fi
  IFS=/ read -r -a to_parts <<< "$to"
  from_count=${#from_parts[@]}
  to_count=${#to_parts[@]}
  common=0
  while ((common < from_count && common < to_count)); do
    [[ ${from_parts[$common]} == "${to_parts[$common]}" ]] || break
    ((common += 1))
  done
  for ((index = common; index < from_count; index += 1)); do
    result=${result}../
  done
  for ((index = common; index < to_count; index += 1)); do
    part=${to_parts[$index]}
    if [[ -n $result && $result != */ ]]; then
      result=$result/
    fi
    result=$result$part
  done
  printf '%s' "$result"
}

print_path_suffixes() {
  local suffix part
  local count start index
  local -a parts=()
  IFS=/ read -r -a parts <<< "$target"
  count=${#parts[@]}
  for ((start = count - 2; start >= 0; start -= 1)); do
    suffix=
    for ((index = start; index < count; index += 1)); do
      part=${parts[$index]}
      if [[ -n $suffix ]]; then
        suffix=$suffix/
      fi
      suffix=$suffix$part
    done
    print_matches path-suffix "$suffix"
  done
}

print_relative_matches() {
  local candidate candidate_dir relative
  local -a matches=()
  while IFS= read -r candidate; do
    if [[ $candidate == */* ]]; then
      candidate_dir=${candidate%/*}
    else
      candidate_dir=.
    fi
    relative=$(relative_path "$candidate_dir" "$target")
    if git -C "$root" grep -F -l -e "$relative" -- "$candidate" >/dev/null 2>&1; then
      matches+=("$candidate")
    fi
  done < <(
    git -C "$root" grep -F -I -l -e "$basename" -- "${search_pathspecs[@]}" 2>/dev/null || true
  )
  printf '\nrelative-path\t%q\t%d matching files\n' "$target" "${#matches[@]}"
  if ((${#matches[@]})); then
    printf '  %q\n' "${matches[@]}"
  fi
}

basename=${target##*/}
stem=${basename%.*}
shallow=$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null || printf false)
last_touch=$(git -C "$root" log -1 --format=%cs -- "$target")
commit_count=$(git -C "$root" rev-list --count HEAD -- "$target")
mode=$(git -C "$root" ls-files -s -- "$target" | awk 'NR == 1 {print $1}')

printf '# Reference evidence\n\n'
printf 'repository\t%q\n' "$root"
printf 'target\t%q\n' "$target"
if [[ $shallow == true ]]; then
  printf 'history\tshallow\n'
  printf 'last_touch\t%s (shallow)\n' "${last_touch:--}"
  printf 'commits_touching_path\t%s (shallow history; incomplete)\n' "$commit_count"
else
  printf 'history\tcomplete\n'
  printf 'last_touch\t%s\n' "${last_touch:--}"
  printf 'commits_touching_path\t%s\n' "$commit_count"
fi
printf 'git_mode\t%s\n' "${mode:--}"
printf 'excluded_sensitive_files\t%s\n' "$excluded_sensitive_files"
if [[ -x $root/$target ]]; then
  printf 'working_tree_executable\tyes\n'
else
  printf 'working_tree_executable\tno\n'
fi

print_matches exact-path "$target"
print_path_suffixes
print_relative_matches
print_matches basename "$basename"
if [[ $stem != "$basename" ]]; then
  print_matches filename-stem "$stem"
fi
for symbol in ${symbols[@]+"${symbols[@]}"}; do
  [[ $symbol =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
    printf '\ninvalid-symbol\t%q\tskipped\n' "$symbol"
    continue
  }
  print_matches symbol "$symbol" true
done

printf '\n## Interpretation guardrails\n'
printf '%s\n' \
  'Matches exclude the target file and never print matched source content.' \
  'Potentially sensitive tracked files are excluded from every content search.' \
  'Shallow history is incomplete; its dates and commit counts are not reliable evidence.' \
  'Path-suffix and relative-path matches may overlap other match categories.' \
  'Basename and filename-stem matches may be incidental, especially for short or common names.' \
  'No textual matches does not prove the target is unused.' \
  'Check entrypoints, manifests, CI, docs, reflection, conventions, generated use, and external consumers.'
