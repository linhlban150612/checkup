#!/usr/bin/env bash
set -euo pipefail

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

is_sensitive_path() {
  case "/$1/" in
    */.env/*|*/.env.*/*|*/credentials/*|*/credential/*|*/secrets/*|*/secret/*|*/keys/*|*/cookies/*|*/cookie/*|*/sessions/*|*/session/*|*/browser-profile/*|*/auth/*)
      return 0
      ;;
  esac
  case "${1##*/}" in
    .env|.env.*|*credential*|*secret*|*cookie*|*session*|*.pem|*.key|id_rsa|id_ed25519)
      return 0
      ;;
  esac
  return 1
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
  mapfile -t matches < <(
    git -C "$root" grep "${args[@]}" -e "$needle" -- "${search_pathspecs[@]}" 2>/dev/null || true
  )
  printf '\n%s\t%q\t%d matching files\n' "$kind" "$needle" "${#matches[@]}"
  if ((${#matches[@]})); then
    printf '  %q\n' "${matches[@]}"
  fi
}

basename=${target##*/}
stem=${basename%.*}
last_touch=$(git -C "$root" log -1 --format=%cs -- "$target")
commit_count=$(git -C "$root" rev-list --count HEAD -- "$target")
mode=$(git -C "$root" ls-files -s -- "$target" | awk 'NR == 1 {print $1}')

printf '# Reference evidence\n\n'
printf 'repository\t%q\n' "$root"
printf 'target\t%q\n' "$target"
printf 'last_touch\t%s\n' "${last_touch:--}"
printf 'commits_touching_path\t%s\n' "$commit_count"
printf 'git_mode\t%s\n' "${mode:--}"
printf 'excluded_sensitive_files\t%s\n' "$excluded_sensitive_files"
if [[ -x $root/$target ]]; then
  printf 'working_tree_executable\tyes\n'
else
  printf 'working_tree_executable\tno\n'
fi

print_matches exact-path "$target"
print_matches basename "$basename"
if [[ $stem != "$basename" ]]; then
  print_matches filename-stem "$stem"
fi
for symbol in "${symbols[@]}"; do
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
  'Basename and filename-stem matches may be incidental, especially for short or common names.' \
  'No textual matches does not prove the target is unused.' \
  'Check entrypoints, manifests, CI, docs, reflection, conventions, generated use, and external consumers.'
