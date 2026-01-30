#!/bin/sh

set -eu

/docker-entrypoint.d/10-nginx-sites-symlink.sh
nginx -t
nginx -s reload

echo "nginx reloaded."
