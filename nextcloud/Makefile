# nextcloud/Makefile
export
SERVICE_NAME = nextcloud
SERVICE_USER = nextcloud
HTML_DIR  = ${INSTALL_ROOT}/nextcloud_html
REPLACE_ADD_VAR = HTML_DIR NEXTCLOUD_PORT
REPLACE_FILES_USER = \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf
UID_IN_PODMAN = 33
GID_IN_PODMAN = 33
NEXTCLOUD_PORT = 9000

-include Makefile.local


ifeq ($(shell id -u),0)
pre-build-root:
	install -d -o ${UID_HOST_MAPPED} -g ${GID_HOST_MAPPED} -m 770 \
	  "$(HTML_DIR)" "$(HTML_DIR)/custom_apps" "$(HTML_DIR)/data" "$(HTML_DIR)/config"

endif


post-build-user:
	mkdir -p -m 2770 $(NFS_ROOT)/$(SERVICE_NAME)/custom_apps \
		$(NFS_ROOT)/$(SERVICE_NAME)/data \
		$(NFS_ROOT)/$(SERVICE_NAME)/config


env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user


include ../mk/services.mk
