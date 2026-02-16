# trilium/Makefile
export
SERVICE_NAME = trilium
SERVICE_USER = trilium
EARLY_STOP = Yes
NFS_GROUP_CHECK = No
DBFILE_DIR = ${INSTALL_ROOT}/trilium_db
REPLACE_ADD_VAR = TRILIUM_PORT DBFILE_DIR
REPLACE_FILES_USER = \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf
UID_IN_PODMAN = 1000
GID_IN_PODMAN = 1000
TRILIUM_PORT = 9002

-include Makefile.local


ifeq ($(shell id -u),0)

pre-build-root:
	@set -e; \
	install -d -m 0700 -o ${SERVICE_USER} -g ${SERVICE_USER} "${DBFILE_DIR}"; \
	dir="${NFS_ROOT}/${SERVICE_NAME}"; \
	uid="${UID_HOST_MAPPED}"; \
	gid="${GID_HOST_MAPPED}"; \
	if [ -z "$$uid" ] || [ -z "$$gid" ]; then \
		echo "ERROR: UID/GID のマップが取得できません。"; \
		exit 1; \
	fi; \
	if ! command -v setpriv >/dev/null 2>&1; then \
		echo "ERROR: setpriv が見つかりません。util-linux をインストールしてください。"; \
		exit 1; \
	fi; \
	if ! test -d "$$dir"; then \
		if ! install -d -o "${SERVICE_USER}" -g "$$gid" -m 2770 "$$dir"; then \
			echo "ERROR: 必要なディレクトリが存在しません。作成に失敗しました。 $$dir"; \
			echo "ERROR: $$dir が NFS の場合は UsersSetup.md を参照し NFS サーバー側でディレクトリを作成してください。"; \
			exit 1; \
		fi; \
	fi; \
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


include ../mk/services.mk
