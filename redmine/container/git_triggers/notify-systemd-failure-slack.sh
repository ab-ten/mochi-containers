#!/usr/bin/env bash

set -euo pipefail

unit_name="${1:-redmine-git-triggers-worker.service}"
service_result="${MONITOR_SERVICE_RESULT:-unknown}"
exit_code="${MONITOR_EXIT_CODE:-unknown}"
exit_status="${MONITOR_EXIT_STATUS:-unknown}"

if [ -z "${SLACK_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL:-}" ]; then
  echo "notify-systemd-failure-slack: SLACK_TOKEN or SLACK_CHANNEL is not set; skip notification" >&2
  exit 0
fi

text="Systemd unit failed: ${unit_name} (result=${service_result}, exit_code=${exit_code}, exit_status=${exit_status})"

curl -fsS -X POST 'https://slack.com/api/chat.postMessage' \
  -d "token=${SLACK_TOKEN}" \
  -d "channel=${SLACK_CHANNEL}" \
  -d "text=${text}"
