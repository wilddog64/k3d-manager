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

@test "alert categories and pipeline panels use scoped selectors" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = text.split("alertmanager-delivery.json: |\n", 1)[1]
dash = json.loads("\n".join(line[4:] for line in body.splitlines()))
panels = {panel["id"]: panel for panel in dash["panels"]}
actionable = 'alertname!~"Watchdog|InfoInhibitor|Trivy.*"' in panels[4]["targets"][0]["expr"] and 'job!~".*smstest.*"' in panels[4]["targets"][0]["expr"]
assert actionable, panels[4]["targets"][0]["expr"]
assert 'alertname!~"Watchdog|InfoInhibitor|Trivy.*"' in panels[9]["targets"][0]["expr"], panels[9]
assert 'job!~".*smstest.*"' in panels[9]["targets"][0]["expr"], panels[9]
assert 'alertname=~"Trivy.*"' in panels[10]["targets"][0]["expr"], panels[10]
assert 'job=~".*smstest.*"' in panels[11]["targets"][0]["expr"], panels[11]
pipeline = panels[13]["targets"][0]["expr"]
assert "Alertmanager.*" in pipeline and "PrometheusNotConnectedToAlertmanagers" in pipeline, pipeline
assert pipeline.endswith("or vector(0)"), pipeline
for panel in dash["panels"]:
    if panel["id"] in {10, 11, 12, 13}:
        continue
    for target in panel.get("targets", []):
        expr = target.get("expr", "")
        if "ALERTS" in expr:
            assert 'Trivy.*' in expr and 'smstest' in expr, (panel["id"], expr)
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "security, synthetic, and noisiest panel contracts match retention" {
  run python3 - "$DASH" "${BATS_TEST_DIRNAME}/../../etc/helm/observability/kube-prometheus-stack-values.yaml" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
body = text.split("alertmanager-delivery.json: |\n", 1)[1]
dash = json.loads("\n".join(line[4:] for line in body.splitlines()))
panels = {panel["id"]: panel for panel in dash["panels"]}
retention = re.search(r"^    retention:\s*([^\s]+)", open(sys.argv[2]).read(), re.M).group(1)
queries = panels[12]["targets"]
assert len(queries) == 2
assert all(f"[{retention}]" in target["expr"] for target in queries), queries
assert "count_over_time" in queries[0]["expr"]
assert "changes" in queries[1]["expr"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "dashboard panel rectangles do not overlap and ids are unique" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = text.split("alertmanager-delivery.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
ids = [panel["id"] for panel in panels]
assert len(ids) == len(set(ids)), ids
rectangles = [panel for panel in panels if panel["type"] != "row"]
for i, left in enumerate(rectangles):
    a = left["gridPos"]
    for right in rectangles[i + 1:]:
        b = right["gridPos"]
        overlap = a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]
        assert not overlap, (left["id"], right["id"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}
