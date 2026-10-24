import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from pathlib import Path
import pytest

SCRIPT = Path(__file__).parents[3] / "bin" / "k3dm-dispatch-metrics"
SPEC = importlib.util.spec_from_loader("dispatch_metrics", importlib.machinery.SourceFileLoader("dispatch_metrics", str(SCRIPT)))
dispatch_metrics = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dispatch_metrics
SPEC.loader.exec_module(dispatch_metrics)


def event(ts, name, slug="one", **extra):
    return {"ts": ts, "event": name, "version": "9.9.9", "slug": slug, **extra}


def test_windows_latest_resume_and_malformed_lines(tmp_path):
    now = 1_000_000
    rows = [
        event(now - 100, "start", "one"), event(now - 90, "codex_exit", "one", tokens=12345),
        event(now - 80, "codex_exit", "one", tokens=20000),
        event(now - 70, "land", "one", verifier_lines=4, wait_seconds=120),
        event(now - 200, "start", "two"), event(now - 190, "codex_exit", "two", tokens=100),
        event(now - 180, "land_refused", "two", reason="tests"),
        event(now - 40, "start", "three"), event(now - 30, "codex_exit", "three", tokens=None),
        event(now - 20, "start", "four"),
        event(now - 60, "start", "five"), event(now - 50, "codex_exit", "five", tokens=1),
        event(now - 10, "resume", "five", n=2),
        event(now - 40 * 86400, "land", "old", verifier_lines=99, wait_seconds=60),
    ]
    ledger = tmp_path / "ledger.jsonl"
    ledger.write_text("\n".join(json.dumps(row) for row in rows) + "\nnot json\n")
    events, bad = dispatch_metrics.read_ledger(ledger)
    assert bad == 1
    output = dispatch_metrics.render(events, bad, now)
    assert 'k3dm_dispatch_landed{window="1d"} 1' in output
    assert 'k3dm_dispatch_land_attempts{window="1d",result="tests"} 1' in output
    assert 'k3dm_dispatch_codex_tokens_per_landed{window="1d"} 20000.0' in output
    assert 'k3dm_dispatch_verifier_lines_per_landed{window="1d"} 4.0' in output
    assert 'k3dm_dispatch_wait_minutes_per_landed{window="1d"} 2.0' in output
    assert 'k3dm_dispatch_landed{window="30d"} 1' in output
    assert 'k3dm_dispatch_landed{window="7d"} 1' in output
    assert 'k3dm_dispatch_land_attempts{window="7d",result="landed"} 1' in output
    assert "k3dm_dispatch_running 2\n" in output
    assert "k3dm_dispatch_awaiting_land 2\n" in output
    assert 'k3dm_dispatch_running{' not in output


def test_dry_run_does_not_open_connection(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path))
    monkeypatch.setattr(dispatch_metrics.urllib.request, "urlopen", lambda *_: (_ for _ in ()).throw(AssertionError()))
    # agent-audit: allow assert-removed dry-run call now passes --codex-home and --prices
    assert dispatch_metrics.main(["--dry-run", "--codex-home", str(tmp_path / "codex"),
                                  "--prices", str(tmp_path / "prices-missing.json")]) == 0
    assert "k3dm_dispatch_ledger_timestamp_seconds" in capsys.readouterr().out


def test_slug_only_in_task_series():
    output = dispatch_metrics.render([
        event(1, "start", "secret-slug"),
        event(2, "codex_exit", "secret-slug", tokens=10),
        event(3, "land", "secret-slug"),
        event(4, "start", "pending-slug"),
    ], 0, 100)
    # agent-audit: allow assert-removed test_render_has_no_slug replaced per spec; both halves kept here
    assert "pending-slug" not in output
    assert 'slug="secret-slug"' in output
    assert all("secret-slug" not in line or "k3dm_dispatch_task_" in line
               for line in output.splitlines())


def test_per_task_values():
    output = dispatch_metrics.render([
        event(0, "start"), event(100, "codex_exit", tokens=10),
        event(150, "resume"), event(250, "codex_exit", tokens=30), event(400, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one"} 30' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one"} 200' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one"} 400' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one"} 2' in output
    assert 'k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 6.666666666666667' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"} 3.3333333333333335' in output


def test_task_spec_uses_latest_start_and_is_emitted_for_each_scope():
    output = dispatch_metrics.render([
        event(1, "start", spec="docs/plans/old.md"), event(2, "start", spec="docs/bugs/2026-10-23-x.md"),
        event(3, "codex_exit", tokens=1), event(4, "land"),
    ], 0, 10)
    for window in ("1d", "7d", "30d", "v9.9.9"):
        assert (f'k3dm_dispatch_task_spec{{window="{window}",version="9.9.9",slug="one",'
                'spec="docs/bugs/2026-10-23-x.md"} 1') in output
    assert 'spec="docs/plans/old.md"' not in output


@pytest.mark.parametrize("spec", [None, "../etc/passwd", "docs/plans/a b.md"])
def test_invalid_or_missing_task_spec_is_omitted_without_hiding_other_series(spec):
    extra = {} if spec is None else {"spec": spec}
    output = dispatch_metrics.render([
        event(1, "start", **extra), event(2, "codex_exit", tokens=4), event(3, "land"),
        event(1, "start", "valid", spec="docs/plans/v1.43.5-valid.md"),
        event(2, "codex_exit", "valid", tokens=5), event(3, "land", "valid"),
    ], 0, 10)
    assert 'slug="one",spec=' not in output
    assert 'slug="valid",spec="docs/plans/v1.43.5-valid.md"} 1' in output
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one"} 4' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one"} 2' in output


def test_landed_task_without_exit_omits_codex_samples_but_keeps_elapsed():
    output = dispatch_metrics.render([
        event(100, "start"), event(399, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one"} 299' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one"}' not in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one"}' not in output
    assert 'k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 4.983333333333333' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"}' not in output


def test_recorded_exit_keeps_codex_samples_including_zero_duration():
    output = dispatch_metrics.render([
        event(100, "start"), event(100, "codex_exit", tokens=0), event(399, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one"} 0' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one"} 1' in output
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one"} 0' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"} 0.0' in output


def test_exit_without_launch_adds_nothing():
    output = dispatch_metrics.render([
        event(0, "start"), event(100, "codex_exit", tokens=10),
        event(101, "codex_exit", tokens=20), event(200, "land"),
    ], 0, 200)
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one"} 100' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one"} 2' in output


def test_invalid_label_values_skipped():
    output = dispatch_metrics.render([
        event(1, "start", "bad slug"), event(2, "codex_exit", "bad slug"),
        event(3, "land", "bad slug"),
        {"ts": 1, "event": "start", "version": "latest", "slug": "good"},
        {"ts": 2, "event": "codex_exit", "version": "latest", "slug": "good"},
        {"ts": 3, "event": "land", "version": "latest", "slug": "good"},
    ], 0, 100)
    assert 'k3dm_dispatch_task_skipped{window="1d"} 2' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="bad slug"}' not in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="latest",slug="good"}' not in output


def test_per_plan_dispatch_state_uses_latest_started_task():
    events = [
        event(1, "start", "old", spec="docs/plans/v1.43.5-a.md"),
        event(2, "codex_exit", "old", exit=0), event(3, "land", "old"),
        event(4, "start", "new", spec="docs/plans/v1.43.5-a.md"),
        event(5, "codex_exit", "new", exit=0),
        event(6, "start", "bug", spec="docs/bugs/2026-10-17-x.md"),
        event(7, "start", "legacy"),
    ]
    output = dispatch_metrics.render(events, 0, 100)
    assert 'k3dm_dispatch_plan_state{plan="v1.43.5-a",version="9.9.9",slug="new",dispatch_state="awaiting_land"} 1' in output
    assert "k3dm_dispatch_plan_state_skipped 1" in output
    assert 'plan="legacy"' not in output


@pytest.mark.parametrize(("events", "expected"), [
    ([event(1,"start" )], "running"),
    ([event(1,"start"),event(2,"codex_exit",exit=1)], "codex_failed"),
    ([event(1,"start"),event(2,"codex_exit",exit=0)], "awaiting_land"),
    ([event(1,"start"),event(2,"codex_exit",exit=1),event(3,"land_refused")], "refused"),
    ([event(1,"start"),event(2,"codex_exit",exit=1),event(3,"land_refused"),event(4,"resume")], "running"),
    ([event(1,"start"),event(2,"land")], "landed"),
    ([event(1,"start"),event(2,"abandon")], "abandoned"),
])
def test_dispatch_state_table(events, expected):
    assert dispatch_metrics._dispatch_state(events) == expected


def test_task_cap():
    events = []
    for index in range(51):
        slug = f"task-{index}"
        events.extend([event(index, "start", slug), event(index + 100, "land", slug)])
    output = dispatch_metrics.render(events, 0, 1000)
    # agent-audit: allow assert-removed expected run count excludes tasks with no codex_exit
    assert output.count('k3dm_dispatch_task_runs{window="1d"') == 0
    assert output.count('k3dm_dispatch_task_elapsed_seconds{window="1d"') == 50
    assert 'slug="task-0"' not in output
    assert 'k3dm_dispatch_task_truncated{window="1d"} 1' in output
    assert 'k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 1.6666666666666667' in output


def _rework(output, window, cause):
    prefix = f'k3dm_dispatch_rework_landed{{window="{window}",cause="{cause}"}} '
    return int(next(line for line in output.splitlines() if line.startswith(prefix))[len(prefix):])


def test_rework_counts_each_cause_and_ratio():
    output = dispatch_metrics.render([
        event(0, "start", "rerun"), event(10, "codex_exit", "rerun"),
        event(20, "resume", "rerun"), event(30, "codex_exit", "rerun"), event(40, "land", "rerun", verifier_lines=0),
        event(0, "start", "tests"), event(10, "codex_exit", "tests"),
        event(20, "land_refused", "tests", reason="tests"), event(40, "land", "tests", verifier_lines=0),
        event(0, "start", "edited"), event(10, "codex_exit", "edited"), event(40, "land", "edited", verifier_lines=7),
        event(0, "start", "clean"), event(10, "codex_exit", "clean"), event(40, "land", "clean", verifier_lines=0),
    ], 0, 100)
    assert _rework(output, "1d", "rerun") == 1
    assert _rework(output, "1d", "tests") == 1
    assert _rework(output, "1d", "claude_edit") == 1
    assert _rework(output, "1d", "any") == 3
    assert 'k3dm_dispatch_rework_ratio{window="1d"} 0.75\n' in output


def test_rebase_and_scope_refusals_are_not_rework():
    output = dispatch_metrics.render([
        event(0, "start"), event(10, "codex_exit"),
        event(20, "land_refused", reason="rebase"), event(25, "land_refused", reason="scope"),
        event(40, "land", verifier_lines=0),
    ], 0, 100)
    for cause in ("rerun", "tests", "claude_edit", "any"):
        assert _rework(output, "30d", cause) == 0
    assert 'k3dm_dispatch_rework_ratio{window="30d"} 0.0\n' in output


def test_rework_ratio_absent_without_landed_spec():
    output = dispatch_metrics.render([event(0, "start"), event(10, "codex_exit")], 0, 100)
    assert "k3dm_dispatch_rework_ratio" not in output
    assert _rework(output, "7d", "any") == 0


def test_time_window_output_matches_pre_release_scope_golden():
    now = 1_000_000
    rows = [
        event(now - 100, "start", "one"), event(now - 90, "codex_exit", "one", tokens=12345),
        event(now - 80, "codex_exit", "one", tokens=20000),
        event(now - 70, "land", "one", verifier_lines=4, wait_seconds=120),
        event(now - 200, "start", "two"), event(now - 190, "codex_exit", "two", tokens=100),
        event(now - 180, "land_refused", "two", reason="tests"),
        event(now - 40, "start", "three"), event(now - 30, "codex_exit", "three", tokens=None),
        event(now - 20, "start", "four"),
        event(now - 60, "start", "five"), event(now - 50, "codex_exit", "five", tokens=1),
        event(now - 10, "resume", "five", n=2),
        event(now - 40 * 86400, "land", "old", verifier_lines=99, wait_seconds=60),
    ]
    output = dispatch_metrics.render(rows, 1, now)
    legacy = ("k3dm_dispatch_landed", "k3dm_dispatch_land_attempts", "k3dm_dispatch_codex_tokens_per_landed",
              "k3dm_dispatch_verifier_lines_per_landed", "k3dm_dispatch_wait_minutes_per_landed",
              "k3dm_dispatch_elapsed_minutes_per_landed", "k3dm_dispatch_codex_minutes_per_landed",
              "k3dm_dispatch_rework_landed", "k3dm_dispatch_rework_ratio", "k3dm_dispatch_task_")
    actual = "\n".join(line for line in output.splitlines() if line.startswith(legacy) and
                        'window="' in line and any(f'window="{window}"' in line for window in ("1d", "7d", "30d")))
    expected = '''k3dm_dispatch_landed{window="1d"} 1
k3dm_dispatch_land_attempts{window="1d",result="landed"} 1
k3dm_dispatch_land_attempts{window="1d",result="tests"} 1
k3dm_dispatch_land_attempts{window="1d",result="scope"} 0
k3dm_dispatch_land_attempts{window="1d",result="rebase"} 0
k3dm_dispatch_codex_tokens_per_landed{window="1d"} 20000.0
k3dm_dispatch_verifier_lines_per_landed{window="1d"} 4.0
k3dm_dispatch_wait_minutes_per_landed{window="1d"} 2.0
k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 0.5
k3dm_dispatch_codex_minutes_per_landed{window="1d"} 0.16666666666666666
k3dm_dispatch_rework_landed{window="1d",cause="rerun"} 1
k3dm_dispatch_rework_landed{window="1d",cause="tests"} 0
k3dm_dispatch_rework_landed{window="1d",cause="claude_edit"} 1
k3dm_dispatch_rework_landed{window="1d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="1d"} 1.0
k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one"} 20000
k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one"} 10
k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one"} 30
k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one"} 2
k3dm_dispatch_task_skipped{window="1d"} 0
k3dm_dispatch_task_truncated{window="1d"} 0
k3dm_dispatch_landed{window="7d"} 1
k3dm_dispatch_land_attempts{window="7d",result="landed"} 1
k3dm_dispatch_land_attempts{window="7d",result="tests"} 1
k3dm_dispatch_land_attempts{window="7d",result="scope"} 0
k3dm_dispatch_land_attempts{window="7d",result="rebase"} 0
k3dm_dispatch_codex_tokens_per_landed{window="7d"} 20000.0
k3dm_dispatch_verifier_lines_per_landed{window="7d"} 4.0
k3dm_dispatch_wait_minutes_per_landed{window="7d"} 2.0
k3dm_dispatch_elapsed_minutes_per_landed{window="7d"} 0.5
k3dm_dispatch_codex_minutes_per_landed{window="7d"} 0.16666666666666666
k3dm_dispatch_rework_landed{window="7d",cause="rerun"} 1
k3dm_dispatch_rework_landed{window="7d",cause="tests"} 0
k3dm_dispatch_rework_landed{window="7d",cause="claude_edit"} 1
k3dm_dispatch_rework_landed{window="7d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="7d"} 1.0
k3dm_dispatch_task_codex_tokens{window="7d",version="9.9.9",slug="one"} 20000
k3dm_dispatch_task_codex_seconds{window="7d",version="9.9.9",slug="one"} 10
k3dm_dispatch_task_elapsed_seconds{window="7d",version="9.9.9",slug="one"} 30
k3dm_dispatch_task_runs{window="7d",version="9.9.9",slug="one"} 2
k3dm_dispatch_task_skipped{window="7d"} 0
k3dm_dispatch_task_truncated{window="7d"} 0
k3dm_dispatch_landed{window="30d"} 1
k3dm_dispatch_land_attempts{window="30d",result="landed"} 1
k3dm_dispatch_land_attempts{window="30d",result="tests"} 1
k3dm_dispatch_land_attempts{window="30d",result="scope"} 0
k3dm_dispatch_land_attempts{window="30d",result="rebase"} 0
k3dm_dispatch_codex_tokens_per_landed{window="30d"} 20000.0
k3dm_dispatch_verifier_lines_per_landed{window="30d"} 4.0
k3dm_dispatch_wait_minutes_per_landed{window="30d"} 2.0
k3dm_dispatch_elapsed_minutes_per_landed{window="30d"} 0.5
k3dm_dispatch_codex_minutes_per_landed{window="30d"} 0.16666666666666666
k3dm_dispatch_rework_landed{window="30d",cause="rerun"} 1
k3dm_dispatch_rework_landed{window="30d",cause="tests"} 0
k3dm_dispatch_rework_landed{window="30d",cause="claude_edit"} 1
k3dm_dispatch_rework_landed{window="30d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="30d"} 1.0
k3dm_dispatch_task_codex_tokens{window="30d",version="9.9.9",slug="one"} 20000
k3dm_dispatch_task_codex_seconds{window="30d",version="9.9.9",slug="one"} 10
k3dm_dispatch_task_elapsed_seconds{window="30d",version="9.9.9",slug="one"} 30
k3dm_dispatch_task_runs{window="30d",version="9.9.9",slug="one"} 2
k3dm_dispatch_task_skipped{window="30d"} 0
k3dm_dispatch_task_truncated{window="30d"} 0'''
    assert actual == expected
    first_window = next(index for index, line in enumerate(output.splitlines()) if 'window="' in line)
    last_time_window = max(index for index, line in enumerate(output.splitlines())
                           if any(f'window="{window}"' in line for window in ("1d", "7d", "30d")))
    first_release = next(index for index, line in enumerate(output.splitlines()) if 'window="v' in line)
    assert first_window < last_time_window < first_release


def test_release_scope_includes_old_lands():
    now = 100 * 86400
    output = dispatch_metrics.render([
        event(now - 70 * 86400, "start", "old", version="v1.43.0"),
        event(now - 60 * 86400, "land", "old", version="v1.43.0"),
    ], 0, now)
    assert 'k3dm_dispatch_landed{window="v1.43.0"} 1' in output
    assert 'slug="old"' in output and 'window="v1.43.0",version="v1.43.0",slug="old"' in output
    assert 'k3dm_dispatch_landed{window="30d"} 0' in output


def test_release_versions_normalize_and_sort_numerically():
    events = [
        event(1, "start", "plain", version="1.43.3"), event(2, "land", "plain", version="1.43.3"),
        event(3, "start", "prefixed", version="v1.43.3"), event(4, "land", "prefixed", version="v1.43.3"),
        event(5, "start", "later", version="v1.43.10"),
    ]
    output = dispatch_metrics.render(events, 0, 100)
    assert 'k3dm_dispatch_landed{window="v1.43.3"} 2' in output
    assert 'window="1.43.3"' not in output
    assert dispatch_metrics._releases(events) == ["v1.43.3", "v1.43.10"]


def test_invalid_version_is_time_scoped_but_not_release_scoped():
    output = dispatch_metrics.render([
        event(10, "start", "main", version="main"), event(20, "land", "main", version="main"),
    ], 0, 100)
    assert 'k3dm_dispatch_landed{window="7d"} 1' in output
    assert 'window="main"' not in output


def test_started_release_without_lands_emits_zero():
    output = dispatch_metrics.render([event(1, "start", version="v2.0.0")], 0, 100)
    assert 'k3dm_dispatch_landed{window="v2.0.0"} 0' in output


def test_release_elapsed_uses_full_task_history():
    now = 100 * 86400
    output = dispatch_metrics.render([
        event(now - 40 * 86400, "start", version="v1.43.5"),
        event(now - 86400, "land", version="v1.43.5"),
    ], 0, now)
    assert 'k3dm_dispatch_task_elapsed_seconds{window="7d",version="v1.43.5",slug="one"} 3369600' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="v1.43.5",version="v1.43.5",slug="one"} 3369600' in output


def test_global_metrics_are_emitted_once_without_scope_labels():
    output = dispatch_metrics.render([event(1, "start"), event(2, "land")], 0, 10)
    lines = output.splitlines()
    for metric in ("k3dm_dispatch_running", "k3dm_dispatch_awaiting_land",
                   "k3dm_dispatch_ledger_timestamp_seconds", "k3dm_dispatch_ledger_bad_lines"):
        matching = [line for line in lines if line.startswith(metric)]
        assert len(matching) == 1
        assert "{" not in matching[0]


def test_dispatch_dashboard_window_variable_and_release_link():
    dashboard_path = Path(__file__).parents[2] / "etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
    raw = dashboard_path.read_text().split("  agent-dispatch.json: |\n", 1)[1]
    dashboard = json.loads("\n".join(line[4:] for line in raw.splitlines()))
    window = dashboard["templating"]["list"][0]
    assert window["type"] == "query"
    assert window["query"]["query"] == "label_values(k3dm_dispatch_landed, window)"
    assert window["sort"] == 7 and window["current"]["value"] == "7d"
    expressions = [target["expr"] for panel in dashboard["panels"]
                   for target in panel.get("targets", [])]
    assert sum("$window" in expr for expr in expressions) == 21  # agent-audit: allow assert-removed panel 12 query E adds one $window expression
    assert all('window="$window"' in expr for expr in expressions
               if any(metric in expr for metric in (
                   "k3dm_dispatch_landed", "k3dm_dispatch_land_attempts",
                   "k3dm_dispatch_verifier_lines_per_landed", "k3dm_dispatch_wait_minutes_per_landed",
                   "k3dm_dispatch_codex_tokens_per_landed", "k3dm_dispatch_elapsed_minutes_per_landed",
                   "k3dm_dispatch_codex_minutes_per_landed", "k3dm_dispatch_task_",
                   "k3dm_dispatch_rework_ratio")))
    per_spec = next(panel for panel in dashboard["panels"] if panel["id"] == 12)
    targets = {target["refId"]: target["expr"] for target in per_spec["targets"]}
    assert targets["E"] == 'max by (version, slug, spec) (k3dm_dispatch_task_spec{window="$window"})'
    organize = per_spec["transformations"][1]["options"]
    assert organize["excludeByName"]["Value #E"] is True
    assert organize["renameByName"]["Value #F"] == "API equiv."
    spec_override = next(item for item in per_spec["fieldConfig"]["overrides"]
                         if item["matcher"]["options"] == "Spec")
    spec_properties = {prop["id"]: prop["value"] for prop in spec_override["properties"]}
    assert spec_properties["custom.hidden"] is True
    assert spec_properties["links"][0]["title"] == "Open spec document"
    assert "${__data.fields.spec}" in spec_properties["links"][0]["url"]
    assert "k3d-manager-${__data.fields.version}" in spec_properties["links"][0]["url"]
    assert spec_properties["links"][0]["targetBlank"] is True
    release_override = next(item for item in per_spec["fieldConfig"]["overrides"]
                            if item["matcher"]["options"] == "Release")
    link = next(prop["value"] for prop in release_override["properties"] if prop["id"] == "links")
    assert link[0]["url"] == "/d/k3dm-bugs?var-release=${__data.fields.version}"
    assert link[0]["targetBlank"] is True
    assert "version" not in per_spec["transformations"][1]["options"]["excludeByName"]
    assert any(item.get("url") == "/d/k3dm-bugs" for item in dashboard["links"])


def test_api_cost_uses_last_session_event_and_counts_all_attempts():
    rates = {"gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}}
    rows = [
        event(10, "codex_usage", session="s1", model="gpt-5.6-luna", input=611180,
              cached_input=561408, output=5912),
        event(11, "codex_usage", session="s1", model="gpt-5.6-luna", input=611180,
              cached_input=561408, output=5912),
        event(12, "codex_usage", session="s2", model="gpt-5.6-luna", input=1_000_000,
              cached_input=0, output=0),
        event(13, "codex_usage", "two", session="s3", model="gpt-5.6-luna", input=5_000_000,
              cached_input=0, output=0),
        event(14, "land", "one"), event(15, "land_refused", "two", reason="tests"),
    ]
    metrics = dispatch_metrics._task_metrics(rows[:3], rows[4], rates)
    assert abs(metrics["api_cost_usd"] - (0.02827696 + 0.2)) < 1e-9
    output = dispatch_metrics.render(rows, 0, 20, prices=rates)
    assert 'k3dm_dispatch_api_cost_usd{window="1d"} 1.22827696' in output
    assert 'k3dm_dispatch_api_cost_per_landed_usd{window="1d"} 1.22827696' in output


def test_unpriced_model_keeps_tokens_and_release_has_no_coverage():
    rows = [event(10, "codex_usage", model="other-model", session="u1", input=10,
                  cached_input=4, output=2, version="v9.9.9")]
    output = dispatch_metrics.render(rows, 0, 20, prices={})
    assert 'k3dm_dispatch_api_cost_unpriced_sessions{window="1d"} 1' in output
    assert 'kind="cached_input"} 4' in output
    assert 'model="other-model"' not in '\n'.join(line for line in output.splitlines()
                                                       if 'api_cost_by_model' in line)
    assert 'k3dm_dispatch_codex_sessions{window="v9.9.9"' not in output


def test_coverage_reads_only_recent_session_metadata_and_usage(tmp_path, monkeypatch):
    now = int(time.time())
    home = tmp_path / "codex"
    folder = home / "sessions/2026/10/23"
    folder.mkdir(parents=True)
    records = [
        ("s1", now - 100, True), ("s2", now - 200, True), ("s3", now - 300, False),
    ]
    for session, started, _ in records:
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started))
        path = folder / f"rollout-{session}.jsonl"
        path.write_text("\n".join([
            json.dumps({"type": "session_meta", "payload": {"id": session, "timestamp": stamp}}),
            json.dumps({"type": "turn_context", "payload": {"model": "gpt-5.6-luna"}}),
            json.dumps({"type": "event_msg", "payload": {"info": {"total_token_usage": {
                "input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0}}}}),
            json.dumps({"type": "event_msg", "payload": {"user_prompt": "SECRET-PROMPT"}}),
        ]) + "\n")
    old = folder / "rollout-old.jsonl"
    old.write_text("should never be opened\n")
    os.utime(old, (now - 31 * 86400, now - 31 * 86400))
    real_open = open
    def guarded_open(name, *args, **kwargs):
        assert Path(name) != old
        return real_open(name, *args, **kwargs)
    monkeypatch.setattr("builtins.open", guarded_open)
    ledger = [event(now - 50, "codex_usage", session="s1", model="gpt-5.6-luna",
                    input=1_000_000, cached_input=0, output=0)]
    output = dispatch_metrics.render(ledger, 0, now,
        prices={"gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.2}},
        codex_home=home)
    assert f'k3dm_dispatch_codex_sessions{{window="1d",ledgered="true"}} 1' in output
    assert f'k3dm_dispatch_codex_sessions{{window="1d",ledgered="false"}} 2' in output
    assert f'k3dm_dispatch_unledgered_api_cost_usd{{window="1d"}} 0.4' in output
    assert "SECRET-PROMPT" not in output


def test_subscriptions_are_global_and_unlabelled_by_window():
    output = dispatch_metrics.render([], 0, 10, subscriptions={"chatgpt": 20, "claude": 20,
        "gemini": 20, "github": 4})
    lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_subscription_usd_per_month")]
    assert len(lines) == 4
    assert all('window=' not in line for line in lines)


def test_dashboard_has_cost_panels_and_nonoverlapping_layout():
    dashboard_path = Path(__file__).parents[2] / "etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
    raw = dashboard_path.read_text().split("  agent-dispatch.json: |\n", 1)[1]
    dashboard = json.loads("\n".join(line[4:] for line in raw.splitlines()))
    by_title = {panel["title"]: panel for panel in dashboard["panels"]}
    titles = {"Codex at API prices", "Per landed spec", "Cached input", "Subscriptions / month",
              "Ledger coverage", "By model", "Projected / month"}
    assert titles <= by_title.keys()
    assert 'window="7d"' in by_title["Projected / month"]["targets"][0]["expr"]
    assert 'window="$window"' not in by_title["Projected / month"]["targets"][0]["expr"]
    outside_override = next(item for item in by_title["Ledger coverage"]["fieldConfig"]["overrides"]
                            if item["matcher"] == {"id": "byName", "options": "outside the ledger"})
    properties = {prop["id"]: prop["value"] for prop in outside_override["properties"]}
    assert properties["unit"] == "currencyUSD"
    assert properties["decimals"] == 2
    boxes = []
    for panel in dashboard["panels"]:
        pos = panel.get("gridPos")
        if not pos or panel.get("type") == "row":
            continue
        rect = (pos["x"], pos["y"], pos["x"] + pos["w"], pos["y"] + pos["h"])
        for prior in boxes:
            assert rect[2] <= prior[0] or prior[2] <= rect[0] or rect[3] <= prior[1] or prior[3] <= rect[1]
        boxes.append(rect)
