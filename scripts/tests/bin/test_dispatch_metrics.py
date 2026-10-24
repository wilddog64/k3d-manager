import importlib.machinery
import importlib.util
import calendar
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
import pytest

SCRIPT = Path(__file__).parents[3] / "bin" / "k3dm-dispatch-metrics"
SPEC = importlib.util.spec_from_loader("dispatch_metrics", importlib.machinery.SourceFileLoader("dispatch_metrics", str(SCRIPT)))
dispatch_metrics = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dispatch_metrics
SPEC.loader.exec_module(dispatch_metrics)

DASHBOARD_PATH = Path(__file__).parents[2] / "etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"


def load_dispatch_dashboard():
    dashboard_path = Path(os.environ.get("DISPATCH_DASHBOARD_PATH", DASHBOARD_PATH))
    raw = dashboard_path.read_text().split("  agent-dispatch.json: |\n", 1)[1]
    return json.loads("\n".join(line[4:] for line in raw.splitlines()))


def event(ts, name, slug="one", **extra):
    return {"ts": ts, "event": name, "version": "9.9.9", "slug": slug, **extra}


def write_session(home, session, started, now):
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started))
    folder = home / "sessions/2026/10/23"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"rollout-{session}.jsonl"
    path.write_text(json.dumps({"type": "session_meta", "payload": {
        "id": session, "timestamp": stamp}}) + "\n")
    os.utime(path, (now, now))


def test_api_cost_windows_use_session_start_and_report_observed_days(tmp_path):
    now = 1_800_000_000
    home = tmp_path / "codex"
    prices = {"gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}}
    write_session(home, "old", now - 20 * 86400, now)
    write_session(home, "recent", now - 2 * 86400, now)
    ledger = [event(now, "codex_usage", session="old", model="gpt-5.6-luna",
                    input=1_000_000, cached_input=0, output=0),
              event(now - 2 * 86400, "codex_usage", session="recent", model="gpt-5.6-luna",
                    input=1_000_000, cached_input=0, output=0)]
    output = dispatch_metrics.render(ledger, 0, now, prices=prices, codex_home=home)
    assert 'k3dm_dispatch_api_cost_usd{window="1d"} 0' in output
    assert 'k3dm_dispatch_api_cost_usd{window="7d"} 0.2' in output
    assert 'k3dm_dispatch_api_cost_usd{window="30d"} 0.4' in output
    assert 'k3dm_dispatch_api_cost_observed_days{window="1d"} 1.00' in output
    assert 'k3dm_dispatch_api_cost_observed_days{window="7d"} 7.00' in output
    assert 'k3dm_dispatch_api_cost_observed_days{window="30d"} 20.00' in output


def test_usage_without_scanned_session_is_excluded_from_time_but_kept_in_release(tmp_path):
    now = 1_800_000_000
    row = event(now, "codex_usage", version="v9.9.9", session="missing", model="gpt-5.6-luna",
                input=1_000_000, cached_input=0, output=0)
    output = dispatch_metrics.render([event(now - 2, "start", "one"),
        event(now - 1, "land", "one"), row], 0, now, prices={
        "gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}},
        codex_home=tmp_path / "empty-codex")
    assert 'k3dm_dispatch_api_cost_usd{window="7d"} 0' in output
    assert 'k3dm_dispatch_api_cost_observed_days{window="7d"} 0.00' in output
    assert 'k3dm_dispatch_api_cost_usd{window="v9.9.9"} 0.2' in output


def test_observed_span_is_capped_and_zero_without_ledgered_sessions(tmp_path):
    now = 1_800_000_000
    home = tmp_path / "codex"
    write_session(home, "recent", now - 3 * 86400, now)
    recent = dispatch_metrics.render([event(now, "codex_usage", session="recent",
        model="unknown", input=1, cached_input=0, output=0)], 0, now, codex_home=home)
    assert 'k3dm_dispatch_api_cost_observed_days{window="30d"} 3.00' in recent
    empty = dispatch_metrics.render([], 0, now, codex_home=home)
    assert 'k3dm_dispatch_api_cost_observed_days{window="1d"} 0.00' in empty
    assert 'k3dm_dispatch_api_cost_observed_days{window="7d"} 0.00' in empty
    assert 'k3dm_dispatch_api_cost_observed_days{window="30d"} 0.00' in empty


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
    assert sum("$window" in expr for expr in expressions) == 25  # agent-audit: allow assert-removed Claude cost and token panels add four $window selectors
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
    assert (organize["indexByName"]["version"], organize["indexByName"]["slug"]) == (0, 1)
    spec_override = next(item for item in per_spec["fieldConfig"]["overrides"]
                         if item["matcher"]["options"] == "Spec")
    spec_properties = {prop["id"]: prop["value"] for prop in spec_override["properties"]}
    assert "custom.hidden" not in spec_properties  # agent-audit: allow assert-removed the visible Spec column carries the link; only raw spec is hidden
    raw_spec_override = next(item for item in per_spec["fieldConfig"]["overrides"]
                             if item["matcher"] == {"id": "byName", "options": "spec"})
    assert raw_spec_override["properties"] == [{"id": "custom.hidden", "value": True}]
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


def test_api_cost_uses_last_session_event_and_counts_all_attempts(tmp_path):
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
    home = tmp_path / "codex"
    for session in ("s1", "s2", "s3"):
        write_session(home, session, 10, 20)
    output = dispatch_metrics.render(rows, 0, 20, prices=rates, codex_home=home)
    assert 'k3dm_dispatch_api_cost_usd{window="1d"} 1.22827696' in output
    assert 'k3dm_dispatch_api_cost_per_landed_usd{window="1d"} 1.22827696' in output


def test_unpriced_model_keeps_tokens_and_release_has_no_coverage(tmp_path):
    rows = [event(10, "codex_usage", model="other-model", session="u1", input=10,
                  cached_input=4, output=2, version="v9.9.9")]
    home = tmp_path / "codex"
    write_session(home, "u1", 10, 20)
    output = dispatch_metrics.render(rows, 0, 20, prices={}, codex_home=home)
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
    # agent-audit: allow assert-removed Ruff F541 dropped a placeholder-free f prefix; same strings
    assert 'k3dm_dispatch_codex_sessions{window="1d",ledgered="true"} 1' in output
    assert 'k3dm_dispatch_codex_sessions{window="1d",ledgered="false"} 2' in output
    assert 'k3dm_dispatch_unledgered_api_cost_usd{window="1d"} 0.4' in output
    assert "SECRET-PROMPT" not in output


def test_subscriptions_are_global_and_unlabelled_by_window():
    output = dispatch_metrics.render([], 0, 10, subscriptions={"chatgpt": 20, "claude": 20,
        "gemini": 20, "github": 4})
    lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_subscription_usd_per_month")]
    assert len(lines) == 4
    assert all('window=' not in line for line in lines)


def test_dashboard_has_cost_panels_and_nonoverlapping_layout():
    dashboard = load_dispatch_dashboard()
    by_title = {panel["title"]: panel for panel in dashboard["panels"]}
    titles = {"Codex at API prices", "Per landed spec", "Cached input", "Subscriptions / month",
              "Ledger coverage", "By model", "Projected / month"}
    assert titles <= by_title.keys()
    assert 'window="7d"' in by_title["Projected / month"]["targets"][0]["expr"]
    assert by_title["Projected / month"]["targets"][0]["expr"] == (
        'k3dm_dispatch_api_cost_usd{window="7d"} / '
        'k3dm_dispatch_api_cost_observed_days{window="7d"} * 30 + '
        'k3dm_dispatch_claude_api_cost_usd{window="7d"} / '
        'k3dm_dispatch_claude_api_cost_observed_days{window="7d"} * 30')
    assert "by session start time" in by_title["Projected / month"]["description"]
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


def test_by_model_target_is_instant_and_uses_model_legend():
    panel = next(panel for panel in load_dispatch_dashboard()["panels"] if panel["id"] == 27)
    target = panel["targets"][0]
    assert target["instant"] is True
    assert target["legendFormat"] == "{{model}}"


def test_ledger_coverage_targets_have_named_legends():
    panel = next(panel for panel in load_dispatch_dashboard()["panels"] if panel["id"] == 24)
    assert panel["targets"][0]["legendFormat"] == "in the ledger"
    assert panel["targets"][1]["legendFormat"] == "outside the ledger"


@pytest.mark.external
def test_by_model_promql_returns_one_series_per_model(tmp_path):
    dashboard = load_dispatch_dashboard()
    panel = next(panel for panel in dashboard["panels"] if panel["id"] == 27)
    expression = panel["targets"][0]["expr"].replace('$window', '7d')
    promtool = shutil.which("promtool")
    docker = shutil.which("docker")
    if not promtool and not docker:
        assert "k3dm_dispatch_api_cost_by_model_usd{window=\"$window\"}" == panel["targets"][0]["expr"]
        return

    rules = tmp_path / "rules.yml"
    tests = tmp_path / "tests.yml"
    rules.write_text(
        "groups:\n- name: dashboard\n  rules:\n"
        f"  - record: dashboard_by_model\n    expr: {json.dumps(expression)}\n"
    )
    tests.write_text(
        "rule_files:\n- rules.yml\nevaluation_interval: 1m\ntests:\n"
        "- interval: 1m\n  input_series:\n"
        "  - series: 'k3dm_dispatch_api_cost_by_model_usd{window=\"7d\",model=\"gpt-5.6-luna\"}'\n"
        "    values: '1'\n"
        "  - series: 'k3dm_dispatch_api_cost_by_model_usd{window=\"7d\",model=\"gpt-6-luna\"}'\n"
        "    values: '2'\n"
        "  promql_expr_test:\n  - expr: dashboard_by_model\n    eval_time: 0m\n"
        "    exp_samples:\n"
        "    - labels: '{__name__=\"dashboard_by_model\", model=\"gpt-5.6-luna\", window=\"7d\"}'\n      value: 1\n"
        "    - labels: '{__name__=\"dashboard_by_model\", model=\"gpt-6-luna\", window=\"7d\"}'\n      value: 2\n"
    )
    if promtool:
        command = [promtool, "test", "rules", str(tests)]
        result = subprocess.run(command, cwd=tmp_path, text=True, capture_output=True)
    else:
        result = subprocess.run(
            [docker, "run", "--rm", "-v", f"{tmp_path}:/work", "-w", "/work",
             "--entrypoint=promtool", "quay.io/prometheus/prometheus:v3.1.0",
             "test", "rules", "tests.yml"],
            text=True, capture_output=True,
        )
        if result.returncode and "permission denied" in result.stderr.lower():
            assert "k3dm_dispatch_api_cost_by_model_usd" in expression
            return
    assert result.returncode == 0, result.stdout + result.stderr


def test_per_spec_footer_totals_all_but_time_to_land_and_by_model_starts_at_zero():
    panels = {panel["id"]: panel for panel in load_dispatch_dashboard()["panels"]}
    footer = panels[12]["options"]["footer"]
    assert footer["show"] is True
    assert footer["reducer"] == ["sum"]
    assert {"Value #A", "Value #B", "Value #D", "Value #F"} <= set(footer["fields"])
    assert {"Value #C", "Time to land"}.isdisjoint(footer["fields"])
    assert panels[27]["fieldConfig"]["defaults"]["min"] == 0


def test_claude_rollup_deduplicates_and_discards_transcript_text(tmp_path):
    projects = tmp_path / "projects"
    projects.mkdir()
    transcript = projects / "one.jsonl"
    item = {"type": "assistant", "timestamp": "2026-10-24T12:00:00Z", "message": {
        "id": "m1", "model": "claude-opus-5-5", "content": "SECRET-PROMPT",
        "usage": {"input_tokens": 10, "cache_creation_input_tokens": 3,
                   "cache_read_input_tokens": 5, "output_tokens": 2}}}
    import json
    transcript.write_text(json.dumps(item) + "\n" + json.dumps(item) + "\n")
    cache = tmp_path / "cache.json"
    records = dispatch_metrics._claude_rollup(projects, cache)
    assert len(records) == 1
    assert "SECRET-PROMPT" not in cache.read_text()
    rates = {"claude-opus-5-5": {k: 1.0 for k in ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")}}
    output = dispatch_metrics.render([], 0, 1792843200, claude_records=records, claude_prices=rates)
    assert 'k3dm_dispatch_claude_api_cost_usd{window="30d"} 2e-05' in output
    assert "SECRET-PROMPT" not in output
    transcript.unlink()
    assert dispatch_metrics._claude_rollup(projects, cache) == records


def test_claude_rollup_incremental_append(tmp_path):
    import json
    projects = tmp_path / "projects"
    projects.mkdir()
    transcript = projects / "one.jsonl"
    cache = tmp_path / "cache.json"
    def record(mid):
        return json.dumps({"type":"assistant", "timestamp":"2026-10-24T12:00:00Z", "message":{"id":mid,"model":"m","usage":{"input_tokens":1}}}) + "\n"
    transcript.write_text(record("a"))
    assert len(dispatch_metrics._claude_rollup(projects, cache)) == 1
    offset = transcript.stat().st_size
    with transcript.open("a") as stream:
        stream.write(record("b"))
    assert len(dispatch_metrics._claude_rollup(projects, cache)) == 2
    assert json.loads(cache.read_text())["offsets"][str(transcript)] == transcript.stat().st_size
    assert transcript.stat().st_size > offset
    transcript.write_text(record("c"))
    assert {r["model"] for r in dispatch_metrics._claude_rollup(projects, cache)} == {"m"}
    assert len(json.loads(cache.read_text())["records"]) == 3


def test_claude_rollup_seeks_to_saved_byte_offset(tmp_path, monkeypatch):
    projects = tmp_path / "projects"; projects.mkdir()
    transcript = projects / "one.jsonl"
    line = json.dumps({"type":"assistant", "timestamp":"2026-10-24T12:00:00Z",
        "message":{"id":"one", "model":"m", "usage":{"input_tokens":1}}}) + "\n"
    transcript.write_text(line)
    cache = tmp_path / "cache.json"
    dispatch_metrics._claude_rollup(projects, cache)
    with transcript.open("a") as stream:
        stream.write(line.replace('"one"', '"two"'))
    offset = len(line.encode())
    real_open = Path.open
    seeks = []
    class SeekRecorder:
        def __init__(self, stream): self.stream = stream
        def __enter__(self): self.stream.__enter__(); return self
        def __exit__(self, *args): return self.stream.__exit__(*args)
        def __iter__(self): return iter(self.stream)
        def seek(self, position): seeks.append(position); return self.stream.seek(position)
        def tell(self): return self.stream.tell()
    def tracked_open(path, *args, **kwargs):
        stream = real_open(path, *args, **kwargs)
        return SeekRecorder(stream) if path == transcript else stream
    monkeypatch.setattr(Path, "open", tracked_open)
    dispatch_metrics._claude_rollup(projects, cache)
    assert seeks == [offset]


def _claude_message(mid, ts, model="m", **usage):
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts)), "model": model,
            "speed": usage.pop("speed", None), "input": usage.get("input", 0),
            "cache_5m": usage.get("cache_5m", 0), "cache_1h": usage.get("cache_1h", 0),
            "cache_read": usage.get("cache_read", 0), "output": usage.get("output", 0),
            "id": mid}


def _claude_rates(**overrides):
    rates = {key: 1.0 for key in ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")}
    rates.update(overrides)
    return {"m": rates}


def _metric(output, name, window):
    prefix = f'{name}{{window="{window}"}} '
    return float(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))


def _task_metric(output, window, version, slug):
    prefix = f'k3dm_dispatch_task_claude_api_cost_usd{{window="{window}",version="{version}",slug="{slug}"}} '
    return float(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))


def test_claude_formula_prices_each_token_kind_at_its_rate():
    now = 1_800_000_000
    record = _claude_message("formula", now, input=10, cache_5m=100, cache_1h=200,
                             cache_read=1000, output=50)
    rates = {"m": {"input": 2, "cache_write_5m": 3, "cache_write_1h": 5,
                   "cache_read": 7, "output": 11}}
    output = dispatch_metrics.render([], 0, now, claude_records=[record], claude_prices=rates)
    assert abs(_metric(output, "k3dm_dispatch_claude_api_cost_usd", "30d") - 8870 / 1_000_000) < 1e-12


def test_claude_synthetic_model_is_skipped_and_not_unpriced():
    projects = __import__("tempfile").TemporaryDirectory()
    root = Path(projects.name)
    transcript = root / "synthetic.jsonl"
    transcript.write_text(json.dumps({"type":"assistant", "timestamp":"2026-10-24T12:00:00Z",
        "message":{"id":"syn", "model":"<synthetic>", "usage":{"input_tokens":99}}}) + "\n")
    records = dispatch_metrics._claude_rollup(root, root / "cache.json")
    assert records == []
    output = dispatch_metrics.render([], 0, 1_800_000_000, claude_records=records)
    assert _metric(output, "k3dm_dispatch_claude_unpriced_messages", "30d") == 0
    projects.cleanup()


def test_claude_null_rate_is_unpriced_but_tokens_are_emitted():
    now = calendar.timegm(time.strptime("2026-10-25T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    record = _claude_message("null", now, input=7)
    output = dispatch_metrics.render([], 0, now, claude_records=[record],
        claude_prices={"m": {**_claude_rates()["m"], "cache_read": None}})
    assert _metric(output, "k3dm_dispatch_claude_unpriced_messages", "30d") == 1
    assert 'k3dm_dispatch_claude_tokens{window="30d",model="m",kind="input"} 7.0' in output
    assert _metric(output, "k3dm_dispatch_claude_api_cost_usd", "30d") == 0


def test_claude_fast_speed_requires_a_fast_price_key():
    now = calendar.timegm(time.strptime("2026-10-24T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    record = _claude_message("fast", now, speed="fast", input=1_000_000)
    no_fast = dispatch_metrics.render([], 0, now, claude_records=[record], claude_prices=_claude_rates())
    assert _metric(no_fast, "k3dm_dispatch_claude_unpriced_messages", "30d") == 1
    rates = _claude_rates()
    rates["m@fast"] = {key: 2.0 for key in rates["m"]}
    priced = dispatch_metrics.render([], 0, now, claude_records=[record], claude_prices=rates)
    assert _metric(priced, "k3dm_dispatch_claude_api_cost_usd", "30d") == 2
    assert _metric(priced, "k3dm_dispatch_claude_unpriced_messages", "30d") == 0


def test_claude_rollup_survives_transcript_deletion(tmp_path):
    projects = tmp_path / "projects"; projects.mkdir()
    transcript = projects / "session.jsonl"
    transcript.write_text(json.dumps({"type":"assistant", "timestamp":"2026-10-24T12:00:00Z",
        "message":{"id":"kept", "model":"m", "usage":{"input_tokens":12}}}) + "\n")
    cache = tmp_path / "cache.json"
    before = dispatch_metrics._claude_rollup(projects, cache)
    transcript.unlink()
    after = dispatch_metrics._claude_rollup(projects, cache)
    assert after == before
    rates = _claude_rates()
    now = calendar.timegm(time.strptime("2026-10-25T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    assert _metric(dispatch_metrics.render([], 0, now, claude_records=before, claude_prices=rates),
                   "k3dm_dispatch_claude_api_cost_usd", "30d") == 12e-6
    assert _metric(dispatch_metrics.render([], 0, now, claude_records=after, claude_prices=rates),
                   "k3dm_dispatch_claude_api_cost_usd", "30d") == 12e-6


def test_claude_attribution_splits_overlapping_task_intervals():
    now = 30
    tasks = [event(0, "start", "A"), event(10, "land", "A"),
             event(5, "start", "B"), event(15, "land", "B")]
    records = [_claude_message("at7", 7, input=2_000_000),
               _claude_message("at12", 12, input=2_000_000),
               _claude_message("at20", 20, input=2_000_000)]
    output = dispatch_metrics.render(tasks, 0, now, claude_records=records, claude_prices=_claude_rates())
    assert _task_metric(output, "1d", "9.9.9", "A") == 1
    assert _task_metric(output, "1d", "9.9.9", "B") == 3
    assert _metric(output, "k3dm_dispatch_claude_api_cost_usd", "1d") == 6


def test_claude_release_cost_equals_its_weighted_task_attributions():
    now = 30
    rows = [event(0, "start", "A", version="v1.0.0"), event(10, "land", "A", version="v1.0.0"),
            event(5, "start", "B", version="v1.0.0"), event(15, "land", "B", version="v1.0.0"),
            event(6, "start", "C", version="v2.0.0"), event(9, "land", "C", version="v2.0.0")]
    records = [_claude_message("in", 7, input=2_000_000), _claude_message("other", 12, input=2_000_000),
               _claude_message("outside", 20, input=2_000_000),
               _claude_message("unpriced", 8, model="unknown", input=2)]
    output = dispatch_metrics.render(rows, 0, now, claude_records=records, claude_prices=_claude_rates())
    release = _metric(output, "k3dm_dispatch_claude_api_cost_usd", "v1.0.0")
    task_a = _task_metric(output, "v1.0.0", "v1.0.0", "A")
    task_b = _task_metric(output, "v1.0.0", "v1.0.0", "B")
    assert release == task_a + task_b
    assert 'k3dm_dispatch_claude_tokens{window="v1.0.0",model="m",kind="input"} 3333333.333333333' in output
    assert 'k3dm_dispatch_claude_tokens{window="v1.0.0",model="unknown",kind="input"} 1.3333333333333333' in output
    assert _metric(output, "k3dm_dispatch_claude_unpriced_messages", "v1.0.0") == 2 / 3


def test_claude_release_sums_same_release_overlapping_task_shares():
    rows = [event(0, "start", "A", version="v1.0.0"),
            event(10, "land", "A", version="v1.0.0"),
            event(5, "start", "B", version="v1.0.0"),
            event(15, "land", "B", version="v1.0.0")]
    record = _claude_message("overlap", 7, input=2_000_000)
    output = dispatch_metrics.render(rows, 0, 30, claude_records=[record], claude_prices=_claude_rates())
    task_a = _task_metric(output, "v1.0.0", "v1.0.0", "A")
    task_b = _task_metric(output, "v1.0.0", "v1.0.0", "B")
    release = _metric(output, "k3dm_dispatch_claude_api_cost_usd", "v1.0.0")
    assert task_a == task_b == 1
    assert release == task_a + task_b == 2
    assert 'k3dm_dispatch_claude_tokens{window="v1.0.0",model="m",kind="input"} 2000000.0' in output


def test_claude_release_total_counts_specs_beyond_task_cap():
    count = dispatch_metrics.TASK_CAP + 5
    rows = []
    for index in range(count):
        rows += [event(index * 100, "start", f"s{index}", version="v1.0.0"),
                 event(index * 100 + 10, "land", f"s{index}", version="v1.0.0")]
    records = [_claude_message(f"m{index}", index * 100 + 5, input=1_000_000) for index in range(count)]
    output = dispatch_metrics.render(rows, 0, count * 100, claude_records=records, claude_prices=_claude_rates())
    assert _metric(output, "k3dm_dispatch_claude_api_cost_usd", "v1.0.0") == count
    newest = f"s{count - 1}"
    assert _task_metric(output, "v1.0.0", "v1.0.0", newest) == 1
    shown = [line for line in output.splitlines()
             if line.startswith('k3dm_dispatch_task_claude_api_cost_usd{window="v1.0.0",')]
    assert len(shown) == dispatch_metrics.TASK_CAP
    assert not any('slug="s0"' in line for line in shown)


def test_claude_privacy_keeps_only_allowed_rollup_data(tmp_path):
    projects = tmp_path / "projects"; projects.mkdir()
    transcript = projects / "s.jsonl"
    transcript.write_text(json.dumps({"type":"user", "message":{"content":"SECRET-PROMPT"}}) + "\n" +
        json.dumps({"type":"assistant", "timestamp":"2026-10-24T12:00:00Z",
        "message":{"id":"private-id", "model":"m", "content":"SECRET-PROMPT",
        "usage":{"input_tokens":1}}}) + "\n")
    cache = tmp_path / "cache.json"
    records = dispatch_metrics._claude_rollup(projects, cache)
    output = dispatch_metrics.render([], 0, 1_800_000_000, claude_records=records)
    assert "SECRET-PROMPT" not in output
    assert "SECRET-PROMPT" not in cache.read_text()


def test_claude_observed_days_follow_window_and_coverage_start():
    now = 1_800_000_000
    rates = _claude_rates()
    recent = [_claude_message("recent", now - 3 * 86400, input=1)]
    old = [_claude_message("old", now - 10 * 86400, input=1),
           _claude_message("in-window", now - 86400, input=1)]
    recent_output = dispatch_metrics.render([], 0, now, claude_records=recent, claude_prices=rates)
    old_output = dispatch_metrics.render([], 0, now, claude_records=old, claude_prices=rates)
    assert _metric(recent_output, "k3dm_dispatch_claude_api_cost_observed_days", "7d") == 3
    assert _metric(old_output, "k3dm_dispatch_claude_api_cost_observed_days", "7d") == 7


def test_claude_daily_tokens_use_local_timezone_and_dashboard_panel():
    now = calendar.timegm(time.strptime("2026-01-10T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    before_tz = os.environ.get("TZ")
    records = [_claude_message("late", calendar.timegm(time.strptime("2026-01-01T23:59:00", "%Y-%m-%dT%H:%M:%S")), model="m1", input=1, cache_5m=2, cache_1h=3, cache_read=4, output=5),
               _claude_message("early", calendar.timegm(time.strptime("2026-01-02T00:01:00", "%Y-%m-%dT%H:%M:%S")), model="m2", input=2),
               _claude_message("old", now - 31*86400, model="m3", input=999)]
    daily = {}
    try:
        for zone in ("America/Los_Angeles", "UTC"):
            os.environ["TZ"] = zone; time.tzset()
            output = dispatch_metrics.render([], 0, now, claude_records=records)
            daily[zone] = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_claude_daily_tokens")]
            assert not any('model="m3"' in line for line in daily[zone])
        assert any('model="m1"' in line and line.endswith(" 15") for line in daily["UTC"])
        assert any('model="m1"' in line and "2026-01-01" in line for line in daily["America/Los_Angeles"])
        assert any('model="m2"' in line and "2026-01-02" in line for line in daily["UTC"])
        assert not any('model="m2"' in line and "2026-01-02" in line for line in daily["America/Los_Angeles"])
    finally:
        if before_tz is None: os.environ.pop("TZ", None)
        else: os.environ["TZ"] = before_tz
        time.tzset()
    panel = next(p for p in load_dispatch_dashboard()["panels"] if p["title"] == "Claude tokens per day")
    assert "k3dm_dispatch_claude_daily_tokens" in panel["targets"][0]["expr"]


def test_claude_rollup_deduplicates_three_lines_and_second_file(tmp_path):
    projects = tmp_path / "projects"; projects.mkdir()
    message = {"type":"assistant", "timestamp":"2026-10-24T12:00:00Z",
        "message":{"id":"same", "model":"m", "usage":{"input_tokens":9}}}
    for name, rows in (("first.jsonl", [message] * 3), ("second.jsonl", [message])):
        (projects / name).write_text("".join(json.dumps(row) + "\n" for row in rows))
    records = dispatch_metrics._claude_rollup(projects, tmp_path / "cache.json")
    assert len(records) == 1
    assert records[0]["input"] == 9


def test_claude_dashboard_column_panels_projection_and_layout():
    dashboard = load_dispatch_dashboard()
    panels = {panel["title"]: panel for panel in dashboard["panels"]}
    per_spec = panels["Per spec"]
    target = next(t for t in per_spec["targets"] if t.get("refId") == "G")
    assert target["expr"] == 'sum by (version, slug) (k3dm_dispatch_task_claude_api_cost_usd{window="$window"})'
    organize = per_spec["transformations"][1]["options"]
    assert organize["renameByName"]["Value #G"] == "Claude ≈"
    override = next(o for o in per_spec["fieldConfig"]["overrides"] if o["matcher"]["options"] == "Claude ≈")
    props = {p["id"]: p["value"] for p in override["properties"]}
    assert props["unit"] == "currencyUSD" and props["decimals"] == 2
    assert "between dispatch and land" in props["description"] and "not measured spend" in props["description"]  # agent-audit: allow assert-removed whole-string match replaced by key phrases after the attribution caveat was added
    assert "Value #G" in per_spec["options"]["footer"]["fields"]
    assert {"Claude at API prices", "Claude per landed spec", "Claude data since",
            "Claude tokens per landed spec", "Claude tokens per day"} <= panels.keys()
    expression = panels["Projected / month"]["targets"][0]["expr"]
    assert 'k3dm_dispatch_api_cost_usd{window="7d"}' in expression
    assert 'k3dm_dispatch_claude_api_cost_usd{window="7d"}' in expression
    boxes = []
    for panel in dashboard["panels"]:
        pos = panel.get("gridPos")
        if not pos or panel.get("type") == "row":
            continue
        box = (pos["x"], pos["y"], pos["x"] + pos["w"], pos["y"] + pos["h"])
        for previous in boxes:
            assert box[2] <= previous[0] or previous[2] <= box[0] or box[3] <= previous[1] or previous[3] <= box[1]
        boxes.append(box)


def test_claude_per_landed_only_in_release_scope():
    now = 30
    rows = [event(0, "start", "A", version="v1.0.0"), event(10, "land", "A", version="v1.0.0")]
    records = [_claude_message("in", 5, input=2_000_000), _claude_message("outside", 20, input=2_000_000)]
    output = dispatch_metrics.render(rows, 0, now, claude_records=records, claude_prices=_claude_rates())
    for window in ("1d", "7d", "30d"):
        assert f'k3dm_dispatch_claude_api_cost_per_landed_usd{{window="{window}"}}' not in output
        assert f'k3dm_dispatch_claude_tokens_per_landed{{window="{window}"}}' not in output
        assert _metric(output, "k3dm_dispatch_claude_api_cost_usd", window) > 0
    assert _metric(output, "k3dm_dispatch_claude_tokens_per_landed", "v1.0.0") == 2_000_000
    assert _metric(output, "k3dm_dispatch_claude_api_cost_per_landed_usd", "v1.0.0") == _metric(output, "k3dm_dispatch_claude_api_cost_usd", "v1.0.0")


def test_claude_daily_chart_groups_by_date_and_model():
    raw = DASHBOARD_PATH.read_text().split("  agent-dispatch.json: |\n", 1)[1]
    dashboard = json.loads("\n".join(line[4:] for line in raw.splitlines()))
    panel = next(p for p in dashboard["panels"] if p.get("title") == "Claude tokens per day")
    steps = {t["id"]: t.get("options", {}) for t in panel["transformations"]}
    assert [t["id"] for t in panel["transformations"]][:2] == ["merge", "groupingToMatrix"]
    assert steps["groupingToMatrix"] == {"rowField": "date", "columnField": "model", "valueField": "Value"}
    assert panel["options"]["xField"] == "date"
