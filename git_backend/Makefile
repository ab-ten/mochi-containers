export
SERVICE_NAME = git_backend
SERVICE_USER = git_backend
NFS_GROUP_CHECK = No
REPLACE_ADD_VAR = GIT_BACKEND_PORT FCGIWRAP_CHILDREN GIT_BACKEND_SOCK_VOLUME
REPLACE_FILES_USER = \
	${SERVICE_PATH}/http_${SERVICE_NAME}.conf \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf
GID_IN_PODMAN = 101
GIT_BACKEND_PORT = 9010
FCGIWRAP_CHILDREN = 4
GIT_BACKEND_SOCK_VOLUME = git_backend_fcgi_sock

-include Makefile.local


pre-build-root:
	install -o "${SERVICE_USER}" -g "${GID_HOST_MAPPED}" -m 0640 \
	  "${SECRETS_DIR}/git_backend.htpasswd" "${SERVICE_PATH}/git_backend.htpasswd"
	install -d -o "${SERVICE_USER}" -m 0751 "${INSTALL_ROOT}/git_triggers"
	@case " ${SERVICES} " in \
		*" redmine "*) \
			redmine_gid="$$( $(MAKE) -C .. --no-print-directory redmine-get-gid )"; \
			install -d "${INSTALL_ROOT}/git_triggers/pending"; \
			install -d "${INSTALL_ROOT}/git_triggers/processing"; \
			chown "${SERVICE_USER}:$$redmine_gid" "${INSTALL_ROOT}/git_triggers" "${INSTALL_ROOT}/git_triggers/pending" "${INSTALL_ROOT}/git_triggers/processing"; \
			chmod 0751 "${INSTALL_ROOT}/git_triggers"; \
			chmod 2770 "${INSTALL_ROOT}/git_triggers/pending"; \
			chmod 0070 "${INSTALL_ROOT}/git_triggers/processing"; \
			;; \
		*) \
			;; \
	esac

post-build-user:
	podman volume inspect "${GIT_BACKEND_SOCK_VOLUME}" >/dev/null 2>&1 \
		|| podman volume create "${GIT_BACKEND_SOCK_VOLUME}" >/dev/null
	chmod 755 "${SERVICE_PATH}/scripts/create-repo.sh"

post-build-root:
	install -d -o root -g root -m 0755 "${INSTALL_ROOT}/bin"
	chmod 755 "${SERVICE_PATH}/container/"*.sh
	"${INSTALL_ROOT}/scripts/replace-deploy-vars.sh" \
	  "${SERVICE_PATH}/bin/git-backend-create-repo"
	install -o root -g root -m 0755 \
	  "${SERVICE_PATH}/bin/git-backend-create-repo" \
	  "${INSTALL_ROOT}/bin/git-backend-create-repo"

include ../mk/services.mk
