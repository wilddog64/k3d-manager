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
for metric in set(re.findall(r"\bk3dm_(?:dispatch|claude)_[a-z0-9_]+", queries)):
    assert metric in exporter, metric
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: Claude context and compaction row panels exist below existing rows" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
by_title = {p["title"]: p for p in panels}
row = by_title["Claude context and compaction"]
assert row["type"] == "row"
other_bottom = max(p["gridPos"]["y"] + p["gridPos"]["h"] for p in panels if p["id"] < 33)
assert row["gridPos"]["y"] >= other_bottom
expected = {
    "Claude cost per verified spec": ("stat", "currencyUSD"),
    "Compactions per verified spec": ("stat", "short"),
    "Compactions by trigger": ("bargauge", "none"),
    "Re-read share after compaction": ("stat", "percentunit"),
    "Context incidents": ("bargauge", "none"),
    "Auto-compact threshold": ("stat", "short"),
}
for title, (ptype, unit) in expected.items():
    panel = by_title[title]
    assert panel["type"] == ptype, (title, panel["type"])
    assert panel["fieldConfig"]["defaults"]["unit"] == unit, (title, panel["fieldConfig"]["defaults"]["unit"])
    assert panel["gridPos"]["y"] > row["gridPos"]["y"]
assert by_title["Compactions per verified spec"]["targets"][0]["expr"] == 'sum(k3dm_claude_compactions{window="$window"}) / sum(k3dm_claude_verified_specs{window="$window"} > 0)'  # agent-audit: allow assert-removed sum() drops window/job/instance, so the old one-sided division never matched
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
assert len(panel12["targets"]) >= 4
assert all(target["expr"].startswith(("sum by (version, slug)", "max by (version, slug, spec)"))
           for target in panel12["targets"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
dashboard = json.loads("\n".join(line[4:] for line in body.splitlines()))
var = next(item for item in dashboard["templating"]["list"] if item["name"] == "window")
assert var["type"] == "query"
assert var["definition"] == "label_values(k3dm_dispatch_landed, window)"
assert var["current"]["value"] == "7d", var["current"]
assert var["label"] == "Window"
PY
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: rework rate stat reads the selected window" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
dashboard = json.loads("\n".join(line[4:] for line in body.splitlines()))
panel = next(p for p in dashboard["panels"] if p["title"] == "Rework rate")
assert panel["type"] == "stat"
assert [t["expr"] for t in panel["targets"]] == ['k3dm_dispatch_rework_ratio{window="$window"}']
assert panel["fieldConfig"]["defaults"]["unit"] == "percentunit"
assert "independent verifier" in panel["description"]
PY
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: stat and bar gauge panels use explicit colours" {
  run python3 - "$DASH" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("agent-dispatch.json: |\n", 1)[1]
panels = json.loads("\n".join(line[4:] for line in body.splitlines()))["panels"]
by_id = {panel["id"]: panel for panel in panels}
for panel in panels:
    if panel["type"] not in ("stat", "bargauge"):
        continue
    defaults = panel["fieldConfig"]["defaults"]
    assert "thresholds" in defaults or defaults.get("color", {}).get("mode") == "fixed", panel["id"]
land = by_id[8]
assert land["options"]["displayMode"] == "basic"
overrides = {item["matcher"].get("options"): item["properties"] for item in land["fieldConfig"]["overrides"]}
def fixed_color(series):
    prop = next(item for item in overrides[series] if item["id"] == "color")
    assert prop["value"]["mode"] == "fixed"
    return prop["value"]["fixedColor"]
assert fixed_color("landed") == "green"
for series in ("rebase", "scope", "tests"):
    assert fixed_color(series) != "green", series
for panel_id, expected in {
    2: {"mode": "absolute", "steps": [{"color": "red"}, {"color": "green", "value": 0.8}]},
    9: {"mode": "absolute", "steps": [{"color": "green"}, {"color": "yellow", "value": 86400}]},
    13: {"mode": "absolute", "steps": [{"color": "green"}, {"color": "yellow", "value": 0.5}]},
}.items():
    assert by_id[panel_id]["fieldConfig"]["defaults"]["thresholds"] == expected, panel_id
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}
