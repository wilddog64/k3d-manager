#!/usr/bin/env bats

ACG_RULE="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules-acg/k3dm-tests.yaml"
HUB_RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"

@test "k3dm-tests rules select the app-cluster stack, not the hub stack" {
  run grep -F -- 'release: acg-kube-prometheus-stack' "${ACG_RULE}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'release: kube-prometheus-stack' "${ACG_RULE}"
  [ "${status}" -ne 0 ]
}

@test "k3dm-tests rules live on the app cluster only" {
  run grep -F -- 'k3dm-tests.alerts' "${ACG_RULE}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3dm-tests.alerts' "${HUB_RULE}"
  [ "${status}" -ne 0 ]
}

@test "all five k3dm test-suite alerts are present" {
  for _alert in OfflineSuiteFailing OfflineSuiteVacuous OfflineSuiteCaseCountDropped \
                OfflineSuiteStale DeploymentMetricsStale; do
    run grep -F -- "alert: ${_alert}" "${ACG_RULE}"
    [ "${status}" -eq 0 ]
  done
}

@test "OfflineSuiteVacuous names the result label value" {
  run grep -F -- 'k3dm_test_suite_cases{result="ok"} < 1' "${ACG_RULE}"
  [ "${status}" -eq 0 ]
  run grep -E -- 'expr: k3dm_test_suite_cases < 1' "${ACG_RULE}"
  [ "${status}" -ne 0 ]
}

@test "every k3dm alert carries a non-empty expr" {
  run python3 - "${ACG_RULE}" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
alerts = re.findall(r"- alert: (\S+)\n\s+expr: (.+)", text)
assert len(alerts) == 5, f"expected 5 alerts, found {len(alerts)}"
for name, expr in alerts:
    assert expr.strip(), f"{name} has an empty expr"
print("OK", len(alerts))
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK 5"* ]]
}
