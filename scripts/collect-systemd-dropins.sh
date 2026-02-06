#!/usr/bin/env bash

set -euo pipefail


info() {
  echo "collect-systemd-dropins [${SERVICE_NAME}]: $*"
}

err() {
  echo "collect-systemd-dropins [${SERVICE_NAME}]: $*" >&2
  exit 1
}

required_vars=(SERVICE_PREFIX SERVICE_NAME SERVICE_USER INSTALL_ROOT SERVICES USER_CONTAINER_UNIT_DIR USER_SYSTEMD_USER_DIR ROOT_UNIT_DEST ROOT_UNIT_PREFIX)
missing=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var-}" ]; then
    missing+=("${var}")
  fi
done
if [ "${#missing[@]}" -ne 0 ]; then
  err "必須環境変数が未設定: ${missing[*]}"
fi

INSTALL_ROOT="${INSTALL_ROOT%/}"

# 残しておくべきdrop-inは存在しないため全部削除する
cleanup_user_dropins() {
  local dest_root="$1"
  [ -d "${dest_root}" ] || return 0
  find "${dest_root}" -type f -name "*.conf" -delete
}

# SERVICE_PREFIX で開始するdrop-inは再配置に備えて削除する
cleanup_root_dropins() {
  [ -d "${ROOT_UNIT_DEST}" ] || return
  while IFS= read -r -d '' dir; do
    find "${dir}" -type f -name "*.conf" -delete
  done < <(find "${ROOT_UNIT_DEST}" -maxdepth 1 -type d -name "${ROOT_UNIT_PREFIX}*.d" -print0)
}

# drop-in 作成側のサービスコンテクストで置換済みなので収集側のコンテクストで置換は不要
copy_dropins_to_dir() {
  local src_root="$1"
  local dest_root="$2"
  local owner="$3"
  local group="$4"

  [ -d "${src_root}" ] || return 0

  while IFS= read -r -d '' file; do
    rel="${file#${src_root}/}"
    dest="${dest_root}/${rel}"
    dest_dir="$(dirname "${dest}")"
    install -d -m 0750 -o "${owner}" -g "${group}" "${dest_dir}"
    install -m 0644 -o "${owner}" -g "${group}" "${file}" "${dest}"
    info "Collected drop-in: ${file} -> ${dest}"
  done < <(find "${src_root}" -type f -name "*.conf" -print0)
}

# drop-in 作成側のサービスコンテクストで置換済みなので収集側のコンテクストで置換は不要
copy_dropins_with_prefix() {
  local src_root="$1"
  local dest_prefix="$2"

  [ -d "${src_root}" ] || return 0

  while IFS= read -r -d '' file; do
    rel="${file#${src_root}/}"
    dest="${dest_prefix}${rel}"
    dest_dir="$(dirname "${dest}")"
    install -d -m 0755 -o root -g root "${dest_dir}"
    install -m 0644 -o root -g root "${file}" "${dest}"
    info "Collected root drop-in: ${file} -> ${dest}"
  done < <(find "${src_root}" -type f -name "*.conf" -print0)
}

info "managed drop-in を掃除"
cleanup_user_dropins "${USER_CONTAINER_UNIT_DIR}"
cleanup_user_dropins "${USER_SYSTEMD_USER_DIR}"
cleanup_root_dropins

after_self=No
for svc in ${SERVICES}; do
  src_base="${INSTALL_ROOT}/${svc}/dropins/systemd"

  src_user_container="${src_base}/user/containers/${SERVICE_NAME}"
  src_user_systemd="${src_base}/user/systemd/${SERVICE_NAME}"
  src_root="${src_base}/root/${SERVICE_NAME}"

  copy_dropins_to_dir "${src_user_container}" "${USER_CONTAINER_UNIT_DIR}" "${SERVICE_USER}" "${SERVICE_USER}"
  copy_dropins_to_dir "${src_user_systemd}" "${USER_SYSTEMD_USER_DIR}" "${SERVICE_USER}" "${SERVICE_USER}"
  copy_dropins_with_prefix "${src_root}" "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}"

  if [ "${after_self}" = "Yes" ]; then
    if [ -d "${src_user_container}" ] || [ -d "${src_user_systemd}" ] || [ -d "${src_root}" ]; then
      info "Warning: ${svc} は ${SERVICE_NAME} の後に SERVICES で定義されています。初回 deploy では drop-in が反映されない可能性があります。"
    fi
  fi

  if [ "${svc}" = "${SERVICE_NAME}" ]; then
    after_self=Yes
  fi
done
