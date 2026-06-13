#!/usr/bin/env bats
# scripts/tests/lib/provider_contract.bats
# Contract tests: every cluster provider must implement the full interface.

# shellcheck disable=SC1091

# Setup providers directory path
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  PROVIDERS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib/providers" && pwd)"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)/scripts"
  source "${REPO_ROOT}/scripts/lib/provider.sh"
  export SCRIPT_DIR
}

teardown_file() {
  # Clean up any potential leftover test clusters
  k3d cluster delete "k3d-test-orbstack-exists" 2>/dev/null || true
}

# --- K3D Provider Contract ---

@test "_acg_normalize_provider normalizes short aliases" {
  [[ "$(_acg_normalize_provider aws)" == "k3s-aws" ]]
  [[ "$(_acg_normalize_provider az)" == "k3s-az" ]]
  [[ "$(_acg_normalize_provider azure)" == "k3s-az" ]]
  [[ "$(_acg_normalize_provider gcp)" == "k3s-gcp" ]]
  [[ "$(_acg_normalize_provider oci)" == "k3s-oci" ]]
  [[ "$(_acg_normalize_provider foo)" == "foo" ]]
}

@test "_acg_provider_context maps providers to app contexts" {
  [[ "$(_acg_provider_context k3s-aws)" == "ubuntu-k3s" ]]
  [[ "$(_acg_provider_context k3s-az)" == "ubuntu-azure" ]]
  [[ "$(_acg_provider_context k3s-gcp)" == "ubuntu-gcp" ]]
  [[ "$(_acg_provider_context foo)" == "ubuntu-k3s" ]]
}

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
