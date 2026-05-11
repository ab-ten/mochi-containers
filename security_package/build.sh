#!/usr/bin/env bash
set -euo pipefail

# Ensure rpmbuild tree exists when called from a fresh checkout
mkdir -p /rpmbuild/BUILD /rpmbuild/BUILDROOT /rpmbuild/RPMS /rpmbuild/SRPMS

PKGVER="$(make -s -f VERSION.mk print-pkgver)"
PKGREL="$(make -s -f VERSION.mk print-pkgrel)"
RPM_NAME="${RPM_NAME:-$(make -s -f VERSION.mk print-rpm-name)}"
RPM_SPEC="${RPM_SPEC:-$(make -s -f VERSION.mk print-rpm-spec)}"

# Build
rpmbuild -bb \
  --define "_topdir /rpmbuild" \
  --define "rpmname ${RPM_NAME}" \
  --define "pkgver ${PKGVER}" \
  --define "pkgrelease ${PKGREL}" \
  "/rpmbuild/${RPM_SPEC}"

# Export artifacts
mkdir -p /out
find /rpmbuild/RPMS -name '*.rpm' -type f -print -exec cp -a {} /out/ \;
#find /rpmbuild/SRPMS -name '*.src.rpm' -type f -print -exec cp -a {} /out/ \;
