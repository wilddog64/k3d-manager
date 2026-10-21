import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

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
    assert dispatch_metrics.main(["--dry-run"]) == 0
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
