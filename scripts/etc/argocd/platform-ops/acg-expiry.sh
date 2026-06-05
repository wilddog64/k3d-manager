#!/bin/sh
# acg-expiry.sh — notify via Slack when ACG sandbox may have expired.
# Fires between ACG_EXPIRY_WARNING_SECONDS and ACG_EXPIRY_MAX_SECONDS after last provision.

set -eu

SLACK_URL="${K3DM_SLACK_WEBHOOK_URL:-}"
WARNING_S="${ACG_EXPIRY_WARNING_SECONDS:-12600}"
MAX_S="${ACG_EXPIRY_MAX_SECONDS:-28800}"
STATE_FILE="/config/acg-state/provisioned-at"
PROVIDER_FILE="/config/acg-state/provider"

if [ ! -f "${STATE_FILE}" ] || [ ! -s "${STATE_FILE}" ]; then
  exit 0
fi

PROVISIONED_AT=$(cat "${STATE_FILE}")
PROVIDER=$(cat "${PROVIDER_FILE}" 2>/dev/null || echo "aws")
NOW=$(date +%s)
AGE=$(( NOW - PROVISIONED_AT ))

if [ "${AGE}" -lt "${WARNING_S}" ]; then
  exit 0
fi

if [ "${AGE}" -gt "${MAX_S}" ]; then
  exit 0
fi

if [ -z "${SLACK_URL}" ]; then
  echo "[acg-expiry] Slack webhook URL not configured"
  exit 0
fi

AGE_H=$(( AGE / 3600 ))
AGE_M=$(( (AGE % 3600) / 60 ))

curl -sf --max-time 10 -X POST "${SLACK_URL}" \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"⏰ ACG sandbox (*${PROVIDER}*) provisioned ${AGE_H}h ${AGE_M}m ago — may have expired.\\nRun \\\`/acg-up ${PROVIDER}\\\` if you need the cluster.\"}"
