#!/usr/bin/env bats

CHECK="${BATS_TEST_DIRNAME}/../../check-stale-test-refs.sh"

_require_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null \
    || skip "fixture commit ${1} not reachable in this clone (orphaned by branch cleanup)"
}

@test "stale-ref check is executable" {
  [ -x "${CHECK}" ]
}

@test "stale-ref check flags the f03df202 data-layer rename" {
  _require_commit f03df202
  run "${CHECK}" 'f03df202^..f03df202'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"provider_contract.bats"* ]]
}

@test "stale-ref check flags the 4c89dabb trivy split" {
  _require_commit 4c89dabb
  run "${CHECK}" '4c89dabb^..4c89dabb'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"argocd_metrics_servicemonitor.bats"* ]]
}

@test "stale-ref check is quiet on a commit that touched no etc files" {
  _require_commit e3a75f1f
  run "${CHECK}" 'e3a75f1f^..e3a75f1f'
  [ "${status}" -eq 0 ]
}
