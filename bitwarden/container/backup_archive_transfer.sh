#!/bin/sh
# Transfer the newest completed Bitwarden Lite backup to /backup_sync.
# Requires /backup_sync to be an NFS bind mount writable by the container user.
# Run only one instance at a time. The previous complete archive is kept as .bak.

set -eu
LC_ALL=C
export LC_ALL
umask 077

backup_dir=/backups
sync_dir=/backup_sync
target="$sync_dir/bitwarden_backup.tar.gz"
previous="$target.bak"
temporary="$target.tmp"

if ! awk '$5 == "/backup_sync" && $0 ~ / - nfs(4)? / { found = 1 } END { exit !found }' /proc/self/mountinfo; then
  echo "Error: $sync_dir is not an NFS mount" >&2
  exit 1
fi

# nfs だと stat 系が subuid/subgid をそのまま返すのでこのチェックは false negative になる
#if [ ! -d "$sync_dir" ] || [ ! -w "$sync_dir" ]; then
#  echo "Error: $sync_dir is not writable" >&2
#  exit 1
#fi

# Bitwarden Lite archives are named with sortable UTC timestamps.
# Ignore .partial files and select the newest completed archive by name.
source=$(ls -1dt "$backup_dir"/bitwarden-*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$source" ] || [ ! -f "$source" ]; then
  echo "Error: no completed backup in $backup_dir" >&2
  exit 1
fi

# Recover if the previous run stopped between the two renames.
if [ ! -e "$target" ] && [ -f "$previous" ]; then
  mv "$previous" "$target"
  echo "Recovered previous archive: $target"
fi

# A previous interrupted copy may have left a partial temporary file.
rm -f "$temporary"

if [ -f "$target" ]; then
  if cmp -s "$source" "$target"; then
    echo "Backup unchanged: $source"
    exit 0
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "Error: cannot compare $source with $target (exit $status)" >&2
      exit 1
    fi
  fi
fi

trap 'rm -f "$temporary"' 0
trap 'exit 1' 1 2 3 15

cat "$source" > "$temporary"
if ! cmp -s "$source" "$temporary"; then
  echo "Error: copied backup differs from source" >&2
  exit 1
fi
if ! tar -tzf "$temporary" >/dev/null; then
  echo "Error: copied backup is not a valid tar.gz archive" >&2
  exit 1
fi

rm -f "$previous"
if [ -f "$target" ]; then
  mv "$target" "$previous"
fi
mv "$temporary" "$target"
trap - 0

echo "Backup transferred: $source -> $target"
