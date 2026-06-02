#!/bin/sh
# notify.sh — send email and/or PagerDuty alert from inside the CVE scan CronJob.
#
# Usage:
#   notify.sh info    "Title" "Message body"
#   notify.sh warning "Title" "Message body"
#   notify.sh critical "Title" "Message body"
#
# Severity mapping:
#   info     → email only
#   warning  → email + PagerDuty trigger
#   critical → email + PagerDuty trigger
#
# Credentials (all optional — missing = skip that channel):
#   SENDGRID_API_KEY       — SendGrid v3 API key
#   NOTIFICATION_EMAIL     — recipient email address
#   NOTIFICATION_FROM      — sender email address (default: argocd-cve@k3d-manager)
#   PAGERDUTY_ROUTING_KEY  — PagerDuty Events API v2 routing/integration key

set -eu

SEVERITY="${1:-info}"
TITLE="${2:-[k3d-manager] notification}"
MESSAGE="${3:-no message}"

NOTIFICATION_FROM="${NOTIFICATION_FROM:-argocd-cve@k3d-manager}"

_log() { echo "[notify] $*"; }

# --- Email via SendGrid ---
if [ -n "${SENDGRID_API_KEY:-}" ] && [ -n "${NOTIFICATION_EMAIL:-}" ]; then
  _SAFE_TITLE=$(printf '%s' "${TITLE}" | sed 's/"/\\"/g')
  _SAFE_MSG=$(printf '%s' "${MESSAGE}" | sed 's/"/\\"/g')
  _PAYLOAD=$(printf '{"personalizations":[{"to":[{"email":"%s"}]}],"from":{"email":"%s"},"subject":"[k3d-manager] %s","content":[{"type":"text/plain","value":"%s"}]}' \
    "${NOTIFICATION_EMAIL}" "${NOTIFICATION_FROM}" "${_SAFE_TITLE}" "${_SAFE_MSG}")

  _STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://api.sendgrid.com/v3/mail/send" \
    -H "Authorization: Bearer ${SENDGRID_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${_PAYLOAD}" 2>/dev/null || echo "000")

  if [ "${_STATUS}" = "202" ]; then
    _log "Email sent to ${NOTIFICATION_EMAIL} (${SEVERITY})"
  else
    _log "Email failed: HTTP ${_STATUS}"
  fi
else
  _log "Email skipped: SENDGRID_API_KEY or NOTIFICATION_EMAIL not set"
fi

# --- PagerDuty (warning and critical only) ---
if [ "${SEVERITY}" != "info" ] && [ -n "${PAGERDUTY_ROUTING_KEY:-}" ]; then
  _PD_SEVERITY="warning"
  [ "${SEVERITY}" = "critical" ] && _PD_SEVERITY="critical"

  _SAFE_TITLE=$(printf '%s' "${TITLE}" | sed 's/"/\\"/g')
  _SAFE_MSG=$(printf '%s' "${MESSAGE}" | sed 's/"/\\"/g')
  _PD_PAYLOAD=$(printf '{"routing_key":"%s","event_action":"trigger","payload":{"summary":"%s","source":"k3d-manager-oci","severity":"%s","custom_details":{"message":"%s"}}}' \
    "${PAGERDUTY_ROUTING_KEY}" "${_SAFE_TITLE}" "${_PD_SEVERITY}" "${_SAFE_MSG}")

  _PD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://events.pagerduty.com/v2/enqueue" \
    -H "Content-Type: application/json" \
    -d "${_PD_PAYLOAD}" 2>/dev/null || echo "000")

  if [ "${_PD_STATUS}" = "202" ]; then
    _log "PagerDuty triggered (${_PD_SEVERITY})"
  else
    _log "PagerDuty failed: HTTP ${_PD_STATUS}"
  fi
elif [ "${SEVERITY}" != "info" ]; then
  _log "PagerDuty skipped: PAGERDUTY_ROUTING_KEY not set"
fi
