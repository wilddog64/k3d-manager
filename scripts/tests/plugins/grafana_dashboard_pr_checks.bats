#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  dashboard="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml"
}

@test "PR checks dashboard YAML and embedded JSON are valid" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
assert raw.startswith("apiVersion: v1\n")
payload = raw.split("  pr-checks.json: |\n", 1)[1]
data = json.loads(payload)
assert data["uid"] == "k3dm-pr-checks"
assert "grafana_dashboard: \"1\"" in raw
PY
  [ "${status}" -eq 0 ]
}

@test "PR checks dashboard has filtered panels and repo variable" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
assert set(panels) == set(range(1, 9))
assert 'state="failure"' in panels[2]["targets"][0]["expr"]
assert 'state="running"' in panels[3]["targets"][0]["expr"]
for panel in panels.values():
    assert all('repo=~"$repo"' in target["expr"] for target in panel.get("targets", []))
repo = next(item for item in data["templating"]["list"] if item["name"] == "repo")
assert repo["includeAll"] and repo["multi"]
for panel_id in (5, 6):
    assert any(item["id"] == "joinByField" for item in panels[panel_id]["transformations"])
    assert "Repo" in next(item for item in panels[panel_id]["transformations"] if item["id"] == "organize")["options"]["renameByName"].values()
state = panels[6]["fieldConfig"]["defaults"]["mappings"][0]["options"]
assert state["failure"]["color"] == "red" and state["in_progress"]["color"] == "blue"
PY
  [ "${status}" -eq 0 ]
}

@test "PR checks tables say No open PRs instead of No data when nothing is open" {
  run python3 - "${PR_CHECKS_DASHBOARD:-${dashboard}}" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
for panel_id in (5, 6):
    assert panels[panel_id]["type"] == "table"
    assert "No open PRs" in panels[panel_id]["fieldConfig"]["defaults"].get("noValue", ""), panel_id
for panel_id in (1, 2, 3):
    assert panels[panel_id]["targets"][0]["expr"].endswith("or vector(0)"), panel_id
PY
  [ "${status}" -eq 0 ]
}

@test "PR checks tables join populated rows without duplicate label fields" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}

def organize(panel_id):
    return next(item for item in panels[panel_id]["transformations"] if item["id"] == "organize")["options"]

assert [item["id"] for item in panels[5]["transformations"]] == ["joinByField", "organize"]
assert [item["id"] for item in panels[6]["transformations"]] == ["joinByField", "organize"]
for panel_id in (5, 6):
    join = panels[panel_id]["transformations"][0]
    assert join["options"] == {"byField": "__join", "mode": "outer"}
    assert "max by" not in panels[panel_id]["targets"][0]["expr"]
    assert "label_join" in panels[panel_id]["targets"][0]["expr"]
    exclude = organize(panel_id)["excludeByName"]
    assert all(exclude.get(name) for name in ("Time", "Value", "Value #A", "__name__", "__join", "job", "instance"))

assert panels[5]["targets"][1]["expr"].startswith("max by (__join, state) (")
assert panels[6]["targets"][1]["expr"].startswith("max by (__join) (")
assert "repo\",\"pr\"))" in panels[5]["targets"][1]["expr"]
assert "repo\",\"pr\",\"check\"))" in panels[6]["targets"][1]["expr"]
assert organize(5)["excludeByName"]["Value #B"]
assert "Value #B" not in organize(6)["excludeByName"]
assert organize(6)["renameByName"]["Value #B"] == "Duration"
assert "state)" in panels[5]["targets"][1]["expr"]
assert "check" in panels[6]["targets"][0]["expr"]

# Seconds formatting belongs only to the transformed duration field. Applying
# it as a panel default also renders the numeric PR identifier as elapsed time.
defaults = panels[6]["fieldConfig"]["defaults"]
assert "unit" not in defaults
duration_override = next(
    override for override in panels[6]["fieldConfig"]["overrides"]
    if override["matcher"] == {"id": "byName", "options": "Duration"}
)
assert {prop["id"]: prop["value"] for prop in duration_override["properties"]}["unit"] == "s"
PY
  [ "${status}" -eq 0 ]
}

@test "PR check duration legend uses a readable side layout without changing its query" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panel = next(panel for panel in data["panels"] if panel["id"] == 8)
assert panel["options"]["legend"] == {
    "showLegend": True,
    "displayMode": "list",
    "placement": "right",
    "calcs": [],
}
assert panel["targets"][0]["expr"] == 'k3dm_pr_check_duration_seconds{repo=~"$repo"}'
assert panel["targets"][0]["legendFormat"] == "{{repo}}#{{pr}} {{check}}"
PY
  [ "${status}" -eq 0 ]
}
