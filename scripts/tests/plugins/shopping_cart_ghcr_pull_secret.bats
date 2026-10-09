#!/usr/bin/env bats
# shellcheck shell=bash

@test "shopping cart GHCR pull secret keeps the PAT off kubectl argv" {
  local old_script="${SHOPPING_CART_SCRIPT:-scripts/plugins/shopping_cart.sh}"
  local argv_log="${BATS_TEST_TMPDIR}/kubectl-argv.log"
  local stdin_log="${BATS_TEST_TMPDIR}/kubectl-stdin.log"
  : > "${argv_log}"
  : > "${stdin_log}"

  run env SCRIPT_DIR="$(pwd)/scripts" SHOPPING_CART_SCRIPT="${old_script}" \
    ARGV_LOG="${argv_log}" STDIN_LOG="${stdin_log}" bash -c '
set -euo pipefail
source scripts/lib/system.sh
source scripts/lib/core.sh
source "${SHOPPING_CART_SCRIPT}"
APP_CONTEXT=test-ctx
_github_user=octo
_ghcr_pat=PAT-SENTINEL-123
kubectl() {
  printf "%s\n" "$*" >> "${ARGV_LOG}"
  if [[ "$*" == *"apply"* ]]; then
    cat >> "${STDIN_LOG}"
  fi
}
shopping_cart_create_ghcr_pull_secret
'
  [ "$status" -eq 0 ]

  local pat_count docker_password_count
  pat_count="$(grep -cF 'PAT-SENTINEL-123' "${argv_log}" || true)"
  docker_password_count="$(grep -cF -- '--docker-password' "${argv_log}" || true)"
  [ "${pat_count}" -eq 0 ]
  [ "${docker_password_count}" -eq 0 ]

  local manifest_count
  manifest_count="$(grep -cF 'type: kubernetes.io/dockerconfigjson' "${stdin_log}" || true)"
  [ "${manifest_count}" -eq 3 ]
  [ "$(grep -cF 'namespace: shopping-cart-apps' "${stdin_log}" || true)" -eq 1 ]
  [ "$(grep -cF 'namespace: shopping-cart-payment' "${stdin_log}" || true)" -eq 1 ]
  [ "$(grep -cF 'namespace: shopping-cart-data' "${stdin_log}" || true)" -eq 1 ]

  local dockerconfig_b64 dockerconfig auth_b64 auth
  dockerconfig_b64="$(awk '/^  \.dockerconfigjson: / { print $2; exit }' "${stdin_log}")"
  dockerconfig="$(printf '%s' "${dockerconfig_b64}" | base64 -d)"
  auth_b64="$(printf '%s' 'octo:PAT-SENTINEL-123' | base64 | tr -d '\n')"
  [ "${dockerconfig}" = "{\"auths\":{\"ghcr.io\":{\"auth\":\"${auth_b64}\"}}}" ]
  auth="$(printf '%s' "${auth_b64}" | base64 -d)"
  [ "${auth}" = 'octo:PAT-SENTINEL-123' ]
}
