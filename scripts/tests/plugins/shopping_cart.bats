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
