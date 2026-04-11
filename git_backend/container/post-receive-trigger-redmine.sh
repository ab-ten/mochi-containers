#!/usr/bin/env bash

set -euo pipefail

pending_dir="/var/git_triggers/pending"

if [ ! -w "${pending_dir}" ]; then
  exit 0
fi

repo_dir="$(pwd -P)"
repo_base="$(basename -- "${repo_dir}")"

case "${repo_base}" in
  *.git)
    repo_name="${repo_base%.git}"
    ;;
  *)
    exit 0
    ;;
esac

touch -- "${pending_dir}/${repo_name}" || exit 0
