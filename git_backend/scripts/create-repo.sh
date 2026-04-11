#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [-n] [-i] <name.git>" >&2
}

validate_only=0
install_hook_only=0
hook_target="/usr/local/bin/post-receive-trigger-redmine.sh"

install_hook() {
  local hook_path="$1"
  local current_target=""
  local hook_dir=""

  hook_dir="$(dirname -- "${hook_path}")"
  if [ ! -d "${hook_dir}" ]; then
    echo "create-repo: hooks ディレクトリが存在しません: ${hook_dir}" >&2
    exit 1
  fi

  if [ -L "${hook_path}" ]; then
    current_target="$(readlink -- "${hook_path}")"
    if [ "${current_target}" = "${hook_target}" ]; then
      echo "(hook already installed.)"
      return 0
    fi
    echo "create-repo: 既存の post-receive hook が別のリンク先を指しています: ${hook_path} -> ${current_target}" >&2
    exit 1
  fi

  if [ -e "${hook_path}" ]; then
    echo "create-repo: 既存の post-receive hook があるため上書きしません: ${hook_path}" >&2
    exit 1
  fi

  ln -s "${hook_target}" "${hook_path}"
  echo "hook installed: ${hook_path}"
}

while getopts ":ni" opt; do
  case "${opt}" in
    n)
      validate_only=1
      ;;
    i)
      install_hook_only=1
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
post_receive_hook="${repo_path}/hooks/post-receive"

umask 027

if [ -e "${repo_path}" ]; then
  if [ "${install_hook_only}" -eq 1 ]; then
    install_hook "${post_receive_hook}"
    echo "repository url: https://git.${CERT_DOMAIN}/${name}"
    exit 0
  fi
  echo "create-repo: 既に存在します: ${repo_path}" >&2
  exit 1
fi

git init --bare "${repo_path}"
install_hook "${post_receive_hook}"
#git -C "${repo_path}" update-server-info

echo "created: ${repo_path}"
echo "repository url: https://git.${CERT_DOMAIN}/${name}"
