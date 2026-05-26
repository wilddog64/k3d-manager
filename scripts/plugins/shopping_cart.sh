#!/usr/bin/env bash
set -euo pipefail

: "${_vault_local_port:=}"

function add_ubuntu_k3s_cluster() {
  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-parallels}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-${ssh_host}}"
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
      | sed "s|127.0.0.1|${external_ip}|g" > "${local_kubeconfig}"; then
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

  local kube_context
  if [[ -n "${UBUNTU_K3S_CONTEXT:-}" ]]; then
    kube_context="${UBUNTU_K3S_CONTEXT}"
  else
    if ! kube_context=$(KUBECONFIG="${local_kubeconfig}" kubectl config current-context 2>/dev/null); then
      _err "[shopping_cart] Failed to determine current context from ${local_kubeconfig}"
      return 1
    fi
    if [[ -z "${kube_context}" ]]; then
      _err "[shopping_cart] kubeconfig ${local_kubeconfig} has no current-context configured"
      return 1
    fi
  fi

  _info "[shopping_cart] Registering Ubuntu k3s cluster with ArgoCD using context ${kube_context}"
  KUBECONFIG="${local_kubeconfig}" _run_command -- argocd cluster add "${kube_context}" \
    --name ubuntu-k3s \
    --kubeconfig "${local_kubeconfig}"
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

  _info "[shopping_cart] Deploying data layer (PostgreSQL, Redis, RabbitMQ, MinIO)..."
  for pg_dir in orders payment products; do
    _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/postgresql/${pg_dir}/"
  done
  _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/redis/cart/"
  _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/rabbitmq/"
  _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/minio/"

  _info "[shopping_cart] Waiting for PostgreSQL instances to be Ready..."
  for pg in postgresql-orders postgresql-payment postgresql-products; do
    kubectl rollout status statefulset/"${pg}" \
      -n shopping-cart-data --context ubuntu-k3s --timeout=120s
  done

  _info "[shopping_cart] Waiting for MinIO to be Ready..."
  kubectl rollout status statefulset/minio \
    -n shopping-cart-data --context ubuntu-k3s --timeout=120s

  _info "[shopping_cart] Aligning PostgreSQL passwords to match app secrets (CHANGE_ME)..."
  for pg_pod in postgresql-orders-0 postgresql-products-0; do
    kubectl exec "${pg_pod}" -n shopping-cart-data --context ubuntu-k3s -- \
      psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'CHANGE_ME';" 2>/dev/null || true
  done

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

  _info "[shopping_cart] Applying Vault-backed ExternalSecrets for data, app, payment, and MinIO..."
  _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/secrets/"
  _run_command -- kubectl apply --context ubuntu-k3s -f "${infra_root}/minio/secret.yaml"

  _info "[shopping_cart] Waiting for Vault-backed ExternalSecrets to become Ready..."
  local -a externalsecrets=(
    "shopping-cart-data/redis-cart"
    "shopping-cart-data/redis-orders-cache"
    "shopping-cart-data/postgres-orders-readwrite"
    "shopping-cart-data/postgres-products-app"
    "shopping-cart-data/postgres-products-readwrite"
    "shopping-cart-data/rabbitmq-credentials"
    "shopping-cart-data/minio-credentials"
    "shopping-cart-apps/redis-cart-apps"
    "shopping-cart-apps/redis-orders-cache-apps"
    "shopping-cart-apps/order-service-secrets"
    "shopping-cart-apps/product-catalog-secrets"
    "shopping-cart-payment/postgres-payment-app"
    "shopping-cart-payment/payment-encryption-secret"
    "shopping-cart-payment/payment-gateway-secrets"
  )

  local externalsecret namespace name
  for externalsecret in "${externalsecrets[@]}"; do
    namespace="${externalsecret%%/*}"
    name="${externalsecret##*/}"
    if ! kubectl get externalsecret "${name}" -n "${namespace}" --context ubuntu-k3s >/dev/null 2>&1; then
      _warn "[shopping_cart] ExternalSecret ${namespace}/${name} not found — skipping wait"
      continue
    fi
    kubectl wait --for=condition=Ready --timeout=180s \
      externalsecret/"${name}" -n "${namespace}" --context ubuntu-k3s
  done

  _info "[shopping_cart] Vault-backed ExternalSecrets synced."
}

function shopping_cart_load_ghcr_pat_from_env() {
  _ghcr_pat="${GHCR_PAT:-}"
  _github_user="${GITHUB_USERNAME:-wilddog64}"

  if [[ -z "${_ghcr_pat}" ]]; then
    return 1
  fi

  _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_ghcr_pat}" "https://api.github.com/user" 2>/dev/null || true)
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

  _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_ghcr_pat}" "https://api.github.com/user" 2>/dev/null || true)
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

  _gh_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_gh_token}" "https://api.github.com/user" 2>/dev/null || true)
  if [[ "${_gh_http}" != "200" ]]; then
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
  local ns
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl create namespace "$ns" --context ubuntu-k3s \
      --dry-run=client -o yaml \
      | kubectl apply --context ubuntu-k3s -f - >/dev/null
    case "$ns" in
      shopping-cart-data)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=data \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-apps)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=application \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-payment)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=payment \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
    esac
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${_github_user}" \
      --docker-password="${_ghcr_pat}" \
      --context ubuntu-k3s \
      -n "$ns" \
      --dry-run=client -o yaml \
      | kubectl apply --context ubuntu-k3s -f -
    _info "[acg-up] ghcr-pull-secret applied in namespace: ${ns}"
  done
  kubectl patch serviceaccount default -n shopping-cart-apps \
    --context ubuntu-k3s \
    -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
}

function shopping_cart_create_vault_bridge() {
  if [[ -z "${_vault_node_ip:-}" ]]; then
    _vault_node_ip=$(kubectl get nodes --context ubuntu-k3s \
      -l node-role.kubernetes.io/control-plane \
      --no-headers \
      -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
  fi
  if [[ -z "${_vault_node_ip}" ]]; then
    _err "[acg-up] Could not determine server node internal IP — vault-bridge Endpoints skipped"
    return 1
  fi

  kubectl create namespace secrets --context ubuntu-k3s \
    --dry-run=client -o yaml \
    | kubectl apply --context ubuntu-k3s -f - >/dev/null
  kubectl apply --context ubuntu-k3s -f - <<EOF
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
  kubectl apply --context ubuntu-k3s -f - <<'SVCEOF'
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
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null
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

function shopping_cart_apply_vault_token_and_cluster_secret_store() {
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster \
    -o jsonpath='{.data.root_token}' | base64 -d)
  if [[ -z "${_vault_root_token}" ]]; then
    _err "[acg-up] Could not read vault-root token from k3d-k3d-cluster — is Vault running?"
    return 1
  fi
  kubectl create namespace secrets --context ubuntu-k3s \
    --dry-run=client -o yaml | kubectl apply --context ubuntu-k3s -f - >/dev/null
  kubectl create secret generic vault-token \
    -n secrets --context ubuntu-k3s \
    --from-literal=token="${_vault_root_token}" \
    --dry-run=client -o yaml | kubectl apply --context ubuntu-k3s -f -
  _info "[acg-up] Waiting for ESO webhook to be ready..."
  for i in $(seq 1 18); do
    _wh_ip=$(kubectl get endpoints external-secrets-webhook -n secrets --context ubuntu-k3s \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
    if [[ -n "${_wh_ip}" ]]; then
      _info "[acg-up] ESO webhook ready (${_wh_ip})"
      break
    fi
    _info "[acg-up] ESO webhook not ready yet (attempt ${i}/18) — waiting 10s..."
    sleep 10
  done
  kubectl apply --context ubuntu-k3s -f - <<'CSSEOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault-bridge.secrets.svc.cluster.local:8201"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          namespace: secrets
          key: token
CSSEOF
  kubectl annotate clustersecretstore vault-backend --context ubuntu-k3s \
    "k3d-manager/reconcile-at=$(date -u +%Y%m%dT%H%M%SZ)" \
    --overwrite >/dev/null
  _info "[acg-up] vault-token secret + ClusterSecretStore applied"
}

function shopping_cart_seed_sandbox_vault_kv() {
  _info "[acg-up] Seeding Vault KV with sandbox static secrets..."
  _vault_kv_put() {
    curl -sf -X POST \
      -H "X-Vault-Token: ${_vault_root_token}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":$1}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/$2" >/dev/null
  }
  _vault_kv_exists() {
    local path="$1"
    curl -sf \
      -H "X-Vault-Token: ${_vault_root_token}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/${path}" >/dev/null 2>&1
  }
  _vault_kv_get_field() {
    local path="$1"
    local field="$2"
    curl -sf \
      -H "X-Vault-Token: ${_vault_root_token}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/${path}" \
      | jq -r --arg field "$field" '.data.data[$field] // empty'
  }
  _redis_pass_cart=$(openssl rand -base64 24 | tr -d '=+/')
  _redis_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
  _rabbitmq_pass=$(openssl rand -base64 24 | tr -d '=+/')

  _vault_kv_put "{\"password\":\"${_redis_pass_cart}\"}"                                           redis/cart
  _vault_kv_put "{\"password\":\"${_redis_pass_orders}\"}"                                         redis/orders-cache

  if _vault_kv_exists "postgres/orders"; then
    _info "[acg-up] Reusing existing Vault secret postgres/orders"
    _pg_pass_orders=$(_vault_kv_get_field "postgres/orders" "password")
  else
    _pg_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_orders}\"}"                postgres/orders
  fi

  if _vault_kv_exists "postgres/products"; then
    _info "[acg-up] Reusing existing Vault secret postgres/products"
    _pg_pass_products=$(_vault_kv_get_field "postgres/products" "password")
  else
    _pg_pass_products=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_products}\"}"              postgres/products
  fi

  if _vault_kv_exists "postgres/payment"; then
    _info "[acg-up] Reusing existing Vault secret postgres/payment"
    _pg_pass_payment=$(_vault_kv_get_field "postgres/payment" "password")
  else
    _pg_pass_payment=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_payment}\"}"               postgres/payment
  fi
  _vault_kv_put '{"key":"dmF1bHQtZGV2LXNhbmRib3gtZW5jcnlwdGlvbg=="}'                             payment/encryption
  _vault_kv_put '{"api_key":"sk_test_placeholder","webhook_secret":"whsec_placeholder"}'           payment/stripe
  _vault_kv_put '{"client_id":"paypal_sandbox_client_id","client_secret":"paypal_sandbox_client_secret"}' payment/paypal
  _vault_kv_put "{\"username\":\"rabbitmq\",\"password\":\"${_rabbitmq_pass}\"}"                   rabbitmq/default

  if _vault_kv_exists "minio/credentials"; then
    _info "[acg-up] Reusing existing Vault secret minio/credentials"
    _minio_root_user=$(_vault_kv_get_field "minio/credentials" "root-user")
    _minio_root_password=$(_vault_kv_get_field "minio/credentials" "root-password")
  else
    _minio_root_user="minioadmin"
    _minio_root_password=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"root-user\":\"${_minio_root_user}\",\"root-password\":\"${_minio_root_password}\"}" minio/credentials
  fi

  if _vault_kv_exists "ldap/admin"; then
    _info "[acg-up] Reusing existing Vault secret ldap/admin"
    _ldap_admin_pass=$(_vault_kv_get_field "ldap/admin" "admin_password")
    _ldap_readonly_pass=$(_vault_kv_get_field "ldap/admin" "readonly_password")
  else
    _ldap_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
    _ldap_readonly_pass=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"admin_password\":\"${_ldap_admin_pass}\",\"readonly_password\":\"${_ldap_readonly_pass}\"}" ldap/admin
  fi

  if _vault_kv_exists "keycloak/admin"; then
    _info "[acg-up] Reusing existing Vault secret keycloak/admin"
    _kc_admin_pass=$(_vault_kv_get_field "keycloak/admin" "admin_password")
    _kc_db_pass=$(_vault_kv_get_field "keycloak/admin" "db_password")
    if [[ -z "${_kc_admin_pass}" || -z "${_kc_db_pass}" ]]; then
      _acg_fail "[acg-up] Vault secret keycloak/admin is missing admin_password or db_password — restore the secret before continuing"
    fi
  else
    _kc_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
    _kc_db_pass=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"admin_password\":\"${_kc_admin_pass}\",\"db_password\":\"${_kc_db_pass}\"}" keycloak/admin
  fi

  if _vault_kv_exists "keycloak/clients"; then
    _info "[acg-up] Reusing existing Vault secret keycloak/clients"
    _argocd_client_secret=$(_vault_kv_get_field "keycloak/clients" "argocd_client_secret")
    _order_client_secret=$(_vault_kv_get_field "keycloak/clients" "order_service_client_secret")
    _product_client_secret=$(_vault_kv_get_field "keycloak/clients" "product_catalog_client_secret")
    _grafana_client_secret=$(_vault_kv_get_field "keycloak/clients" "grafana_client_secret")
  else
    _argocd_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
    _order_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
    _product_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
    _grafana_client_secret=$(openssl rand -base64 24 | tr -d '=+/')
    _vault_kv_put "{\"argocd_client_secret\":\"${_argocd_client_secret}\",\"order_service_client_secret\":\"${_order_client_secret}\",\"product_catalog_client_secret\":\"${_product_client_secret}\",\"grafana_client_secret\":\"${_grafana_client_secret}\"}" keycloak/clients
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
        -n shopping-cart-apps --context ubuntu-k3s --ignore-not-found --wait=false >/dev/null 2>&1
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
_run_command -- ssh -i "${ssh_key}" "${ssh_host}" bash <<'REMOTE'
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
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args '--disable traefik --disable servicelb'

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
