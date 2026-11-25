#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
  source "${BATS_TEST_DIRNAME}/../python_yaml.bash"
  source "${BATS_TEST_DIRNAME}/../promtool.bash"
}

RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"

@test "ArgoCD app alerts match cluster-prefixed shopping-cart and existing bare names" {
  rules_file="${BATS_TEST_TMPDIR}/argocd-rules.yml"
  test_file="${BATS_TEST_TMPDIR}/argocd.test.yml"
  "$(k3dm_python_yaml)" - "${RULE}" "${rules_file}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as source:
    document = next(d for d in yaml.safe_load_all(source)
                    if d and d.get("kind") == "PrometheusRule")
groups = [g for g in document["spec"]["groups"] if g["name"] == "argocd.alerts"]
if len(groups) != 1:
    raise SystemExit("expected exactly one argocd.alerts group")
rules = {rule["alert"]: rule for rule in groups[0]["rules"]}
expected = {"ArgoCDAppDegraded", "ArgoCDAppOutOfSync"}
if not expected.issubset(rules):
    raise SystemExit("target alerts missing from argocd.alerts")
yaml.safe_dump({"groups": groups}, open(sys.argv[2], "w", encoding="utf-8"),
               sort_keys=False)
PY
  cat > "${test_file}" <<EOF
rule_files:
  - ${rules_file}
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'argocd_app_info{name="ubuntu-hostinger-shopping-cart-order",health_status="Degraded"}'
        values: '1+0x10'
      - series: 'argocd_app_info{name="ubuntu-hostinger-shopping-cart-order",sync_status="OutOfSync"}'
        values: '1+0x20'
      - series: 'argocd_app_info{name="data-layer",health_status="Degraded"}'
        values: '1+0x10'
      - series: 'argocd_app_info{name="trivy-operator",health_status="Degraded"}'
        values: '1+0x10'
      - series: 'argocd_app_info{name="ubuntu-hostinger-eso",health_status="Degraded"}'
        values: '1+0x10'
    alert_rule_test:
      - eval_time: 5m
        alertname: ArgoCDAppDegraded
        exp_alerts:
          - exp_labels:
              alertname: ArgoCDAppDegraded
              name: ubuntu-hostinger-shopping-cart-order
              health_status: Degraded
              group: argocd
              severity: warning
            exp_annotations:
              summary: 'ArgoCD app ubuntu-hostinger-shopping-cart-order is Degraded'
              description: 'App ubuntu-hostinger-shopping-cart-order in namespace  has been Degraded for 5 minutes'
          - exp_labels:
              alertname: ArgoCDAppDegraded
              name: data-layer
              health_status: Degraded
              group: argocd
              severity: warning
            exp_annotations:
              summary: 'ArgoCD app data-layer is Degraded'
              description: 'App data-layer in namespace  has been Degraded for 5 minutes'
          - exp_labels:
              alertname: ArgoCDAppDegraded
              name: trivy-operator
              health_status: Degraded
              group: argocd
              severity: warning
            exp_annotations:
              summary: 'ArgoCD app trivy-operator is Degraded'
              description: 'App trivy-operator in namespace  has been Degraded for 5 minutes'
          - exp_labels:
              alertname: ArgoCDAppDegraded
              name: ubuntu-hostinger-eso
              health_status: Degraded
              group: argocd
              severity: warning
            exp_annotations:
              summary: 'ArgoCD app ubuntu-hostinger-eso is Degraded'
              description: 'App ubuntu-hostinger-eso in namespace  has been Degraded for 5 minutes'
      - eval_time: 15m
        alertname: ArgoCDAppOutOfSync
        exp_alerts:
          - exp_labels:
              alertname: ArgoCDAppOutOfSync
              name: ubuntu-hostinger-shopping-cart-order
              sync_status: OutOfSync
              group: argocd
              severity: warning
            exp_annotations:
              summary: 'ArgoCD app ubuntu-hostinger-shopping-cart-order is OutOfSync'
              description: 'App ubuntu-hostinger-shopping-cart-order in namespace  has been OutOfSync for 15 minutes'
EOF
  run k3dm_promtool test rules "${test_file}"
  echo "$output"
  [ "${status}" -eq 0 ]
}
