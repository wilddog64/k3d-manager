#!/usr/bin/env bash

CERT_MANAGER_CONFIG_DIR="$SCRIPT_DIR/etc/cert-manager"
CERT_MANAGER_VARS="$CERT_MANAGER_CONFIG_DIR/vars.sh"

if [[ ! -r "$CERT_MANAGER_VARS" ]]; then
   _err "[cert-manager] Configuration file not found: $CERT_MANAGER_VARS"
else
   # shellcheck disable=SC1090
   source "$CERT_MANAGER_VARS"
fi

function deploy_cert_manager() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<'USAGE'
Usage: deploy_cert_manager [--production] [--skip-issuer]

Install cert-manager via Helm and configure ACME ClusterIssuers.

Options:
  --production    Use the production Let's Encrypt endpoint
  --skip-issuer   Install cert-manager only (skip ClusterIssuer + Gateway)
  -h, --help      Show this help message
USAGE
      return 0
   fi

   local use_production=0
   local skip_issuer=0

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --production)
            use_production=1
            shift
            ;;
         --skip-issuer)
            skip_issuer=1
            shift
            ;;
         -h|--help)
            cat <<'USAGE'
Usage: deploy_cert_manager [--production] [--skip-issuer]
USAGE
            return 0
            ;;
         *)
            _err "[cert-manager] Unknown option: $1"
            return 1
            ;;
      esac
   done

   _info "[cert-manager] Installing cert-manager Helm release"
   _cert_manager_helm_install || return 1

   if ! _cert_manager_wait_webhook; then
      _err "[cert-manager] cert-manager webhook failed to become Ready"
      return 1
   fi

   if (( skip_issuer )); then
      _info "[cert-manager] --skip-issuer specified; skipping ClusterIssuer configuration"
      return 0
   fi

   _cert_manager_validate_email || return 1
   _cert_manager_configure_issuer_flow "$use_production"
   return 0
}

function _cert_manager_helm_install() {
   local skip_repo_ops=0

   case "$CERT_MANAGER_HELM_CHART_REF" in
      /*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac

   case "$CERT_MANAGER_HELM_REPO_URL" in
      ""|/*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac

   if (( ! skip_repo_ops )); then
      _helm repo add "$CERT_MANAGER_HELM_REPO_NAME" "$CERT_MANAGER_HELM_REPO_URL"
      _helm repo update >/dev/null 2>&1
   fi

   local -a helm_args=(
      --create-namespace
      --set crds.enabled=true
   )

   if [[ -n "${CERT_MANAGER_HELM_CHART_VERSION:-}" ]]; then
      helm_args+=(--version "$CERT_MANAGER_HELM_CHART_VERSION")
   fi

   _helm upgrade --install \
      -n "$CERT_MANAGER_NAMESPACE" \
      "$CERT_MANAGER_HELM_RELEASE" \
      "$CERT_MANAGER_HELM_CHART_REF" \
      "${helm_args[@]}"
}

function _cert_manager_wait_webhook() {
   if ! _kubectl -n "$CERT_MANAGER_NAMESPACE" wait --for=condition=available --timeout=120s deployment/cert-manager-webhook >/dev/null 2>&1; then
      return 1
   fi
   return 0
}

function _cert_manager_apply_gateway() {
   local template="$CERT_MANAGER_CONFIG_DIR/http-gateway.yaml.tmpl"
   if [[ ! -f "$template" ]]; then
      _err "[cert-manager] Gateway template missing: $template"
      return 1
   fi

   envsubst "\$CERT_MANAGER_HTTP_GATEWAY \$CERT_MANAGER_HTTP_GATEWAY_NS" < "$template" | _kubectl apply -f - >/dev/null
}

function _cert_manager_apply_issuer() {
   local mode="$1"

   if [[ -z "${ACME_EMAIL:-}" ]]; then
      _err "[cert-manager] ACME_EMAIL must be set before applying a ClusterIssuer"
      return 1
   fi

   local template whitelist
   if [[ "$mode" == "production" ]]; then
      template="$CERT_MANAGER_CONFIG_DIR/clusterissuer-production.yaml.tmpl"
      whitelist="\$CERT_MANAGER_PRODUCTION_ISSUER \$ACME_PRODUCTION_SERVER \$ACME_EMAIL \$ACME_INGRESS_CLASS"
   else
      template="$CERT_MANAGER_CONFIG_DIR/clusterissuer-staging.yaml.tmpl"
      whitelist="\$CERT_MANAGER_STAGING_ISSUER \$ACME_STAGING_SERVER \$ACME_EMAIL \$ACME_INGRESS_CLASS"
   fi

   if [[ ! -f "$template" ]]; then
      _err "[cert-manager] ClusterIssuer template missing: $template"
      return 1
   fi

   local rendered
   rendered=$(mktemp -t cert-manager-issuer.XXXXXX.yaml)
   # shellcheck disable=SC2064
   trap "rm -f '$rendered'" RETURN
   envsubst "$whitelist" < "$template" > "$rendered"
   if [[ -n "${CERT_MANAGER_DEBUG_RENDER:-}" ]]; then
      cp "$rendered" "$CERT_MANAGER_DEBUG_RENDER" >/dev/null 2>&1 || true
   fi
   local rc=0
   _kubectl apply -f "$rendered" >/dev/null || rc=$?
   return "$rc"
}

function _cert_manager_validate_email() {
   if [[ -z "${ACME_EMAIL:-}" ]]; then
      _err "[cert-manager] ACME_EMAIL is required. Set ACME_EMAIL=user@example.com and retry."
      return 1
   fi

   if [[ ! "$ACME_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
      _err "[cert-manager] ACME_EMAIL '$ACME_EMAIL' is invalid."
      return 1
   fi

   return 0
}

function _cert_manager_configure_issuer_flow() {
   local use_production="$1"

   if (( use_production )) && [[ "${CLUSTER_PROVIDER:-}" =~ ^(k3d|orbstack)$ ]]; then
      _warn "[cert-manager] Production issuers require an internet-accessible domain. Use staging to validate locally."
   fi

   if ! _kubectl --no-exit get ingressclass "$ACME_INGRESS_CLASS" >/dev/null 2>&1; then
      _err "[cert-manager] IngressClass '$ACME_INGRESS_CLASS' not found. Enable Istio ingress support before continuing."
      return 1
   fi

   _cert_manager_apply_gateway || return 1

   local issuer_mode="staging"
   local issuer_name="$CERT_MANAGER_STAGING_ISSUER"
   if (( use_production )); then
      issuer_mode="production"
      issuer_name="$CERT_MANAGER_PRODUCTION_ISSUER"
   fi

   _cert_manager_apply_issuer "$issuer_mode" || return 1

   if ! _kubectl --no-exit wait --for=condition=Ready --timeout=60s clusterissuer/"$issuer_name" >/dev/null 2>&1; then
      _err "[cert-manager] ClusterIssuer '$issuer_name' failed to become Ready"
      return 1
   fi

   _info "[cert-manager] ClusterIssuer '$issuer_name' is Ready"
   _info "[cert-manager] Annotate your Ingress: cert-manager.io/cluster-issuer: $issuer_name"
   _info "[cert-manager] Or create a Certificate object referencing ClusterIssuer $issuer_name"
}
