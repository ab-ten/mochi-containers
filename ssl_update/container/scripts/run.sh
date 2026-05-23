#!/bin/sh

set -eu

SHARE_ROOT=/var/ssl_share
HOOK_SCRIPT=/scripts/hook.sh
LOCK_FILE=/var/ssl_share/.lego.lock
CLIENTS="${CLIENTS-nginx_rp}"
ROOT_ARCHIVE="${SHARE_ROOT}/certs.tar"
NEW_ARCHIVE="${SHARE_ROOT}/certs-new.tar"
SERVER_STAGING=https://acme-staging-v02.api.letsencrypt.org/directory

WORK_DIR=
LOG_FILE=

cleanup() {
  if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
    rm -rf "${WORK_DIR}"
  fi
}

trap cleanup EXIT

notify_slack() {
  subject="$1"
  body="${2:-}"

  if [ -z "${SLACK_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL:-}" ]; then
    echo "slack notification skipped: SLACK_TOKEN or SLACK_CHANNEL is not set" >&2
    return 0
  fi

  text="${subject}"
  if [ -n "${body}" ]; then
    text="${text}
${body}"
  fi

  curl -fsS -X POST 'https://slack.com/api/chat.postMessage' \
    -d "token=${SLACK_TOKEN}" \
    -d "channel=${SLACK_CHANNEL}" \
    --data-urlencode "text=${text}" || true
}

fail_distribution() {
  message="$1"
  notify_slack "ssl_update certificate distribution failed" "${message}"
  exit 1
}

fail_lego() {
  message="$1"
  log_tail=""
  if [ -n "${LOG_FILE}" ] && [ -f "${LOG_FILE}" ]; then
    log_tail="$(tail -c 3000 "${LOG_FILE}" || true)"
  fi
  notify_slack "ssl_update lego failed" "${message}
${log_tail}"
  exit 1
}

prepare_paths() {
  if [ "${USE_STAGING:-No}" = "Yes" ]; then
    LEGO_PATH="${SHARE_ROOT}/staging"
    SERVER_OPTION="--server ${SERVER_STAGING}"
  else
    LEGO_PATH="${SHARE_ROOT}/production"
    SERVER_OPTION=""
  fi

  ACCOUNTS_DIR="${LEGO_PATH}/accounts"
  CERTS_DIR="${LEGO_PATH}/certificates"
}

run_lego() {
  if find "${ACCOUNTS_DIR}" -type f -name account.json -print | grep -q '/account.json$'; then
    /lego ${SERVER_OPTION} ${ADDITIONAL_OPTIONS:-} --accept-tos --email "${EMAIL}" \
      --dns "${DNSPROVIDER}" --domains "${DOMAIN}" --path "${LEGO_PATH}" \
      renew --no-random-sleep --renew-hook "${HOOK_SCRIPT}" ${RENEW_OPTION:---dynamic}
  else
    /lego ${SERVER_OPTION} ${ADDITIONAL_OPTIONS:-} --accept-tos --email "${EMAIL}" \
      --dns "${DNSPROVIDER}" --domains "${DOMAIN}" --path "${LEGO_PATH}" \
      run --run-hook "${HOOK_SCRIPT}" ${RUN_OPTIONS:-}
  fi
}

validate_certificates() {
  domain_name="${DOMAIN#*.}"
  cert_file="${CERTS_DIR}/_.${domain_name}.crt"
  key_file="${CERTS_DIR}/_.${domain_name}.key"

  if [ ! -s "${cert_file}" ]; then
    fail_distribution "required certificate file is missing or empty: ${cert_file}"
  fi
  if [ ! -s "${key_file}" ]; then
    fail_distribution "required key file is missing or empty: ${key_file}"
  fi
}

create_archive_from_certificates() {
  archive_path="$1"
  tmp_archive="${archive_path}.tmp"

  rm -f "${tmp_archive}" "${archive_path}"
  (
    umask 077
    cd "${CERTS_DIR}"
    find . -type f ! -name '.*' -print | sort | tar -cf "${tmp_archive}" -T -
  )
  mv "${tmp_archive}" "${archive_path}"
}

archive_changed() {
  candidate="$1"

  if [ ! -f "${ROOT_ARCHIVE}" ]; then
    return 0
  fi

  mkdir -p "${WORK_DIR}/old" "${WORK_DIR}/new"
  tar -xf "${ROOT_ARCHIVE}" -C "${WORK_DIR}/old" || return 0
  tar -xf "${candidate}" -C "${WORK_DIR}/new" || return 0

  if diff -qr "${WORK_DIR}/old" "${WORK_DIR}/new" >/dev/null; then
    return 1
  fi
  return 0
}

distribute_archive_file() {
  archive_path="$1"

  for client in ${CLIENTS}; do
    client_dir="${SHARE_ROOT}/${client}"
    pending="${client_dir}/.pending-update"
    tmp="${client_dir}/certs-new.tar.tmp"

    if [ ! -d "${client_dir}" ]; then
      fail_distribution "client directory does not exist: ${client_dir}"
    fi

    umask 027
    touch "${pending}" || fail_distribution "failed to create ${pending}"
    rm -f "${tmp}"
    install -m 0640 "${archive_path}" "${tmp}" || fail_distribution "failed to install archive to ${tmp}"
    mv "${tmp}" "${client_dir}/certs.tar" || fail_distribution "failed to publish ${client_dir}/certs.tar"
    touch "${client_dir}/marker.updated" || fail_distribution "failed to touch ${client_dir}/marker.updated"
    rm -f "${pending}" || fail_distribution "failed to remove ${pending}"
  done
}

backfill_archive() {
  for client in ${CLIENTS}; do
    client_dir="${SHARE_ROOT}/${client}"
    if [ ! -f "${client_dir}/certs.tar" ] || [ -f "${client_dir}/.pending-update" ]; then
      distribute_archive_file "${ROOT_ARCHIVE}"
      return
    fi
  done
}

prepare_paths
mkdir -p "${ACCOUNTS_DIR}" "${CERTS_DIR}"
WORK_DIR="$(mktemp -d)"
LOG_FILE="${WORK_DIR}/lego.log"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  notify_slack "ssl_update lock failed" "another ssl_update process is already running"
  exit 1
fi

touch "${SHARE_ROOT}/.lego-error"
rm -f "${SHARE_ROOT}/marker.updated"

if ! run_lego >"${LOG_FILE}" 2>&1; then
  fail_lego "lego exited with an error"
fi

rm -f "${SHARE_ROOT}/.lego-error"

validate_certificates

CANDIDATE_ARCHIVE="${WORK_DIR}/certs-new.tar"
create_archive_from_certificates "${CANDIDATE_ARCHIVE}"

if archive_changed "${CANDIDATE_ARCHIVE}"; then
  install -m 0640 "${CANDIDATE_ARCHIVE}" "${NEW_ARCHIVE}.tmp" || fail_distribution "failed to prepare ${NEW_ARCHIVE}.tmp"
  mv "${NEW_ARCHIVE}.tmp" "${NEW_ARCHIVE}" || fail_distribution "failed to publish ${NEW_ARCHIVE}"
  distribute_archive_file "${NEW_ARCHIVE}"
  mv "${NEW_ARCHIVE}" "${ROOT_ARCHIVE}" || fail_distribution "failed to update ${ROOT_ARCHIVE}"
  chmod 0640 "${ROOT_ARCHIVE}" || fail_distribution "failed to chmod ${ROOT_ARCHIVE}"
else
  backfill_archive
fi
