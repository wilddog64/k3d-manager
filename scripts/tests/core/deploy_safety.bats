#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  MANAGER="${REPO_ROOT}/scripts/k3d-manager"
}

@test "deploy safety gate: no args requires confirm" {
  run "$MANAGER" deploy_vault
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: deploy_vault"* ]]
  [[ "$output" == *"Safety gate"* ]]
}

@test "deploy_vault --dry-run prints commands" {
  run "$MANAGER" deploy_vault --dry-run --namespace dry-run-ns --release dry-run-release
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] helm"* ]]
}
