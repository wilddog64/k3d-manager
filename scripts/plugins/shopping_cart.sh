#!/usr/bin/env bash
set -euo pipefail

: "${_vault_local_port:=}"

# --- Tier 3 P3: seed target / canonical source / backup targets ----------------------
# Defaults preserve pre-P3 behavior: target == source == laptop Vault via local port-forward.
: "${SEED_VAULT_ADDR:=http://localhost:${_vault_local_port}}"
: "${SEED_VAULT_TOKEN:=${_vault_root_token:-}}"
: "${SEED_VAULT_SOURCE_ADDR:=${SEED_VAULT_ADDR}}"
: "${SEED_VAULT_SOURCE_TOKEN:=${SEED_VAULT_TOKEN}}"
# Keychain (macOS) / secret-tool (Linux) backup service; per-key account = the Vault KV path.
: "${SEED_KEYCHAIN_SERVICE:=k3d-manager-app-cluster-secrets}"
# Native in-cluster disaster-recovery copy.
: "${SEED_K8S_BACKUP_NS:=secrets}"
: "${SEED_K8S_BACKUP_NAME:=vault-seed-backup}"

function add_ubuntu_k3s_cluster() {
  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-ubuntu}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-}"
  if [[ -z "${external_ip}" ]] && _command_exist awk; then
    external_ip=$(awk -v host="${ssh_host}" \
      '$1=="Host" && $2==host {found=1; next} found && $1=="HostName" {print $2; exit}' \
      "${HOME}/.ssh/config" 2>/dev/null)
  fi
  : "${external_ip:=${ssh_host}}"
  local remote_kubeconfig="${UBUNTU_K3S_REMOTE_KUBECONFIG:-/home/${ssh_user}/.kube/k3s.yaml}"
  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
  local ssh_target="${ssh_user}@${ssh_host}"

  case "${remote_kubeconfig}" in
    (*[!A-Za-z0-9_./-]*)
      _err "[shopping_cart] Unsafe characters in UBUNTU_K3S_REMOTE_KUBECONFIG: ${remote_kubeconfig}"
      return 1
      ;;
  esac

  _info "[shopping_cart] Exporting Ubuntu k3s kubeconfig from ${ssh_target}"
  mkdir -p "$(dirname "${local_kubeconfig}")"

# shellcheck disable=SC2029
  if ! ssh "${ssh_target}" "cat ${remote_kubeconfig}" 2>/dev/null \
      | sed -e "s|127.0.0.1|${external_ip}|g" -e "s|https://localhost:|https://${external_ip}:|g" > "${local_kubeconfig}"; then
    _err "[shopping_cart] Failed to export kubeconfig from ${ssh_target}:${remote_kubeconfig}"
    _err "[shopping_cart] Ensure ${ssh_user} can read ${remote_kubeconfig} on ${ssh_host}"
    return 1
  fi
  chmod 600 "${local_kubeconfig}"

  _info "[shopping_cart] Verifying connectivity to Ubuntu k3s at ${external_ip}:6443"
  if ! KUBECONFIG="${local_kubeconfig}" _run_command -- kubectl get nodes; then
    _err "[shopping_cart] Cannot reach Ubuntu k3s API at ${external_ip}:6443"
    return 1
  fi

  _info "[shopping_cart] Merging ubuntu-k3s context into ~/.kube/config"
  local _tmp_kube _tmp_merged
  _tmp_kube="${HOME}/.kube/ubuntu-k3s-tmp.yaml"
  _tmp_merged="${HOME}/.kube/config-merged-tmp.yaml"
  if kubectl config get-contexts ubuntu-k3s &>/dev/null; then
    kubectl config delete-context ubuntu-k3s &>/dev/null || true
    _info "[shopping_cart] Removed stale ubuntu-k3s context — will re-merge with fresh credentials"
  fi
  kubectl config delete-cluster default &>/dev/null || true
  kubectl config delete-user default &>/dev/null || true
  cp "${local_kubeconfig}" "${_tmp_kube}"
  chmod 600 "${_tmp_kube}"
  local _src_context
  if ! _src_context=$(KUBECONFIG="${_tmp_kube}" kubectl config current-context 2>/dev/null); then
    _src_context=""
  fi
  if [[ -n "${_src_context}" && "${_src_context}" != "ubuntu-k3s" ]]; then
    KUBECONFIG="${_tmp_kube}" kubectl config rename-context "${_src_context}" ubuntu-k3s
  fi
  KUBECONFIG="${HOME}/.kube/config:${_tmp_kube}" kubectl config view --flatten > "${_tmp_merged}"
  mv "${_tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${_tmp_kube}"
  _info "[shopping_cart] ubuntu-k3s context merged into ~/.kube/config"
}

function deploy_shopping_cart_data() {
  local repo_root
  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    _err "[shopping_cart] Unable to determine repository root"
    return 1
  fi

  local infra_root="${repo_root}/../shopping-carts/shopping-cart-infra/data-layer"
  if [[ ! -d "${infra_root}" ]]; then
    _err "[shopping_cart] shopping-cart-infra data-layer not found: ${infra_root}"
    _err "[shopping_cart] Clone shopping-cart-infra under ../shopping-carts/"
    return 1
  fi

  _info "[shopping_cart] Data layer managed by ArgoCD — waiting for StatefulSets to appear (max 300s)..."

  local _sts_deadline
  _sts_deadline=$(( $(date +%s) + 300 ))
  for pg in postgresql-orders postgresql-payment postgresql-products; do
    until kubectl get statefulset/"${pg}" \
        -n shopping-cart-data --context ubuntu-k3s >/dev/null 2>&1; do
      if [[ $(date +%s) -ge ${_sts_deadline} ]]; then
        _err "[shopping_cart] StatefulSet ${pg} not created in shopping-cart-data within 300s of ArgoCD sync — check: kubectl get application data-layer -n cicd --context k3d-k3d-cluster"
        return 1
      fi
      _info "[shopping_cart] ${pg} not yet created by ArgoCD — waiting..."
      sleep 10
    done
  done

  _info "[shopping_cart] Waiting for PostgreSQL instances to be Ready..."
  for pg in postgresql-orders postgresql-payment postgresql-products; do
    kubectl rollout status statefulset/"${pg}" \
      -n shopping-cart-data --context ubuntu-k3s --timeout=120s
  done

  _info "[shopping_cart] Waiting for MinIO to be Ready..."
  kubectl rollout status statefulset/minio \
    -n shopping-cart-data --context ubuntu-k3s --timeout=300s


  _info "[shopping_cart] Creating rabbitmq-credentials secret..."
  kubectl create secret generic rabbitmq-credentials \
    --context ubuntu-k3s -n shopping-cart-data \
    --from-literal=username=guest \
    --from-literal=password=CHANGE_ME \
    --dry-run=client -o yaml | kubectl apply --context ubuntu-k3s -f -


  _info "[shopping_cart] Data layer deployed."
}

function shopping_cart_sync_vault_backed_secrets() {
  local repo_root
  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    _err "[shopping_cart] Unable to determine repository root"
    return 1
  fi

  local infra_root="${repo_root}/../shopping-carts/shopping-cart-infra/data-layer"
  if [[ ! -d "${infra_root}" ]]; then
    _err "[shopping_cart] shopping-cart-infra data-layer not found: ${infra_root}"
    _err "[shopping_cart] Clone shopping-cart-infra under ../shopping-carts/"
    return 1
  fi

  local _app_context
  _app_context="$(_shopping_cart_resolve_app_context)"

  _info "[shopping_cart] Waiting for ClusterSecretStore vault-backend to be Ready on ${_app_context}..."
  local _css_ready=0
  for _css_try in 1 2 3; do
    if kubectl wait --for=condition=Ready --timeout=90s \
        clustersecretstore/vault-backend --context "${_app_context}" 2>/dev/null; then
      _css_ready=1
      break
    fi
    _warn "[shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt ${_css_try}/3) — forcing reconcile..."
    kubectl annotate clustersecretstore vault-backend --context "${_app_context}" \
      "k3d-manager/reconcile-at=$(date -u +%Y%m%dT%H%M%SZ)" --overwrite >/dev/null 2>&1 || true
  done
  if (( _css_ready == 0 )); then
    _err "[shopping_cart] ClusterSecretStore vault-backend never became Ready after 3 attempts (270s total)"
    return 1
  fi

  _info "[shopping_cart] Applying Vault-backed ExternalSecrets for data, app, payment, and MinIO..."
  _run_command -- kubectl apply --context "${_app_context}" -f "${infra_root}/secrets/"
  if [[ -f "${infra_root}/minio/secret.yaml" ]]; then
    _run_command -- kubectl apply --context "${_app_context}" -f "${infra_root}/minio/secret.yaml"
  fi

  _info "[shopping_cart] Waiting for Vault-backed ExternalSecrets to become Ready..."
  local -a _existing_es=()
  mapfile -t _existing_es < <(shopping_cart_force_vault_secret_reconcile "${_app_context}")

  for externalsecret in "${_existing_es[@]}"; do
    namespace="${externalsecret%%/*}"
    name="${externalsecret##*/}"
    kubectl wait --for=condition=Ready --timeout=300s \
      externalsecret/"${name}" -n "${namespace}" --context "${_app_context}" \
      || { _err "[shopping_cart] ExternalSecret ${namespace}/${name} did not become Ready"; return 1; }
  done

  _info "[shopping_cart] Vault-backed ExternalSecrets synced."
}

function _shopping_cart_vault_externalsecrets() {
  printf '%s\n' \
    "shopping-cart-data/redis-cart" \
    "shopping-cart-data/redis-orders-cache" \
    "shopping-cart-data/postgres-orders-readwrite" \
    "shopping-cart-data/postgres-products-app" \
    "shopping-cart-data/postgres-products-readwrite" \
    "shopping-cart-data/rabbitmq-credentials" \
    "shopping-cart-data/minio-credentials" \
    "shopping-cart-apps/redis-cart-apps" \
    "shopping-cart-apps/redis-orders-cache-apps" \
    "shopping-cart-apps/order-service-secrets" \
    "shopping-cart-apps/product-catalog-secrets" \
    "shopping-cart-apps/ghcr-pull-secret" \
    "shopping-cart-payment/postgres-payment-app" \
    "shopping-cart-payment/payment-encryption-secret" \
    "shopping-cart-payment/payment-gateway-secrets"
}

function shopping_cart_force_vault_secret_reconcile() {
  local _app_context="${1:-$(_shopping_cart_resolve_app_context)}"
  local externalsecret namespace name _es_sync_ts
  _es_sync_ts=$(date +%s)

  while IFS= read -r externalsecret; do
    [[ -z "${externalsecret}" ]] && continue
    namespace="${externalsecret%%/*}"
    name="${externalsecret##*/}"
    if ! kubectl get externalsecret "${name}" -n "${namespace}" --context "${_app_context}" >/dev/null 2>&1; then
      _warn "[shopping_cart] ExternalSecret ${namespace}/${name} not found — skipping wait"
      continue
    fi
    kubectl annotate externalsecret "${name}" -n "${namespace}" --context "${_app_context}" \
      force-sync="${_es_sync_ts}" --overwrite >/dev/null \
      || _warn "[shopping_cart] Failed to annotate ${namespace}/${name} — sync may not trigger"
    printf '%s\n' "${externalsecret}"
  done < <(_shopping_cart_vault_externalsecrets)
}

function shopping_cart_load_ghcr_pat_from_env() {
  _ghcr_pat="${GHCR_PAT:-}"
  _github_user="${GITHUB_USERNAME:-wilddog64}"

  if [[ -z "${_ghcr_pat}" ]]; then
    return 1
  fi

  local _netrc
  _netrc=$(mktemp) && chmod 0600 "${_netrc}"
  printf 'machine api.github.com login %s password %s\n' "${_github_user}" "${_ghcr_pat}" > "${_netrc}"
  _pat_http=$(curl -s -o /dev/null -w "%{http_code}" --netrc-file "${_netrc}" "https://api.github.com/user" 2>/dev/null || true)
  rm -f "${_netrc}"
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] GHCR_PAT env var is invalid (HTTP ${_pat_http}) — falling back to Vault"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using validated GHCR_PAT from env for ghcr-pull-secret"
  return 0
}

function shopping_cart_load_ghcr_pat_from_vault() {
  _info "[acg-up] GHCR_PAT not in env — checking Vault..."
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 -d 2>/dev/null || true)
  if [[ -z "${_vault_root_token}" ]]; then
    return 1
  fi

  _ghcr_pat=$(curl -s -H "X-Vault-Token: ${_vault_root_token}" "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" | jq -r '.data.data.token // empty' 2>/dev/null || true)
  if [[ -z "${_ghcr_pat}" ]]; then
    return 1
  fi

  local _netrc
  _netrc=$(mktemp) && chmod 0600 "${_netrc}"
  printf 'machine api.github.com login %s password %s\n' "${_github_user}" "${_ghcr_pat}" > "${_netrc}"
  _pat_http=$(curl -s -o /dev/null -w "%{http_code}" --netrc-file "${_netrc}" "https://api.github.com/user" 2>/dev/null || true)
  rm -f "${_netrc}"
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] Vault PAT is expired (HTTP ${_pat_http}) — prompting for a new one"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using PAT from Vault for ghcr-pull-secret"
  return 0
}

function shopping_cart_load_ghcr_pat_from_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi

  _gh_token=$(gh auth token 2>/dev/null || true)
  if [[ -z "${_gh_token}" ]]; then
    return 1
  fi

  if ! GH_TOKEN="${_gh_token}" gh api user >/dev/null 2>&1; then
    return 1
  fi

  _ghcr_pat="${_gh_token}"
  _info "[acg-up] using gh CLI token for ghcr-pull-secret"
  if [[ -n "${_vault_root_token:-}" ]]; then
    curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
      -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
    _info "[acg-up] gh CLI token saved to Vault for future runs"
  fi
  return 0
}

function shopping_cart_prompt_ghcr_pat() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    return 1
  fi

  read -r -s -p "[acg-up] Paste GitHub PAT (repo + read:packages) and press Enter: " _ghcr_pat
  echo ""
  if [[ -z "${_ghcr_pat}" ]]; then
    return 1
  fi

  if [[ -n "${_vault_root_token:-}" ]]; then
    curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
      -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
    _info "[acg-up] new PAT saved to Vault"
  fi
  return 0
}

function shopping_cart_resolve_ghcr_pat() {
  _ghcr_pat=""
  _github_user="${GITHUB_USERNAME:-wilddog64}"

  if shopping_cart_load_ghcr_pat_from_env; then
    return 0
  fi
  if shopping_cart_load_ghcr_pat_from_vault; then
    return 0
  fi
  if shopping_cart_load_ghcr_pat_from_gh; then
    return 0
  fi
  if shopping_cart_prompt_ghcr_pat; then
    return 0
  fi

  _err "[acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var or run: pbpaste | bin/rotate-ghcr-pat"
}

function shopping_cart_create_ghcr_pull_secret() {
  local ns _ctx
  _ctx="${APP_CONTEXT:-$(_acg_provider_context "$(_acg_resolve_provider)")}"
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl create namespace "$ns" --context "${_ctx}" \
      --dry-run=client -o yaml \
      | kubectl apply --context "${_ctx}" -f - >/dev/null
    case "$ns" in
      shopping-cart-data)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=data \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-apps)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=application \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-payment)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=payment \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
    esac
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${_github_user}" \
      --docker-password="${_ghcr_pat}" \
      --context "${_ctx}" \
      -n "$ns" \
      --dry-run=client -o yaml \
      | kubectl apply --context "${_ctx}" -f -
    _info "[acg-up] ghcr-pull-secret applied in namespace: ${ns} (context ${_ctx})"
  done
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl patch serviceaccount default -n "$ns" \
      --context "${_ctx}" \
      -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
  done
}

function shopping_cart_provision_ghcr_pull_secret() {
  shopping_cart_resolve_ghcr_pat
  shopping_cart_create_ghcr_pull_secret
}

function shopping_cart_create_vault_bridge() {
  local _app_context
  _app_context="$(_shopping_cart_resolve_app_context)"
  if [[ -z "${_vault_node_ip:-}" ]]; then
    _vault_node_ip=$(kubectl get nodes --context "${_app_context}" \
      -l node-role.kubernetes.io/control-plane \
      --no-headers \
      -o jsonpath='{range .items[0].status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' 2>/dev/null \
      | awk 'NF { print $1; exit }' || true)
  fi
  if [[ -z "${_vault_node_ip}" ]]; then
    _err "[acg-up] Could not determine server node internal IP — vault-bridge Endpoints skipped"
    return 1
  fi

  kubectl create namespace secrets --context "${_app_context}" \
    --dry-run=client -o yaml \
    | kubectl apply --context "${_app_context}" -f - >/dev/null
  kubectl apply --context "${_app_context}" -f - <<EOF
apiVersion: v1
kind: Endpoints
metadata:
  name: vault-bridge
  namespace: secrets
subsets:
- addresses:
  - ip: ${_vault_node_ip}
  ports:
  - port: 8201
EOF
  _info "[acg-up] vault-bridge Endpoints → ${_vault_node_ip}:8201"
  kubectl apply --context "${_app_context}" -f - <<'SVCEOF'
apiVersion: v1
kind: Service
metadata:
  name: vault-bridge
  namespace: secrets
spec:
  ports:
  - port: 8201
    protocol: TCP
    targetPort: 8201
SVCEOF
  _info "[acg-up] vault-bridge Service applied (DNS: vault-bridge.secrets.svc.cluster.local:8201)"
}

function shopping_cart_install_helm_and_eso() {
  local _eso_version="${ESO_VERSION:-1.0.0}"
  _info "[acg-up] Installing helm + ESO on remote cluster..."
  # shellcheck disable=SC2029
  ssh ubuntu "ESO_VERSION=${_eso_version} bash -s" <<'REMOTE'
set -euo pipefail
SUDO="sudo"
if ! command -v helm >/dev/null 2>&1; then
  echo "[acg-up] helm not found — installing..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/v3.17.3/scripts/get-helm-3 | DESIRED_VERSION=v3.17.3 bash >/dev/null
fi
if ! $SUDO KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm status external-secrets -n secrets >/dev/null 2>&1; then
  echo "[acg-up] ESO not installed — installing v${ESO_VERSION}..."
  $SUDO KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1
  $SUDO KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo update >/dev/null 2>&1
  $SUDO KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install external-secrets external-secrets/external-secrets \
    -n secrets --create-namespace --set installCRDs=true --version "${ESO_VERSION}" >/dev/null
  echo "[acg-up] ESO v${ESO_VERSION} installed"
else
  echo "[acg-up] ESO already installed — skipping"
fi
REMOTE
}

function _shopping_cart_css_auth_block() {
  local mode="${1:-token}"
  if [[ "${mode}" == "kubernetes" ]]; then
    cat <<K8SAUTH
        kubernetes:
          mountPath: "${APP_K8S_AUTH_MOUNT:-kubernetes-app}"
          role: "${APP_ESO_VAULT_ROLE:-eso-app-cluster}"
          serviceAccountRef:
            name: "${APP_ESO_SA_NAME:-external-secrets}"
            namespace: "${APP_ESO_SA_NS:-secrets}"
K8SAUTH
  else
    cat <<TOKENAUTH
        tokenSecretRef:
          name: vault-token
          namespace: secrets
          key: token
TOKENAUTH
  fi
}

function shopping_cart_apply_vault_token_and_cluster_secret_store() {
  local _app_context
  _app_context="$(_shopping_cart_resolve_app_context)"

  local _css_auth="${HUB_VAULT_CSS_AUTH:-token}"

  kubectl create namespace secrets --context "${_app_context}" \
    --dry-run=client -o yaml | kubectl apply --context "${_app_context}" -f - >/dev/null

  if [[ "${_css_auth}" == "token" ]]; then
    _vault_root_token=$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster \
      -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -z "${_vault_root_token}" ]]; then
      _err "[acg-up] Could not read vault-root token from k3d-k3d-cluster — is Vault running?"
      return 1
    fi
    kubectl create secret generic vault-token \
      -n secrets --context "${_app_context}" \
      --from-literal=token="${_vault_root_token}" \
      --dry-run=client -o yaml | kubectl apply --context "${_app_context}" -f -
  fi
  _info "[acg-up] Waiting for ESO webhook to be ready on ${_app_context}..."
  for i in $(seq 1 18); do
    _wh_ip=$(kubectl get endpoints external-secrets-webhook -n secrets --context "${_app_context}" \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
    if [[ -n "${_wh_ip}" ]]; then
      _info "[acg-up] ESO webhook ready (${_wh_ip})"
      break
    fi
    _info "[acg-up] ESO webhook not ready yet (attempt ${i}/18) — waiting 10s..."
    sleep 10
  done
  local _css_vault_server="${HUB_VAULT_CSS_SERVER:-http://vault-bridge.secrets.svc.cluster.local:8201}"
  local _css_auth_block
  _css_auth_block="$(_shopping_cart_css_auth_block "${_css_auth}")"
  kubectl apply --context "${_app_context}" -f - <<CSSEOF
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "${_css_vault_server}"
      path: "secret"
      version: "v2"
      auth:
${_css_auth_block}
CSSEOF
  kubectl annotate clustersecretstore vault-backend --context "${_app_context}" \
    "k3d-manager/reconcile-at=$(date -u +%Y%m%dT%H%M%SZ)" \
    --overwrite >/dev/null
  _info "[acg-up] vault-token secret + ClusterSecretStore applied"
}

function _shopping_cart_resolve_app_context() {
  local _provider="k3s-aws"
  if declare -f _acg_resolve_provider >/dev/null 2>&1; then
    _provider="$(_acg_resolve_provider 2>/dev/null || printf '%s' k3s-aws)"
  fi
  if declare -f _acg_provider_context >/dev/null 2>&1; then
    _acg_provider_context "${_provider}"
    return 0
  fi
  printf '%s\n' "ubuntu-k3s"
}

function shopping_cart_seed_sandbox_vault_kv() {
  _info "[acg-up] Seeding Vault KV with sandbox static secrets..."
  local _seed_addr="${SEED_VAULT_ADDR:-http://localhost:${_vault_local_port}}"
  local _seed_token="${SEED_VAULT_TOKEN:-${_vault_root_token}}"
  local _src_addr="${SEED_VAULT_SOURCE_ADDR:-${_seed_addr}}"
  local _src_token="${SEED_VAULT_SOURCE_TOKEN:-${_seed_token}}"
  # Token headers via curl --config files (mode 600) so the Vault tokens never appear in argv/ps.
  local _seed_hdr _src_hdr _src_json
  _seed_hdr=$(mktemp) || { _err "[acg-up] could not create temp header file"; return 1; }
  _src_hdr=$(mktemp) || { rm -f "${_seed_hdr}" 2>/dev/null || true; _err "[acg-up] could not create temp header file"; return 1; }
  chmod 600 "${_seed_hdr}" "${_src_hdr}"
  printf 'header = "X-Vault-Token: %s"\n' "${_seed_token}" > "${_seed_hdr}"
  printf 'header = "X-Vault-Token: %s"\n' "${_src_token}"  > "${_src_hdr}"
  trap 'rm -f "'"${_seed_hdr}"'" "'"${_src_hdr}"'" 2>/dev/null || true' RETURN
  _vault_kv_put() {
    curl -sf -X POST \
      --config "${_seed_hdr}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":$1}" \
      "${_seed_addr}/v1/secret/data/$2" >/dev/null
  }
  _vault_kv_exists() {
    local path="$1"
    curl -sf \
      --config "${_seed_hdr}" \
      "${_seed_addr}/v1/secret/data/${path}" >/dev/null 2>&1
  }
  _vault_kv_get_field() {
    local path="$1"
    local field="$2"
    curl -sf \
      --config "${_seed_hdr}" \
      "${_seed_addr}/v1/secret/data/${path}" \
      | jq -r --arg field "$field" '.data.data[$field] // empty'
  }
  # Canonical source reader (Vault = source of truth). Returns the raw KV-v2 data object as JSON,
  # empty string if the key is absent in the source Vault.
  _seed_source_data() {
    local path="$1"
    curl -sf \
      --config "${_src_hdr}" \
      "${_src_addr}/v1/secret/data/${path}" \
      | jq -c '.data.data // empty' 2>/dev/null || true
  }
  if _vault_kv_exists "redis/cart"; then
    _info "[acg-up] Reusing existing Vault secret redis/cart"
    _redis_pass_cart=$(_vault_kv_get_field "redis/cart" "password")
  else
    _src_json=$(_seed_source_data "redis/cart")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying redis/cart from canonical source Vault"
      _vault_kv_put "${_src_json}" redis/cart
      _redis_pass_cart=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _redis_pass_cart=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"password\":\"${_redis_pass_cart}\"}"                                         redis/cart
    fi
  fi

  if _vault_kv_exists "redis/orders-cache"; then
    _info "[acg-up] Reusing existing Vault secret redis/orders-cache"
    _redis_pass_orders=$(_vault_kv_get_field "redis/orders-cache" "password")
  else
    _src_json=$(_seed_source_data "redis/orders-cache")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying redis/orders-cache from canonical source Vault"
      _vault_kv_put "${_src_json}" redis/orders-cache
      _redis_pass_orders=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _redis_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"password\":\"${_redis_pass_orders}\"}"                                       redis/orders-cache
    fi
  fi

  if _vault_kv_exists "postgres/orders"; then
    _info "[acg-up] Reusing existing Vault secret postgres/orders"
    _pg_pass_orders=$(_vault_kv_get_field "postgres/orders" "password")
  else
    _src_json=$(_seed_source_data "postgres/orders")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying postgres/orders from canonical source Vault"
      _vault_kv_put "${_src_json}" postgres/orders
      _pg_pass_orders=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _pg_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_orders}\"}"                postgres/orders
    fi
  fi

  if _vault_kv_exists "postgres/products"; then
    _info "[acg-up] Reusing existing Vault secret postgres/products"
    _pg_pass_products=$(_vault_kv_get_field "postgres/products" "password")
  else
    _src_json=$(_seed_source_data "postgres/products")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying postgres/products from canonical source Vault"
      _vault_kv_put "${_src_json}" postgres/products
      _pg_pass_products=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _pg_pass_products=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_products}\"}"              postgres/products
    fi
  fi

  if _vault_kv_exists "postgres/payment"; then
    _info "[acg-up] Reusing existing Vault secret postgres/payment"
    _pg_pass_payment=$(_vault_kv_get_field "postgres/payment" "password")
  else
    _src_json=$(_seed_source_data "postgres/payment")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying postgres/payment from canonical source Vault"
      _vault_kv_put "${_src_json}" postgres/payment
      _pg_pass_payment=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _pg_pass_payment=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_payment}\"}"               postgres/payment
    fi
  fi
  _vault_kv_put '{"key":"dmF1bHQtZGV2LXNhbmRib3gtZW5jcnlwdGlvbg=="}'                             payment/encryption
  _vault_kv_put '{"api_key":"sk_test_placeholder","webhook_secret":"whsec_placeholder"}'           payment/stripe
  _vault_kv_put '{"client_id":"paypal_sandbox_client_id","client_secret":"paypal_sandbox_client_secret"}' payment/paypal
  if _vault_kv_exists "rabbitmq/default"; then
    _info "[acg-up] Reusing existing Vault secret rabbitmq/default"
    _rabbitmq_pass=$(_vault_kv_get_field "rabbitmq/default" "password")
  else
    _src_json=$(_seed_source_data "rabbitmq/default")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying rabbitmq/default from canonical source Vault"
      _vault_kv_put "${_src_json}" rabbitmq/default
      _rabbitmq_pass=$(printf '%s' "${_src_json}" | jq -r '.password // empty')
    else
      _rabbitmq_pass=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"username\":\"rabbitmq\",\"password\":\"${_rabbitmq_pass}\"}"                 rabbitmq/default
    fi
  fi

  if _vault_kv_exists "minio/credentials"; then
    _info "[acg-up] Reusing existing Vault secret minio/credentials"
    _minio_root_user=$(_vault_kv_get_field "minio/credentials" "root-user")
    _minio_root_password=$(_vault_kv_get_field "minio/credentials" "root-password")
  else
    _src_json=$(_seed_source_data "minio/credentials")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying minio/credentials from canonical source Vault"
      _vault_kv_put "${_src_json}" minio/credentials
      _minio_root_user=$(printf '%s' "${_src_json}" | jq -r '.["root-user"] // empty')
      _minio_root_password=$(printf '%s' "${_src_json}" | jq -r '.["root-password"] // empty')
    else
      _minio_root_user="minioadmin"
      _minio_root_password=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"root-user\":\"${_minio_root_user}\",\"root-password\":\"${_minio_root_password}\"}" minio/credentials
    fi
  fi

  if _vault_kv_exists "ldap/admin"; then
    _info "[acg-up] Reusing existing Vault secret ldap/admin"
    _ldap_admin_pass=$(_vault_kv_get_field "ldap/admin" "admin_password")
    _ldap_readonly_pass=$(_vault_kv_get_field "ldap/admin" "readonly_password")
  else
    _src_json=$(_seed_source_data "ldap/admin")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying ldap/admin from canonical source Vault"
      _vault_kv_put "${_src_json}" ldap/admin
      _ldap_admin_pass=$(printf '%s' "${_src_json}" | jq -r '.admin_password // empty')
      _ldap_readonly_pass=$(printf '%s' "${_src_json}" | jq -r '.readonly_password // empty')
    else
      _ldap_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
      _ldap_readonly_pass=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"admin_password\":\"${_ldap_admin_pass}\",\"readonly_password\":\"${_ldap_readonly_pass}\"}" ldap/admin
    fi
  fi

  if _vault_kv_exists "keycloak/admin"; then
    _info "[acg-up] Reusing existing Vault secret keycloak/admin"
    _kc_admin_pass=$(_vault_kv_get_field "keycloak/admin" "admin_password")
    _kc_db_pass=$(_vault_kv_get_field "keycloak/admin" "db_password")
    if [[ -z "${_kc_admin_pass}" || -z "${_kc_db_pass}" ]]; then
      _acg_fail "[acg-up] Vault secret keycloak/admin is missing admin_password or db_password — restore the secret before continuing"
    fi
  else
    _src_json=$(_seed_source_data "keycloak/admin")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying keycloak/admin from canonical source Vault"
      _vault_kv_put "${_src_json}" keycloak/admin
      _kc_admin_pass=$(printf '%s' "${_src_json}" | jq -r '.admin_password // empty')
      _kc_db_pass=$(printf '%s' "${_src_json}" | jq -r '.db_password // empty')
      if [[ -z "${_kc_admin_pass}" || -z "${_kc_db_pass}" ]]; then
        _acg_fail "[acg-up] Vault secret keycloak/admin is missing admin_password or db_password — restore the secret before continuing"
      fi
    else
      _kc_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
      _kc_db_pass=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"admin_password\":\"${_kc_admin_pass}\",\"db_password\":\"${_kc_db_pass}\"}" keycloak/admin
    fi
  fi

  if _vault_kv_exists "keycloak/clients"; then
    _info "[acg-up] Reusing existing Vault secret keycloak/clients"
    _argocd_client_secret=$(_vault_kv_get_field "keycloak/clients" "argocd_client_secret")
    _order_client_secret=$(_vault_kv_get_field "keycloak/clients" "order_service_client_secret")
    _product_client_secret=$(_vault_kv_get_field "keycloak/clients" "product_catalog_client_secret")
    _grafana_client_secret=$(_vault_kv_get_field "keycloak/clients" "grafana_client_secret")
  else
    _src_json=$(_seed_source_data "keycloak/clients")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying keycloak/clients from canonical source Vault"
      _vault_kv_put "${_src_json}" keycloak/clients
      _argocd_client_secret=$(printf '%s' "${_src_json}" | jq -r '.argocd_client_secret // empty')
      _order_client_secret=$(printf '%s' "${_src_json}" | jq -r '.order_service_client_secret // empty')
      _product_client_secret=$(printf '%s' "${_src_json}" | jq -r '.product_catalog_client_secret // empty')
      _grafana_client_secret=$(printf '%s' "${_src_json}" | jq -r '.grafana_client_secret // empty')
    else
      _argocd_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
      _order_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
      _product_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
      _grafana_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_kv_put "{\"argocd_client_secret\":\"${_argocd_client_secret}\",\"order_service_client_secret\":\"${_order_client_secret}\",\"product_catalog_client_secret\":\"${_product_client_secret}\",\"grafana_client_secret\":\"${_grafana_client_secret}\"}" keycloak/clients
    fi
  fi
  _info "[acg-up] Vault KV seeded (redis, postgres, payment, rabbitmq, minio, ldap, keycloak sandbox secrets)"
}

function shopping_cart_prepare_infra_bootstrap() {
  _info "[acg-up] Step 5/12 — Creating ghcr-pull-secret in all app namespaces..."
  shopping_cart_resolve_ghcr_pat
  shopping_cart_create_ghcr_pull_secret
  _info "[acg-up] Step 6/12 — Creating vault-bridge Endpoints + Service in secrets namespace..."
  shopping_cart_create_vault_bridge
}

function shopping_cart_prepare_cluster_secrets_and_seed() {
  _info "[acg-up] Step 8/12 — Installing helm + ESO on remote cluster..."
  shopping_cart_install_helm_and_eso
  _info "[acg-up] Step 9/12 — Applying vault-token secret + ClusterSecretStore on remote cluster..."
  shopping_cart_apply_vault_token_and_cluster_secret_store
  shopping_cart_seed_sandbox_vault_kv
  shopping_cart_sync_vault_backed_secrets
}

function shopping_cart_reconcile_product_catalog() {
  _info "[acg-up] Step 11b/14 — Reconciling PostgreSQL products password with Vault and seeding catalog..."
  # Use _pg_pass_products directly — ESO refreshInterval is 24h so the synced secret may lag
  # behind the Vault write that happened earlier in this run
  kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
    psql -U postgres -c "ALTER USER postgres PASSWORD '${_pg_pass_products}';" >/dev/null 2>&1 \
    && _info "[acg-up] PostgreSQL products password reconciled with Vault" \
    || _info "[acg-up] WARN: could not reconcile PostgreSQL products password"

  kubectl annotate externalsecret product-catalog-secrets \
    -n shopping-cart-apps --context ubuntu-k3s \
    force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 \
    && _info "[acg-up] ESO force-sync triggered for product-catalog-secrets" \
    || _info "[acg-up] WARN: could not trigger ESO force-sync for product-catalog-secrets"

  if kubectl get deployment product-catalog \
      -n shopping-cart-apps --context ubuntu-k3s >/dev/null 2>&1; then
    _pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
      deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]') || _pc_db_pw=""
    if [[ -n "${_pc_db_pw}" && "${_pc_db_pw}" != "${_pg_pass_products}" ]]; then
      _info "[acg-up] product-catalog DB_PASSWORD mismatch — restarting to pick up ESO secret..."
      kubectl rollout restart deployment/product-catalog \
        -n shopping-cart-apps --context ubuntu-k3s >/dev/null \
        || _info "[acg-up] WARN: could not restart product-catalog"
      kubectl rollout status deployment/product-catalog \
        -n shopping-cart-apps --context ubuntu-k3s --timeout=120s 2>/dev/null \
        || _info "[acg-up] WARN: product-catalog rollout did not finish within 120s"
    fi
  else
    _info "[acg-up] product-catalog not yet deployed — skipping DB_PASSWORD mismatch check"
  fi

  _product_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
    psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]') \
    || _product_count=0
  if [[ "${_product_count:-0}" -eq 0 ]]; then
    _info "[acg-up] Product DB is empty — running seed job..."
    _pc_kustomize_dir="${REPO_ROOT}/../shopping-carts/shopping-cart-product-catalog"
    if [[ -d "${_pc_kustomize_dir}/k8s/base" ]]; then
      kubectl delete job product-catalog-seed \
        -n shopping-cart-apps --context ubuntu-k3s --ignore-not-found >/dev/null 2>&1
      kubectl kustomize "${_pc_kustomize_dir}/k8s/base" \
        | kubectl apply --context ubuntu-k3s \
            --selector app.kubernetes.io/component=seed -f - >/dev/null
      _seed_done=false
      for _seed_i in $(seq 1 30); do
        _seed_complete=$(kubectl get job product-catalog-seed \
          -n shopping-cart-apps --context ubuntu-k3s \
          -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
        _seed_failed=$(kubectl get job product-catalog-seed \
          -n shopping-cart-apps --context ubuntu-k3s \
          -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
        if [[ "${_seed_complete}" == "True" ]]; then
          _seed_done=true
          break
        fi
        if [[ "${_seed_failed}" == "True" ]]; then
          _info "[acg-up] WARN: product-catalog seed job failed — check: kubectl logs -n shopping-cart-apps --context ubuntu-k3s -l app.kubernetes.io/component=seed"
          break
        fi
        sleep 10
      done
      _final_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
        psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]') \
        || _final_count=0
      if [[ "${_seed_done}" == "true" ]]; then
        _info "[acg-up] Product catalog seeded: ${_final_count:-0} products"
      else
        _info "[acg-up] WARN: seed did not complete within 300s — ${_final_count:-0} products in DB"
      fi
    else
      _info "[acg-up] WARN: shopping-cart-product-catalog not found at ${_pc_kustomize_dir} — skipping seed"
    fi
  else
    _info "[acg-up] Product catalog already has ${_product_count} products — skipping seed"
  fi
}

function shopping_cart_reconcile_order_service() {
  _info "[acg-up] Step 11a/14 — Reconciling PostgreSQL orders password with Vault..."
  if [[ -z "${_pg_pass_orders:-}" ]]; then
    _info "[acg-up] WARN: _pg_pass_orders is empty — skipping order-service password reconciliation"
    return 0
  fi

  kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-orders-0 -- \
    psql -U postgres -c "ALTER USER postgres PASSWORD '${_pg_pass_orders}';" >/dev/null 2>&1 \
    && _info "[acg-up] PostgreSQL orders password reconciled with Vault" \
    || _info "[acg-up] WARN: could not reconcile PostgreSQL orders password"

  kubectl annotate externalsecret order-service-secrets \
    -n shopping-cart-apps --context ubuntu-k3s \
    force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 \
    && _info "[acg-up] ESO force-sync triggered for order-service-secrets" \
    || _info "[acg-up] WARN: could not trigger ESO force-sync for order-service-secrets"

  if kubectl get deployment order-service \
      -n shopping-cart-apps --context ubuntu-k3s >/dev/null 2>&1; then
    _os_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
      deploy/order-service -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]') || _os_db_pw=""
    if [[ -n "${_os_db_pw}" && "${_os_db_pw}" != "${_pg_pass_orders}" ]]; then
      _info "[acg-up] order-service DB_PASSWORD mismatch — restarting to pick up ESO secret..."
      kubectl rollout restart deployment/order-service \
        -n shopping-cart-apps --context ubuntu-k3s >/dev/null \
        || _info "[acg-up] WARN: could not restart order-service"
      kubectl rollout status deployment/order-service \
        -n shopping-cart-apps --context ubuntu-k3s --timeout=120s 2>/dev/null \
        || _info "[acg-up] WARN: order-service rollout did not finish within 120s"
    fi
  else
    _info "[acg-up] order-service not yet deployed — skipping DB_PASSWORD mismatch check"
  fi
}

function register_shopping_cart_apps() {
  local repo_root
  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    _err "[shopping_cart] Unable to determine repository root"
    return 1
  fi

  local argocd_dir
  argocd_dir="${repo_root}/../shopping-carts/shopping-cart-infra/argocd/applications"

  if [[ ! -d "$argocd_dir" ]]; then
    _err "[shopping_cart] shopping-cart-infra applications not found: ${argocd_dir}"
    _err "[shopping_cart] Clone shopping-cart-infra under ../shopping-carts/"
    return 1
  fi

  _info "[shopping_cart] Applying ArgoCD applications from ${argocd_dir}"
  _run_command -- kubectl apply -f "${argocd_dir}/"
}

function _ensure_k3sup() {
  if _command_exist k3sup; then
    return 0
  fi
  _info "[shopping_cart] k3sup not found — installing..."
  if _command_exist brew; then
    _run_command --soft -- brew install k3sup
    if _command_exist k3sup; then
      return 0
    fi
  fi
  if _is_debian_family && _command_exist curl; then
    local _k3sup_installer
    _k3sup_installer="$(mktemp)"
    if ! curl -fsSL -o "${_k3sup_installer}" https://get.k3sup.dev; then
      rm -f "${_k3sup_installer}"
      _err "[shopping_cart] Failed to download k3sup installer from https://get.k3sup.dev"
    fi
    _run_command --soft --prefer-sudo -- sh "${_k3sup_installer}"
    rm -f "${_k3sup_installer}"
    if _command_exist k3sup; then
      return 0
    fi
  fi
  _err "[shopping_cart] k3sup not found and automatic installation failed — install manually: brew install k3sup"
}

function _ubuntu_k3s_trust_host() {
  local host="$1" attempts=0 key
  [[ -z "${host}" ]] && return 0
  mkdir -p "${HOME}/.ssh"
  touch "${HOME}/.ssh/known_hosts"
  until key=$(ssh-keyscan -T 5 "${host}" 2>/dev/null) && [[ -n "${key}" ]]; do
    (( ++attempts ))
    if (( attempts >= 24 )); then
      _warn "[shopping_cart] ssh-keyscan ${host} not ready after 120s — k3sup may prompt"
      return 0
    fi
    sleep 5
  done
  ssh-keygen -R "${host}" >/dev/null 2>&1 || true
  printf '%s\n' "${key}" >> "${HOME}/.ssh/known_hosts"
  _info "[shopping_cart] Trusted host key for ${host}"
}

function _k3sup_join_agent() {
  local agent_host="$1" server_ip="$2"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-ubuntu}"
  local ssh_key="${UBUNTU_K3S_SSH_KEY:-${HOME}/.ssh/k3d-manager-key.pem}"
  local agent_ip
  if _command_exist awk; then
    agent_ip=$(awk -v host="${agent_host}" \
      '$1=="Host" && $2==host {found=1; next} found && $1=="HostName" {print $2; exit}' \
      "${HOME}/.ssh/config" 2>/dev/null)
  fi
  : "${agent_ip:=${agent_host}}"
  _info "[shopping_cart] Joining agent ${agent_host} (${agent_ip}) to server ${server_ip}..."
  _ubuntu_k3s_trust_host "${agent_ip}"
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}"
  _info "[shopping_cart] Agent ${agent_host} joined."
}

function _setup_vault_bridge() {
  local ssh_host="${1}"
  local ssh_key="${2}"
  _info "[shopping_cart] Installing socat and vault-bridge systemd unit on ${ssh_host}..."
  # SC2087: single-quoted heredoc intentionally prevents local expansion
  # shellcheck disable=SC2087
_run_command -- ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${ssh_host}" bash <<'REMOTE'
set -euo pipefail
SUDO="sudo"
if ! command -v socat >/dev/null 2>&1; then
  $SUDO apt-get update -qq
  $SUDO apt-get install -y socat
fi
$SUDO tee /etc/systemd/system/vault-bridge.service >/dev/null <<'UNIT'
[Unit]
Description=Vault reverse tunnel bridge (socat)
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8201,fork,bind=0.0.0.0 TCP:localhost:8200
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
$SUDO systemctl daemon-reload
$SUDO systemctl enable vault-bridge
$SUDO systemctl restart vault-bridge
REMOTE
  _info "[shopping_cart] vault-bridge active on ${ssh_host}:8201"
}

function deploy_app_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: deploy_app_cluster [--confirm]

Install k3s on the remote EC2 app cluster via k3sup, then merge its kubeconfig
into ~/.kube/config as the ubuntu-k3s context.

Does NOT register the cluster with ArgoCD — that requires a bearer token:
  ssh ubuntu kubectl create token argocd-manager -n kube-system --duration=8760h
Then run: ./scripts/k3d-manager register_app_cluster

Config (override via env or scripts/etc/k3s/vars.sh):
  UBUNTU_K3S_SSH_HOST          SSH host alias (default: ubuntu)
  UBUNTU_K3S_SSH_USER          SSH user       (default: ubuntu)
  UBUNTU_K3S_EXTERNAL_IP       Node IP        (default: UBUNTU_K3S_SSH_HOST)
  UBUNTU_K3S_SSH_KEY           SSH key path   (default: ~/.ssh/k3d-manager-key.pem)
  UBUNTU_K3S_LOCAL_KUBECONFIG  Local kubeconfig path (default: ~/.kube/k3s-ubuntu.yaml)
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    _err "[shopping_cart] deploy_app_cluster requires --confirm to prevent accidental runs"
    return 1
  fi

  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"

  [[ "${K3S_AWS_SSM_ENABLED:-false}" == "true" ]] && {
    _ssm_bootstrap_k3s "${local_kubeconfig}" || return 1
    return 0
  }

  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-ubuntu}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-}"
  if [[ -z "$external_ip" ]]; then
    if _command_exist awk; then
      external_ip=$(awk -v host="${ssh_host}" \
        '$1=="Host" && $2==host {found=1; next} found && $1=="HostName" {print $2; exit}' \
        "${HOME}/.ssh/config" 2>/dev/null)
    fi
  fi
  : "${external_ip:=${ssh_host}}"
  local ssh_key="${UBUNTU_K3S_SSH_KEY:-${HOME}/.ssh/k3d-manager-key.pem}"
  local kube_context="ubuntu-k3s"
  local kubeconfig_dir="${local_kubeconfig%/*}"

  _ensure_k3sup

  if [[ ! -f "${ssh_key}" ]]; then
    _err "[shopping_cart] SSH key not found: ${ssh_key}"
    return 1
  fi

  mkdir -p "${kubeconfig_dir}" "${HOME}/.kube"

  _info "[shopping_cart] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _ubuntu_k3s_trust_host "${external_ip}"
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args '--disable traefik --disable servicelb'

  # Copy system kubeconfig to user home so add_ubuntu_k3s_cluster can read it without sudo
  # SC2087: single-quoted heredoc intentionally prevents local expansion
  # shellcheck disable=SC2087
  _run_command -- ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${ssh_user}@${external_ip}" bash <<'REMOTE'
SUDO="sudo"
mkdir -p "${HOME}/.kube"
$SUDO cp /etc/rancher/k3s/k3s.yaml "${HOME}/.kube/k3s.yaml"
$SUDO chown "$(id -u)":"$(id -g)" "${HOME}/.kube/k3s.yaml"
chmod 600 "${HOME}/.kube/k3s.yaml"
REMOTE

  _info "[shopping_cart] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${local_kubeconfig}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( attempts++ ))
    if (( attempts >= 30 )); then
      _err "[shopping_cart] Node did not become Ready after 150s"
      return 1
    fi
    sleep 5
  done
  _info "[shopping_cart] Node Ready."

  _info "[shopping_cart] Merging ubuntu-k3s context into ~/.kube/config"
  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-k3s.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  if kubectl config get-contexts "${kube_context}" >/dev/null 2>&1; then
    kubectl config delete-context "${kube_context}" >/dev/null 2>&1 || true
    _info "[shopping_cart] Removed stale ${kube_context} context"
  fi
  cp "${local_kubeconfig}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[shopping_cart] ${kube_context} context merged into ~/.kube/config"

  if [[ -n "${UBUNTU_K3S_AGENT_HOSTS:-}" ]]; then
    local -a _agent_hosts
    IFS=',' read -ra _agent_hosts <<< "${UBUNTU_K3S_AGENT_HOSTS}"
    local agent_host
    for agent_host in "${_agent_hosts[@]}"; do
      _k3sup_join_agent "${agent_host}" "${external_ip}" || return 1
    done
    _info "[shopping_cart] All agent nodes joined."
  fi

  _setup_vault_bridge "${ssh_host}" "${ssh_key}" || return 1

  _info "[shopping_cart] k3s install complete."
  _info ""
  _info "Next steps:"
  _info "  1. Get a bearer token:"
  _info "       ssh ${ssh_host} kubectl create token argocd-manager -n kube-system --duration=8760h"
  _info "  2. Register with ArgoCD:"
  _info "       ARGOCD_APP_CLUSTER_TOKEN=<token> ./scripts/k3d-manager register_app_cluster"
}

function _ssm_bootstrap_k3s() {
  local local_kubeconfig="$1"
  local server_alias="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local kube_context="ubuntu-k3s"

  local server_id
  server_id=$(_ssm_get_instance_id "${server_alias}") || return 1
  ssm_wait "${server_id}" || return 1

  _info "[shopping_cart] Installing k3s server on ${server_alias} via SSM..."
  ssm_exec "${server_id}" \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--disable traefik --disable servicelb' sh -" \
    || return 1

  _info "[shopping_cart] Waiting for k3s node to be Ready..."
  local attempts=0
  until ssm_exec "${server_id}" \
      "kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready'" 2>/dev/null; do
    (( attempts++ ))
    if (( attempts >= 30 )); then
      _err "[shopping_cart] k3s node did not become Ready after 150s"
      return 1
    fi
    sleep 5
  done
  _info "[shopping_cart] Node Ready."

  local kubeconfig_content server_ip
  kubeconfig_content=$(ssm_exec "${server_id}" "cat /etc/rancher/k3s/k3s.yaml") || return 1
  server_ip=$(aws ec2 describe-instances \
    --instance-ids "${server_id}" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text) || return 1

  mkdir -p "$(dirname "${local_kubeconfig}")"
  printf '%s\n' "${kubeconfig_content}" \
    | sed "s|127.0.0.1|${server_ip}|g" > "${local_kubeconfig}"
  chmod 600 "${local_kubeconfig}"
  KUBECONFIG="${local_kubeconfig}" kubectl config rename-context default \
    "${kube_context}" 2>/dev/null || true

  local k3s_token
  k3s_token=$(ssm_exec "${server_id}" \
    "cat /var/lib/rancher/k3s/server/node-token") || return 1

  if [[ -n "${UBUNTU_K3S_AGENT_HOSTS:-}" ]]; then
    local -a _agent_hosts
    IFS=',' read -ra _agent_hosts <<< "${UBUNTU_K3S_AGENT_HOSTS}"
    local agent_alias agent_id
    for agent_alias in "${_agent_hosts[@]}"; do
      agent_id=$(_ssm_get_instance_id "${agent_alias}") || return 1
      ssm_wait "${agent_id}" || return 1
      _info "[shopping_cart] Joining agent ${agent_alias} to server ${server_ip}..."
      ssm_exec "${agent_id}" \
        "curl -sfL https://get.k3s.io | K3S_URL=https://${server_ip}:6443 K3S_TOKEN=${k3s_token} sh -" \
        || return 1
      _info "[shopping_cart] Agent ${agent_alias} joined."
    done
  fi

  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-k3s.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  mkdir -p "${HOME}/.kube"
  if kubectl config get-contexts "${kube_context}" >/dev/null 2>&1; then
    kubectl config delete-context "${kube_context}" >/dev/null 2>&1 || true
    _info "[shopping_cart] Removed stale ${kube_context} context"
  fi
  cp "${local_kubeconfig}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[shopping_cart] ${kube_context} context merged into ~/.kube/config"

  _info "[shopping_cart] k3s install complete (SSM mode)."
  _info "[shopping_cart] Note: Vault reverse bridge not available in SSM mode."
}
