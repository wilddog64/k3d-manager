# shellcheck shell=bash

# OrbStack provider piggybacks on k3d but ensures the Docker context targets
# OrbStack's runtime and skips redundant Docker installation steps.

if ! declare -f _provider_k3d_create_cluster >/dev/null 2>&1; then
   # shellcheck source=/dev/null
   source "${SCRIPT_DIR}/lib/providers/k3d.sh"
fi

function _provider_orbstack__ensure_runtime() {
   if ! _orbstack_detect; then
      if declare -f _install_orbstack >/dev/null 2>&1; then
         _install_orbstack
      fi
   fi

   if ! _orbstack_detect; then
      _err "OrbStack CLI not found or OrbStack is not running. Install OrbStack, complete the GUI setup, and ensure 'orb status' reports it is running."
   fi

   _provider_orbstack__set_docker_context
}

function _provider_orbstack__set_docker_context() {
   if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
      return 0
   fi

   local context
   context=$(_orbstack_find_docker_context 2>/dev/null || true)

   if [[ -n "$context" ]]; then
      export DOCKER_CONTEXT="$context"
   fi
}

function _provider_orbstack_exec() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_exec "$@"
}

function _provider_orbstack_cluster_exists() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_cluster_exists "$@"
}

function _provider_orbstack_list_clusters() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_list_clusters "$@"
}

function _provider_orbstack_apply_cluster_config() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_apply_cluster_config "$@"
}

function _provider_orbstack_install() {
   _provider_orbstack__ensure_runtime

   SKIP_DOCKER_SETUP=1 _provider_k3d_install "$@"
}

function _provider_orbstack_configure_istio() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_configure_istio "$@"
}

function _provider_orbstack_create_cluster() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_create_cluster "$@"
}

function _provider_orbstack_destroy_cluster() {
   _provider_orbstack__ensure_runtime
   _provider_k3d_destroy_cluster "$@"
}

function _provider_orbstack_deploy_cluster() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_cluster [cluster_name=k3d-cluster]"
      echo "OrbStack provider auto-detects the OrbStack Docker context."
      return 0
   fi

   _provider_orbstack__ensure_runtime

   local cluster_name="${1:-k3d-cluster}"

   if _is_mac; then
      _provider_orbstack_install "$HOME/.local/bin"
   else
      _provider_orbstack_install /usr/local/bin
   fi

   if ! _provider_orbstack_cluster_exists "$cluster_name" ; then
      _provider_orbstack_create_cluster "$cluster_name"
   fi

   _provider_orbstack_configure_istio "$cluster_name"
}
