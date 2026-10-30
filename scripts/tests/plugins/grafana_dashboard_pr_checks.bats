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

assert [item["id"] for item in panels[5]["transformations"]] == ["joinByField", "sortBy", "organize"]
assert [item["id"] for item in panels[6]["transformations"]] == ["joinByField", "sortBy", "organize"]
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

@test "PR checks per PR sorts on the repo:pr:check join key before organize and keeps the intended columns" {
  run python3 - "${PR_CHECKS_DASHBOARD:-${dashboard}}" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panel = next(panel for panel in data["panels"] if panel["id"] == 6)
transformations = panel["transformations"]
assert [item["id"] for item in transformations] == ["joinByField", "sortBy", "organize"]
sort = transformations[1]
assert sort["options"]["sort"] == [{"field": "__join", "desc": False}]
organize = transformations[2]["options"]
index = organize["indexByName"]
assert set(index) <= set(organize["renameByName"]), sorted(set(index) - set(organize["renameByName"]))
assert [organize["renameByName"][name] for name in sorted(index, key=index.get)] == ["Repo", "PR", "Check", "Duration", "State"]
PY
  [ "${status}" -eq 0 ]
}

@test "PR checks dashboard does not put sorting inside organize options" {
  run python3 - "${PR_CHECKS_DASHBOARD:-${dashboard}}" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
for panel in data["panels"]:
    for transformation in panel.get("transformations", []):
        if transformation["id"] == "organize":
            assert "sortBy" not in transformation["options"], panel["id"]
PY
  [ "${status}" -eq 0 ]
}

@test "PR check duration legend uses a readable side layout without changing its query" {
  run python3 - "${dashboard}" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panel = next(panel for panel in data["panels"] if panel["id"] == 8)
assert panel["title"] == "Historical sampled check durations (may include closed PRs)"
assert "Prometheus sample time" in panel["description"]
assert "completed_at" in panel["description"]
assert "until Prometheus retention expires" in panel["description"]
assert "No samples in the selected range" in panel["description"]
assert "GitHub read and Last scrape" in panel["description"]
assert panel["options"]["legend"] == {
    "showLegend": True,
    "displayMode": "list",
    "placement": "right",
    "calcs": [],
}
assert panel["targets"][0]["expr"] == 'k3dm_pr_check_duration_seconds{repo=~"$repo"}'
assert panel["targets"][0]["legendFormat"] == "{{repo}}#{{pr}} {{check}}"
table = next(panel for panel in data["panels"] if panel["id"] == 6)
assert all(target.get("instant") is True for target in table["targets"])
PY
  [ "${status}" -eq 0 ]
}


@test "PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads" {
  run python3 - "${dashboard}" <<'PY_PRESENTATION'
import json, sys
from pathlib import Path

panels = {panel["id"]: panel for panel in json.loads(
    Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1]
)["panels"]}
assert "may include closed PRs" in panels[8]["title"]
assert "Closed or merged PRs disappear" in panels[5]["description"]
assert "No open PRs means there are no current rows" in panels[6]["description"]
assert "failed or stale read" in panels[6]["description"]
assert "latest GitHub read succeeded" in panels[7]["description"]
assert "Last scrape" in panels[7]["description"]
PY_PRESENTATION
  echo "$output"; [ "${status}" -eq 0 ]

  if ! command -v promtool >/dev/null 2>&1; then skip "promtool not installed"; fi
  test_file="${BATS_TEST_TMPDIR}/pr-checks-history.test.json"
  run python3 - "${dashboard}" "${test_file}" <<'PY_PROMQL'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text().split("  pr-checks.json: |\n", 1)[1])
panels = {panel["id"]: panel for panel in data["panels"]}
all_repos = data["templating"]["list"][0]["allValue"]
opened = "wilddog64/lib-foundation"
closed = "wilddog64/shopping-cart-payment"
empty = "wilddog64/shopping-cart-e2e-tests"
failed = "wilddog64/shopping-cart-frontend"
stale = "wilddog64/shopping-cart-basket"
inputs, checks = [], []


def labels(metric="", **values):
    return metric + "{" + ",".join(f"{key}={json.dumps(value)}" for key, value in values.items()) + "}"


def query(panel_id, repo, target=0):
    return panels[panel_id]["targets"][target]["expr"].replace("$repo", repo)


def check(expr, expected, at="5m"):
    checks.append({"expr": expr, "eval_time": at, "exp_samples": [
        {"labels": name, "value": value} for name, value in expected
    ]})


# Closure removes the instant duration series at minute 2. Failed reads leave
# last-known check data; the separate success/age metrics expose its freshness.
for repo, pr, duration, values in (
    (opened, "66", 45, "45+0x40"),
    (closed, "93", 51, "51 51 stale"),
    (failed, "133", 25, "25+0x40"),
):
    inputs.append({"series": labels("k3dm_pr_check_duration_seconds", repo=repo, pr=pr, check="lint"),
                   "values": values})
    check(query(8, repo), [] if repo == closed else [(
        labels("k3dm_pr_check_duration_seconds", repo=repo, pr=pr, check="lint"), duration,
    )])
    # This range selector evaluates the actual unchanged panel8 selector over
    # retained scrape samples, including those preceding the stale marker.
    check(f"count_over_time({query(8, repo)}[10m])", [(
        labels(repo=repo, pr=pr, check="lint"), 2 if repo == closed else 6,
    )])

check(query(8, closed), [(
    labels("k3dm_pr_check_duration_seconds", repo=closed, pr="93", check="lint"), 51,
)], at="1m")
check(query(6, closed, target=1), [])
check(query(6, opened, target=1), [(
    labels(__join=f"{opened}:66:lint"), 45,
)])
check(query(8, all_repos), [
    (labels("k3dm_pr_check_duration_seconds", repo=opened, pr="66", check="lint"), 45),
    (labels("k3dm_pr_check_duration_seconds", repo=failed, pr="133", check="lint"), 25),
])
check(f"count_over_time({query(8, all_repos)}[10m])", [
    (labels(repo=opened, pr="66", check="lint"), 6),
    (labels(repo=closed, pr="93", check="lint"), 2),
    (labels(repo=failed, pr="133", check="lint"), 6),
])
check(query(8, empty), [])
check(f"count_over_time({query(8, empty)}[10m])", [])

for repo, count, success, timestamp in (
    (opened, "1+0x40", "1+0x40", "0+60x40"),
    (closed, "1 1 0+0x38", "1+0x40", "0+60x40"),
    (empty, "0+0x40", "1+0x40", "0+60x40"),
    (failed, "1+0x40", "1 0+0x39", "0 60+0x39"),
    (stale, "0+0x40", "1+0x40", "0 60+0x39"),
):
    for metric, values in (
        ("k3dm_pr_checks_open_prs", count),
        ("k3dm_pr_checks_scrape_success", success),
        ("k3dm_pr_checks_last_scrape_timestamp_seconds", timestamp),
    ):
        inputs.append({"series": labels(metric, repo=repo), "values": values})
    check(query(1, repo), [("{}", 0 if repo in (closed, empty, stale) else 1)])
    check(query(7, repo), [("{}", 0 if repo == failed else 1)])
    check(query(4, repo), [("{}", 240 if repo in (failed, stale) else 0)])

# Read success and age remain independent: stale last-known data cannot be
# mistaken for a fresh successful read, even when the duration still exists.
check(query(7, failed), [("{}", 0)], at="40m")
check(query(4, failed), [("{}", 2340)], at="40m")
check(query(7, stale), [("{}", 1)], at="40m")
check(query(4, stale), [("{}", 2340)], at="40m")
check(query(7, all_repos), [("{}", 0)])
Path(sys.argv[2]).write_text(json.dumps({
    "rule_files": [], "evaluation_interval": "1m",
    "tests": [{"interval": "1m", "input_series": inputs, "promql_expr_test": checks}],
}))
PY_PROMQL
  echo "$output"; [ "${status}" -eq 0 ]
  run promtool test rules "${test_file}"
  echo "$output"; [ "${status}" -eq 0 ]
}
