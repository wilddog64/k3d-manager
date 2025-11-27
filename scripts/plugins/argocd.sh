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

   # Phase 1 implementation: Basic deployment placeholder
   _info "[argocd] Phase 1: Core Argo CD deployment"
   _warn "[argocd] Implementation in progress - basic scaffold created"

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
