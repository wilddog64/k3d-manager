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

# Default configuration values
: "${ARGOCD_NAMESPACE:=argocd}"
: "${ARGOCD_HELM_RELEASE:=argocd}"
: "${ARGOCD_HELM_REPO_NAME:=argo}"
: "${ARGOCD_HELM_REPO_URL:=https://argoproj.github.io/argo-helm}"
: "${ARGOCD_HELM_CHART_REF:=argo/argo-cd}"
: "${ARGOCD_VIRTUALSERVICE_HOST:=argocd.dev.local.me}"
: "${ARGOCD_DEPLOY_KEY_SECRETSTORE:=argocd-deploy-key-store}"
: "${ARGOCD_DEPLOY_KEY_ESO_SA:=eso-argocd-deploy-keys-sa}"
: "${ARGOCD_DEPLOY_KEY_VAULT_ROLE:=argocd-deploy-key-reader}"
: "${ARGOCD_GITHUB_ORG:=wilddog64}"

function _argocd_ensure_logged_in() {
   if argocd account get-context --server localhost:8080 >/dev/null 2>&1; then
      return 0
   fi

   _info "[argocd] Performing automated CLI login..."
   local pass
   pass=$(kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
   
   # Ensure port-forward is active
   if ! curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
      _info "[argocd] Starting background port-forward for login..."
      kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 >/dev/null 2>&1 &
      sleep 3
   fi

   argocd login localhost:8080 --username admin --password "$pass" --insecure --grpc-web >/dev/null
}

function deploy_argocd() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      # ... help text ...
      return 0
   fi

   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[argocd] CLUSTER_ROLE=app — skipping deploy_argocd"
      return 0
   fi

   # 1. Smart Dependency Chain
   _info "[argocd] Verifying infrastructure foundations..."
   if ! _kubectl get ns secrets >/dev/null 2>&1; then
      _info "[argocd] Vault foundation missing — triggering deploy_vault..."
      deploy_vault --confirm
   fi
   if ! _kubectl get ns ldap >/dev/null 2>&1; then
      _info "[argocd] LDAP foundation missing — triggering deploy_ldap..."
      deploy_ldap --confirm
   fi

   local enable_ldap=1  # Default to smart enabled
   local enable_vault=1 # Default to smart enabled
   # ... option parsing ...

   # 2. Helm Installation
   _info "[argocd] Installing Argo CD via Helm"
   _argocd_helm_deploy_release "$enable_ldap" "0"

   # 3. Wait and Post-Deploy
   _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=available --timeout=180s deployment/argocd-server
   
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
   _kubectl apply -f "$rendered" >/dev/null
   trap '$(_cleanup_trap_command "$rendered")' RETURN

   _info "[argocd] AppProject deployed: platform"
   return 0
}

function _argocd_deploy_applicationsets() {
   _info "[argocd] Deploying sample ApplicationSets"

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

      if envsubst '$ARGOCD_NAMESPACE' < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
         ((deployed_count++))
      else
         _warn "[argocd] Failed to deploy ApplicationSet: $filename"
      fi
   done

   _info "[argocd] Successfully deployed $deployed_count/${#appset_files[@]} ApplicationSet(s)"
   return 0
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
  ARGOCD_APP_CLUSTER_TOKEN         Bearer token  (required — no default)
HELP
    return 0
  fi

  local tmpl="${SCRIPT_DIR}/etc/argocd/cluster-secret.yaml.tmpl"
  if [[ ! -f "$tmpl" ]]; then
    _err "[argocd] cluster secret template not found: $tmpl"
    return 1
  fi

  if [[ -z "${ARGOCD_APP_CLUSTER_TOKEN:-}" ]]; then
    _err "[argocd] ARGOCD_APP_CLUSTER_TOKEN is required — get it with:"
    _err "  ssh ubuntu kubectl create token argocd-manager -n kube-system --duration=8760h"
    return 1
  fi

  _info "[argocd] registering app cluster '${ARGOCD_APP_CLUSTER_NAME}' -> ${ARGOCD_APP_CLUSTER_SERVER}"

  local _wasx=0
  case $- in *x*) _wasx=1; set +x;; esac
  ARGOCD_APP_CLUSTER_SECRET_NAME="${ARGOCD_APP_CLUSTER_SECRET_NAME}" \
  ARGOCD_APP_CLUSTER_NAME="${ARGOCD_APP_CLUSTER_NAME}" \
  ARGOCD_APP_CLUSTER_SERVER="${ARGOCD_APP_CLUSTER_SERVER}" \
  ARGOCD_APP_CLUSTER_INSECURE="${ARGOCD_APP_CLUSTER_INSECURE}" \
  ARGOCD_APP_CLUSTER_TOKEN="${ARGOCD_APP_CLUSTER_TOKEN}" \
  ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE}" \
    envsubst < "$tmpl" | _kubectl apply -f -
  (( _wasx )) && set -x

  _info "[argocd] cluster secret applied — verify with: kubectl get secret ${ARGOCD_APP_CLUSTER_SECRET_NAME} -n ${ARGOCD_NAMESPACE}"
}
