#!/usr/bin/env sh
set -eu

CERT_ARCHIVE="${MAIL_CERT_ARCHIVE:-/var/ssl_share/mail_service/certs.tar}"
CERT_DOMAIN="${MAIL_CERT_DOMAIN:-@@CERT_DOMAIN@@}"
CERT_DIR=/run/mail-service-certs
CERT_FILE="_.${CERT_DOMAIN}.crt"
KEY_FILE="_.${CERT_DOMAIN}.key"

if [ ! -s "${CERT_ARCHIVE}" ]; then
  echo "certificate archive is missing or empty: ${CERT_ARCHIVE}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d /run/mail-service-certs.XXXXXX)"
old_dir=

cleanup() {
  if [ -n "${tmp_dir:-}" ] && [ -d "${tmp_dir}" ]; then
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

tar -xf "${CERT_ARCHIVE}" -C "${tmp_dir}"

if [ ! -s "${tmp_dir}/${CERT_FILE}" ] || [ ! -s "${tmp_dir}/${KEY_FILE}" ]; then
  echo "certificate archive does not contain ${CERT_FILE} and ${KEY_FILE}" >&2
  exit 1
fi

ln -sf "${CERT_FILE}" "${tmp_dir}/fullchain.crt"
ln -sf "${KEY_FILE}" "${tmp_dir}/privkey.key"
chown -R root:root "${tmp_dir}"
chmod 0755 "${tmp_dir}"
chmod 0644 "${tmp_dir}/${CERT_FILE}"
chmod 0600 "${tmp_dir}/${KEY_FILE}"

if [ -d "${CERT_DIR}" ]; then
  old_dir="$(mktemp -d /run/mail-service-certs-old.XXXXXX)"
  rmdir "${old_dir}"
  mv "${CERT_DIR}" "${old_dir}"
fi

if ! mv "${tmp_dir}" "${CERT_DIR}"; then
  if [ -n "${old_dir}" ] && [ -d "${old_dir}" ]; then
    mv "${old_dir}" "${CERT_DIR}"
  fi
  echo "failed to publish certificate directory" >&2
  exit 1
fi

tmp_dir=
if [ -n "${old_dir}" ] && [ -d "${old_dir}" ]; then
  rm -rf "${old_dir}"
fi

echo "dovecot certificates updated."
