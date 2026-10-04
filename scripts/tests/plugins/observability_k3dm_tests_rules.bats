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

@test "the ACG rules dir is applied to the app cluster by the observability plugin" {
  local _plugin="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  run grep -F -- 'etc/prometheus/rules-acg' "${_plugin}"
  [ "${status}" -eq 0 ]
  run grep -F -- '_kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/"' "${_plugin}"
  [ "${status}" -eq 0 ]
}

@test "PrometheusRule CRD wait allows rules apply after delayed creation" {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../../"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${PLUGINS_DIR}/observability.sh"
  _info() { :; }
  _warn() { :; }
  helm() { return 0; }
  sleep() { :; }
  local calls="${BATS_TEST_TMPDIR}/calls"
  : > "${calls}"
  _err() { printf '%s\n' "$*" >> "${calls}"; return 0; }
  _kubectl() {
    printf '%s\n' "$*" >> "${calls}"
    if [[ "$*" == *"get crd"* ]]; then
      local gets
      gets=$(grep -c 'get crd' "${calls}" || true)
      (( gets >= 3 )) && printf 'True'
      return 0
    fi
    if [[ "$*" == *"api-resources"* ]]; then
      printf 'prometheuses.monitoring.coreos.com\n'
      return 0
    fi
    return 0
  }
  export K3DM_ACG_RULES_CRD_ATTEMPTS=3 K3DM_ACG_RULES_CRD_INTERVAL=0
  run _deploy_pushgateway_acg test-context
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'get crd prometheusrules.monitoring.coreos.com' "${calls}")" -eq 3 ]
  [ "$(grep -c 'wait.*crd/prometheusrules.monitoring.coreos.com' "${calls}" || true)" -eq 0 ]
  [ "$(grep -c 'apply.*rules-acg' "${calls}")" -eq 1 ]
}

@test "PrometheusRule CRD wait skips apply when creation never completes" {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../../"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${PLUGINS_DIR}/observability.sh"
  _info() { :; }
  _warn() { :; }
  helm() { return 0; }
  sleep() { :; }
  local calls="${BATS_TEST_TMPDIR}/calls"
  : > "${calls}"
  _err() { printf '%s\n' "$*" >> "${calls}"; return 0; }
  _kubectl() {
    printf '%s\n' "$*" >> "${calls}"
    [[ "$*" != *"get crd"* && "$*" != *"apply"* ]]
  }
  export K3DM_ACG_RULES_CRD_ATTEMPTS=3 K3DM_ACG_RULES_CRD_INTERVAL=0
  run _deploy_pushgateway_acg test-context
  [ "${status}" -ne 0 ]
  run grep -F 'prometheusrules.monitoring.coreos.com' "${calls}"
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'apply.*rules-acg' "${calls}" || true)" -eq 0 ]
}
