# shellcheck shell=bash

# load k3s variables
K3S_VARS="$SCRIPT_DIR/etc/k3s/vars.sh"
if [[ ! -r "$K3S_VARS" ]]; then
   _err "k3s vars file not found: $K3S_VARS"
fi
source "$K3S_VARS"

function _provider_k3s_exec() {
   local pre=()
   while [[ $# -gt 0 ]]; do
      case "$1" in
         --quiet|--prefer-sudo|--require-sudo|--no-exit)
            pre+=("$1")
            shift
            ;;
         --)
            shift
            break
            ;;
         *)
            break
            ;;
      esac
   done

   _run_command "${pre[@]}" --prefer-sudo -- k3s "$@"
}

function _provider_k3s_cluster_exists() {
   _k3s_cluster_exists
}

function _provider_k3s_list_clusters() {
   if _k3s_cluster_exists ; then
      echo "k3s (system)"
      return 0
   fi

   return 1
}

function _provider_k3s_apply_cluster_config() {
   _warn "k3s provider does not support applying external cluster configuration; skipping"
}

function _provider_k3s_install() {
   _install_k3s "$@"
}

function _provider_k3s_create_cluster() {
   _deploy_k3s_cluster "$@"
}

function _provider_k3s_destroy_cluster() {
   # Clean up ingress forwarding service if it exists
   if [[ -f "${K3S_INGRESS_SERVICE_FILE}" ]] || systemctl list-unit-files 2>/dev/null | grep -q "${K3S_INGRESS_SERVICE_NAME}"; then
      _info "Cleaning up ingress forwarding service..."
      _k3s_remove_ingress_forward 2>/dev/null || true
   fi

   _teardown_k3s_cluster "$@"
}

function _provider_k3s_configure_istio() {
   local cluster_name=$1

   local istio_yaml_template="${SCRIPT_DIR}/etc/istio-operator.yaml.tmpl"
   local istio_var="${SCRIPT_DIR}/etc/istio_var.sh"

   if [[ ! -r "$istio_yaml_template" ]]; then
      echo "Istio template file not found: $istio_yaml_template"
      exit 1
   fi

   if [[ ! -r "$istio_var" ]]; then
      echo "Istio variable file not found: $istio_var"
      exit 1
   fi

   # shellcheck disable=SC1090
   source "$istio_var"
   local istio_yamlfile
   istio_yamlfile=$(mktemp -t k3s-istio-operator.XXXXXX.yaml)
   envsubst < "$istio_yaml_template" > "$istio_yamlfile"

   _install_istioctl
   _istioctl x precheck
   _istioctl install -y -f "$istio_yamlfile"
   _kubectl label ns default istio-injection=enabled --overwrite

   trap '$(_cleanup_trap_command "$istio_yamlfile")' EXIT
}

function _provider_k3s_deploy_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_cluster [cluster_name=k3s-cluster]"
      return 0
   fi

   local cluster_name="${1:-k3s-cluster}"
   cluster_name="k3s-${cluster_name}"

   export CLUSTER_NAME="$cluster_name"

   _provider_k3s_install "$cluster_name"
   _deploy_k3s_cluster "$cluster_name"
   _provider_k3s_configure_istio "$cluster_name"

   # Automatically setup ingress port forwarding for k3s
   if [[ "${K3S_INGRESS_FORWARD_ENABLED:-1}" == "1" ]]; then
      _info ""
      _info "Setting up ingress port forwarding..."
      if _k3s_setup_ingress_forward; then
         _info "Ingress forwarding configured successfully"
      else
         _warn "Failed to setup ingress forwarding automatically"
         _warn "You can run it manually later with: CLUSTER_PROVIDER=k3s ./scripts/k3d-manager setup_ingress_forward"
      fi
   else
      _info "Ingress forwarding disabled (K3S_INGRESS_FORWARD_ENABLED=0)"
      _info "To enable later, run: CLUSTER_PROVIDER=k3s ./scripts/k3d-manager setup_ingress_forward"
   fi
}

function _provider_k3s_expose_ingress() {
   local action="${1:-setup}"

   case "$action" in
      setup|enable)
         _k3s_setup_ingress_forward
         ;;
      status)
         _k3s_ingress_forward_status
         ;;
      remove|disable)
         _k3s_remove_ingress_forward
         ;;
      *)
         echo "Usage: expose_ingress {setup|status|remove}"
         echo ""
         echo "Actions:"
         echo "  setup   - Configure and enable ingress port forwarding (default)"
         echo "  status  - Show current forwarding status"
         echo "  remove  - Disable and remove ingress port forwarding"
         return 1
         ;;
   esac
}

function _k3s_setup_ingress_forward() {
   _info "Setting up k3s ingress port forwarding..."

   # Check prerequisites and get socat path
   local socat_path
   if ! socat_path=$(command -v socat 2>/dev/null); then
      _warn "socat is not installed"
      _info "Installing socat..."
      _run_command --prefer-sudo -- apt-get update -qq
      _run_command --prefer-sudo -- apt-get install -y socat
      socat_path=$(command -v socat 2>/dev/null)
   fi

   if [[ -z "$socat_path" ]]; then
      _err "Failed to locate socat after installation"
      return 1
   fi

   # Get Istio IngressGateway NodePort for HTTPS
   local istio_https_nodeport
   istio_https_nodeport=$(_kubectl get svc -n istio-system istio-ingressgateway \
      -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null)

   if [[ -z "$istio_https_nodeport" ]]; then
      _err "Could not detect Istio IngressGateway HTTPS NodePort"
      _err "Is Istio deployed? Run: ./scripts/k3d-manager deploy_cluster"
      return 1
   fi

   # Auto-detect node IP
   local node_ip
   node_ip="${K3S_NODE_IP:-${NODE_IP:-}}"

   if [[ -z "$node_ip" ]]; then
      # Try to detect from default route
      node_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K[^ ]+' 2>/dev/null || echo "127.0.0.1")
   fi

   _info "Detected configuration:"
   _info "  socat path: $socat_path"
   _info "  Istio HTTPS NodePort: $istio_https_nodeport"
   _info "  Node IP: $node_ip"
   _info "  External HTTPS Port: ${K3S_INGRESS_FORWARD_HTTPS_PORT}"

   # Generate systemd service file
   local service_template="${SCRIPT_DIR}/etc/k3s/ingress-forward.service.tmpl"
   local service_file="${K3S_INGRESS_SERVICE_FILE}"

   if [[ ! -f "$service_template" ]]; then
      _err "Service template not found: $service_template"
      return 1
   fi

   export SOCAT_PATH="${socat_path}"
   export HTTPS_PORT="${K3S_INGRESS_FORWARD_HTTPS_PORT}"
   export INGRESS_TARGET_IP="${node_ip}"
   export INGRESS_TARGET_HTTPS_PORT="${istio_https_nodeport}"

   local temp_service
   temp_service=$(mktemp)
   envsubst < "$service_template" > "$temp_service"

   # Install service file
   _run_command --prefer-sudo -- cp "$temp_service" "$service_file"
   _run_command --prefer-sudo -- chmod 644 "$service_file"
   rm -f "$temp_service"

   # Reload systemd and enable service
   _run_command --prefer-sudo -- systemctl daemon-reload
   _run_command --prefer-sudo -- systemctl enable "${K3S_INGRESS_SERVICE_NAME}"
   _run_command --prefer-sudo -- systemctl restart "${K3S_INGRESS_SERVICE_NAME}"

   _info "Ingress port forwarding configured successfully"
   _info ""
   _info "Port forwarding active:"
   _info "  External port ${K3S_INGRESS_FORWARD_HTTPS_PORT} -> Istio IngressGateway ${node_ip}:${istio_https_nodeport}"
   _info ""

   # Detect WSL and provide specific instructions
   if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
      _warn "WSL detected - additional configuration may be needed for Windows access"
      _info ""
      _info "To access from within WSL:"
      _info "  Add to /etc/hosts:"
      _info "    127.0.0.1 jenkins.dev.local.me"
      _info "    127.0.0.1 argocd.dev.local.me"
      _info ""
      _info "To access from Windows host:"
      _info "  1. Get WSL IP: hostname -I"
      _info "  2. Add to C:\\Windows\\System32\\drivers\\etc\\hosts:"
      _info "     <WSL-IP> jenkins.dev.local.me"
      _info "     <WSL-IP> argocd.dev.local.me"
      _info "  3. Access via NodePort: https://jenkins.dev.local.me:${istio_https_nodeport}/"
      _info ""
      _info "For port 443 access from Windows, see:"
      _info "  docs/architecture/ingress-port-forwarding.md#wsl-windows-access"
   else
      _info "Add these entries to /etc/hosts on client machines:"
      _info "  ${node_ip} jenkins.dev.local.me"
      _info "  ${node_ip} argocd.dev.local.me"
      _info ""
      _info "Then access services:"
      _info "  https://jenkins.dev.local.me/"
      _info "  https://argocd.dev.local.me/"
   fi
}

function _k3s_ingress_forward_status() {
   local service_name="${K3S_INGRESS_SERVICE_NAME}"
   local service_file="${K3S_INGRESS_SERVICE_FILE}"

   _info "Ingress forwarding status:"
   echo ""

   if [[ -f "$service_file" ]]; then
      _info "Service file: $service_file (exists)"

      if systemctl is-active --quiet "$service_name"; then
         _info "Status: ACTIVE"
      elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
         _warn "Status: ENABLED but not running"
      else
         _warn "Status: INACTIVE"
      fi

      echo ""
      _info "Service details:"
      systemctl status "$service_name" --no-pager -l || true

      echo ""
      _info "Port listeners:"
      _run_command --quiet -- ss -tlnp 2>/dev/null | grep ":${K3S_INGRESS_FORWARD_HTTPS_PORT}" || \
         _warn "Port ${K3S_INGRESS_FORWARD_HTTPS_PORT} not listening"
   else
      _warn "Service file not found: $service_file"
      _info "Ingress forwarding is not configured"
      _info "Run: ./scripts/k3d-manager expose_ingress setup"
   fi
}

function _k3s_remove_ingress_forward() {
   local service_name="${K3S_INGRESS_SERVICE_NAME}"
   local service_file="${K3S_INGRESS_SERVICE_FILE}"

   _info "Removing k3s ingress port forwarding..."

   if systemctl is-active --quiet "$service_name" 2>/dev/null; then
      _info "Stopping service: $service_name"
      _run_command --prefer-sudo -- systemctl stop "$service_name"
   fi

   if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
      _info "Disabling service: $service_name"
      _run_command --prefer-sudo -- systemctl disable "$service_name"
   fi

   if [[ -f "$service_file" ]]; then
      _info "Removing service file: $service_file"
      _run_command --prefer-sudo -- rm -f "$service_file"
   fi

   _run_command --prefer-sudo -- systemctl daemon-reload

   _info "Ingress port forwarding removed"
}
