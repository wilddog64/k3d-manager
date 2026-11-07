import os
import json
import re
import runpy
import subprocess
import shutil
import sys
from datetime import datetime, timezone
from types import SimpleNamespace
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))


@pytest.fixture
def metrics(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_LIB_FOUNDATION_DIR", str(tmp_path / "missing-lib-foundation"))
    module = Path(os.environ.get("METRICS_MODULE", ROOT / "bin/k3dm-vectordb-metrics"))
    return SimpleNamespace(**runpy.run_path(module))


def _repo(tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "p1-open.md").write_text("# open\n\n**Priority:** P1\n**Status:** Open\n")
    (bugs / "p0-fixed.md").write_text("# fixed\n\n**Priority:** P0\n**Status:** FIXED\n")
    (bugs / "unset.md").write_text("# unknown\n\nno status\n")
    (bugs / "archive").mkdir()
    (bugs / "archive/ignored.md").write_text("**Priority:** P0\n**Status:** Open\n")
    (tmp_path / "docs/issues").mkdir(parents=True)
    (tmp_path / "docs/issues/ignored.md").write_text("**Priority:** P0\n**Status:** Open\n")
    return tmp_path


def test_bug_metrics_waiting_on_labels_are_safe_and_status_gated(metrics, tmp_path):
    root = tmp_path / "fixture-repo"
    (root / "docs/bugs").mkdir(parents=True)
    assert root.name == "fixture-repo" and not (root / "docs/bugs").resolve() == (ROOT / "docs/bugs").resolve()
    texts = {
        "docs/bugs/2026-11-01-open.md": "# open\n**Priority:** P2\n**Filed:** 2026-11-01\n**Status:** OPEN — fix landed\n**Waiting on:** live check — since 2026-11-06\n",
        "docs/bugs/2026-11-01-unknown.md": "# unknown\n**Priority:** P2\n**Filed:** 2026-11-01\n**Waiting on:** scheduled run\n",
        "docs/bugs/2026-11-01-closed.md": "# closed\n**Priority:** P2\n**Filed:** 2026-11-01\n**Status:** FIXED\n**Waiting on:** dispatch\n",
        "docs/bugs/2026-11-01-deferred.md": "# deferred\n**Priority:** P2\n**Filed:** 2026-11-01\n**Status:** DEFERRED\n**Waiting on:** operator decision\n",
        "docs/bugs/2026-11-01-malformed.md": '# malformed\n**Priority:** P2\n**Filed:** 2026-11-01\n**Status:** OPEN\n**Waiting on:** live check", evil="1\n',
    }
    output = metrics._bug_status_metrics(root, now=datetime(2026, 11, 6, tzinfo=timezone.utc), texts=texts)
    assert 'bug="2026-11-01-open",' in output
    rows = {re.search(r'bug="([^"]+)"', line).group(1): line for line in output.splitlines() if line.startswith("k3dm_bug_info{")}
    assert 'waiting_on="live check",waiting_since="2026-11-06"' in rows["2026-11-01-open"]
    assert 'waiting_on="scheduled run",waiting_since="-"' in rows["2026-11-01-unknown"]
    assert 'waiting_on="-",waiting_since="-"' in rows["2026-11-01-closed"]
    assert 'waiting_on="-",waiting_since="-"' in rows["2026-11-01-deferred"]
    assert 'waiting_on="invalid",waiting_since="-"' in rows["2026-11-01-malformed"]
    assert 'evil=' not in rows["2026-11-01-malformed"]


def test_waiting_on_does_not_change_metric_identity_fields(metrics, tmp_path):
    root = tmp_path / "fixture-repo"
    (root / "docs/bugs").mkdir(parents=True)
    assert root.name == "fixture-repo"
    base = "# bug\n**Priority:** P1\n**Filed:** 2026-11-01\n**Status:** OPEN\n"
    outputs = [metrics._bug_status_metrics(root, now=datetime(2026, 11, 6, tzinfo=timezone.utc), texts={"docs/bugs/2026-11-01-x.md": base + tail}) for tail in ("", "**Waiting on:** dispatch\n", "**Waiting on:** live check\n")]
    def identity(output):
        line = next(line for line in output.splitlines() if line.startswith("k3dm_bug_info{"))
        labels = line.split("} ", 1)[0]
        return line.split("} ", 1)[1], *(re.search(rf'{name}="([^"]*)"', labels).group(1) for name in ("status", "sort_key", "fix_sha"))
    assert identity(outputs[0]) == identity(outputs[1]) == identity(outputs[2])
    fixed = base.replace("OPEN", "FIXED") + "**Fix commit:** `abcdef1234567890`\n"
    fixed_outputs = [metrics._bug_status_metrics(root, now=datetime(2026, 11, 6, tzinfo=timezone.utc), texts={"docs/bugs/2026-11-01-x.md": fixed + tail}) for tail in ("", "**Waiting on:** dispatch\n")]
    assert identity(fixed_outputs[0]) == identity(fixed_outputs[1])


def _git_repo(root, docs):
    bugs = root / "docs/bugs"
    bugs.mkdir(parents=True)
    for name, text in docs.items():
        (bugs / name).write_text(text, encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
    subprocess.run(["git", "add", "docs/bugs"], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=root, check=True)


def _commit(root, message, date):
    subprocess.run(["git", "add", "docs/bugs"], cwd=root, check=True)
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(["git", "commit", "-qm", message], cwd=root, env=env, check=True)


@pytest.mark.parametrize(("status", "expected"), [
    ("LIVE-VERIFIED — live", ("implemented", "live_verified")),
    ("VERIFIED — tests", ("implemented", "verified")),
    ("IMPLEMENTED BY Codex", ("implemented", "unknown")),
    ("DONE", ("implemented", "unknown")), ("LANDED", ("implemented", "unknown")),
    ("MERGED", ("implemented", "unknown")), ("SHIPPED", ("implemented", "unknown")),
    ("IN PROGRESS", ("in_progress", "n/a")), ("IN-PROGRESS", ("in_progress", "n/a")),
    ("DISPATCHED", ("in_progress", "n/a")), ("PENDING CODEX", ("in_progress", "n/a")),
    ("READY", ("ready", "n/a")), ("APPROVED", ("ready", "n/a")),
    ("PROPOSED", ("proposed", "n/a")), ("SPEC", ("proposed", "n/a")),
    ("DRAFT", ("proposed", "n/a")), ("PLAN", ("proposed", "n/a")),
    ("PLANNED", ("proposed", "n/a")), ("SCOPED", ("proposed", "n/a")),
    ("QUEUED FOR v1.50.0", ("proposed", "n/a")),
    ("DEFERRED", ("deferred", "n/a")), ("MOVED", ("deferred", "n/a")),
    ("SPLIT", ("deferred", "n/a")), ("SUPERSEDED", ("cancelled", "n/a")),
    ("CANCELLED", ("cancelled", "n/a")), ("CANCELED", ("cancelled", "n/a")),
    ("DROPPED", ("cancelled", "n/a")), ("WITHDRAWN", ("cancelled", "n/a")),
    ("IMPLEMENTED — Claude-verified: pytest 106/106; live proof pending", ("implemented", "unknown")),
    ("Garbage", ("unknown", "unknown")), (None, ("unknown", "unknown")),
])
def test_plan_state_leading_status_only(metrics, status, expected):
    assert metrics._plan_state(status) == expected


def test_plan_approval_and_plan_metrics(metrics, tmp_path):
    assert metrics._plan_approval("**Approval:** explicit by operator", "v1.43.5") == "approved"
    assert metrics._plan_approval("**Approval:** pending — review", "v1.43.5") == "pending"
    assert metrics._plan_approval("", "v1.43.5") == "none"
    assert metrics._plan_approval("", "v1.43.1") == "n/a"
    docs = {
        "docs/plans/v1.43.5-a.md": '# v1.43.5 — Foo\n**Status:** READY\n**Approval:** explicit\n',
        "docs/plans/v1.43.5-b.md": '# A "quoted" `title`\n**Status:** IMPLEMENTED\n',
        "docs/plans/v1.42.0-old.md": '# Old\n**Status:** VERIFIED\n',
        "docs/plans/roadmap-v1.md": '# Skip\n',
    }
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = [line for line in output.splitlines() if line.startswith("k3dm_plan_info{")]
    assert len(rows) == 3
    assert 'plan="v1.43.5-a",title="Foo",execution="ready",verification="n/a",approval="approved"' in rows[0]  # agent-audit: allow assert-removed spec W5 renames approval value explicit to approved
    assert 'title="A quoted title"' in rows[1]
    assert metrics._release_order("v1.43.5") in rows[0]
    assert 'k3dm_plan_info_skipped{repo="k3d-manager"} 1' in output
    assert 'release="v1.43.5"' in output and 'execution="ready",verification="n/a"} 1' in output


def test_plan_waves_cycles_declared_waves_overlaps_and_dispatch(metrics, tmp_path):
    docs = {
        "docs/plans/v1.50.0-a.md": "# A\n**Release:** v1.50.0 (plan 1 of 8)\n**Status:** IMPLEMENTED\n**Component:** `scripts/shared/`\n",
        "docs/plans/v1.50.0-b.md": "# B\n**Release:** v1.50.0 (plan 2 of 8)\n**Depends on:** `docs/plans/v1.50.0-a.md`\n**Component:** `scripts/shared/file.sh`\n",
        "docs/plans/v1.50.0-c.md": "# C\n**Release:** v1.50.0 (plan 3 of 8)\n**Depends on:** `docs/plans/v1.50.0-b.md`\n**Component:** `scripts/c.sh`\n**Wave:** 6 — " + 'x' * 100 + ' "quoted"\n',
        "docs/plans/v1.50.0-d.md": "# D\n**Release:** v1.50.0 (plan 4 of 8)\n**Depends on:** `docs/plans/v1.50.0-c.md`\n**Wave:** 1 — too early\n",
        "docs/plans/v1.50.0-e.md": "# E\n**Release:** v1.50.0 (plan 5 of 8)\n**Depends on:** `docs/plans/v1.50.0-f.md`\n",
        "docs/plans/v1.50.0-f.md": "# F\n**Release:** v1.50.0 (plan 6 of 8)\n**Depends on:** `docs/plans/v1.50.0-e.md`\n",
        "docs/plans/v1.50.0-g.md": "# G\n**Release:** v1.50.0 (plan 7 of 8)\n**Status:** READY\n**Approval:** approved to file spec — dispatch not yet approved\n**Component:** `scripts/c.sh`\n**Dispatch:** needed — wait\n",
        "docs/plans/v1.50.0-h.md": "# H\n**Release:** v1.50.0 (plan 8 of 8)\n**Status:** READY\nOnly mentions `scripts/c.sh` in body.\n",
    }
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = {re.search(r'plan="([^"]+)"', line).group(1): line for line in output.splitlines()
            if line.startswith("k3dm_plan_info{")}
    assert 'wave="1"' in rows["v1.50.0-a"]
    assert 'wave="2"' in rows["v1.50.0-b"]
    assert 'wave="6"' in rows["v1.50.0-c"]
    assert 'wave="7",wave_note="declared 1 < required 7"' in rows["v1.50.0-d"]
    assert 'wave="cycle"' in rows["v1.50.0-e"] and 'wave="cycle"' in rows["v1.50.0-f"]
    assert 'overlaps="plan 7: scripts/c.sh"' in rows["v1.50.0-c"]
    assert 'overlaps="plan 3: scripts/c.sh"' in rows["v1.50.0-g"]
    assert 'overlaps="-"' in rows["v1.50.0-h"]
    assert 'approval="approved",dispatch_approval="needed"' in rows["v1.50.0-g"]
    assert 'dispatch_approval="unknown"' in rows["v1.50.0-h"]
    assert 'approval="approved",dispatch_approval="unknown"' not in rows["v1.50.0-h"]
    assert 'blocked_by="branch not cut; dispatch go needed"' in rows["v1.50.0-g"]
    assert len(re.search(r'wave_note="([^"]*)"', rows["v1.50.0-c"]).group(1)) <= 80
    assert 'k3dm_plan_undeclared_overlaps{repo="k3d-manager",release="v1.50.0"} 1' in output


def test_plan_status_and_dispatch_headers_remain_independent(metrics, tmp_path):
    docs = {
        "docs/plans/v1.54.0-proposed.md": "# Proposed\n**Status:** PROPOSED\n**Dispatch:** go\n",
        "docs/plans/v1.54.0-ready.md": "# Ready\n**Status:** READY\n**Dispatch:** needed\n",
        "docs/plans/v1.54.0-progress.md": "# Progress\n**Status:** IN PROGRESS\n**Dispatch:** not required\n",
        "docs/plans/v1.54.0-malformed.md": "# Malformed\n**Status:** READY\n**Approval:** approved\n**Dispatch:** maybe\n",
    }
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = {re.search(r'plan="([^"]+)"', line).group(1): line for line in output.splitlines()
            if line.startswith("k3dm_plan_info{")}
    assert 'execution="proposed",verification="n/a"' in rows["v1.54.0-proposed"]
    assert 'execution="ready",verification="n/a"' in rows["v1.54.0-ready"]
    assert 'execution="in_progress",verification="n/a"' in rows["v1.54.0-progress"]
    assert 'dispatch_approval="go"' in rows["v1.54.0-proposed"]
    assert 'dispatch_approval="needed"' in rows["v1.54.0-ready"]
    assert 'dispatch_approval="not required"' in rows["v1.54.0-progress"]
    assert 'approval="approved",dispatch_approval="unknown"' in rows["v1.54.0-malformed"]


def test_release_plans_lifecycle_rows_reconcile_only_blocked_by(metrics, tmp_path):
    dashboard_path = ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml"
    dashboard = json.loads(dashboard_path.read_text().split("  k3dm-bugs.json: |\n", 1)[1])
    panel = next(panel for panel in dashboard["panels"] if panel["id"] == 107)
    query = panel["targets"][0]["expr"]
    assert '"blocked_by", "landed; documentation stale"' in query
    assert 'dispatch_state="landed"' in query
    assert 'execution=~"proposed|ready|in_progress"' in query
    assert 'unless on(plan)' in query
    assert 'release=~"$release"' in query
    assert 'vector($release_mode) == 1' in query and 'vector($release_mode) == 0' in query
    # agent-audit: allow assert-removed replace single-column ban with projection checks and exact raw-label fixtures
    assert '"verified", "$1", "verification", "(verified|live_verified)"' in query
    assert '"live_verified", "$1", "verification", "(live_verified)"' in query
    lag_panel = next(panel for panel in dashboard["panels"]
                     if panel.get("title") == "Status lags dispatch")
    assert 'dispatch_state="landed"' in lag_panel["targets"][0]["expr"]
    assert 'execution=~"proposed|ready|in_progress"' in lag_panel["targets"][0]["expr"]
    assert '"dispatch_approval": "Dispatch approval"' in json.dumps(
        next(transform["options"] for transform in panel["transformations"]
             if transform["id"] == "organize"))

    dispatch = runpy.run_path(ROOT / "bin/k3dm-dispatch-metrics")
    state = dispatch["_dispatch_state"]
    lifecycle = {
        "landed": [{"event": "start", "ts": 1}, {"event": "land", "ts": 3}],
        "awaiting_land": [{"event": "start", "ts": 1},
                           {"event": "codex_exit", "ts": 2, "exit": 0}],
        "refused": [{"event": "start", "ts": 1},
                    {"event": "codex_exit", "ts": 2, "exit": 0},
                    {"event": "land_refused", "ts": 3}],
        "failed": [{"event": "start", "ts": 1},
                   {"event": "codex_exit", "ts": 2, "exit": 1}],
        "running": [{"event": "start", "ts": 1}],
    }
    assert {name: state(events) for name, events in lifecycle.items()} == {
        "landed": "landed", "awaiting_land": "awaiting_land", "refused": "refused",
        "failed": "codex_failed", "running": "running"}

    docs = {
        f"docs/plans/v1.54.0-{slug}.md": f"# {slug}\n**Status:** {status}\n"
        for slug, status in (("proposed", "PROPOSED"), ("ready", "READY"),
                             ("progress", "IN PROGRESS"), ("implemented", "IMPLEMENTED"))
    }

    task_field = next(prop["value"][0]["options"]
                      for override in panel["fieldConfig"]["overrides"]
                      if override["matcher"].get("options") == "Dispatch task"
                      for prop in override["properties"] if prop["id"] == "mappings")
    assert task_field["awaiting_land"]["text"] == "awaiting land"
    assert task_field["refused"]["text"] == "land refused"
    assert task_field["codex_failed"]["text"] == "codex failed"
    assert task_field["none"]["text"] == "no record"
    assert task_field["running"]["text"] == "running"
    assert task_field["landed"]["text"] == "landed"
    approval_field = next(prop["value"][0]["options"]
                          for override in panel["fieldConfig"]["overrides"]
                          if override["matcher"].get("options") == "Dispatch approval"
                          for prop in override["properties"] if prop["id"] == "mappings")
    assert approval_field["unknown"]["text"] == "not recorded"
    docs["docs/plans/v1.54.0-proposed.md"] += "**Approval:** pending review\n**Dispatch:** needed\n"
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = {re.search(r'plan="([^"]+)"', line).group(1): line
            for line in output.splitlines() if line.startswith("k3dm_plan_info{")}
    for slug, execution in (("proposed", "proposed"), ("ready", "ready"),
                            ("progress", "in_progress"), ("implemented", "implemented")):
        assert f'execution="{execution}"' in rows[f"v1.54.0-{slug}"]
    for slug in ("proposed", "ready", "progress"):
        assert 'verification="n/a"' in rows[f"v1.54.0-{slug}"]
    assert 'verification="unknown"' in rows["v1.54.0-implemented"]
    assert 'approval="pending",dispatch_approval="needed"' in rows["v1.54.0-proposed"]
    assert 'blocked_by="branch not cut; dispatch go needed"' in rows["v1.54.0-proposed"]
    assert 'blocked_by="branch not cut; dispatch approval unknown"' in rows["v1.54.0-ready"]
    assert 'blocked_by="-"' in rows["v1.54.0-progress"]
    assert 'blocked_by="-"' in rows["v1.54.0-implemented"]
    # A plan without a ledger series remains in the row inventory and keeps its own state.
    assert 'dispatch_state", "none"' in query and '"slug", "-"' in query


@pytest.mark.parametrize("release_mode", [0, 1])
def test_release_plans_query_evaluates_lifecycle_fixtures(tmp_path, release_mode):
    promtool = os.environ.get("PROMTOOL") or shutil.which("promtool")
    if not promtool:
        pytest.skip("promtool is required for offline Plans query evaluation")
    dashboard = json.loads((ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml")
                           .read_text().split("  k3dm-bugs.json: |\n", 1)[1])
    query = next(panel for panel in dashboard["panels"] if panel["id"] == 107)["targets"][0]["expr"]
    scenarios = [
        ("landed-proposed", "proposed", "landed", "dispatch approval unknown", "landed; documentation stale"),
        ("landed-ready", "ready", "landed", "dependency not landed", "landed; documentation stale"),
        ("landed-progress", "in_progress", "landed", "-", "landed; documentation stale"),
        ("landed-implemented", "implemented", "landed", "-", "-"),
        ("awaiting", "proposed", "awaiting_land", "dispatch go needed", "dispatch go needed"),
        ("refused", "ready", "refused", "dependency not landed", "dependency not landed"),
        ("failed", "proposed", "codex_failed", "dispatch go needed", "dispatch go needed"),
        ("running", "proposed", "running", "dispatch approval unknown", "dispatch approval unknown"),
        ("no-ledger", "implemented", None, "-", "-"),
        ("verified", "implemented", "landed", "-", "-"),
        ("live-verified", "implemented", "landed", "-", "-"),
    ]

    def sample_labels(name, values):
        return name + "{" + ",".join(key + "=" + json.dumps(value)
                                      for key, value in sorted(values.items())) + "}"

    series, expected = [], []
    for slug, execution, state, source_blocker, displayed_blocker in scenarios:
        source = dict(repo="k3d-manager", release="v1.43.9", plan="v1.43.9-" + slug,
                      title=slug, execution=execution,
                      verification="unknown" if execution == "implemented" else "n/a",
                      approval="pending", dispatch_approval="unknown", blocked_by=source_blocker)
        if slug == "verified":
            source["verification"] = "verified"
        elif slug == "live-verified":
            source["verification"] = "live_verified"
        series.append(dict(series=sample_labels("k3dm_plan_info", source), values="1"))
        if state:
            ledger = dict(plan=source["plan"], version="v1.43.9", slug=slug, dispatch_state=state)
            series.append(dict(series=sample_labels("k3dm_dispatch_plan_state", ledger), values="1"))
        shown = {**source, "dispatch_state": state or "none", "slug": slug if state else "-",
                 "blocked_by": displayed_blocker, "verified": "-", "live_verified": "-"}
        if source["verification"] in ("verified", "live_verified"):
            shown["verified"] = source["verification"]
        if source["verification"] == "live_verified":
            shown["live_verified"] = "live_verified"
        expected.append(dict(labels=sample_labels("" if state else "k3dm_plan_info", shown), value=1))
    series.append(dict(series='k3dm_bug_current_release_info{repo="k3d-manager",release="v1.43.9"}',
                       values="1"))
    # Neither another repo nor a release excluded by the selected mode may leak in.
    for repo, release in [("other", "v1.43.9"), ("k3d-manager", "v1.99.0")]:
        source = dict(repo=repo, release=release, plan=release + "-filtered",
                      execution="proposed", verification="n/a", blocked_by="x")
        series.append(dict(series=sample_labels("k3dm_plan_info", source), values="1"))
    expr = query.replace("$repo", "k3d-manager").replace("$release_mode", str(release_mode))
    expr = expr.replace("$release", "v1.43.9")
    fixture = dict(rule_files=[], evaluation_interval="1m", tests=[dict(
        name=f"Plans lifecycle mode={release_mode}", interval="1m", input_series=series,
        promql_expr_test=[dict(expr=expr, eval_time="0m", exp_samples=expected)])])
    path = tmp_path / "plans-query.json"
    path.write_text(json.dumps(fixture))
    result = subprocess.run([promtool, "test", "rules", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_plan_overlap_cap_and_blocker_branches(metrics, tmp_path):
    docs = {}
    for number in range(1, 7):
        stem = f"v1.51.0-p{number}"
        docs[f"docs/plans/{stem}.md"] = (
            f"# P{number}\n**Release:** v1.51.0 (plan {number} of 6)\n"
            "**Status:** READY\n**Dispatch:** go\n**Component:** `shared/file`\n"
        )
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = {re.search(r'plan="([^"]+)"', line).group(1): line for line in output.splitlines()
            if line.startswith("k3dm_plan_info{")}
    first = rows["v1.51.0-p1"]
    assert 'blocked_by="branch not cut"' in first
    assert 'overlaps="plan 2: shared/file; plan 3: shared/file; plan 4: shared/file +2 more"' in first
    assert len(re.search(r'overlaps="([^"]*)"', first).group(1).split("; ")) == 3

    subprocess.run(["git", "init", "-q", "-b", "k3d-manager-v1.51.0", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "Test"], check=True)
    (tmp_path / "seed").write_text("seed")
    subprocess.run(["git", "-C", str(tmp_path), "add", "seed"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "seed"], check=True)
    output = metrics._plan_metrics(tmp_path, texts=docs)
    first = next(line for line in output.splitlines()
                 if line.startswith("k3dm_plan_info{") and 'plan="v1.51.0-p1"' in line)
    assert 'blocked_by="ready to dispatch"' in first


def test_plan_blocked_by_only_for_undispatched_and_cross_release_uses_stem(metrics, tmp_path):
    docs = {
        "docs/plans/v1.52.0-dep.md": "# Dep\n**Release:** v1.52.0 (plan 2 of 2)\n**Status:** PROPOSED\n**Dispatch:** go\n",
        "docs/plans/v1.52.0-done.md": "# Done\n**Release:** v1.52.0 (plan 1 of 2)\n**Status:** IMPLEMENTED\n**Dispatch:** go\n",
        "docs/plans/v1.53.0-run.md": "# Run\n**Release:** v1.53.0 (plan 1 of 2)\n**Status:** IN PROGRESS\n**Dispatch:** go\n",
        "docs/plans/v1.53.0-next.md": ("# Next\n**Release:** v1.53.0 (plan 2 of 2)\n**Status:** PROPOSED\n"
                                       "**Dispatch:** go\n**Depends on:** `docs/plans/v1.52.0-dep.md`\n"),
    }
    output = metrics._plan_metrics(tmp_path, texts=docs)
    rows = {re.search(r'plan="([^"]+)"', line).group(1): line for line in output.splitlines()
            if line.startswith("k3dm_plan_info{")}
    assert 'blocked_by="-"' in rows["v1.52.0-done"]
    assert 'blocked_by="-"' in rows["v1.53.0-run"]
    assert 'blocked_by="branch not cut; v1.52.0-dep not landed"' in rows["v1.53.0-next"]


def test_plan_info_carries_the_scanned_branch_for_doc_links(metrics, tmp_path):
    docs = {"docs/plans/v1.44.0-next.md": "# Next\n**Status:** READY\n"}
    output = metrics._plan_metrics(tmp_path, "origin/k3d-manager-v1.43.5", texts=docs)
    row = next(line for line in output.splitlines() if line.startswith("k3dm_plan_info{"))
    assert 'branch="k3d-manager-v1.43.5"' in row
    assert 'release="v1.44.0"' in row


def test_plan_metrics_emits_order_and_resolves_dependencies_in_second_pass(metrics, tmp_path):
    docs = {
        "docs/plans/v1.43.5-a.md": "# A\n**Release:** v1.43.5 (plan 2 of 5)\n**Depends on:** `docs/plans/v1.43.5-z.md` (plan 4)\n",
        "docs/plans/v1.43.5-z.md": "# Z\n**Release:** v1.43.5 (plan 4 of 5)\n",
        "docs/plans/v1.43.5-ten.md": "# Ten\n**Release:** v1.43.5 (plan 10 of 12)\n",
        "docs/plans/v1.43.5-none.md": "# None\n",
        "docs/plans/v1.43.5-mixed.md": "# Mixed\n**Release:** v1.43.5 (plan 3 of 5)\n**Depends on:** `docs/plans/v1.43.5-z.md`, `docs/plans/v1.43.4-foo.md`, `docs/plans/v1.43.5-z.md`\n",
        "docs/plans/v1.43.5-empty.md": "# Empty\n**Depends on:** no path here\n",
        "docs/plans/v1.43.4-other-release.md": "# Other\n**Release:** v1.43.4 (plan 1 of 4)\n",
        "docs/plans/v1.43.5-cross.md": "# Cross\n**Release:** v1.43.5 (plan 5 of 5)\n**Depends on:** `docs/plans/v1.43.4-other-release.md`\n",
        "docs/plans/v1.43.5-no-order-dependency.md": "# No order\n",
        "docs/plans/v1.43.5-no-order-user.md": "# User\n**Release:** v1.43.5 (plan 1 of 5)\n**Depends on:** `docs/plans/v1.43.5-no-order-dependency.md`\n",
    }
    rows = [line for line in metrics._plan_metrics(tmp_path, texts=docs).splitlines()
            if line.startswith("k3dm_plan_info{")]
    by_plan = {re.search(r'plan="([^"]+)"', row).group(1): row for row in rows}
    assert 'order="2",depends_on="plan 4"' in by_plan["v1.43.5-a"]
    assert 'order="10"' in by_plan["v1.43.5-ten"]
    assert 'order="",depends_on="-"' in by_plan["v1.43.5-none"]
    assert 'depends_on="plan 4, v1.43.4-foo"' in by_plan["v1.43.5-mixed"]
    assert 'depends_on="-"' in by_plan["v1.43.5-empty"]
    assert 'depends_on="v1.43.4-other-release"' in by_plan["v1.43.5-cross"]
    assert 'depends_on="v1.43.5-no-order-dependency"' in by_plan["v1.43.5-no-order-user"]

def test_plan_metrics_reads_worktree_top_level_only(metrics, tmp_path):
    plans=tmp_path / "docs/plans"
    plans.mkdir(parents=True)
    (plans / "v1.43.5-one.md").write_text("# One\n**Status:** READY\n")
    (plans / "sub").mkdir()
    (plans / "sub/v1.43.5-nested.md").write_text("# Nested")
    out = metrics._plan_metrics(tmp_path)
    assert 'plan="v1.43.5-one"' in out
    assert "nested" not in out


def test_plan_metrics_reads_git_ref_top_level_only(metrics, tmp_path):
    _git_repo(tmp_path, {"2026-10-23-seed.md": "# Seed\n"})
    plans = tmp_path / "docs/plans"
    (plans / "sub").mkdir(parents=True)
    (plans / "v1.43.5-one.md").write_text("# One\n**Status:** READY\n")
    (plans / "sub/v1.43.5-nested.md").write_text("# Nested")
    subprocess.run(["git", "add", "docs/plans"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "plans"], cwd=tmp_path, check=True)
    (plans / "v1.43.5-one.md").write_text("# One\n**Status:** PROPOSED\n")
    out = metrics._plan_metrics(tmp_path, "HEAD")
    assert 'plan="v1.43.5-one"' in out and 'execution="ready"' in out
    assert "nested" not in out


def test_status_date_formats_status_dates(metrics):
    assert metrics._status_date("LIVE-VERIFIED — 2026-10-16T21:35:33Z: x") == "2026-10-16 21:35Z"
    assert metrics._status_date("LIVE-VERIFIED 2026-10-15 — x") == "2026-10-15"
    assert metrics._status_date("LIVE-VERIFIED — not reproduced, test 2026-10-15: x") is None
    assert metrics._status_date("VERIFIED — offline. Drill 2026-10-29. Was: IMPLEMENTED 14:41Z") is None
    assert metrics._status_date("VERIFIED — tests green") is None


def test_M1_doc_live_evidence_accepts_both_separators_and_skips_malformed(metrics):
    text = "\n".join([
        "**Live evidence:** 2026-10-17 · run 123 · env sandbox/local-m4 · scenario stripe/product-catalog · commit abcdef1 · proves E1,E3",
        "**Live evidence:** 2026-10-18 | run logs/proof.log | env hostinger | scenario make-down | commit 0123456789abcdef | proves E4",
        "**Live evidence:** 2026-10-19 · run 123 · env missing-commit · scenario bad · commit nope · proves E1",
    ])
    assert metrics.doc_live_evidence(text) == [
        {"date": "2026-10-17", "run": "123", "env": "sandbox/local-m4",
         "scenario": "stripe/product-catalog", "commit": "abcdef1", "proves": "E1,E3"},
        {"date": "2026-10-18", "run": "logs/proof.log", "env": "hostinger",
         "scenario": "make-down", "commit": "0123456789abcdef", "proves": "E4"},
    ]


def test_M2_M3_M4_live_evidence_states_and_open_for(metrics, tmp_path):
    now = datetime(2026, 10, 17, tzinfo=timezone.utc)
    texts = {
        "docs/bugs/current.md": "**Filed:** 2026-10-10\n**Status:** LIVE-VERIFIED\n**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit abcdef1 · proves E3\n",
        "docs/bugs/missing.md": "**Filed:** 2026-10-10\n**Status:** LIVE-VERIFIED\n",
        "docs/bugs/stale.md": "**Filed:** 2026-10-10\n**Status:** LIVE-VERIFIED\n**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit deadbee · proves E3\n",
    }
    tally = {"v1.43.4": {"closed_paths": [{"path": path} for path in texts]}}
    fixed = {path: {"release": "v1.43.4", "commit": "abc1234"} for path in texts}
    output = metrics._bug_status_metrics(
        tmp_path, now=now, tally=tally, texts=texts, fixed_in=fixed,
        evidence_check=lambda fix, evidence: fix == "abc1234" and evidence == "abcdef1",
    )
    rows = {line.split('bug="', 1)[1].split('"', 1)[0]: line
            for line in output.splitlines() if line.startswith("k3dm_bug_info{")}
    assert 'live_evidence="ok"' in rows["current"] and rows["current"].endswith(" -2")
    assert 'live_evidence="missing"' in rows["missing"] and rows["missing"].endswith(" 7")
    assert 'live_evidence="stale"' in rows["stale"] and rows["stale"].endswith(" 7")


def test_N1_stale_evidence_never_counts_as_current(metrics, tmp_path):
    path = "docs/bugs/stale.md"
    text = "**Filed:** 2026-10-10\n**Status:** LIVE-VERIFIED\n**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit deadbee · proves E3\n"
    output = metrics._bug_status_metrics(
        tmp_path, now=datetime(2026, 10, 17, tzinfo=timezone.utc),
        tally={"v1.43.4": {"closed_paths": [{"path": path}]}}, texts={path: text},
        fixed_in={path: {"release": "v1.43.4", "commit": "abc1234"}},
        evidence_check=lambda *_args: False,
    )
    line = next(line for line in output.splitlines() if line.startswith("k3dm_bug_info{"))
    assert 'live_evidence="stale"' in line and not line.endswith(" -2")


def test_verification_times_use_earliest_git_state_commits_and_utc(metrics, tmp_path):
    _git_repo(tmp_path, {"bug.md": "**Priority:** P1\n**Status:** IMPLEMENTED\n"})
    bug = tmp_path / "docs/bugs/bug.md"
    bug.write_text("**Priority:** P1\n**Status:** VERIFIED — tests green\n")
    _commit(tmp_path, "verified", "2026-10-16T21:35:33-07:00")
    verified_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=tmp_path, capture_output=True, text=True, check=True).stdout.strip()
    bug.write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED — hub proof\n")
    _commit(tmp_path, "live", "2026-10-16T22:35:33+02:00")
    times = metrics._verification_times(tmp_path, "HEAD", {"docs/bugs/bug.md": bug.read_text()})
    # agent-audit: allow assert-removed verification tuples gained the verified commit SHA as a third element
    assert times == {"docs/bugs/bug.md": ("2026-10-17 04:35Z", "2026-10-16 20:35Z", verified_sha)}


def test_verification_times_copy_status_date_for_direct_live_verification(metrics, tmp_path):
    _git_repo(tmp_path, {"bug.md": "**Priority:** P1\n**Status:** IMPLEMENTED\n"})
    bug = tmp_path / "docs/bugs/bug.md"
    bug.write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED — 2026-10-15: not reproduced\n")
    _commit(tmp_path, "live", "2026-10-16T22:35:33+02:00")
    verified_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=tmp_path, capture_output=True, text=True, check=True).stdout.strip()
    times = metrics._verification_times(tmp_path, "HEAD", {"docs/bugs/bug.md": bug.read_text()})
    assert times == {"docs/bugs/bug.md": ("2026-10-15", "2026-10-15", verified_sha)}


def test_verification_times_add_commit_time_to_same_day_status_date(metrics, tmp_path):
    _git_repo(tmp_path, {"bug.md": "**Priority:** P1\n**Status:** IMPLEMENTED\n"})
    bug = tmp_path / "docs/bugs/bug.md"
    bug.write_text("**Priority:** P1\n**Status:** VERIFIED — 2026-10-17: tests green\n")
    _commit(tmp_path, "verified", "2026-10-17T19:41:10+00:00")
    bug.write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED — 2026-10-17: live proof\n")
    _commit(tmp_path, "live", "2026-10-17T21:05:00+00:00")
    times = metrics._verification_times(tmp_path, "HEAD", {"docs/bugs/bug.md": bug.read_text()})
    assert times["docs/bugs/bug.md"][:2] == ("2026-10-17 19:41Z", "2026-10-17 21:05Z")


def test_verification_times_add_commit_time_when_status_date_is_commit_local_date(metrics, tmp_path):
    _git_repo(tmp_path, {"bug.md": "**Priority:** P1\n**Status:** IMPLEMENTED\n"})
    bug = tmp_path / "docs/bugs/bug.md"
    bug.write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED — 2026-10-17: live proof\n")
    _commit(tmp_path, "live", "2026-10-17T17:09:09-07:00")
    times = metrics._verification_times(tmp_path, "HEAD", {"docs/bugs/bug.md": bug.read_text()})
    assert times["docs/bugs/bug.md"][:2] == ("2026-10-18 00:09Z", "2026-10-18 00:09Z")


def test_verification_times_keep_bare_date_when_neither_commit_date_matches(metrics, tmp_path):
    _git_repo(tmp_path, {"bug.md": "**Priority:** P1\n**Status:** IMPLEMENTED\n"})
    bug = tmp_path / "docs/bugs/bug.md"
    bug.write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED — 2026-10-16: live proof\n")
    _commit(tmp_path, "live", "2026-10-17T17:09:09-07:00")
    times = metrics._verification_times(tmp_path, "HEAD", {"docs/bugs/bug.md": bug.read_text()})
    assert times["docs/bugs/bug.md"][:2] == ("2026-10-16", "2026-10-16")


def test_verification_times_git_failure_is_non_fatal_and_metrics_fall_back(metrics, tmp_path):
    texts = {"docs/bugs/verified.md": "**Priority:** P1\n**Status:** VERIFIED\n"}
    times = metrics._verification_times(tmp_path / "not-a-repo", "HEAD", texts)
    assert times == {"docs/bugs/verified.md": ("true", None, None)}
    output = metrics._bug_status_metrics(tmp_path, tally={
        "v1.43.2": {"closed_paths": [{"path": "docs/bugs/verified.md"}]},
    }, texts=texts, verification_times=times)
    assert 'verified_at="true"' in output


def test_bug_metrics_has_exact_counts_all_15_series_and_scan_timestamp(metrics, tmp_path):
    output = metrics._bug_metrics(_repo(tmp_path))
    assert 'k3dm_bug_docs{repo="k3d-manager",priority="P1",state="open"} 1' in output
    assert 'k3dm_bug_docs{repo="k3d-manager",priority="P0",state="closed"} 1' in output
    assert 'k3dm_bug_docs{repo="k3d-manager",priority="unset",state="unknown"} 1' in output
    assert output.count("k3dm_bug_docs{") == 15
    assert "k3dm_bug_docs_scan_timestamp_seconds" in output
    assert "archive" not in output and "issues" not in output


def test_bug_metrics_pushes_separate_group(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    assert metrics.publish_bug_metrics(_repo(tmp_path)) is True
    assert any("/metrics/job/k3dm-bug-docs" in str(getattr(url, "full_url", url)) for url in urls)


def test_release_cadence_nearest_rank_and_minimum(metrics):
    tags = [(f"v1.0.{i}", i * (i + 1) // 2) for i in range(13)]
    assert metrics._cadence(tags) == {"p25": 3, "p50": 6, "p75": 9, "gaps": 12, "last_ts": 78}
    assert metrics._cadence(tags[:6]) is None
    assert metrics._cadence([(f"v1.0.{i}", i // 2 * 100) for i in range(13)]) ["p25"] == 0


def test_release_tags_ignore_non_semver_and_cadence_uses_date_order(metrics, tmp_path):
    _git_repo(tmp_path, {"seed.md": "seed\n"})
    dates = [
        ("v1.1.0", "2026-01-01T00:00:00Z"),
        ("v1.2.0", "2026-01-03T00:00:00Z"),
        ("v1.1.1", "2026-01-13T00:00:00Z"),
        ("v1.3.0", "2026-01-07T00:00:00Z"),
        ("v1.4.0", "2026-01-21T00:00:00Z"),
        ("v1.5.0", "2026-01-31T00:00:00Z"),
        ("v1.6.0", "2026-03-02T00:00:00Z"),
    ]
    for name, date in dates + [("v1.2", "2026-01-03T00:00:00Z"),
                               ("lib-v0.5.2", "2026-01-03T00:00:00Z")]:
        env = {**os.environ, "GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date}
        subprocess.run(["git", "tag", "-a", name, "-m", name], cwd=tmp_path,
                       env=env, check=True)
    tags = metrics._release_tags(tmp_path)
    expected = sorted((name for name, _ in dates), key=lambda v: tuple(map(int, v[1:].split("."))))
    assert [version for version, _ in tags] == expected
    cadence = metrics._cadence(tags)
    assert cadence and cadence["gaps"] == 6
    assert (cadence["p25"], cadence["p50"], cadence["p75"]) == (
        4 * 86400, 6 * 86400, 10 * 86400)
    assert cadence["last_ts"] == max(stamp for _, stamp in tags)


def test_release_forecast_blocking_and_overdue(metrics):
    items = [{"version": "v1.0.1"}, {"version": "v1.0.2"},
             {"version": "v1.0.3", "blocked_by": "external"}, {"version": "v1.0.4"}]
    cadence = {"p25": 10, "p50": 20, "p75": 30, "last_ts": 100}
    rows = metrics._forecast(items, [("v1.0.0", 1)], cadence, 105)
    assert rows[0]["low"] == 110 and rows[1]["mid"] == 140
    assert rows[0]["overdue"] is False
    assert [row["state"] for row in rows[2:]] == ["blocked", "after_blocked"]
    assert all("low" not in row for row in rows[2:])
    rows = metrics._forecast([{"version": f"v1.0.{i}"} for i in range(1, 5)], [], None, 105)
    assert [row["state"] for row in rows] == ["insufficient"] * 4


def test_release_forecast_unblocked_shipped_and_overdue_positions(metrics):
    cadence = {"p25": 10, "p50": 20, "p75": 30, "last_ts": 100}
    items = [
        {"version": "v1.0.1"},
        {"version": "v1.0.2"},
        {"version": "v1.0.3", "blocked_by": "external", "blocked_done": True},
        {"version": "v1.0.4", "target": True},
    ]
    rows = metrics._forecast(items, [], cadence, 105)
    assert [(row["low"], row["mid"], row["high"]) for row in rows] == [
        (110, 120, 130), (120, 140, 160), (130, 160, 190), (140, 180, 220)]
    rows = metrics._forecast(items, [("v1.0.1", 1)], cadence, 105)
    assert rows[0]["state"] == "shipped" and "low" not in rows[0]
    assert (rows[1]["low"], rows[1]["mid"], rows[1]["high"]) == (110, 120, 130)
    overdue = metrics._forecast([{"version": "v1.0.5"}], [],
                                {"p25": 10, "p50": 20, "p75": 30, "last_ts": 0}, 11)[0]
    assert overdue["low"] == 11 and overdue["overdue"] is True


def test_release_forecast_without_not_before_keeps_the_original_formula(metrics):
    cadence = {"p25": 10 * 86400, "p50": 20 * 86400, "p75": 30 * 86400,
               "last_ts": int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp())}
    plain = [{"version": f"v1.0.{i}"} for i in range(1, 4)]
    rows = metrics._forecast(plain, [], cadence, 0)
    for index, row in enumerate(rows, 1):
        assert [row[b] for b in ("low", "mid", "high")] == [
            cadence["last_ts"] + index * cadence[key] for key in ("p25", "p50", "p75")]
    early = metrics._forecast([{"version": "v1.0.1", "not_before": "2025-01-01"}], [], cadence, 0)[0]
    assert [early[b] for b in ("low", "mid", "high")] == [
        cadence["last_ts"] + cadence[key] for key in ("p25", "p50", "p75")]
    shipped = metrics._forecast([{"version": "v1.0.1", "not_before": "2099-01-01"}],
                                [("v1.0.1", 50)], cadence, 0)[0]
    assert shipped["state"] == "shipped" and "low" not in shipped


def test_release_forecast_not_before_floors_every_bound(metrics):
    cadence = {"p25": 10 * 86400, "p50": 20 * 86400, "p75": 30 * 86400,
               "last_ts": int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp())}
    floor = int(datetime(2026, 2, 1, tzinfo=timezone.utc).timestamp())
    row = metrics._forecast([{"version": "v1.0.1", "not_before": "2026-02-01"}],
                            [], cadence, 0)[0]
    assert all(row[b] >= floor for b in ("low", "mid", "high"))
    assert row["floored"] is True


def test_release_after_floored_milestone_chains_from_its_bound(metrics):
    cadence = {"p25": 10 * 86400, "p50": 20 * 86400, "p75": 30 * 86400,
               "last_ts": int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp())}
    floor = int(datetime(2026, 3, 15, tzinfo=timezone.utc).timestamp())
    rows = metrics._forecast([{"version": "v1.0.1", "not_before": "2026-03-15"},
                              {"version": "v1.0.2"}], [], cadence, 0)
    assert all(rows[1][b] >= floor + cadence[key] for b, key in
               zip(("low", "mid", "high"), ("p25", "p50", "p75")))


@pytest.mark.parametrize("value", ["2026-13-40", "next week"])
def test_load_milestones_rejects_invalid_not_before(metrics, tmp_path, value):
    path = tmp_path / "docs/release-milestones.json"
    path.parent.mkdir()
    path.write_text(json.dumps({"milestones": [{"version": "v1.0.0", "target": True,
                                                  "not_before": value}]}))
    with pytest.raises(ValueError):
        metrics._load_milestones(tmp_path)


def _prepare_publish_metrics(metrics, root, monkeypatch, tmp_path):
    _git_repo(root, {"bug.md": "# Bug\n**Priority:** P2\n**Status:** OPEN\n"})
    (root / "docs/plans").mkdir(parents=True, exist_ok=True)
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.0.7"},
        {"version": "v1.0.8", "blocked_by": "outside work"},
        {"version": "v1.0.9", "target": True},
    ]}))
    for index in range(7):
        date = f"2026-01-{index + 1:02d}T00:00:00Z"
        env = {**os.environ, "GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date}
        subprocess.run(["git", "tag", "-a", f"v1.0.{index}", "-m", "release"],
                       cwd=root, env=env, check=True)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__,
                        "_tally", lambda *_a, **_k: {"releases": {}, "fixed_in": {}})
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_verification_times",
                        lambda *_a, **_k: {})
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_bug_status_metrics",
                        lambda *_a, **_k: "open metrics\n")
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_release_metrics",
                        lambda *_a, **_k: "release metrics\n")
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__,
                        "_publish_lib_foundation_bugs", lambda: None)
    pushed = []
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_push_bug_group",
                        lambda job, payload, method="POST", **_k: pushed.append((job, method, payload)) or True)
    return pushed


def test_forecast_metrics_and_publish_put_and_blocking(metrics, monkeypatch, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    pushed = _prepare_publish_metrics(metrics, root, monkeypatch, tmp_path)
    out = metrics._forecast_metrics(root, now=2_000_000_000)
    assert 'version="v1.0.8"' in out and 'state="blocked"' in out
    assert 'version="v1.0.9"' in out and 'state="after_blocked"' in out
    assert all(f'k3dm_release_milestone_forecast_seconds{{repo="k3d-manager",version="{version}"' not in out
               for version in ("v1.0.8", "v1.0.9"))
    info = [line for line in out.splitlines() if line.startswith("k3dm_release_milestone_info{")]
    assert info and all('overdue="true"' in line or 'overdue="false"' in line for line in info)
    assert metrics.publish_bug_metrics(root) is True
    forecast = next(entry for entry in pushed if entry[0] == "k3dm-release-forecast")
    assert forecast[1] == "PUT"


def test_forecast_metrics_exports_not_before_labels(metrics, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    _git_repo(root, {"seed.md": "seed\n"})
    (root / "docs").mkdir(exist_ok=True)
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.0.1", "not_before": "2026-11-03",
         "not_before_reason": 'live window "primary"'},
        {"version": "v1.0.2", "target": True},
    ]}))
    out = metrics._forecast_metrics(root, now=1_700_000_000)
    row = next(line for line in out.splitlines()
               if line.startswith('k3dm_release_milestone_info{') and 'version="v1.0.1"' in line)
    assert 'not_before="2026-11-03"' in row
    assert 'not_before_reason="live window primary"' in row


def test_malformed_forecast_is_nonfatal_to_other_groups(metrics, monkeypatch, tmp_path, capsys):
    root = tmp_path / "repo"
    root.mkdir()
    pushed = _prepare_publish_metrics(metrics, root, monkeypatch, tmp_path)
    (root / "docs/release-milestones.json").write_text("{")
    assert metrics.publish_bug_metrics(root) is True
    captured = capsys.readouterr()
    assert "release forecast skipped (non-fatal)" in captured.err
    jobs = [job for job, _, _ in pushed]
    assert "k3dm-bug-docs" in jobs and "k3dm-plan-docs" in jobs
    assert "k3dm-bug-open" in jobs and "k3dm-bug-releases" in jobs


def test_load_milestones_validates_target_and_versions(metrics, tmp_path):
    path = tmp_path / "docs/release-milestones.json"
    path.parent.mkdir()
    for milestones in ([{"version": "v1.0.0", "target": True}, {"version": "v1.0.0"}],
                       [{"version": "v1.0.0"}],
                       [{"version": "v1.0.0", "target": True}, {"version": "v1.0.1", "target": True}],
                       [{"version": "1.44", "target": True}]):
        path.write_text(json.dumps({"milestones": milestones}))
        with pytest.raises(ValueError):
            metrics._load_milestones(tmp_path)


def test_bug_metrics_read_failure_does_not_push(metrics, monkeypatch, tmp_path):
    root = _repo(tmp_path)
    original_read_text = Path.read_text
    def fail_one(path, *args, **kwargs):
        if path.name == "p1-open.md":
            raise OSError("read failure")
        return original_read_text(path, *args, **kwargs)
    monkeypatch.setattr(Path, "read_text", fail_one)
    pushed = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda *_a, **_k: pushed.append(True))
    assert metrics.publish_bug_metrics(root) is False
    assert pushed == []


def test_bug_texts_reads_committed_docs_with_one_cat_file(metrics, monkeypatch, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    expected = {
        "docs/bugs/one.md": "# one\n\nCafé — 日本語\n",
        "docs/bugs/two.md": "# two\n\nplain\n",
        "docs/bugs/three.md": "# three\n\nthird\n",
    }
    _git_repo(root, {path.removeprefix("docs/bugs/"): text for path, text in expected.items()})
    original_run = metrics.subprocess.run
    calls = []

    def tracked_run(argv, *args, **kwargs):
        calls.append(argv)
        return original_run(argv, *args, **kwargs)

    monkeypatch.setattr(metrics.subprocess, "run", tracked_run)
    assert metrics._bug_texts(root, "HEAD") == expected
    assert sum("cat-file" in call for call in calls) == 1
    assert not any("show" in call for call in calls)


def test_bug_texts_rejects_missing_batch_object(metrics, monkeypatch, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    _git_repo(root, {"present.md": "# present\n"})
    original_run = metrics.subprocess.run

    def add_missing_path(argv, *args, **kwargs):
        result = original_run(argv, *args, **kwargs)
        if "ls-tree" in argv:
            result.stdout += "docs/bugs/missing.md\n"
        return result

    monkeypatch.setattr(metrics.subprocess, "run", add_missing_path)
    with pytest.raises(RuntimeError):
        metrics._bug_texts(root, "HEAD")


def test_bug_metric_labels_are_fixed_enums(metrics, tmp_path):
    output = metrics._bug_metrics(_repo(tmp_path))
    for line in output.splitlines():
        if "k3dm_bug_docs{" not in line:
            continue
        assert 'priority="' in line and 'state="' in line
        assert all(value in line for value in ())
        assert line.split('priority="', 1)[1].split('"', 1)[0] in {"P0", "P1", "P2", "P3", "unset"}
        assert line.split('state="', 1)[1].split('"', 1)[0] in {"open", "closed", "unknown"}


def test_bug_status_metrics_include_all_docs_and_sanitized_labels(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-01-foo.md").write_text(
        '# Bug: the `foo` "bar"\n\n**Priority:** P1\n**Filed:** 2026-10-01\n**Status:** Open\n')
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    (bugs / "unknown.md").write_text("# unknown\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime(2026, 10, 11, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 3
    assert 'priority="P1"' in info[0]
    assert 'title="the foo bar"' in info[0]
    assert 'filed="2026-10-01"' in info[0]
    assert 'bug="2026-10-01-foo"' in info[0]
    assert 'docs/' not in info[0] and '.md' not in info[0]
    assert any(line.endswith(" 10") for line in info)


def test_bug_status_metrics_labels_release_from_tally_or_unassigned(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for name in ("known.md", "unknown.md", "absent.md"):
        (bugs / name).write_text("**Priority:** P1\n**Status:** Open\n")
    tally = {
        "v1.43.1": {"open_paths": [{"path": "docs/bugs/known.md"}]},
        "unknown": {"open_paths": [{"path": "docs/bugs/unknown.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert any('bug="known",' in line and 'release="v1.43.1"' in line for line in lines)
    assert all('release="unassigned"' in line for line in lines if 'bug="known"' not in line)
    no_tally = metrics._bug_status_metrics(tmp_path, tally=None)
    assert all('release="unassigned"' in line for line in no_tally.splitlines()
               if line.startswith("k3dm_bug_info{"))


def test_release_order_inverts_version_parts_and_sorts_newest_first(metrics):
    releases = ["v1.5.0", "v1.14.0", "v1.43.2", "v2.0.0", "unassigned"]
    labels = {metrics._release_order(release): release for release in releases}
    assert metrics._release_order("v1.43.2") == "9998.9956.9997 v1.43.2"
    assert metrics._release_order("unassigned") == "9999.9999.9999 unassigned"
    assert [labels[label] for label in sorted(labels)] == [
        "v2.0.0", "v1.43.2", "v1.14.0", "v1.5.0", "unassigned"]


def test_bug_status_metrics_verified_values_and_status_order(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    docs = {
        "implemented.md": "**Priority:** P1\n**Status:** IMPLEMENTED — landed\n",
        "verified.md": "**Priority:** P1\n**Status:** VERIFIED — live\n",
        "live-verified.md": "**Priority:** P1\n**Status:** LIVE-VERIFIED — hub proof\n",
        "old-fixed.md": "**Priority:** P2\n**Status:** LIVE-VERIFIED — historical proof\n",
        "unassigned-fixed.md": "**Priority:** P3\n**Status:** FIXED\n",
        "open.md": "**Priority:** P0\n**Status:** OPEN\n",
        "deferred.md": "**Priority:** P1\n**Status:** DEFERRED\n",
    }
    for name, text in docs.items():
        (bugs / name).write_text(text)
    tally = {
        "v1.43.2": {"open_paths": [{"path": f"docs/bugs/{name}"} for name in ("implemented.md", "verified.md", "live-verified.md", "open.md", "deferred.md")]},
        "v1.40.0": {"closed_paths": [{"path": "docs/bugs/old-fixed.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    # agent-audit: allow assert-removed because fixed-not-live rows now count from filed date
    assert any('bug="implemented"' in line and 'status="fixed"' in line and 'verified="false"' in line and line.endswith(" -1") for line in info)
    assert any('bug="implemented"' in line and 'live_verified="false"' in line for line in info)
    # agent-audit: allow assert-removed because offline VERIFIED rows now count from filed date
    assert any('bug="verified"' in line and 'status="fixed"' in line and 'verified="true"' in line and 'live_verified="false"' in line and line.endswith(" -1") for line in info)
    assert any('bug="live-verified"' in line and 'verified="true"' in line and 'live_verified="true"' in line for line in info)
    assert any('bug="old-fixed"' in line and 'status="fixed"' in line and 'verified="n/a"' in line and 'live_verified="n/a"' in line and line.endswith(" -2") for line in info)
    # agent-audit: allow assert-removed verified assertions rewritten to also check live_verified
    assert any('bug="unassigned-fixed"' in line and 'status="fixed"' in line and 'verified="n/a"' in line and 'live_verified="n/a"' in line for line in info)
    assert any('bug="open"' in line and 'status="open"' in line and ',verified="-"' in line for line in info)
    assert any('bug="open"' in line and 'live_verified="-"' in line and 'fixed_in="-"' in line for line in info)
    assert any('bug="implemented"' in line and 'verified_at="false"' in line and 'live_verified_at="false"' in line for line in info)
    assert any('bug="old-fixed"' in line and 'verified_at="n/a"' in line and 'live_verified_at="n/a"' in line for line in info)
    assert any('bug="deferred"' in line and 'status="deferred"' in line and ',verified="-"' in line for line in info)
    statuses = [line.split('status="', 1)[1].split('"', 1)[0]
                for line in info if 'release="v1.43.2"' in line]
    assert statuses == sorted(statuses, key={"open": 0, "unknown": 1, "deferred": 2, "fixed": 3}.get)


def test_acceptance_M1_M2_M3_M4_N1_N2_N3_open_for_until_live_verified(metrics, tmp_path):
    now = datetime(2026, 10, 17, tzinfo=timezone.utc)
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    docs = {
        "m1-fixed.md": "**Priority:** P1\n**Filed:** 2026-10-10\n**Status:** FIXED\n",
        "m2-verified.md": "**Priority:** P1\n**Filed:** 2026-10-09\n**Status:** VERIFIED — offline\n",
        "m3-live.md": "**Priority:** P1\n**Filed:** 2026-10-08\n**Status:** LIVE-VERIFIED — live\n**Live evidence:** 2026-10-15 · run r1 · env sandbox/m4 · scenario s/x · commit abcdef12 · proves E3\n",
        "m4-open.md": "**Priority:** P1\n**Filed:** 2026-10-11\n**Status:** OPEN\n",
        "m4-unknown.md": "**Priority:** P1\n**Status:** OPEN\n",
        "n2-old-fixed.md": "**Priority:** P1\n**Filed:** 2026-10-01\n**Status:** FIXED\n",
    }
    for name, text in docs.items():
        (bugs / name).write_text(text)
    tally = {
        "v1.43.4": {"open_paths": [
            {"path": f"docs/bugs/{name}"}
            for name in ("m1-fixed.md", "m2-verified.md", "m3-live.md", "m4-open.md", "m4-unknown.md")
        ]},
        "v1.43.1": {"closed_paths": [{"path": "docs/bugs/n2-old-fixed.md"}]},
    }

    def fail_if_called(*_args, **_kwargs):
        raise AssertionError("metric publishing is outside this acceptance test")

    metrics.publish_bug_metrics = fail_if_called
    metrics._push_bug_group = fail_if_called
    output = metrics._bug_status_metrics(tmp_path, now=now, tally=tally)
    values = {
        line.split('bug="', 1)[1].split('"', 1)[0]: int(line.rsplit(" ", 1)[1])
        for line in output.splitlines() if line.startswith("k3dm_bug_info{")
    }
    assert values["m1-fixed"] == 7
    assert values["m2-verified"] == 8
    assert values["m3-live"] == -2
    assert values["m4-open"] == 6
    assert values["m4-unknown"] == -1
    assert values["n2-old-fixed"] == -2


def test_acceptance_M5_grafana_guide_defines_open_for_until_live_verified():
    guide = (ROOT / "docs/guides/grafana-dashboards/k3dm-bugs.md").read_text(encoding="utf-8")
    # agent-audit: allow assert-removed replace the old punctuation-bound sentence check with code-fix wording plus the explicit investigation exception.
    assert "Open for counts from filed until the bug is LIVE-VERIFIED" in guide
    assert "closed investigation has valid typed recovery proof" in guide


def test_bug_status_metrics_sort_by_release_then_priority(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for name, priority in (("old-p0.md", "P0"), ("new-p2.md", "P2"),
                           ("new-p0.md", "P0"), ("unassigned.md", "P1")):
        (bugs / name).write_text(f"**Priority:** {priority}\n**Status:** Open\n")
    tally = {
        "v1.5.0": {"open_paths": [{"path": "docs/bugs/old-p0.md"}]},
        "v1.14.0": {"open_paths": [{"path": "docs/bugs/new-p2.md"},
                                     {"path": "docs/bugs/new-p0.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert [line.split('bug="', 1)[1].split('"', 1)[0] for line in lines] == [
        "new-p0", "new-p2", "old-p0", "unassigned"]


def test_bug_status_metrics_sort_priority_before_status(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    docs = {
        "p3-open.md": "**Priority:** P3\n**Status:** Open\n",
        "p1-fixed.md": "**Priority:** P1\n**Status:** FIXED\n",
        "p2-open.md": "**Priority:** P2\n**Status:** Open\n",
        "unset-open.md": "**Status:** Open\n",
    }
    for name, text in docs.items():
        (bugs / name).write_text(text)
    tally = {"v1.43.4": {
        "open_paths": [{"path": f"docs/bugs/{name}"} for name in ("p3-open.md", "p2-open.md", "unset-open.md")],
        "closed_paths": [{"path": "docs/bugs/p1-fixed.md"}],
    }}
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    sort_keys = [line.split('sort_key="', 1)[1].split('"', 1)[0] for line in lines]
    assert [line.split('priority="', 1)[1].split('"', 1)[0] for line in lines] == [
        "P1", "P2", "P3", "unset"]
    assert sort_keys == sorted(sort_keys)


def test_bug_status_metrics_puts_live_verified_last_on_fixed_metrics(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "live.md").write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED\n")
    output = metrics._bug_status_metrics(tmp_path, tally={
        "v1.43.2": {"closed_paths": [{"path": "docs/bugs/live.md"}]},
    })
    lines = [line for line in output.splitlines() if "live_verified=\"true\"" in line]
    assert len(lines) == 2
    assert all('verified="true",live_verified="true"' in line for line in lines)


def test_bug_status_metrics_release_is_last_label_and_aggregate_is_uncapped(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for index in range(201):
        priority = "P1" if index < 2 else "P2"
        (bugs / f"bug-{index:03d}.md").write_text(f"**Priority:** {priority}\n**Status:** Open\n")
    tally = {"v1.43.1": {"open_paths": [
        {"path": f"docs/bugs/bug-{index:03d}.md", "priority": "P1" if index < 2 else "P2"}
        for index in range(201)
    ]}}
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 201
    # agent-audit: allow assert-removed label tail now carries waiting placeholders after live_evidence
    assert all(line.split("}", 1)[0].endswith(
        'status="open",fixed_in="-",release_order="9998.9956.9998 v1.43.1",verified="-",live_verified="-",verified_at="-",live_verified_at="-",fix_sha="-",verified_sha="-",live_evidence="-",waiting_on="not stated",waiting_since="-"')
        for line in info)
    assert all("_at=" not in line for line in output.splitlines()
               if line.startswith("k3dm_bug_status_docs{"))
    assert 'k3dm_bug_status_docs{repo="k3d-manager",release="v1.43.1",priority="P1",status="open"} 2' in output
    assert 'k3dm_bug_status_docs{repo="k3d-manager",release="v1.43.1",priority="P2",status="open"} 199' in output
    assert sum(int(line.rsplit(" ", 1)[1]) for line in output.splitlines()
               if line.startswith("k3dm_bug_status_docs{")) == 201


def test_publish_bug_metrics_tallies_once_and_pushes_groups(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    calls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally",
                        lambda *_args, **_kwargs: calls.append(True) or {"releases": {"v1.43.0": _bucket()}, "fixed_in": {}})
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert len(calls) == 1
    methods = {r.full_url.rsplit("/", 1)[-1]: r.method for r in requests if getattr(r, "data", None)}
    assert methods == {"k3dm-bug-docs": "POST", "k3dm-bug-open": "PUT", "k3dm-bug-releases": "POST", "k3dm-plan-docs": "PUT"}
    open_body = next(r.data.decode() for r in requests
                     if getattr(r, "full_url", "").endswith("/metrics/job/k3dm-bug-open"))
    assert "k3dm_bug_open_info" not in open_body
    assert "k3dm_bug_open_release_docs" not in open_body


def test_publish_bug_metrics_reads_bug_texts_once(metrics, monkeypatch, tmp_path):
    calls = []
    texts = {"docs/bugs/one.md": "**Priority:** P1\n**Status:** Open\n"}
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__,
                        "_bug_texts", lambda *_args: calls.append(True) or texts)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_push_bug_group", lambda *_args, **_kwargs: True)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally", lambda *_args: None)
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert len(calls) == 1


def test_publish_bug_metrics_tally_failure_still_pushes_open(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    def boom(*_args):
        raise RuntimeError("tally failed")
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally", boom)
    assert metrics.publish_bug_metrics(tmp_path) is True
    pushed = [str(getattr(url, "full_url", url)) for url in requests if getattr(url, "data", None)]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert any("/metrics/job/k3dm-bug-open" in url for url in pushed)
    assert not any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def test_bug_status_metrics_title_fallback_truncation_and_cap(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-11-no-heading.md").write_text("**Status:** Open\n")
    (bugs / "long.md").write_text("# " + ("x" * 200) + "\n**Status:** Open\n")
    (bugs / "bad name.md").write_text("**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 2
    assert any('title="no heading"' in line for line in info)
    long_line = next(line for line in info if 'bug="long"' in line)
    assert len(long_line.split('title="', 1)[1].split('"', 1)[0]) == 120
    assert long_line.split('title="', 1)[1].split('"', 1)[0].endswith("…")
    assert 'k3dm_bug_info_skipped{repo="k3d-manager"} 1' in output
    assert 'k3dm_bug_info_truncated{repo="k3d-manager"} 0' in output


def test_bug_status_metrics_undated_and_truncated(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for index in range(1001):
        (bugs / f"bug-{index:03d}.md").write_text("**Priority:** P2\n**Status:** Open\n")
    (bugs / "undated.md").write_text("**Priority:** P2\n**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime.now(timezone.utc))
    # agent-audit: allow assert-removed metrics renamed k3dm_bug_open_info -> k3dm_bug_info, cap 200 -> 1000, fixed rows now listed
    assert output.count("k3dm_bug_info{") == 1000
    assert 'k3dm_bug_info_truncated{repo="k3d-manager"} 1' in output


def test_bug_status_metrics_filed_line_wins_and_undated_sorts_last(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-09-01-dated.md").write_text("# dated\n**Priority:** P2\n**Filed:** 2026-10-05\n**Status:** Open\n")
    (bugs / "aaa-undated.md").write_text("# undated\n**Priority:** P2\n**Status:** Open\n")
    (bugs / "2026-10-01-p1.md").write_text("# p1\n**Priority:** P1\n**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime(2026, 10, 15, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert [line.split('bug="', 1)[1].split('"', 1)[0] for line in info] == [
        "2026-10-01-p1", "2026-09-01-dated", "aaa-undated"]
    assert 'filed="2026-10-05"' in info[1] and info[1].endswith(" 10")
    assert 'filed=""' in info[2] and info[2].endswith(" -1")


def test_bug_status_metrics_with_no_docs_still_emits_counters(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    output = metrics._bug_status_metrics(tmp_path)
    assert "k3dm_bug_info{" in output
    assert 'k3dm_bug_info_skipped{repo="k3d-manager"} 0' in output
    assert 'k3dm_bug_info_truncated{repo="k3d-manager"} 0' in output


def test_bug_status_metrics_push_is_put_and_release_inventory_stays_post(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    methods = {r.full_url.rsplit("/", 1)[-1]: r.method for r in requests if getattr(r, "data", None)}
    assert methods["k3dm-bug-docs"] == "POST"
    assert methods["k3dm-bug-open"] == "PUT"
    assert methods["k3dm-bug-releases"] == "POST"
    assert methods["k3dm-plan-docs"] == "PUT"


def test_bug_status_metrics_failure_does_not_block_other_groups(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_bug_status_metrics",
                        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("boom")))
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    pushed = [str(getattr(url, "full_url", url)) for url in urls]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def _fake_git(monkeypatch, metrics, tally, tags, branch="k3d-manager-v1.43.0"):
    def run(argv, **_kwargs):
        if "tag" in argv:
            return SimpleNamespace(stdout="\n".join(tags) + "\n", returncode=0)
        if "branch" in argv:
            return SimpleNamespace(stdout=branch + "\n", returncode=0)
        raise AssertionError(argv)
    monkeypatch.setattr(metrics.subprocess, "run", run)
    monkeypatch.setitem(metrics._release_metrics.__globals__, "_tally",
                        lambda *_args, **kwargs: {"releases": tally, "fixed_in": {}}
                        if kwargs.get("full") else tally)


def _bucket(**counts):
    return {"by_priority": {p: dict(counts.get(p, {})) for p in ("P0", "P1", "P2", "P3", "unset")}}


def test_release_metrics_publishes_fixed_in_counts_and_unknown(metrics, monkeypatch, tmp_path):
    tally = {
        "v1.43.0": {"by_priority": {p: {} for p in metrics.PRIORITIES},
                     "closed_paths": [{"path": "docs/bugs/fixed-p0.md", "priority": "P0"},
                                      {"path": "docs/bugs/fixed-p1.md", "priority": "P1"}]},
        "v1.42.0": _bucket(),
    }
    _fake_git(monkeypatch, metrics, tally, ["v1.42.0"])
    fixed_in = {
        "docs/bugs/fixed-p0.md": {"release": "v1.43.0"},
        "docs/bugs/fixed-p1.md": {"release": "unknown"},
        "docs/bugs/outside.md": {"release": "v1.99.0"},
    }
    output = metrics._release_metrics(tmp_path, tally=tally, fixed_in=fixed_in)
    assert 'k3dm_bug_fixed_in_release_docs{repo="k3d-manager",release="v1.43.0",order="1",priority="P0"} 1' in output
    assert 'k3dm_bug_fixed_in_release_docs{repo="k3d-manager",release="v1.43.0",order="1",priority="P1"} 0' in output
    assert 'k3dm_bug_fixed_in_unknown_docs{repo="k3d-manager"} 1' in output
    assert 'release="v1.99.0"' not in output
    assert metrics._release_metrics(tmp_path, tally=tally, fixed_in=None).count("k3dm_bug_fixed_in_") == 0


def test_bug_status_metrics_adds_fixed_in_only_to_fixed_info(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    (bugs / "unknown-fixed.md").write_text("**Priority:** P2\n**Status:** IMPLEMENTED\n")
    (bugs / "open.md").write_text("**Priority:** P0\n**Status:** OPEN\n")
    tally = {"v1.43.0": {"closed_paths": [
        {"path": "docs/bugs/fixed.md", "priority": "P1"},
        {"path": "docs/bugs/unknown-fixed.md", "priority": "P2"}],
        "open_paths": [{"path": "docs/bugs/open.md", "priority": "P0"}]}}
    base = metrics._bug_status_metrics(tmp_path, tally=tally)
    output = metrics._bug_status_metrics(tmp_path, tally=tally, fixed_in={
        "docs/bugs/fixed.md": {"release": "v1.43.0"},
        "docs/bugs/unknown-fixed.md": {"release": "unknown"},
    })
    base_aggregates = [line for line in base.splitlines() if line.startswith("k3dm_bug_status_docs")]
    output_aggregates = [line for line in output.splitlines() if line.startswith("k3dm_bug_status_docs")]
    assert base_aggregates == output_aggregates
    fixed_lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert any('bug="fixed"' in line and 'fixed_in="v1.43.0"' in line for line in fixed_lines)
    assert any('bug="unknown-fixed"' in line and 'fixed_in="unknown"' in line for line in fixed_lines)
    assert all('fixed_in="-"' in line for line in fixed_lines if 'bug="open"' in line)


def test_bug_status_metrics_adds_commit_labels_with_guard(metrics, tmp_path):
    texts = {"docs/bugs/fixed.md": "**Priority:** P1\n**Status:** VERIFIED\n"}
    output = metrics._bug_status_metrics(tmp_path, tally={
        "v1.43.3": {"closed_paths": [{"path": "docs/bugs/fixed.md"}]},
    }, texts=texts, fixed_in={"docs/bugs/fixed.md": {
        "release": "v1.43.3", "source": "status_change", "commit": "0123456789abcdef0123456789abcdef01234567"}},
        verification_times={"docs/bugs/fixed.md": ("true", None, "abcdef0123456789")})
    assert 'fix_sha="01234567",verified_sha="abcdef01"' in output
    bad = metrics._bug_status_metrics(tmp_path, tally={
        "v1.43.3": {"closed_paths": [{"path": "docs/bugs/fixed.md"}]},
    }, texts=texts, fixed_in={"docs/bugs/fixed.md": {"release": "v1.43.3", "commit": "zz"}},
        verification_times={"docs/bugs/fixed.md": ("true", None, "zz")})
    assert 'fix_sha="-",verified_sha="-"' in bad
    assert all("_sha=" not in line for line in output.splitlines() if line.startswith("k3dm_bug_status_docs{"))


@pytest.mark.parametrize(("header", "expected"), [
    ("**Fix commit:** `a8909477` (v1.43.4 squash; note)", "a8909477"),
    ("**Fix commit:** 17c7cda5, 152f7978", "17c7cda5"),
    ("**Fix commit:** `f11e0c6e` (Claude moved the helper)", "f11e0c6e"),
    ("**Fix commit:** pending", None),
])
def test_doc_fix_commit_accepts_notes_and_lists(metrics, header, expected):
    assert metrics.doc_fix_commit(header) == expected


def test_bug_fix_sha_prefers_header_and_falls_back_safely(metrics, tmp_path):
    fixed = "**Priority:** P1\n**Status:** FIXED\n**Fix commit:** `79fab0b1`\n"
    fixed_item = {"release": "v1.43.7", "commit": "32f1ee64abcdef0123456789abcdef01234567"}
    args = {"tally": {"v1.43.7": {"closed_paths": [{"path": "docs/bugs/fixed.md"}]}},
            "fixed_in": {"docs/bugs/fixed.md": fixed_item}}
    output = metrics._bug_status_metrics(tmp_path, texts={"docs/bugs/fixed.md": fixed}, **args)
    assert 'fix_sha="79fab0b1"' in output

    for header, expected in (("**Fix commit:** f11e0c6e (a note)", "f11e0c6e"),
                             ("**Fix commit:** 17c7cda5, 152f7978", "17c7cda5")):
        text = fixed.replace("**Fix commit:** `79fab0b1`", header)
        output = metrics._bug_status_metrics(tmp_path, texts={"docs/bugs/fixed.md": text}, **args)
        assert f'fix_sha="{expected}"' in output

    for text in (fixed.replace("**Fix commit:** `79fab0b1`\n", ""),
                 fixed.replace("**Fix commit:** `79fab0b1`", "**Fix commit:** pending")):
        output = metrics._bug_status_metrics(tmp_path, texts={"docs/bugs/fixed.md": text}, **args)
        assert 'fix_sha="32f1ee64"' in output

    opened = "**Priority:** P1\n**Status:** OPEN\n**Fix commit:** f11e0c6e\n"
    output = metrics._bug_status_metrics(tmp_path, texts={"docs/bugs/open.md": opened}, tally={
        "v1.43.7": {"open_paths": [{"path": "docs/bugs/open.md"}]}
    }, fixed_in={"docs/bugs/open.md": {"commit": "f11e0c6e"}})
    assert 'fix_sha="-"' in output


def test_bug_fix_sha_reads_each_docs_own_header(metrics, tmp_path):
    with_header = "**Priority:** P3\n**Status:** FIXED\n**Fix commit:** `79fab0b1`\n"
    without_header = "**Priority:** P3\n**Status:** FIXED\n"
    texts = {"docs/bugs/2026-10-25-with-header.md": with_header,
             "docs/bugs/2026-10-25-without-header.md": without_header}
    output = metrics._bug_status_metrics(tmp_path, texts=texts, tally={
        "v1.43.7": {"closed_paths": [{"path": path} for path in texts]}
    }, fixed_in={"docs/bugs/2026-10-25-with-header.md": {"release": "v1.43.7", "commit": "aaaaaaaa11"},
                 "docs/bugs/2026-10-25-without-header.md": {"release": "v1.43.7", "commit": "bbbbbbbb22"}})
    rows = {re.search(r'bug="([^"]+)"', line).group(1): re.search(r'fix_sha="([^"]+)"', line).group(1)
            for line in output.splitlines() if line.startswith("k3dm_bug_info{")}
    assert rows == {"2026-10-25-with-header": "79fab0b1", "2026-10-25-without-header": "bbbbbbbb"}, rows


def test_release_metrics_cover_current_and_five_shipped_releases_in_order(metrics, monkeypatch, tmp_path):
    tags = ["v1.9.0", "v1.10.0", "v1.38.0", "v1.39.0", "v1.40.0", "v1.41.0", "v1.42.0", "v1.43.1", "v1.44.0", "not-a-tag"]
    tally = {"v1.43.0": _bucket(P2={"open": 3, "closed": 4}), "v1.42.0": _bucket(P1={"closed": 3}),
             "v1.43.2": _bucket(P3={"open": 2}), "v1.44.0": _bucket(P2={"open": 1}), "unknown": _bucket(P0={"open": 9})}
    _fake_git(monkeypatch, metrics, tally, tags)
    output = metrics._release_metrics(tmp_path)
    releases = []
    for line in output.splitlines():
        if line.startswith("k3dm_bug_release_docs{"):
            release = line.split('release="', 1)[1].split('"', 1)[0]
            order = line.split('order="', 1)[1].split('"', 1)[0]
            if (release, order) not in releases:
                releases.append((release, order))
    assert releases == [("v1.38.0", "0"), ("v1.39.0", "1"), ("v1.40.0", "2"), ("v1.41.0", "3"),
                        ("v1.42.0", "4"), ("v1.43.0", "5")]
    assert 'k3dm_bug_release_docs{repo="k3d-manager",release="v1.43.0",order="5",priority="P2",state="open"} 3' in output
    assert 'k3dm_bug_release_docs{repo="k3d-manager",release="v1.42.0",order="4",priority="P1",state="closed"} 3' in output
    assert output.count("k3dm_bug_release_docs{") == 6 * 15
    assert 'k3dm_bug_current_release_info{repo="k3d-manager",release="v1.43.0"} 1' in output
    assert 'k3dm_bug_later_release_open_docs{repo="k3d-manager",priority="P3"} 2' in output
    assert 'k3dm_bug_later_release_open_docs{repo="k3d-manager",priority="P2"} 1' in output
    assert 'k3dm_bug_later_release_open_docs{repo="k3d-manager",priority="P0"} 0' in output


def test_release_metrics_on_a_non_release_branch_show_only_shipped_releases(metrics, monkeypatch, tmp_path):
    _fake_git(monkeypatch, metrics, {"v1.42.0": _bucket()}, ["v1.40.0", "v1.41.0", "v1.42.0"], branch="main")
    output = metrics._release_metrics(tmp_path)
    assert "k3dm_bug_current_release_info" not in output
    assert "k3dm_bug_later_release_open_docs" not in output
    assert 'release="v1.42.0",order="2"' in output


def test_release_metrics_failure_keeps_the_inventory_push(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    def boom(*_a, **_k):
        raise metrics.subprocess.CalledProcessError(2, "bug-tally")
    root = _repo(tmp_path)
    monkeypatch.setattr(metrics.subprocess, "run", boom)
    assert metrics.publish_bug_metrics(root) is True
    pushed = [str(getattr(url, "full_url", url)) for url in urls]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert not any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def test_release_metrics_push_to_their_own_group(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    root = _repo(tmp_path)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket(P2={"open": 1})}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(root) is True
    posts = {str(r.full_url): r.data.decode() for r in requests if getattr(r, "data", None)}
    releases = [body for url, body in posts.items() if url.endswith("/metrics/job/k3dm-bug-releases")]
    inventory = [body for url, body in posts.items() if url.endswith("/metrics/job/k3dm-bug-docs")]
    assert len(releases) == 1 and "k3dm_bug_release_docs{" in releases[0]
    assert len(inventory) == 1 and "k3dm_bug_release_docs" not in inventory[0]


# agent-audit: allow assert-removed every removed assertion is restated with the new leading repo="k3d-manager" label
def _lib_foundation(tmp_path):
    origin = tmp_path / "lf-origin.git"
    clone = tmp_path / "lf"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    _git_repo(clone, {"lf-open.md": "# lf open\n\n**Branch:** k3d-manager-v1.40.0\n**Priority:** P1\n**Status:** OPEN\n"})
    subprocess.run(["git", "tag", "v0.1.0"], cwd=clone, check=True)
    subprocess.run(["git", "remote", "add", "origin", str(origin)], cwd=clone, check=True)
    subprocess.run(["git", "push", "-q", "origin", "main", "--tags"], cwd=clone, check=True)
    subprocess.run(["git", "fetch", "-q", "origin"], cwd=clone, check=True)
    return clone


def _publish_both(metrics, monkeypatch, tmp_path, lib_dir, lf_tally_error=False):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen",
                        lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    monkeypatch.setenv("K3DM_LIB_FOUNDATION_DIR", str(lib_dir))
    real_tally = metrics.publish_bug_metrics.__globals__["_tally"]
    if lf_tally_error:
        def real_tally(*_args):
            raise RuntimeError("lib-foundation tally failed")
    km_tally = {"releases": {"v1.43.0": _bucket()}, "fixed_in": {}}
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally",
                        lambda root, ref=None, full=False, repo="k3d-manager", repo_dir=None:
                        real_tally(root, ref, full, repo, repo_dir) if repo == "lib-foundation"
                        else (km_tally if full else km_tally["releases"]))
    km = tmp_path / "km"
    _git_repo(km, {"km-open.md": "# km open\n\n**Priority:** P2\n**Status:** OPEN\n"})
    result = metrics.publish_bug_metrics(km)
    pushes = {r.full_url.split("/metrics/job/", 1)[1]: (r.method, r.data.decode())
              for r in requests if getattr(r, "data", None)}
    return result, pushes


def test_lib_foundation_series_carry_repo_and_push_to_their_own_instance(metrics, monkeypatch, tmp_path):
    result, pushes = _publish_both(metrics, monkeypatch, tmp_path, _lib_foundation(tmp_path))
    assert result is True
    assert {job: method for job, (method, _body) in pushes.items()} == {
        "k3dm-bug-docs": "POST", "k3dm-bug-open": "PUT", "k3dm-bug-releases": "POST",
        "k3dm-plan-docs": "PUT",
        "k3dm-bug-open-history/instance/k3d-manager": "PUT",
        "k3dm-bug-docs/instance/lib-foundation": "POST",
        "k3dm-bug-open/instance/lib-foundation": "PUT",
        "k3dm-bug-releases/instance/lib-foundation": "POST",
        "k3dm-bug-open-history/instance/lib-foundation": "PUT",
    }  # agent-audit: allow assert-removed exact-set asserts extended with k3dm-bug-open-history
    for job, (_method, body) in pushes.items():
        if job == "k3dm-plan-docs":
            assert 'k3dm_plan_info_skipped{repo="k3d-manager"}' in body
            continue
        repo = "lib-foundation" if job.endswith("/instance/lib-foundation") else "k3d-manager"
        series = [line for line in body.splitlines() if line.startswith("k3dm_bug")]
        assert series
        assert all(line.split("{", 1)[1].startswith(f'repo="{repo}"') for line in series), job
    lf_open = pushes["k3dm-bug-open/instance/lib-foundation"][1]
    lf_releases = pushes["k3dm-bug-releases/instance/lib-foundation"][1]
    assert 'bug="lf-open"' in lf_open and "km-open" not in lf_open
    assert 'release="v0.1.0"' in lf_open and 'release="v1.40.0"' not in lf_open
    assert 'k3dm_bug_release_docs{repo="lib-foundation",release="v0.1.0",order="0",priority="P1",state="open"} 1' in lf_releases
    assert 'release="v1.' not in lf_releases
    assert "k3dm_bug_current_release_info" not in lf_releases


def _break_fetch(clone):
    subprocess.run(["git", "remote", "set-url", "origin", str(clone.parent / "gone.git")], cwd=clone, check=True)


def _drop_origin(clone):
    subprocess.run(["git", "remote", "remove", "origin"], cwd=clone, check=True)


@pytest.mark.parametrize("breakage", ["missing_dir", "fetch_fails", "no_origin_main", "tally_fails"])
def test_lib_foundation_failures_leave_k3d_manager_pushes_and_result(metrics, monkeypatch, tmp_path, breakage, capsys):
    clone = _lib_foundation(tmp_path)
    if breakage == "missing_dir":
        lib_dir = tmp_path / "absent"
    elif breakage == "tally_fails":
        lib_dir = clone
    else:
        (_break_fetch if breakage == "fetch_fails" else _drop_origin)(clone)
        lib_dir = clone
    result, pushes = _publish_both(metrics, monkeypatch, tmp_path, lib_dir,
                                   lf_tally_error=breakage == "tally_fails")
    assert result is True
    km_jobs = {job for job in pushes if "/instance/" not in job}
    assert km_jobs == {"k3dm-bug-docs", "k3dm-bug-open", "k3dm-bug-releases", "k3dm-plan-docs"}  # agent-audit: allow assert-removed exact-set asserts extended with k3dm-plan-docs
    lf_jobs = {job for job in pushes if job.endswith("/instance/lib-foundation")}
    assert lf_jobs == {
        "missing_dir": set(), "no_origin_main": set(),
        "tally_fails": {"k3dm-bug-docs/instance/lib-foundation", "k3dm-bug-open-history/instance/lib-foundation"},
        "fetch_fails": {"k3dm-bug-docs/instance/lib-foundation", "k3dm-bug-open/instance/lib-foundation",
                        "k3dm-bug-releases/instance/lib-foundation", "k3dm-bug-open-history/instance/lib-foundation"},
    }[breakage]  # agent-audit: allow assert-removed exact-set asserts extended with k3dm-bug-open-history
    assert "lib-foundation" in capsys.readouterr().err


def test_plan_push_failure_is_nonfatal(metrics, monkeypatch, tmp_path, capsys):
    pushed=[]
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_push_bug_group",
                        lambda job, payload, method="POST": pushed.append((job, method)) or True)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_publish_lib_foundation_bugs", lambda: None)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert ("k3dm-plan-docs", "PUT") in pushed
    pushed.clear()
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_plan_metrics",
                        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("plan parse")))
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert any(job == "k3dm-bug-docs" for job, _method in pushed)
    assert "plan metrics skipped (non-fatal): plan parse" in capsys.readouterr().err


def test_not_before_floor_is_midnight_in_the_operator_time_zone(metrics, monkeypatch):
    from zoneinfo import ZoneInfo
    monkeypatch.delenv("K3DM_FORECAST_TZ", raising=False)
    cadence = {"p25": 86400, "p50": 86400, "p75": 86400,
               "last_ts": int(datetime(2026, 10, 25, tzinfo=timezone.utc).timestamp())}
    row = metrics._forecast([{"version": "v1.0.1", "not_before": "2026-11-03"}], [], cadence, 0)[0]
    pacific = ZoneInfo("America/Los_Angeles")
    for bound in ("low", "mid", "high"):
        assert datetime.fromtimestamp(row[bound], pacific).strftime("%Y-%m-%d %H:%M") == "2026-11-03 00:00"


def test_bug_open_history_across_dates_and_commits_e1(metrics, tmp_path):
    # E1 proves [M1, M2, M3, N1, N2]
    # Fixture asserts scratch repo is not the real repository tree
    assert tmp_path.resolve() != ROOT.resolve()
    assert not (tmp_path / ".git").exists() or (tmp_path / ".git").resolve() != (ROOT / ".git").resolve()

    repo = tmp_path / "repo"
    bugs = repo / "docs/bugs"
    bugs.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)

    # Day 1: 2026-11-01T10:00:00Z
    (bugs / "bug1.md").write_text("# bug1\n**Priority:** P1\n**Status:** Open\n", encoding="utf-8")
    (bugs / "bug2.md").write_text("# bug2\n**Priority:** P2\n**Status:** Open\n", encoding="utf-8")
    _commit(repo, "day 1 commit", "2026-11-01T10:00:00Z")

    # Day 2: 2026-11-02T15:00:00Z
    (bugs / "bug3.md").write_text("# bug3\n**Priority:** P0\n**Status:** Open\n", encoding="utf-8")
    _commit(repo, "day 2 commit", "2026-11-02T15:00:00Z")

    # Day 3: doc closed on day 3, plus positive control commit at 23:59:58Z
    (bugs / "bug1.md").write_text("# bug1\n**Priority:** P1\n**Status:** FIXED\n", encoding="utf-8")
    _commit(repo, "day 3 close bug1", "2026-11-03T12:00:00Z")
    (bugs / "bug4.md").write_text("# bug4\n**Priority:** P3\n**Status:** Open\n", encoding="utf-8")
    _commit(repo, "day 3 late commit 23:59:58Z", "2026-11-03T23:59:58Z")

    # Day 4: commit at 00:00:01Z on day 4
    (bugs / "bug5.md").write_text("# bug5\n**Priority:** P1\n**Status:** Open\n", encoding="utf-8")
    _commit(repo, "day 4 early commit 00:00:01Z", "2026-11-04T00:00:01Z")

    now = datetime(2026, 11, 4, 12, 0, tzinfo=timezone.utc)
    output = metrics._bug_open_history(repo, "main", days=5, now=now)

    # N1: a date before the ref's first commit emits no sample (no zero rows invented for pre-history)
    assert 'date="2026-10-31"' not in output
    # N1 positive control: a date on or after the first commit does emit samples
    assert 'date="2026-11-01"' in output

    # M3: every emitted date carries all five priorities (P0 P1 P2 P3 unset), zeros included
    for date_str in ("2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"):
        for priority in ("P0", "P1", "P2", "P3", "unset"):
            pattern = f'k3dm_bug_open_history{{repo="k3d-manager",priority="{priority}",date="{date_str}"}} '
            assert pattern in output

    # N2: a commit made after a date's 23:59:59Z never changes that date's counts
    # bug5 committed on 2026-11-04T00:00:01Z must NOT be counted on 2026-11-03
    # on Day 3: bug1 is fixed, bug5 not added -> P1 is 0
    assert 'k3dm_bug_open_history{repo="k3d-manager",priority="P1",date="2026-11-03"} 0' in output
    # N2 positive control: commit at 23:59:58Z (bug4) does change day 3
    assert 'k3dm_bug_open_history{repo="k3d-manager",priority="P3",date="2026-11-03"} 1' in output
    # Day 4 includes bug5 -> P1 is 1
    assert 'k3dm_bug_open_history{repo="k3d-manager",priority="P1",date="2026-11-04"} 1' in output

    # M1 & M2: for today's date the history equals the current k3dm_bug_docs{state="open"} counts on the same ref
    current_inventory = metrics._bug_metrics(repo, "main")
    for priority in ("P0", "P1", "P2", "P3", "unset"):
        history_val = re.search(rf'k3dm_bug_open_history\{{repo="k3d-manager",priority="{priority}",date="2026-11-04"\}} (\d+)', output).group(1)
        current_val = re.search(rf'k3dm_bug_docs\{{repo="k3d-manager",priority="{priority}",state="open"\}} (\d+)', current_inventory).group(1)
        assert history_val == current_val


def test_bug_open_history_push_and_failure_isolation_e2(metrics, monkeypatch, tmp_path, capsys):
    # E2 proves [M4, N3, N4, N5]
    # N5: tests never push to the live hub Pushgateway (assert URL points to stub/127.0.0.1:9 first)
    monkeypatch.setenv("K3DM_VECTORDB_PUSHGATEWAY_URL", "http://127.0.0.1:9/stub")
    push_url = metrics._pushgateway_url()
    assert push_url.startswith("http://127.0.0.1:9") or "stub" in push_url

    pushed = []
    monkeypatch.setitem(
        metrics.publish_bug_metrics.__globals__,
        "_push_bug_group",
        lambda job, payload, method="POST", instance=None: pushed.append((job, method, instance, payload)) or True
    )

    km = tmp_path / "km"
    _git_repo(km, {"km-open.md": "# km open\n**Priority:** P1\n**Status:** OPEN\n"})
    lf = _lib_foundation(tmp_path)
    monkeypatch.setenv("K3DM_LIB_FOUNDATION_DIR", str(lf))
    km_tally = {"releases": {"v1.43.0": _bucket()}, "fixed_in": {}}
    monkeypatch.setitem(
        metrics.publish_bug_metrics.__globals__,
        "_tally",
        lambda root, ref=None, full=False, repo="k3d-manager", repo_dir=None: km_tally if full else km_tally["releases"]
    )

    # 1. Normal run (no failure):
    assert metrics.publish_bug_metrics(km) is True

    # M4: k3dm-bug-open-history pushed with PUT once for k3d-manager and once for lib-foundation (instance = repo)
    calls = [(job, method, instance) for job, method, instance, _payload in pushed]
    assert ("k3dm-bug-open-history", "PUT", "k3d-manager") in calls
    assert ("k3dm-bug-open-history", "PUT", "lib-foundation") in calls

    # N3 positive control: run with no failure pushes dates
    km_history_body = next(payload for job, _method, inst, payload in pushed if job == "k3dm-bug-open-history" and inst == "k3d-manager")
    assert 'k3dm_bug_open_history{repo="k3d-manager"' in km_history_body

    # N4: existing groups and series keep their names, labels and values on the same fixture
    assert ("k3dm-bug-docs", "POST", None) in calls
    assert ("k3dm-bug-open", "PUT", None) in calls
    assert ("k3dm-bug-releases", "POST", None) in calls
    assert ("k3dm-plan-docs", "PUT", None) in calls

    # 2. Failure run: cat-file call fails for one date
    pushed.clear()
    real_bug_texts = metrics.publish_bug_metrics.__globals__["_bug_texts"]

    def failing_bug_texts(root, ref=None, repo="k3d-manager"):
        # Fail during history scan when called on specific commit ref
        if ref and len(ref) == 40:
            raise subprocess.CalledProcessError(1, ["git", "cat-file", "--batch"], stderr="simulated cat-file failure")
        return real_bug_texts(root, ref, repo=repo)

    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_bug_texts", failing_bug_texts)
    assert metrics.publish_bug_metrics(km) is True

    failure_calls = [(job, method, instance) for job, method, instance, _payload in pushed]
    # N3: failure while computing any date pushes nothing for k3dm-bug-open-history
    assert not any(job == "k3dm-bug-open-history" and inst == "k3d-manager" for job, _m, inst in failure_calls)
    # N3: does not stop other bug groups from publishing
    assert any(job == "k3dm-bug-docs" and inst is None for job, _m, inst in failure_calls)
    assert any(job == "k3dm-bug-open" and inst is None for job, _m, inst in failure_calls)
    assert any(job == "k3dm-bug-releases" and inst is None for job, _m, inst in failure_calls)
    err = capsys.readouterr().err
    assert "bug open history skipped (non-fatal):" in err


def test_folded_row_and_count_have_unfolded_control(metrics, monkeypatch, tmp_path):
    root = tmp_path / "fixture-repo"
    (root / "docs").mkdir(parents=True)
    assert root.resolve() != ROOT.resolve()
    path = root / "docs/release-milestones.json"
    items = [{"version": "v1.0.1", "state": "folded"},
             {"version": "v1.0.2", "target": True}]
    globals_ = metrics._forecast_metrics.__globals__
    current_release = globals_["_current_release"]
    monkeypatch.setitem(globals_, "_release_tags", lambda _root: [("v1.0.0", 0)])
    monkeypatch.setitem(globals_, "_cadence", lambda _tags: {"p25": 10, "p50": 10, "p75": 10, "last_ts": 0, "gaps": 6})
    monkeypatch.setitem(globals_, "_current_release", lambda *_args: None)
    def output(entries):
        path.write_text(json.dumps({"milestones": entries}))
        return metrics._forecast_metrics(root, now=15)
    folded = output(items)
    absent = output(items[1:])
    assert folded == absent
    assert 'version="v1.0.1"' not in folded
    assert 'k3dm_release_milestones_remaining{repo="k3d-manager"} 1' in folded
    control = output([{"version": "v1.0.1"}, items[1]])
    assert 'version="v1.0.1"' in control
    assert 'k3dm_release_milestones_remaining{repo="k3d-manager"} 2' in control
    subprocess.run(["git", "init", "-q", "-b", "k3d-manager-v1.0.2"], cwd=root, check=True)
    monkeypatch.setitem(globals_, "_current_release", current_release)
    current = output(items)
    assert 'state="in_progress"' in current
    assert 'version="v1.0.2",bound="mid"' in current


def test_current_release_and_following_are_not_overdue(metrics, monkeypatch, tmp_path):
    root = tmp_path / "fixture-repo"
    (root / "docs").mkdir(parents=True)
    assert root.resolve() != ROOT.resolve()
    subprocess.run(["git", "init", "-q", "-b", "k3d-manager-v1.0.1"], cwd=root, check=True)
    items = [{"version": "v1.0.1"}, {"version": "v1.0.2", "target": True}]
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": items}))
    globals_ = metrics._forecast_metrics.__globals__
    monkeypatch.setitem(globals_, "_release_tags", lambda _root: [])
    monkeypatch.setitem(globals_, "_cadence", lambda _tags: {
        "p25": 10, "p50": 20, "p75": 30, "last_ts": 0, "gaps": 6})
    def info(output):
        return [line for line in output.splitlines()
                if line.startswith("k3dm_release_milestone_info{")]
    subprocess.run(["git", "symbolic-ref", "HEAD", "refs/heads/main"], cwd=root, check=True)
    control = info(metrics._forecast_metrics(root, now=100))
    assert len(control) == 2 and all('overdue="true"' in row for row in control)
    subprocess.run(["git", "symbolic-ref", "HEAD", "refs/heads/k3d-manager-v1.0.1"],
                   cwd=root, check=True)
    output = metrics._forecast_metrics(root, now=100)
    rows = info(output)
    assert 'state="in_progress"' in rows[0]
    assert all('overdue="false"' in row for row in rows)
    for version, bounds in (("v1.0.1", (100, 100, 100)), ("v1.0.2", (110, 120, 130))):
        for bound, value in zip(("low", "mid", "high"), bounds):
            assert (f'k3dm_release_milestone_forecast_seconds{{repo="k3d-manager",'
                    f'version="{version}",bound="{bound}"}} {value}') in output
    cadence = {"p25": 10, "p50": 20, "p75": 30, "last_ts": 0}
    floored = metrics._forecast([{**items[0], "not_before": "2026-01-01"}],
                                [], cadence, 100, current_release="v1.0.1")[0]
    assert floored["state"] == "in_progress" and floored["low"] > 100
    blocked = metrics._forecast([{**items[0], "blocked_by": "external"}, items[1]],
                                [], cadence, 100, current_release="v1.0.1")
    assert [row["state"] for row in blocked] == ["blocked", "after_blocked"]


@pytest.mark.parametrize("item", [{"version": "v1.0.1", "state": "unknown"},
                                  {"version": "v1.0.1", "state": "folded", "target": True}])
def test_load_milestones_rejects_invalid_state_and_folded_target(metrics, tmp_path, item):
    root = tmp_path / "fixture-repo"
    (root / "docs").mkdir(parents=True)
    assert root.resolve() != ROOT.resolve()
    items = [item] if item.get("target") else [item, {"version": "v1.0.2", "target": True}]
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": items}))
    with pytest.raises(ValueError):
        metrics._load_milestones(root)
