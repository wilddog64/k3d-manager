#!/usr/bin/env bats

RULES_FILE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"

@test "HermesNotRunning alerts on a missing or stale heartbeat" {
  run rg -n -A 16 '^        - alert: HermesNotRunning$' "${RULES_FILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"time() - k3dm_hermes_last_tick_timestamp_seconds > 900 or absent(k3dm_hermes_last_tick_timestamp_seconds)"* ]]
  [[ "${output}" == *"severity: warning"* ]]
}
