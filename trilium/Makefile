# trilium/Makefile
export
SERVICE_NAME = trilium
SERVICE_USER = trilium
DBFILE_DIR = ${INSTALL_ROOT}/trilium_db
REPLACE_ADD_VAR = TRILIUM_PORT DBFILE_DIR
REPLACE_FILES_USER = \
	${SERVICE_PATH}/https_${SERVICE_NAME}.conf
TRILIUM_PORT = 9002

-include Makefile.local


ifeq ($(shell id -u),0)

pre-build-root:
	install -d -m 0700 -o ${SERVICE_USER} -g ${SERVICE_USER} "${DBFILE_DIR}"

endif


include ../mk/services.mk
