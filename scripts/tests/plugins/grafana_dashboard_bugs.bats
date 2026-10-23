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

@test "release forecast panels align by version and map dates and states" {
  run python3 - "${dashboard}" <<'PY'
import json, re, sys
d=json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n",1)[1])
panels=d["panels"]
new=[p for p in panels if 26 <= p["id"] <= 32]
tiles={p["id"]:p for p in new}
table=tiles[32]
assert len(new)==7
names=[p.get("title","") for p in new]
names += list(next(t for t in table["transformations"] if t["id"]=="organize")["options"].get("renameByName",{}).values())
assert all(not re.search(r"ship|release date", name, re.I) for name in names)
assert all(tiles[i]["fieldConfig"]["defaults"].get("noValue") for i in (28,29,30,31))
for field in ("Value #B","Value #C","Value #D"):
 override=next(o for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"]==field)
 assert {p["id"]:p["value"] for p in override["properties"]}.get("noValue")=="-"
 assert "custom.noValue" not in {p["id"] for p in override["properties"]}
exprs={t["refId"]:t["expr"] for t in table["targets"]}
assert all(f"by (version)" in exprs[k] for k in "BCDE")
assert all(re.fullmatch(r"version", label) for label in re.findall(r"(?:sum|max) by \(([^)]+)\)", " ".join(exprs[k] for k in "BCDE")))
assert "sum by (release)" not in exprs["E"]
assert all(f'bound="{bound}"' in exprs[ref] for ref,bound in zip("BCD",("low","mid","high")))
assert [t["id"] for t in table["transformations"]]==["merge","convertFieldType","organize"]
assert table["transformations"][-1]["options"]["excludeByName"].get("Value #A") is True
conversion=table["transformations"][1]["options"]["conversions"]
assert any(c["targetField"]=="position" and c["destinationType"]=="number" for c in conversion)
state_expr=tiles[31]["targets"][0]["expr"]
assert all(f"({code} * k3dm_release_milestone_info" in state_expr for code in range(1,5))
mapping=tiles[31]["fieldConfig"]["defaults"]["mappings"]
assert set(mapping[0]["options"])=={"1","2","3","4"}
assert {k:v["text"] for k,v in mapping[0]["options"].items()}=={"1":"blocked upstream","2":"insufficient history","3":"forecast","4":"shipped"}
for panel in new:
 a=panel["gridPos"]
 for other in panels:
  if other["id"]==panel["id"]: continue
  b=other["gridPos"]
  assert a["x"]+a["w"]<=b["x"] or b["x"]+b["w"]<=a["x"] or a["y"]+a["h"]<=b["y"] or b["y"]+b["h"]<=a["y"]
PY
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
assert variable["current"]["value"] == ".*"
assert variable["current"]["text"] == "Show all"
assert variable["query"] == "Hide live-verified : ^(false|-)?$,Show all : .*"
PY
  [ "${status}" -eq 0 ]
}

@test "bug dashboard opens on the release branch's version" {
  branch="${GITHUB_HEAD_REF:-$(git -C "${BATS_TEST_DIRNAME}" branch --show-current)}"
  if [[ ! "${branch}" =~ ^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    skip "branch ${branch} is not a release branch"
  fi
  run env EXPECTED_BRANCH="${branch}" python3 - "${dashboard}" <<'PY'
import json, os, re, sys
path = sys.argv[1]
branch = os.environ["EXPECTED_BRANCH"]
data = json.loads(open(path).read().split("  k3dm-bugs.json: |\n", 1)[1])
variable = next(v for v in data["templating"]["list"] if v["name"] == "release")
assert variable["includeAll"] is True and variable["allValue"] == ".*"
match = re.fullmatch(r"k3d-manager-v([0-9]+\.[0-9]+\.[0-9]+)", branch)
assert match, branch
expected = f"v{match.group(1)}"
assert variable["current"]["value"] == [expected]
assert variable["current"]["text"] == [expected]
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
    {"x": 0, "y": 20, "w": 8, "h": 9},
    {"x": 8, "y": 20, "w": 8, "h": 9},
    {"x": 16, "y": 20, "w": 8, "h": 9},
]
organize = next(t for t in panels[23]["transformations"] if t["id"] == "organize")["options"]
assert organize["indexByName"]["fixed_in"] == 6
assert organize["renameByName"]["fixed_in"] == "Fixed in"
assert [organize["indexByName"][k] for k in ("fix_sha", "verified_sha", "verified", "verified_at", "live_verified", "live_verified_at")] == [7, 8, 9, 10, 11, 12]
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

@test "bug dashboard release plans row shows joined plan state without not-started inference" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
d=json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n",1)[1])
panels=d['panels']; row=next(p for p in panels if p['title']=='Release plans — $release')
added=[p for p in panels if p['id'] >= 100]
assert sorted(p['gridPos']['y'] for p in added) == [5, 6, 6, 6, 6, 6, 6, 10]
assert next(p for p in panels if p['id'] == 21)['gridPos']['y'] == 19
table=next(p for p in added if p['title']=='Plans')
expr=table['targets'][0]['expr']
assert 'group_left(dispatch_state, slug)' in expr and ' or on(plan) ' in expr
tiles={p['title']:p for p in added if p['type']=='stat'}
steps=tiles['Plans in release']['fieldConfig']['defaults']['thresholds']['steps']
assert any(s.get('value')==6 and s['color']=='red' for s in steps)
assert not any('not started' in (p['title']+' '+str(p.get('fieldConfig',{}).get('defaults',{}).get('mappings',[]))).lower() for p in added)
assert 'no record' in json.dumps(table).lower()
assert 'label_replace(' in expr and '"dispatch_state", "none"' in expr
assert table['fieldConfig']['overrides'] and any('none' in str(o.get('properties')) and 'no record' in str(o.get('properties')) for o in table['fieldConfig']['overrides'])
exprs=[t['expr'] for p in added for t in p.get('targets',[])]
assert exprs and all('release=~"$release"' in e and 'release_order=~' not in e for e in exprs)
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
    # Model the post-organize frame: excludeByName removes columns, while
    # hideFrom.viz keeps metadata available to data-link interpolation.
    organize = next(t for t in table["transformations"] if t["id"] == "organize")["options"]
    assert not organize["excludeByName"].get("branch") and not organize["excludeByName"].get("bug")
    hidden = {}
    for override in table["fieldConfig"]["overrides"]:
        for prop in override["properties"]:
            if prop["id"] == "hideFrom":
                hidden[override["matcher"]["options"]] = prop["value"]
    assert hidden["bug"]["viz"] and hidden["branch"]["viz"]
    rows = [
        {"branch": "release/v1.43.5", "bug": "2026-10-18-register-app-cluster-role-lookup-exits-silently", "title": "App cluster role lookup"},
        {"branch": "feature/dashboard-fix", "bug": "2026-10-19-grafana-bug-dashboard-links-empty-branch-and-stem", "title": "Dashboard links"},
    ]
    def render_link(row, excluded):
        post_transform = {key: value for key, value in row.items() if key not in excluded}
        resolved = url.replace("${__data.fields.branch}", post_transform.get("branch", ""))
        resolved = resolved.replace("${__data.fields.bug}", post_transform.get("bug", ""))
        return resolved

    for row in rows:
        resolved = render_link(row, organize["excludeByName"])
        assert "/blob//" not in resolved and "/docs/bugs/.md" not in resolved, resolved
        assert f"/blob/{row['branch']}/docs/bugs/{row['bug']}.md" in resolved, resolved
    # Run the same post-transform resolver against the original exclusion
    # configuration. It must reproduce the empty-ref/stem URL from the bug.
    original_exclusions = {**organize["excludeByName"], "branch": True, "bug": True}
    original_result = render_link(rows[0], original_exclusions)
    assert "/blob//" in original_result and "/docs/bugs/.md" in original_result, original_result
elif check == "sort":
    transforms = [t["id"] for t in table["transformations"]]
    assert transforms.index("sortBy") < transforms.index("organize"), transforms
    sort = next(t for t in table["transformations"] if t["id"] == "sortBy")["options"]["sort"]
    assert sort == [{"field": "sort_key", "desc": False}], sort
elif check == "layout":
    assert panels[22]["type"] == "row"
    assert table["gridPos"] == {"x": 0, "y": 34, "w": 24, "h": 12}, table["gridPos"]
    assert all(panels[i]["gridPos"]["y"] + panels[i]["gridPos"]["h"] == 34 for i in (9, 10, 11, 12, 13, 14, 16, 17))
    assert panels[15]["gridPos"]["y"] == 46
    rows = sorted((p["gridPos"]["y"], p["id"]) for p in data["panels"] if p["type"] == "row")
    owner = [rid for y, rid in rows if y <= table["gridPos"]["y"]][-1]
    assert owner == 22, owner
elif check == "columns":
    organize = next(t for t in table["transformations"] if t["id"] == "organize")["options"]
    hidden = {name for name, flag in organize["excludeByName"].items() if flag}
    assert {"sort_key", "release", "__name__", "job", "instance", "Time", "repo"} <= hidden, hidden
    assert not {"bug", "branch"} & hidden
    visible = sorted(organize["indexByName"], key=organize["indexByName"].get)
    assert [organize["renameByName"][name] for name in visible] == ["Release", "Bug", "Priority", "Filed", "Open for", "Status", "Fixed in", "Fix commit", "Verified commit", "Verified", "Verified at", "Live-verified", "Live-verified at", "Live evidence"]
    assert organize["indexByName"]["fixed_in"] == 6
    assert organize["indexByName"]["fix_sha"] == 7
    assert organize["indexByName"]["verified_sha"] == 8
    assert organize["indexByName"]["verified"] == 9
    assert organize["indexByName"]["verified_at"] == 10
    assert organize["indexByName"]["live_verified"] == 11
    assert organize["indexByName"]["live_verified_at"] == 12
    assert organize["renameByName"]["live_verified_at"] == "Live-verified at"
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
assert panels[13]["gridPos"] == {"x": 8, "y": 30, "w": 3, "h": 4}
assert panels[16]["gridPos"] == {"x": 11, "y": 30, "w": 3, "h": 4}
assert live["gridPos"] == {"x": 14, "y": 30, "w": 4, "h": 4}
assert panels[17]["gridPos"] == {"x": 18, "y": 30, "w": 3, "h": 4}
assert panels[14]["gridPos"] == {"x": 21, "y": 30, "w": 3, "h": 4}
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

@test "bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)" {
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

@test "bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  k3dm-bugs.json: |\n", 1)[1])
table = next(p for p in data["panels"] if p["type"] == "table" and p["title"] == "Bugs")
for column in ("Fixed in", "Fix commit", "Verified commit", "Verified", "Live-verified"):
    override = next(o for o in table["fieldConfig"]["overrides"] if o["matcher"]["options"] == column)
    mappings = next(p["value"] for p in override["properties"] if p["id"] == "mappings")
    values = next(m["options"] for m in mappings if m["type"] == "value")
    assert values["-"]["text"] == "—", column
PY
  [ "${status}" -eq 0 ]
}

@test "bugs table pairs each verification column with its timestamp" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read().split("  k3dm-bugs.json: |\n", 1)[1])
table = next(p for p in data["panels"] if p["type"] == "table" and p["title"] == "Bugs")
organize = next(t for t in table["transformations"] if t["id"] == "organize")["options"]
order = sorted(organize["indexByName"], key=organize["indexByName"].get)
assert order[-7:-1] == ["fix_sha", "verified_sha", "verified", "verified_at", "live_verified", "live_verified_at"], order
assert organize["renameByName"]["verified"] == "Verified"
assert organize["renameByName"]["fix_sha"] == "Fix commit"
assert organize["renameByName"]["verified_sha"] == "Verified commit"
assert organize["renameByName"]["verified_at"] == "Verified at"
assert organize["renameByName"]["live_verified"] == "Live-verified"
assert organize["renameByName"]["live_verified_at"] == "Live-verified at"
for label in ("fix_sha", "verified_sha", "verified", "verified_at", "live_verified", "live_verified_at"):
    assert not organize["excludeByName"].get(label), label
overrides = {o["matcher"].get("options"): o for o in table["fieldConfig"]["overrides"]}
for column in ("Fix commit", "Verified commit", "Verified at", "Live-verified at"):
    values = next(m["options"] for p in overrides[column]["properties"] if p["id"] == "mappings"
                  for m in p["value"] if m["type"] == "value")
    assert values["-"]["text"] == "—", column
    if column.endswith("at"):
        assert {values[k]["text"] for k in ("false", "n/a")} == {"—"}, column
        assert values["true"]["text"] == "unknown", column
for column in ("Verified", "Live-verified"):
    mappings = next(p["value"] for p in overrides[column]["properties"] if p["id"] == "mappings")
    assert not any(m["type"] == "regex" for m in mappings), column
PY
  [ "${status}" -eq 0 ]
}
