#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

@test "system overrides: failure handler redacts inline VAULT_TOKEN commands" {
  source "${REPO_ROOT}/scripts/lib/system.sh"
  source "${REPO_ROOT}/scripts/lib/system_overrides.sh"

  _err() {
    printf '%s\n' "$*" >&2
    return 1
  }

  run _run_command_handle_failure "kubectl" 2 0 1 env "VAULT_TOKEN=hvs.secret" vault status
  [ "${status}" -eq 2 ]
  [ -z "${output}" ]
}
