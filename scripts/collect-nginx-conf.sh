#!/bin/sh
set -e

if [ -z "${SERVICE_PATH-}" ] || [ -z "${SERVICE_NAME-}" ] || [ -z "${SERVICE_USER-}" ] || \
  [ -z "${INSTALL_ROOT-}" ] || [ -z "${SERVICES-}" ]; then
  echo "Missing required env: SERVICE_PATH/SERVICE_NAME/SERVICE_USER/INSTALL_ROOT/SERVICES" >&2
  exit 1
fi

conf_dir="${SERVICE_PATH}/container/conf"

echo "Collecting http/https configs from services..."
mkdir -p "$conf_dir"

#for file in "$conf_dir"/http_*.conf "$conf_dir"/https_*.conf; do
#  [ -f "$file" ] || continue
#  case "$file" in
#    "$conf_dir/http_default.conf"|"$conf_dir/https_default.conf") ;;
#    *) rm -f "$file" ;;
#  esac
#done

after_self=No
for svc in ${SERVICES}; do
  if [ "$svc" = "${SERVICE_NAME}" ]; then
    after_self=Yes
    continue
  fi

  src_http="${INSTALL_ROOT}/${svc}/http_${svc}.conf"
  src_https="${INSTALL_ROOT}/${svc}/https_${svc}.conf"

  if [ -f "$src_http" ]; then
    install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 644 \
      "$src_http" "$conf_dir/http_${svc}.conf"
    echo "Imported: $src_http"
    if [ "$after_self" = "Yes" ]; then
      echo "Warning: ${svc} is listed after ${SERVICE_NAME} in SERVICES. Fresh deploy may skip latest http_*.conf."
    fi
  fi

  if [ -f "$src_https" ]; then
    install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 644 \
      "$src_https" "$conf_dir/https_${svc}.conf"
    echo "Imported: $src_https"
    if [ "$after_self" = "Yes" ]; then
      echo "Warning: ${svc} is listed after ${SERVICE_NAME} in SERVICES. Fresh deploy may skip latest https_*.conf."
    fi
  fi
done
