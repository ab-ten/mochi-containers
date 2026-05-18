#!/usr/bin/env bash

set -euo pipefail

repo_name="${1:-${GIT_TRIGGERS_REPO_NAME:-unknown}}"
error_message="${2:-${GIT_TRIGGERS_ERROR_MESSAGE:-unknown error}}"

if [ -z "${SLACK_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL:-}" ]; then
  echo "notify-slack: SLACK_TOKEN or SLACK_CHANNEL is not set; skip notification" >&2
  exit 0
fi

text="Redmine git trigger failed for ${repo_name}: ${error_message}"

curl -fsS -X POST 'https://slack.com/api/chat.postMessage' \
  -d "token=${SLACK_TOKEN}" \
  -d "channel=${SLACK_CHANNEL}" \
  --data-urlencode "text=${text}" || true

# curl が失敗してもエラーにはしない
exit 0
