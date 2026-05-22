#!/bin/sh
set -e

SITES_AVAILABLE=/etc/nginx/sites-available
CONF_D=/etc/nginx/conf.d
CERT_ARCHIVE=/var/ssl_share/nginx_rp/certs.tar
CERT_DIR=/run/nginx-certs

CERT=${CERT_DIR}/_.@@CERT_DOMAIN@@.crt
KEY=${CERT_DIR}/_.@@CERT_DOMAIN@@.key

# 必要ならディレクトリ作成（Dockerfile で mkdir 済みなら不要）
mkdir -p "$SITES_AVAILABLE" "$CONF_D"

if [ -f "$CERT_ARCHIVE" ]; then
  tmp_dir="$(mktemp -d /run/nginx-certs.XXXXXX)"
  if tar -xf "$CERT_ARCHIVE" -C "$tmp_dir" && [ -r "$tmp_dir/_.@@CERT_DOMAIN@@.crt" ] && [ -r "$tmp_dir/_.@@CERT_DOMAIN@@.key" ]; then
    old_dir=
    if [ -d "$CERT_DIR" ]; then
      old_dir="$(mktemp -d /run/nginx-certs-old.XXXXXX)"
      rmdir "$old_dir"
      mv "$CERT_DIR" "$old_dir"
    fi
    if ! mv "$tmp_dir" "$CERT_DIR"; then
      if [ -n "$old_dir" ]; then
        mv "$old_dir" "$CERT_DIR"
      fi
      echo "SSL cert directory update failed."
      exit 1
    fi
    if [ -n "$old_dir" ]; then
      rm -rf "$old_dir"
    fi
  else
    echo "SSL archive is missing required cert/key or cannot be extracted."
    rm -rf "$tmp_dir"
  fi
else
  echo "SSL archive not found: $CERT_ARCHIVE"
fi

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
