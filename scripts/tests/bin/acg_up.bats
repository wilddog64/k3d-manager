#!/usr/bin/env bats

@test "acg-up sources the Argo CD plugin before readiness checks" {
  run grep -nF 'source "${REPO_ROOT}/scripts/plugins/argocd.sh"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/plugins/argocd.sh"* ]]
}
