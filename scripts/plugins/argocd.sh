#!/usr/bin/env bash
# shellcheck disable=SC2016
# scripts/plugins/argocd.sh
# Argo CD GitOps plugin for k3d-manager

# Source Vault plugin for PKI and secret management
VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

# Source ESO plugin for credential syncing
ESO_PLUGIN="$PLUGINS_DIR/eso.sh"
if [[ -r "$ESO_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$ESO_PLUGIN"
fi

# Load Vault configuration variables for VAULT_ENDPOINT
VAULT_VARS_FILE="$SCRIPT_DIR/etc/vault/vars.sh"
if [[ -r "$VAULT_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_VARS_FILE"
fi

# Load Argo CD configuration variables
ARGOCD_CONFIG_DIR="$SCRIPT_DIR/etc/argocd"
ARGOCD_VARS_FILE="$ARGOCD_CONFIG_DIR/vars.sh"

if [[ ! -r "$ARGOCD_VARS_FILE" ]]; then
   _warn "[argocd] Configuration file not found: $ARGOCD_VARS_FILE"
   _warn "[argocd] Will use default values"
else
   # shellcheck disable=SC1090
   source "$ARGOCD_VARS_FILE"
fi

# Load LDAP configuration variables for dependency checks
ARGOCD_LDAP_VARS_FILE="$SCRIPT_DIR/etc/ldap/vars.sh"
if [[ -r "$ARGOCD_LDAP_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$ARGOCD_LDAP_VARS_FILE"
fi

# Default configuration values
: "${ARGOCD_NAMESPACE:=argocd}"
: "${ARGOCD_HELM_RELEASE:=argocd}"
: "${ARGOCD_HELM_REPO_NAME:=argo}"
: "${ARGOCD_HELM_REPO_URL:=https://argoproj.github.io/argo-helm}"
: "${ARGOCD_HELM_CHART_REF:=argo/argo-cd}"
: "${ARGOCD_VIRTUALSERVICE_HOST:=argocd.dev.local.me}"
: "${ARGOCD_CHART_VERSION:=7.8.1}"
: "${ARGOCD_SERVER_WAIT_TIMEOUT:=600s}"
: "${ARGOCD_PORT_FORWARD_WAIT_TIMEOUT:=30}"
: "${ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:=30}"
: "${ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT:=30}"
: "${ARGOCD_BROWSER_HOST:=argocd.shopping-cart.local}"
: "${ARGOCD_BROWSER_PORT:=443}"
: "${ARGOCD_BROWSER_TLS_DIR:=${HOME}/.local/share/k3d-manager/argocd-browser-https-tls}"
: "${ARGOCD_BROWSER_TLS_CERT_FILE:=${ARGOCD_BROWSER_TLS_DIR}/fullchain.crt}"
: "${ARGOCD_BROWSER_TLS_KEY_FILE:=${ARGOCD_BROWSER_TLS_DIR}/tls.key}"
: "${ARGOCD_BROWSER_TLS_CA_FILE:=${ARGOCD_BROWSER_TLS_DIR}/ca.crt}"
: "${ARGOCD_BROWSER_VAULT_PKI_PATH:=pki}"
: "${ARGOCD_BROWSER_VAULT_PKI_ROLE:=argocd-browser-tls}"
: "${ARGOCD_BROWSER_VAULT_PKI_ROLE_TTL:=${VAULT_PKI_ROLE_TTL:-720h}}"
: "${ARGOCD_BROWSER_LISTENER_LABEL:=com.k3d-manager.argocd-browser-https}"
: "${ARGOCD_BROWSER_LISTENER_PLIST:=/Library/LaunchDaemons/${ARGOCD_BROWSER_LISTENER_LABEL}.plist}"
: "${ARGOCD_BROWSER_LISTENER_WRAPPER:=${HOME}/.local/share/k3d-manager/bin/argocd-browser-https.sh}"
: "${ARGOCD_BROWSER_LISTENER_LOG:=${HOME}/.local/share/k3d-manager/logs/argocd-browser-https.log}"
: "${ARGOCD_DEPLOY_KEY_SECRETSTORE:=argocd-deploy-key-store}"
: "${ARGOCD_DEPLOY_KEY_ESO_SA:=eso-argocd-deploy-keys-sa}"
: "${ARGOCD_DEPLOY_KEY_VAULT_ROLE:=argocd-deploy-key-reader}"
: "${ARGOCD_GITHUB_ORG:=wilddog64}"

function _argocd_bootstrap_is_ready() {
   local -a required_resources=(
      "appproject/platform"
      "applicationset/demo-rollout"
      "applicationset/platform-helm"
      "applicationset/services-git"
   )

   local resource
   for resource in "${required_resources[@]}"; do
      if ! _kubectl --no-exit -n "$ARGOCD_NAMESPACE" get "$resource" >/dev/null 2>&1; then
         return 1
      fi
   done

   return 0
}

function _argocd_wait_for_local_port_forward() {
   local log_file="$1"
   local timeout="${2:-$ARGOCD_PORT_FORWARD_WAIT_TIMEOUT}"

   for ((attempt=1; attempt<=timeout; attempt++)); do
      if curl -sf --max-time 1 http://localhost:8080/healthz >/dev/null 2>&1; then
         return 0
      fi
      sleep 1
   done

   printf 'ERROR: %s\n' "[argocd] Argo CD did not become reachable on localhost:8080 within ${timeout}s — check ${log_file}" >&2
   {
      tail -n 20 "$log_file" 2>/dev/null || true
   } >&2
   return 1
}

function _argocd_wait_for_browser_https() {
   local log_file="$1"
   local timeout="${2:-$ARGOCD_PORT_FORWARD_WAIT_TIMEOUT}"
   local url="${3:-https://${ARGOCD_BROWSER_HOST}:${ARGOCD_BROWSER_PORT}/healthz}"

   for ((attempt=1; attempt<=timeout; attempt++)); do
      if curl -sk --max-time 1 "$url" >/dev/null 2>&1; then
         return 0
      fi
      sleep 1
   done

   printf 'ERROR: %s\n' "[argocd] Argo CD did not become reachable on ${ARGOCD_BROWSER_HOST}:${ARGOCD_BROWSER_PORT} within ${timeout}s — check ${log_file}" >&2
   {
      tail -n 20 "$log_file" 2>/dev/null || true
   } >&2
   return 1
}

function _argocd_browser_https_is_ready() {
   local url="${1:-https://${ARGOCD_BROWSER_HOST}:${ARGOCD_BROWSER_PORT}/healthz}"

   curl -sk --max-time 1 "$url" >/dev/null 2>&1
}

function _argocd_browser_tls_allowed_domains() {
   local host="${1:-}"
   local host_no_wildcard="${host#\*\.}"

   case "$host_no_wildcard" in
      *.nip.io|*.sslip.io)
         printf '%s\n' "${host_no_wildcard#*.}"
         ;;
      *.*.*)
         printf '%s\n' "${host_no_wildcard#*.}"
         ;;
      *)
         printf '%s\n' "$host_no_wildcard"
         ;;
   esac
}

function _argocd_issue_browser_tls_material() {
   local material_dir="$1"
   local ns="${2:-$VAULT_NS_DEFAULT}"
   local release="${3:-$VAULT_RELEASE_DEFAULT}"
   local path="${4:-$ARGOCD_BROWSER_VAULT_PKI_PATH}"
   local role="${5:-$ARGOCD_BROWSER_VAULT_PKI_ROLE}"
   local host="${6:-$ARGOCD_BROWSER_HOST}"
   local ttl="${7:-$ARGOCD_BROWSER_VAULT_PKI_ROLE_TTL}"

   if [[ -z "${material_dir:-}" ]]; then
      _err "[argocd] browser TLS material directory not provided"
      return 1
   fi

   if ! declare -f _vault_upsert_pki_role >/dev/null 2>&1 || \
      ! declare -f _vault_exec >/dev/null 2>&1 || \
      ! declare -f _vault_login >/dev/null 2>&1; then
      _err "[argocd] Vault helpers not loaded before browser TLS issuance"
      return 1
   fi

   mkdir -p "$material_dir"

   local existing_serial=""
   local existing_cert_file="${material_dir}/fullchain.crt"
   if [[ -s "$existing_cert_file" ]]; then
      existing_serial=$(_vault_pki_extract_certificate_serial "$existing_cert_file" 2>/dev/null || true)
   fi

   local allowed_domains
   allowed_domains="$(_argocd_browser_tls_allowed_domains "$host")"

   _vault_login "$ns" "$release"
   _vault_upsert_pki_role "$ns" "$release" "$path" "$role" "$ttl" "$allowed_domains" "true" || return 1

   local json cert key ca
   json="$(_vault_exec "$ns" "vault write -format=json ${path}/issue/${role} common_name=\"${host}\" alt_names=\"${host}\" ttl=\"${ttl}\"" "$release")"
   cert=$(printf '%s' "$json" | jq -r '.data.certificate // empty')
   key=$(printf '%s' "$json" | jq -r '.data.private_key // empty')
   ca=$(printf '%s' "$json" | jq -r '.data.issuing_ca // empty')
   if [[ -z "$cert" || -z "$key" || -z "$ca" ]]; then
      _err "[argocd] failed to issue browser TLS cert from ${path}/issue/${role}"
      return 1
   fi

   umask 077
   local cert_tmp key_tmp ca_tmp chain_tmp
   cert_tmp="$(mktemp "${material_dir}/fullchain.crt.XXXXXX")"
   key_tmp="$(mktemp "${material_dir}/tls.key.XXXXXX")"
   ca_tmp="$(mktemp "${material_dir}/ca.crt.XXXXXX")"
   chain_tmp="$(mktemp "${material_dir}/tls.crt.XXXXXX")"

   {
      printf '%s\n' "$cert"
      printf '%s\n' "$ca"
   } > "$cert_tmp"
   printf '%s\n' "$cert" > "$chain_tmp"
   printf '%s\n' "$key" > "$key_tmp"
   printf '%s\n' "$ca" > "$ca_tmp"

   mv "$cert_tmp" "${material_dir}/fullchain.crt"
   mv "$chain_tmp" "${material_dir}/tls.crt"
   mv "$key_tmp" "${material_dir}/tls.key"
   mv "$ca_tmp" "${material_dir}/ca.crt"
   chmod 600 "${material_dir}/fullchain.crt" "${material_dir}/tls.crt" "${material_dir}/tls.key" "${material_dir}/ca.crt"

   if [[ -n "$existing_serial" ]]; then
      if ! _vault_pki_revoke_certificate_serial "$existing_serial" "$path" _vault_post_revoke_request "$ns" "$release"; then
         _warn "[argocd] failed to revoke previous browser TLS certificate serial $existing_serial"
      fi
   fi
}

function _argocd_write_port_forward_wrapper() {
   local wrapper_path="$1"
   local log_file="$2"
   local kubectl_bin="${3:-}"
   local curl_bin="${4:-}"
   local namespace="${5:-$ARGOCD_NAMESPACE}"
   local context="${6:-k3d-k3d-cluster}"
   local service="${7:-svc/argocd-server}"
   local local_port="${8:-8080}"
   local remote_port="${9:-80}"
   local healthz_url="${10:-}"
   local kubeconfig_file="${11:-}"

   case "$kubectl_bin" in
      "") kubectl_bin="$(command -v kubectl 2>/dev/null || true)" ;;
   esac
   case "$curl_bin" in
      "") curl_bin="$(command -v curl 2>/dev/null || true)" ;;
   esac
   case "$healthz_url" in
      "") healthz_url="http://localhost:${local_port}/healthz" ;;
   esac

   case "$kubectl_bin" in
      "")
         _err "[argocd] kubectl not found while writing port-forward wrapper"
         return 1
         ;;
   esac
   case "$curl_bin" in
      "")
         _err "[argocd] curl not found while writing port-forward wrapper"
         return 1
         ;;
   esac

   local template_path="${SCRIPT_DIR}/etc/argocd/port-forward-wrapper.sh.tmpl"
   if [[ ! -r "$template_path" ]]; then
      _err "[argocd] Port-forward wrapper template not found: $template_path"
      return 1
   fi

   local q_kubectl_bin q_curl_bin q_log_file q_kubeconfig_file q_namespace q_context q_service q_local_port q_remote_port q_healthz_url q_startup_timeout
   printf -v q_kubectl_bin '%q' "$kubectl_bin"
   printf -v q_curl_bin '%q' "$curl_bin"
   printf -v q_log_file '%q' "$log_file"
   if [[ -n "$kubeconfig_file" ]]; then
      printf -v q_kubeconfig_file '%q' "$kubeconfig_file"
   else
      q_kubeconfig_file=""
   fi
   printf -v q_namespace '%q' "$namespace"
   printf -v q_context '%q' "$context"
   printf -v q_service '%q' "$service"
   printf -v q_local_port '%q' "$local_port"
   printf -v q_remote_port '%q' "$remote_port"
   printf -v q_healthz_url '%q' "$healthz_url"
   printf -v q_startup_timeout '%q' "${ARGOCD_PORT_FORWARD_STARTUP_TIMEOUT:-30}"

   mkdir -p "$(dirname "$wrapper_path")"
   KUBECTL_BIN="$q_kubectl_bin" \
   CURL_BIN="$q_curl_bin" \
   LOG_FILE="$q_log_file" \
   KUBECONFIG_FILE="$q_kubeconfig_file" \
   NAMESPACE="$q_namespace" \
   CONTEXT="$q_context" \
   SERVICE="$q_service" \
   LOCAL_PORT="$q_local_port" \
   REMOTE_PORT="$q_remote_port" \
   HEALTHZ_URL="$q_healthz_url" \
   STARTUP_TIMEOUT="$q_startup_timeout" \
      envsubst '$KUBECTL_BIN $CURL_BIN $LOG_FILE $KUBECONFIG_FILE $NAMESPACE $CONTEXT $SERVICE $LOCAL_PORT $REMOTE_PORT $HEALTHZ_URL $STARTUP_TIMEOUT' \
         < "$template_path" > "$wrapper_path"
   chmod 700 "$wrapper_path"
}

function _argocd_write_browser_https_wrapper() {
   local wrapper_path="$1"
   local log_file="$2"
   local socat_bin="${3:-}"
   local curl_bin="${4:-}"
   local local_host="${5:-127.0.0.1}"
   local local_port="${6:-$ARGOCD_BROWSER_PORT}"
   local upstream_host="${7:-127.0.0.1}"
   local upstream_port="${8:-8080}"
   local cert_file="${9:-$ARGOCD_BROWSER_TLS_CERT_FILE}"
   local key_file="${10:-$ARGOCD_BROWSER_TLS_KEY_FILE}"
   local healthz_url="${11:-https://${ARGOCD_BROWSER_HOST}:${ARGOCD_BROWSER_PORT}/healthz}"

   case "$socat_bin" in
      "") socat_bin="$(command -v socat 2>/dev/null || true)" ;;
   esac
   case "$curl_bin" in
      "") curl_bin="$(command -v curl 2>/dev/null || true)" ;;
   esac

   case "$socat_bin" in
      "")
         _err "[argocd] socat not found while writing browser HTTPS wrapper"
         return 1
         ;;
   esac
   case "$curl_bin" in
      "")
         _err "[argocd] curl not found while writing browser HTTPS wrapper"
         return 1
         ;;
   esac

   local template_path="${SCRIPT_DIR}/etc/argocd/browser-https-wrapper.sh.tmpl"
   if [[ ! -r "$template_path" ]]; then
      _err "[argocd] Browser HTTPS wrapper template not found: $template_path"
      return 1
   fi

   local q_socat_bin q_curl_bin q_log_file q_local_host q_local_port q_upstream_host q_upstream_port q_cert_file q_key_file q_healthz_url q_startup_timeout
   printf -v q_socat_bin '%q' "$socat_bin"
   printf -v q_curl_bin '%q' "$curl_bin"
   printf -v q_log_file '%q' "$log_file"
   printf -v q_local_host '%q' "$local_host"
   printf -v q_local_port '%q' "$local_port"
   printf -v q_upstream_host '%q' "$upstream_host"
   printf -v q_upstream_port '%q' "$upstream_port"
   printf -v q_cert_file '%q' "$cert_file"
   printf -v q_key_file '%q' "$key_file"
   printf -v q_healthz_url '%q' "$healthz_url"
   printf -v q_startup_timeout '%q' "${ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT:-30}"

   mkdir -p "$(dirname "$wrapper_path")"
   SOCAT_BIN="$q_socat_bin" \
   CURL_BIN="$q_curl_bin" \
   LOG_FILE="$q_log_file" \
   LOCAL_HOST="$q_local_host" \
   LOCAL_PORT="$q_local_port" \
   UPSTREAM_HOST="$q_upstream_host" \
   UPSTREAM_PORT="$q_upstream_port" \
   CERT_FILE="$q_cert_file" \
   KEY_FILE="$q_key_file" \
   HEALTHZ_URL="$q_healthz_url" \
   STARTUP_TIMEOUT="$q_startup_timeout" \
      envsubst '$SOCAT_BIN $CURL_BIN $LOG_FILE $LOCAL_HOST $LOCAL_PORT $UPSTREAM_HOST $UPSTREAM_PORT $CERT_FILE $KEY_FILE $HEALTHZ_URL $STARTUP_TIMEOUT' \
         < "$template_path" > "$wrapper_path"
   chmod 700 "$wrapper_path"
}

function _argocd_ensure_logged_in() {
   if argocd account get-context --server localhost:8080 >/dev/null 2>&1; then
      return 0
   fi

   _info "[argocd] Performing automated CLI login..."
   local pass
   pass=$(kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
   
   local _pf_pid=""
   if ! curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
      _info "[argocd] Starting background port-forward for login..."
      kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 >/dev/null 2>&1 &
      _pf_pid=$!
      # shellcheck disable=SC2064
      trap "[[ -n '${_pf_pid}' ]] && kill '${_pf_pid}' 2>/dev/null || true" RETURN
      sleep 3
   fi

   printf '%s' "$pass" | argocd login localhost:8080 --username admin --stdin \
      --plaintext --skip-test-tls --insecure --grpc-web >/dev/null
}

function deploy_argocd() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<'HELP'
Usage: deploy_argocd [--help]

Install Argo CD via Helm into the cicd namespace and bootstrap the shopping-cart GitOps stack.

Options:
  -h, --help   Show this help text and exit
HELP
      return 0
   fi

   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[argocd] CLUSTER_ROLE=app — skipping deploy_argocd"
      return 0
   fi

   # 1. Smart Dependency Chain
   _info "[argocd] Verifying infrastructure foundations..."
   if ! _kubectl --no-exit get ns secrets >/dev/null 2>&1; then
      _info "[argocd] Vault foundation missing — triggering deploy_vault..."
      deploy_vault
   fi
   if ! _kubectl --no-exit get ns "${LDAP_NAMESPACE:-ldap}" >/dev/null 2>&1; then
      _info "[argocd] LDAP foundation missing — triggering deploy_ldap..."
      deploy_ldap
   fi

   local enable_ldap=1  # Default to smart enabled
   local enable_vault=1 # Default to smart enabled
   # ... option parsing ...

   # 2. Helm Installation
   _info "[argocd] Installing Argo CD via Helm"
   _argocd_helm_deploy_release "$enable_ldap" "0"

   # 3. Wait and Post-Deploy
   _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=available --timeout="$ARGOCD_SERVER_WAIT_TIMEOUT" deployment/argocd-server
   
   # 4. Automatic Bootstrap
   _info "[argocd] Triggering automatic GitOps bootstrap..."
   _argocd_ensure_logged_in
   deploy_argocd_bootstrap
}

function _argocd_check_dependencies() {
   local missing_deps=()

   if ! _kubectl --no-exit get ns istio-system >/dev/null 2>&1; then
      missing_deps+=("Istio (istio-system namespace not found)")
   fi

   if (( ${#missing_deps[@]} > 0 )); then
      _warn "[argocd] Missing optional dependencies:"
      printf '  - %s\n' "${missing_deps[@]}"
   fi

   return 0
}

function _argocd_helm_deploy_release() {
   local enable_ldap="$1"
   local release_exists="$2"

   local -a helm_args=(
      --create-namespace
      --set-string "redisSecretInit.podAnnotations.sidecar\.istio\.io/inject=false"
   )

   if [[ -n "${ARGOCD_HELM_CHART_VERSION:-}" ]]; then
      helm_args+=(--version "$ARGOCD_HELM_CHART_VERSION")
   fi

   local values_file=""
   if (( enable_ldap )); then
      _info "[argocd] Configuring LDAP/Dex authentication"
      values_file="/tmp/argocd-values-${RANDOM}.yaml"
      envsubst '$ARGOCD_VIRTUALSERVICE_HOST $ARGOCD_SERVER_INSECURE $ARGOCD_LDAP_HOST $ARGOCD_LDAP_PORT $ARGOCD_LDAP_BIND_DN $ARGOCD_LDAP_USER_SEARCH_BASE $ARGOCD_LDAP_BASE_DN $ARGOCD_LDAP_GROUP_SEARCH_BASE $ARGOCD_RBAC_DEFAULT_POLICY $ARGOCD_RBAC_ADMIN_GROUP $ARGOCD_SERVER_REPLICAS $ARGOCD_REPO_SERVER_REPLICAS $ARGOCD_APPLICATIONSET_REPLICAS' \
         < "$ARGOCD_CONFIG_DIR/values.yaml.tmpl" > "$values_file"
      helm_args+=(--values "$values_file")
   else
      helm_args+=(
         --set "server.insecure=true"
         --set "server.service.type=ClusterIP"
      )
   fi

   if (( release_exists )); then
      _info "[argocd] Upgrading existing release with new configuration"
      _helm upgrade --install --reset-values \
         -n "$ARGOCD_NAMESPACE" \
         "$ARGOCD_HELM_RELEASE" \
         "$ARGOCD_HELM_CHART_REF" \
         "${helm_args[@]}"
   else
      _helm upgrade --install \
         -n "$ARGOCD_NAMESPACE" \
         "$ARGOCD_HELM_RELEASE" \
         "$ARGOCD_HELM_CHART_REF" \
         "${helm_args[@]}"
   fi

   if [[ -n "$values_file" && -f "$values_file" ]]; then
      rm -f "$values_file"
   fi
}

function _argocd_configure_vault_eso() {
   local enable_ldap="$1"

   _info "[argocd] Configuring Vault/ESO integration"
   _info "[argocd] Creating SecretStore and ServiceAccount"
   _argocd_setup_vault_policies
   envsubst < "$ARGOCD_CONFIG_DIR/secretstore.yaml.tmpl" | _kubectl apply -f - >/dev/null
   _argocd_seed_vault_admin_secret
   sleep 2

   if (( enable_ldap )); then
      _info "[argocd] Creating LDAP bind password ExternalSecret"
      envsubst < "$ARGOCD_CONFIG_DIR/externalsecret-ldap.yaml.tmpl" | _kubectl apply -f - >/dev/null

      if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$ARGOCD_LDAP_SECRET_NAME" 2>/dev/null; then
         _warn "[argocd] Timeout waiting for LDAP ExternalSecret; check ESO status"
      fi
   fi

   _info "[argocd] Creating admin credentials ExternalSecret"
   envsubst < "$ARGOCD_CONFIG_DIR/externalsecret-admin.yaml.tmpl" | _kubectl apply -f - >/dev/null

   if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$ARGOCD_ADMIN_SECRET_NAME" 2>/dev/null; then
      _warn "[argocd] Timeout waiting for admin ExternalSecret; check ESO status"
   fi

   _info "[argocd] Vault/ESO integration configured"
}

function _argocd_configure_post_deploy() {
   local enable_vault="$1"
   local enable_ldap="$2"
   local skip_istio="$3"
   local enable_bootstrap="$4"
   local skip_appproject="$5"
   local skip_applicationsets="$6"

   if (( enable_vault )); then
      _argocd_configure_vault_eso "$enable_ldap"
   fi

   if (( ! skip_istio )); then
      _info "[argocd] Creating Istio VirtualService"
      envsubst < "$ARGOCD_CONFIG_DIR/virtualservice.yaml.tmpl" | _kubectl apply -f - >/dev/null
      _info "[argocd] Argo CD UI accessible at: https://$ARGOCD_VIRTUALSERVICE_HOST"
   fi

   if (( enable_bootstrap )); then
      _info "[argocd] Deploying GitOps bootstrap resources"
      _argocd_deploy_image_updater
      if (( ! skip_appproject )); then
         _argocd_deploy_appproject
      fi
      if (( ! skip_applicationsets )); then
         _argocd_deploy_applicationsets
      fi
      _info "[argocd] Bootstrap deployment complete!"
      _info "[argocd] View AppProjects: kubectl -n $ARGOCD_NAMESPACE get appproject"
      _info "[argocd] View ApplicationSets: kubectl -n $ARGOCD_NAMESPACE get applicationset"
      _info "[argocd] View Applications: kubectl -n $ARGOCD_NAMESPACE get application"
   fi

   _info "[argocd] Deployment complete!"
   if (( enable_vault )); then
      _info "[argocd] Retrieve admin password: kubectl -n $ARGOCD_NAMESPACE get secret $ARGOCD_ADMIN_SECRET_NAME -o jsonpath='{.data.password}' | base64 -d"
   else
      _info "[argocd] Retrieve initial admin password: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
   fi
}

function _argocd_seed_vault_admin_secret() {
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"
   local secret_path="${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}"

   if _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
         vault kv get -format=json "$secret_path" >/dev/null 2>&1; then
      _info "[argocd] Vault admin secret already exists at ${secret_path}, skipping"
      return 0
   fi

   _info "[argocd] Seeding ArgoCD admin password in Vault"
   local password
   password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 24)

   _vault_login "$ns" "$release"
   local rc=0
   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
      vault kv put "$secret_path" "${ARGOCD_ADMIN_PASSWORD_KEY}=${password}" || rc=$?
   if (( rc != 0 )); then
      _err "[argocd] Failed to seed ArgoCD admin password in Vault (exit code $rc). Check Vault status and authentication."
      return "$rc"
   fi

   _info "[argocd] ArgoCD admin password seeded. Retrieve via Kubernetes secret after ESO sync"
}

function _argocd_setup_vault_policies() {
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"
   local eso_sa="${ARGOCD_ESO_SERVICE_ACCOUNT}"
   local eso_ns="${ARGOCD_NAMESPACE}"
   local policy_name="${ARGOCD_ESO_ROLE}"

   # Check if policy already exists
   if _vault_policy_exists "$ns" "$release" "$policy_name"; then
      _info "[argocd] Vault policy '$policy_name' already exists, skipping setup"
      return 0
   fi

   _info "[argocd] Creating Vault policy and Kubernetes role for ESO"
   _vault_login "$ns" "$release"

   # Create policy for ArgoCD ESO access
   cat <<'HCL' | _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
     vault policy write "${ARGOCD_ESO_ROLE}" -
     # ArgoCD ESO policy - read LDAP admin credentials and ArgoCD admin password
     path "secret/data/ldap/*"      { capabilities = ["read"] }
     path "secret/metadata/ldap"    { capabilities = ["list"] }
     path "secret/metadata/ldap/*"  { capabilities = ["read","list"] }
     path "secret/data/argocd/*"    { capabilities = ["read"] }
     path "secret/metadata/argocd"  { capabilities = ["list"] }
     path "secret/metadata/argocd/*" { capabilities = ["read","list"] }
HCL

   # Map ArgoCD ESO service account to the policy
   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
     vault write "auth/kubernetes/role/${policy_name}" \
       "bound_service_account_names=${eso_sa}" \
       "bound_service_account_namespaces=${eso_ns}" \
       "policies=${policy_name}" \
       ttl=1h

   _info "[argocd] Vault policy and Kubernetes role created successfully"
}

function configure_vault_argocd_repos() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<EOF
Usage: configure_vault_argocd_repos [--seed-vault] [--dry-run]

Create Vault-managed deploy key plumbing for the shopping-cart ArgoCD repos.

Options:
   --seed-vault   Seed placeholder deploy keys (REPLACE_ME) in Vault KV
   --dry-run      Show rendered manifests and Vault actions without applying
   -h, --help     Show this help message

EOF
      return 0
   fi

   local seed_vault=0
   local dry_run=0
   while [[ $# -gt 0 ]]; do
      case "$1" in
         --seed-vault)
            seed_vault=1
            shift
            ;;
         --dry-run)
            dry_run=1
            shift
            ;;
         -h|--help)
            cat <<'EOF'
Usage: configure_vault_argocd_repos [--seed-vault] [--dry-run]
EOF
            return 0
            ;;
         *)
            _err "[argocd] Unknown option: $1"
            return 1
            ;;
      esac
   done

   local ns="$ARGOCD_NAMESPACE"
   local vault_ns="${VAULT_NS_DEFAULT:-vault}"
   local vault_release="${VAULT_RELEASE_DEFAULT:-vault}"
   local vault_pod="${vault_release}-0"
   _argocd_validate_deploy_key_prereqs "$dry_run" "$ns" "$vault_ns" "$vault_pod" || return 1

   _info "[argocd] Configuring Vault-managed deploy keys for shopping-cart repos"
   if (( dry_run )); then
      _info "[argocd] Dry-run mode enabled — no changes will be applied"
   fi

   _argocd_setup_deploy_key_resources "$dry_run" "$ns" || return 1

   local -a repo_names=(basket frontend order payment product-catalog)

   if (( seed_vault )); then
      if (( dry_run )); then
         _info "[argocd] (dry-run) Would seed placeholder deploy keys in Vault"
      else
         _warn "[argocd] --seed-vault writes REPLACE_ME placeholders. Suspend ArgoCD auto-sync before proceeding."
         if ! _argocd_seed_deploy_key_placeholders "${repo_names[@]}"; then
            return 1
         fi
      fi
   fi

   _argocd_apply_repo_deploy_keys "$dry_run" "$ns" "${repo_names[@]}" || return 1

   _info "[argocd] Vault-managed deploy keys configured"
   _info "[argocd] Rotation: vault kv put secret/argocd/deploy-keys/<repo> private_key=@<new-key-file>"
   _info "[argocd] Update shopping-cart Application CRs to SSH URLs:"
   for repo in "${repo_names[@]}"; do
      local repo_url="git@github.com:${ARGOCD_GITHUB_ORG}/shopping-cart-${repo}.git"
      _info "  - ${repo_url}"
   done

   _info "[argocd] Verify: kubectl -n $ns get externalsecret -l argocd-deploy-key=true"
   return 0
}

function _argocd_apply_deploy_key_externalsecrets() {
   local repo_name="$1"
   local repo_url="$2"
   local dry_run="${3:-0}"
   local template="$ARGOCD_CONFIG_DIR/externalsecret-deploy-key.yaml.tmpl"

   if [[ ! -f "$template" ]]; then
      _err "[argocd] ExternalSecret template missing: $template"
      return 1
   fi

   local rendered
   rendered=$(mktemp)
   ARGOCD_REPO_NAME="$repo_name" \
   ARGOCD_REPO_SSH_URL="$repo_url" \
   envsubst '$ARGOCD_NAMESPACE $ARGOCD_DEPLOY_KEY_SECRETSTORE $ARGOCD_REPO_NAME $ARGOCD_REPO_SSH_URL' \
      < "$template" > "$rendered"

   if (( dry_run )); then
      cat "$rendered"
      rm -f "$rendered"
      return 0
   fi

   local rc=0
   _kubectl apply -f "$rendered" >/dev/null || rc=$?
   rm -f "$rendered"
   return "$rc"
}

function _argocd_setup_deploy_key_policy() {
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"
   local policy="${ARGOCD_DEPLOY_KEY_VAULT_ROLE}"
   local sa="${ARGOCD_DEPLOY_KEY_ESO_SA}"
   local eso_ns="${ARGOCD_NAMESPACE}"

   _vault_login "$ns" "$release"

   if _vault_policy_exists "$ns" "$release" "$policy"; then
      _info "[argocd] Vault policy ${policy} already exists"
   else
      _info "[argocd] Writing Vault policy ${policy}"
      if ! _argocd_deploy_key_policy_hcl | _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
            vault policy write "$policy" - >/dev/null; then
         _err "[argocd] Failed to write policy ${policy}"
         return 1
      fi
   fi

   if ! _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
         vault write "auth/kubernetes/role/${policy}" \
            "bound_service_account_names=${sa}" \
            "bound_service_account_namespaces=${eso_ns}" \
            "policies=${policy}" \
            ttl=1h >/dev/null; then
      _err "[argocd] Failed to bind service account ${sa} to Vault role ${policy}"
      return 1
   fi

   return 0
}

function _argocd_seed_deploy_key_placeholders() {
   local -a repos=("$@")
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"

   _vault_login "$ns" "$release"

   for repo in "${repos[@]}"; do
      local path="secret/argocd/deploy-keys/${repo}"
      if _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
            vault kv get "$path" >/dev/null 2>&1; then
         _info "[argocd] Vault path ${path} already exists — skipping placeholder"
         continue
      fi

      _info "[argocd] Seeding placeholder deploy key at ${path}"
      if ! _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
            vault kv put "$path" private_key=REPLACE_ME >/dev/null; then
         _err "[argocd] Failed to seed placeholder for ${repo}"
         return 1
      fi
   done

   return 0
}

function _argocd_deploy_key_policy_hcl() {
   cat <<'HCL'
path "secret/data/argocd/deploy-keys/*" {
  capabilities = ["read"]
}
path "secret/metadata/argocd/deploy-keys/*" {
  capabilities = ["read", "list"]
}
HCL
}

function _argocd_validate_deploy_key_prereqs() {
   local dry_run="$1" ns="$2" vault_ns="$3" vault_pod="$4"

   if (( dry_run )); then
      return 0
   fi

   local errors=0

   if ! _kubectl --no-exit get ns "$ns" >/dev/null 2>&1; then
      _err "[argocd] Namespace '$ns' not found. Deploy ArgoCD first."
      errors=1
   fi

   if ! _kubectl --no-exit -n "$ns" get deployment argocd-server >/dev/null 2>&1; then
      _err "[argocd] Deployment argocd-server not found in namespace '$ns'."
      errors=1
   fi

   local -a required_crds=(externalsecrets.external-secrets.io secretstores.external-secrets.io)
   local crd_missing=0
   for crd in "${required_crds[@]}"; do
      if ! _kubectl --no-exit get crd "$crd" >/dev/null 2>&1; then
         _err "[argocd] Missing CRD $crd. Install External Secrets Operator."
         crd_missing=1
      fi
   done

   if (( crd_missing )); then
      errors=1
   fi

   if ! _kubectl --no-exit -n "$vault_ns" get pod "$vault_pod" >/dev/null 2>&1; then
      _err "[argocd] Vault pod ${vault_pod} not found in namespace ${vault_ns}."
      errors=1
   fi

   if (( errors )); then
      _err "[argocd] Aborting configure_vault_argocd_repos due to missing prerequisites"
      return 1
   fi

   return 0
}

function _argocd_setup_deploy_key_resources() {
   local dry_run="$1" ns="$2"

   local sa_manifest
   sa_manifest=$(cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${ARGOCD_DEPLOY_KEY_ESO_SA}
  namespace: ${ns}
EOF
)

   if (( dry_run )); then
      _info "[argocd] (dry-run) ServiceAccount manifest:"
      printf '%s\n' "$sa_manifest"
   else
      printf '%s\n' "$sa_manifest" | _kubectl apply -f - >/dev/null
   fi

   if (( dry_run )); then
      _info "[argocd] (dry-run) Would ensure Vault policy ${ARGOCD_DEPLOY_KEY_VAULT_ROLE} bound to SA ${ARGOCD_DEPLOY_KEY_ESO_SA}"
   else
      if ! _argocd_setup_deploy_key_policy; then
         _err "[argocd] Failed to configure Vault policy ${ARGOCD_DEPLOY_KEY_VAULT_ROLE}"
         return 1
      fi
   fi

   local secretstore_tmpl="$ARGOCD_CONFIG_DIR/secretstore-deploy-key.yaml.tmpl"
   if [[ ! -f "$secretstore_tmpl" ]]; then
      _err "[argocd] SecretStore template not found: $secretstore_tmpl"
      return 1
   fi

   local secretstore_render
   secretstore_render=$(mktemp)
   ARGOCD_NAMESPACE="$ns" \
   envsubst '$ARGOCD_NAMESPACE $ARGOCD_DEPLOY_KEY_SECRETSTORE $VAULT_ENDPOINT $ARGOCD_VAULT_KV_MOUNT $ARGOCD_DEPLOY_KEY_VAULT_ROLE $ARGOCD_DEPLOY_KEY_ESO_SA' \
      < "$secretstore_tmpl" > "$secretstore_render"

   if (( dry_run )); then
      _info "[argocd] (dry-run) SecretStore manifest:"
      cat "$secretstore_render"
   else
      _kubectl apply -f "$secretstore_render" >/dev/null
   fi

   rm -f "$secretstore_render"
   return 0
}

function _argocd_apply_repo_deploy_keys() {
   local dry_run="$1" ns="$2"
   shift 2
   local -a repos=("$@")
   local -a applied_externalsecrets=()

   for repo in "${repos[@]}"; do
      local url="git@github.com:${ARGOCD_GITHUB_ORG}/shopping-cart-${repo}.git"
      _info "[argocd] Configuring deploy key sync for ${repo} (${url})"
      if (( dry_run )); then
         _argocd_apply_deploy_key_externalsecrets "$repo" "$url" 1 || return 1
      else
         if ! _argocd_apply_deploy_key_externalsecrets "$repo" "$url" 0; then
            return 1
         fi
         applied_externalsecrets+=("argocd-deploy-key-${repo}")
      fi
   done

   if (( dry_run )); then
      return 0
   fi

   local wait_failed=0
   for externalsecret in "${applied_externalsecrets[@]}"; do
      if ! _kubectl -n "$ns" wait --for=condition=Ready --timeout=60s "externalsecret/${externalsecret}" >/dev/null 2>&1; then
         _err "[argocd] ExternalSecret ${externalsecret} failed to reach Ready"
         wait_failed=1
      fi
   done

   if (( wait_failed )); then
      _err "[argocd] Deploy key configuration incomplete; resolve ESO errors and rerun"
      return 1
   fi

   return 0
}

# shellcheck disable=SC2120
function deploy_argocd_bootstrap() {
   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[argocd] CLUSTER_ROLE=app — skipping deploy_argocd_bootstrap"
      return 0
   fi
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<EOF
Usage: deploy_argocd_bootstrap [options]

Deploy ArgoCD AppProjects and ApplicationSets for GitOps foundation.

This function deploys:
  - AppProject definitions for platform services
  - Sample ApplicationSet manifests demonstrating different generators:
    * List generator (multi-namespace deployment)
    * Cluster generator (multi-cluster deployment)
    * Git generator (automatic discovery from repository)

Options:
   --skip-applicationsets   Skip ApplicationSet deployment (AppProject only)
   --skip-appproject        Skip AppProject deployment (ApplicationSets only)
   -h, --help               Show this help message

Environment Variables:
   ARGOCD_NAMESPACE         Namespace for Argo CD (default: argocd)
   ARGOCD_CONFIG_DIR        Path to ArgoCD configuration directory

Examples:
   # Deploy everything (AppProjects + ApplicationSets)
   ./scripts/k3d-manager deploy_argocd_bootstrap

   # Deploy only AppProject
   ./scripts/k3d-manager deploy_argocd_bootstrap --skip-applicationsets

   # Deploy only ApplicationSets
   ./scripts/k3d-manager deploy_argocd_bootstrap --skip-appproject

EOF
      return 0
   fi

   local skip_applicationsets=0
   local skip_appproject=0

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --skip-applicationsets)
            skip_applicationsets=1
            shift
            ;;
         --skip-appproject)
            skip_appproject=1
            shift
            ;;
         *)
            _err "[argocd] Unknown option: $1"
            return 1
            ;;
      esac
   done

   _info "[argocd] Starting ArgoCD bootstrap deployment"

   # Verify ArgoCD is running
   if ! _kubectl get ns "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
      _err "[argocd] ArgoCD namespace not found. Deploy ArgoCD first with: deploy_argocd"
      return 1
   fi

   if ! _kubectl -n "$ARGOCD_NAMESPACE" get deployment argocd-server >/dev/null 2>&1; then
      _err "[argocd] ArgoCD server deployment not found. Deploy ArgoCD first with: deploy_argocd"
      return 1
   fi

   # Deploy AppProject
   if (( ! skip_appproject )); then
      _argocd_deploy_appproject
   fi

   # Deploy ApplicationSets
   if (( ! skip_applicationsets )); then
      _argocd_deploy_applicationsets
   fi

   _info "[argocd] Bootstrap deployment complete!"
   _info "[argocd] View AppProjects: kubectl -n $ARGOCD_NAMESPACE get appproject"
   _info "[argocd] View ApplicationSets: kubectl -n $ARGOCD_NAMESPACE get applicationset"
   _info "[argocd] View Applications: kubectl -n $ARGOCD_NAMESPACE get application"

   return 0
}

function _argocd_deploy_appproject() {
   _info "[argocd] Deploying platform AppProject"

   local appproject_tmpl="$ARGOCD_CONFIG_DIR/projects/platform.yaml.tmpl"

   if [[ ! -f "$appproject_tmpl" ]]; then
      _err "[argocd] AppProject file not found: $appproject_tmpl"
      return 1
   fi

   local rendered
   rendered=$(mktemp -t argocd-appproject.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$rendered")' EXIT
   envsubst '$ARGOCD_NAMESPACE' < "$appproject_tmpl" > "$rendered"
   _kubectl apply --server-side -f "$rendered" >/dev/null
   trap '$(_cleanup_trap_command "$rendered")' RETURN

   _info "[argocd] AppProject deployed: platform"
   return 0
}

function _argocd_deploy_image_updater() {
   if [[ "${ARGOCD_SKIP_IMAGE_UPDATER:-0}" == "1" ]]; then
      _info "[argocd] Skipping ArgoCD Image Updater install (ARGOCD_SKIP_IMAGE_UPDATER=1)"
      return 0
   fi

   local updater_dir="$ARGOCD_CONFIG_DIR/image-updater"
   if [[ ! -d "$updater_dir" ]]; then
      _warn "[argocd] Image Updater config dir not found: $updater_dir"
      return 0
   fi

   _info "[argocd] Installing ArgoCD Image Updater (v0.15.0)"
   if ! _kubectl apply -k "$updater_dir" >/dev/null 2>&1; then
      _warn "[argocd] Image Updater install failed (apply -k); continuing"
      return 0
   fi

   _kubectl -n "$ARGOCD_NAMESPACE" rollout restart deploy/argocd-image-updater >/dev/null 2>&1 || true
   if ! _kubectl --no-exit -n "$ARGOCD_NAMESPACE" rollout status deploy/argocd-image-updater --timeout=120s; then
      _warn "[argocd] Image Updater not Ready within timeout; check: kubectl -n $ARGOCD_NAMESPACE get deploy argocd-image-updater"
   fi
   _info "[argocd] ArgoCD Image Updater install complete"
}

function _argocd_deploy_applicationsets() {
   _info "[argocd] Deploying sample ApplicationSets"

   K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
   export K3D_MANAGER_BRANCH

   APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-ubuntu-hostinger}"
   export APP_CLUSTER_NAME
   local _active_app_cluster=""
   if declare -f _acg_provider_context >/dev/null 2>&1 && declare -f _acg_resolve_provider >/dev/null 2>&1; then
      _active_app_cluster="$(_acg_provider_context "$(_acg_resolve_provider)" 2>/dev/null)"
   fi
   _active_app_cluster="${_active_app_cluster:-${APP_CLUSTER_NAME}}"
   _argocd_set_active_app_cluster "${_active_app_cluster}"

   local appsets_dir="$ARGOCD_CONFIG_DIR/applicationsets"

   if [[ ! -d "$appsets_dir" ]]; then
      _err "[argocd] ApplicationSets directory not found: $appsets_dir"
      return 1
   fi

   # Find all ApplicationSet YAML files
   local -a appset_files=()
   while IFS= read -r -d '' file; do
      appset_files+=("$file")
   done < <(find "$appsets_dir" -maxdepth 1 -type f -name '*.yaml' -print0 2>/dev/null)

   if (( ${#appset_files[@]} == 0 )); then
      _warn "[argocd] No ApplicationSet files found in: $appsets_dir"
      return 0
   fi

   _info "[argocd] Found ${#appset_files[@]} ApplicationSet file(s)"

   # Deploy each ApplicationSet
   local deployed_count=0
   for file in "${appset_files[@]}"; do
      local filename
      filename=$(basename "$file")
      _info "[argocd] Deploying ApplicationSet: $filename"

      if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
         ((deployed_count++))
      else
         _warn "[argocd] Failed to deploy ApplicationSet: $filename"
      fi
   done

   _info "[argocd] Successfully deployed $deployed_count/${#appset_files[@]} ApplicationSet(s)"
   return 0
}

function _argocd_set_active_app_cluster() {
   local _active="${1:-}"
   if [[ -z "${_active}" ]]; then
      _err "[argocd] _argocd_set_active_app_cluster: active cluster name required"
      return 1
   fi
   local _ns="${ARGOCD_NAMESPACE:-cicd}"
   local _s _cname
   while IFS= read -r _s; do
      [[ -z "${_s}" ]] && continue
      _cname="$(_kubectl get "${_s}" -n "${_ns}" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/cluster-name}' 2>/dev/null)"
      if [[ "${_cname}" == "${_active}" ]]; then
         _kubectl label "${_s}" -n "${_ns}" k3d-manager/role=app-cluster --overwrite >/dev/null 2>&1 || true
      else
         _kubectl label "${_s}" -n "${_ns}" k3d-manager/role- >/dev/null 2>&1 || true
      fi
   done < <(_kubectl get secrets -n "${_ns}" -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null)
   _info "[argocd] app-cluster role label set on '${_active}' (cleared from others)"
}

function _argocd_hub_kubectl_cmd() {
   local _hub_context="${ARGOCD_HUB_CONTEXT:-k3d-k3d-cluster}"
   printf 'kubectl --context %s\n' "${_hub_context}"
}

function register_app_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: register_app_cluster

Register the Ubuntu k3s app cluster with ArgoCD by applying a cluster secret.
Bypasses argocd cluster add (gRPC over SSH tunnel is unreliable).

Requires a service account token from the ubuntu-k3s cluster:
  ssh ubuntu kubectl create token argocd-manager -n kube-system --duration=8760h

Config (override via env or scripts/etc/argocd/vars.sh):
  ARGOCD_APP_CLUSTER_SECRET_NAME   Secret name   (default: cluster-ubuntu-k3s)
  ARGOCD_APP_CLUSTER_NAME          Cluster name  (default: ubuntu-k3s)
  ARGOCD_APP_CLUSTER_SERVER        API server    (default: https://host.k3d.internal:6443)
  ARGOCD_APP_CLUSTER_INSECURE      Skip TLS      (default: true — dev only)
  ARGOCD_APP_CLUSTER_CA_DATA       CA bundle     (optional, base64; when set forces insecure=false)
  ARGOCD_APP_CLUSTER_TOKEN         Bearer token  (required — no default)
HELP
    return 0
  fi

  if [[ -z "${ARGOCD_APP_CLUSTER_TOKEN:-}" ]]; then
    _err "[argocd] ARGOCD_APP_CLUSTER_TOKEN is required — get it with:"
    _err "  ssh ubuntu kubectl create token argocd-manager -n kube-system --duration=8760h"
    return 1
  fi

  _info "[argocd] registering app cluster '${ARGOCD_APP_CLUSTER_NAME}' -> ${ARGOCD_APP_CLUSTER_SERVER}"

  local app_cluster_environment="${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}"
  if [[ "${ARGOCD_APP_CLUSTER_SERVER}" == "https://kubernetes.default.svc" ]]; then
    app_cluster_environment="${ARGOCD_APP_CLUSTER_ENVIRONMENT:-infra}"
  fi

  local _tls_client_config
  if [[ -n "${ARGOCD_APP_CLUSTER_CA_DATA:-}" ]]; then
    _tls_client_config="\"caData\": \"${ARGOCD_APP_CLUSTER_CA_DATA}\", \"insecure\": false"
  else
    _tls_client_config="\"insecure\": ${ARGOCD_APP_CLUSTER_INSECURE:-true}"
  fi

  local rendered
  rendered="$(mktemp -t argocd-cluster-secret.XXXXXX.yaml)"
  trap '$(_cleanup_trap_command "$rendered")' RETURN

  local _wasx=0
  case $- in *x*) _wasx=1; set +x;; esac
  cat > "$rendered" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_APP_CLUSTER_SECRET_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: "${ARGOCD_APP_CLUSTER_NAME}"
    environment: "${app_cluster_environment}"
    argocd-chart-version: "${ARGOCD_CHART_VERSION}"
    argocd-replicas: "2"
type: Opaque
stringData:
  name: ${ARGOCD_APP_CLUSTER_NAME}
  server: ${ARGOCD_APP_CLUSTER_SERVER}
  config: |
    {
      "bearerToken": "${ARGOCD_APP_CLUSTER_TOKEN}",
      "tlsClientConfig": { ${_tls_client_config} }
    }
EOF
  _kubectl apply -f "$rendered"
  rm -f "$rendered"
  trap - RETURN
  (( _wasx )) && set -x

  _info "[argocd] cluster secret applied — verify with: kubectl get secret ${ARGOCD_APP_CLUSTER_SECRET_NAME} -n ${ARGOCD_NAMESPACE}"
  _argocd_set_active_app_cluster "${ARGOCD_APP_CLUSTER_NAME}"
}

function deploy_argocd_platform_ops() {
   if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      cat <<'HELP'
Usage: deploy_argocd_platform_ops

Deploy the platform-ops namespace, RBAC, CVE scan CronJob, and notification Secret
for the ArgoCD CVE upgrade pipeline. CronJob runs on this Hub cluster (k3d) and
patches cluster secrets directly — no webhook dependency.

All credentials are optional — missing vars disable that channel gracefully.

Required env vars (all optional — missing = channel disabled):
  SENDGRID_API_KEY        SendGrid v3 API key
  PAGERDUTY_ROUTING_KEY   PagerDuty Events API v2 routing key
  NOTIFICATION_EMAIL      Recipient email address
  NOTIFICATION_FROM       Sender address (default: argocd-cve@k3d-manager)

After deploying, optionally create the OCI kubeconfig Secret to enable OCI upgrades:
  kubectl create secret generic oci-kubeconfig \
    --from-file=config=/path/to/oci-kubeconfig -n platform-ops
HELP
      return 0
   fi

   local _dir="${ARGOCD_CONFIG_DIR}/platform-ops"

   _info "[argocd] Ensuring platform-ops namespace..."
   _kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: platform-ops
  labels:
    managed-by: k3d-manager
EOF

   _info "[argocd] Deploying RBAC..."
   _kubectl apply -f "${_dir}/rbac.yaml"

   _info "[argocd] Deploying CVE scan CronJob..."
   _kubectl apply -f "${_dir}/cve-scan-cronjob.yaml"

   _info "[argocd] Deploying app-image CVE scan CronJob..."
   _kubectl apply -f "${_dir}/app-cve-scan-cronjob.yaml"

   _info "[argocd] Deploying scan script ConfigMap..."
   _kubectl create configmap argocd-cve-scan-script \
      --from-file=cve-scan.sh="${_dir}/cve-scan.sh" \
      --from-file=app-cve-scan.sh="${_dir}/app-cve-scan.sh" \
      --from-file=notify.sh="${_dir}/notify.sh" \
      --namespace platform-ops \
      --dry-run=client -o yaml | _kubectl apply -f -

   _info "[argocd] Deploying notification Secret scaffold..."
   NOTIFICATION_FROM="${NOTIFICATION_FROM:-argocd-cve@k3d-manager}" \
   SENDGRID_API_KEY="${SENDGRID_API_KEY:-}" \
   PAGERDUTY_ROUTING_KEY="${PAGERDUTY_ROUTING_KEY:-}" \
   NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}" \
   envsubst '$SENDGRID_API_KEY $PAGERDUTY_ROUTING_KEY $NOTIFICATION_EMAIL $NOTIFICATION_FROM' \
     < "${_dir}/notification-secret.yaml.tmpl" | _kubectl apply -f -

   _info "[argocd] Deploying ACG expiry ConfigMap script..."
   _kubectl create configmap acg-expiry-script \
      --from-file=acg-expiry.sh="${_dir}/acg-expiry.sh" \
      --namespace platform-ops \
      --dry-run=client -o yaml | _kubectl apply -f -

   _info "[argocd] Deploying ACG expiry CronJob..."
   _kubectl apply -f "${_dir}/acg-expiry-cronjob.yaml"

   _info "[argocd] Deploying PrometheusRule..."
   _kubectl apply -f "${_dir}/prometheusrule.yaml"

   _info "[argocd] Deploying AlertmanagerConfig..."
   _kubectl apply -f "${_dir}/alertmanager-config.yaml"

   _info "[argocd] platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m"
   _info "[argocd] Secrets to create manually:"
   _info "[argocd]   kubectl create secret generic oci-kubeconfig --from-file=config=<path> -n platform-ops"
   _info "[argocd]   kubectl create secret generic platform-ops-app-rebuild --from-literal=gh-token=<token> -n platform-ops"
   _info "[argocd]   kubectl create secret generic k3dm-webhook-token --from-literal=token=<token> -n cicd"
   _info "[argocd]   kubectl patch secret platform-ops-notifications -n platform-ops --type=merge \\"
   _info "[argocd]     -p '{\"data\":{\"slack-incoming-webhook-url\":\"<base64-url>\"}}'"
}
