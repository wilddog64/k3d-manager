#!/usr/bin/env bash
# shellcheck shell=bash
# scripts/plugins/gcp.sh — helpers for Pluralsight GCP sandbox credentials

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLAYWRIGHT_SCRIPT="${SCRIPT_DIR}/playwright/acg_credentials.js"

function gcp_get_credentials() {
  local url="${1:-}"; shift || true
  if [[ -z "${url}" ]]; then
    _err "[gcp] Sandbox URL is required"
    return 1
  fi

  local output
  output=$(node "${PLAYWRIGHT_SCRIPT}" "${url}" --provider gcp) || {
    _err "[gcp] Failed to extract credentials via Playwright"
    return 1
  }

  GCP_PROJECT=$(printf '%s\n' "${output}" | grep '^GCP_PROJECT=' | cut -d= -f2-)
  GOOGLE_APPLICATION_CREDENTIALS=$(printf '%s\n' "${output}" | grep '^GOOGLE_APPLICATION_CREDENTIALS=' | cut -d= -f2-)
  GCP_USERNAME=$(printf '%s\n' "${output}" | grep '^GCP_USERNAME=' | cut -d= -f2-)
  GCP_PASSWORD=$(printf '%s\n' "${output}" | grep '^GCP_PASSWORD=' | cut -d= -f2-)

  export GCP_PROJECT GOOGLE_APPLICATION_CREDENTIALS GCP_USERNAME GCP_PASSWORD

  _info "[gcp] GCP_PROJECT=${GCP_PROJECT}"
  _info "[gcp] GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}"
}
