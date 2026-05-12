RPM_NAME := local-mochi-security-selinux-mail_service
RPM_SPEC := SPECS/local-mochi-security-selinux.spec
RPM_SOURCES := SOURCES/local_mochi_mail_service_security.te
RPM_VERSION_CHECK_INPUTS := SOURCES/local_mochi_mail_service_security.te ${RPM_SPEC}
RPM_ARCH := noarch
PKGVER := 1.0
PKGREL := 1


print-evr:
	@echo "${PKGVER}-${PKGREL}"

print-pkgver:
	@echo "${PKGVER}"

print-pkgrel:
	@echo "${PKGREL}"

print-rpm-name:
	@echo "${RPM_NAME}"

print-rpm-spec:
	@echo "${RPM_SPEC}"

print-rpm-version-check-inputs:
	@printf '%s\n' ${RPM_VERSION_CHECK_INPUTS}

print-rpm-arch:
	@echo "${RPM_ARCH}"
