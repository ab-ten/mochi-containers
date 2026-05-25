#!/usr/bin/env sh
set -eu

/usr/local/sbin/mail-dovecot-certs-extract
doveconf -n >/dev/null
doveadm reload

echo "dovecot reloaded."
