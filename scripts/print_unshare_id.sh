#!/usr/bin/env bash

set -euo pipefail

err() {
  echo "print_unshare_id: $*" >&2
  exit 1
}

type_arg=""
service_user=""
id_in_podman=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)
      [ "$#" -ge 2 ] || err "--type の値が必要です"
      type_arg="$2"
      shift 2
      ;;
    --user)
      [ "$#" -ge 2 ] || err "--user の値が必要です"
      service_user="$2"
      shift 2
      ;;
    --id)
      [ "$#" -ge 2 ] || err "--id の値が必要です"
      id_in_podman="$2"
      shift 2
      ;;
    *)
      err "不明な引数です: $1"
      ;;
  esac
done

[ -n "${type_arg}" ] || err "--type を指定してください"
[ -n "${service_user}" ] || err "--user を指定してください"
[ -n "${id_in_podman}" ] || err "--id を指定してください"

case "${type_arg}" in
  uid)
    map_file="/proc/self/uid_map"
    ;;
  gid)
    map_file="/proc/self/gid_map"
    ;;
  *)
    err "--type は uid または gid を指定してください: ${type_arg}"
    ;;
esac

if ! [[ "${id_in_podman}" =~ ^[0-9]+$ ]]; then
  err "--id は 0 以上の整数を指定してください: ${id_in_podman}"
fi

if ! id -u "${service_user}" >/dev/null 2>&1; then
  err "指定されたユーザーが存在しません: ${service_user}"
fi

current_uid="$(id -u)"
current_user="$(id -un)"
if [ "${current_uid}" -ne 0 ] && [ "${current_user}" != "${service_user}" ]; then
  err "実行ユーザーは root または ${service_user} である必要があります（現在: ${current_user}）"
fi

run_unshare() {
  # カレントディレクトリがそのユーザーにパーミッションが出ていないとエラーになるので cd / しておく
  cd /
  if [ "${current_uid}" -eq 0 ]; then
    sudo -u "${service_user}" -H -- podman unshare "$@"
  else
    podman unshare "$@"
  fi
}

mapped_id="$(
  run_unshare awk -v id="${id_in_podman}" '
    $1 <= id && id < ($1 + $3) {
      print $2 + (id - $1)
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 2
      }
    }
  ' "${map_file}"
)" || err "ID マップに値が見つかりません type=${type_arg} id=${id_in_podman}"

printf '%s\n' "${mapped_id}"
