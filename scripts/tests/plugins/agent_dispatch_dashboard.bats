#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
EXPORTER="${BATS_TEST_DIRNAME}/../../../bin/k3dm-dispatch-metrics"

_dashboard_json() {
  python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
print(json.dumps(json.loads("\n".join(line[4:] for line in body.splitlines()))))
PY
}

@test "agent dispatch dashboard: valid ConfigMap JSON and datasource" {
  run _dashboard_json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"uid": "k3dm-agent-dispatch"'* ]]
  [[ "$output" == *'"type": "prometheus", "uid": "prometheus"'* ]]
}

@test "agent dispatch dashboard: every queried metric is exported" {
  run python3 - "$DASH" "$EXPORTER" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
dashboard = json.loads("\n".join(line[4:] for line in body.splitlines()))
exporter = open(sys.argv[2], encoding="utf-8").read()
queries = "\n".join(target.get("expr", "") for panel in dashboard["panels"] for target in panel.get("targets", []))
for metric in set(re.findall(r"\bk3dm_dispatch_[a-z0-9_]+", queries)):
    assert metric in exporter, metric
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: landing success aggregates both sides" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
panel = next(panel for panel in panels if panel["id"] == 2)
expr = panel["targets"][0]["expr"]
numerator, denominator = [side.strip() for side in expr.split(" / ")]
assert numerator.startswith("sum("), numerator
assert denominator.startswith("sum("), denominator
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: panel rectangles do not overlap" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
ids = [panel["id"] for panel in panels]
assert len(ids) == len(set(ids))
for i, left in enumerate(panels):
    a = left["gridPos"]
    for right in panels[i + 1:]:
        b = right["gridPos"]
        assert not (a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]), (left["id"], right["id"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: per-spec panels use readable units and grouped targets" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
panel5 = next(panel for panel in panels if panel["id"] == 5)
assert panel5["fieldConfig"]["defaults"]["unit"] == "short"
panel12 = next(panel for panel in panels if panel["id"] == 12)
assert len(panel12["targets"]) == 4
assert all(target["expr"].startswith("sum by (version, slug)") for target in panel12["targets"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: spec window defaults to 30d and says the time picker does not apply" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
dashboard = json.loads("\n".join(line[4:] for line in body.splitlines()))
var = next(item for item in dashboard["templating"]["list"] if item["name"] == "window")
assert var["current"]["value"] == "30d", var["current"]
assert [o["value"] for o in var["options"] if o["selected"]] == ["30d"]
assert [o["value"] for o in var["options"]] == ["1d", "7d", "30d"]
assert var["label"] == "Spec window"
assert "time picker" in var["description"]
PY
  [ "$status" -eq 0 ]
}
