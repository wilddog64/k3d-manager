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
   --enable-ldap       Enable LDAP authentication via Dex
   --enable-vault      Enable Vault integration for admin credentials
   --skip-istio        Skip Istio VirtualService creation
   -h, --help          Show this help message

Environment Variables:
   ARGOCD_NAMESPACE              Namespace for Argo CD (default: argocd)
   ARGOCD_HELM_RELEASE          Helm release name (default: argocd)
   ARGOCD_VIRTUALSERVICE_HOST   Istio VirtualService hostname (default: argocd.dev.local.me)

Examples:
   # Basic deployment
   ./scripts/k3d-manager deploy_argocd

   # With LDAP and Vault integration
   ./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault

EOF
      return 0
   fi

   local enable_ldap=0
   local enable_vault=0
   local skip_istio=0

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
      # Use envsubst with variable whitelist to preserve $dex references in Dex config
      envsubst '$ARGOCD_VIRTUALSERVICE_HOST $ARGOCD_SERVER_INSECURE $ARGOCD_LDAP_HOST $ARGOCD_LDAP_PORT $ARGOCD_LDAP_BIND_DN $ARGOCD_LDAP_USER_SEARCH_BASE $ARGOCD_LDAP_BASE_DN $ARGOCD_LDAP_USER_SEARCH_FILTER $ARGOCD_LDAP_GROUP_SEARCH_BASE $ARGOCD_LDAP_GROUP_SEARCH_FILTER $ARGOCD_RBAC_DEFAULT_POLICY $ARGOCD_RBAC_ADMIN_GROUP $ARGOCD_SERVER_REPLICAS $ARGOCD_REPO_SERVER_REPLICAS $ARGOCD_APPLICATIONSET_REPLICAS' \
         < "$ARGOCD_CONFIG_DIR/values.yaml.tmpl" > "$values_file"
      helm_args+=(--values "$values_file")
   else
      helm_args+=(
         --set "server.insecure=true"
         --set "server.service.type=ClusterIP"
      )
   fi

   # Install or upgrade Argo CD
   _helm upgrade --install \
      -n "$ARGOCD_NAMESPACE" \
      "$ARGOCD_HELM_RELEASE" \
      "$ARGOCD_HELM_CHART_REF" \
      "${helm_args[@]}"

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
