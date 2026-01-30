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


ifeq ("${CWD}","${SERVICE_PATH}")
PACKAGE_EVR := $(shell cat .package-evr)
else
PACKAGE_EVR := pkg-evr-error
endif

RPM_TARGET := ${INSTALL_ROOT}/rpms/local-mochi-security-selinux-${PACKAGE_EVR}.noarch.rpm
RPM_BUILD_INPUTS := rpmbuild/build.sh rpmbuild/VERSION.mk rpmbuild/SPECS/local-mochi-security-selinux.spec rpmbuild/SOURCES/local_mochi_security.te

.PHONY: pre-build-root post-build-user build-rpm


pre-build-root:
	install -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 755 ../LICENSE ${SERVICE_PATH}/rpmbuild/SOURCES/
	install -d -m 755 -o "${SERVICE_USER}" -g "${SERVICE_USER}" ${INSTALL_ROOT}/rpms
	./check-version-consistency.sh
	make -s -f rpmbuild/VERSION.mk print-evr > ${SERVICE_PATH}/.package-evr

#

post-build-user: build-rpm
	@true

build-rpm: ${RPM_TARGET}

${RPM_TARGET}: ${RPM_BUILD_INPUTS}  #| ${INSTALL_ROOT}/rpms
	sudo -u "${SERVICE_USER}" \
	  podman run --rm \
	  -v ${CWD}/rpmbuild:/rpmbuild:rw,Z \
	  -v ${CWD}/out:/out:rw,Z \
	  -w /rpmbuild \
	  "localhost/${SERVICE_NAME}:dev" \
	  bash /rpmbuild/build.sh
	install -m 644 ${CWD}/out/local-mochi-security-selinux-${PACKAGE_EVR}.noarch.rpm $@
	@printf '\033[31m%s\033[0m\n' "rpm 更新後はインストールと再起動が必要です:"
	@printf '\033[31m%s\033[0m\n' "sudo transactional-update pkg install $@"

#

print-spec-user-name:
	@echo "${SPEC_USER_NAME}"

print-spec-email:
	@echo "${SPEC_EMAIL_ADDRESS}"


include ../mk/services.mk
