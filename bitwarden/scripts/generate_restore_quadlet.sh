#!/bin/sh
# Generate a manual-only restore Quadlet from the deployed Bitwarden Quadlet.
# The output preserves image, network, environment, and necessary bind mounts.
# It does not copy [Install] or the normal application's systemd service settings.
set -eu

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s SOURCE_CONTAINER DEST_RESTORE_CONTAINER ARCHIVE_BASENAME.tar.gz\n' "$0" >&2
  exit 2
fi

source=$1
destination=$2
archive=$3

# Restrict the basename so it can be used literally in Quadlet Exec=.
case "$archive" in
  ''|*[!a-zA-Z0-9._-]*)
    echo 'Archive must be a basename containing only ASCII letters, digits, dots, underscores or hyphens' >&2
    exit 2
    ;;
esac
case "$archive" in
  ?*.tar.gz) ;;
  *) echo 'Archive basename must end in .tar.gz' >&2; exit 2 ;;
esac

[ -r "$source" ] || { echo "Cannot read source Quadlet: $source" >&2; exit 1; }
[ "$source" != "$destination" ] || { echo 'Source and destination must differ' >&2; exit 1; }

# Work in the destination directory so the replacement is on the same filesystem.
temporary=$(mktemp "${destination}.tmp.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM

awk -v archive="$archive" '
BEGIN {
  section = ""
  have_container = 0
  have_image = 0
  have_config = 0
  have_backup = 0
  have_env_file = 0

  print "#NOSTART"
  print "# Generated from bitwarden.container. Manual restore only."
  print "# No [Install] section: this unit must never run at boot."
  print "[Unit]"
  print "Description=Restore Bitwarden Lite from backup archive (manual only)"
  print ""
}
/^[[:space:]]*\[/ {
  if ($0 == "[Container]") {
    section = "container"
    have_container = 1
    print "[Container]"
  } else {
    section = "other"
  }
  next
}
section == "container" {
  # The normal service and restore service need distinct container names.
  if ($0 ~ /^[[:space:]]*(ContainerName|ServiceName|Entrypoint|Exec|PublishPort|AutoUpdate|Environment|Volume)[[:space:]]*=/) {
    if ($0 ~ /^[[:space:]]*(ContainerName|ServiceName|Entrypoint|Exec|PublishPort|AutoUpdate)[[:space:]]*=/) next
    if ($0 ~ /^[[:space:]]*Environment[[:space:]]*=[[:space:]]*RESTORE_STAGE_DIR=/) next
    if ($0 ~ /^[[:space:]]*Volume[[:space:]]*=/) {
      if ($0 ~ /backup_archive_transfer[.]sh/ || $0 ~ /\/backup_sync([: ]|$)/) next
      if ($0 ~ /:\/etc\/bitwarden([:,]|$)/) {
        have_config = 1
        if ($0 ~ /:\/etc\/bitwarden:ro([, ]|$)/) {
          print "The /etc/bitwarden mount must be writable for restore" > "/dev/stderr"
          exit 1
        }
      }
      if ($0 ~ /:\/backups([:,]|$)/) {
        have_backup = 1
        if ($0 ~ /:\/backups:ro([, ]|$)/) {
          print "The /backups mount must be writable for restore staging" > "/dev/stderr"
          exit 1
        }
      }
    }
  }
  if ($0 ~ /^[[:space:]]*Image[[:space:]]*=/) have_image = 1
  if ($0 ~ /^[[:space:]]*EnvironmentFile[[:space:]]*=/) have_env_file = 1
  print
}
END {
  if (!have_container || !have_image || !have_config || !have_backup || !have_env_file) {
    print "Source Quadlet must contain [Container], Image, EnvironmentFile, /etc/bitwarden and /backups mounts." > "/dev/stderr"
    exit 1
  }

  print "ContainerName=bitwarden-restore"
  print "Entrypoint=/restore-db.sh"
  print "Exec=/backups/" archive " --clean --yes"
  print "Environment=RESTORE_STAGE_DIR=/backups"
  print ""
  print "[Service]"
  print "Type=oneshot"
  print "RemainAfterExit=no"
  print "Restart=no"
  print "TimeoutStartSec=30min"
}
' "$source" > "$temporary"

chmod 0644 "$temporary"
mv -f "$temporary" "$destination"
trap - EXIT HUP INT TERM
printf 'Generated: %s\n' "$destination"
