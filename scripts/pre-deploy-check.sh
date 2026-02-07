#!/usr/bin/env bash

set -euo pipefail

START_DIR=$PWD

info() {
  echo "pre-deploy-check: $*"
}

err() {
  echo "pre-deploy-check: $*" >&2
  exit 1
}

run_user() {
  sudo -u "${SERVICE_USER}" "$@"
}

if grep -q '^pre-deploy-check-user:' Makefile; then
  info "pre-deploy-check-user: を実行"
  run_user make -C "${START_DIR}" pre-deploy-check-user
fi

if grep -q '^pre-deploy-check-root:' Makefile; then
  info "pre-deploy-check-root を実行"
  make -C "${START_DIR}" pre-deploy-check-root
fi


NFS_GROUP="svc_nfs_clients"

required_vars=(SERVICE_NAME SERVICE_USER SERVICE_PATH INSTALL_ROOT NFS_ROOT SERVICES CERT_DOMAIN MAP_LOCAL_ADDRESS)
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
NFS_ROOT="${NFS_ROOT%/}"
EXPECTED_SERVICE_PATH="${INSTALL_ROOT}/${SERVICE_NAME}"
SERVICE_PATH="${SERVICE_PATH%/}"
SERVICE_HOME="/home/${SERVICE_USER}"

if [ "${SERVICE_PATH}" != "${EXPECTED_SERVICE_PATH}" ]; then
  err "SERVICE_PATH が不正: 期待値=${EXPECTED_SERVICE_PATH}, 現在=${SERVICE_PATH}"
fi

passwd_entry="$(getent passwd "${SERVICE_USER}" || true)"
if [ -z "${passwd_entry}" ]; then
  err "ユーザーが存在しない: ${SERVICE_USER}"
fi

IFS=":" read -r _ _ _ _ _ found_home _ <<<"${passwd_entry}"
if [ "${found_home}" != "${SERVICE_HOME}" ]; then
  err "HOME 不一致: 期待=${SERVICE_HOME}, 実際=${found_home}"
fi
service_uid="$(id -u "${SERVICE_USER}")"
service_gid="$(id -g "${SERVICE_USER}")"

if [ X"${NFS_GROUP_CHECK:-Yes}" == X"No" ] ; then
  info "NFS group check: skipped."
else
#  if ! id -nG "${SERVICE_USER}" | tr ' ' '\n' | grep -Fx "${NFS_GROUP}" >/dev/null; then
#    err "SERVICE_USER が ${NFS_GROUP} グループに所属していない: ${SERVICE_USER}"
#  fi

  NFS_DIR="${NFS_ROOT}/${SERVICE_NAME}"
  if [ ! -d "${NFS_DIR}" ]; then
    info "NFS ディレクトリを ${SERVICE_USER} 権限で作成: ${NFS_DIR}"
    sudo -u "${SERVICE_USER}" install -d -m 0700 "${NFS_DIR}"
  else
    read -r nfs_uid nfs_gid <<<"$(stat -c '%u %g' "${NFS_DIR}")"
    if [ "${nfs_uid}" != "${service_uid}" ] || [ "${nfs_gid}" != "${service_gid}" ]; then
      err "NFS ディレクトリの所有権が不一致 (期待 UID:GID=${service_uid}:${service_gid}, 実際=${nfs_uid}:${nfs_gid}): ${NFS_DIR}。${SERVICE_USER} で作成し直してね"
    fi
  fi
fi

info "ok for ${SERVICE_NAME}"
