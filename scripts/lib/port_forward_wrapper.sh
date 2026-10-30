# shellcheck shell=bash
# shellcheck disable=SC2016
# scripts/lib/port_forward_wrapper.sh
# Renders a self-healing kubectl port-forward wrapper from etc/argocd/port-forward-wrapper.sh.tmpl.
# Needs SCRIPT_DIR (the repo scripts/ dir) and _err. Sourced by plugins/argocd.sh and bin/hub-restore.

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
   local address="${12:-127.0.0.1}"
   local log_tag="${13:-argocd-pf}"

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

   local q_kubectl_bin q_curl_bin q_log_file q_kubeconfig_file q_namespace q_context q_service q_local_port q_remote_port q_healthz_url q_startup_timeout q_address q_log_tag
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
   printf -v q_address '%q' "$address"
   printf -v q_log_tag '%q' "$log_tag"

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
   ADDRESS="$q_address" \
   LOG_TAG="$q_log_tag" \
      envsubst '$KUBECTL_BIN $CURL_BIN $LOG_FILE $KUBECONFIG_FILE $NAMESPACE $CONTEXT $SERVICE $LOCAL_PORT $REMOTE_PORT $HEALTHZ_URL $STARTUP_TIMEOUT $ADDRESS $LOG_TAG' \
         < "$template_path" > "$wrapper_path"
   chmod 700 "$wrapper_path"
}
