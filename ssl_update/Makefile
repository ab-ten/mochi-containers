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
SSL_UPDATE_CLIENTS = nginx_rp mail_service
SERVICE_REPO_DIR ?= $(if $(BASE_REPO_DIR),$(BASE_REPO_DIR),..)

-include Makefile.local

SSL_UPDATE_ACTIVE_CLIENTS ?= $(filter $(SERVICES),$(SSL_UPDATE_CLIENTS))

REPLACE_ADD_VAR += USE_STAGING SSL_UPDATE_ACTIVE_CLIENTS

post-build-root:
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0755 "${SSL_SHARE_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${PRODUCTION_DIR}"
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
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${ACCOUNTS_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${CERTS_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${STAGING_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${STAGING_ACCOUNTS_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${STAGING_CERTS_DIR}"
	@for client in ${SSL_UPDATE_ACTIVE_CLIENTS}; do \
	  client_group="$$( $(MAKE) -C "${SERVICE_REPO_DIR}" --no-print-directory "$${client}-get-service-group" )"; \
	  if [ -z "$${client_group}" ]; then \
	    echo "ERROR: SERVICE_GROUP is empty for $${client}" >&2; \
	    exit 1; \
	  fi; \
	  install -d -o "${SERVICE_USER}" -g "$${client_group}" -m 2750 "${SSL_SHARE_DIR}/$${client}"; \
	done
	chmod 750 ${SERVICE_PATH}/container/scripts/*.sh

env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user

include ../mk/services.mk
