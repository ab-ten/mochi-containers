#!/usr/bin/env bash

set -euo pipefail

START_DIR=$PWD
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPLACE_SCRIPT="${SCRIPT_DIR}/replace-deploy-vars.sh"
STOP_ONLY=No

if [ "$#" -ge 1 ] && [ "$1" = "stop" ]; then
  STOP_ONLY=Yes
fi

info() {
  echo "deploy-service [${SERVICE_NAME}]: $*"
}

err() {
  echo "deploy-service [${SERVICE_NAME}]: $*" >&2
  exit 1
}

run_user() {
  sudo -u "${SERVICE_USER}" "$@"
}

run_user_systemctl() {
  sudo systemctl -M "${SERVICE_USER}@.host" --user "$@"
}

run_user_systemctl_stop() {
  if (run_user_systemctl --no-pager is-active "$1" | grep -q "^active") >/dev/null 2>&1; then
    info "Stopping --user unit: $1"
    run_user_systemctl stop "$1"
  else
    info "Skipping --user unit (not active): $1"
  fi
}

run_user_systemctl_disable() {
  if (run_user_systemctl --no-pager is-enabled "$1" | grep -q "^enabled") >/dev/null 2>&1; then
    info "Disabling --user unit: $1"
    run_user_systemctl disable "$1"
  else
    info "Skipping --user unit (not enabled): $1"
  fi
}

run_user_make() {
  (
    cd ${INSTALL_ROOT}
    run_user env \
      INSTALL_ROOT="${INSTALL_ROOT}" \
      NFS_ROOT="${NFS_ROOT}" \
      SERVICE_PATH="${SERVICE_PATH}" \
      CERT_DOMAIN="${CERT_DOMAIN}" \
      BASE_REPO_DIR="${BASE_REPO_DIR}" \
      ROOT_UNIT_PREFIX="${ROOT_UNIT_PREFIX}" \
      SERVICES="${SERVICES}" \
      MAP_LOCAL_ADDRESS="${MAP_LOCAL_ADDRESS}" \
      make "$@"
  )
}

run_system_systemctl_stop() {
  if (systemctl --no-pager is-active "$1" | grep -q "^active") >/dev/null 2>&1; then
    info "Stopping system unit: $1"
    systemctl stop "$1"
  else
    info "Skipping system unit (not active): $1"
  fi
}

run_system_systemctl_disable() {
  if (systemctl --no-pager is-enabled "$1" | grep -q "^enabled") >/dev/null 2>&1; then
    info "Disabling system unit: $1"
    systemctl disable "$1"
  else
    info "Skipping system unit (not enabled): $1"
  fi
}

reorder_units_sockets_first() {
  local -n arr_ref=$1
  local timers=()
  local sockets=()
  local paths=()
  local others=()
  local unit

  for unit in "${arr_ref[@]}"; do
    if [[ "${unit}" == *.timer ]]; then
      timers+=("${unit}")
    elif [[ "${unit}" == *.socket ]]; then
      sockets+=("${unit}")
    elif [[ "${unit}" == *.path ]]; then
      paths+=("${unit}")
    else
      others+=("${unit}")
    fi
  done

  arr_ref=("${timers[@]}" "${sockets[@]}" "${paths[@]}" "${others[@]}")
}

collect_units() {
  local mode="$1"
  local dir="$2"
  [ -d "${dir}" ] || return

  if [ "${mode}" = "-root" ]; then
    find "${dir}" -maxdepth 1 -type f \( -name "${ROOT_UNIT_PREFIX}*" \) \( -name "*.service" -o -name "*.socket" -o -name "*.container" -o -name "*.timer" -o -name "*.path" \) -printf '%f\n' | sort
  else
    find "${dir}" -maxdepth 1 -type f \( -name "*.service" -o -name "*.socket" -o -name "*.container" -o -name "*.timer" -o -name "*.path" \) -printf '%f\n' | sort
  fi
}

collect_user_units() {
  local units=()
  local dir

  for dir in "$@"; do
    [ -d "${dir}" ] || continue
    while IFS= read -r unit; do
      units+=("${unit}")
    done < <(find "${dir}" -maxdepth 1 -type f \( -name "*.service" -o -name "*.socket" -o -name "*.container" -o -name "*.timer" -o -name "*.path" \) -printf '%f\n' | sort)
  done

  if [ "${#units[@]}" -gt 0 ]; then
    printf '%s\n' "${units[@]}" | sort -u
  fi
}

user_unit_file_path() {
  local unit="$1"

  if [ -f "${USER_CONTAINER_UNIT_DIR}/${unit}" ]; then
    echo "${USER_CONTAINER_UNIT_DIR}/${unit}"
  elif [ -f "${USER_SYSTEMD_USER_DIR}/${unit}" ]; then
    echo "${USER_SYSTEMD_USER_DIR}/${unit}"
  fi
}

required_vars=(SERVICE_NAME SERVICE_USER SERVICE_PATH INSTALL_ROOT NFS_ROOT SERVICE_PREFIX SECRETS_DIR SERVICES)
missing=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var-}" ]; then
    missing+=("${var}")
  fi
done
if [ "${#missing[@]}" -ne 0 ]; then
  err "必須環境変数が未設定: ${missing[*]}"
fi

export INSTALL_ROOT="${INSTALL_ROOT%/}"
export NFS_ROOT="${NFS_ROOT%/}"
export SERVICE_PATH="${SERVICE_PATH%/}"
export EXPECTED_SERVICE_PATH="${INSTALL_ROOT}/${SERVICE_NAME}"
if [ "${SERVICE_PATH}" != "${EXPECTED_SERVICE_PATH}" ]; then
  err "SERVICE_PATH が不正: 期待値=${EXPECTED_SERVICE_PATH}, 現在=${SERVICE_PATH}"
fi
if [[ "${SERVICE_PREFIX}" =~ [[:space:]] ]] || [ -z "${SERVICE_PREFIX}" ]; then
  err "SERVICE_PREFIX が不正（空白禁止・空禁止）: ${SERVICE_PREFIX}"
fi

export SRC_DIR="$(pwd)"
# ホームは OS 既定の /home/<user> を使用し、/srv 配下には置かない（Podman ストレージ前提の揺れを避ける）
export SERVICE_HOME="/home/${SERVICE_USER}"
export USER_UNIT_DIR="${SERVICE_HOME}/.config"
export USER_CONTAINER_UNIT_DIR="${USER_UNIT_DIR}/containers/systemd"
export USER_SYSTEMD_USER_DIR="${USER_UNIT_DIR}/systemd/user"
export ROOT_UNIT_PREFIX="${SERVICE_PREFIX}-${SERVICE_NAME}-"
export ROOT_UNIT_DEST="/etc/systemd/system"

info "uninstall 用の unit 一覧を取得"
mapfile -t user_units_uninstall < <(collect_user_units "${USER_CONTAINER_UNIT_DIR}" "${USER_SYSTEMD_USER_DIR}" || true)
mapfile -t root_units_uninstall < <(collect_units -root "${ROOT_UNIT_DEST}" || true)
reorder_units_sockets_first user_units_uninstall
reorder_units_sockets_first root_units_uninstall

if [ "${#user_units_uninstall[@]}" -gt 0 ]; then
  for unit in "${user_units_uninstall[@]}"; do
    target="${unit}"
    if [[ "${unit}" == *.container ]]; then
      target="${unit%.container}"
    fi
    run_user_systemctl_stop "${target}"
    run_user_systemctl_disable "${target}"
  done
else
  info "停止対象の --user unit は無し"
fi
if [ "${#root_units_uninstall[@]}" -gt 0 ]; then
  for unit in "${root_units_uninstall[@]}"; do
    target="${unit}"
    if [[ "${unit}" == *.container ]]; then
      target="${unit%.container}"
    fi
    run_system_systemctl_stop "${target}"
    run_system_systemctl_disable "${target}"
  done
  info "旧 root unit ファイルを削除: ${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}*"
  rm -f "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}"* || true
else
  info "停止対象の system unit は無し"
fi

if [ "${STOP_ONLY}" = "Yes" ]; then
  exit 0
fi

info "配置ディレクトリを作成: ${SERVICE_PATH}"
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${SERVICE_PATH}"
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${SERVICE_HOME}"
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${USER_UNIT_DIR}/containers/systemd"
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${USER_UNIT_DIR}/systemd/user"

info "rsync でソースを配置: ${SRC_DIR} -> ${SERVICE_PATH}"
rsync -a --delete --exclude '.git' --exclude '*.swp' --exclude '*~' "${SRC_DIR}/" "${SERVICE_PATH}/"
if [ -d "${SRC_DIR}/home" ] ; then
  rsync -a --delete --exclude '.cache' --exclude '.local' --exclude '*~' "${SRC_DIR}/home/" "${SERVICE_HOME}/"
fi
chmod 750 "${SERVICE_HOME}/" "${SERVICE_PATH}/"

info "drop-in 配布元の @@SERVICE_PATH@@ などを置換"
dropins_root="${SERVICE_PATH}/dropins/systemd"
if [ -d "${dropins_root}" ]; then
  while IFS= read -r -d '' dropin_file; do
    "${REPLACE_SCRIPT}" "${dropin_file}"
  done < <(find "${dropins_root}" -type f -name "*.conf" -print0)
else
  info "drop-in 配布元ディレクトリが存在しないため置換スキップ: ${dropins_root}"
fi

info "user unit に含まれる @@SERVICE_PATH@@ などを置換"
user_unit_dirs=("${USER_CONTAINER_UNIT_DIR}" "${USER_SYSTEMD_USER_DIR}")
for unit_dir in "${user_unit_dirs[@]}"; do
  if [ -d "${unit_dir}" ]; then
    while IFS= read -r -d '' unit_file; do
      info "replace-scropt ${unit_file}"
      "${REPLACE_SCRIPT}" "${unit_file}"
    done < <(find "${unit_dir}" -maxdepth 2 -type f \( -name "*.service" -o -name "*.socket" -o -name "*.container" -o -name "*.timer" -o -name "*.path" -o \( -path "*/.d/*.conf" -a -name "*.conf" \) \) -print0)
  else
    info "user unit ディレクトリが存在しないため置換スキップ: ${unit_dir}"
  fi
done

info "systemd drop-in を収集"
"${SCRIPT_DIR}/collect-systemd-dropins.sh"

info "所有権を ${SERVICE_USER}:${SERVICE_USER} に統一"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${SERVICE_PATH}" "${SERVICE_HOME}"

cd "${SERVICE_PATH}"

info "loginctl enable-linger ${SERVICE_USER}"
loginctl enable-linger "${SERVICE_USER}"

if grep -q '^pre-build-user:' Makefile; then
  info "pre-build-user を実行"
  run_user_make -C "${START_DIR}" pre-build-user
fi

if grep -q '^pre-build-root:' Makefile; then
  info "pre-build-root を実行"
  make -C "${START_DIR}" pre-build-root
fi

if [ -n "${REPLACE_FILES_USER-}" ]; then
  info "replace-files-user を実行"
  run_user_make -C "${SERVICE_PATH}" replace-files-user
fi

if [ -n "${REPLACE_FILES_ROOT-}" ]; then
  info "replace-files-root を実行"
  make -C "${SERVICE_PATH}" replace-files-root
fi

info "コンテナをビルド"
shopt -s nullglob
container_dirs=("${SERVICE_PATH}"/container "${SERVICE_PATH}"/container.*)
shopt -u nullglob
built_any=No
for dir in "${container_dirs[@]}"; do
  [ -d "${dir}" ] || continue
  base="$(basename "${dir}")"
  if [ "${base}" = "container" ]; then
    image="localhost/${SERVICE_NAME}:dev"
  else
    image="localhost/${SERVICE_NAME}-${base#container.}:dev"
  fi
  info "podman build: ${image} (${dir})"
  run_user podman build -t "${image}" "${dir}"
  built_any=Yes
done
if [ "${built_any}" = "No" ]; then
  info "コンテナディレクトリが見つからないためビルドスキップ"
fi

if grep -q '^post-build-user:' Makefile; then
  info "post-build-user を実行"
  run_user_make -C "${SERVICE_PATH}" post-build-user
fi

if grep -q '^post-build-root:' Makefile; then
  info "post-build-root を実行"
  make -C "${SERVICE_PATH}" post-build-root
fi

if grep -q '^env-files-user:' Makefile; then
  info "env-files-user を実行"
  make -C "${SERVICE_PATH}" --always-make env-files-user
fi

if grep -q '^env-files-root:' Makefile; then
  info "env-files-root を実行"
  make -C "${SERVICE_PATH}" --always-make env-files-root
fi

info "install 用の unit 一覧を取得"
mapfile -t user_units_install < <(collect_user_units "${USER_CONTAINER_UNIT_DIR}" "${USER_SYSTEMD_USER_DIR}" || true)
mapfile -t root_units_install < <(collect_units -source "${SERVICE_PATH}/systemd" || true)

if [ "${#root_units_install[@]}" -gt 0 ]; then
  if [ ! -d "${ROOT_UNIT_DEST}" ]; then
    err "ROOT_UNIT_DEST が存在しません: ${ROOT_UNIT_DEST}"
  fi
  info "root unit を配置: ${ROOT_UNIT_DEST}"
  for unit in "${root_units_install[@]}"; do
    cp "${SERVICE_PATH}/systemd/${unit}" "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"
    "${REPLACE_SCRIPT}" "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"
    chmod 0644 "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"
    chown root:root "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"
    info "配置: ${unit} -> ${ROOT_UNIT_PREFIX}${unit} (テンプレート置換済み)"
  done
  systemctl daemon-reload
fi

info "user unit を daemon-reload"
run_user_systemctl daemon-reload

if [ "${#user_units_install[@]}" -gt 0 ]; then
  for unit in "${user_units_install[@]}"; do
    if [[ $unit == *.container ]]; then
      # Quadlet 生成ユニット → enable 不可なので start のみ
      info "start --user ${unit%.container}"
      run_user_systemctl start "${unit%.container}"
    else
      # .service / .socket / その他の unit ファイルの場合
      # [Install] セクションがあるかチェックして、ある場合だけ enable する
      unit_path="$(user_unit_file_path "${unit}")"
      if [ -n "${unit_path}" ] && grep -q '^\[Install\]' "${unit_path}"; then
        info "enable --now --user ${unit}"
        run_user_systemctl enable --now "${unit}"
      else
        if [ -n "${unit_path}" ] && grep -q '^#NOSTART' "${unit_path}"; then
          info "NOSTART: --user ${unit}"
	else
          info "start --user ${unit} (no [Install] section)"
          run_user_systemctl start "${unit}"
	fi
      fi
    fi
  done
else
  info "enable 対象の --user unit は無し"
fi

if [ "${#root_units_install[@]}" -gt 0 ]; then
  for unit in "${root_units_install[@]}"; do
    if [[ $unit == *.container ]]; then
      # Quadlet 生成ユニット → enable 不可なので start のみ
      info "start ${ROOT_UNIT_PREFIX}${unit%.container}"
      systemctl start "${ROOT_UNIT_PREFIX}${unit%.container}"
    else
      # .service / .socket / その他の unit ファイルの場合
      # [Install] セクションがあるかチェックして、ある場合だけ enable する
      if grep -q '^\[Install\]' "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"; then
        info "enable --now (system) ${ROOT_UNIT_PREFIX}${unit}"
        systemctl enable --now "${ROOT_UNIT_PREFIX}${unit}"
      else
        if grep -q '^#NOSTART' "${ROOT_UNIT_DEST}/${ROOT_UNIT_PREFIX}${unit}"; then
          info "NOSTART: ${unit}"
	else
          info "start (system) ${ROOT_UNIT_PREFIX}${unit} (no [Install] section)"
          systemctl start "${ROOT_UNIT_PREFIX}${unit}"
	fi
      fi
    fi
  done
fi

info "deploy ok for ${SERVICE_NAME}"
