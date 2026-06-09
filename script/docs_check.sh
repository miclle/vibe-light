#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Git whitespace check"
git diff --check

echo "==> Untracked file whitespace check"
untracked_files=()
while IFS= read -r -d '' file; do
  untracked_files+=("$file")
done < <(git ls-files --others --exclude-standard -z)
if [[ "${#untracked_files[@]}" -gt 0 ]]; then
  index_path="$(git rev-parse --git-path index)"
  temp_index="$(mktemp)"
  trap 'rm -f "$temp_index"' EXIT

  if [[ -f "$index_path" ]]; then
    cp "$index_path" "$temp_index"
  else
    : >"$temp_index"
  fi

  GIT_INDEX_FILE="$temp_index" git add -N -- "${untracked_files[@]}"
  GIT_INDEX_FILE="$temp_index" git diff --check -- "${untracked_files[@]}"
else
  echo "No untracked files."
fi

echo "==> Agent compatibility link"
if [[ ! -L CLAUDE.md ]]; then
  echo "CLAUDE.md must remain a symlink to AGENTS.md" >&2
  exit 1
fi

CLAUDE_TARGET="$(readlink CLAUDE.md)"
if [[ "$CLAUDE_TARGET" != "AGENTS.md" ]]; then
  echo "CLAUDE.md points to $CLAUDE_TARGET, expected AGENTS.md" >&2
  exit 1
fi

echo "==> AGENTS.md referenced local files"
missing=0
while IFS= read -r ref; do
  path="${ref#@}"
  if [[ ! -e "$path" ]]; then
    echo "Missing referenced file: $path" >&2
    missing=1
  fi
done < <(grep -Eo '@[A-Za-z0-9._/-]+' AGENTS.md | sort -u)

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "Docs checks passed."
