#!/usr/bin/env sh
set -eu

install -d -o vmail -g mail_service_sock -m 2770 /run/mail-service
install -d -o vmail -g vmail -m 0750 /var/mail/vhosts

doveconf -n >/dev/null

exec "$@"
