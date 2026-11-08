#!/usr/bin/env bats

BASE="${BASE:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops}"
FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/agent-dispatch-dashboard-pre-split.yaml"
EXPORTER="${BATS_TEST_DIRNAME}/../../../bin/k3dm-dispatch-metrics"

@test "agent dispatch dashboard: valid ConfigMap JSON and datasource" {
  run python3 - "$BASE" <<'PY'
import json, sys
from pathlib import Path
base=Path(sys.argv[1])
for filename,key,uid in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json","k3dm-agent-dispatch"),
                         ("grafana-dashboard-agent-cost.yaml","agent-cost.json","k3dm-agent-cost"),
                         ("grafana-dashboard-agent-activity.yaml","agent-activity.json","k3dm-agent-activity")):
    text=(base/filename).read_text(); dashboard=json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
    assert dashboard["uid"]==uid
    assert all(panel.get("datasource",{}).get("uid")=="prometheus" for panel in dashboard["panels"] if panel.get("targets"))
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: verification ladder contract" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "${BATS_TEST_DIRNAME}/../../../docs/guides/grafana-dashboards/k3dm-agent-dispatch.md" <<'PY'
import json, re, subprocess, sys
from pathlib import Path
dashboard_path, guide_path = map(Path, sys.argv[1:])
def load(path):
    text = path.read_text()
    return json.loads("\n".join(line[4:] for line in text.split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
dashboard = load(dashboard_path)
panel = next(panel for panel in dashboard["panels"] if panel["title"] == "Verification ladder")
assert panel["id"] == 105 and panel["gridPos"] == {"h": 6, "w": 12, "x": 12, "y": 65}
assert panel["type"] == "table"
target, = panel["targets"]
assert target["expr"] == "sum by (rung, status) (k3dm_dispatch_ladder_tasks)"
assert target["instant"] is True and target["format"] == "table"
organize = next(item["options"] for item in panel["transformations"] if item["id"] == "organize")
assert organize["indexByName"] == {"rung": 0, "status": 1, "Value": 2}
assert organize["renameByName"]["Value"] == "tasks" and organize["excludeByName"]["Time"] is True
task_override = next(item for item in panel["fieldConfig"]["overrides"] if item["matcher"]["options"] == "tasks")
cell = next(item["value"] for item in task_override["properties"] if item["id"] == "custom.cellOptions")
assert cell == {"type": "gauge", "mode": "basic"}
assert panel["options"]["sortBy"] == [{"displayName": "tasks", "desc": True}]
filters, = [item["options"] for item in panel["transformations"] if item["id"] == "filterByValue"]
assert filters["type"] == "exclude"
assert filters["match"] == "all"
assert [(item["fieldName"], item["config"]["id"], item["config"]["options"]["value"]) for item in filters["filters"]] == [("status", "equal", "unknown"), ("rung", "regex", "^(implemented|landed)$")]
rows = [("implemented", "unknown", 0), ("landed", "unknown", 0), ("implemented", "pending", 0), ("offline_tested", "unknown", 0), ("independently_verified", "unknown", 0)]
visible = [row for row in rows if not (row[1] == "unknown" and re.fullmatch(filters["filters"][1]["config"]["options"]["value"], row[0]))]
assert visible == rows[2:], visible
description = panel["description"]
assert "Self-reported and advisory" in description
for phrase in ("offline_tested", "deployed", "live_verified", "gate_coverage_start", "independently_verified", "evidence_sha256"):
    assert phrase in description, phrase
section = guide_path.read_text().split("## Verification ladder", 1)[1].split("\n## ", 1)[0]
for phrase in ("implemented", "offline_tested", "deployed", "live_verified", "independently_verified", "landed", "gate_coverage_start", "evidence hash"):
    assert phrase in section, phrase
dashboard_repo_path = "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
baseline_text = subprocess.run(["git", "-C", str(dashboard_path.parent), "show", f"028b898f:{dashboard_repo_path}"], check=True, capture_output=True, text=True).stdout
baseline_json = json.loads("\n".join(line[4:] for line in baseline_text.split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
assert next(item for item in baseline_json["panels"] if item["id"] == 105)["type"] == "bargauge"
old = {item["id"]: item for item in baseline_json["panels"]}
new = {item["id"]: item for item in dashboard["panels"]}
assert set(old) == set(new)
for panel_id in old.keys() - {105}:
    assert old[panel_id] == new[panel_id], panel_id
print("ok: verification ladder contract; other panels unchanged")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verification ladder contract; other panels unchanged"* ]]
}

@test "agent dispatch dashboard: every queried metric is exported" {
  run python3 - "$BASE" "$EXPORTER" <<'PY'
import json,re,sys
from pathlib import Path
base=Path(sys.argv[1]); dashboards=[]
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
    text=(base/filename).read_text(); dashboards.append(json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines())))
exporter=Path(sys.argv[2]).read_text()
queries="\n".join(t.get("expr","") for d in dashboards for p in d["panels"] for t in p.get("targets",[]))
for metric in set(re.findall(r"\bk3dm_(?:dispatch|claude|codex|agy)_[a-z0-9_]+",queries)):
    assert metric in exporter,metric
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: Claude context and compaction row panels exist below existing rows" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-activity.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
by_id={p["id"]:p for p in d["panels"]}; row=by_id[33]
assert row["title"]=="Claude context and compaction" and row["type"]=="row"
expected={35:("Compactions per verified spec","stat","short"),36:("Compactions by trigger","bargauge","none"),37:("Re-read share after compaction","stat","percentunit"),38:("Context incidents","bargauge","none"),39:("Auto-compact setting (configured)","stat","short")}
for panel_id,(title,ptype,unit) in expected.items():
    panel=by_id[panel_id]
    assert panel["title"]==title and panel["type"]==ptype
    assert panel["fieldConfig"]["defaults"]["unit"]==unit
    assert panel["gridPos"]["y"]>row["gridPos"]["y"]
cost=(Path(sys.argv[1])/"grafana-dashboard-agent-cost.yaml").read_text()
cost=json.loads("\n".join(x[4:] for x in cost.split("  agent-cost.json: |\n",1)[1].splitlines()))
panel=next(p for p in cost["panels"] if p["id"]==34)
assert panel["title"]=="Claude cost per verified spec" and panel["fieldConfig"]["defaults"]["unit"]=="currencyUSD"
assert by_id[35]["targets"][0]["expr"]=='sum(k3dm_claude_compactions{window="$window"}) / sum(k3dm_claude_verified_specs{window="$window"} > 0)'
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: landing success aggregates both sides" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["id"]==2); numerator,denominator=[side.strip() for side in panel["targets"][0]["expr"].split(" / ")]
assert numerator.startswith("sum(") and denominator.startswith("sum(")
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: panel rectangles do not overlap" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
    text=(base/filename).read_text(); panels=json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))["panels"]
    ids=[p["id"] for p in panels]; assert len(ids)==len(set(ids)),filename
    for i,left in enumerate(panels):
        a=left["gridPos"]
        for right in panels[i+1:]:
            b=right["gridPos"]
            assert not (a["x"]<b["x"]+b["w"] and b["x"]<a["x"]+a["w"] and a["y"]<b["y"]+b["h"] and b["y"]<a["y"]+a["h"]),(filename,left["id"],right["id"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: Codex API cost shows priced total and excluded sessions" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
by_id={p["id"]:p for p in d["panels"]}
cost=by_id[58]; excluded=by_id[83]
assert "priced sessions only" in cost["description"]
assert cost["targets"][0]["expr"]=='sum(k3dm_codex_api_cost_usd{window="$window"})'
assert excluded["title"]=="Unpriced Codex sessions"
assert excluded["targets"][0]["expr"]=='sum(k3dm_codex_unpriced_sessions{window="$window"})'
assert cost["gridPos"]["y"]==excluded["gridPos"]["y"] and cost["gridPos"]["x"]+cost["gridPos"]["w"]==excluded["gridPos"]["x"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: per-spec panels use readable units and grouped targets" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]
panel5=next(p for p in panels if p["id"]==5); assert panel5["fieldConfig"]["defaults"]["unit"]=="short"
panel12=next(p for p in panels if p["id"]==12); assert len(panel12["targets"])>=4
assert all(t["expr"].startswith(("sum by (version, slug, repo)","max by (version, slug, spec, agent, repo)","max by (version, slug, repo, worker)","max by (version, slug, repo, coordinator)","max by (version, slug, repo, primary_coordinator)","max by (version, slug, repo, acting_coordinator)","max by (version, slug, repo, landed_by)","max by (version, slug, repo, primary_cost_state)","max by (version, slug, repo) (")) for t in panel12["targets"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: final exit gap and operator coverage are exposed" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panels={p["title"]:p for p in d["panels"]}
per=panels["Per spec"]
assert any("k3dm_dispatch_task_post_exit_land_seconds" in t["expr"] for t in per["targets"])
assert any(p["title"]=="Time to land" for p in d["panels"])
assert "k3dm_dispatch_post_exit_land_minutes_per_landed" in panels["Final worker exit → land"]["targets"][0]["expr"]
human=panels["Human continuation prompts"]
assert any("k3dm_dispatch_intervention_tracking_tasks" in t["expr"] for t in human["targets"])
assert any("k3dm_dispatch_human_continuation_prompts" in t["expr"] for t in human["targets"])
assert human["type"]=="bargauge" and human["options"]["namePlacement"]=="top" and all(t.get("instant") for t in human["targets"]),human["type"]
index=next(x["options"]["indexByName"] for x in per["transformations"] if x["id"]=="organize")
assert len(set(index.values()))==len(index),index
assert index["Value #J"]==index["Value #C"]+1,index
for phrase in ("bin/k3dm-codex-dispatch","Claude ≈","footer"):
  assert phrase in per["description"],phrase
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json")):
    text=(Path(sys.argv[1])/filename).read_text(); d=json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
    var=next(v for v in d["templating"]["list"] if v["name"]=="window")
    assert var["type"]=="query" and var["definition"]=="label_values(k3dm_dispatch_landed, window)"
    assert var["current"]["value"]=="7d" and var["label"]=="Window"
    assert var["sort"]==8, (filename, var["sort"])
PY
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: rework rate stat reads the selected window" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
p=next(p for p in d["panels"] if p["title"]=="Rework rate")
assert p["type"]=="stat" and [t["expr"] for t in p["targets"]]==['k3dm_dispatch_rework_ratio{window="$window"}']
assert p["fieldConfig"]["defaults"]["unit"]=="percentunit" and "independent verifier" in p["description"]
PY
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: verified delivery stats use exported metrics without overlap" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]
by_id={p["id"]:p for p in panels}; tokens=by_id[40]; awaiting=by_id[41]
assert tokens["targets"][0]["expr"]=='k3dm_dispatch_codex_tokens_per_delivered{window="$window"}'
assert awaiting["targets"][0]["expr"]=='k3dm_dispatch_awaiting_verification{window="$window"}'
assert tokens["gridPos"]["y"]==awaiting["gridPos"]["y"]
rework=next(p for p in panels if p["title"]=="Rework rate")["description"]
assert "review" in rework and "verdict is not in the ledger" not in rework
PY
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: stat and bar gauge panels use explicit colours" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1]); dashboards=[]
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
    text=(base/filename).read_text(); dashboards.append(json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines())))
panels=[p for d in dashboards for p in d["panels"]]; by_id={p["id"]:p for p in panels}
for panel in panels:
    if panel["type"] not in ("stat","bargauge"): continue
    defaults=panel["fieldConfig"]["defaults"]; assert "thresholds" in defaults or defaults.get("color",{}).get("mode")=="fixed",panel["id"]
land=by_id[8]; assert land["options"]["displayMode"]=="basic"
overrides={item["matcher"].get("options"):item["properties"] for item in land["fieldConfig"]["overrides"]}
def fixed_color(series):
    prop=next(item for item in overrides[series] if item["id"]=="color")
    assert prop["value"]["mode"]=="fixed"; return prop["value"]["fixedColor"]
assert fixed_color("landed")=="green"
for series in ("rebase","scope","tests"): assert fixed_color(series)!="green",series
for panel_id,expected in {2:{"mode":"absolute","steps":[{"color":"red"},{"color":"green","value":0.8}]},9:{"mode":"absolute","steps":[{"color":"green"},{"color":"yellow","value":86400}]},13:{"mode":"absolute","steps":[{"color":"green"},{"color":"yellow","value":0.5}]}}.items():
    assert by_id[panel_id]["fieldConfig"]["defaults"]["thresholds"]==expected,panel_id
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups" {
  run python3 - "$BASE" "$FIXTURE" <<'PY'
import json,sys
from pathlib import Path
base,fixture=Path(sys.argv[1]),Path(sys.argv[2])
def load(path,key):
 text=path.read_text(); return json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
old=load(fixture,"agent-dispatch.json")
files=(("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json"))
new=[load(base/f,key) for f,key in files]; old_ids=[p["id"] for p in old["panels"]]
all_ids=[p["id"] for d in new for p in d["panels"]]
assert sorted(all_ids)==sorted(old_ids+[14,15,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112]) and len(all_ids)==len(set(all_ids))
assert set(p["id"] for p in new[0]["panels"])==set(range(1,16))|{40,41,84,85,89,90,91,92,101,103,104,105,106}|set(range(42,49))
assert set(p["id"] for p in new[1]["panels"])=={19,20,21,22,23,24,25,27,28,29,30,31,32,34,86,87,88,93,94,95,96,97,98,107,108,109,110,111,112}
assert set(p["id"] for p in new[2]["panels"])=={33,83,99,100,102}|set(range(35,40))|set(range(49,65))|set(range(66,72))
print(f"ok: {len(all_ids)} panels, each exactly once")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: 96 panels, each exactly once"* ]]
}

@test "agent dashboards: panel targets, fieldConfig and options match the pre-split fixture" {
  run python3 - "$BASE" "$FIXTURE" <<'PY'
import json,sys
from pathlib import Path
base,fixture=Path(sys.argv[1]),Path(sys.argv[2])
def load(path,key):
 text=path.read_text(); return json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
old=load(fixture,"agent-dispatch.json"); old_by_id={p["id"]:p for p in old["panels"]}
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
 for panel in load(base/filename,key)["panels"]:
    if panel["id"] in (14,15,34,47,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112):
      continue
    for field in ("targets","fieldConfig","options"):
      new,old_field=panel.get(field),old_by_id[panel["id"]].get(field)
      if field=="options" and panel["id"]==48:
        continue
      if panel["id"]==12 or (field=="targets" and panel["id"] in (54,56)):
        continue
      if field=="options" and panel["type"]=="bargauge":
        new={k:v for k,v in (new or {}).items() if k not in ("orientation","namePlacement","minVizHeight","text")} or None
      if field=="fieldConfig" and panel["id"] in (29,31):
        new=json.loads(json.dumps(new)); new["defaults"].pop("noValue",None)
      if field=="options" and panel["id"]==32:
        new={k:v for k,v in new.items() if k not in ("text","showValue","tooltip","xTickLabelRotation","xTickLabelSpacing")}
      if field=="fieldConfig" and panel["id"] in (56,71) and new["defaults"].get("unit")=="short":
        new=json.loads(json.dumps(new)); new["defaults"]["unit"]=old_field["defaults"]["unit"]
      assert new==old_field,(panel["id"],field)
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent activity: repo gauge height, row layout, and protected panel data" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
import json,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
panels=d["panels"]; by_id={p["id"]:p for p in panels}
for panel_id in (54,56):
    p=by_id[panel_id]
    assert p["gridPos"]["h"]>=12 and (p["gridPos"]["h"]*38-8-52)/9>=36,p["gridPos"]
    assert p["options"]["minVizHeight"]>=36,p["options"]
    assert p["options"]["namePlacement"]=="top"
    expected={54:[
      'topk(8, sum by (repo, mode) (k3dm_codex_untracked_sessions{window="$window"}))',
      '(sum(sum by (repo, mode) (k3dm_codex_untracked_sessions{window="$window"})) - sum(topk(8, sum by (repo, mode) (k3dm_codex_untracked_sessions{window="$window"})))) > 0'],
      56:[
      'topk(8, sum by (repo) (k3dm_codex_tokens{window="$window"}))',
      '(sum(sum by (repo) (k3dm_codex_tokens{window="$window"})) - sum(topk(8, sum by (repo) (k3dm_codex_tokens{window="$window"})))) > 0']}[panel_id]
    assert [t["expr"] for t in p["targets"]]==expected
    assert p["targets"][1]["legendFormat"]=="other"
row=[by_id[i] for i in (54,55,56,57)]
assert len({p["gridPos"]["y"] for p in row})==len({p["gridPos"]["h"] for p in row})==1
assert all(p["gridPos"]["h"]==12 for p in row)
# Only the two repo gauges get the taller minimum.
assert by_id[55]["options"]["minVizHeight"]==8
assert "minVizHeight" not in by_id[57]["options"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dashboards: each dashboard has unique panel ids and no overlapping rectangles" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
 text=(base/filename).read_text(); panels=json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))["panels"]
 ids=[p["id"] for p in panels]; assert len(ids)==len(set(ids)),filename
 for i,left in enumerate(panels):
    a=left["gridPos"]
    for right in panels[i+1:]:
      b=right["gridPos"]
      assert not (a["x"]<b["x"]+b["w"] and b["x"]<a["x"]+a["w"] and a["y"]<b["y"]+b["h"] and b["y"]<a["y"]+a["h"]),(filename,left["id"],right["id"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dashboards: all dashboards have the tag-based Agents link" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
expected={"type":"dashboards","tags":["k3dm-agents"],"asDropdown":False,"includeVars":True,"keepTime":True,"title":"Agents"}
for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json"),("grafana-dashboard-agent-activity.yaml","agent-activity.json")):
 text=(base/filename).read_text(); d=json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
 assert "k3dm-agents" in d["tags"] and d["links"][0]==expected
 assert d["links"][1]=={"type":"link","title":"Bug Tracking","url":"/d/k3dm-bugs"}
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
def load(file,key):
 text=(base/file).read_text(); return json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
activity=load("grafana-dashboard-agent-activity.yaml","agent-activity.json")["templating"]["list"][0]
assert activity["name"]=="window" and activity["label"]=="Window" and activity["type"]=="custom"
assert [o["value"] for o in activity["options"]]==["1d","7d","30d"] and activity["current"]["value"]=="7d"
for file,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json")):
 window=load(file,key)["templating"]["list"][0]
 assert window["type"]=="query" and window["definition"]=="label_values(k3dm_dispatch_landed, window)"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent activity: Claude row fills the width and bar gauge names read beside each bar" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-activity.yaml").read_text()
panels=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))["panels"]
by_id={p["id"]:p for p in panels}
claude=[by_id[i] for i in (35,36,37,38,39,99)]
assert min(p["gridPos"]["x"] for p in claude)==0
for p in claude:
  assert p["gridPos"]["w"]>=(12 if p["type"]=="bargauge" else 6),(p["id"],p["gridPos"])
for y in {p["gridPos"]["y"] for p in claude}:
  assert sum(p["gridPos"]["w"] for p in claude if p["gridPos"]["y"]==y)==24,y
for p in panels:
  if p["type"]=="bargauge":
    assert p.get("options",{}).get("orientation")=="horizontal",p["id"]
    want="left" if p["gridPos"]["w"]>=12 else "top"
    assert p.get("options",{}).get("namePlacement")==want,(p["id"],p["gridPos"]["w"])  # agent-audit: allow assert-removed narrow gauges put names above the bar so long repo names fit
    text_sizes=p.get("options",{}).get("text",{})
    assert text_sizes.get("titleSize") and text_sizes.get("valueSize"),p["id"]
    if want=="top":
      assert p["gridPos"]["h"]>=8,(p["id"],p["gridPos"])
for i in (56,71):
  assert by_id[i]["fieldConfig"]["defaults"]["unit"]=="short",i
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec" {
  run python3 - "$BASE" <<'PY'
import json,re,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panels={p["id"]:p for p in d["panels"]}
assert panels[43]["options"].get("orientation")=="horizontal" and panels[43]["options"].get("namePlacement")=="left"
table=panels[47]
fp,tg=panels[48]["gridPos"],table["gridPos"]
assert fp["y"]==tg["y"] and fp["h"]==tg["h"] and fp["x"]==0 and fp["x"]+fp["w"]==tg["x"] and tg["x"]+tg["w"]==24,(fp,tg)
fpo=panels[48]["options"]
assert panels[48]["type"]=="bargauge" and fpo.get("orientation")=="horizontal" and fpo.get("namePlacement")=="left",fpo
assert fpo.get("text")=={"titleSize":14,"valueSize":24},fpo
for target in table["targets"]:
  assert target["expr"].startswith("sum by (version, slug, run, ") and '"doc"' not in target["expr"] and "plans/" not in target["expr"] and "bugs/" not in target["expr"]
  assert target["expr"].count("label_join(") == 1 and ', "vsort", "|", "vsort", "slug", "rpad"))' in target["expr"]
  sum_by = target["expr"].split(") (", 1)[0]
  assert "rpad" not in sum_by and "vsort" in sum_by
assert table["targets"][0]["expr"].startswith("sum by (version, slug, run, outcome, evidence, evidence_summary, evidence_path, spec_url, vsort) (")
assert table["targets"][1]["expr"].startswith("sum by (version, slug, run, vsort) (")
assert "spec_url" in table["targets"][0]["expr"]
ids=[t["id"] for t in table.get("transformations",[])]
assert ids[:3]==["merge","sortBy","organize"],ids
assert any(t["id"]=="convertFieldType" and any(c.get("targetField")=="run" and c.get("destinationType")=="number" for c in t.get("options",{}).get("conversions",[])) for t in table.get("transformations",[])[3:])
assert table["transformations"][1]["options"]["sort"]==[{"field":"vsort","desc":True}] and "sortBy" not in table["options"]
for target in table["targets"]:
  assert target["expr"].split(") (",1)[0].endswith(", vsort") and '"v$1.0$2.$3"' in target["expr"] and '"$1.0$2"' in target["expr"]
def pad_run(run_str, expr):
  pats = re.findall(r'"rpad",\s*"([^"]+)",\s*"run",\s*"([^"]+)"', expr)
  assert len(pats) == 3, pats
  val = run_str
  for repl, pat in pats:
    m = re.fullmatch(pat, run_str)
    if m:
      val = repl.replace("$1", m.group(1))
  return val
assert pad_run("9", table["targets"][0]["expr"]) < pad_run("10", table["targets"][0]["expr"]) < pad_run("100", table["targets"][0]["expr"])
assert pad_run("1", table["targets"][0]["expr"]) < pad_run("2", table["targets"][0]["expr"]) < pad_run("3", table["targets"][0]["expr"])
org=table["transformations"][2]["options"]
for hidden in ("Time","__name__","job","window","Value #A","vsort"):
  assert org["excludeByName"].get(hidden) is True,hidden
assert not org["excludeByName"].get("spec_url"),"spec_url feeds the slug link; excluding it empties the URL"
assert any(o["matcher"]=={"id":"byName","options":"spec_url"} and {"id":"custom.hidden","value":True} in o["properties"] for o in table["fieldConfig"]["overrides"])
order=sorted(org["indexByName"],key=org["indexByName"].get)
assert order[:4]==["version","slug","run","Value #B"],order
assert org["renameByName"].get("Value #B")=="Tokens"
assert "k3dm_dispatch_task_run_agent_tokens{" in next(x["expr"] for x in table["targets"] if x["refId"]=="B")
links=[l for o in table["fieldConfig"]["overrides"] if o["matcher"]=={"id":"byName","options":"slug"} for p in o["properties"] if p["id"]=="links" for l in p["value"]]
assert len(links)==1 and links[0]["url"]=="${__data.fields.spec_url}"
assert org["renameByName"].get("evidence_summary")=="Result"
assert org["renameByName"].get("evidence_path")=="Log"
assert org["excludeByName"].get("evidence") is True
assert "evidence_summary" in table["targets"][0]["expr"] and "evidence_path" in table["targets"][0]["expr"]
assert all("loki_url" not in t["expr"] for t in table["targets"])
assert "loki_url" not in org["excludeByName"]
log_overrides=[o for o in table["fieldConfig"]["overrides"] if o["matcher"]=={"id":"byName","options":"Log"}]
assert len(log_overrides)==1
log_properties={p["id"]:p["value"] for p in log_overrides[0]["properties"]}
assert log_properties.get("custom.inspect") is True and log_properties.get("custom.width", 999)>0 and log_properties["custom.width"]<=160
assert log_properties["links"][0]["title"]=="Open run log and availability"
assert log_properties["links"][0]["url"]=="/d/k3dm-agent-run-log?var-version=${__data.fields.version}&var-slug=${__data.fields.slug}&var-run=${__data.fields.run}&var-result=${__data.fields.Result}&from=now-30d&to=now"
assert "Landing-test logs are shipped" in table["description"]
assert "local only (not shipped)" in table["description"]
assert "file://" not in text
widths={o["matcher"]["options"]:p["value"] for o in table["fieldConfig"]["overrides"] if o["matcher"]["id"]=="byName" for p in o["properties"] if p["id"]=="custom.width"}
assert all(name in widths for name in ("version","run","outcome","Result","Log","Tokens")), widths
assert "slug" not in widths
assert sum(widths.values())<=table["gridPos"]["w"]*55-300, widths
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs" {
  run python3 - "$BASE" <<'PYTEST'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
def load(name,key):
    text=(base/name).read_text()
    return json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
d=load("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json")
assert not any(p["id"]==93 for p in d["panels"])
assert sum(p.get("title")=="Per run evidence" for p in d["panels"])==1
panel=next(p for p in d["panels"] if p["id"]==47)
assert all('evidence=~' not in t["expr"] and 'evidence!~' not in t["expr"] for t in panel["targets"])
assert "local only (not shipped)" in panel["description"]
runlog=load("grafana-dashboard-agent-run-log.yaml","agent-run-log.json")
assert len(runlog["panels"])==1
result=next(v for v in runlog["templating"]["list"] if v["name"]=="result")
assert result["hide"]==2 and result["type"]=="textbox"
assert result["current"]["value"]=="Evidence availability unknown"
assert "${result}" in runlog["panels"][0]["title"]
assert "local only (not shipped)" in runlog["panels"][0]["description"]
assert "codex.log" in runlog["panels"][0]["description"]
print("ok")
PYTEST
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch: per spec shows which agent landed each spec" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["id"]==12)
spec=[t for t in panel["targets"] if "k3dm_dispatch_task_spec{" in t["expr"]]
assert len(spec)==1 and spec[0]["expr"].startswith("max by (version, slug, spec, agent, repo) "),spec
org=next(t for t in panel["transformations"] if t["id"]=="organize")["options"]
assert org["renameByName"].get("agent")=="Agent",org
idx=org["indexByName"]
assert idx["version"]<idx["slug"]<idx["repo"]<idx["agent"]<idx["Value #A"],idx
assert org["renameByName"].get("repo")=="Repo",org
assert not org.get("excludeByName",{}).get("agent"),org
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: Log opens the filtered run log dashboard" {
  run python3 - "$BASE" <<'PYTEST'
import json,re,sys
from pathlib import Path
from urllib.parse import quote, urlsplit, parse_qs
base=Path(sys.argv[1])
def load(name,key):
    text=(base/name).read_text()
    return json.loads("\n".join(x[4:] for x in text.split(f"  {key}: |\n",1)[1].splitlines()))
d=load("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json")
panel=next(p for p in d["panels"] if p["id"]==47)
props=next(o["properties"] for o in panel["fieldConfig"]["overrides"] if o["matcher"].get("options")=="Log")
assert any(p["id"]=="custom.inspect" and p["value"] for p in props)
link=next(p["value"][0] for p in props if p["id"]=="links")
assert link["title"]=="Open run log and availability"
url=link["url"]
assert url=="/d/k3dm-agent-run-log?var-version=${__data.fields.version}&var-slug=${__data.fields.slug}&var-run=${__data.fields.run}&var-result=${__data.fields.Result}&from=now-30d&to=now"
org=next(t["options"] for t in panel["transformations"] if t["id"]=="organize")
raw={"version","slug","run","evidence_summary","evidence_path"}-set(org["excludeByName"])
visible={org["renameByName"].get(k,k) for k in raw}
assert set(re.findall(r"\$\{__data.fields.([^}]+)\}",url))=={"version","slug","run","Result"}<=visible
for summary in ("36/36 ok", "exit 127; local only (not shipped)", "none", "unknown & unavailable # test"):
    row={"version":"v1.43.9","slug":"sample-run","run":"1","Result":summary}
    resolved=re.sub(r"\$\{__data.fields.([^}]+)\}",lambda m:quote(row[m.group(1)],safe=""),url)
    parsed=urlsplit(resolved); params=parse_qs(parsed.query)
    assert parsed.path=="/d/k3dm-agent-run-log" and not parsed.fragment
    assert params["var-result"]==[summary] and params["var-slug"]==["sample-run"]
assert "file://" not in json.dumps(d)
runlog=load("grafana-dashboard-agent-run-log.yaml","agent-run-log.json")
assert runlog["uid"]=="k3dm-agent-run-log"
p=runlog["panels"][0]
assert p["type"]=="logs" and p["datasource"]["uid"]=="loki"
assert p["targets"][0]["expr"]=='{job="k3dm-dispatch-run", version="$version", slug="$slug", run="$run"}'
assert runlog["time"]=={"from":"now-30d","to":"now"}
print("ok")
PYTEST
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent cost: Claude tokens by kind splits the selected window by cache kind" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-cost.yaml").read_text()
cost=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
panel=next(p for p in cost["panels"] if p["title"]=="Claude tokens by kind")
expr=panel["targets"][0]["expr"]
assert panel["type"]=="bargauge" and panel["options"]["orientation"]=="horizontal" and panel["options"]["namePlacement"]=="left",panel["type"]
assert "sum by (kind)" in expr and "k3dm_dispatch_claude_tokens{" in expr and 'window=\"$window\"' in expr,expr
assert panel["targets"][0]["instant"] and panel["targets"][0]["legendFormat"]=="{{kind}}"
assert panel["fieldConfig"]["defaults"]["unit"]=="short" and "cache_read" in panel["description"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent cost: daily Claude tokens and cost panels split by kind" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-cost.yaml").read_text()
cost=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
by_id={p["id"]:p for p in cost["panels"]}
p32=by_id[32]; daily=by_id[87]; gauge=by_id[88]
assert p32["title"]=="Claude tokens per day" and p32["type"]=="barchart"
assert p32["targets"][0]["expr"]=="sum by (date, model) (k3dm_dispatch_claude_daily_tokens)"
assert p32["gridPos"]=={"h":8,"w":24,"x":0,"y":19}
assert p32["options"]["stacking"]=="normal" and p32["options"]["xField"]=="date"
assert "all token kinds including cache reads" in p32["description"]
assert daily["title"]=="Claude tokens per day by kind" and daily["type"]=="barchart"
assert daily["targets"][0]["expr"]=="sum by (date, kind) (k3dm_dispatch_claude_daily_tokens_by_kind)"
assert daily["targets"][0]["legendFormat"]=="{{kind}}" and daily["gridPos"]=={"h":8,"w":24,"x":0,"y":35}
assert daily["options"]["stacking"]=="normal" and "cache_read" in daily["description"] and "fraction" in daily["description"]
for p in (p32, daily):
  opt=p["options"]
  assert opt["showValue"]=="never" and opt["tooltip"]=={"mode":"multi","sort":"desc"}
  assert opt["xTickLabelRotation"]==-45 and opt["xTickLabelSpacing"]==100
  assert opt.get("showValue") not in ("always","auto")
  assert "text" not in opt or "valueSize" not in opt["text"]
assert gauge["title"]=="Claude cost by kind" and gauge["type"]=="bargauge"
assert gauge["targets"][0]["expr"]=='k3dm_dispatch_claude_api_cost_by_kind_usd{window="$window"}'
assert gauge["targets"][0]["instant"] and gauge["targets"][0]["legendFormat"]=="{{kind}}"
assert gauge["fieldConfig"]["defaults"]["unit"]=="currencyUSD" and gauge["fieldConfig"]["defaults"]["decimals"]==2
assert gauge["gridPos"]=={"h":8,"w":6,"x":18,"y":27}
assert gauge["options"]["orientation"]=="horizontal" and gauge["options"]["namePlacement"]=="left"
assert gauge["options"]["text"]=={"titleSize":14,"valueSize":20}
assert "cache_read" in gauge["description"] and "fraction" in gauge["description"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent dashboards: labels and titles stay readable and release-only stats say why they are empty" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
def load(name,key):
  return json.loads("\n".join(x[4:] for x in (base/name).read_text().split(f"  {key}: |\n",1)[1].splitlines()))
cost={p["id"]:p for p in load("grafana-dashboard-agent-cost.yaml","agent-cost.json")["panels"]}
dispatch={p["id"]:p for p in load("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json")["panels"]}
assert cost[34]["gridPos"]["w"]>=6 and cost[93]["gridPos"]["x"]==cost[34]["gridPos"]["w"]
assert cost[34]["gridPos"]["h"]==cost[93]["gridPos"]["h"]==cost[86]["gridPos"]["h"]==cost[88]["gridPos"]["h"]
assert sum(cost[i]["gridPos"]["w"] for i in (34,93,86,88))==24
for i in (29,31):
  assert cost[i]["fieldConfig"]["defaults"]["noValue"]=="Release window only",i
for i in (32,87):
  if cost[i]["options"].get("showValue") != "never":
    assert cost[i]["options"].get("text", {}).get("valueSize", 0) >= 14, i  # agent-audit: allow assert-removed valueSize guard made conditional on showValue, bug 2026-11-07-claude-tokens-per-day-chart-crowded-labels
rename=[o for o in dispatch[85]["fieldConfig"]["overrides"] if o["matcher"]=={"id":"byName","options":"continue_prompt"}]
assert rename and {"id":"displayName","value":"continue"} in rename[0]["properties"]
assert dispatch[85]["options"]["namePlacement"]=="top"
assert dispatch[85]["gridPos"]["h"]>=8 and dispatch[84]["gridPos"]["h"]==dispatch[85]["gridPos"]["h"]
assert [t["legendFormat"] for t in dispatch[85]["targets"]]==["{{reason}}","tracked tasks"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
dispatch=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
spec=[p for p in dispatch["panels"] if p["title"]=="Per spec"][0]
exprs=[t["expr"] for t in spec["targets"] if "k3dm_dispatch_model_identity" in t["expr"]]
assert len(exprs)==4,exprs
for role in ("worker","coordinator","primary_coordinator","acting_coordinator"):
  assert any(f'role="{role}"' in e and '"display"' in e for e in exprs),role
assert not any('model!="unknown"' in e for e in exprs)
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1]) / "grafana-dashboard-agent-dispatch.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["title"]=="Per spec")
org=next(t["options"] for t in panel["transformations"] if t["id"]=="organize")
for field,label in (("Value #S","Handoffs"),("Value #T","Primary cost USD"),("primary_cost_state","Primary cost status")):
  assert not org["excludeByName"].get(field),field
  assert org["renameByName"].get(field)==label,(field,org["renameByName"].get(field))
overrides={}
for item in panel["fieldConfig"]["overrides"]:
  props={p["id"]:p["value"] for p in item["properties"]}
  if "custom.width" in props:
    overrides[item["matcher"]["options"]]=props
assert overrides["Handoffs"]["custom.width"]>0
assert overrides["Primary cost USD"]["custom.width"]>0
assert overrides["Primary cost USD"]["unit"]=="currencyUSD"
assert overrides["Primary cost status"]["custom.width"]>0
width_sum=sum(props["custom.width"] for props in overrides.values())
assert width_sum<=panel["gridPos"]["w"]*55,(width_sum,panel["gridPos"])
assert panel["gridPos"]["w"]==24
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
dispatch={p["id"]:p for p in json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]}
assert dispatch[12]["gridPos"]=={"h":10,"w":24,"x":0,"y":12},dispatch[12]["gridPos"]
assert dispatch[12]["fieldConfig"]["defaults"]["custom"]["minWidth"]<=80
assert dispatch[9]["gridPos"]=={"h":4,"w":12,"x":0,"y":22} and dispatch[13]["gridPos"]=={"h":4,"w":12,"x":12,"y":22}
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["id"]==47)
props={o["matcher"]["options"]:{p["id"]:p["value"] for p in o["properties"]} for o in panel["fieldConfig"]["overrides"]}
mappings=props["Log"]["mappings"]
assert next(m for m in mappings if m["type"]=="value")["options"][""]["text"]=="Open run evidence"
assert any(m["type"]=="special" and m["options"]["match"]=="null" and m["options"]["result"]["text"]=="Open run evidence" for m in mappings)
assert props["Log"]["links"][0]["url"].startswith("/d/k3dm-agent-run-log?")
assert next(m for m in mappings if m["type"]=="value")["options"].keys()=={""}
assert props["outcome"]["mappings"][0]["options"]["unknown"]["text"]=="unverified"
assert props["Result"]["mappings"][0]["options"]["none"]["text"]=="No landing-test evidence recorded"
assert all(p["id"]!=93 for p in d["panels"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch: unrecorded attribution is labeled without overwriting known identities" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["id"]==12)
props={o["matcher"]["options"]:{p["id"]:p["value"] for p in o["properties"]} for o in panel["fieldConfig"]["overrides"]}
for field in ["Worker","Coordinator (legacy)","Primary coordinator","Acting coordinator","Landed by"]:
    opts=props[field]["mappings"][0]["options"]
    assert opts=={"unknown":{"text":"not recorded"}}
assert len(d["panels"])==35
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent cost: whole-system API panels meet the cost and denominator contract" {
  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
by_title={p["title"]:p for p in d["panels"]}
titles=["Claude + Codex at API prices","Claude + Codex per live-verified spec","API run rate / month","API vs replaced plans"]
row=next(p for p in d["panels"] if p["title"]=="Whole system at API prices")
assert row["type"]=="row" and row["gridPos"]["y"]>=max(p["gridPos"]["y"]+p["gridPos"]["h"] for p in d["panels"] if p["id"] not in range(94,99) and p["id"] not in range(107,113))
for title in titles:
    p=by_title[title]
    assert p["type"]=="stat" and p["gridPos"]["y"]>row["gridPos"]["y"]
    assert p["targets"][0]["instant"]
    assert "API price" in p["description"]
assert [by_title[t]["id"] for t in titles]==[95,96,97,98]
assert [by_title[t]["fieldConfig"]["defaults"]["unit"] for t in titles]==["currencyUSD","currencyUSD","currencyUSD","x"]
expr0=by_title[titles[0]]["targets"][0]["expr"]
expr1=by_title[titles[1]]["targets"][0]["expr"]
expr2=by_title[titles[2]]["targets"][0]["expr"]
expr3=by_title[titles[3]]["targets"][0]["expr"]
for metric in ("k3dm_dispatch_claude_api_cost_usd","k3dm_dispatch_api_cost_usd","k3dm_dispatch_unledgered_api_cost_usd"):
    assert metric in expr0 and metric in expr1
assert 'window="$window"' in expr0 and 'window="$window"' in expr1
assert " or " in expr0 and " or " in expr1
assert 'level="live"' in expr1 and "> 0" in expr1
assert "k3dm_claude_verified_specs{window=\"$window\"}" not in expr1
assert 'window="7d"' in expr2 and 'window="7d"' in expr3
for metric in ("k3dm_dispatch_claude_api_cost_observed_days","k3dm_dispatch_api_cost_observed_days"):
    assert metric in expr2 and metric in expr3
assert "k3dm_dispatch_unledgered_api_cost_usd" in expr2 and "k3dm_dispatch_unledgered_api_cost_usd" in expr3
assert '{plan="claude"}' in expr3 and '{plan="chatgpt"}' in expr3
assert all(f'plan="{plan}"' not in expr3 for plan in ("gemini","github","hostinger"))
assert all("failed dispatches" in by_title[t]["description"] and "rework" in by_title[t]["description"] for t in titles)
assert "Claude + ChatGPT" in by_title[titles[3]]["description"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent cost: existing panels are unchanged and new API panels do not overlap" {
  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
import json,subprocess,sys
from pathlib import Path
path=Path(sys.argv[1]); text=path.read_text()
def load(raw): return json.loads("\n".join(x[4:] for x in raw.split("  agent-cost.json: |\n",1)[1].splitlines()))
current=load(text)
base=load(subprocess.check_output(["git","show","HEAD:scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml"],text=True))
old={p["id"]:p for p in base["panels"]}
now={p["id"]:p for p in current["panels"]}
assert set(old).issubset(now)
for panel_id,panel in old.items():
    assert now[panel_id]==panel,(panel_id,"existing panel changed")
for i,a_panel in enumerate(current["panels"]):
    a=a_panel["gridPos"]
    for b_panel in current["panels"][i+1:]:
        b=b_panel["gridPos"]
        assert not (a["x"]<b["x"]+b["w"] and b["x"]<a["x"]+a["w"] and a["y"]<b["y"]+b["h"] and b["y"]<a["y"]+a["h"]),(a_panel["id"],b_panel["id"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent cost: API cost expression stub matches the 7d baseline and missing release term" {
  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
p={x["title"]:x for x in d["panels"]}
expr=p["Claude + Codex per live-verified spec"]["targets"][0]["expr"]
assert all(term in expr for term in ("sum by (window) (k3dm_dispatch_claude_api_cost_usd", "sum by (window) (k3dm_dispatch_api_cost_usd", "sum by (window) (k3dm_dispatch_unledgered_api_cost_usd", "sum by (window) (k3dm_claude_verified_specs"))
claude,ledgered,unledgered,live=292.58,5.41,0.10,93
assert abs((claude+ledgered+unledgered)/live-3.21)<=0.01
# Release windows omit unledgered data; the PromQL `or ... * 0` fallback contributes zero.
assert abs((292.58+5.41+0)/93-3.21)<=0.01
assert " or " in expr and "* 0" in expr
print("ok: 7d = $3.21/live-verified; missing unledgered release term = zero")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"7d ="* && "$output" == *"missing unledgered release term = zero"* ]]
}

@test "agent activity: configured setting and observed compaction point are distinct" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
import json,sys
text=open(sys.argv[1]).read()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
panels={p["title"]:p for p in d["panels"]}
assert "Auto-compact threshold" not in panels
configured=panels["Auto-compact setting (configured)"]
assert configured["targets"][0]["expr"]=="k3dm_claude_auto_compact_tokens"
assert "docs/metrics/context-window-experiment.md" in configured["description"]
assert "may not take effect" in configured["description"] and "effective threshold" not in configured["description"].lower()
observed=panels["Observed compaction point"]
assert observed["type"]=="stat"
expr=observed["targets"][0]["expr"]
assert expr=='k3dm_claude_compaction_pre_tokens_sum{window="$window",trigger="auto"} / k3dm_claude_compactions{window="$window",trigger="auto"}'
assert "k3dm_claude_auto_compact_tokens" not in expr
defaults=observed["fieldConfig"]["defaults"]
assert defaults["unit"]=="short" and defaults["noValue"]=="No auto-compactions in window"
assert {m["options"]["match"] for m in defaults["mappings"] if m["type"]=="special" and m["options"]["result"]["text"]==defaults["noValue"]} >= {"nan","null"}
a,b=configured["gridPos"],observed["gridPos"]
assert a["y"]==b["y"] and a["x"]+a["w"]==b["x"]
PYTEST
  [ "$status" -eq 0 ]
}

@test "agent activity: wasted reread share and empty mapping" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
import json, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
panels=json.loads("\n".join(line[4:] for line in text.split("  agent-activity.json: |\n",1)[1].splitlines()))["panels"]
by_title={p["title"]:p for p in panels}
assert "Re-read share after compaction" in by_title
panel=by_title["Wasted re-read share"]
assert panel["targets"][0]["expr"]=='k3dm_claude_reads{window="$window",kind="reread_unchanged"} / ignoring(kind) (k3dm_claude_reads{window="$window",kind="all"} > 0)'
assert panel["fieldConfig"]["defaults"]["unit"]=="percentunit"
assert panel["fieldConfig"]["defaults"]["noValue"]=="No reads in window"
assert any(m["options"]["result"]["text"]=="No reads in window" for m in panel["fieldConfig"]["defaults"]["mappings"])
for i,a in enumerate(panels):
 for b in panels[i+1:]:
  x,y=a["gridPos"],b["gridPos"]
  assert not (x["x"]<y["x"]+y["w"] and y["x"]<x["x"]+x["w"] and x["y"]<y["y"]+y["h"] and y["y"]<x["y"]+x["h"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent activity: repo gauges cap named series and preserve the remainder" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
import json,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
panels=json.loads("\n".join(line[4:] for line in text.split("  agent-activity.json: |\n",1)[1].splitlines()))["panels"]
by_title={p["title"]:p for p in panels}
for title,group,metric,legend in (("Untracked by repo","repo, mode","k3dm_codex_untracked_sessions","{{repo}} {{mode}}"),("Tokens by repo","repo","k3dm_codex_tokens","{{repo}}")):
    panel=by_title[title]
    base=f'sum by ({group}) ({metric}{{window="$window"}})'
    named,other=panel["targets"]
    assert named["expr"]==f'topk(8, {base})' and named["legendFormat"]==legend and named["instant"]
    assert other["expr"]==f'(sum({base}) - sum(topk(8, {base}))) > 0'
    assert other["legendFormat"]=="other" and other["instant"]
    assert panel["gridPos"]["h"]>=5 and panel["options"]["namePlacement"]=="top"
PYTEST
  [ "$status" -eq 0 ]
}

@test "agent activity: agy data source names local host and source without overlap" {
  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
import json,sys
text=open(sys.argv[1]).read()
panels=json.loads("\n".join(line[4:] for line in text.split("  agent-activity.json: |\n",1)[1].splitlines()))["panels"]
panel=next(p for p in panels if p["title"]=="agy data source")
assert panel["type"]=="stat" and panel["targets"][0]["expr"]=='k3dm_agy_source_present{source!="none"}'
assert panel["targets"][1]["expr"]=='k3dm_agy_source_present{source="none"}'
assert [target["refId"] for target in panel["targets"]]==["A","B"]
assert panel["options"]["textMode"]=="name"
assert panel["gridPos"]=={"h":8,"w":6,"x":12,"y":60}
assert "host" in panel["targets"][0]["legendFormat"] and "source" in panel["targets"][0]["legendFormat"]
assert "interactive and print" in panel["description"] and "not combined" in panel["description"]
warning=panel["fieldConfig"]["overrides"][0]
assert warning["matcher"]=={"id":"byFrameRefID","options":"B"}
assert warning["properties"][0]["value"]["fixedColor"]=="red"
for i,a in enumerate(panels):
 for b in panels[i+1:]:
  x,y=a["gridPos"],b["gridPos"]
  assert not (x["x"]<y["x"]+y["w"] and y["x"]<x["x"]+x["w"] and x["y"]<y["y"]+y["h"] and y["y"]<x["y"]+x["h"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch: outcome row accommodates nine labels and preserves subsequent layout" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panels={p["title"]:p for p in d["panels"]}
row=("Run outcomes", "Rejected-attempt Codex tokens", "Run outcome coverage", "Codex tokens per live-verified bug")
for x,title in enumerate(row):
    assert panels[title]["gridPos"]=={"h":9,"w":6,"x":6*x,"y":33}, (title,panels[title]["gridPos"])
options=panels["Run outcomes"]["options"]
assert options["orientation"]=="horizontal" and options["namePlacement"]=="left" and options["minVizHeight"]==20
# Original positions before expanding the outcome row; all other dimensions stay fixed.
later={"Per run evidence":(10,18,6,39), "First-pass live verification":(10,6,0,39),
       "Lines changed total":(4,6,0,49), "Median lines / spec":(4,6,6,49),
       "Acceptance items total":(4,6,12,49), "Measured":(4,6,18,49),
       "Final worker exit → land":(8,6,0,54), "Human continuation prompts":(8,18,6,54)}
assert {p["title"] for p in d["panels"] if 42<=p["gridPos"]["y"]<65}==set(later)
for title,(h,w,x,y) in later.items():
    assert panels[title]["gridPos"]=={"h":h,"w":w,"x":x,"y":y+3},title
# The expanded row and the immediately following row tile the whole width without gaps or overlaps.
for y in range(33,52):
    cells=[x for p in d["panels"] for x in range(p["gridPos"]["x"],p["gridPos"]["x"]+p["gridPos"]["w"])
           if p["gridPos"]["y"]<=y<p["gridPos"]["y"]+p["gridPos"]["h"]]
    assert sorted(cells)==list(range(24)),y
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: claimed verification stat is present" {
  run grep -F 'k3dm_dispatch_verification_claimed' "$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
  [ "$status" -eq 0 ]
}

@test "agent dispatch dashboard: S1 gate panels exist and match query and description contract" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" <<'PY'
import json, re, sys
from pathlib import Path
d = json.loads("\n".join(x[4:] for x in open(sys.argv[1]).read().split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
exporter = Path(sys.argv[2]).read_text()
panels = {p["title"]: p for p in d["panels"]}

expected_panels = ["Stalled tasks", "Live verification pending", "Verification ladder", "Split work"]
for title in expected_panels:
    assert title in panels, f"missing panel: {title}"
    desc = panels[title].get("description", "").lower()
    assert "self-reported and advisory" in desc, f"{title} description missing advisory note: {desc}"

series_by_panel = {
    "Stalled tasks": "k3dm_dispatch_stalled_tasks",
    "Live verification pending": "k3dm_dispatch_live_pending_tasks",
    "Verification ladder": "k3dm_dispatch_ladder_tasks",
}
for title, series in series_by_panel.items():
    exprs = "\n".join(t.get("expr", "") for t in panels[title].get("targets", []))
    assert series in exprs, f"{title} targets do not query {series}: {exprs}"
    assert series in exporter, f"{series} not in exporter"

split = panels["Split work"]
split_exprs = [t.get("expr", "") for t in split.get("targets", [])]
for s in ("k3dm_dispatch_split_parent_parts", "k3dm_dispatch_split_parent_conflicts",
          "k3dm_dispatch_split_parent_info", "k3dm_dispatch_split_parent_elapsed_seconds"):
    assert any(s in expr for expr in split_exprs), f"Split work missing query for {s}"
    assert s in exporter, f"{s} not in exporter"

for role in ("build", "review", "verify"):
    assert any(f'role="{role}"' in expr for expr in split_exprs), f"Split work missing target for role {role}"

for expr in split_exprs:
    assert ", role" not in expr and "by (role)" not in expr and "by (parent, role)" not in expr, f"target groups by role: {expr}"

info_expr = next(expr for expr in split_exprs if "split_parent_info" in expr)
assert "pending" not in info_expr, f"info query has pending filter: {info_expr}"

join_transform = next((t for t in split.get("transformations", []) if t.get("id") == "joinByField"), None)
assert join_transform is not None, "Split work missing joinByField transformation"
assert join_transform.get("options", {}).get("byField") == "parent"
assert join_transform.get("options", {}).get("mode") == "outer"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "agent dispatch dashboard: Split work outer join on synthetic metrics" {
  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" "${BATS_TEST_DIRNAME}/../fixtures/dispatch-gates/synthetic.jsonl" <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

dashboard = json.loads("\n".join(x[4:] for x in open(sys.argv[1]).read().split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
exporter_path = sys.argv[2]
fixture_path = Path(sys.argv[3])

with tempfile.TemporaryDirectory() as tmpdir:
    wt = Path(tmpdir) / "worktrees"
    wt.mkdir()
    shutil.copy(fixture_path, wt / "ledger.jsonl")
    env = os.environ.copy()
    env["K3DM_WORKTREE_ROOT"] = str(wt)
    env["K3DM_DISPATCH_PUSHGATEWAY_URL"] = "http://127.0.0.1:9"
    proc = subprocess.run([sys.executable, exporter_path, "--dry-run"], env=env, capture_output=True, text=True, check=True)
    metrics_text = proc.stdout

split_panel = next(p for p in dashboard["panels"] if p["title"] == "Split work")
join_tf = next(t for t in split_panel["transformations"] if t["id"] == "joinByField")
assert join_tf["options"]["byField"] == "parent"
assert join_tf["options"]["mode"] == "outer"

split_exprs = [t.get("expr", "") for t in split_panel["targets"]]
for role in ("build", "review", "verify"):
    assert any(f'role="{role}"' in expr for expr in split_exprs)
for expr in split_exprs:
    assert ", role" not in expr and "by (role)" not in expr and "by (parent, role)" not in expr

info_expr = next(expr for expr in split_exprs if "split_parent_info" in expr)
assert "pending" not in info_expr

build = {}
review = {}
verify = {}
for line in metrics_text.splitlines():
    m = re.match(r'^k3dm_dispatch_split_parent_parts\{version="[^"]+",parent="([^"]+)",role="([^"]+)"\}\s+([0-9.]+)', line)
    if m:
        p, r, v = m.group(1), m.group(2), int(float(m.group(3)))
        if r == "build":
            build[p] = v
        elif r == "review":
            review[p] = v
        elif r == "verify":
            verify[p] = v

conflicts = {}
for line in metrics_text.splitlines():
    m = re.match(r'^k3dm_dispatch_split_parent_conflicts\{version="[^"]+",parent="([^"]+)"\}\s+([0-9.]+)', line)
    if m:
        conflicts[m.group(1)] = int(float(m.group(2)))

combines = {}
for line in metrics_text.splitlines():
    m = re.match(r'^k3dm_dispatch_split_parent_info\{version="[^"]+",parent="([^"]+)",combine="([^"]+)"\}\s+([0-9.]+)', line)
    if m:
        combines[m.group(1)] = m.group(2)

elapsed = {}
for line in metrics_text.splitlines():
    m = re.match(r'^k3dm_dispatch_split_parent_elapsed_seconds\{version="[^"]+",parent="([^"]+)"\}\s+([0-9.]+)', line)
    if m:
        elapsed[m.group(1)] = int(float(m.group(2)))

all_parents = sorted(set(list(build.keys()) + list(review.keys()) + list(verify.keys()) + list(conflicts.keys()) + list(combines.keys()) + list(elapsed.keys())))
joined_rows = []
for p in all_parents:
    joined_rows.append({
        "parent": p,
        "build": build.get(p),
        "review": review.get(p),
        "verify": verify.get(p),
        "conflicts": conflicts.get(p),
        "combine": combines.get(p),
        "elapsed": elapsed.get(p),
    })

assert len(joined_rows) == len(all_parents)
assert len(joined_rows) == len(set(r["parent"] for r in joined_rows))

p_one_rows = [r for r in joined_rows if r["parent"] == "p-one"]
assert len(p_one_rows) == 1
p1 = p_one_rows[0]
assert p1["build"] == 2 and p1["verify"] == 1 and p1["review"] == 0
assert p1["conflicts"] == 1 and p1["combine"] == "pass" and p1["elapsed"] == 70

for no_comb in ("p-two", "p-four"):
    r = next(row for row in joined_rows if row["parent"] == no_comb)
    assert r["combine"] == "pending"
    assert r["conflicts"] is None
    assert r["elapsed"] is None

p_four = next(r for r in joined_rows if r["parent"] == "p-four")
assert p_four["build"] == 0 and p_four["verify"] == 0 and p_four["review"] == 1
p_orphan = next(r for r in joined_rows if r["parent"] == "p-orphan")
assert p_orphan["build"] == 0 and p_orphan["review"] == 0 and p_orphan["verify"] == 0
assert p_orphan["combine"] == "pass"

print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}
