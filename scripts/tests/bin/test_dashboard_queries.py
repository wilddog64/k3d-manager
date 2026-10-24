"""Evaluate Bug Tracking panels against offline output from their real producers."""

import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[3]
DASHBOARD = Path(os.environ.get(
    "BUG_DASHBOARD_PATH", ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml"))
GUIDE = ROOT / "docs/guides/grafana-dashboards.md"
PROMETHEUS_IMAGE = "prom/prometheus:v3.1.0"


def load_module(name, path):
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_dashboard():
    raw = DASHBOARD.read_text().split("  k3dm-bugs.json: |\n", 1)[1]
    return json.loads("\n".join(line[4:] for line in raw.splitlines()))


def fixture_metrics(tmp_path):
    """Run the real offline producers on a tagged fixture repo, docs, and ledger."""
    producer = load_module("vectordb_metrics_dashboard_test", ROOT / "bin/k3dm-vectordb-metrics")
    dispatch = load_module("dispatch_metrics_dashboard_test", ROOT / "bin/k3dm-dispatch-metrics")
    repo = tmp_path / "repo"
    docs = repo / "docs"
    (docs / "bugs").mkdir(parents=True)
    (docs / "plans").mkdir()
    (docs / "release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.43.4"}, {"version": "v1.43.5", "target": True},
    ]}))
    bug_path = "docs/bugs/2026-10-23-fixture.md"
    bug_text = ("# Bug: fixture\n**Filed:** 2026-10-23\n**Status:** LIVE-VERIFIED\n"
                "**Priority:** P2\n**Release:** v1.43.5\n")
    (repo / bug_path).write_text(bug_text)
    plans = {
        "v1.43.5-fixture-dispatched": "DISPATCHED",
        "v1.43.5-fixture-undispatched": "PROPOSED",
    }
    texts = {}
    for name, status in plans.items():
        path = f"docs/plans/{name}.md"
        texts[path] = (f"# {name}\n**Status:** {status}\n**Approval:** explicit\n"
                       "**Release:** v1.43.5 (plan 1 of 2)\n**Depends on:** none\n")
    bug_texts = {bug_path: bug_text}
    metric_text = (producer._plan_metrics(repo, texts=texts)
                   + producer._bug_metrics(repo, texts=bug_texts)
                   + producer._bug_status_metrics(repo, texts=bug_texts, tally={
                       "v1.43.5": {"closed_paths": [{"path": bug_path}]}
                   }))

    # Release and forecast producers intentionally read Git tags/current branch
    # and release-milestones.json. Keep that state wholly inside tmp_path.
    subprocess.run(["git", "init", str(repo)], check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Dashboard fixture"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "fixture@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "branch", "-m", "k3d-manager-v1.43.5"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "docs"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-m", "fixture"], check=True,
                   capture_output=True, text=True)
    versions = ["v1.42.0", "v1.42.1", "v1.42.2", "v1.42.3", "v1.42.4",
                "v1.43.0", "v1.43.1"]
    for index, version in enumerate(versions):
        stamp = f"2026-01-{index + 1:02d}T00:00:00Z"
        tag_env = os.environ.copy()
        tag_env.update({"GIT_COMMITTER_DATE": stamp, "GIT_AUTHOR_DATE": stamp})
        subprocess.run(["git", "-C", str(repo), "tag", "-a", version, "-m", "fixture release"],
                       check=True, env=tag_env, capture_output=True, text=True)
    release_tally = {
        "v1.43.5": {
            "by_priority": {"P2": {"open": 0, "closed": 1, "unknown": 0}},
            "closed_paths": [{"path": bug_path, "priority": "P2"}],
        }
    }
    metric_text += producer._release_metrics(repo, tally=release_tally,
                                          fixed_in={bug_path: {"release": "v1.43.5"}})
    metric_text += producer._forecast_metrics(repo, now=1_800_000_000)

    events = [{"ts": 1_800_000_000, "event": "start", "version": "v1.43.5",
               "slug": "fixture-dispatched", "spec": "docs/plans/v1.43.5-fixture-dispatched.md"}]
    metric_text += dispatch.render(events, 0, now=1_800_000_000)
    return metric_text, set(texts)


def parse_series(exposition):
    result = []
    for line in exposition.splitlines():
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r'([a-zA-Z_:][a-zA-Z0-9_:]*)(\{.*\})?\s+([-+0-9.eE]+)', line)
        if match:
            result.append((match.group(1), match.group(2) or "", match.group(3)))
    return result


def label_names(series):
    names = set()
    for _, labels, _ in series:
        names.update(re.findall(r'(?:^|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)="', labels.strip("{}")))
    return names


def substitute_variables(expr, dashboard, series):
    variables = {item["name"]: item for item in dashboard["templating"]["list"]}
    expr = expr.replace("$repo", variables["repo"]["current"]["value"])
    expr = expr.replace("$verified", variables["verified"]["current"]["value"])
    release_var = variables["release"]
    label_values = []
    for _, labels, _ in series:
        if 'repo="k3d-manager"' not in labels:
            continue
        found = re.search(r'(?:^|,)release_order="([^"]+)"', labels.strip("{}"))
        if found:
            label_values.append(found.group(1))
    grafana_regex = release_var["regex"].strip("/")
    grafana_regex = grafana_regex.replace("(?<value>", "(?P<value>")
    selected = [re.search(grafana_regex, value).group("value") for value in label_values
                if re.search(grafana_regex, value)]
    chosen = release_var["current"]["value"]
    if chosen == [".*"] or chosen == ".*":
        chosen = [".*"]
    else:
        chosen = [value for value in chosen if value in selected]
    assert chosen, "release variable regex did not select producer release_order values"
    expr = expr.replace("$release", "|".join(chosen))
    return expr


def promtool_command(tmp_path):
    local = shutil.which("promtool")
    if local:
        return [local, "test", "rules", "tests.yml"]
    docker = shutil.which("docker")
    if docker:
        return [docker, "run", "--rm", "-v", f"{tmp_path}:/work", "-w", "/work",
                "--entrypoint=promtool", PROMETHEUS_IMAGE, "test", "rules", "tests.yml"]
    pytest.skip("SKIP: neither local promtool nor Docker is available; real PromQL evaluation unavailable")


@pytest.mark.external
def test_every_bug_dashboard_target_matches_producer_series(tmp_path):
    dashboard = load_dashboard()
    exposition, plan_names = fixture_metrics(tmp_path)
    series = parse_series(exposition)
    panels = [panel for panel in dashboard["panels"] if panel.get("targets")]
    expressions = []
    for panel in panels:
        for target in panel["targets"]:
            expression = substitute_variables(target["expr"], dashboard, series)
            expressions.append((panel, target, expression))

    rules = ["groups:", "- name: dashboard-query-tests", "  rules:"]
    tests = ["rule_files:", "- rules.yml", "evaluation_interval: 1m", "tests:",
             "- interval: 1m", "  input_series:"]
    for metric, labels, value in series:
        tests.extend([f"  - series: '{metric}{labels}'", f"    values: '{value}'"])
    expected_alerts = []
    for index, (panel, target, expression) in enumerate(expressions):
        record = f"dashboard_query_{index}"
        alert = f"DashboardQueryHasSeries{index}"
        rules.extend([f"  - record: {record}", f"    expr: {json.dumps(expression)}",
                      f"  - alert: {alert}",
                      f"    expr: count({record}) == {len(plan_names)}"
                      if panel.get("title") == "Plans" else f"    expr: count({record}) > 0"])
        tests.extend(["  alert_rule_test:", "  - eval_time: 0m", f"    alertname: {alert}",
                      "    exp_alerts:", f"    - exp_labels: {{alertname: {alert}}}"])
        if panel.get("title") == "Plans":
            missing_dispatch = f"DashboardUndispatchedPlan{index}"
            rules.extend([f"  - alert: {missing_dispatch}",
                          f"    expr: count({record}{{dispatch_state=\"none\"}}) == 1"])
            tests.extend(["  - eval_time: 0m", f"    alertname: {missing_dispatch}",
                          "    exp_alerts:",
                          f"    - exp_labels: {{alertname: {missing_dispatch}}}"])
        expected_alerts.append((panel, target))
    # Prometheus rule tests allow one alert_rule_test field per test case. Fold
    # individual entries into a single list under the input-series test.
    alert_start = tests.index("  alert_rule_test:")
    alert_lines = []
    for line in tests[alert_start:]:
        if line == "  alert_rule_test:":
            continue
        if line.startswith("  - interval"):
            continue
        alert_lines.append(line)
    tests = tests[:alert_start] + ["  alert_rule_test:"] + alert_lines
    (tmp_path / "rules.yml").write_text("\n".join(rules) + "\n")
    (tmp_path / "tests.yml").write_text("\n".join(tests) + "\n")
    command = promtool_command(tmp_path)
    result = subprocess.run(command, cwd=tmp_path, text=True, capture_output=True)
    if result.returncode and "permission denied" in result.stderr.lower() and "docker" in command[0]:
        pytest.skip("SKIP: Docker is installed but its daemon is unavailable to this user; "
                    "real PromQL evaluation did not run")
    assert result.returncode == 0, result.stdout + result.stderr

    table_panels = [panel for panel in dashboard["panels"] if panel.get("type") == "table"]
    available_labels = label_names(series)
    for table in table_panels:
        organize = next((item for item in table.get("transformations", [])
                         if item["id"] == "organize"), None)
        if organize:
            columns = {name for name in organize["options"].get("indexByName", {})
                       if not re.fullmatch(r"(Time|Value)( #[A-Z]+)?", name)}
            assert columns <= available_labels, (
                f"{table['title']} table columns absent from producer series: "
                f"{columns - available_labels}"
            )

    plan_panel = next(panel for panel in dashboard["panels"] if panel.get("title") == "Plans")
    plan_rows = [item for item in expressions if item[0] is plan_panel]
    assert len(plan_rows) == 1
    assert len(plan_names) == 2
    assert "dispatch_state" in plan_rows[0][2]
    assert "release=~\"$release\"" in GUIDE.read_text(), (
        "See docs/guides/grafana-dashboards.md: Bug Tracking panels must filter release; "
        "release_order is only for sorting."
    )
