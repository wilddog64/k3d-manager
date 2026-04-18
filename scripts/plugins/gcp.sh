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

  # Account not in store — automate OAuth via Playwright
  _info "[gcp] Authenticating as ${expected_user} via Playwright (automated)..."

  if [[ -z "${GCP_PASSWORD:-}" ]]; then
    _err "[gcp] gcp_login: GCP_PASSWORD not set — cannot automate OAuth"
    return 1
  fi

  local _pw_script="${SCRIPT_DIR}/playwright/gcp_login.js"
  if [[ ! -f "${_pw_script}" ]]; then
    _err "[gcp] gcp_login: Playwright script not found: ${_pw_script}"
    return 1
  fi

  local _auth_log _auth_fifo _fifo_writer_pid
  _auth_log=$(mktemp)
  _auth_fifo=$(mktemp -u)
  mkfifo "${_auth_fifo}"

  # Open write end first so gcloud's open(FIFO, O_RDONLY) does not block
  { sleep 300; } >"${_auth_fifo}" &
  _fifo_writer_pid=$!

  # Run gcloud without browser; it prints an auth URL then waits on stdin for the code
  gcloud auth login --no-launch-browser --account "${expected_user}" \
    >"${_auth_log}" 2>&1 <"${_auth_fifo}" &
  local _gcloud_pid=$!

  # Poll for the auth URL in gcloud's output (up to 30s)
  local _auth_url="" _attempts=0
  while [[ "${_attempts}" -lt 30 ]]; do
    _auth_url=$(grep -oE 'https://accounts\.google\.com[^ ]+' "${_auth_log}" 2>/dev/null | head -1 || true)
    [[ -n "${_auth_url}" ]] && break
    sleep 1
    (( _attempts++ )) || true
  done

  if [[ -z "${_auth_url}" ]]; then
    _err "[gcp] gcp_login: could not extract auth URL from gcloud output"
    _err "[gcp] gcloud raw output: $(cat "${_auth_log}" 2>/dev/null || echo '<empty>')"
    kill "${_fifo_writer_pid}" 2>/dev/null || true
    kill "${_gcloud_pid}" 2>/dev/null || true
    rm -f "${_auth_log}" "${_auth_fifo}"
    return 1
  fi

  # Playwright automates the consent flow; receives URL+credentials via stdin JSON,
  # returns the one-time auth code on stdout
  local _auth_code
  _auth_code=$(printf '{"url":"%s","username":"%s","password":"%s"}' \
    "${_auth_url}" "${expected_user}" "${GCP_PASSWORD}" \
    | node "${_pw_script}") || {
    _err "[gcp] gcp_login: Playwright auth failed"
    kill "${_fifo_writer_pid}" 2>/dev/null || true
    kill "${_gcloud_pid}" 2>/dev/null || true
    rm -f "${_auth_log}" "${_auth_fifo}"
    return 1
  }

  if [[ -z "${_auth_code}" ]]; then
    _err "[gcp] gcp_login: Playwright returned empty auth code"
    kill "${_fifo_writer_pid}" 2>/dev/null || true
    kill "${_gcloud_pid}" 2>/dev/null || true
    rm -f "${_auth_log}" "${_auth_fifo}"
    return 1
  fi

  # Feed the auth code to gcloud's stdin; kill sleeper after gcloud reads it
  printf '%s\n' "${_auth_code}" >"${_auth_fifo}"
  wait "${_gcloud_pid}"
  local _exit=$?
  kill "${_fifo_writer_pid}" 2>/dev/null || true

  if [[ "${_exit}" -ne 0 ]]; then
    _err "[gcp] gcp_login: gcloud auth login failed (exit ${_exit})"
    _err "[gcp] gcloud output: $(cat "${_auth_log}" 2>/dev/null || echo '<empty>')"
    rm -f "${_auth_log}" "${_auth_fifo}"
    return 1
  fi
  rm -f "${_auth_log}" "${_auth_fifo}"

  _info "[gcp] Authenticated as ${expected_user}"
}

function gcp_provision_stack() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager gcp_provision_stack

Deploy the infrastructure plugin stack on the k3s-gcp single-node cluster:
  1. Vault (secrets backend)
  2. External Secrets Operator + ClusterSecretStore
  3. App namespaces + ghcr-pull-secret
  4. ArgoCD + ApplicationSets (--bootstrap, no LDAP, no Istio)

Run `make sync-apps CLUSTER_PROVIDER=k3s-gcp` to register shopping-cart apps with ArgoCD.

Prerequisites:
  make up CLUSTER_PROVIDER=k3s-gcp      — node must be Running
  GHCR_PAT=<pat>                         — GitHub PAT with read:packages
  ../shopping-carts/shopping-cart-infra  — ArgoCD app manifests
HELP
    return 0
  fi

  local _ghcr_pat="${GHCR_PAT:-}"
  local _github_user="${GITHUB_USERNAME:-wilddog64}"
  local _kubeconfig="${HOME}/.kube/k3s-gcp.yaml"
  local _context="k3s-gcp"

  if [[ -z "${_ghcr_pat}" ]]; then
    _err "[gcp] GHCR_PAT is not set — required for ghcr-pull-secret"
    return 1
  fi
  if [[ ! -f "${_kubeconfig}" ]]; then
    _err "[gcp] ${_kubeconfig} not found — run: make up CLUSTER_PROVIDER=k3s-gcp"
    return 1
  fi

  export KUBECONFIG="${_kubeconfig}"

  _info "[gcp] Step 1/6 — Deploying Vault..."
  CLUSTER_ROLE=infra deploy_vault || return 1

  _info "[gcp] Step 2/6 — Seeding Vault KV..."
  local _vault_pf_pid
  kubectl port-forward svc/vault -n secrets --context "${_context}" 8200:8200 >/dev/null 2>&1 &
  _vault_pf_pid=$!
  sleep 5
  local _vault_token
  _vault_token=$(kubectl get secret vault-root -n secrets --context "${_context}" \
    -o jsonpath='{.data.root_token}' | base64 -d)
  if [[ -z "${_vault_token}" ]]; then
    kill "${_vault_pf_pid}" 2>/dev/null || true
    _err "[gcp] Could not read vault-root token — is Vault ready?"
    return 1
  fi
  _gcp_seed_vault_kv "${_vault_token}"
  kill "${_vault_pf_pid}" 2>/dev/null || true

  _info "[gcp] Step 3/6 — Deploying ESO..."
  deploy_eso || return 1

  _info "[gcp] Step 4/6 — Applying ClusterSecretStore..."
  kubectl apply --context "${_context}" -f - <<'CSSEOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.secrets.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-root
          namespace: secrets
          key: root_token
CSSEOF

  _info "[gcp] Step 5/6 — Creating namespaces and ghcr-pull-secret..."
  for _ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl create namespace "${_ns}" --context "${_context}" \
      --dry-run=client -o yaml | kubectl apply --context "${_context}" -f - >/dev/null
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${_github_user}" \
      --docker-password="${_ghcr_pat}" \
      --context "${_context}" -n "${_ns}" \
      --dry-run=client -o yaml | kubectl apply --context "${_context}" -f -
    _info "[gcp] ghcr-pull-secret applied in namespace: ${_ns}"
  done

  _info "[gcp] Step 6/6 — Deploying ArgoCD..."
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/plugins/argocd.sh"
  deploy_argocd --bootstrap --skip-istio || return 1

  _info "[gcp] Full stack provisioned on k3s-gcp."
  kubectl get pods -A --context "${_context}"
}

function _gcp_seed_vault_kv() {
  local _token="$1"
  local _kv_put
  _kv_put() {
    curl -sf -X POST \
      -H "X-Vault-Token: ${_token}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":$1}" \
      "http://localhost:8200/v1/secret/data/$2" >/dev/null
  }
  local _pg_orders _pg_products _pg_payment _redis_cart _redis_orders _rabbit _ldap_admin _ldap_ro
  _pg_orders=$(openssl rand -base64 24 | tr -d '=+/')
  _pg_products=$(openssl rand -base64 24 | tr -d '=+/')
  _pg_payment=$(openssl rand -base64 24 | tr -d '=+/')
  _redis_cart=$(openssl rand -base64 24 | tr -d '=+/')
  _redis_orders=$(openssl rand -base64 24 | tr -d '=+/')
  _rabbit=$(openssl rand -base64 24 | tr -d '=+/')
  _ldap_admin=$(openssl rand -base64 24 | tr -d '=+/')
  _ldap_ro=$(openssl rand -base64 24 | tr -d '=+/')

  _kv_put "{\"password\":\"${_redis_cart}\"}"                                                redis/cart
  _kv_put "{\"password\":\"${_redis_orders}\"}"                                              redis/orders-cache
  _kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_orders}\"}"                      postgres/orders
  _kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_products}\"}"                    postgres/products
  _kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_payment}\"}"                     postgres/payment
  _kv_put '{"key":"dmF1bHQtZGV2LXNhbmRib3gtZW5jcnlwdGlvbg=="}'                            payment/encryption
  _kv_put '{"api_key":"sk_test_placeholder","webhook_secret":"whsec_placeholder"}'          payment/stripe
  _kv_put '{"client_id":"paypal_sandbox_client_id","client_secret":"paypal_sandbox_client_secret"}' payment/paypal
  _kv_put "{\"username\":\"rabbitmq\",\"password\":\"${_rabbit}\"}"                         rabbitmq/default
  _kv_put "{\"admin_password\":\"${_ldap_admin}\",\"readonly_password\":\"${_ldap_ro}\"}"   ldap/admin
  _info "[gcp] Vault KV seeded"
}
