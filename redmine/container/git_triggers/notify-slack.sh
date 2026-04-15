#!/usr/bin/env bash

set -euo pipefail

repo_name="${1:-${GIT_TRIGGERS_REPO_NAME:-unknown}}"
error_message="${2:-${GIT_TRIGGERS_ERROR_MESSAGE:-unknown error}}"

: "${SLACK_TOKEN:?SLACK_TOKEN is required}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL is required}"

text="Redmine git trigger failed for ${repo_name}: ${error_message}"

curl -fsS -X POST 'https://slack.com/api/chat.postMessage' \
  -d "token=${SLACK_TOKEN}" \
  -d "channel=${SLACK_CHANNEL}" \
  --data-urlencode "text=${text}"

# curl が失敗してもエラーにはしない
exit 0
