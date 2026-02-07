#!/bin/sh
set -e

echo -n "generating mochi-index: " >&2

if [ -z "${SERVICE_PATH-}" ] || [ -z "${SERVICES-}" ]; then
  echo "Missing required env: SERVICE_PATH/SERVICES" >&2
  exit 1
fi

conf_dir="${SERVICE_PATH}/container/conf"
output="${SERVICE_PATH}/container/html/index.html"

services=""
for svc in ${SERVICES}; do
  [ "${svc}" = "${SERVICE_NAME-}" ] && continue
  case " ${services} " in
    *" ${svc} "*) continue ;;
  esac
  if [ -f "${conf_dir}/https_${svc}.conf" ] || [ -f "${conf_dir}/http_${svc}.conf" ]; then
    services="${services} ${svc}"
  fi
done

{
  echo '<!doctype html>'
  echo '<html lang="ja">'
  echo '  <head>'
  echo '    <meta charset="utf-8">'
  echo '    <title>Mochi サービス一覧</title>'
  echo '  </head>'
  echo '  <body>'
  echo '    <h1>Mochi サービス一覧</h1>'
  echo '    <p>nginx_rp が reverse proxy するサービス一覧です。</p>'
  echo '    <h2>サービス</h2>'
  if [ -z "${services}" ]; then
    echo '    <p>現在公開中のサービスはありません。</p>'
  else
    echo '    <ul>'
    for svc in ${services}; do
      if [ -f "${conf_dir}/https_${svc}.conf" ]; then
        scheme="https"
      else
        scheme="http"
      fi
      echo -n "${scheme}:${svc}.." >&2
      echo "      <li><a href=\"${scheme}://${svc}.${CERT_DOMAIN}/\">${svc}</a></li>"
    done
    echo '    </ul>'
  fi
  echo '  </body>'
  echo '</html>'
} > "${output}"

echo " Done." >&2
