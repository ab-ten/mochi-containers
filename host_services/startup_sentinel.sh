#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <startup_uid_list>" >&2
  exit 2
fi

UID_LIST_FILE="$1"

log() {
  echo "startup_sentinel: $*"
}

if [ ! -f "${UID_LIST_FILE}" ]; then
  log "startup_uid_list が存在しないため終了"
  exit 0
fi

missing_uids=()
while IFS= read -r uid; do
  if [ -z "${uid}" ]; then
    continue
  fi
  if [[ ! "${uid}" =~ ^[0-9]+$ ]]; then
    log "不正な UID をスキップ: ${uid}"
    continue
  fi
  if [ ! -d "/run/user/${uid}" ]; then
    missing_uids+=("${uid}")
  fi
done < "${UID_LIST_FILE}"

if [ "${#missing_uids[@]}" -eq 0 ]; then
  log "対象 UID の /run/user はすべて存在"
  exit 0
fi

log "欠損した /run/user を検出: ${missing_uids[*]}"
systemctl restart systemd-logind

remaining_uids=()
for uid in "${missing_uids[@]}"; do
  if [ ! -d "/run/user/${uid}" ]; then
    remaining_uids+=("${uid}")
  fi
done

if [ "${#remaining_uids[@]}" -eq 0 ]; then
  log "systemd-logind 再起動後に復旧を確認"
  exit 0
fi

log "systemd-logind 再起動後も /run/user が不足: ${remaining_uids[*]}"
exit 1
