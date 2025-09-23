# shellcheck shell=bash

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
   _install_k3s
}

function _provider_k3s_create_cluster() {
   _deploy_k3s_cluster "$@"
}

function _provider_k3s_destroy_cluster() {
   _teardown_k3s_cluster "$@"
}

function _provider_k3s_deploy_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_cluster [cluster_name=k3s-cluster]"
      return 0
   fi

   local cluster_name="${1:-k3s-cluster}"

   _provider_k3s_install
   _deploy_k3s_cluster "$cluster_name"
}
