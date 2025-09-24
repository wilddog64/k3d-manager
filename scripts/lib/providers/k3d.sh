# shellcheck shell=bash

function _provider_k3d_exec() {
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

   _run_command "${pre[@]}" -- k3d "$@"
}

function _provider_k3d_cluster_exists() {
   local cluster_name=$1

   if _run_command --no-exit -- k3d cluster list "$cluster_name" >/dev/null 2>&1 ; then
      return 0
   else
      return 1
   fi
}

function _provider_k3d_list_clusters() {
   _run_command --quiet -- k3d cluster list
}

function _provider_k3d_apply_cluster_config() {
   local cluster_yaml=$1

   if _is_mac ; then
      _run_command --quiet -- k3d cluster create --config "${cluster_yaml}"
   else
      _run_command k3d cluster create --config "${cluster_yaml}"
   fi
}

function _provider_k3d_install() {
   export K3D_INSTALL_DIR="${1:-/usr/local/bin}"
   export INSTALL_DIR="$K3D_INSTALL_DIR"

   _install_docker
   _install_helm
   if _is_mac; then
      _install_istioctl "$HOME/.local/bin"
   else
      _install_istioctl
   fi

   if ! _command_exist k3d ; then
      echo k3d does not exist, install it
      _curl -f -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | INSTALL_DIR="$K3D_INSTALL_DIR" bash
   else
      echo k3d installed already
   fi
}

function _provider_k3d_configure_istio() {
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
   istio_yamlfile=$(mktemp -t)
   envsubst < "$istio_yaml_template" > "$istio_yamlfile"

   _install_istioctl
   _istioctl x precheck
   _istioctl install -y -f "$istio_yamlfile"
   _kubectl label ns default istio-injection=enabled --overwrite

   trap "$(_cleanup_trap_command "$istio_yamlfile")" EXIT
}

function _provider_k3d_create_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: create_cluster <cluster_name> [http_port=8000] [https_port=8443]"
      return 0
   fi

   local cluster_name=$1
   local http_port="${2:-8000}"
   local https_port="${3:-8443}"

   export CLUSTER_NAME="$cluster_name"
   export HTTP_PORT="$http_port"
   export HTTPS_PORT="$https_port"

   if [[ -z "$cluster_name" ]]; then
      echo "Cluster name is required"
      exit 1
   fi

   local cluster_template="${SCRIPT_DIR}/etc/cluster.yaml.tmpl"
   local cluster_var="${SCRIPT_DIR}/etc/cluster_var.sh"

   if [[ ! -r "$cluster_template" ]]; then
      echo "Cluster template file not found: $cluster_template"
      exit 1
   fi

   if [[ ! -r "$cluster_var" ]]; then
      echo "Cluster variable file not found: $cluster_var"
      exit 1
   fi

   # shellcheck disable=SC1090
   source "$cluster_var"

   local yamlfile
   yamlfile=$(mktemp -t)
   envsubst < "$cluster_template" > "$yamlfile"

   trap "$(_cleanup_trap_command "$yamlfile")" RETURN

   if _provider_k3d_list_clusters | grep -q "$cluster_name"; then
      echo "Cluster $cluster_name already exists, skip"
      return 0
   fi

   _provider_k3d_apply_cluster_config "$yamlfile"
}

function _provider_k3d_destroy_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: destroy_cluster <cluster_name>"
      return 0
   fi

   local cluster_name=$1

   if [[ -z "$cluster_name" ]]; then
      echo "Cluster name is required"
      exit 1
   fi

   if ! _provider_k3d_cluster_exists "$cluster_name"; then
      _info "Cluster $cluster_name does not exist, skip"
      return 0
   fi

   _info "Deleting k3d cluster: $cluster_name"
   _provider_k3d_exec cluster delete "$cluster_name"
}

function _provider_k3d_deploy_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_cluster [cluster_name=k3d-cluster]"
      echo "Set CLUSTER_PROVIDER to choose a different backend."
      return 0
   fi

   local cluster_name="${1:-k3d-cluster}"

   if _is_mac; then
      _provider_k3d_install "$HOME/.local/bin"
   else
      _provider_k3d_install /usr/local/bin
   fi

   if ! _provider_k3d_cluster_exists "$cluster_name" ; then
      _provider_k3d_create_cluster "$cluster_name"
   fi
   _provider_k3d_configure_istio "$cluster_name"
}
