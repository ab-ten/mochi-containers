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
SLACK_NOTIFICATION = Yes

-include Makefile.local

ifeq ($(shell id -u),0)
pre-build-root:
	@set -e; \
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
		setpriv --reuid=`id -u ${SERVICE_USER}` --regid="$$gid" --clear-groups -- \
			sh -c "umask 006; mkdir -p '$$dir/files'"; \
		setpriv --reuid="$$uid" --regid="$$gid" --clear-groups -- sh -c "rm '$$tmpfile'"; \
	else \
		echo "ERROR: UID_IN_PODMAN:GID_IN_PODMAN (${UID_IN_PODMAN}:${GID_IN_PODMAN}) で $$dir に書き込みできません。"; \
		echo "対処: chgrp -R $$gid '$$dir'"; \
		echo "対処: chmod -R g+rwX '$$dir'"; \
		exit 1; \
	fi; \
	case " ${SERVICES} " in \
		*" git_backend "*) \
			git_repo_dir="${NFS_ROOT}/git_backend/repos"; \
			if ! test -d "$$git_repo_dir"; then \
				echo "ERROR: git_backend が SERVICES に含まれますが、$$git_repo_dir が存在しません。"; \
				exit 1; \
			fi; \
			if setpriv --reuid="$$uid" --regid="$$gid" --clear-groups -- \
				sh -c "test -r '$$git_repo_dir' && test -x '$$git_repo_dir' && ls -1 '$$git_repo_dir' >/dev/null"; then \
				:; \
			else \
				echo "ERROR: UID_IN_PODMAN:GID_IN_PODMAN (${UID_IN_PODMAN}:${GID_IN_PODMAN}) 相当権限で $$git_repo_dir を読み取れません。"; \
				echo "対処: chgrp -R $$gid '$$git_repo_dir'"; \
				echo "対処: chmod -R g+rX '$$git_repo_dir'"; \
				exit 1; \
			fi; \
			;; \
	esac

post-build-root:
	chmod 755 "${SERVICE_PATH}/container/git_triggers/"*.rb "${SERVICE_PATH}/container/git_triggers/"*.sh


endif


env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user


include ../mk/services.mk
