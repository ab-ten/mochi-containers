# bitwarden/Makefile
export
SERVICE_NAME = bitwarden
SERVICE_USER = bitwarden
NFS_GROUP_CHECK = No
BITWARDEN_PORT = 9003
UID_IN_PODMAN = 911
GID_IN_PODMAN = 911
BITWARDEN_DATA_DIR ?= ${INSTALL_ROOT}/bitwarden_data
BITWARDEN_BACKUP_DIR ?= ${INSTALL_ROOT}/bitwarden_backup
BW_DOMAIN = bitwarden.${CERT_DOMAIN}
BW_ENABLE_SSL = false
BW_PORT_HTTP = 8080
BW_DB_PROVIDER = postgresql
BW_DB_SERVER =
BW_DB_PORT = 5432
BW_DB_DATABASE = bitwarden
BW_DB_USERNAME = bitwarden
BW_ENABLE_ADMIN = true
BW_ENABLE_API = true
BW_ENABLE_EVENTS = true
BW_ENABLE_ICONS = true
BW_ENABLE_IDENTITY = true
BW_ENABLE_NOTIFICATIONS = true
BW_ENABLE_SCIM = false
BW_ENABLE_SSO = false
globalSettings__disableUserRegistration = true
REPLACE_ADD_VAR = \
	BITWARDEN_PORT \
	BITWARDEN_DATA_DIR \
	BITWARDEN_BACKUP_DIR \
	BW_DOMAIN \
	BW_ENABLE_SSL \
	BW_PORT_HTTP \
	BW_DB_PROVIDER \
	BW_DB_SERVER \
	BW_DB_PORT \
	BW_DB_DATABASE \
	BW_DB_USERNAME \
	BW_ENABLE_ADMIN \
	BW_ENABLE_API \
	BW_ENABLE_EVENTS \
	BW_ENABLE_ICONS \
	BW_ENABLE_IDENTITY \
	BW_ENABLE_NOTIFICATIONS \
	BW_ENABLE_SCIM \
	BW_ENABLE_SSO \
	globalSettings__disableUserRegistration
REPLACE_FILES_USER = \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf

-include Makefile.local

ifeq ($(shell id -u),0)

pre-deploy-check-root:
	@set -e; \
	if [ -z "${BW_DB_SERVER}" ]; then \
		echo "ERROR: BW_DB_SERVER が未設定です。Makefile.local で外部 PostgreSQL ホストを指定してください。"; \
		exit 1; \
	fi

pre-build-root:
	if [ -z "${GID_HOST_MAPPED}" ]; then \
		echo "ERROR: GID のマップが取得できません。"; \
		exit 1; \
	fi;
	install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${BITWARDEN_DATA_DIR}"
	install -d -o "${SERVICE_USER}" -g "${GID_HOST_MAPPED}" -m 0770 "${BITWARDEN_BACKUP_DIR}"

endif

env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user

include ../mk/services.mk
