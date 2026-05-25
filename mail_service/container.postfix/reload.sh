#!/usr/bin/env sh
set -eu

/usr/local/sbin/mail-postfix-certs-extract
postfix check
postfix reload

echo "postfix reloaded."
