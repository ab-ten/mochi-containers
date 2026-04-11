#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [-n] <name.git>" >&2
}

validate_only=0
while getopts ":n" opt; do
  case "${opt}" in
    n)
      validate_only=1
      ;;
    :)
      usage
      exit 1
      ;;
    \?)
      usage
      exit 1
      ;;
  esac
done
shift "$((OPTIND - 1))"

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

name="$1"
if ! [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.git$ ]]; then
  echo "create-repo: リポジトリ名は ^[A-Za-z0-9][A-Za-z0-9._-]*\\.git$ に一致させてください: ${name}" >&2
  exit 1
fi

if [ "${validate_only}" -eq 1 ]; then
  echo "repository name check OK"
  exit 0
fi

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
echo "repository url: https://git.${CERT_DOMAIN}/${name}"
