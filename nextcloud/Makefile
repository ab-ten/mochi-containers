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

UID_NC := $(shell cd / && sudo -u "${SERVICE_USER}" -H -- \
  podman unshare awk -v id=${UID_IN_PODMAN} '$$1<=id && id<($$1+$$3){print $$2+(id-$$1); exit}' /proc/self/uid_map)
GID_NC := $(shell cd / && sudo -u "${SERVICE_USER}" -H -- \
  podman unshare awk -v id=${GID_IN_PODMAN} '$$1<=id && id<($$1+$$3){print $$2+(id-$$1); exit}' /proc/self/gid_map)

print-uid-gid:
	@echo "UID_NC: ${UID_NC}"
	@echo "GID_NC: ${GID_NC}"

pre-build-root:
	install -d -o ${UID_NC} -g ${GID_NC} -m 770 \
	  "$(HTML_DIR)" "$(HTML_DIR)/app" "$(HTML_DIR)/data" "$(HTML_DIR)/config"

endif


post-build-user:
	mkdir -p -m 700 $(NFS_ROOT)/$(SERVICE_NAME)/app \
		$(NFS_ROOT)/$(SERVICE_NAME)/data \
		$(NFS_ROOT)/$(SERVICE_NAME)/config


env-files-user: ${SERVICE_PATH}/${SERVICE_NAME}.env-user


include ../mk/services.mk
