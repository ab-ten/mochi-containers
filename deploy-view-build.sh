#!/usr/bin/env bash

set -euo pipefail

info() {
  echo "deploy-view-build: $*"
}

err() {
  echo "deploy-view-build: $*" >&2
  exit 1
}

resolve_existing_dir() {
  local dir_path="$1"

  if [ ! -d "${dir_path}" ]; then
    err "ディレクトリが存在しません: ${dir_path}"
  fi

  (
    cd -P -- "${dir_path}"
    pwd -P
  )
}

is_same_or_within() {
  local lhs="${1%/}"
  local rhs="${2%/}"

  if [ "${1}" = "/" ]; then
    lhs="/"
  fi
  if [ "${2}" = "/" ]; then
    rhs="/"
  fi

  if [ "${lhs}" = "${rhs}" ]; then
    return 0
  fi
  if [ "${rhs}" = "/" ]; then
    return 0
  fi

  case "${lhs}" in
    "${rhs}"/*) return 0 ;;
    *) return 1 ;;
  esac
}

should_skip_relpath() {
  local rel_path="$1"
  local base_name

  base_name="$(basename "${rel_path}")"
  case "${rel_path}" in
    .git|.git/*|README.md) return 0 ;;
    *)
      ;;
  esac
  case "${base_name}" in
    .gitignore|*~|*.swp) return 0 ;;
    *)
      return 1
      ;;
  esac
}

check_customize_conflicts() {
  local customize_root="$1"
  local containers_root="$2"
  local -n conflicts_ref="$3"
  local customize_path
  local rel_path
  local source_path
  local parent_path

  conflicts_ref=()

  while IFS= read -r -d '' customize_path; do
    rel_path="${customize_path#${customize_root}/}"
    if should_skip_relpath "${rel_path}"; then
      continue
    fi

    source_path="${containers_root}/${rel_path}"
    if [ -d "${customize_path}" ]; then
      if [ -e "${source_path}" ] && [ ! -d "${source_path}" ]; then
        conflicts_ref+=("${rel_path} (customize: directory, containers: non-directory)")
      fi
    else
      if [ -e "${source_path}" ]; then
        conflicts_ref+=("${rel_path}")
      fi
    fi

    parent_path="${rel_path}"
    while [[ "${parent_path}" == */* ]]; do
      parent_path="${parent_path%/*}"
      source_path="${containers_root}/${parent_path}"
      if [ -e "${source_path}" ] && [ ! -d "${source_path}" ]; then
        conflicts_ref+=("${rel_path} (ancestor is non-directory in containers: ${parent_path})")
        break
      fi
    done
  done < <(find "${customize_root}" -mindepth 1 \( -path "${customize_root}/.git" -o -path "${customize_root}/.git/*" \) -prune -o -print0)

  if [ "${#conflicts_ref[@]}" -gt 0 ]; then
    mapfile -t conflicts_ref < <(printf '%s\n' "${conflicts_ref[@]}" | sort -u)
  fi
}

sync_view() {
  local containers_root="$1"
  local customize_root="$2"
  local view_root="$3"

  info "view を初期化します: ${containers_root} -> ${view_root}"
  rsync -a --delete \
    --exclude '/_local/' \
    --exclude '*.swp' \
    --exclude '*~' \
    "${containers_root}/" "${view_root}/"

  info "customize ファイルを追加します: ${customize_root} -> ${view_root}"
  rsync -a \
    --exclude '/README.md' \
    --exclude '.git' \
    --exclude '.gitignore' \
    --exclude '*.swp' \
    --exclude '*~' \
    "${customize_root}/" "${view_root}/"
}

SCRIPT_DIR="$(cd -P -- "$(dirname "$0")" && pwd -P)"
CONTAINERS_ROOT="$(resolve_existing_dir "${SCRIPT_DIR}")"
CURRENT_DIR="$(resolve_existing_dir "$PWD")"
LOCAL_CUSTOMIZE_ROOT="${CONTAINERS_ROOT}/_local"
if [ -n "${MOCHI_CUSTOMIZE+x}" ]; then
  CUSTOMIZE_ROOT_INPUT="${MOCHI_CUSTOMIZE}"
elif [ "${CURRENT_DIR}" = "${CONTAINERS_ROOT}" ] && [ -d "${LOCAL_CUSTOMIZE_ROOT}" ]; then
  CUSTOMIZE_ROOT_INPUT="${LOCAL_CUSTOMIZE_ROOT}"
else
  CUSTOMIZE_ROOT_INPUT="${CURRENT_DIR}"
fi
VIEW_ROOT_INPUT="${MOCHI_DEPLOY_VIEW:-${CONTAINERS_ROOT%/}/../mochi-deploy-view}"
INVOKER_USER="$(id -un)"
INVOKER_GROUP="$(id -gn)"
RUN_MAKE=No

CUSTOMIZE_ROOT="$(resolve_existing_dir "${CUSTOMIZE_ROOT_INPUT}")"
VIEW_ROOT="$(resolve_existing_dir "${VIEW_ROOT_INPUT}")"

if [ "${CONTAINERS_ROOT}" = "/" ]; then
  err "mochi-containers に / は指定できません"
fi
if [ "${CUSTOMIZE_ROOT}" = "/" ]; then
  err "カスタマイズディレクトリに / は指定できません"
fi
if [ "${VIEW_ROOT}" = "/" ]; then
  err "mochi-deploy-view に / は指定できません"
fi

if [ "${CUSTOMIZE_ROOT}" = "${CONTAINERS_ROOT}" ]; then
  err "カスタマイズディレクトリと mochi-containers は別ディレクトリにしてください"
fi
if [ "${VIEW_ROOT}" = "${CONTAINERS_ROOT}" ] || [ "${VIEW_ROOT}" = "${CUSTOMIZE_ROOT}" ]; then
  err "mochi-deploy-view はカスタマイズディレクトリ / mochi-containers と別ディレクトリにしてください"
fi

if is_same_or_within "${VIEW_ROOT}" "${CONTAINERS_ROOT}" || is_same_or_within "${CONTAINERS_ROOT}" "${VIEW_ROOT}"; then
  err "mochi-deploy-view と mochi-containers は相互に入れ子にできません"
fi
if is_same_or_within "${VIEW_ROOT}" "${CUSTOMIZE_ROOT}" || is_same_or_within "${CUSTOMIZE_ROOT}" "${VIEW_ROOT}"; then
  err "mochi-deploy-view とカスタマイズディレクトリは相互に入れ子にできません"
fi
if [ "${CUSTOMIZE_ROOT}" != "${LOCAL_CUSTOMIZE_ROOT}" ] && \
  { is_same_or_within "${CUSTOMIZE_ROOT}" "${CONTAINERS_ROOT}" || is_same_or_within "${CONTAINERS_ROOT}" "${CUSTOMIZE_ROOT}"; }; then
  err "カスタマイズディレクトリと mochi-containers は相互に入れ子にできません"
fi

if [ "${#}" -eq 0 ]; then
  info "引数が無いため make の既定ターゲットを実行します"
fi

if [ -n "${SECRETS_DIR+x}" ]; then
  if [ -z "${SECRETS_DIR}" ]; then
    err "SECRETS_DIR が空文字列です"
  fi
  SECRETS_DIR="$(resolve_existing_dir "${SECRETS_DIR}")"
fi

cleanup_after_make() {
  local status=$?

  if [ "${RUN_MAKE}" = "Yes" ]; then
    sudo chown -R "${INVOKER_USER}:${INVOKER_GROUP}" "${VIEW_ROOT}"
  fi

  exit "${status}"
}

trap cleanup_after_make EXIT

info "view の所有権を確認します: ${VIEW_ROOT}"
sudo chown -R "${INVOKER_USER}:${INVOKER_GROUP}" "${VIEW_ROOT}"

declare -a conflicts=()
check_customize_conflicts "${CUSTOMIZE_ROOT}" "${CONTAINERS_ROOT}" conflicts
if [ "${#conflicts[@]}" -gt 0 ]; then
  {
    echo "deploy-view-build: カスタマイズディレクトリに upstream と衝突するパスがあります:"
    printf '  %s\n' "${conflicts[@]}"
  } >&2
  exit 1
fi

sync_view "${CONTAINERS_ROOT}" "${CUSTOMIZE_ROOT}" "${VIEW_ROOT}"

declare -a sudo_make_cmd=(sudo)
if [ -n "${SECRETS_DIR-}" ]; then
  sudo_make_cmd+=(env "SECRETS_DIR=${SECRETS_DIR}")
fi
sudo_make_cmd+=(make "$@")

RUN_MAKE=Yes
info "view 上で make を実行します: ${VIEW_ROOT}"
(
  cd "${VIEW_ROOT}"
  "${sudo_make_cmd[@]}"
)
