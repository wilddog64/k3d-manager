#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

_dashboard_json() {
  python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = text.split("alertmanager-delivery.json: |\n", 1)[1]
lines = [line[4:] if line.startswith("    ") else line for line in body.splitlines()]
print(json.dumps(json.loads("\n".join(lines))))
PY
}

@test "the dashboard is a sidecar-loaded ConfigMap in monitoring with valid JSON" {
  run grep -F -- 'grafana_dashboard: "1"' "$DASH"
  [ "$status" -eq 0 ]
  run _dashboard_json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"uid": "k3dm-alertmanager-delivery"'* ]]
}

@test "the integration variable lists only integrations that have sent something" {
  run _dashboard_json
  [ "$status" -eq 0 ]
  [[ "$output" == *'max_over_time(alertmanager_notifications_total{namespace=\"monitoring\"}[30d])) > 0'* ]]
  [[ "$output" == *'"regex": "/integration=\"([^\"]+)\"/"'* ]]
}

@test "the dashboard names no integration this stack does not use" {
  for name in discord msteams opsgenie pagerduty pushover slack sns telegram victorops webex wechat; do
    run grep -iqw -- "$name" "$DASH"
    [ "$status" -ne 0 ]
  done
}

@test "every panel uses the hub Prometheus datasource" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = text.split("alertmanager-delivery.json: |\n", 1)[1]
dash = json.loads("\n".join(line[4:] for line in body.splitlines()))
for panel in dash["panels"]:
    if panel["type"] == "row":
        continue
    assert panel["datasource"] == {"type": "prometheus", "uid": "prometheus"}, panel["title"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "argocd platform-ops deploy applies the Alertmanager delivery dashboard" {
  run grep -F -- 'grafana-dashboard-alertmanager-delivery.yaml' "$ARGOCD"
  [ "$status" -eq 0 ]
}
