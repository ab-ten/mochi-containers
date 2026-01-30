#!/usr/bin/env bash

TE="rpmbuild/SOURCES/local_mochi_security.te"
SPEC="${1:-rpmbuild/SPECS/local-mochi-security-selinux.spec}"
VERREL="rpmbuild/VERSION.mk"

git="git -c safe.directory=$(realpath ..)"
changed_core="$($git diff --name-only -- "$TE" "$SPEC")"
changed_ver="$($git diff --name-only -- "$VERREL")"

if [ -n "$changed_core" ] && [ -z "$changed_ver" ]; then
  echo "ERROR: $TE or $SPEC changed but VERSION/RELEASE not bumped."
  exit 1
fi

current_evr="$(make -s -f "$VERREL" print-evr)"

first_changelog_line="$(awk 'BEGIN{inlog=0} /^%changelog/{inlog=1; next} inlog && /^\*/{print; exit}' "$SPEC")"

if [ -z "$first_changelog_line" ]; then
  echo "ERROR: %changelog entry not found in $SPEC"
  exit 1
fi

changelog_evr="${first_changelog_line##* - }"

if [ "$changelog_evr" != "$current_evr" ]; then
  spec_user_name="$(make -s print-spec-user-name)"
  spec_user_email="$(make -s print-spec-email)"
  current_date="$(LC_ALL=C date '+%a %b %d %Y')"
  current_date="${current_date/ 0/ }"
  echo "* $current_date $spec_user_name <$spec_user_email> - $current_evr"
  exit 1
fi
