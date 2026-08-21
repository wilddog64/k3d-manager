#!/usr/bin/env bats
# shellcheck shell=bash

@test "deploy_app_cluster prints help with --help" {
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; deploy_app_cluster --help'
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3sup"* ]]
}

@test "deploy_app_cluster requires --confirm" {
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; deploy_app_cluster'
  [ "$status" -ne 0 ]
  [[ "$output" == *"--confirm"* ]]
}

@test "deploy_app_cluster fails if k3sup not found" {
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; PATH=/dev/null; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; deploy_app_cluster --confirm'
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3sup not found"* ]]
}

@test "local k3s kubeconfig keeps loopback endpoint for tunneled TLS" {
  run grep -nF "sed -e 's|https://localhost:|https://127.0.0.1:|g'" scripts/plugins/shopping_cart.sh
  [ "$status" -eq 0 ]
  run grep -nF 's|127.0.0.1|${external_ip}|g' scripts/plugins/shopping_cart.sh
  [ "$status" -ne 0 ]
}

@test "register_shopping_cart_apps fails if argocd dir missing" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." >/dev/null 2>&1 && pwd)"
  if [[ -d "${repo_root}/../shopping-carts/shopping-cart-infra/argocd/applications" ]]; then
    skip "shopping-cart-infra repo detected alongside k3d-manager"
  fi
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; register_shopping_cart_apps'
  [ "$status" -ne 0 ]
}

@test "_ensure_k3sup returns 0 when k3sup is already installed" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    k3sup() { return 0; }
    _command_exist() { [[ "$1" == "k3sup" ]]; }
    _ensure_k3sup
  '
  [ "$status" -eq 0 ]
}

@test "_ensure_k3sup errors when k3sup absent and no installer available" {
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; PATH=/dev/null; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; _ensure_k3sup'
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3sup not found"* ]]
}

@test "shopping_cart bootstrap helpers exist" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    declare -F shopping_cart_prepare_infra_bootstrap >/dev/null
    declare -F shopping_cart_prepare_cluster_secrets_and_seed >/dev/null
    declare -F shopping_cart_sync_vault_backed_secrets >/dev/null
    declare -F shopping_cart_reconcile_order_service >/dev/null
    declare -F shopping_cart_reconcile_product_catalog >/dev/null
  '
  [ "$status" -eq 0 ]
}

@test "_shopping_cart_resolve_app_context follows the active provider context" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/plugins/shopping_cart.sh
    _acg_resolve_provider() { printf "%s\n" "k3s-hostinger"; }
    _shopping_cart_resolve_app_context
  '
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu-hostinger" ]
}

@test "_shopping_cart_vault_externalsecrets includes the GHCR pull secret" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    _shopping_cart_vault_externalsecrets
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"shopping-cart-apps/ghcr-pull-secret"* ]]
}

@test "_ensure_k3sup returns 0 after successful brew install" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh
    _state="$(mktemp)"
    _command_exist() {
      case "$1" in
        k3sup) [[ -s "$_state" ]] ;;
        brew)  return 0 ;;
        *)     return 1 ;;
      esac
    }
    _run_command() { [[ "$*" == *"brew"* ]] && echo 1 > "$_state"; return 0; }
    _ensure_k3sup; rc=$?; rm -f "$_state"; exit $rc
  '
  [ "$status" -eq 0 ]
}

@test "_ensure_k3sup returns 0 after successful curl install on debian" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh
    _state="$(mktemp)"
    _command_exist() {
      case "$1" in
        k3sup) [[ -s "$_state" ]] ;;
        brew)  return 1 ;;
        curl)  return 0 ;;
        *)     return 1 ;;
      esac
    }
    _is_debian_family() { return 0; }
    curl() { return 0; }
    _run_command() { [[ "$*" == *"sh "* ]] && echo 1 > "$_state"; return 0; }
    _ensure_k3sup; rc=$?; rm -f "$_state"; exit $rc
  '
  [ "$status" -eq 0 ]
}

@test "agent joins fan out in parallel and wait for every worker" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    log="$(mktemp)"
    _k3s_agent_is_ready() { return 1; }
    _k3s_agent_address() { printf "%s\n" "$1"; }
    _k3sup_join_agent() { printf "join %s\n" "$1" >> "$log"; }
    _k3s_wait_agent_ready() { printf "ready %s\n" "$2" >> "$log"; }
    _k3sup_join_agents_parallel ubuntu-1,ubuntu-2,ubuntu-3,ubuntu-4 server "$(mktemp)"
    cat "$log"
  '
  [ "$status" -eq 0 ]
  [ "$(printf "%s\n" "$output" | grep -c '^join ')" -eq 4 ]
  [ "$(printf "%s\n" "$output" | grep -c '^ready ')" -eq 4 ]
}

@test "agent join failures are collected without aborting other workers" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    _k3s_agent_is_ready() { return 1; }
    _k3s_agent_address() { printf "%s\n" "$1"; }
    _k3sup_join_agent() { [[ "$1" != ubuntu-2 ]]; }
    _k3s_wait_agent_ready() { return 0; }
    _k3sup_join_agents_parallel ubuntu-1,ubuntu-2,ubuntu-3 server "$(mktemp)"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"ubuntu-2"* ]]
}

@test "already-ready agents are skipped on an idempotent rerun" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    log="$(mktemp)"
    _k3s_agent_is_ready() { return 0; }
    _k3s_agent_address() { printf "%s\n" "$1"; }
    _k3sup_join_agent() { printf "unexpected join\n" >> "$log"; return 1; }
    _k3sup_join_agents_parallel ubuntu-1,ubuntu-2 server "$(mktemp)"
    [ ! -s "$log" ]
  '
  [ "$status" -eq 0 ]
}
