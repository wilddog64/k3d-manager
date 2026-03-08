#!/usr/bin/env bats
# scripts/tests/lib/provider_contract.bats
# Contract tests: every cluster provider must implement the full interface.

# shellcheck disable=SC1091

# Setup providers directory path
setup() {
  PROVIDERS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib/providers" && pwd)"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)/scripts"
  export SCRIPT_DIR
}

teardown() {
  # Clean up any potential leftover test clusters
  k3d cluster delete "k3d-test-orbstack-exists" 2>/dev/null || true
}

# --- K3D Provider Contract ---

@test "_provider_k3d_exec is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_exec" >/dev/null
}

@test "_provider_k3d_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_cluster_exists" >/dev/null
}

@test "_provider_k3d_list_clusters is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_list_clusters" >/dev/null
}

@test "_provider_k3d_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_apply_cluster_config" >/dev/null
}

@test "_provider_k3d_install is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_install" >/dev/null
}

@test "_provider_k3d_create_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_create_cluster" >/dev/null
}

@test "_provider_k3d_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_destroy_cluster" >/dev/null
}

@test "_provider_k3d_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_deploy_cluster" >/dev/null
}

@test "_provider_k3d_configure_istio is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_configure_istio" >/dev/null
}

@test "_provider_k3d_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_expose_ingress" >/dev/null
}

# --- K3S Provider Contract ---

@test "_provider_k3s_exec is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_exec" >/dev/null
}

@test "_provider_k3s_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_cluster_exists" >/dev/null
}

@test "_provider_k3s_list_clusters is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_list_clusters" >/dev/null
}

@test "_provider_k3s_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_apply_cluster_config" >/dev/null
}

@test "_provider_k3s_install is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_install" >/dev/null
}

@test "_provider_k3s_create_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_create_cluster" >/dev/null
}

@test "_provider_k3s_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_destroy_cluster" >/dev/null
}

@test "_provider_k3s_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_deploy_cluster" >/dev/null
}

@test "_provider_k3s_configure_istio is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_configure_istio" >/dev/null
}

@test "_provider_k3s_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_expose_ingress" >/dev/null
}

# --- OrbStack Provider Contract ---

@test "_provider_orbstack_exec is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_exec" >/dev/null
}

@test "_provider_orbstack_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_cluster_exists" >/dev/null
}

@test "_provider_orbstack_list_clusters is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_list_clusters" >/dev/null
}

@test "_provider_orbstack_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_apply_cluster_config" >/dev/null
}

@test "_provider_orbstack_install is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_install" >/dev/null
}

@test "_provider_orbstack_create_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_create_cluster" >/dev/null
}

@test "_provider_orbstack_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_destroy_cluster" >/dev/null
}

@test "_provider_orbstack_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_deploy_cluster" >/dev/null
}

@test "_provider_orbstack_configure_istio is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_configure_istio" >/dev/null
}

@test "_provider_orbstack_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_expose_ingress" >/dev/null
}
