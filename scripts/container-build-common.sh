#!/usr/bin/env bash

set -euo pipefail

if [ -z "${CONTAINER_IMAGE-}" ] || [ -z "${CONTAINER_DIR-}" ]; then
  echo "container-build-common: CONTAINER_IMAGE と CONTAINER_DIR は必須です" >&2
  exit 1
fi

podman build -t "${CONTAINER_IMAGE}" "${CONTAINER_DIR}"
