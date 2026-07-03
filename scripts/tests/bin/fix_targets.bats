#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  cd "${REPO_ROOT}" || exit 1
}

@test "make fix-list prints all documented fix targets" {
  run make fix-list
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make fix-list"* ]]
  [[ "${output}" == *"make fix-restart"* ]]
  [[ "${output}" == *"make fix-delete-pod"* ]]
  [[ "${output}" == *"make fix-sync"* ]]
  [[ "${output}" == *"make fix-force-sync"* ]]
  [[ "${output}" == *"make fix-eso-refresh"* ]]
  [[ "${output}" == *"make fix-status"* ]]
}

@test "make fix-restart dry-run renders rollout restart and status" {
  run make -n fix-restart APP=frontend NS=shopping-cart-apps
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubectl rollout restart 'deployment/frontend' -n 'shopping-cart-apps' --context 'ubuntu-k3s'"* ]]
  [[ "${output}" == *"kubectl rollout status  'deployment/frontend' -n 'shopping-cart-apps' --context 'ubuntu-k3s' --timeout=120s"* ]]
}

@test "make fix-status honors FIX_CONTEXT override" {
  run make -n fix-status NS=shopping-cart-apps FIX_CONTEXT=k3d-k3d-cluster
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubectl get nodes --context 'k3d-k3d-cluster' --no-headers"* ]]
  [[ "${output}" == *"kubectl get pods -n 'shopping-cart-apps' --context 'k3d-k3d-cluster'"* ]]
}

@test "ask sandbox allows make fix-list in fix mode" {
  run env K3DM_FIX_MODE=1 bin/k3dm-ask-bash -lc 'make fix-list'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make fix-list"* ]]
}

@test "ask sandbox blocks make up in fix mode" {
  run env K3DM_FIX_MODE=1 bin/k3dm-ask-bash -lc 'make up'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"operation not permitted"* ]]
}
