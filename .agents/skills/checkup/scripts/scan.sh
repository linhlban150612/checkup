#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scan.sh [--mode full|config|code] [--stale-days N] [REPOSITORY]

Prints a read-only repository inventory to stdout. It does not run project
commands, inspect secret contents, or create files in the target repository.
EOF
}

mode=full
stale_days=180
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

printf '# Checkup inventory\n\n'
printf 'repository\t%q\n' "$root"
printf 'mode\t%s\n' "$mode"
printf 'stale_days\t%s\n' "$stale_days"
printf 'generated_at_epoch\t%s\n' "$(date +%s)"

printf '\n## Tools\n'
for tool in git rg grep find fd; do
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
  printf '\n## Tracked files\n'
  printf 'age_days\tlast_touch\tbytes\tpath\tflag\n'
  while IFS= read -r -d '' file; do
    if is_sensitive_path "$file"; then
      printf -- '-\t-\t-\t%q\texcluded-sensitive\n' "$file"
      continue
    fi
    touched_epoch=$(git -C "$root" log -1 --format=%ct -- "$file")
    touched_date=$(git -C "$root" log -1 --format=%cs -- "$file")
    if [[ -n $touched_epoch ]]; then
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
    flag=-
    if ((age_days >= stale_days && age_days >= 0)); then
      flag=stale-signal-only
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

if [[ $mode == full || $mode == config ]]; then
  printf '\n## Project-local agent configuration\n'
  config_paths=(
    AGENTS.md CLAUDE.md .agents .claude .codex .cursor
    .github/copilot-instructions.md .amp .factory .omp .opencode .pi .zcode
  )
  for path in "${config_paths[@]}"; do
    [[ -e $root/$path || -L $root/$path ]] || continue
    if [[ -d $root/$path ]]; then
      kib=$(du -sk "$root/$path" 2>/dev/null | awk '{print $1}')
      files=$(find "$root/$path" \
        \( -name .git -o -name node_modules -o -name .venv -o -name venv \
           -o -name browser-profile -o -name dist -o -name build -o -name coverage \) -prune \
        -o -type f -print 2>/dev/null | wc -l)
      printf 'directory\t%q\t%s KiB total including generated trees\t%s files excluding common generated trees\n' "$path" "$kib" "$files"
    else
      bytes=$(wc -c < "$root/$path" 2>/dev/null || printf '?')
      printf 'file\t%q\t%s bytes\n' "$path" "$bytes"
    fi
  done

  printf '\n## Skill entrypoints\n'
  for base in .agents/skills .claude/skills .cursor/skills .codex/skills; do
    [[ -d $root/$base ]] || continue
    while IFS= read -r -d '' dir; do
      rel=${dir#"$root/"}
      if [[ -f $dir/SKILL.md ]]; then
        printf 'entrypoint-present\t%q\n' "$rel/SKILL.md"
      else
        printf 'missing-root-SKILL.md\t%q\n' "$rel"
      fi
    done < <(find "$root/$base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  done
fi

printf '\n## Interpretation guardrails\n'
printf '%s\n' \
  'stale-signal-only is not evidence that a file is unused' \
  'ignored or untracked paths are not deletion candidates by default' \
  'entrypoint-present checks file presence only; it does not validate SKILL.md frontmatter' \
  'A missing root SKILL.md may identify a source checkout or skill container rather than a broken skill' \
  'run references.sh for each plausible tracked-file candidate' \
  'obtain explicit approval before any write or deletion'
