#!/usr/bin/env bash
# scripts/plugins/gcp.sh — GCP sandbox credential extraction and surgical auth
#
# Functions: gcp_get_credentials gcp_login gcp_revoke
# Invoked by: scripts/lib/providers/k3s-gcp.sh (Phase D or later)
#
# Design notes (v1.1.0 recovery):
#   - Never launches, restarts, or kills Chrome. Relies on the CDP launchd job
#     managed by scripts/plugins/acg.sh (_acg_chrome_cdp_*).
#   - GCP SA key is consumed via GOOGLE_APPLICATION_CREDENTIALS env var (ADC).
#     We do NOT run `gcloud auth activate-service-account` globally because that
#     overwrites the user's CLI identity.
#   - `gcp_login` performs a one-time `gcloud auth login` for the extracted
#     cloud_user account (latch-on). Subsequent runs detect the account is
#     already in the credential store and switch to it without a browser.
#   - `gcp_revoke` revokes ONLY the specified account. Never `--all`.

if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/etc/playwright/vars.sh"

_GCP_SA_KEY_PATH="${HOME}/.local/share/k3d-manager/gcp-service-account.json"
_GCP_SANDBOX_URL="${GCP_SANDBOX_URL:-${PLAYWRIGHT_URL_GCP}}"

_gcp_ensure_node() {
  if command -v node >/dev/null 2>&1; then
    return 0
  fi

  if declare -f _ensure_node >/dev/null 2>&1; then
    _ensure_node || return 1
  fi

  if command -v node >/dev/null 2>&1; then
    return 0
  fi

  printf 'ERROR: %s\n' "[gcp] node is required for Playwright automation" >&2
  return 1
}

function gcp_get_credentials() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<HELP
Usage: gcp_get_credentials [sandbox-url]

Extract GCP sandbox credentials (project, username, password, SA key path)
from the Pluralsight Cloud Sandbox "Cloud Access" panel via Chrome CDP.
Writes the service account JSON to ~/.local/share/k3d-manager/gcp-service-account.json.

Exports: GCP_PROJECT, GCP_USERNAME, GCP_PASSWORD, GOOGLE_APPLICATION_CREDENTIALS

Arguments:
  sandbox-url   (optional) URL of the GCP sandbox (defaults to PLAYWRIGHT_URL_GCP)
HELP
    return 0
  fi

  local sandbox_url="${1:-${_GCP_SANDBOX_URL}}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local playwright_script="${script_dir}/../playwright/acg_credentials.js"

  _gcp_ensure_node || return 1
  if ! node -e "require('playwright')" 2>/dev/null; then
    printf 'ERROR: %s\n' "[gcp] playwright npm module not found — run: cd scripts/playwright && npm install" >&2
    return 1
  fi

  if ! curl -sf "http://${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}/json" >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[gcp] Chrome CDP not reachable on ${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}." >&2
    printf 'ERROR: %s\n' "[gcp] Run: ./scripts/k3d-manager acg_chrome_cdp_install" >&2
    printf 'ERROR: %s\n' "[gcp] Then sign in to Pluralsight once in that Chrome window." >&2
    return 1
  fi

  _info "[gcp] Extracting GCP credentials from ${sandbox_url}..."

  local creds_tmp
  creds_tmp=$(mktemp -t k3dm-gcp-creds.XXXXXX)
  chmod 600 "${creds_tmp}"

  # Execute extraction; robot writes sensitive fields to creds_tmp
  # stdout only contains non-sensitive INFO/DIAGNOSTIC logs.
  PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
  PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
  PLAYWRIGHT_AUTH_DIR="${PLAYWRIGHT_AUTH_DIR}" \
  PLAYWRIGHT_CREDS_FILE="${creds_tmp}" \
  node "${playwright_script}" "${sandbox_url}" --provider gcp

  if [[ ! -s "${creds_tmp}" ]]; then
    printf 'ERROR: %s\n' "[gcp] Extraction failed — credential file is empty" >&2
    rm -f "${creds_tmp}"
    return 1
  fi

  # Load credentials into shell memory (not stdout) and immediately scrub the file
  # shellcheck source=/dev/null
  source "${creds_tmp}"
  rm -f "${creds_tmp}"

  # Map extracted vars to canonical names
  local project="${GCP_PROJECT:-}"
  local key_path="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  local username="${GCP_USERNAME:-}"
  local password="${GCP_PASSWORD:-}"

  if [[ -z "${project}" || "${project}" == "None" || "${project}" == "null" ]]; then
    printf 'ERROR: %s\n' "[gcp] Could not extract GCP_PROJECT" >&2
    return 1
  fi
  if [[ -z "${key_path}" || ! -f "${key_path}" ]]; then
    printf 'ERROR: %s\n' "[gcp] Service account key not written: ${key_path}" >&2
    return 1
  fi

  export GCP_PROJECT="${project}"
  export GOOGLE_APPLICATION_CREDENTIALS="${key_path}"
  export GCP_USERNAME="${username}"
  export GCP_PASSWORD="${password}"

  _info "[gcp] GCP_PROJECT=${project}"
  _info "[gcp] GOOGLE_APPLICATION_CREDENTIALS=${key_path}"

  # Final Step: Trigger the identity switch to unblock SSH and management
  gcp_login "${username}"
}

function _gcp_capture_auth_url() {
  local account="$1"
  local url_file="$2"
  local url=""
  local i

  gcloud auth login --account "${account}" >"${url_file}" 2>&1 &
  local pid=$!

  for i in $(seq 1 10); do
    url=$(grep -oE 'https://accounts\.google\.com[^[:space:]]+' "${url_file}" 2>/dev/null | head -1 || true)
    if [[ -n "${url}" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -n "${url}" ]]; then
    printf '%s' "${url}"
  fi
  return 0
}

function _gcp_perform_login_auth() {
  local account="$1"
  local playwright_dir="$2"

  if ! command -v node >/dev/null 2>&1 || ! node -e "require('playwright')" 2>/dev/null; then
    printf 'WARN: %s\n' "[gcp] node/playwright not available — gcloud auth login will require manual browser interaction" >&2
    gcloud auth login --account "${account}"
    return $?
  fi

  if [[ "$(uname)" == "Linux" ]]; then
    local _gcloud_url_file
    _gcloud_url_file=$(mktemp)
    local _auth_url
    _auth_url=$(_gcp_capture_auth_url "${account}" "${_gcloud_url_file}")
    local gcloud_pid
    gcloud_pid=$(pgrep -n -f "gcloud auth login --account ${account}")
    
    rm -f "${_gcloud_url_file}"
    if [[ -z "${_auth_url}" ]]; then
      _err "[gcp] Could not capture gcloud OAuth URL — manual gcloud auth login required"
    fi
    GCP_USERNAME="${account}" \
    GCP_AUTH_URL="${_auth_url}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    if [[ -n "$gcloud_pid" ]]; then
      wait "${gcloud_pid}"
    fi
  else
    # macOS: gcloud opens the OAuth tab in this Chrome session — Playwright waits for it
    gcloud auth login --account "${account}" &
    local gcloud_pid=$!
    GCP_USERNAME="${account}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    wait "${gcloud_pid}"
  fi
}

function gcp_login() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<HELP
Usage: gcp_login [account]

Surgical latch-on: authenticate gcloud CLI as the given account (defaults to
\$GCP_USERNAME). If the account is already in the credential store, switch to
it without launching a browser. Otherwise run \`gcloud auth login\` once.

Never runs \`activate-service-account\` — the SA key is consumed via ADC
(GOOGLE_APPLICATION_CREDENTIALS env var) by k3sup / terraform.
HELP
    return 0
  fi

  local account="${1:-${GCP_USERNAME:-}}"
  if [[ -z "${account}" ]]; then
    printf 'ERROR: %s\n' "[gcp] gcp_login: account not set (pass as arg or export GCP_USERNAME)" >&2
    return 1
  fi
  if ! command -v gcloud >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[gcp] gcloud CLI not found — install google-cloud-sdk" >&2
    return 1
  fi

  local active_account
  active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)
  if [[ "${active_account}" == "${account}" ]]; then
    _info "[gcp] CLI already authenticated as ${account}"
    return 0
  fi

  if gcloud auth list --format="value(account)" 2>/dev/null | grep -qF "${account}"; then
    gcloud config set account "${account}" --quiet
    _info "[gcp] Switched active gcloud account to ${account}"
    return 0
  fi

  _info "[gcp] Running one-time 'gcloud auth login' for ${account}..."
  local playwright_dir
  playwright_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../playwright"

  _gcp_perform_login_auth "${account}" "${playwright_dir}"
  
  _info "[gcp] Authenticated as ${account}"
}

function gcp_revoke() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<HELP
Usage: gcp_revoke <account>

Revoke credentials for the specified account ONLY. Never revokes --all.
Intended for sandbox teardown — targets either the cloud_user account or the
service account email.
HELP
    return 0
  fi

  local account="${1:-}"
  if [[ -z "${account}" ]]; then
    printf 'ERROR: %s\n' "[gcp] gcp_revoke: account argument is required (never revokes --all)" >&2
    return 1
  fi
  if ! command -v gcloud >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[gcp] gcloud CLI not found" >&2
    return 1
  fi

  gcloud auth revoke "${account}" --quiet 2>/dev/null || true
  _info "[gcp] Revoked credentials for ${account}"
}
