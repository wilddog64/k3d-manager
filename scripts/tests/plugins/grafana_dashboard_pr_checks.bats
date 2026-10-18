#!/usr/bin/env bats

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
    assert any(item["id"] == "merge" for item in panels[panel_id]["transformations"])
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
