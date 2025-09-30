# shellcheck shell=bash

# load k3s variables
K3S_VARS="$SCRIPT_DIR/etc/k3s/vars.sh"
if [[ ! -r "$K3S_VARS" ]]; then
   _err "k3s vars file not found: $K3S_VARS"
fi
source $K3S_VARS

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
}
