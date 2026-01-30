# ssl_update/Makefile
export
SERVICE_NAME = ssl_update
SERVICE_USER = ssl_update
ACCOUNTS_DIR = ${INSTALL_ROOT}/ssl_share/accounts
CERTS_DIR    = ${INSTALL_ROOT}/ssl_share/certificates

-include Makefile.local


post-build-root:
	mkdir -p -m 700 "${ACCOUNTS_DIR}"
	chown "${SERVICE_USER}:${SERVICE_USER}" "${ACCOUNTS_DIR}"
	mkdir -p -m 2750 "${CERTS_DIR}"
# nginx コンテナが証明書を読み込む時点ではまだ root:root なので group は subgid に変換しなくて良い
	chown "${SERVICE_USER}:nginx_rp" "${CERTS_DIR}"
	chown "${SERVICE_USER}:nginx_rp" "${INSTALL_ROOT}/ssl_share"
	chmod 750 "${INSTALL_ROOT}/ssl_share"
	chmod 750 ${SERVICE_PATH}/container/scripts/*.sh

env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user

include ../mk/services.mk
