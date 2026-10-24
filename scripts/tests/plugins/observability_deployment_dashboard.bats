#!/usr/bin/env bats

DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-deployments-configmap.yaml"
HARNESS="${BATS_TEST_DIRNAME}/../lib/webhook.bats"

@test "every deployment panel aggregates job_id away" {
  run python3 - "${DASHBOARD}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
exprs = re.findall(r'"expr": "(.*?)",?\n', text)
exprs = [e for e in exprs if "k3dm_deployment" in e]
assert len(exprs) == 5, f"expected 5 deployment exprs, found {len(exprs)}"
for expr in exprs:
    assert expr.startswith("max by ("), f"not aggregated: {expr}"
    assert "job_id" not in expr, f"job_id leaked into grouping: {expr}"
print("OK", len(exprs))
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK 5"* ]]
}

@test "the webhook harness neutralizes the Pushgateway" {
  run grep -F -- 'export K3DM_PUSHGATEWAY_URL=""' "${HARNESS}"
  [ "${status}" -eq 0 ]
}

@test "stat tiles read current values in stacked rows; the graph keeps history" {
  run python3 - "${DASHBOARD}" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
dash = json.loads(text.split(".json: |\n", 1)[1].replace("\n    ", "\n"))
stats = [p for p in dash["panels"] if p["type"] == "stat"]
assert len(stats) == 4, f"expected 4 stat panels, found {len(stats)}"
for p in stats:
    t = p["targets"][0]
    assert t.get("instant") is True and t.get("range") is False, f"{p['title']}: not an instant query"
    assert p["options"]["orientation"] == "horizontal", f"{p['title']}: values not stacked in rows"
    assert p["options"]["textMode"] == "value_and_name", f"{p['title']}: name hidden"
    if "duration" in t["expr"]:
        assert "status" not in t["expr"] and "status" not in t["legendFormat"], f"{p['title']}: still split by status"
series = [p for p in dash["panels"] if p["type"] == "timeseries"]
assert len(series) == 1 and not series[0]["targets"][0].get("instant"), "graph lost its history"
print("OK")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK"* ]]
}
