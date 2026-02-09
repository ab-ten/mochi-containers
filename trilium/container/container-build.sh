#!/usr/bin/env bash

set -euo pipefail

if [ -z "${CONTAINER_IMAGE-}" ] || [ -z "${CONTAINER_DIR-}" ]; then
  echo "container-build: CONTAINER_IMAGE と CONTAINER_DIR は必須です" >&2
  exit 1
fi

if [ -z "${TRILIUM_TZ-}" ]; then
  echo "container-build: TRILIUM_TZ は必須です" >&2
  exit 1
fi

podman build -t "${CONTAINER_IMAGE}" --build-arg TZ="${TRILIUM_TZ}" "${CONTAINER_DIR}"
