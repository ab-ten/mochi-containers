#!/usr/bin/env bash
set -euo pipefail

# Ensure rpmbuild tree exists when called from a fresh checkout
mkdir -p /rpmbuild/BUILD /rpmbuild/BUILDROOT /rpmbuild/RPMS /rpmbuild/SRPMS

PKGVER="$(make -s -f VERSION.mk print-pkgver)"
PKGREL="$(make -s -f VERSION.mk print-pkgrel)"

# Build
rpmbuild -bb \
  --define "_topdir /rpmbuild" \
  --define "pkgver ${PKGVER}" \
  --define "pkgrelease ${PKGREL}" \
  /rpmbuild/SPECS/local-mochi-security-selinux.spec

# Export artifacts
mkdir -p /out
find /rpmbuild/RPMS -name '*.rpm' -type f -print -exec cp -a {} /out/ \;
#find /rpmbuild/SRPMS -name '*.src.rpm' -type f -print -exec cp -a {} /out/ \;
