#!/usr/bin/env bash

set -euo pipefail

if [ -z "${INSTALL_ROOT-}" ]; then
  echo "replace-deploy-vars: 必須環境変数が未設定: INSTALL_ROOT" >&2
  exit 1
fi
SCRIPT_DIR="${INSTALL_ROOT%/}/scripts"
# shellcheck source=deploy-vars.subr
source "${SCRIPT_DIR}/deploy-vars.subr"

err() {
  echo "replace-deploy-vars: $*" >&2
  exit 1
}

usage() {
  echo "使い方: $0 <unit-file>" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
fi

target="$1"
if [ ! -f "${target}" ]; then
  err "対象ファイルが見つからない: ${target}"
fi

missing=()
deploy_vars_get_replacement_vars replacement_vars
deploy_vars_collect_missing replacement_vars missing

if [ "${#missing[@]}" -gt 0 ]; then
  err "未設定の環境変数: ${missing[*]}"
fi

sed_args=()
for var in "${replacement_vars[@]}"; do
  value="${!var}"
  sed_args+=("-e" "s|@@${var}@@|${value}|g")
done

#set -x
sed -i "${sed_args[@]}" "${target}"

if grep -nE '@@[A-Z0-9_]+@@' "${target}" >&2; then
  err "未置換のプレースホルダーが残っています: ${target}"
fi
