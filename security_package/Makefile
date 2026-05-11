# security_package/Makefile
export
SERVICE_NAME = security_package
SERVICE_USER = security_package
NFS_GROUP_CHECK = No
CWD = $(shell pwd)
# override with Mailefile.local
SPEC_USER_NAME = 
SPEC_EMAIL_ADDRESS = 

-include Makefile.local

RPMBUILD_DIRS := $(sort $(foreach dir,$(wildcard rpmbuild_*),$(if $(wildcard $(dir)/VERSION.mk),$(dir))))
RPM_MODULES := $(patsubst rpmbuild_%,%,$(notdir $(RPMBUILD_DIRS)))
PACKAGE_EVR_FILES := $(addprefix ${SERVICE_PATH}/.package-evr-,$(RPM_MODULES))
PACKAGE_EVR_REFRESH_TARGETS := $(addprefix refresh-package-evr-,$(RPM_MODULES))
RPM_BUILD_TARGETS := $(addprefix build-rpm-,$(RPM_MODULES))

.PHONY: FORCE pre-build-root pre-build-root-prepare-prereq-dirs post-build-user build-rpm


pre-build-root: pre-build-root-prepare-prereq-dirs $(PACKAGE_EVR_REFRESH_TARGETS)

pre-build-root-prepare-prereq-dirs:
	install -d -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" ${INSTALL_ROOT}/rpms ${SERVICE_PATH}/out
	for dir in $(RPMBUILD_DIRS); do \
	  install -d -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${SERVICE_PATH}/$${dir}/SOURCES"; \
	  install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 755 ../LICENSE "${SERVICE_PATH}/$${dir}/SOURCES/"; \
	done

refresh-package-evr-%: rpmbuild_%/VERSION.mk FORCE
	./check-version-consistency.sh "rpmbuild_$*"
	make -s -f "$<" print-evr > "${SERVICE_PATH}/.package-evr-$*"

${SERVICE_PATH}/.package-evr-%: rpmbuild_%/VERSION.mk
	./check-version-consistency.sh "rpmbuild_$*"
	make -s -f "$<" print-evr > "$@"

#

post-build-user: build-rpm
	@true

build-rpm: $(RPM_BUILD_TARGETS)

FORCE:

build-rpm-%: FORCE build.sh build-with-container.mk rpmbuild_%/VERSION.mk ${SERVICE_PATH}/.package-evr-%
	$(MAKE) --no-print-directory -f "rpmbuild_$*/VERSION.mk" -f build-with-container.mk module_build MODULE="$*"

#

print-spec-user-name:
	@echo "${SPEC_USER_NAME}"

print-spec-email:
	@echo "${SPEC_EMAIL_ADDRESS}"


include ../mk/services.mk
