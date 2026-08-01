#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

@test "make up reconciles platform-ops after observability" {
  run awk '/^up:/,/^$$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'@$(MAKE) --no-print-directory observability'* ]]
  [[ "${output}" == *'@$(MAKE) --no-print-directory platform-ops'* ]]
}

@test "platform-ops target uses the scoped CVE reconciler" {
  run awk '/^platform-ops:/,/^$$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'./scripts/k3d-manager deploy_argocd_platform_ops --confirm'* ]]
}
