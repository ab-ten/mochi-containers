#!/bin/sh
set -e

if [ -z "${SERVICE_PATH-}" ]; then
  echo "Missing required env: SERVICE_PATH" >&2
  exit 1
fi

conf_dir="${SERVICE_PATH}/container/conf"
output="${SERVICE_PATH}/container/html/index.html"

services=""
for file in "${conf_dir}"/https_*.conf "${conf_dir}"/http_*.conf; do
  [ -f "${file}" ] || continue
  base="$(basename "${file}")"
  case "${base}" in
    http_default.conf|https_default.conf) continue ;;
  esac
  svc="${base#http_}"
  svc="${svc#https_}"
  svc="${svc%.conf}"
  case " ${services} " in
    *" ${svc} "*) ;;
    *) services="${services} ${svc}" ;;
  esac
done

services="$(printf '%s\n' ${services} | sort -u)"

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
      echo "      <li><a href=\"${scheme}://${svc}.@@CERT_DOMAIN@@/\">${svc}</a></li>"
    done
    echo '    </ul>'
  fi
  echo '  </body>'
  echo '</html>'
} > "${output}"
