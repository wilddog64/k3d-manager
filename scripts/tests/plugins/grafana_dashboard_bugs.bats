#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  dashboard="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-bugs.yaml"
  metrics="${BATS_TEST_DIRNAME}/../../../bin/k3dm-vectordb-metrics"
}

@test "bug dashboard is valid JSON with uid and Prometheus datasource" {
  run python3 -c 'import json,sys; p=sys.argv[1]; s=open(p).read().split("  k3dm-bugs.json: |\n",1)[1]; d=json.loads(s); assert d["uid"] == "k3dm-bugs"; assert "datasource" in d or any("datasource" in panel for panel in d["panels"])' "${dashboard}"
  [ "${status}" -eq 0 ]
}

@test "bug dashboard has a release variable" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
variable = next(v for v in data["templating"]["list"] if v["name"] == "release")
assert variable["includeAll"] is True and variable["multi"] is True
assert variable["allValue"] == ".*"
assert "k3dm_bug_info" in variable["definition"]
assert variable["sort"] == 0
assert variable["regex"] == r"/^\S+ (?<value>\S+)$/"
assert "release_order" in variable["definition"]
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard has a repo variable and scopes every bug selector" {
  run python3 - "${dashboard}" <<'PY'
import json, re, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
repo = next(v for v in data["templating"]["list"] if v["name"] == "repo")
assert repo["type"] == "custom" and repo["query"] == "k3d-manager,lib-foundation"
assert repo["multi"] is False and repo["current"]["value"] == "k3d-manager"
for panel in data["panels"]:
    for target in panel.get("targets", []):
        expr = target["expr"]
        for metric in re.findall(r"k3dm_bug_[a-z_]+", expr):
            assert f'{metric}{{repo="$repo"' in expr, expr
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard has a verified filter" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
variable = next(v for v in data["templating"]["list"] if v["name"] == "verified")
assert variable["type"] == "custom"
assert variable["current"]["value"] == "^(false)?$"
assert variable["current"]["text"] == "Hide live-verified"
assert variable["query"] == "Hide live-verified : ^(false)?$,Show all : .*"
PY
  [ "${status}" -eq 0 ]
}

@test "release dropdown and table use version-order labels" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
variable = next(v for v in data["templating"]["list"] if v["name"] == "release")
assert variable["query"]["query"] == 'label_values(k3dm_bug_info{repo="$repo"}, release_order)'
table = next(panel for panel in data["panels"] if panel["id"] == 23)
organize = next(t for t in table["transformations"] if t["id"] == "organize")["options"]
assert organize["indexByName"]["release_order"] == 0
assert organize["excludeByName"]["release"] is True
assert organize["renameByName"]["release_order"] == "Release"
release = next(o for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"] == "Release")
mapping = next(p["value"][0] for p in release["properties"] if p["id"] == "mappings")
assert mapping["options"]["result"]["text"] == "$1"
PY
  [ "${status}" -eq 0 ]
}

@test "release filters status summary stats and table" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
for panel_id in (9, 10, 11, 12, 13, 16, 17, 23):
    assert 'release=~"$release"' in panels[panel_id]["targets"][0]["expr"]
for panel_id in (14, 15):
    assert 'release=~"$release"' not in " ".join(t["expr"] for t in panels[panel_id]["targets"])
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard separates filed-in and fixed-in release views" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
assert "k3dm_bug_fixed_in_release_docs" in panels[4]["targets"][0]["expr"]
assert panels[8]["title"] == "Bugs filed per release, open vs fixed"
assert panels[25]["targets"][0]["expr"] == 'sum by (release, order, priority) (k3dm_bug_fixed_in_release_docs{repo="$repo"}) > 0'
assert [panels[i]["gridPos"] for i in (7, 8, 25)] == [
    {"x": 0, "y": 6, "w": 8, "h": 9},
    {"x": 8, "y": 6, "w": 8, "h": 9},
    {"x": 16, "y": 6, "w": 8, "h": 9},
]
organize = next(t for t in panels[23]["transformations"] if t["id"] == "organize")["options"]
assert organize["indexByName"]["fixed_in"] == 6
assert organize["renameByName"]["fixed_in"] == "Fixed in"
assert organize["indexByName"]["verified"] == 7 and organize["indexByName"]["live_verified"] == 8
PY
  [ "${status}" -eq 0 ]
}

@test "every bug metric queried by dashboard is emitted" {
  run python3 - "${dashboard}" "${metrics}" <<'PY'
import json, runpy, sys, tempfile
from pathlib import Path
dashboard, metrics_path = sys.argv[1:]
raw = Path(dashboard).read_text().split("  k3dm-bugs.json: |\n", 1)[1]
data = json.loads(raw)
import re
queries = set()
for panel in data["panels"]:
    for target in panel.get("targets", []):
        queries.update(re.findall(r"k3dm_bug_[a-z_]+", target["expr"]))
for variable in data.get("templating", {}).get("list", []):
    queries.update(re.findall(r"k3dm_bug_[a-z_]+", variable.get("definition", "")))
module = runpy.run_path(metrics_path)
with tempfile.TemporaryDirectory() as tmp:
    bugs = Path(tmp) / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "one.md").write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED\n")
    output = module["_bug_metrics"](Path(tmp)) + module["_bug_status_metrics"](Path(tmp))
source = Path(metrics_path).read_text()
assert {"k3dm_bug_docs", "k3dm_bug_release_docs", "k3dm_bug_current_release_info", "k3dm_bug_later_release_open_docs", "k3dm_bug_info", "k3dm_bug_status_docs"} <= queries
missing = [name for name in queries if name + "{" not in output and name + " " not in output and name + "{{" not in source]
assert not missing, missing
assert "k3dm_bug_docs_scan_timestamp_seconds" in output
assert "k3dm_bug_open_info" not in output and "k3dm_bug_open_release_docs" not in output
assert "live_verified=" in output
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard panels have non-overlapping positions inside 24 columns" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
cells = set()
for panel in data["panels"]:
    pos = panel["gridPos"]
    assert pos["x"] + pos["w"] <= 24, panel["title"]
    for x in range(pos["x"], pos["x"] + pos["w"]):
        for y in range(pos["y"], pos["y"] + pos["h"]):
            assert (x, y) not in cells, panel["title"]
            cells.add((x, y))
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard bar charts blank the labels of empty segments" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
bars = [panel for panel in data["panels"] if panel["type"] == "barchart"]
assert len(bars) == 3
for panel in bars:
    assert panel["targets"][0]["expr"].rstrip().endswith("> 0"), panel["title"]
    matrix = next(x for x in panel["transformations"] if x["id"] == "groupingToMatrix")
    assert matrix["options"]["emptyValue"] == "null", panel["title"]
    assert not panel["fieldConfig"]["defaults"].get("mappings"), panel["title"]
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard pins one colour per priority and state, independent of data order" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
def colours(panel):
    return {o["matcher"]["options"]: o["properties"][0]["value"]["fixedColor"]
            for o in panel["fieldConfig"]["overrides"] if o["properties"][0]["id"] == "color"}
panels = {panel["id"]: panel for panel in data["panels"]}
by_priority = [panels[index] for index in (7, 25)]
by_state = [p for p in data["panels"] if p["type"] == "barchart"
            and "state)" in " ".join(t["expr"] for t in p["targets"])]
assert len(by_priority) == 2 and len(by_state) == 1
first = colours(by_priority[0])
assert set(first) == {"P0", "P1", "P2", "P3", "unset"}
assert all(colours(p) == first for p in by_priority)
assert set(colours(by_state[0])) == {"closed", "open", "unknown"}
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard stacked bars give counts in the tooltip, not on-bar labels" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
bars = [panel for panel in data["panels"] if panel["type"] == "barchart"]
assert len(bars) == 3
for panel in bars:
    assert panel["options"]["showValue"] == "never", panel["title"]
    assert panel["options"]["tooltip"]["mode"] == "multi", panel["title"]
PY
  [ "${status}" -eq 0 ]
}

_open_bugs_table_check() {
  python3 - "${dashboard}" "$1" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
table = next(panel for panel in data["panels"] if panel["type"] == "table" and panel["title"] == "Bugs")
check = sys.argv[2]
if check == "link":
    links = [prop["value"] for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"] == "Bug"
             for prop in o["properties"] if prop["id"] == "links"]
    url = links[0][0]["url"]
    assert "${__data.fields.branch}" in url and "${__data.fields.bug}" in url, url
    assert links[0][0]["targetBlank"] is True
elif check == "sort":
    transforms = [t["id"] for t in table["transformations"]]
    assert transforms.index("sortBy") < transforms.index("organize"), transforms
    sort = next(t for t in table["transformations"] if t["id"] == "sortBy")["options"]["sort"]
    assert sort == [{"field": "sort_key", "desc": False}], sort
elif check == "layout":
    assert panels[22]["type"] == "row"
    assert table["gridPos"] == {"x": 0, "y": 20, "w": 24, "h": 12}, table["gridPos"]
    assert all(panels[i]["gridPos"]["y"] + panels[i]["gridPos"]["h"] == 20 for i in (9, 10, 11, 12, 13, 14, 16, 17))
    assert panels[15]["gridPos"]["y"] == 32
    rows = sorted((p["gridPos"]["y"], p["id"]) for p in data["panels"] if p["type"] == "row")
    owner = [rid for y, rid in rows if y <= table["gridPos"]["y"]][-1]
    assert owner == 22, owner
elif check == "columns":
    organize = next(t for t in table["transformations"] if t["id"] == "organize")["options"]
    hidden = {name for name, flag in organize["excludeByName"].items() if flag}
    assert {"bug", "sort_key", "branch", "release", "__name__", "job", "instance", "Time"} <= hidden, hidden
    visible = sorted(organize["indexByName"], key=organize["indexByName"].get)
    assert [organize["renameByName"][name] for name in visible] == ["Release", "Bug", "Priority", "Filed", "Open for", "Status", "Fixed in", "Verified", "Live-verified"]
    assert organize["indexByName"]["fixed_in"] == 6
    assert organize["indexByName"]["verified"] == 7
    assert organize["indexByName"]["live_verified"] == 8
    assert organize["renameByName"]["live_verified"] == "Live-verified"
    priority = next(o for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"] == "Priority")
    mapping = next(p["value"][0]["options"] for p in priority["properties"] if p["id"] == "mappings")
    pinned = {o["matcher"]["options"]: o["properties"][0]["value"]["fixedColor"]
              for o in panels[7]["fieldConfig"]["overrides"]}
    assert {k: v["color"] for k, v in mapping.items()} == pinned, (mapping, pinned)
PY
}

@test "open bugs table links each title to its doc on the scanned branch" {
  run _open_bugs_table_check link
  [ "${status}" -eq 0 ]
}

@test "bug dashboard separates verified and live-verified summary and table" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
live = panels[24]
assert live["title"] == "Live-verified"
assert 'live_verified="true"' in live["targets"][0]["expr"]
assert panels[16]["gridPos"] == {"x": 15, "y": 16, "w": 2, "h": 4}
assert live["gridPos"] == {"x": 17, "y": 16, "w": 2, "h": 4}
assert panels[17]["gridPos"] == {"x": 19, "y": 16, "w": 2, "h": 4}
table = panels[23]
assert 'live_verified=~"$verified"' in table["targets"][0]["expr"]
PY
  [ "${status}" -eq 0 ]
}

@test "Verified column reads verified, and only Live-verified reads live" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
table = {panel["id"]: panel for panel in data["panels"]}[23]
def true_text(column):
    matches = [prop["value"][0]["options"]["true"]["text"]
               for override in table["fieldConfig"]["overrides"]
               if override["matcher"].get("options") == column
               for prop in override["properties"] if prop["id"] == "mappings"]
    assert len(matches) == 1, (column, matches)
    return matches[0]
assert true_text("Verified") == "✓ verified", true_text("Verified")
assert true_text("Live-verified") == "✓ live", true_text("Live-verified")
PY
  [ "${status}" -eq 0 ]
}

@test "open bugs table sorts by sort_key before hiding it" {
  run _open_bugs_table_check sort
  [ "${status}" -eq 0 ]
}

@test "open bugs table sits in row 22 under the stats, with the time series moved below" {
  run _open_bugs_table_check layout
  [ "${status}" -eq 0 ]
}

@test "bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified, Live-verified" {
  run _open_bugs_table_check columns
  [ "${status}" -eq 0 ]
}

@test "open bugs table shows age in days, not a duration that rolls up to weeks" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
table = next(p for p in data["panels"] if p["type"] == "table" and p["title"] == "Bugs")
age = next(o for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"] == "Open for")
unit = next(p["value"] for p in age["properties"] if p["id"] == "unit")
assert unit == "suffix: d", unit
PY
  [ "${status}" -eq 0 ]
}
