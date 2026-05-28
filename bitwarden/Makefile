# bitwarden/Makefile
export
SERVICE_NAME = bitwarden
SERVICE_USER = bitwarden
NFS_GROUP_CHECK = No
BITWARDEN_PORT = 9003
BITWARDEN_DATA_DIR = ${NFS_ROOT}/bitwarden/data
UID_IN_PODMAN = 1000
GID_IN_PODMAN = 1000
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
	@set -e; \
	parent="${NFS_ROOT}/${SERVICE_NAME}"; \
	dir="${BITWARDEN_DATA_DIR}"; \
	uid="${UID_HOST_MAPPED}"; \
	gid="${GID_HOST_MAPPED}"; \
	service_uid=`id -u ${SERVICE_USER}`; \
	if [ -z "$$uid" ] || [ -z "$$gid" ]; then \
		echo "ERROR: UID/GID のマップが取得できません。"; \
		exit 1; \
	fi; \
	if ! command -v setpriv >/dev/null 2>&1; then \
		echo "ERROR: setpriv が見つかりません。util-linux をインストールしてください。"; \
		exit 1; \
	fi; \
	if ! test -d "$$parent"; then \
		if ! install -d -o "${SERVICE_USER}" -g "$$gid" -m 2770 "$$parent"; then \
			echo "ERROR: 必要なディレクトリが存在しません。作成に失敗しました。 $$parent"; \
			echo "ERROR: $$parent が NFS の場合は UsersSetup.md を参照し NFS サーバー側でディレクトリを作成してください。"; \
			exit 1; \
		fi; \
	fi; \
	chmod 2770 "$$parent" 2>/dev/null || true; \
	if ! test -d "$$dir"; then \
		if ! setpriv --reuid="$$service_uid" --regid="$$gid" --clear-groups -- \
			sh -c "umask 007; install -d -m 2770 '$$dir'"; then \
			echo "ERROR: 必要なディレクトリが存在しません。作成に失敗しました。 $$dir"; \
			echo "ERROR: $$dir が NFS の場合は UsersSetup.md を参照し NFS サーバー側でディレクトリを作成してください。"; \
			exit 1; \
		fi; \
	fi; \
	chmod 2770 "$$dir" 2>/dev/null || true; \
	tmpfile="$$dir/.write_test_$$"; \
	if setpriv --reuid="$$uid" --regid="$$gid" --clear-groups -- sh -c "umask 002; : > '$$tmpfile'"; then \
		setpriv --reuid="$$uid" --regid="$$gid" --clear-groups -- sh -c "rm '$$tmpfile'"; \
	else \
		echo "ERROR: UID_IN_PODMAN:GID_IN_PODMAN (${UID_IN_PODMAN}:${GID_IN_PODMAN}) で $$dir に書き込みできません。"; \
		echo "対処: chgrp -R $$gid '$$dir'"; \
		echo "対処: chmod -R g+rwX '$$dir'"; \
		exit 1; \
	fi

endif

env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user

include ../mk/services.mk
