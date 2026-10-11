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
module = runpy.run_path(metrics_path)
with tempfile.TemporaryDirectory() as tmp:
    bugs = Path(tmp) / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "one.md").write_text("**Priority:** P1\n**Status:** Open\n")
    output = module["_bug_metrics"](Path(tmp))
source = Path(metrics_path).read_text()
assert {"k3dm_bug_docs", "k3dm_bug_release_docs", "k3dm_bug_current_release_info", "k3dm_bug_later_release_open_docs"} <= queries
missing = [name for name in queries if name + "{" not in output and name + " " not in output and name + "{{" not in source]
assert not missing, missing
assert "k3dm_bug_docs_scan_timestamp_seconds" in output
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
assert len(bars) == 2
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
by_priority = [p for p in data["panels"] if p["type"] in ("barchart", "timeseries")
               and "priority)" in " ".join(t["expr"] for t in p["targets"])]
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
