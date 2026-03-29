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
