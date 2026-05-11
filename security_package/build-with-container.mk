# security_package/build-with-container.mk

ifndef MODULE
$(error MODULE is required)
endif

RPM_ARCH ?= noarch
RPM_SPEC ?= SPECS/$(RPM_NAME).spec
RPM_SOURCES ?=
RPM_NAME ?= local-mochi-security-selinux-$(MODULE)

PACKAGE_EVR_FILE ?= .package-evr-$(MODULE)
PACKAGE_EVR ?= $(shell cat "$(PACKAGE_EVR_FILE)")
RPMBUILD_DIR := rpmbuild_$(MODULE)
RPM_TARGET := ${INSTALL_ROOT}/rpms/$(RPM_NAME)-$(PACKAGE_EVR).$(RPM_ARCH).rpm
RPM_BUILD_INPUTS := \
	build.sh \
	build-with-container.mk \
	$(RPMBUILD_DIR)/VERSION.mk \
	$(addprefix $(RPMBUILD_DIR)/,$(RPM_SPEC) $(RPM_SOURCES))

.PHONY: module_build

module_build: $(RPM_TARGET)

$(RPM_TARGET): $(RPM_BUILD_INPUTS)
	podman run --rm \
	  -e RPM_NAME="$(RPM_NAME)" \
	  -e RPM_SPEC="$(RPM_SPEC)" \
	  -v ${CWD}/build.sh:/build.sh:ro,Z \
	  -v ${CWD}/$(RPMBUILD_DIR):/rpmbuild:rw,Z \
	  -v ${CWD}/out:/out:rw,Z \
	  -w /rpmbuild \
	  "localhost/${SERVICE_NAME}:dev" \
	  bash /build.sh
	install -m 644 ${CWD}/out/$(RPM_NAME)-$(PACKAGE_EVR).$(RPM_ARCH).rpm $@
	@printf '\033[31m%s\033[0m\n' "rpm 更新後はインストールと再起動が必要です:"
	@printf '\033[31m%s\033[0m\n' "sudo transactional-update pkg install $@"
