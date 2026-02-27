#!/usr/bin/env bash
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

function deploy_argocd() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<EOF
Usage: deploy_argocd [options]

Deploy Argo CD GitOps platform with LDAP authentication and Istio ingress.

Options:
   --enable-ldap            Enable LDAP authentication via Dex
   --enable-vault           Enable Vault integration for admin credentials
   --skip-istio             Skip Istio VirtualService creation
   --bootstrap              Deploy AppProjects and ApplicationSets for GitOps
   --skip-applicationsets   Skip ApplicationSet deployment (requires --bootstrap)
   --skip-appproject        Skip AppProject deployment (requires --bootstrap)
   -h, --help               Show this help message

Environment Variables:
   ARGOCD_NAMESPACE              Namespace for Argo CD (default: argocd)
   ARGOCD_HELM_RELEASE          Helm release name (default: argocd)
   ARGOCD_VIRTUALSERVICE_HOST   Istio VirtualService hostname (default: argocd.dev.local.me)

Examples:
   # Basic deployment
   ./scripts/k3d-manager deploy_argocd

   # With LDAP and Vault integration
   ./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault

   # With GitOps bootstrap (AppProjects + ApplicationSets)
   ./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault --bootstrap

   # Bootstrap with only AppProject (no ApplicationSets)
   ./scripts/k3d-manager deploy_argocd --bootstrap --skip-applicationsets

EOF
      return 0
   fi

   local enable_ldap=0
   local enable_vault=0
   local skip_istio=0
   local enable_bootstrap=0
   local skip_applicationsets=0
   local skip_appproject=0

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --enable-ldap)
            enable_ldap=1
            shift
            ;;
         --enable-vault)
            enable_vault=1
            shift
            ;;
         --skip-istio)
            skip_istio=1
            shift
            ;;
         --bootstrap)
            enable_bootstrap=1
            shift
            ;;
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

   _info "[argocd] Starting Argo CD deployment"
   _info "[argocd] Namespace: $ARGOCD_NAMESPACE"
   _info "[argocd] Helm release: $ARGOCD_HELM_RELEASE"

   # Check if Helm release already exists
   local release_exists=0
   if _run_command --no-exit -- helm -n "$ARGOCD_NAMESPACE" status "$ARGOCD_HELM_RELEASE" > /dev/null 2>&1; then
      release_exists=1
      _info "[argocd] Existing release found; will upgrade"
   fi

   # Determine if we should skip Helm repo operations
   local skip_repo_ops=0
   case "$ARGOCD_HELM_CHART_REF" in
      /*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac
   case "$ARGOCD_HELM_REPO_URL" in
      ""|/*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac

   # Add Helm repository if not using local chart
   if (( ! skip_repo_ops )); then
      _info "[argocd] Adding Helm repository: $ARGOCD_HELM_REPO_NAME"
      _helm repo add "$ARGOCD_HELM_REPO_NAME" "$ARGOCD_HELM_REPO_URL"
      _helm repo update >/dev/null 2>&1
   fi

   # Prepare Helm values
   _info "[argocd] Installing Argo CD via Helm"
   local -a helm_args=(
      --create-namespace
   )

   # Add version if specified
   if [[ -n "${ARGOCD_HELM_CHART_VERSION:-}" ]]; then
      helm_args+=(--version "$ARGOCD_HELM_CHART_VERSION")
   fi

   # Use values template if LDAP is enabled, otherwise use basic settings
   local values_file=""
   if (( enable_ldap )); then
      _info "[argocd] Configuring LDAP/Dex authentication"
      values_file="/tmp/argocd-values-${RANDOM}.yaml"
      # Use envsubst with variable whitelist to preserve $dex references and LDAP filter placeholders
      envsubst '$ARGOCD_VIRTUALSERVICE_HOST $ARGOCD_SERVER_INSECURE $ARGOCD_LDAP_HOST $ARGOCD_LDAP_PORT $ARGOCD_LDAP_BIND_DN $ARGOCD_LDAP_USER_SEARCH_BASE $ARGOCD_LDAP_BASE_DN $ARGOCD_LDAP_GROUP_SEARCH_BASE $ARGOCD_RBAC_DEFAULT_POLICY $ARGOCD_RBAC_ADMIN_GROUP $ARGOCD_SERVER_REPLICAS $ARGOCD_REPO_SERVER_REPLICAS $ARGOCD_APPLICATIONSET_REPLICAS' \
         < "$ARGOCD_CONFIG_DIR/values.yaml.tmpl" > "$values_file"
      helm_args+=(--values "$values_file")
   else
      helm_args+=(
         --set "server.insecure=true"
         --set "server.service.type=ClusterIP"
      )
   fi

   # Install or upgrade Argo CD
   # Use --reset-values for upgrades to avoid conflicts with previous installation
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

   # Clean up temporary values file
   if [[ -n "$values_file" && -f "$values_file" ]]; then
      rm -f "$values_file"
   fi

   # Wait for server deployment to be ready
   _info "[argocd] Waiting for Argo CD server to be ready..."
   if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=available --timeout=180s deployment/argocd-server 2>/dev/null; then
      _warn "[argocd] Timeout waiting for argocd-server deployment; check status manually"
   fi

   # Wait for other core deployments
   if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=available --timeout=120s deployment/argocd-repo-server 2>/dev/null; then
      _warn "[argocd] Timeout waiting for argocd-repo-server deployment"
   fi

   _info "[argocd] Argo CD deployed successfully"
   _info "[argocd] Namespace: $ARGOCD_NAMESPACE"
   _info "[argocd] Server: argocd-server.$ARGOCD_NAMESPACE.svc.cluster.local"

   # Configure Vault/ESO integration for credentials
   if (( enable_vault )); then
      _info "[argocd] Configuring Vault/ESO integration"

      # Setup Vault policies and SecretStore first
      _info "[argocd] Creating SecretStore and ServiceAccount"
      _argocd_setup_vault_policies
      envsubst < "$ARGOCD_CONFIG_DIR/secretstore.yaml.tmpl" | _kubectl apply -f - >/dev/null

      # Wait for SecretStore to be ready
      sleep 2

      # Deploy LDAP bind password secret if LDAP is enabled
      if (( enable_ldap )); then
         _info "[argocd] Creating LDAP bind password ExternalSecret"
         envsubst < "$ARGOCD_CONFIG_DIR/externalsecret-ldap.yaml.tmpl" | _kubectl apply -f - >/dev/null

         # Wait for LDAP secret to sync
         if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$ARGOCD_LDAP_SECRET_NAME" 2>/dev/null; then
            _warn "[argocd] Timeout waiting for LDAP ExternalSecret; check ESO status"
         fi
      fi

      # Deploy admin credentials secret
      _info "[argocd] Creating admin credentials ExternalSecret"
      envsubst < "$ARGOCD_CONFIG_DIR/externalsecret-admin.yaml.tmpl" | _kubectl apply -f - >/dev/null

      # Wait for admin secret to sync
      if ! _kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$ARGOCD_ADMIN_SECRET_NAME" 2>/dev/null; then
         _warn "[argocd] Timeout waiting for admin ExternalSecret; check ESO status"
      fi

      _info "[argocd] Vault/ESO integration configured"
   fi

   # Deploy Istio VirtualService for UI access
   if (( ! skip_istio )); then
      _info "[argocd] Creating Istio VirtualService"
      envsubst < "$ARGOCD_CONFIG_DIR/virtualservice.yaml.tmpl" | _kubectl apply -f - >/dev/null
      _info "[argocd] Argo CD UI accessible at: https://$ARGOCD_VIRTUALSERVICE_HOST"
   fi

   # Deploy GitOps bootstrap if requested
   if (( enable_bootstrap )); then
      _info "[argocd] Deploying GitOps bootstrap resources"

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
   fi

   # Print next steps
   _info "[argocd] Deployment complete!"
   if (( enable_vault )); then
      _info "[argocd] Retrieve admin password: kubectl -n $ARGOCD_NAMESPACE get secret $ARGOCD_ADMIN_SECRET_NAME -o jsonpath='{.data.password}' | base64 -d"
   else
      _info "[argocd] Retrieve initial admin password: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
   fi

   return 0
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

function deploy_argocd_bootstrap() {
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

   local appproject_file="$ARGOCD_CONFIG_DIR/projects/platform.yaml"

   if [[ ! -f "$appproject_file" ]]; then
      _err "[argocd] AppProject file not found: $appproject_file"
      return 1
   fi

   _kubectl apply -f "$appproject_file" >/dev/null

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

      if _kubectl apply -f "$file" >/dev/null 2>&1; then
         ((deployed_count++))
      else
         _warn "[argocd] Failed to deploy ApplicationSet: $filename"
      fi
   done

   _info "[argocd] Successfully deployed $deployed_count/${#appset_files[@]} ApplicationSet(s)"
   return 0
}
