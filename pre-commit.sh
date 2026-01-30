#!/usr/bin/env bash
set -euo pipefail

if git rev-parse --verify HEAD >/dev/null 2>&1
then
  against=HEAD
else
  # Initial commit: diff against an empty tree object
  against=$(git hash-object -t tree /dev/null)
fi

# Redirect output to stderr.
exec 1>&2


repo_root="$(git rev-parse --show-toplevel)"
checker="$repo_root/denycheck.awk"

# checker がなかったら正常終了
if [ ! -f "$checker" ]; then
  echo "no checker file, skipped."
  exit 0
fi

# stagedファイル（スペース対応のため -z でNUL区切り）
mapfile -d '' staged_files < <(git diff --cached --name-only --diff-filter=ACMRT -z)


is_binary_in_index() {
  local f="$1"
  local first
  first="$(git diff --cached --numstat -- "$f" | head -n 1 | awk '{print $1}' || true)"
  [[ "$first" == "-" ]]
}

failed=0

for f in "${staged_files[@]}"; do
  if [[ "$f" == "denycheck.awk" ]]; then
    continue
  fi

  git cat-file -e ":$f" 2>/dev/null || continue
  is_binary_in_index "$f" && continue

  if ! git show ":$f" | awk -v path="$f" -f "$checker"; then
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "✗ pre-commit: 禁止パターンが見つかりました。コミットを中断します。" 1>&2
  exit 1
fi

exit 0
