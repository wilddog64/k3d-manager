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

  local project key_path username password
  project=$(printf '%s\n' "${output}" | grep '^GCP_PROJECT=' | cut -d= -f2-)
  key_path=$(printf '%s\n' "${output}" | grep '^GOOGLE_APPLICATION_CREDENTIALS=' | cut -d= -f2-)
  username=$(printf '%s\n' "${output}" | grep '^GCP_USERNAME=' | cut -d= -f2-)
  password=$(printf '%s\n' "${output}" | grep '^GCP_PASSWORD=' | cut -d= -f2-)

  if [[ -z "${project}" || "${project}" == "None" || "${project}" == "null" ]]; then
    _err "[gcp] Could not extract GCP_PROJECT from Playwright output"
    return 1
  fi
  if [[ -z "${key_path}" || ! -f "${key_path}" ]]; then
    _err "[gcp] GOOGLE_APPLICATION_CREDENTIALS not set or key file not found: ${key_path}"
    return 1
  fi

  export GCP_PROJECT="${project}"
  export GOOGLE_APPLICATION_CREDENTIALS="${key_path}"
  export GCP_USERNAME="${username}"
  export GCP_PASSWORD="${password}"

  _info "[gcp] GCP_PROJECT=${project}"
  _info "[gcp] GOOGLE_APPLICATION_CREDENTIALS=${key_path}"
}
