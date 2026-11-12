#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

@test "make up reconciles platform-ops after observability" {
  run awk '/^up:/,/^$$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  grep -Fq "@\$(MAKE) --no-print-directory observability" <<< "${output}"
  grep -Fq "@\$(MAKE) --no-print-directory platform-ops" <<< "${output}"
}

@test "platform-ops target uses the scoped CVE reconciler" {
  run awk '/^platform-ops:/,/^$$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  curdir_literal='$'
  curdir_literal+='(CURDIR)'
  grep -Fq "git -C \"${curdir_literal}\" archive" <<< "${output}"
  [[ "${output}" == *'tar -x -C'* ]]
  [[ "${output}" == *'./scripts/k3d-manager deploy_argocd_platform_ops --confirm'* ]]
}
