# nextcloud/Makefile
export
SERVICE_NAME = redmine
SERVICE_USER = redmine
NFS_GROUP_CHECK = No
REPLACE_ADD_VAR = REDMINE_PORT
REPLACE_FILES_USER = \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf
UID_IN_PODMAN = 999
GID_IN_PODMAN = 999
REDMINE_PORT = 9001

-include Makefile.local

ifeq ($(shell id -u),0)

UID_NC := $(shell cd / && sudo -u "${SERVICE_USER}" -H -- \
  podman unshare awk -v id=${UID_IN_PODMAN} '$$1<=id && id<($$1+$$3){print $$2+(id-$$1); exit}' /proc/self/uid_map)
GID_NC := $(shell cd / && sudo -u "${SERVICE_USER}" -H -- \
  podman unshare awk -v id=${GID_IN_PODMAN} '$$1<=id && id<($$1+$$3){print $$2+(id-$$1); exit}' /proc/self/gid_map)

print-uid-gid:
	@echo "UID_NC: ${UID_NC}"
	@echo "GID_NC: ${GID_NC}"

pre-build-root:
	@set -e; \
	dir="${NFS_ROOT}/${SERVICE_NAME}"; \
	uid="${UID_NC}"; \
	gid="${GID_NC}"; \
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
		setpriv --reuid=`id -u ${SERVICE_USER}` --regid="$$gid" --clear-groups -- \
			sh -c "umask 006; mkdir -p '$$dir/files'"; \
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
