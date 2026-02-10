#!/usr/bin/env bash

set -euo pipefail

if [ -z "${CONTAINER_IMAGE-}" ] || [ -z "${CONTAINER_DIR-}" ]; then
  echo "container-build: CONTAINER_IMAGE と CONTAINER_DIR は必須です" >&2
  exit 1
fi

custom_build_script="${CONTAINER_DIR}/custom-build.sh"

if [ -x "${custom_build_script}" ]; then
  echo "container-build: カスタムビルドスクリプト実行 ${custom_build_script}" >&2
  exec "${custom_build_script}"
elif [ -f "${custom_build_script}" ]; then
  echo "container-build: custom-build.sh が実行不可です。実行権限を付与してください: ${custom_build_script}" >&2
  exit 1
else
  exec podman build -t "${CONTAINER_IMAGE}" "${CONTAINER_DIR}"
fi
