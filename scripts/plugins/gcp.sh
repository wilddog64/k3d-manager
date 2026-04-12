#!/usr/bin/env bash
# shellcheck shell=bash
# scripts/plugins/gcp.sh — helpers for Pluralsight GCP sandbox credentials

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLAYWRIGHT_SCRIPT="${SCRIPT_DIR}/playwright/acg_credentials.js"

function _ensure_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then
    return 0
  fi
  _info "[gcp] gcloud CLI not found — installing..."
  if _command_exist brew; then
    _run_command --soft -- brew install --cask google-cloud-sdk
    if command -v gcloud >/dev/null 2>&1; then
      return 0
    fi
  fi
  if _is_debian_family && _command_exist curl; then
    local _gcloud_installer
    _gcloud_installer="$(mktemp)"
    if ! curl -fsSL -o "${_gcloud_installer}" https://sdk.cloud.google.com; then
      rm -f "${_gcloud_installer}"
      _err "[gcp] Failed to download Google Cloud SDK installer"
      return 1
    fi
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
      _run_command --soft -- bash "${_gcloud_installer}" --disable-prompts \
        --install-dir="${HOME}/.local/share/google-cloud-sdk"
    rm -f "${_gcloud_installer}"
    if command -v gcloud >/dev/null 2>&1; then
      return 0
    fi
    local _gcloud_bin="${HOME}/.local/share/google-cloud-sdk/google-cloud-sdk/bin"
    if [[ -f "${_gcloud_bin}/gcloud" ]]; then
      export PATH="${_gcloud_bin}:${PATH}"
      return 0
    fi
  fi
  _err "[gcp] gcloud CLI not found and automatic installation failed — install manually: brew install --cask google-cloud-sdk"
  return 1
}

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
