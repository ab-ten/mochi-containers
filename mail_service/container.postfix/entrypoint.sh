#!/usr/bin/env sh
set -eu

install -d -o root -g mail_service_sock -m 2770 /run/mail-service
install -d -o root -g root -m 0755 /var/spool/postfix
if [ ! -d /var/spool/postfix/public ]; then
  cp -a /var/spool/postfix-template/. /var/spool/postfix/
fi

chown postfix /var/lib/postfix/
chgrp postdrop /usr/sbin/postqueue /usr/sbin/postdrop

/usr/local/sbin/mail-postfix-certs-extract
postfix check

exec "$@"
