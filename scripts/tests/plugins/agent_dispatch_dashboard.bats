#!/usr/bin/env bats

BASE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops"
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
expected={35:("Compactions per verified spec","stat","short"),36:("Compactions by trigger","bargauge","none"),37:("Re-read share after compaction","stat","percentunit"),38:("Context incidents","bargauge","none"),39:("Auto-compact threshold","stat","short")}
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
assert all(t["expr"].startswith(("sum by (version, slug, repo)","max by (version, slug, spec, agent, repo)","max by (version, slug, repo, worker)","max by (version, slug, repo, coordinator)")) for t in panel12["targets"])
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
assert any(p["title"]=="Dispatch-to-land elapsed (wall clock)" for p in d["panels"])
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
assert sorted(all_ids)==sorted(old_ids+[83,84,85,86,87,88]) and len(all_ids)==len(set(all_ids))
assert set(p["id"] for p in new[0]["panels"])==set(range(1,14))|{40,41,84,85}|set(range(42,49))
assert set(p["id"] for p in new[1]["panels"])=={19,20,21,22,23,24,25,27,28,29,30,31,32,34,86,87,88}
assert set(p["id"] for p in new[2]["panels"])=={33,83}|set(range(35,40))|set(range(49,65))|set(range(66,72))
print(f"ok: {len(all_ids)} panels, each exactly once")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: 70 panels, each exactly once"* ]]
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
    if panel["id"] in (47,83,84,85,86,87,88):
      continue
    for field in ("targets","fieldConfig","options"):
      new,old_field=panel.get(field),old_by_id[panel["id"]].get(field)
      if field=="options" and panel["id"]==48:
        continue
      if panel["id"]==12:
        continue
      if field=="options" and panel["type"]=="bargauge":
        new={k:v for k,v in (new or {}).items() if k not in ("orientation","namePlacement","minVizHeight","text")} or None
      if field=="fieldConfig" and panel["id"] in (29,31):
        new=json.loads(json.dumps(new)); new["defaults"].pop("noValue",None)
      if field=="options" and panel["id"]==32:
        new={k:v for k,v in new.items() if k!="text"}
      if field=="fieldConfig" and panel["id"] in (56,71) and new["defaults"].get("unit")=="short":
        new=json.loads(json.dumps(new)); new["defaults"]["unit"]=old_field["defaults"]["unit"]
      assert new==old_field,(panel["id"],field)
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
claude=[by_id[i] for i in (35,36,37,38,39)]
assert min(p["gridPos"]["x"] for p in claude)==0
for p in claude:
  assert p["gridPos"]["w"]>=(12 if p["type"]=="bargauge" else 8),(p["id"],p["gridPos"])
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
  assert target["expr"].startswith("sum by (version, slug, run, ") and 'label_join(' in target["expr"] and '"doc", "plans/$1"' in target["expr"] and '"doc", "bugs/$1"' in target["expr"]
ids=[t["id"] for t in table.get("transformations",[])]
assert ids[:3]==["merge","sortBy","organize"],ids
assert table["transformations"][1]["options"]["sort"]==[{"field":"vsort","desc":True}] and "sortBy" not in table["options"]
for target in table["targets"]:
  assert target["expr"].split(") (",1)[0].endswith(", vsort") and '"v$1.0$2.$3"' in target["expr"] and '"$1.0$2"' in target["expr"]
org=table["transformations"][2]["options"]
for hidden in ("Time","__name__","job","window","Value #A","vsort"):
  assert org["excludeByName"].get(hidden) is True,hidden
assert not org["excludeByName"].get("doc"),"doc feeds the slug link; excluding it empties the URL"
assert any(o["matcher"]=={"id":"byName","options":"doc"} and {"id":"custom.hidden","value":True} in o["properties"] for o in table["fieldConfig"]["overrides"])
order=sorted(org["indexByName"],key=org["indexByName"].get)
assert order[:4]==["version","slug","run","Value #B"],order
assert org["renameByName"].get("Value #B")=="Tokens"
assert "k3dm_dispatch_task_run_agent_tokens{" in next(x["expr"] for x in table["targets"] if x["refId"]=="B")
links=[l for o in table["fieldConfig"]["overrides"] if o["matcher"]=={"id":"byName","options":"slug"} for p in o["properties"] if p["id"]=="links" for l in p["value"]]
assert len(links)==1 and links[0]["url"]=="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-${__data.fields.version}/docs/${__data.fields.doc}.md"
assert org["renameByName"].get("evidence_summary")=="Result"
assert org["renameByName"].get("evidence_path")=="Log"
assert org["excludeByName"].get("evidence") is True
assert "evidence_summary" in table["targets"][0]["expr"] and "evidence_path" in table["targets"][0]["expr"]
log_overrides=[o for o in table["fieldConfig"]["overrides"] if o["matcher"]=={"id":"byName","options":"Log"}]
assert len(log_overrides)==1
log_properties={p["id"]:p["value"] for p in log_overrides[0]["properties"]}
assert log_properties.get("custom.inspect") is True and log_properties.get("custom.width", 999)>0 and log_properties["custom.width"]<=160
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

@test "agent dispatch: per spec shows which agent landed each spec" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
panel=next(p for p in d["panels"] if p["id"]==12)
spec=[t for t in panel["targets"] if "k3dm_dispatch_task_spec" in t["expr"]]
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
  run python3 - "${BASE}" <<'PY'
import json,sys
from pathlib import Path
base=Path(sys.argv[1])
def load(name,key):
    text=(base/name).read_text()
    return json.loads("\n".join(line[4:] for line in text.split(f"  {key}: |\n",1)[1].splitlines()))
d=load("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json")
panel=next(p for p in d["panels"] if p["id"]==47)
log=next(o for o in panel["fieldConfig"]["overrides"] if o["matcher"].get("options")=="Log")
props=log["properties"]
assert any(p["id"]=="custom.inspect" and p["value"] for p in props)
links=next(p["value"] for p in props if p["id"]=="links")
url=links[0]["url"]
assert links[0]["title"]=="Open log" and "/d/k3dm-agent-run-log" in url
assert all(f"var-{key}=${{__data.fields.{key}}}" in url for key in ("version","slug","run")),url
assert "file://" not in json.dumps(d)
runlog=load("grafana-dashboard-agent-run-log.yaml","agent-run-log.json")
assert runlog["uid"]=="k3dm-agent-run-log"
p=runlog["panels"][0]
assert p["type"]=="logs" and p["datasource"]["uid"]=="loki"
expr=p["targets"][0]["expr"]
assert 'job="k3dm-dispatch-run"' in expr and all(f'${key}' in expr for key in ("version","slug","run"))
assert runlog["time"]=={"from":"now-30d","to":"now"}
print("ok")
PY
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
daily=by_id[87]; gauge=by_id[88]
assert daily["title"]=="Claude tokens per day by kind" and daily["type"]=="barchart"
assert daily["targets"][0]["expr"]=="sum by (date, kind) (k3dm_dispatch_claude_daily_tokens_by_kind)"
assert daily["targets"][0]["legendFormat"]=="{{kind}}" and daily["gridPos"]=={"h":8,"w":24,"x":0,"y":35}
assert daily["options"]["stacking"]=="normal" and "cache_read" in daily["description"] and "fraction" in daily["description"]
assert gauge["title"]=="Claude cost by kind" and gauge["type"]=="bargauge"
assert gauge["targets"][0]["expr"]=='k3dm_dispatch_claude_api_cost_by_kind_usd{window="$window"}'
assert gauge["targets"][0]["instant"] and gauge["targets"][0]["legendFormat"]=="{{kind}}"
assert gauge["fieldConfig"]["defaults"]["unit"]=="currencyUSD" and gauge["fieldConfig"]["defaults"]["decimals"]==2
assert gauge["gridPos"]=={"h":8,"w":8,"x":16,"y":27}
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
assert cost[34]["gridPos"]["w"]>=6 and cost[86]["gridPos"]["x"]==cost[34]["gridPos"]["w"]
assert cost[34]["gridPos"]["h"]==cost[86]["gridPos"]["h"]==cost[88]["gridPos"]["h"]
assert sum(cost[i]["gridPos"]["w"] for i in (34,86,88))==24
for i in (29,31):
  assert cost[i]["fieldConfig"]["defaults"]["noValue"]=="Release window only",i
for i in (32,87):
  assert cost[i]["options"]["text"]["valueSize"]>=14,i
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

@test "agent dispatch dashboard: Per spec leaves an unknown worker or coordinator blank" {
  run python3 - "$BASE" <<'PY'
import json,sys
from pathlib import Path
text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
dispatch=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
spec=[p for p in dispatch["panels"] if p["title"]=="Per spec"][0]
exprs=[t["expr"] for t in spec["targets"] if "k3dm_dispatch_model_identity" in t["expr"]]
assert len(exprs)==2,exprs
for role in ("worker","coordinator"):
  assert any(f'role="{role}",model!="unknown"' in e for e in exprs),role
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}
