#!/usr/bin/env bash
set -euo pipefail
set -x
port_type="mochi_mail_high_port_t"
semanage_err_file="/tmp/mochi-mail-semanage-port.err"

err() {
  echo "configure-selinux-ports: $*" >&2
  exit 1
}

[ -n "${MAIL_SMTP_BACKEND_PORT-}" ] || err "MAIL_SMTP_BACKEND_PORT is not set"
[ -n "${MAIL_POP3_BACKEND_PORT-}" ] || err "MAIL_POP3_BACKEND_PORT is not set"

case "${MAIL_SMTP_BACKEND_PORT}" in
  *[!0-9]*|"") err "MAIL_SMTP_BACKEND_PORT must be numeric: ${MAIL_SMTP_BACKEND_PORT}" ;;
esac
case "${MAIL_POP3_BACKEND_PORT}" in
  *[!0-9]*|"") err "MAIL_POP3_BACKEND_PORT must be numeric: ${MAIL_POP3_BACKEND_PORT}" ;;
esac

for port in "${MAIL_SMTP_BACKEND_PORT}" "${MAIL_POP3_BACKEND_PORT}"; do
  if [ "${port}" -lt 1024 ] || [ "${port}" -gt 65535 ]; then
    err "backend ports must be high TCP ports: ${port}"
  fi
done

check_port_type_installed() {
  command -v seinfo >/dev/null 2>&1 \
    || err "seinfo is not available. Install setools-console and local-mochi-mail-security-selinux first."

  seinfo -t "${port_type}" \
    | awk -v type="${port_type}" '
        {
          for (i = 1; i <= NF; i++) {
            if ($i == type) found = 1
          }
        }
        END {
          exit found ? 0 : 1
        }' \
    || err "SELinux port type ${port_type} is not available. Install local-mochi-mail-security-selinux first and reboot if required."
}

delete_existing_ports() {
  semanage port -l -C \
    | awk -v type="${port_type}" '$1 == type && $2 == "tcp" {
        for (i = 4; i <= NF; i++) {
          gsub(",", "", $i)
          if ($i != "") print $i
        }
      }' \
    | sort -u \
    | while IFS= read -r port; do
        [ -n "${port}" ] || continue
        semanage port -d -t "${port_type}" -p tcp "${port}" || true
      done
}

add_port() {
  port="$1"

  if ! semanage port -a -t "${port_type}" -p tcp "${port}" 2>"${semanage_err_file}"; then
    cat "${semanage_err_file}" >&2
    err "failed to assign ${port}/tcp to ${port_type}. Check conflicting local SELinux port definitions."
  fi
  rm -f "${semanage_err_file}"
}

check_port_type_installed
delete_existing_ports
add_port "${MAIL_SMTP_BACKEND_PORT}"
add_port "${MAIL_POP3_BACKEND_PORT}"
