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

function _ensure_k3sup() {
  if command -v k3sup >/dev/null 2>&1; then
    return 0
  fi
  _info "[gcp] k3sup not found — installing..."
  if _command_exist brew; then
    _run_command --soft -- brew install k3sup
    if command -v k3sup >/dev/null 2>&1; then
      return 0
    fi
  fi
  if _command_exist curl; then
    local _k3sup_installer
    _k3sup_installer="$(mktemp)"
    if ! curl -fsSL -o "${_k3sup_installer}" https://get.k3sup.dev; then
      rm -f "${_k3sup_installer}"
      _err "[gcp] Failed to download k3sup installer"
      return 1
    fi
    mkdir -p "${HOME}/.local/bin"
    INSTALL_PATH="${HOME}/.local/bin" \
      _run_command --soft -- sh "${_k3sup_installer}"
    rm -f "${_k3sup_installer}"
    if command -v k3sup >/dev/null 2>&1; then
      return 0
    fi
    if [[ -f "${HOME}/.local/bin/k3sup" ]]; then
      export PATH="${HOME}/.local/bin:${PATH}"
      return 0
    fi
  fi
  _err "[gcp] k3sup not found and automatic installation failed — install manually: brew install k3sup"
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

function gcp_login() {
  local expected_user="${1:-${GCP_USERNAME:-}}"
  if [[ -z "${expected_user}" ]]; then
    _err "[gcp] gcp_login: GCP_USERNAME not set"
    return 1
  fi

  local active_account
  active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)

  if [[ "${active_account}" == "${expected_user}" ]]; then
    _info "[gcp] CLI already authenticated as ${expected_user}"
    return 0
  fi

  # Account exists in credential store but is not active — switch without browser
  if gcloud auth list --format="value(account)" 2>/dev/null | grep -qF "${expected_user}"; then
    gcloud config set account "${expected_user}" --quiet
    _info "[gcp] Switched active gcloud account to ${expected_user}"
    return 0
  fi

  # Account not in store — need interactive login (browser will open once; token is cached)
  _info "[gcp] Authenticating as ${expected_user} (browser will open)..."
  if ! gcloud auth login --account "${expected_user}"; then
    _err "[gcp] Failed to authenticate as ${expected_user}"
    return 1
  fi
}

function gcp_grant_compute_admin() {
  local project="${1:-${GCP_PROJECT:-}}"
  local key_file="${2:-${GOOGLE_APPLICATION_CREDENTIALS:-}}"
  local username="${GCP_USERNAME:-}"

  if [[ -z "${project}" ]]; then
    _err "[gcp] gcp_grant_compute_admin: GCP_PROJECT not set"
    return 1
  fi
  if [[ -z "${key_file}" || ! -f "${key_file}" ]]; then
    _err "[gcp] gcp_grant_compute_admin: key file not found: ${key_file}"
    return 1
  fi
  if [[ -z "${username}" ]]; then
    _err "[gcp] gcp_grant_compute_admin: GCP_USERNAME not set (needed for identity guard)"
    return 1
  fi

  local sa_email
  sa_email=$(jq -r '.client_email' "${key_file}" 2>/dev/null)
  if [[ -z "${sa_email}" || "${sa_email}" == "null" ]]; then
    _err "[gcp] gcp_grant_compute_admin: could not extract client_email from ${key_file}"
    return 1
  fi

  _info "[gcp] Ensuring CLI is authenticated as sandbox user ${username}..."
  gcp_login "${username}" || return 1

  _info "[gcp] Granting roles/compute.admin to ${sa_email} on project ${project}..."
  if ! gcloud projects add-iam-policy-binding "${project}" \
    --member="serviceAccount:${sa_email}" \
    --role="roles/compute.admin" \
    --condition=None \
    --quiet >/dev/null; then
    _err "[gcp] IAM grant failed — check that ${username} has roles/resourcemanager.projectIamAdmin or Owner on ${project}"
    return 1
  fi

  _info "[gcp] roles/compute.admin granted to ${sa_email} (idempotent)"
}
