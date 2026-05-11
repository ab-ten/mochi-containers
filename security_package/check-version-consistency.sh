#!/usr/bin/env bash
set -euo pipefail

RPMBUILD_DIR="${1:?usage: check-version-consistency.sh rpmbuild_<module>}"
VERREL="${RPMBUILD_DIR}/VERSION.mk"
SPEC="${RPMBUILD_DIR}/$(make -s -f "$VERREL" print-rpm-spec)"
mapfile -t VERSION_CHECK_INPUTS < <(make -s -f "$VERREL" print-rpm-version-check-inputs)
VERSION_CHECK_PATHS=()
for input in "${VERSION_CHECK_INPUTS[@]}"; do
  VERSION_CHECK_PATHS+=("${RPMBUILD_DIR}/${input}")
done

git="git -c safe.directory=$(realpath ..)"
changed_core="$($git diff --name-only -- "${VERSION_CHECK_PATHS[@]}")"
changed_ver="$($git diff --name-only -- "$VERREL")"

if [ -n "$changed_core" ] && [ -z "$changed_ver" ]; then
  echo "ERROR: ${RPMBUILD_DIR} inputs changed but VERSION/RELEASE not bumped."
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
