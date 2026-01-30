#!/usr/bin/env bash

set -euo pipefail

REPLACEMENT_VARS=(
  ROOT_UNIT_PREFIX
  SERVICE_PATH
  INSTALL_ROOT
  CERT_DOMAIN
  MAP_LOCAL_ADDRESS
  NFS_ROOT
  ${REPLACE_ADD_VAR:-}
)

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
for var in "${REPLACEMENT_VARS[@]}"; do
  if [ -z "${!var-}" ]; then
    missing+=("${var}")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  err "未設定の環境変数: ${missing[*]}"
fi

sed_args=()
for var in "${REPLACEMENT_VARS[@]}"; do
  value="${!var}"
  sed_args+=("-e" "s|@@${var}@@|${value}|g")
done

#set -x
sed -i "${sed_args[@]}" "${target}"
