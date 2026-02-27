#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <name.git>" >&2
  exit 1
fi

name="$1"
case "${name}" in
  *.git) ;;
  *)
    echo "create-repo: 末尾 .git のリポジトリ名を指定してください: ${name}" >&2
    exit 1
    ;;
esac

case "${name}" in
  *..*|*/*)
    echo "create-repo: 無効なリポジトリ名です: ${name}" >&2
    exit 1
    ;;
esac

if [ -z "${NFS_ROOT-}" ]; then
  echo "create-repo: NFS_ROOT が未設定です" >&2
  exit 1
fi

repo_root="${NFS_ROOT%/}/git_backend/repos"
repo_path="${repo_root}/${name}"

umask 027

if [ -e "${repo_path}" ]; then
  echo "create-repo: 既に存在します: ${repo_path}" >&2
  exit 1
fi

git init --bare "${repo_path}"
#git -C "${repo_path}" update-server-info

echo "created: ${repo_path}"
