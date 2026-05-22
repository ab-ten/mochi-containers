# ssl_update/Makefile
export
SERVICE_NAME = ssl_update
SERVICE_USER = ssl_update
USE_STAGING = No
SLACK_NOTIFICATION = Yes
SSL_SHARE_DIR = ${INSTALL_ROOT}/ssl_share
PRODUCTION_DIR = ${INSTALL_ROOT}/ssl_share/production
ACCOUNTS_DIR = ${INSTALL_ROOT}/ssl_share/production/accounts
CERTS_DIR    = ${INSTALL_ROOT}/ssl_share/production/certificates
OLD_ACCOUNTS_DIR = ${INSTALL_ROOT}/ssl_share/accounts
OLD_CERTS_DIR    = ${INSTALL_ROOT}/ssl_share/certificates
STAGING_DIR = ${INSTALL_ROOT}/ssl_share/staging
STAGING_ACCOUNTS_DIR = ${INSTALL_ROOT}/ssl_share/staging/accounts
STAGING_CERTS_DIR    = ${INSTALL_ROOT}/ssl_share/staging/certificates
NGINX_RP_CERTS_DIR   = ${INSTALL_ROOT}/ssl_share/nginx_rp
MAIL_SERVICE_CERTS_DIR = ${INSTALL_ROOT}/ssl_share/mail_service

-include Makefile.local

REPLACE_ADD_VAR += USE_STAGING

post-build-root:
	mkdir -p -m 755 "${SSL_SHARE_DIR}"
	chown "${SERVICE_USER}:${SERVICE_USER}" "${SSL_SHARE_DIR}"
	chmod 755 "${SSL_SHARE_DIR}"
	mkdir -p -m 751 "${PRODUCTION_DIR}"
	chown "${SERVICE_USER}:${SERVICE_USER}" "${PRODUCTION_DIR}"
	chmod 751 "${PRODUCTION_DIR}"
# 旧配置の accounts/certificates は production 配下へ移行します。移行先が存在する場合は安全のため停止します。
	@if [ -d "${OLD_ACCOUNTS_DIR}" ]; then \
	  if [ -e "${ACCOUNTS_DIR}" ]; then \
	    echo "ERROR: ${OLD_ACCOUNTS_DIR} と ${ACCOUNTS_DIR} が両方存在するため、自動移行できません。" >&2; \
	    exit 1; \
	  fi; \
	  mv "${OLD_ACCOUNTS_DIR}" "${ACCOUNTS_DIR}"; \
	fi
	@if [ -d "${OLD_CERTS_DIR}" ]; then \
	  if [ -e "${CERTS_DIR}" ]; then \
	    echo "ERROR: ${OLD_CERTS_DIR} と ${CERTS_DIR} が両方存在するため、自動移行できません。" >&2; \
	    exit 1; \
	  fi; \
	  mv "${OLD_CERTS_DIR}" "${CERTS_DIR}"; \
	fi
	mkdir -p -m 751 "${ACCOUNTS_DIR}"
	chown -R "${SERVICE_USER}:${SERVICE_USER}" "${ACCOUNTS_DIR}"
	chmod 751 "${ACCOUNTS_DIR}"
	mkdir -p -m 751 "${CERTS_DIR}"
	chown -R "${SERVICE_USER}:${SERVICE_USER}" "${CERTS_DIR}"
	chmod 751 "${CERTS_DIR}"
	mkdir -p -m 751 "${STAGING_DIR}"
	chown "${SERVICE_USER}:${SERVICE_USER}" "${STAGING_DIR}"
	chmod 751 "${STAGING_DIR}"
	mkdir -p -m 751 "${STAGING_ACCOUNTS_DIR}"
	chown -R "${SERVICE_USER}:${SERVICE_USER}" "${STAGING_ACCOUNTS_DIR}"
	chmod 751 "${STAGING_ACCOUNTS_DIR}"
	mkdir -p -m 751 "${STAGING_CERTS_DIR}"
	chown -R "${SERVICE_USER}:${SERVICE_USER}" "${STAGING_CERTS_DIR}"
	chmod 751 "${STAGING_CERTS_DIR}"
	mkdir -p -m 2750 "${NGINX_RP_CERTS_DIR}"
	chown "${SERVICE_USER}:nginx_rp" "${NGINX_RP_CERTS_DIR}"
	chmod 2750 "${NGINX_RP_CERTS_DIR}"
	mkdir -p -m 2750 "${MAIL_SERVICE_CERTS_DIR}"
	chown "${SERVICE_USER}:mail_service" "${MAIL_SERVICE_CERTS_DIR}"
	chmod 2750 "${MAIL_SERVICE_CERTS_DIR}"
	chmod 750 ${SERVICE_PATH}/container/scripts/*.sh

env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user

include ../mk/services.mk
