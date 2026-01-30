#!/bin/sh
set -e

SITES_AVAILABLE=/etc/nginx/sites-available
CONF_D=/etc/nginx/conf.d

CERT=/var/ssl_share/certificates/_.@@CERT_DOMAIN@@.crt
KEY=/var/ssl_share/certificates/_.@@CERT_DOMAIN@@.key

# 必要ならディレクトリ作成（Dockerfile で mkdir 済みなら不要）
mkdir -p "$SITES_AVAILABLE" "$CONF_D"

rm -f "$CONF_D"/http_*.conf "$CONF_D"/https_*.conf

# http_*.conf は常に使う
found_http=No
for file in "$SITES_AVAILABLE"/http_*.conf; do
  [ -f "$file" ] || continue
  ln -sf "$file" "$CONF_D/$(basename "$file")"
  echo "Enabled: $(basename "$file")"
  found_http=Yes
done
if [ "$found_http" = "No" ]; then
  echo "Warning: http_*.conf not found in $SITES_AVAILABLE."
fi

# https_*.conf は証明書が揃っているときだけ
if [ -r "$CERT" ] && [ -r "$KEY" ]; then
  found_https=No
  for file in "$SITES_AVAILABLE"/https_*.conf; do
    [ -f "$file" ] || continue
    ln -sf "$file" "$CONF_D/$(basename "$file")"
    echo "Enabled: $(basename "$file") (SSL)"
    found_https=Yes
  done
  if [ "$found_https" = "No" ]; then
    echo "Warning: https_*.conf not found in $SITES_AVAILABLE."
  fi
else
  echo "SSL config not enabled. Either cert/key is missing or unreadable."
fi

# 起動前にコンフィグチェック
nginx -t
