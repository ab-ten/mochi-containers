export
SERVICE_NAME = mail_service
SERVICE_USER = mail_service
NFS_GROUP_CHECK = No
UID_IN_PODMAN = 100
GID_IN_PODMAN = 102

MAIL_DOMAIN ?= ${CERT_DOMAIN}
MAIL_HOSTNAME ?= mail.${MAIL_DOMAIN}
MAIL_MYNETWORKS ?= 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
MAIL_SMTP_BACKEND_PORT ?= 2525
MAIL_POP3_BACKEND_PORT ?= 8110
MAIL_SMTP_PUBLIC_PORT ?= 25
MAIL_POP3_PUBLIC_PORT ?= 110
MAIL_STATE_DIR ?= ${INSTALL_ROOT}/mail_service_state
MAIL_MAILDIR ?= ${MAIL_STATE_DIR}/maildir
MAIL_QUEUEDIR ?= ${MAIL_STATE_DIR}/postfix-queue
MAIL_SOCKET_VOLUME ?= mail_service_sockets

REPLACE_ADD_VAR = \
	MAIL_DOMAIN \
	MAIL_HOSTNAME \
	MAIL_MYNETWORKS \
	MAIL_SMTP_BACKEND_PORT \
	MAIL_POP3_BACKEND_PORT \
	MAIL_SMTP_PUBLIC_PORT \
	MAIL_POP3_PUBLIC_PORT \
	MAIL_MAILDIR \
	MAIL_QUEUEDIR \
	MAIL_SOCKET_VOLUME

REPLACE_FILES_USER = \
	${SERVICE_PATH}/generated/postfix/main.cf \
	${SERVICE_PATH}/generated/postfix/master.cf \
	${SERVICE_PATH}/generated/postfix/virtual_mailbox \
	${SERVICE_PATH}/generated/postfix/virtual_alias \
	${SERVICE_PATH}/generated/postfix/transport \
	${SERVICE_PATH}/generated/postfix/relay_sasl_passwd \
	${SERVICE_PATH}/generated/dovecot/dovecot.conf

-include Makefile.local

pre-build-root:
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${MAIL_STATE_DIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${MAIL_MAILDIR}"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${MAIL_QUEUEDIR}"
	MAIL_SMTP_BACKEND_PORT="${MAIL_SMTP_BACKEND_PORT}" \
	  MAIL_POP3_BACKEND_PORT="${MAIL_POP3_BACKEND_PORT}" \
	  bash "${SERVICE_PATH}/scripts/configure-selinux-ports.sh"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${SERVICE_PATH}/generated/postfix"
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${SERVICE_PATH}/generated/dovecot"
	install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	  "${SERVICE_PATH}/config/postfix/main.cf" \
	  "${SERVICE_PATH}/generated/postfix/main.cf"
	install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	  "${SERVICE_PATH}/config/postfix/master.cf" \
	  "${SERVICE_PATH}/generated/postfix/master.cf"
	install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	  "${SERVICE_PATH}/config/dovecot/dovecot.conf" \
	  "${SERVICE_PATH}/generated/dovecot/dovecot.conf"
	install -o "${UID_HOST_MAPPED}" -g "${GID_HOST_MAPPED}" -m 0640 \
	  "${SECRETS_DIR}/mail_service/users.passwd" \
	  "${SERVICE_PATH}/generated/dovecot/users.passwd"
	install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	  "${SECRETS_DIR}/mail_service/virtual_mailbox" \
	  "${SERVICE_PATH}/generated/postfix/virtual_mailbox"
	@if [ -f "${SECRETS_DIR}/mail_service/virtual_alias" ]; then \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	    "${SECRETS_DIR}/mail_service/virtual_alias" \
	    "${SERVICE_PATH}/generated/postfix/virtual_alias"; \
	else \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	    /dev/null "${SERVICE_PATH}/generated/postfix/virtual_alias"; \
	fi
	@if [ -f "${SECRETS_DIR}/mail_service/transport" ]; then \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	    "${SECRETS_DIR}/mail_service/transport" \
	    "${SERVICE_PATH}/generated/postfix/transport"; \
	else \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0640 \
	    /dev/null "${SERVICE_PATH}/generated/postfix/transport"; \
	fi
	@if [ -f "${SECRETS_DIR}/mail_service/relay_sasl_passwd" ]; then \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0600 \
	    "${SECRETS_DIR}/mail_service/relay_sasl_passwd" \
	    "${SERVICE_PATH}/generated/postfix/relay_sasl_passwd"; \
	else \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0600 \
	    /dev/null "${SERVICE_PATH}/generated/postfix/relay_sasl_passwd"; \
	fi

post-build-user:
	podman volume inspect "${MAIL_SOCKET_VOLUME}" >/dev/null 2>&1 \
		|| podman volume create "${MAIL_SOCKET_VOLUME}" >/dev/null
	podman run --rm --entrypoint postmap \
	  -v "${SERVICE_PATH}/generated/postfix:/work:Z" \
	  localhost/${SERVICE_NAME}-postfix:dev \
	  /work/virtual_mailbox
	podman run --rm --entrypoint postmap \
	  -v "${SERVICE_PATH}/generated/postfix:/work:Z" \
	  localhost/${SERVICE_NAME}-postfix:dev \
	  /work/virtual_alias
	podman run --rm --entrypoint postmap \
	  -v "${SERVICE_PATH}/generated/postfix:/work:Z" \
	  localhost/${SERVICE_NAME}-postfix:dev \
	  /work/transport
	podman run --rm --entrypoint postmap \
	  -v "${SERVICE_PATH}/generated/postfix:/work:Z" \
	  localhost/${SERVICE_NAME}-postfix:dev \
	  /work/relay_sasl_passwd

post-build-root:
	install -d -o root -g root -m 0755 "${INSTALL_ROOT}/bin"
	"${INSTALL_ROOT}/scripts/replace-deploy-vars.sh" \
	  "${SERVICE_PATH}/bin/mail-service-create-user-passwd"
	install -o root -g root -m 0755 \
	  "${SERVICE_PATH}/bin/mail-service-create-user-passwd" \
	  "${INSTALL_ROOT}/bin/mail-service-create-user-passwd"

include ../mk/services.mk
