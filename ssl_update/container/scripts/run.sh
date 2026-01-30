#!/bin/sh

set -u
set -x

LEGO_PATH=/var/ssl_share
HOOK_SCRIPT=/scripts/hook.sh


# LEGO_PATH/accounts 以下に account.json ファイルがなかったら run を実行
if find "${LEGO_PATH}/accounts" -type f -name account.json -print | grep -q '/account.json$' ; then
  /lego ${ADDITIONAL_OPTIONS:-} --accept-tos --email "${EMAIL}" \
	--dns "${DNSPROVIDER}" --domains "${DOMAIN}" --path "${LEGO_PATH}" \
	renew --no-random-sleep --renew-hook "${HOOK_SCRIPT}" ${RENEW_OPTION:---dynamic}
else
  /lego ${ADDITIONAL_OPTIONS:-} --accept-tos --email "${EMAIL}" \
	--dns "${DNSPROVIDER}" --domains "${DOMAIN}" --path "${LEGO_PATH}" \
	run --run-hook "${HOOK_SCRIPT}" ${RUN_OPTIONS:-}
fi

touch /var/ssl_share/certificates/.executed
