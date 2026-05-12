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

.PHONY: module_build

module_build: $(RPM_TARGET)

# RPM の更新判定は EVR に対応する成果物ファイルの有無で行います。
# policy source、spec、ビルドシステムを変更した場合は、対象 VERSION.mk の EVR を更新してください。
$(RPM_TARGET):
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
