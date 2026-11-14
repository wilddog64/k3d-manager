import importlib.machinery
from textwrap import dedent
import importlib.util
import calendar
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from promtool_helper import resolve_promtool  # noqa: E402
# agent-audit: allow assert-removed removed asserts lived in the no-promtool/docker fallback branches the spec deletes; the promtool path keeps its returncode assert
# agent-audit: allow assert-removed evidence_path drops the home directory; the absolute-path assert becomes a root-relative one plus a no-tmp-path assert
# agent-audit: allow assert-removed per-spec series gained an agent label; every removed assert is re-added with agent="codex" and the same value

SCRIPT = Path(__file__).parents[3] / "bin" / "k3dm-dispatch-metrics"
SPEC = importlib.util.spec_from_loader("dispatch_metrics", importlib.machinery.SourceFileLoader("dispatch_metrics", str(SCRIPT)))
dispatch_metrics = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dispatch_metrics
SPEC.loader.exec_module(dispatch_metrics)

DASHBOARD_PATH = Path(__file__).parents[2] / "etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"


@pytest.fixture(autouse=True)
def _pin_pushgateway_target(monkeypatch):
    monkeypatch.setenv("K3DM_DISPATCH_PUSHGATEWAY_URL", "http://127.0.0.1:9")


@pytest.fixture(autouse=True)
def _isolate_state_dirs(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path / "worktrees"))
    monkeypatch.setenv("K3DM_AGENT_LEDGER_DIR", str(tmp_path / "agent-sessions"))
    monkeypatch.setenv("K3DM_AGY_BRAIN_DIR", str(tmp_path / "agy-brain"))


def load_dashboard(path, key):
    raw = path.read_text().split(f"  {key}: |\n", 1)[1]
    return json.loads("\n".join(line[4:] for line in raw.splitlines()))


def load_dispatch_dashboard():
    dashboard_path = Path(os.environ.get("DISPATCH_DASHBOARD_PATH", DASHBOARD_PATH))
    dashboard = load_dashboard(dashboard_path, "agent-dispatch.json")
    for offset, (key, filename) in enumerate((
        ("agent-cost.json", "grafana-dashboard-agent-cost.yaml"),
        ("agent-activity.json", "grafana-dashboard-agent-activity.yaml")), start=1):
        extra = load_dashboard(dashboard_path.with_name(filename), key)
        dashboard["panels"].extend(dict(panel, gridPos=dict(panel.get("gridPos", {}), y=panel.get("gridPos", {}).get("y", 0) + offset * 1000)) for panel in extra["panels"])
    return dashboard


def event(ts, name, slug="one", **extra):
    return {"ts": ts, "event": name, "version": "9.9.9", "slug": slug, **extra}


def write_session(home, session, started, now, cwd=None, usage=None):
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started))
    folder = home / "sessions/2026/10/23"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"rollout-{session}.jsonl"
    rows = [{"type": "session_meta", "payload": {
        "id": session, "timestamp": stamp, **({"cwd": str(cwd)} if cwd is not None else {})}}]
    if usage is not None:
        rows.append({"type": "event_msg", "payload": {"info": {"total_token_usage": usage}}})
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    os.utime(path, (now, now))


def test_api_cost_windows_use_session_start_and_report_observed_days(tmp_path):
    now = time.time()
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


def test_activity_cost_keeps_priced_sessions_and_counts_unpriced(tmp_path):
    now = time.time()
    home = tmp_path / "codex"
    for name, model, usage in (
        ("priced", "gpt-5.6-luna", {"input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0}),
        ("review", "codex-auto-review", {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 0}),
        ("missing", "gpt-5.6-luna", None),
        ("only-review", "codex-auto-review", {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 0}),
    ):
        write_session(home, name, now - 10, now)
        path = next((home / "sessions").rglob(f"rollout-{name}.jsonl"))
        lines = path.read_text().splitlines()
        meta = json.loads(lines[0])
        meta["payload"]["originator"] = "codex_exec" if name != "only-review" else "codex-tui"
        path.write_text(json.dumps(meta) + "\n" + "\n".join([
            json.dumps({"type": "turn_context", "payload": {"model": model}}),
            json.dumps({"type": "event_msg", "payload": {"info": {"total_token_usage": usage}}}),
        ]) + "\n")
    output = dispatch_metrics.render([], 0, now,
        prices={"gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}}, codex_home=home)
    assert 'k3dm_codex_api_cost_usd{window="1d",mode="exec"} 0.2' in output
    assert 'k3dm_codex_unpriced_sessions{window="1d",mode="exec",reason="model"} 1' in output
    assert 'k3dm_codex_unpriced_sessions{window="1d",mode="exec",reason="usage"} 1' in output
    assert 'k3dm_codex_unpriced_sessions{window="1d",mode="interactive",reason="model"} 1' in output
    assert not any(line.startswith('k3dm_codex_api_cost_usd{window="1d",mode="interactive"}') for line in output.splitlines())


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
    now = time.time()
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
    assert all("secret-slug" not in line or "k3dm_dispatch_task_" in line or "k3dm_dispatch_model_identity" in line
               for line in output.splitlines())


def test_legacy_task_gets_codex_agent_label_and_keeps_values():
    output = dispatch_metrics.render([
        event(1, "start", spec="docs/plans/v1.43.6-example.md"),
        event(5, "codex_exit", tokens=123), event(10, "land"),
    ], 0, 10)
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 123' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 4' in output


def test_task_repo_label_uses_valid_origin_name_and_defaults_invalid_events():
    output = dispatch_metrics.render([
        event(1, "start", "cart", repo="shopping-cart-frontend"),
        event(2, "codex_exit", "cart", tokens=8), event(3, "land", "cart"),
        event(4, "start", "legacy", repo="bad repo"),
        event(5, "codex_exit", "legacy", tokens=4), event(6, "land", "legacy"),
    ], 0, 10)
    assert 'slug="cart",agent="codex",repo="shopping-cart-frontend"} 8' in output
    assert 'slug="legacy",agent="codex",repo="k3d-manager"} 4' in output
    assert 'k3dm_dispatch_landed{window="1d"} 2' in output
    assert 'k3dm_dispatch_landed{window="1d",repo=' not in output


def test_agy_usage_never_enters_codex_token_series():
    output = dispatch_metrics.render([
        event(1, "start", agent="agy", model="gemini-4-argon-medium", spec="docs/plans/v1.43.6-example.md"),
        event(5, "agent_exit", exit=0, usage={"input_tokens": 999, "output_tokens": 100}),
        event(10, "land"),
    ], 0, 10)
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one",agent="agy",repo="k3d-manager"} 9' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="agy",repo="k3d-manager"}' not in output
    assert "k3dm_dispatch_task_codex_tokens{" not in output
    assert "k3dm_dispatch_codex_tokens_by_model" not in output


def test_unknown_agent_is_bounded_as_other():
    output = dispatch_metrics.render([
        event(1, "start", agent="mystery"), event(2, "agent_exit", exit=0), event(3, "land"),
    ], 0, 3)
    assert 'slug="one",agent="other"' in output


def test_agy_exit_counts_as_finished_dispatch():
    output = dispatch_metrics.render([
        event(1, "start", agent="agy"), event(2, "agent_exit", exit=0),
    ], 0, 3)
    assert "k3dm_dispatch_running 0\n" in output
    assert "k3dm_dispatch_awaiting_land 1\n" in output


def test_per_task_values():
    output = dispatch_metrics.render([
        event(0, "start"), event(100, "codex_exit", tokens=10),
        event(150, "resume"), event(250, "codex_exit", tokens=30), event(400, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 30' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 200' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 400' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2' in output
    assert 'k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 6.666666666666667' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"} 3.3333333333333335' in output


def test_task_spec_uses_latest_start_and_is_emitted_for_each_scope():
    output = dispatch_metrics.render([
        event(1, "start", spec="docs/plans/old.md"), event(2, "start", spec="docs/bugs/2026-10-23-x.md"),
        event(3, "codex_exit", tokens=1), event(4, "land"),
    ], 0, 10)
    for window in ("1d", "7d", "30d", "v9.9.9"):
        assert (f'k3dm_dispatch_task_spec{{window="{window}",version="9.9.9",slug="one",agent="codex",repo="k3d-manager",'
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
    assert 'slug="valid",agent="codex",repo="k3d-manager",spec="docs/plans/v1.43.5-valid.md"} 1' in output
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 4' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2' in output


def test_landed_task_without_exit_omits_codex_samples_but_keeps_elapsed():
    output = dispatch_metrics.render([
        event(100, "start"), event(399, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 299' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"}' not in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"}' not in output
    assert 'k3dm_dispatch_elapsed_minutes_per_landed{window="1d"} 4.983333333333333' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"}' not in output
    assert 'k3dm_dispatch_task_post_exit_land_seconds{window="1d",version="9.9.9",slug="one",repo="k3d-manager"}' not in output


def test_post_exit_land_uses_latest_exit_before_land_and_ignores_later_exit():
    output = dispatch_metrics.render([
        event(100, "start"), event(120, "codex_exit"), event(200, "resume"),
        event(240, "codex_exit"), event(300, "land"), event(350, "codex_exit"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_post_exit_land_seconds{window="1d",version="9.9.9",slug="one",repo="k3d-manager"} 60' in output
    assert 'k3dm_dispatch_post_exit_land_minutes_per_landed{window="1d"} 1.0' in output


def test_post_exit_land_invalid_exit_and_land_timestamps_are_omitted():
    output = dispatch_metrics.render([
        event(1, "start"), {"ts": float("nan"), "event": "codex_exit", "version": "9.9.9", "slug": "one"},
        event(3, "land"),
    ], 0, 10)
    assert "k3dm_dispatch_task_post_exit_land_seconds" not in output


def test_intervention_metrics_require_coverage_marker_and_count_reason():
    legacy = dispatch_metrics.render([
        event(1, "start"), event(2, "intervention", reason="correction"), event(3, "land"),
    ], 0, 10)
    assert "k3dm_dispatch_human_continuation_prompts" not in legacy
    output = dispatch_metrics.render([
        event(1, "start", "one"), event(2, "intervention_coverage_start", "one"),
        event(3, "intervention", "one", reason="correction"), event(4, "land", "one"),
    ], 0, 10)
    assert 'k3dm_dispatch_intervention_tracking_tasks{window="1d"} 1' in output
    assert 'k3dm_dispatch_human_continuation_prompts{window="1d",reason="correction"} 1' in output


def test_recorded_exit_keeps_codex_samples_including_zero_duration():
    output = dispatch_metrics.render([
        event(100, "start"), event(100, "codex_exit", tokens=0), event(399, "land"),
    ], 0, 400)
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 0' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 1' in output
    assert 'k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 0' in output
    assert 'k3dm_dispatch_codex_minutes_per_landed{window="1d"} 0.0' in output


def test_exit_without_launch_adds_nothing():
    output = dispatch_metrics.render([
        event(0, "start"), event(100, "codex_exit", tokens=10),
        event(101, "codex_exit", tokens=20), event(200, "land"),
    ], 0, 200)
    assert 'k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 100' in output
    assert 'k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2' in output


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


def test_bug_dispatch_state_uses_latest_started_task_and_emits_bug_state():
    events = [
        event(1, "start", "plan-task", spec="docs/plans/v1.43.15-test-plan.md"),
        event(2, "codex_exit", "plan-task", exit=0),
        event(3, "start", "bug-exited-old", spec="docs/bugs/2026-11-01-exited-bug.md"),
        event(4, "codex_exit", "bug-exited-old", exit=1),
        event(5, "start", "bug-exited", spec="docs/bugs/2026-11-01-exited-bug.md"),
        event(6, "codex_exit", "bug-exited", exit=0),
        event(7, "start", "bug-running", spec="docs/bugs/2026-11-02-running-bug.md"),
        event(8, "start", "outside-task", spec="docs/issues/2026-11-03-outside.md"),
        event(9, "start", "bad-stem", spec="docs/bugs/invalid_stem.md"),
    ]
    output = dispatch_metrics.render(events, 0, 100)
    assert 'k3dm_dispatch_plan_state{plan="v1.43.15-test-plan",version="9.9.9",slug="plan-task",dispatch_state="awaiting_land"} 1' in output
    assert "k3dm_dispatch_plan_state_skipped 5" in output
    assert 'k3dm_dispatch_bug_state{bug="2026-11-01-exited-bug",version="9.9.9",slug="bug-exited",dispatch_state="awaiting_land"} 1' in output
    assert 'k3dm_dispatch_bug_state{bug="2026-11-02-running-bug",version="9.9.9",slug="bug-running",dispatch_state="running"} 1' in output
    assert output.count("k3dm_dispatch_bug_state{") == 2
    assert 'bug="2026-11-03-outside"' not in output
    assert 'bug="invalid_stem"' not in output


@pytest.mark.parametrize(("events", "expected"), [
    ([event(1,"start" )], "running"),
    ([event(1,"start"),event(2,"codex_exit",exit=1)], "codex_failed"),
    ([event(1,"start"),event(2,"codex_exit",exit=0)], "awaiting_land"),
    ([event(1,"start"),event(2,"codex_exit",exit=1),event(3,"land_refused")], "refused"),
    ([event(1,"start"),event(2,"codex_exit",exit=1),event(3,"land_refused"),event(4,"resume")], "running"),
    ([event(1,"start"),event(2,"land")], "landed"),
    ([event(1,"start"),event(2,"abandon")], "abandoned"),
    ([event(1,"start"),event(2,"codex_exit",exit=0),event(3,"land"),event(4,"intervention_coverage_start"),event(5,"intervention")], "landed"),
    ([event(1,"start"),event(2,"codex_exit",exit=0),event(3,"land"),event(4,"verify")], "landed"),
    ([event(1,"start"),event(2,"codex_exit",exit=0),event(3,"intervention")], "awaiting_land"),
    ([event(1,"start"),event(2,"abandon"),event(3,"codex_usage")], "abandoned"),
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



def test_verified_delivery_cost_and_review_rework(tmp_path):
    spec = tmp_path / "docs/plans/v9.9.9-demo.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("**Status:** VERIFIED\n\n## Acceptance\n\n```yaml\nevidence:\n  - kind: offline\n```\n")
    now = int(time.time())
    rows = [
        event(now - 20, "start", "one", spec="docs/plans/v9.9.9-demo.md"),
        event(now - 10, "codex_exit", "one", tokens=100),
        event(now - 5, "land", "one"),
        event(now - 4, "verify", "one", result="fail"),
        event(now - 3, "verify", "one", result="pass", evidence_sha256="abc", tokens=50),
    ]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_delivered{window="30d"} 1' in output  # agent-audit: allow assert-removed same 19 asserts, f prefix dropped for ruff F541
    assert 'k3dm_dispatch_codex_tokens_per_delivered{window="30d"} 150.0' in output
    assert 'k3dm_dispatch_rework_landed{window="30d",cause="review"} 1' in output
    assert 'k3dm_dispatch_rework_landed{window="30d",cause="any"} 1' in output


def test_delivered_agy_spec_counts_but_stays_out_of_codex_token_mean(tmp_path):
    spec = tmp_path / "docs/plans/v9.9.9-demo.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("**Status:** VERIFIED\n\n## Acceptance\n\n```yaml\nevidence:\n  - kind: offline\n```\n")
    now = int(time.time())
    rows = [
        event(now - 20, "start", "codex", spec="docs/plans/v9.9.9-demo.md"),
        event(now - 10, "codex_exit", "codex", tokens=100),
        event(now - 5, "land", "codex"),
        event(now - 3, "verify", "codex", result="pass", evidence_sha256="abc"),
        event(now - 20, "start", "agy", spec="docs/plans/v9.9.9-demo.md", agent="agy"),
        event(now - 10, "agent_exit", "agy", usage={"total_tokens": 900}),
        event(now - 5, "land", "agy"),
        event(now - 3, "verify", "agy", result="pass", evidence_sha256="abc"),
    ]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_delivered{window="30d"} 2' in output
    assert 'k3dm_dispatch_codex_tokens_per_delivered{window="30d"} 100.0' in output


def test_live_delivery_waiting_and_unknown_spec_are_distinct(tmp_path):
    now = int(time.time())
    spec = tmp_path / "docs/plans/v9.9.9-live.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("**Status:** VERIFIED\n\n## Acceptance\n\n```yaml\nevidence:\n  - kind: live\n```\n")
    rows = [
        event(now - 20, "start", "waiting", spec="docs/plans/v9.9.9-live.md"),
        event(now - 10, "land", "waiting"),
        event(now - 8, "verify", "waiting", result="pass", evidence_sha256="abc"),
        event(now - 20, "start", "unknown"),
        event(now - 10, "land", "unknown"),
        event(now - 8, "verify", "unknown", result="pass", evidence_sha256="abc"),
    ]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_delivered{window="30d"} 0' in output
    assert 'k3dm_dispatch_awaiting_verification{window="30d"} 1' in output
    assert 'k3dm_dispatch_verification_unknown{window="30d"} 1' in output



def test_live_delivery_requires_status_and_well_formed_evidence(tmp_path):
    repo = tmp_path
    spec = repo / "docs/plans/v9.9.9-live.md"
    spec.parent.mkdir(parents=True)
    spec.write_text(dedent("""\
        **Status:** LIVE-VERIFIED
        **Live evidence:** 2026-10-24 · run job-123 · env dev · scenario smoke · commit deadbee · proves E1

        ## Acceptance

        ```yaml
        evidence:
          - kind: live
        ```
        """))
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "docs/plans/v9.9.9-live.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "live evidence"], check=True)
    now = int(time.time())
    rows = [event(now - 20, "start", "live", spec="docs/plans/v9.9.9-live.md"),
            event(now - 15, "codex_exit", "live", tokens=100), event(now - 10, "land", "live"),
            event(now - 5, "verify", "live", result="pass", evidence_sha256="abc", tokens=7)]
    output = dispatch_metrics.render(rows, 0, now, repo_root=repo)
    assert 'k3dm_dispatch_delivered{window="30d"} 1' in output
    assert 'k3dm_dispatch_codex_tokens_per_delivered{window="30d"} 107.0' in output

def test_run_outcome_missing_evidence_classes_and_coverage(tmp_path, monkeypatch):
    now = int(time.time())
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    root.mkdir(parents=True)
    # Event shapes copied from the M4 ledger, 2026-11-01.
    rows = [
        event(now - 100, "start", "unrecorded", run=1),
        event(now - 90, "codex_exit", "unrecorded", run=1, exit=0),
        event(now - 80, "land", "unrecorded"),
        event(now - 100, "start", "superseded", run=1),
        event(now - 90, "codex_exit", "superseded", run=1, exit=0),
        event(now - 80, "resume", "superseded", n=2),
        event(now - 100, "start", "open", run=1),
        event(now - 90, "codex_exit", "open", run=1, exit=0),
        event(now - 7 * 86400 - 10, "start", "stale", run=1),
        event(now - 7 * 86400, "codex_exit", "stale", run=1, exit=0),
        event(now - 100, "start", "accepted", run=1),
        event(now - 90, "codex_exit", "accepted", run=1, exit=0, tree="a"),
        event(now - 80, "land", "accepted", tree="a", test_result="passed"),
        event(now - 100, "start", "rework", run=1),
        event(now - 90, "codex_exit", "rework", run=1, exit=0),
        event(now - 80, "land_refused", "rework", reason="tests"),
        event(now - 70, "resume", "rework", n=2),
        event(now - 100, "start", "failed", run=1),
        event(now - 90, "codex_exit", "failed", run=1, exit=1),
        event(now - 80, "land", "failed"),
    ]
    ledger = root / "ledger.jsonl"
    ledger.write_text("".join(json.dumps(row) + "\n" for row in rows))
    rows = [json.loads(line) for line in ledger.read_text().splitlines()]
    result = dispatch_metrics._run_outcome_metrics(rows, tmp_path, now=now)
    assert result["outcomes"] == {"accepted": 1, "progress": 0, "rework": 1, "failed": 1,
                                  "unrecorded": 1, "superseded": 1, "open": 1, "stale": 1, "unknown": 0}
    assert sum(result["outcomes"].values()) == 7
    assert result["coverage"] == 3 / 7
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    original = dispatch_metrics._run_outcome_metrics

    def old_fallback(*args, **kwargs):
        metrics = original(*args, **kwargs)
        for label in ("unrecorded", "superseded", "open", "stale"):
            metrics["outcomes"]["unknown"] += metrics["outcomes"].pop(label)
        for _, _, _, task_rows in metrics["rows"]:
            for row in task_rows:
                if row["outcome"] in {"unrecorded", "superseded", "open", "stale"}:
                    row["outcome"] = "unknown"
        return metrics

    monkeypatch.setattr(dispatch_metrics, "_run_outcome_metrics", old_fallback)
    baseline = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    def unaffected(text):
        return [line for line in text.splitlines() if not line.startswith((
            "k3dm_dispatch_run_outcomes{", "k3dm_dispatch_task_run_outcome{"))]
    assert unaffected(output) == unaffected(baseline)
    assert 'k3dm_dispatch_run_outcome_coverage{window="30d"} 0.42857142857142855' in output


def test_run_outcomes_use_evidence_and_cumulative_token_increments(tmp_path):
    now = int(time.time())
    rows = [
        event(now - 60, "start", "attempt", run=1),
        event(now - 50, "codex_exit", "attempt", run=1, exit=0, tokens=100, tree="tree-a"),
        event(now - 40, "land_refused", "attempt", reason="tests"),
        event(now - 30, "resume", "attempt", run=2, n=2),
        event(now - 20, "codex_exit", "attempt", run=2, exit=0, tokens=160, tree="tree-b"),
        event(now - 10, "land", "attempt", test_result="passed", tree="tree-b"),
    ]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_run_outcomes{window="30d",outcome="rework"} 1' in output
    assert 'k3dm_dispatch_run_outcomes{window="30d",outcome="accepted"} 1' in output
    assert 'k3dm_dispatch_objectively_rejected_codex_tokens{window="30d"} 100' in output
    assert 'k3dm_dispatch_task_run_codex_tokens{window="30d",version="9.9.9",slug="attempt",run="2",repo="k3d-manager"} 60' in output
    assert 'evidence="land_refused.tests"' in output and 'evidence="land-test.log"' in output
    refused = next(line for line in output.splitlines() if 'evidence="land_refused.tests"' in line)
    assert 'loki_url="/d/k3dm-agent-run-log?var-version=9.9.9&var-slug=attempt&var-run=1&from=now-30d&to=now"' in refused


@pytest.mark.parametrize(("log_text", "expected"), [
    ("ok 1 - first\nok 2 - second\nnot ok 3 - third\n", "2/3 ok"),
    ("89 passed in 1.41s\n", "89 passed"),
    ("ok 1 - first\n89 passed in 1.41s\n", "1/1 ok; 89 passed"),
    ('ok 1 - quote " and newline\nname\n', "1/1 ok"),
])
def test_run_outcome_exports_parsed_result_and_absolute_log_path(tmp_path, monkeypatch, log_text, expected):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    now = int(time.time())
    run_dir = tmp_path / "worktrees" / "9.9.9" / "attempt.run"
    run_dir.mkdir(parents=True)
    (run_dir / "land-test.log").write_text(log_text)
    output = dispatch_metrics.render([
        event(now - 20, "start", "attempt", run=1),
        event(now - 10, "codex_exit", "attempt", run=1, exit=0, tokens=10, tree="tree-a"),
        event(now, "land", "attempt", test_result="passed", tree="tree-a"),
    ], 0, now, repo_root=tmp_path)
    line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
    assert f'evidence_summary="{expected}"' in line
    assert 'evidence_path="9.9.9/attempt.run/land-test.log"' in line
    assert 'loki_url="/d/k3dm-agent-run-log?var-version=9.9.9&var-slug=attempt&var-run=1&from=now-30d&to=now"' in line
    assert str(tmp_path) not in line
    assert 'evidence="land-test.log"' in line


def test_run_outcome_missing_log_and_codex_exit_keep_metrics_valid(tmp_path):
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "missing", run=1),
        event(now - 10, "codex_exit", "missing", run=1, exit=7, tokens=10),
    ], 0, now, repo_root=tmp_path)
    line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
    # agent-audit: allow assert-removed replace exact summary with exit plus local-only explanation
    assert 'evidence_summary="exit 7; local only (not shipped)"' in line
    assert line.split('evidence_path="', 1)[1].split('"', 1)[0].endswith("/missing.run/codex.log")
    assert "\\n" not in line and "\\" not in line and line.count('"') % 2 == 0


def test_failed_startup_exit127_is_local_only_and_retains_codex_log_path(tmp_path, monkeypatch):
    # Keep path expectations independent of whether the runner TMPDIR is under the operator home.
    monkeypatch.setattr(Path, "home", lambda: tmp_path / "home")
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "startup", run=1),
        event(now - 10, "codex_exit", "startup", run=1, exit=127, tokens=10),
    ], 0, now, repo_root=tmp_path)
    line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
    assert 'outcome="failed"' in line and 'evidence="codex_exit.exit"' in line
    assert 'evidence_summary="exit 127; local only (not shipped)"' in line
    assert 'evidence_path="9.9.9/startup.run/codex.log"' in line
    assert 'loki_url=' not in line
    assert str(tmp_path) not in line


def test_legacy_unknown_run_evidence_does_not_claim_a_log(tmp_path):
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "legacy", run=1),
        event(now - 10, "codex_exit", "legacy", run=1, exit=0, tokens=10),
    ], 0, now, repo_root=tmp_path)
    line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
    assert 'evidence="none"' in line and 'evidence_summary="none"' in line
    assert 'evidence_path=""' in line
    assert 'loki_url=' not in line


def test_accepted_missing_log_is_unknown_and_render_succeeds(tmp_path):
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "missing", run=1),
        event(now - 10, "codex_exit", "missing", run=1, exit=0, tokens=10, tree="tree-a"),
        event(now, "land", "missing", test_result="passed", tree="tree-a"),
    ], 0, now, repo_root=tmp_path)
    assert 'evidence_summary="unknown"' in output


def test_agent_neutral_metrics_include_agy_usage_without_codex_series():
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "agy", agent="agy"),
        event(now - 10, "agent_exit", "agy", exit=0, usage={"total_tokens": 500}),
        event(now, "land", "agy"),
    ], 0, now)
    assert 'k3dm_dispatch_task_agent_tokens{window="30d",version="9.9.9",slug="agy",agent="agy",repo="k3d-manager"} 500' in output
    assert 'k3dm_dispatch_task_agent_seconds{window="30d",version="9.9.9",slug="agy",agent="agy",repo="k3d-manager"} 10' in output
    assert 'k3dm_dispatch_task_agent_runs{window="30d",version="9.9.9",slug="agy",agent="agy",repo="k3d-manager"} 1' in output
    assert 'k3dm_dispatch_task_codex_tokens{' not in output


def test_agent_neutral_metrics_match_codex_series():
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 20, "start", "codex", agent="codex"),
        event(now - 10, "codex_exit", "codex", exit=0, tokens=500),
        event(now, "land", "codex"),
    ], 0, now)
    assert 'k3dm_dispatch_task_agent_tokens{window="30d",version="9.9.9",slug="codex",agent="codex",repo="k3d-manager"} 500' in output
    assert 'k3dm_dispatch_task_codex_tokens{window="30d",version="9.9.9",slug="codex",agent="codex",repo="k3d-manager"} 500' in output
    assert 'k3dm_dispatch_task_agent_seconds{window="30d",version="9.9.9",slug="codex",agent="codex",repo="k3d-manager"} 10' in output
    assert 'k3dm_dispatch_task_codex_seconds{window="30d",version="9.9.9",slug="codex",agent="codex",repo="k3d-manager"} 10' in output


def test_agent_neutral_tokens_sum_agy_runs_and_count_them():
    now = int(time.time())
    output = dispatch_metrics.render([
        event(now - 40, "start", "agy-many", agent="agy", run=1),
        event(now - 30, "agent_exit", "agy-many", run=1, usage={"total_tokens": 300}),
        event(now - 20, "resume", "agy-many", agent="agy", run=2),
        event(now - 10, "agent_exit", "agy-many", run=2, usage={"total_tokens": 200}),
        event(now, "land", "agy-many"),
    ], 0, now)
    assert 'k3dm_dispatch_task_agent_tokens{window="30d",version="9.9.9",slug="agy-many",agent="agy",repo="k3d-manager"} 500' in output
    assert 'k3dm_dispatch_task_agent_runs{window="30d",version="9.9.9",slug="agy-many",agent="agy",repo="k3d-manager"} 2' in output


@pytest.mark.parametrize("usage", [None, {"total_tokens": "500"}, {"total_tokens": -1},
                                   {"total_tokens": True}])
def test_invalid_agy_usage_does_not_emit_agent_tokens(usage):
    now = int(time.time())
    usage_fields = {} if usage is None else {"usage": usage}
    row = event(now - 10, "agent_exit", "invalid", **usage_fields)
    output = dispatch_metrics.render([event(now - 20, "start", "invalid", agent="agy"), row,
                                      event(now, "land", "invalid")], 0, now)
    assert 'k3dm_dispatch_task_agent_tokens{' not in output


def test_agent_neutral_per_run_tokens_preserve_codex_series():
    now = int(time.time())
    agy = dispatch_metrics.render([
        event(now - 20, "start", "agy-run", agent="agy", run=1),
        event(now - 10, "agent_exit", "agy-run", run=1, usage={"total_tokens": 500}),
        event(now, "land", "agy-run"),
    ], 0, now)
    assert 'k3dm_dispatch_task_run_agent_tokens{window="30d",version="9.9.9",slug="agy-run",run="1",repo="k3d-manager"} 500' in agy
    assert 'k3dm_dispatch_task_run_codex_tokens{window="30d",version="9.9.9",slug="agy-run",run="1",repo="k3d-manager"}' not in agy
    codex = dispatch_metrics.render([
        event(now - 20, "start", "codex-run", agent="codex", run=1),
        event(now - 10, "codex_exit", "codex-run", run=1, exit=0, tokens=500),
        event(now, "land", "codex-run"),
    ], 0, now)
    assert 'k3dm_dispatch_task_run_agent_tokens{window="30d",version="9.9.9",slug="codex-run",run="1",repo="k3d-manager"} 500' in codex
    assert 'k3dm_dispatch_task_run_codex_tokens{window="30d",version="9.9.9",slug="codex-run",run="1",repo="k3d-manager"} 500' in codex


def test_reset_cumulative_run_counter_stays_unknown(tmp_path):
    now = int(time.time())
    rows = [event(now - 20, "start", "reset", run=1),
            event(now - 15, "codex_exit", "reset", run=1, exit=0, tokens=100),
            event(now - 10, "resume", "reset", run=2, n=2),
            event(now - 5, "codex_exit", "reset", run=2, exit=1, tokens=20)]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_run_outcomes{window="30d",outcome="failed"} 1' in output
    assert 'k3dm_dispatch_objectively_rejected_codex_tokens{window="30d"}' not in output
    assert 'k3dm_dispatch_task_run_codex_tokens{window="30d",version="9.9.9",slug="reset",run="2",repo="k3d-manager"}' not in output


def test_rejected_tokens_are_zero_when_counted_runs_have_no_objective_rejection(tmp_path):
    now = int(time.time())
    rows = [event(now - 20, "start", "accepted", run=1),
            event(now - 15, "codex_exit", "accepted", run=1, exit=0, tokens=100, tree="tree-a"),
            event(now - 10, "land", "accepted", test_result="passed", tree="tree-a"),
            event(now - 8, "start", "abandoned", run=1),
            event(now - 5, "codex_exit", "abandoned", run=1, exit=0, tokens=20),
            event(now - 1, "abandon", "abandoned")]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_objectively_rejected_codex_tokens{window="30d"} 0' in output


def test_rejected_tokens_are_absent_when_window_has_no_runs():
    output = dispatch_metrics.render([], 0, int(time.time()))
    assert 'k3dm_dispatch_objectively_rejected_codex_tokens{window="30d"}' not in output


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



def test_directly_linked_live_verified_bug_has_known_run_cost(tmp_path):
    now = int(time.time())
    spec = tmp_path / "docs/bugs/2026-10-24-dispatch-cost.md"
    spec.parent.mkdir(parents=True)
    spec.write_text(dedent("""\
        **Status:** LIVE-VERIFIED
        **Live evidence:** 2026-10-24 · run job-123 · env dev · scenario smoke · commit deadbee · proves E1

        ## Acceptance

        ```yaml
        evidence:
          - kind: live
        ```
        """))
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "docs/bugs/2026-10-24-dispatch-cost.md"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "live bug"], check=True)
    rows = [event(now - 20, "start", "bug", run=1, spec="docs/bugs/2026-10-24-dispatch-cost.md"),
            event(now - 15, "codex_exit", "bug", run=1, exit=0, tokens=100, tree="tree"),
            event(now - 10, "land", "bug", tree="tree", test_result="passed"),
            event(now - 5, "verify", "bug", result="pass", evidence_sha256="abc")]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_codex_tokens_per_live_verified_bug{window="30d"} 100.0' in output
    assert 'k3dm_dispatch_live_verified_bug_first_pass{window="30d",result="pass"} 1' in output

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
                        not line.startswith(("k3dm_dispatch_task_run_", "k3dm_dispatch_task_agent_", "k3dm_dispatch_task_post_exit_land_", "k3dm_dispatch_task_landing_actor", "k3dm_dispatch_task_handoff_", "k3dm_dispatch_task_primary_coordinator_cost_")) and
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
k3dm_dispatch_rework_landed{window="1d",cause="review"} 0
k3dm_dispatch_rework_landed{window="1d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="1d"} 1.0
k3dm_dispatch_task_codex_tokens{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 20000
k3dm_dispatch_task_codex_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 10
k3dm_dispatch_task_elapsed_seconds{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 30
k3dm_dispatch_task_runs{window="1d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2
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
k3dm_dispatch_rework_landed{window="7d",cause="review"} 0
k3dm_dispatch_rework_landed{window="7d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="7d"} 1.0
k3dm_dispatch_task_codex_tokens{window="7d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 20000
k3dm_dispatch_task_codex_seconds{window="7d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 10
k3dm_dispatch_task_elapsed_seconds{window="7d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 30
k3dm_dispatch_task_runs{window="7d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2
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
k3dm_dispatch_rework_landed{window="30d",cause="review"} 0
k3dm_dispatch_rework_landed{window="30d",cause="any"} 1
k3dm_dispatch_rework_ratio{window="30d"} 1.0
k3dm_dispatch_task_codex_tokens{window="30d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 20000
k3dm_dispatch_task_codex_seconds{window="30d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 10
k3dm_dispatch_task_elapsed_seconds{window="30d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 30
k3dm_dispatch_task_runs{window="30d",version="9.9.9",slug="one",agent="codex",repo="k3d-manager"} 2
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


def test_release_span_union_and_latest_merge_ignore_unlanded_and_refusals():
    rows = [
        event(0, "start", "early-unlanded", version="v1.43.8"),
        event(100, "start", "one", version="v1.43.8"),
        event(100, "start", "one", version="v1.43.8"),
        event(200, "start", "two", version="v1.43.8"),
        event(700, "land", "one", version="v1.43.8"),
        event(800, "land", "two", version="v1.43.8"),
        event(900, "land_refused", "two", version="v1.43.8"),
        event(1000, "release_merged", "release", merged_at=7200, version="v1.43.8"),
        event(1100, "release_merged", "release", merged_at=7200, version="v1.43.8"),
    ]
    output = dispatch_metrics.render(rows, 0, 8000)
    assert 'k3dm_dispatch_release_span_minutes{window="v1.43.8",end="merge"} 120' in output
    assert 'k3dm_dispatch_release_active_minutes{window="v1.43.8"} 11.6667' in output
    assert 'k3dm_dispatch_landed{window="v1.43.8"} 2' in output


def test_release_span_uses_last_land_without_merge_and_not_time_windows():
    rows = [event(0, "start", "early", version="v1.43.8"),
            event(300, "start", "one", version="v1.43.8"),
            event(900, "land", "one", version="v1.43.8"),
            event(1200, "land_refused", "one", version="v1.43.8")]
    output = dispatch_metrics.render(rows, 0, 2000)
    assert 'k3dm_dispatch_release_span_minutes{window="v1.43.8",end="last_land"} 15' in output
    assert 'k3dm_dispatch_release_active_minutes{window="v1.43.8"} 10' in output
    assert "k3dm_dispatch_release_span_minutes{window=\"7d\"" not in output
    assert "k3dm_dispatch_release_active_minutes{window=\"7d\"" not in output


def test_release_merged_does_not_change_other_dispatch_metrics():
    rows = [event(10, "start", "one", version="v1.43.8", run=1),
            event(20, "land", "one", version="v1.43.8")]
    baseline = dispatch_metrics.render(rows, 0, 100)
    recorded = dispatch_metrics.render(rows + [event(30, "release_merged", "release",
                                                      version="v1.43.8", merged_at=90, pr=1)], 0, 100)
    duration_metrics = ("k3dm_dispatch_release_span_minutes", "k3dm_dispatch_release_active_minutes")
    recorded_other = [line for line in recorded.splitlines() if not line.startswith(duration_metrics)]
    baseline_other = [line for line in baseline.splitlines() if not line.startswith(duration_metrics)]
    assert recorded_other == baseline_other


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
    assert 'k3dm_dispatch_task_elapsed_seconds{window="7d",version="v1.43.5",slug="one",agent="codex",repo="k3d-manager"} 3369600' in output
    assert 'k3dm_dispatch_task_elapsed_seconds{window="v1.43.5",version="v1.43.5",slug="one",agent="codex",repo="k3d-manager"} 3369600' in output


def test_global_metrics_are_emitted_once_without_scope_labels():
    output = dispatch_metrics.render([event(1, "start"), event(2, "land")], 0, 10)
    lines = output.splitlines()
    for metric in ("k3dm_dispatch_running", "k3dm_dispatch_awaiting_land",
                   "k3dm_dispatch_ledger_timestamp_seconds", "k3dm_dispatch_ledger_bad_lines"):
        matching = [line for line in lines if line.startswith(metric)]
        assert len(matching) == 1
        assert "{" not in matching[0]


def test_dispatch_dashboard_window_variable_and_release_link():
    dashboard = load_dispatch_dashboard()
    window = dashboard["templating"]["list"][0]
    assert window["type"] == "query"
    assert window["query"]["query"] == "query_result(sort_desc(k3dm_dispatch_window_order))"
    assert window["regex"] == '/window="([^"]+)"/'
    assert window["sort"] == 0 and window["current"]["value"] == "7d"  # agent-audit: allow assert-removed label_values and sort 8 replaced by query_result(sort_desc) and sort 0, bug 2026-11-07-dispatch-window-variable-sorts-versions-alphabetically
    expressions = [target["expr"] for panel in dashboard["panels"]
                   for target in panel.get("targets", [])]
    assert sum("$window" in expr for expr in expressions) == 100  # agent-audit: allow assert-removed includes unreported coordinator share target
    assert all('window="$window"' in expr for expr in expressions
               if any(metric in expr for metric in (
                   "k3dm_dispatch_landed", "k3dm_dispatch_land_attempts",
                   "k3dm_dispatch_verifier_lines_per_landed", "k3dm_dispatch_wait_minutes_per_landed",
                   "k3dm_dispatch_codex_tokens_per_landed", "k3dm_dispatch_elapsed_minutes_per_landed",
                   "k3dm_dispatch_codex_minutes_per_landed", "k3dm_dispatch_task_",
                   "k3dm_dispatch_rework_ratio")))
    per_spec = next(panel for panel in dashboard["panels"] if panel["id"] == 12)
    targets = {target["refId"]: target["expr"] for target in per_spec["targets"]}
    assert targets["E"] == 'max by (version, slug, spec, agent, repo) (k3dm_dispatch_task_spec{window="$window"})'  # agent-audit: allow assert-removed Per spec groups by agent since 210040d8
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


def test_dispatch_window_order_metric_ranks_only_emitted_scopes():
    versions = ("v1.43.0", "v1.43.2", "v1.43.9", "v1.43.10", "v1.43.15")
    events = [event(index, "start", version=version) for index, version in enumerate(versions, start=1)]
    output = dispatch_metrics.render(events, 0, now=100)
    matches = list(re.finditer(r'k3dm_dispatch_window_order\{window="([^"]+)"\} (\d+)', output))
    orders = {match.group(1): int(match.group(2)) for match in matches}
    landed_windows = re.findall(r'k3dm_dispatch_landed\{window="([^"]+)"\}', output)
    assert len(matches) == len(orders) == len(landed_windows)
    assert set(orders) == set(landed_windows)
    assert orders == {
        "1d": 3, "7d": 2, "30d": 1,
        "v1.43.0": 1_043_000, "v1.43.2": 1_043_002,
        "v1.43.9": 1_043_009, "v1.43.10": 1_043_010,
        "v1.43.15": 1_043_015,
    }
    assert sorted(orders, key=orders.get, reverse=True) == [
        "v1.43.15", "v1.43.10", "v1.43.9", "v1.43.2", "v1.43.0", "1d", "7d", "30d"]
    assert "v9.9.9" not in orders


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


def test_agy_run_api_cost_uses_start_model_and_deduplicates_usage():
    prices = {
        "gemini-3.8-flash": {"input": 0.75, "cached_input": 0.075, "output": 3.75},
        "gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20},
    }
    captured = {"input_tokens": 951876, "output_tokens": 54141, "thinking_tokens": 23889,
                "cache_read_tokens": 51703491, "total_tokens": 1006017}
    rows = [
        event(10, "start", "agy-priced", run=1, agent="agy", model="gemini-3.8-flash-medium"),
        event(11, "agent_exit", "agy-priced", run=1, exit=0, usage=captured),
        event(11, "agent_usage", "agy-priced", run=1, usage=dict(captured)),
        event(12, "land", "agy-priced"),
        event(20, "start", "agy-unpriced", run=1, agent="agy", model="gemini-9-unknown-medium"),
        event(21, "agent_exit", "agy-unpriced", run=1, exit=0, usage=captured),
        event(21, "agent_usage", "agy-unpriced", run=1, usage=dict(captured)),
        event(22, "land", "agy-unpriced"),
        event(23, "start", "agy-malformed", run=1, agent="agy", model="gemini-3.8-flash-low"),
        event(24, "agent_exit", "agy-malformed", run=1,
              usage={"input_tokens": 10, "cache_read_tokens": 0, "output_tokens": 2}),
        event(25, "land", "agy-malformed"),
        event(30, "start", "codex-control", run=1, agent="codex"),
        event(31, "codex_usage", "codex-control", session="codex-s", model="gpt-5.6-luna",
              input=1_000_000, cached_input=0, output=0),
        event(32, "land", "codex-control"),
    ]
    expected = (951876 * 0.75 + 51703491 * 0.075 + (54141 + 23889) * 3.75) / 1_000_000
    priced_task = dispatch_metrics._task_metrics(rows[:4], rows[3], prices)
    unpriced_task = dispatch_metrics._task_metrics(rows[4:8], rows[7], prices)
    malformed_task = dispatch_metrics._task_metrics(rows[8:11], rows[10], prices)
    assert priced_task["api_cost_usd"] == pytest.approx(expected)
    assert unpriced_task["api_cost_usd"] is None
    assert malformed_task["api_cost_usd"] is None
    assert dispatch_metrics._cost(rows[12], prices) == pytest.approx(0.2)

    output = dispatch_metrics.render(rows, 0, 40, prices=prices)
    assert f'k3dm_dispatch_task_api_cost_usd{{window="1d",version="9.9.9",slug="agy-priced",agent="agy",repo="k3d-manager"}} {expected}' in output
    assert 'k3dm_dispatch_task_api_cost_usd{window="1d",version="9.9.9",slug="agy-unpriced"' not in output
    assert f'k3dm_dispatch_api_cost_usd{{window="1d"}} {expected}' in output
    assert f'k3dm_dispatch_api_cost_per_landed_usd{{window="1d"}} {expected / 4}' in output


def test_session_usage_splits_cumulative_totals_by_run_model_and_keeps_session_count(tmp_path):
    # Real ledger sequence read on m4-air, 2026-11-06; cached_input values exercise the same cumulative-counter split.
    rows = [
        event(10, "codex_usage", session="pr-checks-history-semantics-luna", model="gpt-6-luna",
              input=1_310_459, cached_input=1_000_000, output=8_037),
        event(11, "codex_usage", session="pr-checks-history-semantics-luna", model="gpt-6.1-sol",
              input=2_013_348, cached_input=1_500_000, output=15_964),
    ]
    rates = {
        "gpt-6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20},
        "gpt-6.1-sol": {"input": 0.30, "cached_input": 0.03, "output": 1.50},
    }
    shares = dispatch_metrics._session_records(rows)["pr-checks-history-semantics-luna"]
    assert [(item["model"], item["input"], item["cached_input"], item["output"]) for item in shares] == [
        ("gpt-6-luna", 1_310_459, 1_000_000, 8_037),
        ("gpt-6.1-sol", 702_889, 500_000, 7_927),
    ]
    luna_cost = dispatch_metrics._cost(shares[0], rates)
    sol_cost = dispatch_metrics._cost(shares[1], rates)
    assert luna_cost == pytest.approx(((310_459 * 0.20) + (1_000_000 * 0.02) + (8_037 * 1.20)) / 1_000_000)
    assert sol_cost == pytest.approx(((202_889 * 0.30) + (500_000 * 0.03) + (7_927 * 1.50)) / 1_000_000)
    assert sum(item["input"] for item in shares) == 2_013_348
    assert sum(item["cached_input"] for item in shares) == 1_500_000
    assert sum(item["output"] for item in shares) == 15_964
    task = [event(9, "start", "pr-checks-history-semantics-luna"), *rows]
    assert dispatch_metrics._task_metrics(task, {"ts": 12}, rates)["api_cost_usd"] == pytest.approx(luna_cost + sol_cost)

    home = tmp_path / "codex"
    write_session(home, "pr-checks-history-semantics-luna", 10, 20)
    output = dispatch_metrics.render(rows, 0, 20, prices=rates, codex_home=home)
    assert 'model="gpt-6-luna",kind="uncached_input"} 310459' in output
    assert 'model="gpt-6-luna",kind="cached_input"} 1000000' in output
    assert 'model="gpt-6-luna",kind="output"} 8037' in output
    assert 'model="gpt-6.1-sol",kind="uncached_input"} 202889' in output
    assert 'model="gpt-6.1-sol",kind="cached_input"} 500000' in output
    assert 'model="gpt-6.1-sol",kind="output"} 7927' in output
    assert f'model="gpt-6-luna"}} {luna_cost}' in output
    assert f'model="gpt-6.1-sol"}} {sol_cost}' in output
    assert 'k3dm_dispatch_codex_sessions{window="1d",ledgered="true"} 1' in output


def test_one_model_multi_event_session_keeps_previous_totals_and_cost():
    # One-model positive control: cumulative session totals remain unchanged when events repeat one model.
    rows = [
        event(10, "codex_usage", session="single-model", model="gpt-6-luna",
              input=1_310_459, cached_input=1_000_000, output=8_037),
        event(11, "codex_usage", session="single-model", model="gpt-6-luna",
              input=2_013_348, cached_input=1_500_000, output=15_964),
    ]
    rates = {"gpt-6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}}
    shares = dispatch_metrics._session_records(rows)["single-model"]
    assert len(shares) == 2
    assert [item["input"] for item in shares] == [1_310_459, 702_889]
    assert [item["cached_input"] for item in shares] == [1_000_000, 500_000]
    assert [item["output"] for item in shares] == [8_037, 7_927]
    assert sum(dispatch_metrics._cost(item, rates) for item in shares) == pytest.approx(
        dispatch_metrics._cost(rows[-1], rates))


def test_decreasing_session_totals_start_a_new_usage_segment_without_negatives():
    rows = [
        event(10, "codex_usage", session="reset", model="gpt-6-luna",
              input=100, cached_input=30, output=50),
        event(11, "codex_usage", session="reset", model="gpt-6.1-sol",
              input=10, cached_input=5, output=4),
        event(12, "codex_usage", session="reset", model="gpt-6.1-sol",
              input=15, cached_input=6, output=9),
    ]
    shares = dispatch_metrics._session_records(rows)["reset"]
    assert [(item["input"], item["cached_input"], item["output"]) for item in shares] == [
        (100, 30, 50), (10, 5, 4), (5, 1, 5)]
    assert all(item[key] >= 0 for item in shares for key in ("input", "cached_input", "output"))


def test_null_model_event_is_unpriced_only_for_its_increment():
    rows = [
        event(10, "codex_usage", session="null-model", model="gpt-6-luna",
              input=100, cached_input=30, output=50),
        event(11, "codex_usage", session="null-model", model=None,
              input=150, cached_input=45, output=70),
    ]
    rates = {"gpt-6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20}}
    shares = dispatch_metrics._session_records(rows)["null-model"]
    assert [item["input"] for item in shares] == [100, 50]
    assert [item["cached_input"] for item in shares] == [30, 15]
    assert [item["output"] for item in shares] == [50, 20]
    assert dispatch_metrics._cost(shares[0], rates) is not None
    assert dispatch_metrics._cost(shares[1], rates) is None
    lines = []
    dispatch_metrics._render_cost(lines, "1d", {"null-model": shares}, 0, rates)
    assert any('model="gpt-6-luna",kind="uncached_input"} 70' in line for line in lines)
    assert any('model="unknown",kind="uncached_input"} 35' in line for line in lines)
    assert 'k3dm_dispatch_api_cost_unpriced_sessions{window="1d"} 1' in lines


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
              "Dispatch coverage (by cost)", "By model", "Projected / month",
              "Codex spend by category", "Ledger gaps", "Spend outside dispatch"}
    # agent-audit: allow assert-removed Ledger coverage replaced by Dispatch coverage (by cost), Codex spend by category, Ledger gaps and Spend outside dispatch
    assert titles <= by_title.keys()
    assert "Ledger coverage" not in by_title
    assert 'window="7d"' in by_title["Projected / month"]["targets"][0]["expr"]
    assert by_title["Projected / month"]["targets"][0]["expr"] == (
        'k3dm_dispatch_api_cost_usd{window="7d"} / '
        'k3dm_dispatch_api_cost_observed_days{window="7d"} * 30 + '
        'k3dm_dispatch_claude_api_cost_usd{window="7d"} / '
        'k3dm_dispatch_claude_api_cost_observed_days{window="7d"} * 30')
    assert "by session start time" in by_title["Projected / month"]["description"]
    assert 'window="$window"' not in by_title["Projected / month"]["targets"][0]["expr"]
    outside_override = next(item for item in by_title["Ledger gaps"]["fieldConfig"]["overrides"]
                            if item["matcher"] == {"id": "byName", "options": "cost"})
    properties = {prop["id"]: prop["value"] for prop in outside_override["properties"]}
    assert properties["unit"] == "currencyUSD"
    assert properties["decimals"] == 2
    verified = by_title["Claude cost per verified spec"]["targets"][0]["expr"]
    live = by_title["Claude cost per live-verified resolution"]["targets"][0]["expr"]
    assert verified == ('sum by (window) (k3dm_dispatch_claude_api_cost_usd{window="$window"}) / '
                        '(sum by (window) (k3dm_claude_verified_specs{window="$window"}) > 0)')
    assert live == ('sum by (window) (k3dm_dispatch_claude_api_cost_usd{window="$window"}) / '
                    '(sum by (window) (k3dm_claude_verified_specs{window="$window",level="live"}) > 0)')
    # agent-audit: allow assert-removed both cost exprs now aggregate the numerator by window; asserts updated, not dropped
    for expr in (verified, live):
        numerator, denominator = expr.split(" / ", 1)
        assert numerator.startswith("sum by (window) (") and denominator.startswith("(sum by (window) (")
    boxes = []
    for panel in dashboard["panels"]:
        pos = panel.get("gridPos")
        if not pos or panel.get("type") == "row":
            continue
        rect = (pos["x"], pos["y"], pos["x"] + pos["w"], pos["y"] + pos["h"])
        for prior in boxes:
            assert rect[2] <= prior[0] or prior[2] <= rect[0] or rect[3] <= prior[1] or prior[3] <= rect[1]
        boxes.append(rect)


def test_dry_run_exports_verified_spec_counts_for_each_window_and_level():
    env = os.environ.copy()
    env["K3DM_DISPATCH_PUSHGATEWAY_URL"] = "http://127.0.0.1:9"
    proc = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                          env=env, check=True, timeout=60)
    lines = [line for line in proc.stdout.splitlines()
             if line.startswith("k3dm_claude_verified_specs")]
    assert len(lines) == len(dispatch_metrics.WINDOWS) * 3
    assert all('level=' in line for line in lines)
    assert all(any(f'window="{window}",level="{level}"' in line for line in lines)
               for window in dispatch_metrics.WINDOWS
               for level in ("live", "verified", "unverified"))
    assert not any(line.startswith('k3dm_claude_verified_specs{window=') and 'level=' not in line
                   for line in proc.stdout.splitlines())


def test_by_model_target_is_instant_and_uses_model_legend():
    panel = next(panel for panel in load_dispatch_dashboard()["panels"] if panel["id"] == 27)
    target = panel["targets"][0]
    assert target["instant"] is True
    assert target["legendFormat"] == "{{model}}"


def test_ledger_coverage_targets_have_named_legends():
    # agent-audit: allow assert-removed Ledger coverage replaced with Ledger gaps and Codex spend by category
    dashboard = load_dispatch_dashboard()
    by_title = {p["title"]: p for p in dashboard["panels"]}
    gaps = by_title["Ledger gaps"]
    assert gaps["targets"][0]["legendFormat"] == "cost"
    assert gaps["targets"][1]["legendFormat"] == "sessions"
    assert "Ledger coverage" not in by_title


@pytest.mark.external
def test_by_model_promql_returns_one_series_per_model(tmp_path):
    dashboard = load_dispatch_dashboard()
    panel = next(panel for panel in dashboard["panels"] if panel["id"] == 27)
    expression = panel["targets"][0]["expr"].replace('$window', '7d')
    promtool = resolve_promtool()

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
    result = subprocess.run([promtool, "test", "rules", str(tests)],
                            cwd=tmp_path, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_per_spec_footer_totals_all_but_time_to_land_and_by_model_starts_at_zero():
    panels = {panel["id"]: panel for panel in load_dispatch_dashboard()["panels"]}
    footer = panels[12]["options"]["footer"]
    assert footer["show"] is True
    assert footer["reducer"] == ["sum"]
    assert {"Value #A", "Value #B", "Value #D", "Value #F"} <= set(footer["fields"])
    assert {"Value #C", "Time to land"}.isdisjoint(footer["fields"])
    assert panels[27]["fieldConfig"]["defaults"]["min"] == 0


def test_per_spec_reads_agent_neutral_series_and_keeps_api_equiv_codex_only():
    panel = {p["id"]: p for p in load_dispatch_dashboard()["panels"]}[12]
    exprs = {t["refId"]: t["expr"] for t in panel["targets"]}
    assert "k3dm_dispatch_task_agent_tokens{" in exprs["A"]
    assert "k3dm_dispatch_task_agent_seconds{" in exprs["B"]
    assert "k3dm_dispatch_task_agent_runs{" in exprs["D"]
    assert "k3dm_dispatch_task_api_cost_usd{" in exprs["F"]
    organize = next(t for t in panel["transformations"] if t["id"] == "organize")["options"]
    assert {k: organize["renameByName"][k] for k in ("Value #A", "Value #B", "Value #D")} == {
        "Value #A": "Tokens", "Value #B": "Agent time", "Value #D": "Runs"}
    assert "Codex" not in " ".join(organize["renameByName"].values())
    assert "API equiv. stays Codex-only" in panel["description"]


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


def test_claude_rollup_overlapping_saves_use_private_temp_files(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    projects.mkdir()
    transcript = projects / "one.jsonl"
    transcript.write_text(json.dumps({"type": "assistant", "timestamp": "2026-10-24T12:00:00Z",
        "message": {"id": "one", "model": "m", "usage": {"input_tokens": 1}}}) + "\n")
    cache = tmp_path / "cache.json"
    real_replace = os.replace
    nested_results = []
    triggered = False

    def overlap_replace(source, target):
        nonlocal triggered
        if not triggered:
            triggered = True
            nested_results.append(dispatch_metrics._claude_rollup(projects, cache))
        real_replace(source, target)

    monkeypatch.setattr(dispatch_metrics.os, "replace", overlap_replace)
    outer_records = dispatch_metrics._claude_rollup(projects, cache)
    assert outer_records == nested_results[0]
    assert json.loads(cache.read_text())["records"]["one"]["model"] == "m"


def test_claude_rollup_save_failure_is_reported_and_cleaned(tmp_path, monkeypatch, capsys):
    projects = tmp_path / "projects"
    projects.mkdir()
    transcript = projects / "one.jsonl"
    transcript.write_text(json.dumps({"type": "assistant", "timestamp": "2026-10-24T12:00:00Z",
        "message": {"id": "one", "model": "m", "usage": {"input_tokens": 1}}}) + "\n")
    cache = tmp_path / "cache.json"

    def fail_replace(source, target):
        raise FileNotFoundError("simulated rename race")

    monkeypatch.setattr(dispatch_metrics.os, "replace", fail_replace)
    records = dispatch_metrics._claude_rollup(projects, cache)
    assert records == [{"ts": "2026-10-24T12:00:00Z", "model": "m", "speed": None,
        "input": 1, "cache_5m": 0, "cache_1h": 0, "cache_read": 0, "output": 0,
        "id": "one", "subagent": False,
        "session": hashlib.sha256(str(transcript).encode()).hexdigest()}]
    assert "claude rollup cache not saved: simulated rename race" in capsys.readouterr().err
    assert list(tmp_path.glob("cache.json.*.tmp")) == []


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
    prefix = f'k3dm_dispatch_task_claude_api_cost_usd{{window="{window}",version="{version}",slug="{slug}",repo="k3d-manager"}} '
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
            daily[zone] = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_claude_daily_tokens{")]
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
    assert target["expr"] == 'sum by (version, slug, repo) (k3dm_dispatch_task_claude_api_cost_usd{window="$window"})'  # agent-audit: allow assert-removed Per spec groups by repo (cross-repo M5)
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
    dashboard = load_dashboard(DASHBOARD_PATH.with_name("grafana-dashboard-agent-cost.yaml"), "agent-cost.json")
    panel = next(p for p in dashboard["panels"] if p.get("title") == "Claude tokens per day")
    steps = {t["id"]: t.get("options", {}) for t in panel["transformations"]}
    assert [t["id"] for t in panel["transformations"]][:2] == ["merge", "groupingToMatrix"]
    assert steps["groupingToMatrix"] == {"rowField": "date", "columnField": "model", "valueField": "Value"}
    assert panel["options"]["xField"] == "date"


def test_claude_compactions_reads_and_tally_privacy(tmp_path):
    assert os.environ.get("K3DM_DISPATCH_PUSHGATEWAY_URL") == "http://127.0.0.1:9"
    now = calendar.timegm(time.strptime("2026-10-24T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    t_recent = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 3600))
    t_week = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 3 * 86400))
    t_old = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 40 * 86400))
    projects = tmp_path / "projects"
    projects.mkdir()
    session_lines = [
        json.dumps({"type": "user", "message": {"content": "SECRET-PROMPT-TOKEN-123"}}),
        json.dumps({"type": "assistant", "timestamp": t_recent, "message": {
            "id": "m1", "model": "m", "usage": {"input_tokens": 10},
            "content": [{"type": "tool_use", "id": "tu1", "name": "Read",
                         "input": {"file_path": "/secret/path/alpha.py"}}]}}),
        "not valid json {{{",
        json.dumps({"type": "system", "subtype": "compact_boundary", "timestamp": t_recent,
                    "sessionId": "s1", "compactMetadata": {"trigger": "manual", "preTokens": 113270,
                                                           "postTokens": 18037, "durationMs": 45152}}),
        json.dumps({"type": "user", "isCompactSummary": True, "message": {"content": "SECRET-SUMMARY"}}),
        json.dumps({"type": "assistant", "timestamp": t_recent, "message": {
            "id": "m2", "model": "m", "usage": {"input_tokens": 20},
            "content": [
                {"type": "tool_use", "id": "tu2", "name": "Read", "input": {"file_path": "/secret/path/alpha.py"}},
                {"type": "tool_use", "id": "tu3", "name": "Read", "input": {"file_path": "/secret/path/beta.py"}},
            ]}}),
        json.dumps({"type": "system", "subtype": "compact_boundary", "timestamp": t_week,
                    "sessionId": "s1", "compactMetadata": {"trigger": "auto", "preTokens": 195000}}),
        json.dumps({"type": "system", "subtype": "compact_boundary", "timestamp": t_week,
                    "sessionId": "s1", "compactMetadata": {"trigger": "auto", "preTokens": "not-an-int"}}),
        json.dumps({"type": "system", "subtype": "compact_boundary", "timestamp": t_old,
                    "sessionId": "s1"}),
        json.dumps({"type": "assistant", "timestamp": t_recent, "message": {
            "id": "m3", "model": "m", "usage": {"input_tokens": 5},
            "content": [{"type": "tool_use", "id": "tu4", "name": "Read",
                         "input": {"file_path": "/secret/path/beta.py"}}]}}),
    ]
    (projects / "session.jsonl").write_text("\n".join(session_lines) + "\n")
    repo = tmp_path / "repo"
    (repo / "docs/metrics").mkdir(parents=True)
    tally_md = """# Experiment
## Settings
| date | auto_compact_tokens | note |
|---|---|---|
| 2026-10-01 | 200000 | SECRET-NOTE-INITIAL |
| 2026-10-20 | 250000 | SECRET-NOTE-RAISED |
| 2099-01-01 | 999999 | SECRET-FUTURE-SETTING |
| bad-date | not-int | unparseable |

## Incidents
| date | kind | spec | note |
|---|---|---|---|
| 2026-10-24 | resumption-failure | v1.43.6-secret-spec | SECRET-INCIDENT-NOTE |
| 2026-10-20 | missing-context-correction | v1.43.5-secret-spec | SECRET-CORRECTION-NOTE |
| bad-row | unknown-kind | v1.0.0-bad | broken |
"""
    (repo / "docs/metrics/context-window-experiment.md").write_text(tally_md)
    ctx = {}
    cache = tmp_path / "cache.json"
    records = dispatch_metrics._claude_rollup(projects, cache, ctx)
    output = dispatch_metrics.render([event(now - 10, "start", "s1", version="v1.43.6")], 0, now,
                                     claude_records=records, claude_prices=_claude_rates(),
                                     claude_context=ctx, repo_root=repo)
    assert 'k3dm_claude_compactions{window="1d",trigger="manual"} 1' in output
    assert 'k3dm_claude_compactions{window="1d",trigger="auto"} 0' in output
    assert 'k3dm_claude_compactions{window="7d",trigger="auto"} 2' in output
    assert 'k3dm_claude_compactions{window="7d",trigger="manual"} 1' in output
    assert 'k3dm_claude_compaction_pre_tokens_sum{window="7d",trigger="manual"} 113270' in output
    assert 'k3dm_claude_compaction_pre_tokens_sum{window="7d",trigger="auto"} 195000' in output
    assert 'k3dm_claude_reads{window="1d",kind="all"} 4' in output
    assert 'k3dm_claude_reads{window="1d",kind="reread_after_compaction"} 2' in output
    assert 'k3dm_claude_context_incidents{window="1d",kind="resumption-failure"} 1' in output
    assert 'k3dm_claude_context_incidents{window="1d",kind="missing-context-correction"} 0' in output
    assert 'k3dm_claude_context_incidents{window="7d",kind="missing-context-correction"} 1' in output
    assert "k3dm_claude_auto_compact_tokens 250000\n" in output
    assert 'window="v1.43.6"' not in "\n".join(
        line for line in output.splitlines() if line.startswith("k3dm_claude_"))
    for forbidden in ("SECRET-PROMPT", "SECRET-SUMMARY", "/secret/path", "alpha.py", "beta.py",
                      "SECRET-NOTE", "SECRET-FUTURE", "v1.43.6-secret-spec", "v1.43.5-secret-spec",
                      "SECRET-INCIDENT", "SECRET-CORRECTION"):
        assert forbidden not in output
        assert forbidden not in cache.read_text()


def test_claude_auto_compact_tokens_omitted_when_settings_table_empty(tmp_path):
    repo = tmp_path / "repo"
    (repo / "docs/metrics").mkdir(parents=True)
    (repo / "docs/metrics/context-window-experiment.md").write_text(
        "| date | auto_compact_tokens | note |\n|---|---|---|\n"
        "| 2099-01-01 | 300000 | future only |\n")
    output = dispatch_metrics.render([], 0, 1_800_000_000, repo_root=repo)
    assert "k3dm_claude_auto_compact_tokens" not in output


def test_claude_verified_specs_counts_closed_status_transitions_in_window(tmp_path):
    now = 1_800_000_000
    repo = tmp_path / "repo"
    (repo / "docs/bugs").mkdir(parents=True)
    (repo / "docs/plans").mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "t@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "T"], check=True)

    def commit_doc(rel, status, ts):
        p = repo / rel
        p.write_text(f"# Doc\n\n**Status:** {status}\n")
        subprocess.run(["git", "-C", str(repo), "add", rel], check=True)
        env = os.environ.copy()
        env["GIT_AUTHOR_DATE"] = f"{ts} +0000"
        env["GIT_COMMITTER_DATE"] = f"{ts} +0000"
        subprocess.run(["git", "-C", str(repo), "commit", "-qm", f"{rel} {status}"], check=True, env=env)

    commit_doc("docs/bugs/outside.md", "LIVE-VERIFIED", now - 40 * 86400)
    commit_doc("docs/bugs/in-window.md", "OPEN", now - 5 * 86400)
    commit_doc("docs/bugs/in-window.md", "LIVE-VERIFIED — proven", now - 2 * 86400)
    commit_doc("docs/bugs/in-window.md", "VERIFIED — updated note", now - 3600)
    commit_doc("docs/bugs/new-verified.md", "Fixed on v1.43.10", now - 3 * 86400)
    commit_doc("docs/bugs/new-unverified.md", "LANDED", now - 3 * 86400)
    backfill = repo / "docs/bugs/backfill.md"
    backfill.write_text("# Doc\n\nNo status recorded yet.\n")
    subprocess.run(["git", "-C", str(repo), "add", "docs/bugs/backfill.md"], check=True)
    env = os.environ.copy()
    env["GIT_AUTHOR_DATE"] = f"{now - 3 * 86400} +0000"
    env["GIT_COMMITTER_DATE"] = env["GIT_AUTHOR_DATE"]
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "backfill precursor"], check=True, env=env)
    backfill.write_text("# Doc\n\n**Status:** CLOSED — backfilled\n")
    subprocess.run(["git", "-C", str(repo), "add", "docs/bugs/backfill.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "backfill status"], check=True, env=env)
    commit_doc("docs/plans/v1.43.6-open.md", "IN PROGRESS", now - 3600)

    output = dispatch_metrics.render([], 0, now, repo_root=repo)
    assert 'k3dm_claude_verified_specs{window="1d",level="live"} 0' in output
    assert 'k3dm_claude_verified_specs{window="1d",level="verified"} 0' in output
    assert 'k3dm_claude_verified_specs{window="1d",level="unverified"} 0' in output
    assert 'k3dm_claude_verified_specs{window="7d",level="live"} 1' in output
    assert 'k3dm_claude_verified_specs{window="7d",level="verified"} 1' in output
    assert 'k3dm_claude_verified_specs{window="7d",level="unverified"} 1' in output
    assert 'k3dm_claude_verified_specs{window="30d",level="live"} 1' in output
    assert 'k3dm_claude_verified_specs{window="30d",level="verified"} 1' in output
    assert 'k3dm_claude_verified_specs{window="30d",level="unverified"} 1' in output
    assert all('level=' in line for line in output.splitlines() if line.startswith("k3dm_claude_verified_specs"))


def test_codex_activity_exports_sessions_tokens_quota_and_untracked(tmp_path):
    from datetime import datetime, timezone
    now = time.time()
    home = tmp_path / "codex"
    day = datetime.fromtimestamp(now, timezone.utc).strftime("%Y/%m/%d")
    folder = home / "sessions" / day
    folder.mkdir(parents=True)
    path = folder / "rollout-one.jsonl"
    path.write_text("\n".join([
        json.dumps({"type": "session_meta", "payload": {"id": "sid", "timestamp": datetime.fromtimestamp(now-10, timezone.utc).isoformat(), "cwd": "/repo/shop", "originator": "codex_exec", "account_id": "secret"}}),
        json.dumps({"type": "event_msg", "timestamp": datetime.fromtimestamp(now-2, timezone.utc).isoformat(), "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 30}}, "rate_limits": {"primary": {"used_percent": 30, "window_minutes": 300, "resets_at": now+10}, "secondary": {"used_percent": 40, "window_minutes": 10080, "resets_at": now+20}}}}),
        json.dumps({"type": "event_msg", "payload": {"type": "task_complete", "duration_ms": 1500}}),
    ]) + "\n")
    output = dispatch_metrics.render([], 0, now, prices={}, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="exec",repo="shop"} 1' in output
    assert 'k3dm_codex_untracked_sessions{window="1d",mode="exec",repo="shop"} 1' in output
    assert 'k3dm_codex_tokens{window="1d",mode="exec",repo="shop",kind="uncached_input"} 80' in output
    assert 'k3dm_codex_active_seconds{window="1d",mode="exec"} 1.5' in output
    assert 'k3dm_codex_quota_used_ratio{limit="secondary",window_minutes="10080"} 0.4' in output
    assert "secret" not in output


def test_dispatch_worktree_activity_uses_latest_ledger_repo(tmp_path, monkeypatch):
    now = time.time()
    root = tmp_path / "worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    home = tmp_path / "codex"
    cwd = root / "v1.43.7" / "some-slug"
    write_session(home, "dispatch", now - 10, now, cwd)
    output = dispatch_metrics.render([
        event(now - 2, "start", "some-slug", version="v1.43.7", repo="shopping-cart-order"),
        event(now - 1, "start", "some-slug", version="v1.43.7", repo="shopping-cart-order"),
    ], 0, now, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="other",repo="shopping-cart-order"} 1' in output
    assert str(tmp_path) not in output


def test_dispatch_worktree_without_ledger_repo_defaults_to_manager(tmp_path, monkeypatch):
    now = time.time()
    root = tmp_path / "worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    home = tmp_path / "codex"
    cwd = root / "v1.43.7" / "legacy-slug"
    write_session(home, "legacy-dispatch", now - 10, now, cwd)
    output = dispatch_metrics.render([
        event(now - 1, "start", "legacy-slug", version="v1.43.7"),
    ], 0, now, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="other",repo="k3d-manager"} 1' in output


def test_dispatch_worktree_falls_back_to_gitdir_repo_and_nested_cwd(tmp_path, monkeypatch):
    now = time.time()
    root = tmp_path / "worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    home = tmp_path / "codex"
    cwd = root / "v1.43.7" / "nested-slug"
    (cwd / "subdir").mkdir(parents=True)
    (cwd / ".git").write_text(f"gitdir: {tmp_path}/my-repo/.git/worktrees/s\n")
    write_session(home, "nested-dispatch", now - 10, now, cwd / "subdir")
    output = dispatch_metrics.render([], 0, now, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="other",repo="my-repo"} 1' in output


def test_dispatch_worktree_without_match_or_gitdir_is_other(tmp_path, monkeypatch):
    now = time.time()
    root = tmp_path / "worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    home = tmp_path / "codex"
    cwd = root / "v1.43.7" / "unknown-slug"
    write_session(home, "unknown-dispatch", now - 10, now, cwd)
    output = dispatch_metrics.render([], 0, now, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="other",repo="other"} 1' in output


def test_dispatch_sessions_outside_worktree_keep_folder_label(tmp_path, monkeypatch):
    now = time.time()
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path / "worktrees"))
    home = tmp_path / "codex"
    write_session(home, "outside", now - 10, now, tmp_path / "my-project")
    output = dispatch_metrics.render([], 0, now, codex_home=home)
    assert 'k3dm_codex_sessions{window="1d",mode="other",repo="my-project"} 1' in output


def test_eleven_dispatch_worktrees_fold_into_manager_not_other(tmp_path, monkeypatch):
    now = time.time()
    root = tmp_path / "worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    home = tmp_path / "codex"
    starts = []
    for index in range(11):
        slug = f"dispatch-{index}"
        write_session(home, slug, now - 10, now, root / "v1.43.7" / slug,
                      {"input_tokens": 10, "cached_input_tokens": 0, "output_tokens": 0})
        starts.append(event(now - index, "start", slug, version="v1.43.7"))
    output = dispatch_metrics.render(starts, 0, now, codex_home=home)
    assert 'k3dm_codex_tokens{window="1d",mode="other",repo="k3d-manager",kind="uncached_input"} 110' in output
    assert not any('repo="other"' in line for line in output.splitlines() if line.startswith("k3dm_codex_tokens{"))


def test_agy_ledger_missing_or_corrupt_is_nonfatal(tmp_path, monkeypatch):
    # agent-audit: allow assert-removed every render now emits exactly one source line; the replacements assert that line and nothing else
    brain = tmp_path / "brain"
    ledger = tmp_path / "agent-sessions/agy.jsonl"
    assert not brain.exists()
    assert not ledger.exists() and tmp_path in ledger.parents
    monkeypatch.setenv("K3DM_AGY_BRAIN_DIR", str(brain))
    output = []
    dispatch_metrics._agy_metrics(output, ledger, 100)
    assert len(output) == 1 and 'source="none"' in output[0]
    output.clear()
    path = tmp_path / "agy.jsonl"
    path.write_text("{bad}\n")
    dispatch_metrics._agy_metrics(output, path, 100)
    assert len(output) == 1 and 'source="ledger"' in output[0]


# Step keys mirror read-only output from m4-air on 2026-11-06; values and session ids below are invented.
def write_agy_transcript(brain, session, rows, now):
    path = brain / session / ".system_generated/logs/transcript_full.jsonl"
    path.parent.mkdir(parents=True)
    path.write_text("".join(row if isinstance(row, str) else json.dumps(row) + "\n" for row in rows))
    os.utime(path, (now, now))
    return path


def agy_scratch(monkeypatch, tmp_path, now):
    home = tmp_path / "home"
    brain = home / ".gemini/antigravity-cli/brain"
    ledger_dir = home / ".local/share/k3d-manager/agent-sessions"
    worktree_root = tmp_path / "repo"
    home.mkdir()
    brain.mkdir(parents=True)
    ledger_dir.mkdir(parents=True)
    worktree_root.mkdir()
    assert home != Path.home() and brain.is_dir() and ledger_dir.is_dir() and worktree_root.is_dir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("K3DM_AGY_BRAIN_DIR", str(brain))
    monkeypatch.setenv("K3DM_AGENT_LEDGER_DIR", str(ledger_dir))
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(worktree_root))
    monkeypatch.setenv("K3DM_DISPATCH_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    return home, brain, ledger_dir, worktree_root


def test_agy_transcripts_report_in_window_tokens_active_time_and_source(monkeypatch, tmp_path):
    now = 1_800_000_600
    _, brain, _, _ = agy_scratch(monkeypatch, tmp_path, now)
    write_agy_transcript(brain, "session-a", [
        {"created_at": "2027-01-14T07:59:30Z", "input_tokens": 2, "content": "PRIVATE_MARKER"},
        {"created_at": "2027-01-15T08:00:00Z", "input_tokens": 3, "cache_read_tokens": 5,
         "thinking": "PRIVATE_MARKER", "tool_calls": [{"marker": "PRIVATE_MARKER"}], "error": "PRIVATE_MARKER"},
        {"created_at": "2027-01-15T08:06:40Z", "output_tokens": 7},
    ], now)
    output = dispatch_metrics.render([], 0, now, repo_root=tmp_path / "repo")
    assert 'k3dm_agy_sessions{window="1d",mode="unknown",repo="unknown"} 1' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="input_tokens"} 3' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="cache_read_tokens"} 5' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="output_tokens"} 7' in output
    assert 'k3dm_agy_active_seconds{window="1d",mode="unknown"} 300' in output
    assert 'source="transcripts"} 1' in output
    assert "PRIVATE_MARKER" not in output


def test_agy_transcript_window_boundary_and_dispatch_tracking(monkeypatch, tmp_path):
    now = 1_800_000_000
    _, brain, _, repo = agy_scratch(monkeypatch, tmp_path, now)
    write_agy_transcript(brain, "tracked", [
        {"created_at": "2027-01-14T07:59:59Z", "input_tokens": 99},
        {"created_at": "2027-01-14T08:00:01Z", "input_tokens": 4},
    ], now)
    write_agy_transcript(brain, "untracked", [{"created_at": "2027-01-15T07:59:00Z"}], now)
    events = [event(now, "agent_exit", exit=0, session="tracked")]
    output = dispatch_metrics.render(events, 0, now, repo_root=repo)
    assert 'k3dm_agy_sessions{window="1d",mode="unknown",repo="unknown"} 2' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="input_tokens"} 4' in output
    assert 'k3dm_agy_untracked_sessions{window="1d",mode="unknown",repo="unknown"} 1' in output
    assert 'k3dm_agy_active_seconds{window="1d",mode="unknown"} 0' in output
    assert 'k3dm_agy_sessions{window="30d",mode="unknown",repo="unknown"} 2' in output
    assert 'k3dm_agy_tokens{window="30d",mode="unknown",kind="input_tokens"} 103' in output
    codex_only = dispatch_metrics.render([event(now, "codex_exit", exit=0, session="tracked")], 0, now, repo_root=repo)
    assert 'k3dm_agy_untracked_sessions{window="1d",mode="unknown",repo="unknown"} 2' in codex_only


def test_agy_missing_sources_emit_source_but_no_usage_zero(monkeypatch, tmp_path):
    now = 1_800_000_000
    home = tmp_path / "home"
    brain = home / ".gemini/antigravity-cli/brain"
    ledger = home / ".local/share/k3d-manager/agent-sessions"
    root = tmp_path / "repo"
    home.mkdir(); root.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("K3DM_AGY_BRAIN_DIR", str(brain))
    monkeypatch.setenv("K3DM_AGENT_LEDGER_DIR", str(ledger))
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    assert not brain.exists() and not (ledger / "agy.jsonl").exists() and root.is_dir()
    output = dispatch_metrics.render([], 0, now, repo_root=root)
    assert 'source="none"} 1' in output
    assert "k3dm_agy_sessions{" not in output and "k3dm_agy_tokens{" not in output


def test_agy_transcript_skips_malformed_bad_tokens_and_unreadable_file(monkeypatch, tmp_path):
    now = 1_800_000_000
    _, brain, _, repo = agy_scratch(monkeypatch, tmp_path, now)
    write_agy_transcript(brain, "bad", [
        "{malformed}\n",
        {"created_at": "2027-01-15T08:00:00Z", "input_tokens": True},
        {"created_at": "2027-01-15T08:00:01Z", "output_tokens": "8"},
    ], now)
    unreadable = brain / "unreadable/.system_generated/logs/transcript_full.jsonl"
    unreadable.parent.mkdir(parents=True)
    unreadable.mkdir()
    os.utime(unreadable, (now, now))
    output = dispatch_metrics.render([], 0, now, repo_root=repo)
    assert 'k3dm_agy_transcript_skipped_lines 4' in output
    assert "k3dm_agy_tokens{" not in output
    assert 'k3dm_agy_sessions{window="1d",mode="unknown",repo="unknown"} 1' in output


def test_agy_transcript_invalid_utf8_line_is_skipped_without_losing_valid_steps(monkeypatch, tmp_path):
    now = 1_800_000_000
    _, brain, _, repo = agy_scratch(monkeypatch, tmp_path, now)
    path = brain / "utf8-session/.system_generated/logs/transcript_full.jsonl"
    path.parent.mkdir(parents=True)
    assert path.parent.is_dir() and path.is_relative_to(brain) and repo.is_dir()
    path.write_bytes(
        b'{"created_at":"2027-01-15T07:59:00Z","input_tokens":4}\n'
        b'\xff\n'
        b'{"created_at":"2027-01-15T07:59:30Z","output_tokens":6}\n'
    )
    os.utime(path, (now, now))
    output = dispatch_metrics.render([], 0, now, repo_root=repo)
    assert 'k3dm_agy_sessions{window="1d",mode="unknown",repo="unknown"} 1' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="input_tokens"} 4' in output
    assert 'k3dm_agy_tokens{window="1d",mode="unknown",kind="output_tokens"} 6' in output
    assert "k3dm_agy_transcript_skipped_lines 1" in output


def test_agy_transcripts_prefer_brain_over_duplicate_ledger(monkeypatch, tmp_path):
    now = 1_800_000_000
    _, brain, ledger_dir, repo = agy_scratch(monkeypatch, tmp_path, now)
    write_agy_transcript(brain, "same-run", [{"created_at": "2027-01-15T08:00:00Z", "input_tokens": 5}], now)
    (ledger_dir / "agy.jsonl").write_text(json.dumps({"start": now, "mode": "print", "usage": {"input_tokens": 5}}) + "\n")
    output = dispatch_metrics.render([], 0, now, repo_root=repo)
    assert 'source="transcripts"} 1' in output
    assert 'k3dm_agy_sessions{window="1d",mode="unknown",repo="unknown"} 1' in output
    assert 'k3dm_agy_sessions{window="1d",mode="print",repo="other"}' not in output


def test_agy_ledger_fallback_preserves_existing_metrics(monkeypatch, tmp_path):
    now = 1_800_000_000
    home, brain, ledger_dir, repo = agy_scratch(monkeypatch, tmp_path, now)
    shutil.rmtree(brain)
    assert not brain.exists()
    ledger = ledger_dir / "agy.jsonl"
    ledger.write_text(json.dumps({"start": now - 10, "mode": "print", "repo": "repo-a",
                                  "duration_s": 9, "usage": {"input_tokens": 11}}) + "\n")
    output = dispatch_metrics.render([], 0, now, repo_root=repo)
    assert 'k3dm_agy_source_present{host="' in output and 'source="ledger"} 1' in output
    assert 'k3dm_agy_sessions{window="1d",mode="print",repo="repo-a"} 1' in output
    assert 'k3dm_agy_active_seconds{window="1d",mode="print"} 9' in output
    assert 'k3dm_agy_tokens{window="1d",mode="print",kind="input_tokens"} 11' in output


def test_agy_dry_run_with_no_sources_succeeds_without_zero_usage(monkeypatch, tmp_path):
    now = 1_800_000_000
    home, brain, ledger, repo = agy_scratch(monkeypatch, tmp_path, now)
    shutil.rmtree(brain)
    assert not brain.exists() and not (ledger / "agy.jsonl").exists() and repo.is_dir()
    completed = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                               env=os.environ.copy(), check=False)
    assert completed.returncode == 0, completed.stderr
    assert 'source="none"} 1' in completed.stdout
    assert "k3dm_agy_sessions{" not in completed.stdout and "k3dm_agy_tokens{" not in completed.stdout


def test_quota_efficiency_requires_same_reset_and_positive_observed_delta(tmp_path, monkeypatch):
    monkeypatch.setattr(dispatch_metrics, "_root", lambda: tmp_path / "state")
    repo = tmp_path / "repo"
    spec = repo / "docs/plans/v9.9.9-demo.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("# Demo\n\n## Acceptance\n\n- offline\n")
    monkeypatch.setattr(dispatch_metrics, "_repo_root", lambda: repo)
    now = time.time()
    events = [
        event(now - 300, "start", version="v9.9.9", slug="quota", spec="docs/plans/v9.9.9-demo.md", agent="codex"),
        event(now - 250, "land", version="v9.9.9", slug="quota"),
        event(now - 150, "verify", version="v9.9.9", slug="quota", result="pass", evidence_sha256="abc"),
    ]
    lines = []
    dispatch_metrics._quota_efficiency(lines, events, (time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(now - 600)), {"secondary": {"used_percent": 20, "resets_at": 200}}), 100)
    assert "k3dm_codex_quota_efficiency_coverage 0" in lines
    lines.clear()
    dispatch_metrics._quota_efficiency(lines, events, (time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(now - 500)), {"secondary": {"used_percent": 25, "resets_at": 201}}), 100)
    assert "k3dm_codex_quota_efficiency_coverage 0" in lines
    lines.clear()
    dispatch_metrics._quota_efficiency(lines, events, (time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(now - 400)), {"secondary": {"used_percent": 25.005, "resets_at": 201}}), 100)
    assert "k3dm_codex_quota_efficiency_coverage 0" in lines
    lines.clear()
    dispatch_metrics._quota_efficiency(lines, events, (time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(now - 100)), {"secondary": {"used_percent": 26, "resets_at": 201}}), 100)
    assert "k3dm_codex_quota_efficiency_coverage 1" in lines
    assert "k3dm_codex_verified_outputs 1" in lines


def test_run_outcome_keeps_a_long_evidence_path_whole(tmp_path, monkeypatch):
    slug = "2026-10-25-dispatch-run-evidence-column-names-a-file-you-cannot-open"
    root = tmp_path / ("worktrees-" + "x" * 40)
    run_dir = root / "v1.43.7" / f"{slug}.run"
    run_dir.mkdir(parents=True)
    (run_dir / "land-test.log").write_text("8 passed in 0.1s\n")
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    summary, path = dispatch_metrics._evidence_details("v1.43.7", slug, "land-test.log")
    assert len(path) > 120
    assert path.startswith("~/worktrees-") and str(tmp_path) not in path
    assert dispatch_metrics._label_value(path, limit=512) == path
    assert summary == "8 passed"


def _identity_lines(output, role):
    return [line for line in output.splitlines()
            if line.startswith('k3dm_dispatch_model_identity{window="1d",') and f'role="{role}"' in line]


def test_model_identity_exports_worker_and_coordinator_from_latest_start():
    output = dispatch_metrics.render([
        event(1, "start", "mixed", agent="codex", model="gpt-5.6-luna",
              worker_identity={"vendor": "openai", "model": "gpt-5.6-luna", "source": "explicit", "status": "selected"},
              coordinator_identity={"vendor": "anthropic", "model": "claude-opus-5-5", "source": "runtime", "status": "runtime_reported"}),
        event(2, "codex_exit", "mixed", tokens=10),
        event(3, "land", "mixed"),
    ], 0, 100)
    worker = _identity_lines(output, "worker")
    coordinator = _identity_lines(output, "coordinator")
    assert len(worker) == 1 and len(coordinator) == 1
    assert 'vendor="openai",model="gpt-5.6-luna",source="explicit",status="selected"' in worker[0]
    assert 'vendor="anthropic",model="claude-opus-5-5",source="runtime",status="runtime_reported"' in coordinator[0]


def test_repeated_handoffs_preserve_claude_primary_and_human_landing_stays_review_pending(tmp_path):
    spec = tmp_path / "docs/plans/v9.9.9-demo.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("**Status:** LANDED — Claude review pending\n\n## Acceptance\n\n```yaml\nevidence:\n  - kind: offline\n```\n")
    rows = [
        event(1, "start", "handoff", agent="codex", spec="docs/plans/v9.9.9-demo.md",
              primary_coordinator_identity={"vendor": "anthropic", "model": "claude-opus-5-5", "source": "declared", "status": "declared"},
              worker_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "explicit", "status": "selected"}),
        event(2, "handoff", "handoff", acting_coordinator_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "declared", "status": "declared"}, handoff_reason="quota_exhausted"),
        event(3, "handoff", "handoff", acting_coordinator_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "declared", "status": "declared"}, handoff_reason="manual"),
        event(4, "resume", "handoff", primary_coordinator_identity={"vendor": "openai", "model": "wrong-later-primary", "source": "declared", "status": "declared"}),
        event(5, "land", "handoff", landing_actor={"actor": "human", "vendor": "unknown", "model": "unknown", "source": "declared"}, review_status="pending"),
        event(6, "review_pending", "handoff", landing_actor="human", review_status="pending"),
    ]
    output = dispatch_metrics.render(rows, 0, 100, repo_root=tmp_path)
    assert 'role="primary_coordinator",vendor="anthropic",model="claude-opus-5-5"' in output
    assert 'role="acting_coordinator",vendor="openai",model="gpt-6-luna"' in output
    assert 'actor="human"' in next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_landing_actor{"))
    assert 'k3dm_dispatch_handoffs{window="1d",reason="manual"} 1' in output
    assert 'k3dm_dispatch_handoffs{window="1d",reason="quota_exhausted"} 1' in output
    assert 'k3dm_dispatch_task_handoff_reason' in output
    assert 'k3dm_dispatch_delivered{window="30d"} 0' in output
    assert 'k3dm_dispatch_awaiting_verification{window="30d"} 1' in output
    assert not any(row.get("event") == "verify" for row in rows)


def test_primary_cost_is_explicitly_unmeasured_not_zero():
    output = dispatch_metrics.render([
        event(1, "start", "cost"), event(2, "codex_exit", "cost", tokens=101), event(3, "land", "cost")
    ], 0, 100)
    assert 'k3dm_dispatch_task_primary_coordinator_cost_usd' not in output
    measured = dispatch_metrics.render([
        event(1, "start", "cost"),
        event(1, "codex_exit", "cost", tokens=101),
        event(2, "primary_coordinator_cost", "cost", amount_usd=0, source="runtime-reported"),
        event(3, "land", "cost"),
    ], 0, 100)
    assert 'k3dm_dispatch_task_primary_coordinator_cost_usd{window="1d",version="9.9.9",slug="cost",agent="codex",repo="k3d-manager"} 0' in measured
    assert 'state="not measured"' in output
    assert 'state="measured"' in measured


def test_unlisted_worker_history_collapses_duplicate_normalized_series_only():
    rows = [
        event(1, "start", "runtime-dedupe", agent="codex",
              worker_identity={"vendor": "openai", "model": "unknown", "source": "inherited", "status": "unknown"}),
        event(2, "identity", "runtime-dedupe", run=1,
              worker_identity={"vendor": "openai", "model": "gpt-private-a", "source": "runtime", "status": "reported"}),
        event(3, "identity", "runtime-dedupe", run=2,
              worker_identity={"vendor": "openai", "model": "gpt-private-b", "source": "runtime", "status": "reported"}),
        event(4, "identity", "runtime-dedupe", run=3,
              worker_identity={"vendor": "openai", "model": "gpt-private-c", "source": "runtime", "status": "reported"}),
        event(5, "land", "runtime-dedupe"),
    ]
    raw_models = [row["worker_identity"]["model"] for row in rows if row.get("event") == "identity"]
    output = dispatch_metrics.render(rows, 0, 100)
    history = _identity_lines(output, "worker_history")
    assert raw_models == ["gpt-private-a", "gpt-private-b", "gpt-private-c"]
    assert len(history) == 1 and len(set(history)) == 1
    assert 'model="other"' in history[0]


def test_model_identity_is_unknown_for_a_legacy_start_with_a_model_field():
    output = dispatch_metrics.render([
        event(1, "start", "legacy", agent="codex", model="gpt-5.6-luna", model_source="inherited"),
        event(2, "codex_exit", "legacy", tokens=10),
        event(3, "land", "legacy"),
    ], 0, 100)
    for role in ("worker", "coordinator", "primary_coordinator"):
        lines = _identity_lines(output, role)
        assert len(lines) == 1
        assert 'model="unknown"' in lines[0] and 'status="unknown"' in lines[0]
    assert 'actor="unknown"' in next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_landing_actor{"))


def test_model_identity_rejects_unbounded_label_values():
    output = dispatch_metrics.render([
        event(1, "start", "bad", agent="codex",
              worker_identity={"vendor": "acme", "model": 'x"}\nevil', "source": "prompt", "status": "great"}),
        event(2, "codex_exit", "bad", tokens=10),
        event(3, "land", "bad"),
    ], 0, 100)
    worker = _identity_lines(output, "worker")
    assert len(worker) == 1
    assert 'vendor="unknown",model="unknown",source="unreported",status="unknown"' in worker[0]
    assert "evil" not in output and "acme" not in output


def test_unlisted_but_valid_model_is_normalized_for_bounded_cardinality():
    output = dispatch_metrics.render([
        event(1, "start", "unlisted", primary_coordinator_identity={
            "vendor": "openai", "model": "one-off-private-model-123", "source": "declared", "status": "declared"}),
        event(2, "land", "unlisted"),
    ], 0, 100)
    primary = _identity_lines(output, "primary_coordinator")
    assert len(primary) == 1 and 'model="other"' in primary[0]
    assert "one-off-private-model-123" not in output


def test_runtime_identity_prefers_latest_and_keeps_each_reported_model():
    output = dispatch_metrics.render([
        event(1, "start", "runtime", agent="codex",
              worker_identity={"vendor": "openai", "model": "unknown", "source": "inherited", "status": "unknown"}),
        event(2, "identity", "runtime", run=1,
              worker_identity={"vendor": "openai", "model": "gpt-test-1", "source": "runtime", "status": "reported"}),
        event(3, "resume", "runtime", run=2, n=2,
              coordinator_identity={"vendor": "anthropic", "model": "claude-test", "source": "declared", "status": "declared"}),
        event(4, "identity", "runtime", run=2,
              worker_identity={"vendor": "openai", "model": "gpt-test-2", "source": "runtime", "status": "reported"}),
        event(5, "land", "runtime"),
    ], 0, 100)
    workers = _identity_lines(output, "worker")
    worker_history = _identity_lines(output, "worker_history")
    coordinators = _identity_lines(output, "coordinator")
    assert len(workers) == 1 and 'model="other",source="runtime",status="reported"' in workers[0]
    assert 'display="gpt-test-1 → gpt-test-2"' in workers[0]
    assert len(worker_history) == 1 and 'model="other",source="runtime",status="reported"' in worker_history[0]
    assert len(coordinators) == 1
    assert 'vendor="anthropic",model="other",source="declared",status="declared"' in coordinators[0]


def test_worker_display_lists_distinct_runtime_models_in_run_order_once():
    output = dispatch_metrics.render([
        event(1, "start", "one-model", agent="codex"),
        event(2, "identity", "one-model", run=1,
              worker_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "runtime", "status": "reported"}),
        event(3, "identity", "one-model", run=2,
              worker_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "runtime", "status": "reported"}),
        event(4, "land", "one-model"),
    ], 0, 100)
    worker = _identity_lines(output, "worker")
    assert len(worker) == 1
    assert 'display="gpt-6-luna"' in worker[0]
    assert "→" not in worker[0]


def test_invalid_runtime_identity_does_not_replace_legacy_value():
    output = dispatch_metrics.render([
        event(1, "start", "invalid", agent="codex",
              worker_identity={"vendor": "openai", "model": "unknown", "source": "inherited", "status": "unknown"}),
        event(2, "identity", "invalid", worker_identity={
            "vendor": "openai", "model": "bad value!", "source": "runtime", "status": "reported"}),
        event(3, "land", "invalid"),
    ], 0, 100)
    worker = _identity_lines(output, "worker")
    assert len(worker) == 1 and 'model="unknown",source="inherited",status="unknown"' in worker[0]
    assert "bad value" not in output


def test_per_spec_identity_queries_give_one_row_per_task():
    panels = {panel["title"]: panel for panel in load_dispatch_dashboard()["panels"]}
    per_spec = panels["Per spec"]
    exprs = {t["refId"]: t["expr"] for t in per_spec["targets"]}
    assert 'role="worker"' in exprs["H"] and exprs["H"].startswith("max by (version, slug, repo, worker)")
    assert 'role="coordinator"' in exprs["I"] and exprs["I"].startswith("max by (version, slug, repo, coordinator)")
    assert 'role="primary_coordinator"' in exprs["P"] and exprs["P"].startswith("max by (version, slug, repo, primary_coordinator)")
    assert 'role="acting_coordinator"' in exprs["Q"] and exprs["Q"].startswith("max by (version, slug, repo, acting_coordinator)")
    assert "k3dm_dispatch_task_landing_actor" in exprs["R"]
    organize = per_spec["transformations"][1]["options"]
    assert organize["excludeByName"]["Value #H"] and organize["excludeByName"]["Value #I"]
    assert organize["renameByName"]["worker"] == "Worker model"  # agent-audit: allow assert-removed renamed Worker to Worker model per bug 2026-11-10-dispatch-table-shows-flash-and-fable-as-other
    assert organize["renameByName"]["coordinator"] == "Coordinator (legacy)"
    assert organize["renameByName"]["primary_coordinator"] == "Primary coordinator"
    assert organize["renameByName"]["acting_coordinator"] == "Acting coordinator"
    assert organize["renameByName"]["landed_by"] == "Landed by"


def test_claude_daily_tokens_by_kind_partition_local_dates_and_filter_records():
    now = calendar.timegm(time.strptime("2026-01-10T12:00:00", "%Y-%m-%dT%H:%M:%S"))
    before_tz = os.environ.get("TZ")
    records = [
        _claude_message("one", calendar.timegm(time.strptime("2026-01-01T23:59:00", "%Y-%m-%dT%H:%M:%S")),
                        input=1, cache_5m=2, cache_1h=3, cache_read=4, output=5),
        _claude_message("two", calendar.timegm(time.strptime("2026-01-02T00:01:00", "%Y-%m-%dT%H:%M:%S")),
                        input=6, cache_5m=7, cache_1h=8, cache_read=9, output=10),
        _claude_message("synthetic", now, model="<synthetic>", input=999),
        _claude_message("old", now - 31 * 86400, input=999),
    ]
    try:
        os.environ["TZ"] = "UTC"; time.tzset()
        output = dispatch_metrics.render([], 0, now, claude_records=records)
        rows = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_claude_daily_tokens_by_kind{")]
        assert len(rows) == 8
        assert 'date="2026-01-01",kind="cache_write"} 5' in "\n".join(rows)
        assert 'date="2026-01-02",kind="cache_write"} 15' in "\n".join(rows)
        for day in ("2026-01-01", "2026-01-02"):
            by_kind = sum(float(line.rsplit(" ", 1)[1]) for line in rows if f'date="{day}"' in line)
            by_model = sum(float(line.rsplit(" ", 1)[1]) for line in output.splitlines()
                           if line.startswith("k3dm_dispatch_claude_daily_tokens{") and f'date="{day}"' in line)
            assert by_kind == by_model
        assert not any('date="2026-01-10"' in line for line in rows)
    finally:
        if before_tz is None: os.environ.pop("TZ", None)
        else: os.environ["TZ"] = before_tz
        time.tzset()


def test_claude_cost_by_kind_uses_rates_and_unpriced_record_is_excluded():
    now = 30
    rates = _claude_rates(input=2, cache_write_5m=3, cache_write_1h=5, cache_read=0.1, output=4)
    tasks = [event(0, "start", "A", version="v1.0.0"), event(20, "land", "A", version="v1.0.0")]
    records = [_claude_message("priced", 10, input=1_000_000, cache_5m=2_000_000,
                               cache_1h=3_000_000, cache_read=4_000_000, output=5_000_000),
               _claude_message("unpriced", 11, model="unknown", input=100)]
    output = dispatch_metrics.render(tasks, 0, now, claude_records=records, claude_prices=rates)
    expected = {"input": 2, "cache_write": 21, "cache_read": 0.4, "output": 20}
    for kind, amount in expected.items():
        line = next(row for row in output.splitlines()
                    if row.startswith(f'k3dm_dispatch_claude_api_cost_by_kind_usd{{window="v1.0.0",kind="{kind}"}}'))
        assert abs(float(line.rsplit(" ", 1)[1]) - amount) < 1e-6
    assert abs(sum(expected.values()) - _metric(output, "k3dm_dispatch_claude_api_cost_usd", "v1.0.0")) < 1e-6
    time_output = dispatch_metrics.render([], 0, now, claude_records=records, claude_prices=rates)
    for window in ("1d", "7d", "30d"):
        values = [float(line.rsplit(" ", 1)[1]) for line in time_output.splitlines()
                  if line.startswith(f'k3dm_dispatch_claude_api_cost_by_kind_usd{{window="{window}"')]
        assert len(values) == 4
        assert abs(sum(values) - _metric(time_output, "k3dm_dispatch_claude_api_cost_usd", window)) < 1e-6


def test_claude_non_numeric_usage_does_not_break_render_or_emit_invalid_values():
    now = 1_800_000_000
    records = [_claude_message("bad", now, input="invalid", cache_read=None),
               {"ts": "bad timestamp", "model": "m", "input": object()}]
    output = dispatch_metrics.render([], 0, now, claude_records=records, claude_prices=_claude_rates())
    assert "k3dm_dispatch_claude_api_cost_usd" in output
    claude_lines = [line for line in output.splitlines()
                    if line.startswith(("k3dm_dispatch_claude_api_cost", "k3dm_dispatch_claude_tokens",
                                       "k3dm_dispatch_claude_daily_tokens"))]
    assert all(not line.rstrip().endswith((" nan", " inf", " -inf")) for line in claude_lines)


def test_spec_stats_counts_files_and_acceptance_yaml(tmp_path):
    spec = tmp_path / "spec.md"
    spec.write_text(dedent("""\
        ## Files
        - `one.py`
        - `two.py`
        | File |
        |---|
        | `three.py` |

        ## Acceptance
        ```yaml
        must:
          - id: M1
          - id: M2
          - id: M3
        must_not:
          - id: N1
          - id: N2
        evidence:
          - id: E1
            kind: offline
          - id: E2
            kind: live
        ```
        """))
    assert dispatch_metrics._spec_stats(spec) == {
        "files": 3, "must": 3, "must_not": 2, "evidence": 2, "live_evidence": 1}
    no_acceptance = tmp_path / "no-acceptance.md"
    no_acceptance.write_text("## Files\n| File |\n|---|\n| `x.py` |\n")
    assert dispatch_metrics._spec_stats(no_acceptance) == {
        "files": 1, "must": None, "must_not": None, "evidence": None, "live_evidence": None}


def test_complexity_series_omit_unmeasured_and_totals_cover_all_tasks():
    now = 100
    events = []
    for index in range(dispatch_metrics.TASK_CAP + 1):
        slug = f"task-{index:03}"
        events.extend([
            event(index + 1, "start", slug, version="v1.0.0", spec_stats={"files": 2, "must": 1, "must_not": 1}),
            event(index + 2, "land", slug, version="v1.0.0", change={"files": 3, "code": 2, "tests": 3, "docs": 4}),
        ])
    events.extend([event(200, "start", "legacy", version="v1.0.0"), event(201, "land", "legacy", version="v1.0.0")])
    output = dispatch_metrics.render(events, 0, now)
    # The newest 50 displayed tasks include the unmeasured legacy task, so only 49 have change rows.
    assert output.count('k3dm_dispatch_task_change_files{window="v1.0.0"') == dispatch_metrics.TASK_CAP - 1
    assert 'k3dm_dispatch_change_files_total{window="v1.0.0"} 153' in output
    assert 'k3dm_dispatch_change_lines_total{window="v1.0.0",kind="code"} 102' in output
    assert 'k3dm_dispatch_change_lines_median{window="v1.0.0"} 9' in output
    assert 'k3dm_dispatch_spec_acceptance_items_total{window="v1.0.0"} 102' in output
    assert 'k3dm_dispatch_complexity_measured_tasks{window="v1.0.0",measure="change"} 51' in output
    assert 'k3dm_dispatch_complexity_measured_tasks{window="v1.0.0",measure="spec"} 51' in output


def test_null_spec_stats_are_not_counted_as_measured():
    null_stats = {"files": None, "must": None, "must_not": None, "evidence": None, "live_evidence": None}
    events = [
        event(1, "start", "old-spec", version="v1.0.0", spec_stats=null_stats),
        event(2, "land", "old-spec", version="v1.0.0"),
        event(3, "start", "new-spec", version="v1.0.0", spec_stats={"files": 2, "must": 1, "must_not": 1}),
        event(4, "land", "new-spec", version="v1.0.0"),
    ]
    output = dispatch_metrics.render(events, 0, 100)
    assert 'k3dm_dispatch_complexity_measured_tasks{window="v1.0.0",measure="spec"} 1' in output
    assert 'slug="old-spec"' not in "".join(line for line in output.splitlines() if "task_spec_" in line)


def test_dashboard_complexity_columns_and_stat_queries():
    dashboard = load_dispatch_dashboard()
    per_spec = next(panel for panel in dashboard["panels"] if panel.get("title") == "Per spec")
    assert {"Spec files", "Acceptance items", "Files changed", "Lines changed", "Test lines"} <= set(
        per_spec["transformations"][1]["options"]["renameByName"].values())
    assert {"Spec files", "Acceptance items", "Files changed", "Lines changed", "Test lines"} <= set(
        per_spec["options"]["footer"]["fields"])
    stat_titles = {panel.get("title") for panel in dashboard["panels"] if panel.get("type") == "stat"}
    assert {"Lines changed total", "Median lines / spec", "Acceptance items total", "Measured"} <= stat_titles


def test_claude_existing_series_keep_their_fixture_output():
    now = 1_800_000_000
    record = _claude_message("stable", now, input=11, cache_5m=13, cache_1h=17, cache_read=19, output=23)
    output = dispatch_metrics.render([], 0, now, claude_records=[record], claude_prices=_claude_rates())
    existing = [line for line in output.splitlines()
                if line.startswith(("k3dm_dispatch_claude_api_cost_usd{", "k3dm_dispatch_claude_tokens{",
                                    "k3dm_dispatch_claude_daily_tokens{"))]
    expected = []
    for window in ("1d", "7d", "30d"):
        expected.append(f'k3dm_dispatch_claude_api_cost_usd{{window="{window}"}} 8.3e-05')
        expected.extend(f'k3dm_dispatch_claude_tokens{{window="{window}",model="m",kind="{kind}"}} {value}'
                        for kind, value in (("input", "11.0"), ("cache_write", "30.0"),
                                            ("cache_read", "19.0"), ("output", "23.0")))
    expected.append('k3dm_dispatch_claude_daily_tokens{date="2027-01-15",model="m"} 83')
    assert existing == expected


def test_partial_identity_keeps_recorded_vendor_without_inventing_model():
    output = dispatch_metrics.render([
        event(1, "start", "partial-identity", agent="codex",
              coordinator_identity={"vendor": "openai", "model": "unknown",
                                    "source": "declared", "status": "declared"}),
        event(2, "codex_exit", "partial-identity", exit=0, tokens=10),
        event(3, "land", "partial-identity"),
    ], 0, 100)
    lines = _identity_lines(output, "coordinator")
    assert len(lines) == 1
    assert 'vendor="openai"' in lines[0] and 'model="unknown"' in lines[0]
    assert 'display="openai/model not recorded (declared)"' in lines[0]
    assert 'display="unknown"' in _identity_lines(output, "primary_coordinator")[0]


def test_run_spec_link_uses_recorded_issue_instead_of_custom_slug(tmp_path):
    output = dispatch_metrics.render([
        event(1, "start", "vectordb-retrieval-key-cache", version="v1.43.9", run=1,
              spec="docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md"),
        event(2, "codex_exit", "vectordb-retrieval-key-cache", version="v1.43.9", run=1, exit=127),
        event(3, "resume", "vectordb-retrieval-key-cache", version="v1.43.9", run=2),
        event(4, "codex_exit", "vectordb-retrieval-key-cache", version="v1.43.9", run=2, exit=0),
    ], 0, 100, repo_root=tmp_path)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
    expected = ('spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/'
                'docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md"')
    assert len(lines) > 1 and all(expected in line for line in lines)
    assert not any('spec_url="' in line and 'docs/plans/v1.43.9-vectordb-retrieval-key-cache.md' in line
                   for line in lines)


@pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                  'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
    output = dispatch_metrics.render([
        event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
        event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
    ], 0, 100, repo_root=tmp_path)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
    assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                         in line for line in lines)


@pytest.mark.parametrize("directory", ["plans", "bugs", "issues"])
def test_run_spec_link_accepts_recorded_doc_kinds(tmp_path, directory):
    spec = f"docs/{directory}/different-from-slug.md"
    output = dispatch_metrics.render([
        event(1, "start", "custom-slug", version="v1.43.9", run=1, spec=spec),
        event(2, "codex_exit", "custom-slug", version="v1.43.9", run=1, exit=0),
    ], 0, 100, repo_root=tmp_path)
    line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
    assert f'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/{spec}"' in line


def test_attempt_evidence_uses_ledger_paths_and_redacts(tmp_path, monkeypatch):
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path))
    run = tmp_path / "9.9.9" / "attempt.run"
    run.mkdir(parents=True)
    secret = "ghp_" + "a" * 36
    (run / "land-test.1.log").write_text("".join(f"ok {i} - pass\n" for i in range(100)) + f"not ok 101 - {Path.home()}/private {secret}\n")
    (run / "land-test.2.log").write_text("1 passed in 0.1s\n")
    now = int(time.time())
    rows = [event(now-6, "start", "attempt", run=1), event(now-5, "codex_exit", "attempt", run=1, tree="a"),
            event(now-4, "land_refused", "attempt", reason="tests", validation=str(run / "land-test.1.log")),
            event(now-3, "resume", "attempt", run=2), event(now-2, "codex_exit", "attempt", run=2, tree="b"),
            event(now-1, "land", "attempt", tree="b", test_result="passed", validation=str(run / "land-test.2.log"))]
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert '100/101 ok; first fail: 101 - ~/private <redacted>' in output
    assert 'attempt.run/land-test.1.log' in output and 'attempt.run/land-test.2.log' in output
    assert secret not in output and str(Path.home()) not in output


def test_refused_pytest_summary(tmp_path, monkeypatch):
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path))
    run = tmp_path / "v1.2.3" / "sample.run"
    run.mkdir(parents=True)
    (run / "land-test.1.log").write_text("FAILED tests/test_a.py::test_bad - error\n1 failed, 2 passed in 1.0s\n")
    summary, path = dispatch_metrics._evidence_details("v1.2.3", "sample", "land_refused.tests", {"validation": "land-test.1.log"})
    assert summary == "1 failed, 2 passed; first fail: tests/test_a.py::test_bad"
    assert path.endswith("land-test.1.log")


def test_claude_bash_rereads_classification_and_privacy(tmp_path):
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    projects = tmp_path / "projects"
    projects.mkdir()
    assert projects.resolve() != (Path.home() / ".claude").resolve()
    now = time.time()
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
    entries = []

    def call(ident, name, inp, result=None):
        entries.append({"type": "assistant", "timestamp": timestamp, "message": {"content": [
            {"type": "tool_use", "id": ident, "name": name, "input": inp}]}})
        if result is not None:
            entries.append({"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": ident, "content": result}]}})

    paths = [f"/private-fixture/secret-{i}" for i in range(5)]
    commands = [f"cat {paths[0]}", f"sed -n '1,2p' {paths[1]}",
                f"head -n 2 {paths[2]}", f"grep secret {paths[3]}"]
    for i, command in enumerate(commands):
        call(f"before{i}", "Bash", {"command": command}, "private-result")
    call("read-before", "Read", {"file_path": paths[4]}, "private-result")
    entries.append({"type": "system", "subtype": "compact_boundary", "timestamp": timestamp})
    call("same", "Bash", {"command": commands[0]}, "private-result")
    call("repeat", "Bash", {"command": commands[0]}, "private-result")
    call("changed", "Bash", {"command": commands[1]}, "different-result")
    call("range", "Bash", {"command": f"head -n 3 {paths[2]}"}, "private-result")
    call("edit", "Edit", {"file_path": paths[3]})
    call("edited", "Bash", {"command": commands[3]}, "private-result")
    call("same-read", "Read", {"file_path": paths[4]}, "private-result")
    for i, command in enumerate((f"sed -i x {paths[0]}", f"cat {paths[0]} > {paths[1]}",
                                 f"cat {paths[0]} | tee {paths[1]}", "cat 'unterminated")):
        call(f"write{i}", "Bash", {"command": command}, "private-result")
    (projects / "session.jsonl").write_text("\n".join(map(json.dumps, entries)))
    cache = tmp_path / "cache.json"
    ctx = {}
    dispatch_metrics._claude_rollup(projects, cache, ctx)
    output = dispatch_metrics.render([], 0, now, claude_context=ctx, repo_root=tmp_path)
    for window in ("1d", "7d", "30d"):
        for kind, count in (("all", 11), ("reread_after_compaction", 5),
                            ("reread_unchanged", 2), ("reread_changed", 3)):
            assert f'k3dm_claude_reads{{window="{window}",kind="{kind}"}} {count}' in output
        for tool, count in (("bash", 9), ("read", 2)):
            assert f'k3dm_claude_reads_by_tool{{window="{window}",tool="{tool}"}} {count}' in output
    for secret in (*paths, *commands, "private-result", "different-result"):
        assert secret not in output
        assert secret not in cache.read_text()


def test_bash_read_operands_and_rejected_commands(tmp_path, monkeypatch):
    monkeypatch.setattr(dispatch_metrics, "_repo_root", lambda: tmp_path)
    parse = dispatch_metrics._bash_reads
    assert len(parse("cat one two | head -n 1", str(tmp_path))) == 2
    assert len(parse("grep -n needle one", str(tmp_path))) == 1
    assert not parse("cat " + " ".join(f"file{i}" for i in range(6)), str(tmp_path))
    assert not parse("cat ../outside", str(tmp_path))
    assert not parse("cat one || cat two", str(tmp_path))
    assert not parse(None, str(tmp_path))


def test_claude_result_hash_rejects_errors_and_truncation():
    digest = dispatch_metrics._result_hash
    assert digest({"content": "same"}) == digest({"content": "same"})
    assert digest({"content": "same", "is_error": True}) is None
    assert digest({"content": "Output truncated: secret"}) is None


def test_claimed_verification_is_not_delivered(tmp_path):
    spec = tmp_path / "docs/plans/v9.9.9-demo.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("## Acceptance\n\n```yaml\nevidence:\n  - kind: offline\n```\n")
    now = int(time.time())
    rows = []
    for slug in ("backed", "claimed"):
        rows.extend([event(now - 3, "start", slug, spec="docs/plans/v9.9.9-demo.md"), event(now - 2, "land", slug)])
    rows.extend([event(now - 1, "verify", "backed", result="pass", evidence_sha256="abc"), event(now - 1, "verify", "claimed", result="pass")])
    output = dispatch_metrics.render(rows, 0, now, repo_root=tmp_path)
    assert 'k3dm_dispatch_delivered{window="30d"} 1' in output
    assert 'k3dm_dispatch_awaiting_verification{window="30d"} 1' in output
    assert 'k3dm_dispatch_verification_claimed{window="30d"} 1' in output


@pytest.mark.parametrize("reason,intervention,expected,evidence", [
    ("correction", None, "rework", "resume.correction"),
    ("continue_prompt", None, "progress", "resume.continue_prompt"),
    ("clarification", None, "progress", "resume.clarification"),
    (None, "correction", "rework", "intervention.correction"),
    ("other", "correction", "superseded", "none"),
    (None, None, "superseded", "none"),
])
def test_resume_reason_outcomes(tmp_path, reason, intervention, expected, evidence):
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    root.mkdir(parents=True)
    # Event shapes copied from the M4 ledger, 2026-11-01.
    rows = [event(100, "start", "task", run=1), event(110, "codex_exit", "task", run=1, exit=0)]
    if intervention:
        rows.append(event(115, "intervention", "task", reason=intervention))
    rows.append(event(120, "resume", "task", n=2, **({"reason": reason} if reason else {})))
    ledger = root / "ledger.jsonl"
    ledger.write_text("".join(json.dumps(row) + "\n" for row in rows))
    result = dispatch_metrics._run_outcome_metrics([json.loads(line) for line in ledger.read_text().splitlines()], tmp_path, now=130)
    assert result["outcomes"][expected] == 1
    assert result["rows"][0][3][0]["evidence"] == evidence
    assert result["coverage"] == (0 if expected == "superseded" else 1)


@pytest.mark.parametrize("extra,exit_code,expected", [
    ([event(130, "land", "task", tree="a", test_result="passed")], 0, "accepted"),
    ([event(115, "land_refused", "task", reason="tests")], 0, "rework"),
    ([], 1, "failed"),
    ([event(130, "abandon", "task")], 0, "failed"),
])
def test_resume_reason_preserves_precedence(tmp_path, extra, exit_code, expected):
    rows = [event(100, "start", "task", run=1), event(110, "codex_exit", "task", run=1, exit=exit_code, tree="a"),
            *extra, event(120, "resume", "task", n=2, reason="clarification")]
    result = dispatch_metrics._run_outcome_metrics(rows, tmp_path, now=140)
    assert result["outcomes"][expected] == 1


def test_dispatch_gates_synthetic_matches_expected(tmp_path):
    import re
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    root.mkdir(parents=True, exist_ok=True)

    fixture_dir = Path(__file__).parents[2] / "tests/fixtures/dispatch-gates"
    assert (fixture_dir / "synthetic.jsonl").exists() and (fixture_dir / "expected.json").exists()

    shutil.copy(fixture_dir / "synthetic.jsonl", root / "ledger.jsonl")

    proc = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                          env=os.environ.copy(), check=True, timeout=60)
    stdout = proc.stdout

    with open(fixture_dir / "expected.json") as f:
        exp = json.load(f)["synthetic"]

    # 1. Stalled and live_pending tasks counts
    stalled_val = exp["counts"]["stalled_tasks"]
    assert f'k3dm_dispatch_stalled_tasks{{version="v9.9.9"}} {stalled_val}' in stdout
    lp_val = exp["counts"]["live_pending_tasks"]
    assert f'k3dm_dispatch_live_pending_tasks{{version="v9.9.9"}} {lp_val}' in stdout
    spd_val = exp["split_parents_dropped"]
    assert f'k3dm_dispatch_split_parents_dropped{{version="v9.9.9"}} {spd_val}' in stdout

    # 2. Gate events (all 6 present and match)
    for ge, count in exp["gate_events"].items():
        assert f'k3dm_dispatch_gate_events{{version="v9.9.9",event="{ge}"}} {count}' in stdout

    # 3. Ladder counts from tasks (all 18 combinations present)
    ladder_counts = {}
    for task in exp["tasks"].values():
        for rung, status in task["ladder"].items():
            ladder_counts[(rung, status)] = ladder_counts.get((rung, status), 0) + 1

    for rung in dispatch_metrics.RUNGS:
        for status in dispatch_metrics.STATUSES:
            count = ladder_counts.get((rung, status), 0)
            assert f'k3dm_dispatch_ladder_tasks{{version="v9.9.9",rung="{rung}",status="{status}"}} {count}' in stdout

    # 4. Split parent rows
    for p, pdata in exp["split"].items():
        comb = pdata["combine"]
        assert f'k3dm_dispatch_split_parent_info{{version="v9.9.9",parent="{p}",combine="{comb}"}} 1' in stdout
        for role in dispatch_metrics.ROLES:
            role_cnt = pdata[role]
            assert f'k3dm_dispatch_split_parent_parts{{version="v9.9.9",parent="{p}",role="{role}"}} {role_cnt}' in stdout
        if pdata["conflicts"] is not None:
            c_val = pdata["conflicts"]
            assert f'k3dm_dispatch_split_parent_conflicts{{version="v9.9.9",parent="{p}"}} {c_val}' in stdout
        else:
            assert f'k3dm_dispatch_split_parent_conflicts{{version="v9.9.9",parent="{p}"}}' not in stdout
        if pdata["elapsed_seconds"] is not None:
            el_val = pdata["elapsed_seconds"]
            assert f'k3dm_dispatch_split_parent_elapsed_seconds{{version="v9.9.9",parent="{p}"}} {el_val}' in stdout
        else:
            assert f'k3dm_dispatch_split_parent_elapsed_seconds{{version="v9.9.9",parent="{p}"}}' not in stdout

    # 5. Label-value allowlists (E4)
    s1_series_prefixes = (
        "k3dm_dispatch_ladder_tasks",
        "k3dm_dispatch_stalled_tasks",
        "k3dm_dispatch_live_pending_tasks",
        "k3dm_dispatch_gate_events",
        "k3dm_dispatch_split_parent_info",
        "k3dm_dispatch_split_parent_parts",
        "k3dm_dispatch_split_parent_conflicts",
        "k3dm_dispatch_split_parent_elapsed_seconds",
        "k3dm_dispatch_split_parents_dropped",
    )
    s1_lines = [line for line in stdout.splitlines() if any(line.startswith(p) for p in s1_series_prefixes)]
    assert len(s1_lines) > 0
    for line in s1_lines:
        assert "slug=" not in line
        if "rung=" in line:
            m = re.search(r'rung="([^"]+)"', line)
            assert m and m.group(1) in dispatch_metrics.RUNGS
        if "status=" in line:
            m = re.search(r'status="([^"]+)"', line)
            assert m and m.group(1) in dispatch_metrics.STATUSES
        if "role=" in line:
            m = re.search(r'role="([^"]+)"', line)
            assert m and m.group(1) in dispatch_metrics.ROLES
        if "combine=" in line:
            m = re.search(r'combine="([^"]+)"', line)
            assert m and m.group(1) in dispatch_metrics.COMBINE_RESULTS
        if "event=" in line:
            m = re.search(r'event="([^"]+)"', line)
            assert m and m.group(1) in dispatch_metrics.GATE_EVENTS
        if "parent=" in line:
            m = re.search(r'parent="([^"]+)"', line)
            assert m and dispatch_metrics.PARENT_RE.fullmatch(m.group(1))


def test_dispatch_gates_n7_label_and_parent_bounds(tmp_path):
    import re
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    root.mkdir(parents=True, exist_ok=True)

    now = 1_800_000_000
    bad_rows = [
        {"ts": now, "event": "gate_coverage_start"},
        # Invalid role
        {"ts": now + 1, "event": "start", "version": "v1.0.0", "slug": "bad-role", "parent": "valid-p1", "role": "invalid_role"},
        # Valid role (paired positive control)
        {"ts": now + 2, "event": "start", "version": "v1.0.0", "slug": "good-role", "parent": "valid-p1", "role": "build"},
        # Invalid combine
        {"ts": now + 3, "event": "combine", "version": "v1.0.0", "parent": "valid-p1", "parts": ["good-role"], "conflicts": 0, "result": "invalid_res"},
        # Valid combine (paired positive control on another parent)
        {"ts": now + 4, "event": "start", "version": "v1.0.0", "slug": "good-role-2", "parent": "valid-p2", "role": "verify"},
        {"ts": now + 5, "event": "combine", "version": "v1.0.0", "parent": "valid-p2", "parts": ["good-role-2"], "conflicts": 0, "result": "pass"},
        # Unknown event type (not in GATE_EVENTS)
        {"ts": now + 6, "event": "custom_unknown_event", "version": "v1.0.0", "slug": "good-role-2"},
        # Valid gate event (paired positive control)
        {"ts": now + 7, "event": "stall_gate", "version": "v1.0.0", "slug": "good-role-2", "gate_state": "opened", "runs": [1], "reason": "r", "assessor": "a", "baseline_sha": "0" * 40},
        # Invalid parent pattern
        {"ts": now + 8, "event": "start", "version": "v1.0.0", "slug": "bad-parent-task", "parent": "Bad Parent!", "role": "build"},
    ]
    (root / "ledger.jsonl").write_text("".join(json.dumps(r) + "\n" for r in bad_rows))

    proc = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                          env=os.environ.copy(), check=True, timeout=60)
    out = proc.stdout

    s1_series_prefixes = (
        "k3dm_dispatch_ladder_tasks", "k3dm_dispatch_stalled_tasks", "k3dm_dispatch_live_pending_tasks",
        "k3dm_dispatch_gate_events", "k3dm_dispatch_split_parent_info", "k3dm_dispatch_split_parent_parts",
        "k3dm_dispatch_split_parent_conflicts", "k3dm_dispatch_split_parent_elapsed_seconds",
        "k3dm_dispatch_split_parents_dropped",
    )
    for line in out.splitlines():
        if any(line.startswith(p) for p in s1_series_prefixes):
            assert "slug=" not in line

    assert 'role="invalid_role"' not in out
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="valid-p1",role="build"} 1' in out
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="valid-p1",role="review"} 0' in out

    assert 'combine="invalid_res"' not in out
    assert 'k3dm_dispatch_split_parent_info{version="v1.0.0",parent="valid-p2",combine="pass"} 1' in out

    assert 'event="custom_unknown_event"' not in out
    assert 'k3dm_dispatch_gate_events{version="v1.0.0",event="stall_gate"} 1' in out

    assert 'parent="Bad Parent!"' not in out
    assert 'k3dm_dispatch_split_parents_dropped{version="v1.0.0"} 1' in out

    # 25 valid parents: newest 20 exported, oldest 5 dropped into split_parents_dropped
    parents_25_rows = [{"ts": now, "event": "gate_coverage_start"}]
    for i in range(25):
        pname = f"parent-{i:02d}"
        parents_25_rows.append({
            "ts": now + 10 + i,
            "event": "start",
            "version": "v2.0.0",
            "slug": f"task-p-{i:02d}",
            "parent": pname,
            "role": "build",
        })
    (root / "ledger.jsonl").write_text("".join(json.dumps(r) + "\n" for r in parents_25_rows))

    proc25 = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                            env=os.environ.copy(), check=True, timeout=60)
    out25 = proc25.stdout

    exported_parents = set(re.findall(r'k3dm_dispatch_split_parent_info\{version="v2.0.0",parent="([^"]+)"', out25))
    assert len(exported_parents) == 20
    for i in range(5):
        assert f"parent-{i:02d}" not in exported_parents
    for i in range(5, 25):
        assert f"parent-{i:02d}" in exported_parents
    assert 'k3dm_dispatch_split_parents_dropped{version="v2.0.0"} 5' in out25


def test_dispatch_gates_n8_existing_series_unmoved(tmp_path):
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    root.mkdir(parents=True, exist_ok=True)

    fixture_dir = Path(__file__).parents[2] / "tests/fixtures/dispatch-gates"
    raw_lines = (fixture_dir / "synthetic.jsonl").read_text().splitlines()

    events_all = []
    events_without_new = []
    for line in raw_lines:
        try:
            data = json.loads(line)
            if isinstance(data, dict) and isinstance(data.get("ts"), (int, float)):
                events_all.append(data)
                if data.get("event") not in dispatch_metrics.NEW_S1_EVENTS and data.get("event") != "gate_coverage_start":
                    events_without_new.append(data)
        except Exception:
            pass

    fixed_now = 1_800_000_000
    out_with_new = dispatch_metrics.render(events_all, 1, now=fixed_now)
    out_without_new = dispatch_metrics.render(events_without_new, 1, now=fixed_now)

    s1_series_prefixes = (
        "k3dm_dispatch_ladder_tasks",
        "k3dm_dispatch_stalled_tasks",
        "k3dm_dispatch_live_pending_tasks",
        "k3dm_dispatch_gate_events",
        "k3dm_dispatch_split_parent_info",
        "k3dm_dispatch_split_parent_parts",
        "k3dm_dispatch_split_parent_conflicts",
        "k3dm_dispatch_split_parent_elapsed_seconds",
        "k3dm_dispatch_split_parents_dropped",
    )

    existing_lines_with = [l for l in out_with_new.splitlines() if not any(l.startswith(p) for p in s1_series_prefixes)]
    existing_lines_without = [l for l in out_without_new.splitlines() if not any(l.startswith(p) for p in s1_series_prefixes)]

    assert len(existing_lines_with) > 0
    assert existing_lines_with == existing_lines_without

    s1_lines_with = [l for l in out_with_new.splitlines() if any(l.startswith(p) for p in s1_series_prefixes)]
    s1_lines_without = [l for l in out_without_new.splitlines() if any(l.startswith(p) for p in s1_series_prefixes)]
    assert s1_lines_with != s1_lines_without


def test_dispatch_gates_parent_reassignment_drops_stale_parent(tmp_path):
    root = Path(os.environ["K3DM_WORKTREE_ROOT"])
    assert root.is_relative_to(tmp_path) and root != Path.home() / ".local/share/k3d-manager/worktrees"
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    root.mkdir(parents=True, exist_ok=True)

    rows = [
        {"ts": 100, "event": "gate_coverage_start"},
        {"ts": 101, "event": "start", "version": "v1.0.0", "repo": "r", "slug": "a", "run": 1, "parent": "old-parent", "role": "build"},
        {"ts": 102, "event": "link", "version": "v1.0.0", "repo": "r", "slug": "a", "parent": "new-parent", "role": "review"},
    ]
    (root / "ledger.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))

    proc = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                          env=os.environ.copy(), check=True, timeout=60)
    out = proc.stdout

    # new-parent exported
    assert 'parent="new-parent"' in out
    assert 'k3dm_dispatch_split_parent_info{version="v1.0.0",parent="new-parent",combine="pending"} 1' in out
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="new-parent",role="review"} 1' in out

    # old-parent absent and not counted as dropped
    assert 'parent="old-parent"' not in out
    assert 'k3dm_dispatch_split_parents_dropped{version="v1.0.0"} 0' in out

    # Paired control: a combine naming old-parent brings it back with zero parts
    control_rows = list(rows) + [
        {"ts": 103, "event": "combine", "version": "v1.0.0", "parent": "old-parent", "parts": [], "conflicts": 0, "result": "pass"},
    ]
    (root / "ledger.jsonl").write_text("".join(json.dumps(r) + "\n" for r in control_rows))

    proc_control = subprocess.run([str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                                  env=os.environ.copy(), check=True, timeout=60)
    out_control = proc_control.stdout

    assert 'parent="new-parent"' in out_control
    assert 'k3dm_dispatch_split_parent_info{version="v1.0.0",parent="old-parent",combine="pass"} 1' in out_control
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="old-parent",role="build"} 0' in out_control
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="old-parent",role="review"} 0' in out_control
    assert 'k3dm_dispatch_split_parent_parts{version="v1.0.0",parent="old-parent",role="verify"} 0' in out_control
    assert 'k3dm_dispatch_split_parents_dropped{version="v1.0.0"} 0' in out_control


def test_claude_context_turn_metrics_deduplicate_split_agents_and_classify_rebuilds(tmp_path, monkeypatch):
    # Fixture field shape sampled read-only from assistant usage records (content omitted): host m4-air.local, 2026-11-07.
    # Fields observed: timestamp, message.id, model, input_tokens, cache_read_input_tokens, cache_creation.ephemeral_5m_input_tokens, cache_creation.ephemeral_1h_input_tokens.
    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    assert Path(os.environ["HOME"]) == scratch_home
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    projects = scratch_home / ".claude/projects"
    projects.mkdir(parents=True)
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    assert fake_repo.is_dir()
    t0 = calendar.timegm(time.strptime("2026-11-01T00:00:00", "%Y-%m-%dT%H:%M:%S"))
    def turn(mid, sec, input_tokens, write=0):
        usage = {"input_tokens": input_tokens, "cache_read_input_tokens": 10,
                 "cache_creation": {"ephemeral_5m_input_tokens": write, "ephemeral_1h_input_tokens": 0}}
        return {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t0 + sec)),
                "message": {"id": mid, "model": "m", "usage": usage}}
    main_path = projects / "main.jsonl"
    rows = [turn("a", 0, 100), turn("a", 0, 100), turn("b", 3600, 200),
            {"type": "system", "subtype": "compact_boundary", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t0 + 3601))},
            turn("c", 3602, 300, 50001), turn("d", 7203, 400, 50001)]
    main_path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    subdir = projects / "subagents"
    subdir.mkdir()
    (subdir / "sub.jsonl").write_text(json.dumps(turn("sub", 10, 999999)) + "\n")
    context = {}
    records = dispatch_metrics._claude_rollup(projects, scratch_home / "rollup.json", context)
    output = dispatch_metrics.render([], 0, t0 + 86400, claude_records=records,
                                     claude_prices=_claude_rates(), claude_context=context,
                                     repo_root=fake_repo)
    assert 'k3dm_claude_context_turns{window="1d",agent="main"} 4' in output
    assert 'k3dm_claude_context_tokens{window="1d",agent="main",quantile="0.5"} 210' in output
    assert any(line.startswith('k3dm_claude_context_tokens{window="1d",agent="subagent"') for line in output.splitlines())
    assert 'k3dm_claude_context_floor_tokens{window="1d"} 50311' in output, [line for line in output.splitlines() if "context_floor" in line]
    assert 'k3dm_claude_context_ceiling_tokens{window="1d"} 50411' in output
    assert 'k3dm_claude_cache_rebuilds{window="1d",cause="compaction"} 1' in output
    assert 'k3dm_claude_cache_rebuilds{window="1d",cause="idle"} 1' in output
    assert 'k3dm_claude_cache_rebuilds{window="1d",cause="other"} 0' in output
    assert 'k3dm_claude_cache_rebuild_cost_usd{window="1d",cause="compaction"} 0.050001' in output
    assert 'k3dm_claude_cache_rebuild_cost_usd{window="1d",cause="idle"} 0.050001' in output
    unpriced = dispatch_metrics.render([], 0, t0 + 86400, claude_records=records,
        claude_context=context, repo_root=fake_repo)
    assert 'k3dm_claude_cache_rebuild_cost_usd{window="1d",cause="compaction"} 0' in unpriced
    assert 'k3dm_claude_turns_per_active_day{window="1d",agent="main"} 4' in output
    assert not any('agent="subagent"' in line and any(metric in line for metric in
                   ("context_floor", "context_ceiling", "cache_rebuild")) for line in output.splitlines())
    assert 'k3dm_claude_context_floor_tokens' in output and 'session=' not in output
    assert not any("main.jsonl" in line or str(scratch_home) in line for line in output.splitlines())


def test_claude_context_active_days_ignore_idle_dates_and_short_idle_gap(tmp_path, monkeypatch):
    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    assert Path(os.environ["HOME"]) == scratch_home
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    projects = scratch_home / ".claude/projects"
    projects.mkdir(parents=True)
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    assert fake_repo.is_dir()
    day1 = calendar.timegm(time.strptime("2026-11-01T00:00:00", "%Y-%m-%dT%H:%M:%S"))
    def row(mid, stamp, write):
        return {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(stamp)),
                "message": {"id": mid, "model": "m", "usage": {"input_tokens": 1,
                "cache_creation": {"ephemeral_5m_input_tokens": write}}}}
    session = projects / "session.jsonl"
    session.write_text("\n".join(json.dumps(x) for x in [row("one", day1, 50000),
        row("two", day1 + 3599, 50001), row("three", day1 + 86400 * 2, 0)]) + "\n")
    context = {}
    records = dispatch_metrics._claude_rollup(projects, scratch_home / "rollup.json", context)
    out = dispatch_metrics.render([], 0, day1 + 86400 * 3, claude_records=records,
                                 claude_context=context, repo_root=fake_repo)
    assert 'k3dm_claude_turns_per_active_day{window="7d",agent="main"} 1.5' in out
    assert not any(line.startswith('k3dm_claude_turns_per_active_day{window="7d",agent="subagent"}')
                   for line in out.splitlines())
    assert 'k3dm_claude_cache_rebuilds{window="7d",cause="idle"} 0' in out


def test_claude_context_dashboard_has_five_window_panels_and_guarded_spec_ratio():
    dashboard = load_dashboard(DASHBOARD_PATH.with_name("grafana-dashboard-agent-cost.yaml"), "agent-cost.json")
    row_index = next(i for i, panel in enumerate(dashboard["panels"])
                     if panel.get("title") == "Claude context per turn")
    panels = dashboard["panels"][row_index + 1:row_index + 6]
    assert [panel["title"] for panel in panels] == ["Context per turn",
        "Floor, observed ceiling and configured threshold", "Cache rebuilds by cause",
        "Mean context per turn", "Turns"]
    expressions = [target["expr"] for panel in panels for target in panel.get("targets", [])]
    emitted = {"k3dm_claude_context_tokens", "k3dm_claude_context_floor_tokens",
        "k3dm_claude_context_ceiling_tokens", "k3dm_claude_auto_compact_tokens",
        "k3dm_claude_cache_rebuilds", "k3dm_claude_cache_rebuild_cost_usd",
        "k3dm_claude_context_tokens_sum", "k3dm_claude_context_turns",
        "k3dm_claude_turns_per_active_day", "k3dm_claude_verified_specs"}
    for expression in expressions:
        assert "$window" in expression or "k3dm_claude_auto_compact_tokens" in expression
        assert set(re.findall(r"k3dm_claude_[a-z_]+", expression)) <= emitted
    ratio = expressions[-1]
    assert "/ on(window) (sum by (window) (k3dm_claude_verified_specs" in ratio  # agent-audit: allow assert-removed denominator keeps the window label so on(window) matches
    assert 'level=~"live|verified"' in ratio
    assert all("$window" in panel.get("description", "") for panel in panels)


def test_claude_context_metrics_follow_release_scoped_claude_turns():
    now = 1_800_000_000
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 20))
    context = {"turns": [{"id": "r1", "ts": ts, "context": 123, "session": "opaque",
                           "subagent": False, "model": "m", "cache_5m": 0, "cache_1h": 0}],
               "boundaries": [], "compactions": [], "reads": []}
    rows = [event(now - 30, "start", "task", version="v1.0.0"),
            event(now - 10, "land", "task", version="v1.0.0")]
    output = dispatch_metrics.render(rows, 0, now, claude_records=[_claude_message("r1", now - 20, input=123)],
                                     claude_context=context, repo_root=Path("/nonexistent"))
    assert 'k3dm_claude_context_tokens{window="v1.0.0",agent="main",quantile="0.5"} 123' in output
    assert 'k3dm_claude_context_turns{window="v1.0.0",agent="main"} 1' in output


def test_claude_context_warm_cache_equals_cold_cache_and_drops_no_series(tmp_path, monkeypatch):
    # Proves M1, N1 (E1): exporter run twice on fixed transcripts (cold, then warm with no new lines)
    # gets identical context series, including floor, ceiling, quantiles, and turn counts.
    # An old cache without context_turns is treated as cold and also yields identical context series.
    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    assert Path(os.environ["HOME"]) == scratch_home
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    projects = scratch_home / ".claude/projects"
    projects.mkdir(parents=True)
    assert projects.is_dir()
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    assert fake_repo.is_dir()

    now = 1_800_000_000
    t_turn1 = now - 7200
    t_boundary = now - 5000
    t_turn2 = now - 3600

    def turn(mid, stamp, inp, write=0):
        usage = {"input_tokens": inp, "cache_read_input_tokens": 10,
                 "cache_creation": {"ephemeral_5m_input_tokens": write, "ephemeral_1h_input_tokens": 0}}
        return {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(stamp)),
                "message": {"id": mid, "model": "m", "usage": usage}}
    boundary = {"type": "system", "subtype": "compact_boundary", "compactMetadata": {"trigger": "auto", "preTokens": 160000},
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t_boundary))}

    transcript = projects / "session.jsonl"
    transcript.write_text("\n".join(json.dumps(row) for row in [
        turn("t1", t_turn1, 100),
        boundary,
        turn("t2", t_turn2, 200, 50001),
    ]) + "\n")

    cache = scratch_home / "rollup.json"

    # Cold run
    ctx_cold = {}
    rec_cold = dispatch_metrics._claude_rollup(projects, cache, ctx_cold)
    out_cold = dispatch_metrics.render([], 0, now, claude_records=rec_cold, claude_context=ctx_cold, repo_root=fake_repo)

    # Warm run (second run, no new lines)
    ctx_warm = {}
    rec_warm = dispatch_metrics._claude_rollup(projects, cache, ctx_warm)
    out_warm = dispatch_metrics.render([], 0, now, claude_records=rec_warm, claude_context=ctx_warm, repo_root=fake_repo)

    cold_series = [l for l in out_cold.splitlines() if l.startswith("k3dm_claude_context_")]
    warm_series = [l for l in out_warm.splitlines() if l.startswith("k3dm_claude_context_")]

    assert len(cold_series) > 0
    assert warm_series == cold_series

    # Check key metrics explicitly
    assert 'k3dm_claude_context_ceiling_tokens{window="1d"} 50211' in out_warm
    assert 'k3dm_claude_context_floor_tokens{window="1d"} 50211' in out_warm
    assert 'k3dm_claude_context_turns{window="1d",agent="main"} 2' in out_warm
    assert 'k3dm_claude_context_tokens{window="1d",agent="main",quantile="0.5"} 110' in out_warm
    assert 'k3dm_claude_context_tokens{window="1d",agent="main",quantile="0.9"} 50211' in out_warm

    # Backward compatibility: old cache with only offsets and records (no context_turns key)
    # must be treated as cold for context turns and yield identical series.
    raw_cache = json.loads(cache.read_text())
    old_cache_data = {"offsets": raw_cache["offsets"], "records": raw_cache["records"]}
    old_cache = scratch_home / "old_rollup.json"
    old_cache.write_text(json.dumps(old_cache_data))
    ctx_old = {}
    rec_old = dispatch_metrics._claude_rollup(projects, old_cache, ctx_old)
    out_old = dispatch_metrics.render([], 0, now, claude_records=rec_old, claude_context=ctx_old, repo_root=fake_repo)
    old_series = [l for l in out_old.splitlines() if l.startswith("k3dm_claude_context_")]
    assert old_series == cold_series

    # Survival across transcript deletion: persisted context_turns survive when transcripts are deleted
    transcript.unlink()
    ctx_del = {}
    rec_del = dispatch_metrics._claude_rollup(projects, cache, ctx_del)
    out_del = dispatch_metrics.render([], 0, now, claude_records=rec_del, claude_context=ctx_del, repo_root=fake_repo)
    del_series = [l for l in out_del.splitlines() if l.startswith("k3dm_claude_context_")]
    assert del_series == cold_series


def test_claude_context_ceilings_differ_across_windows(tmp_path, monkeypatch):
    # Proves M2 (E2): a test with turns at 2h, 3d and 20d ago gets three different ceilings for 1d, 7d and 30d
    # asserting 1d ceiling <= 7d ceiling <= 30d ceiling.
    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    assert Path(os.environ["HOME"]) == scratch_home
    assert os.environ["K3DM_DISPATCH_PUSHGATEWAY_URL"] == "http://127.0.0.1:9"
    projects = scratch_home / ".claude/projects"
    projects.mkdir(parents=True)
    assert projects.is_dir()
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    assert fake_repo.is_dir()

    now = 1_800_000_000
    t_2h = now - 2 * 3600
    t_3d = now - 3 * 86400
    t_20d = now - 20 * 86400

    def turn(mid, stamp, inp):
        usage = {"input_tokens": inp, "cache_read_input_tokens": 0,
                 "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}}
        return {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(stamp)),
                "message": {"id": mid, "model": "m", "usage": usage}}

    transcript = projects / "session.jsonl"
    transcript.write_text("\n".join(json.dumps(row) for row in [
        turn("t_20d", t_20d, 30000),
        turn("t_3d", t_3d, 20000),
        turn("t_2h", t_2h, 10000),
    ]) + "\n")

    cache = scratch_home / "rollup.json"

    # Cold run
    ctx_cold = {}
    rec_cold = dispatch_metrics._claude_rollup(projects, cache, ctx_cold)
    out_cold = dispatch_metrics.render([], 0, now, claude_records=rec_cold, claude_context=ctx_cold, repo_root=fake_repo)

    # Warm run
    ctx_warm = {}
    rec_warm = dispatch_metrics._claude_rollup(projects, cache, ctx_warm)
    out_warm = dispatch_metrics.render([], 0, now, claude_records=rec_warm, claude_context=ctx_warm, repo_root=fake_repo)

    for out in (out_cold, out_warm):
        assert 'k3dm_claude_context_ceiling_tokens{window="1d"} 10000' in out
        assert 'k3dm_claude_context_ceiling_tokens{window="7d"} 20000' in out
        assert 'k3dm_claude_context_ceiling_tokens{window="30d"} 30000' in out

    c_1d = 10000
    c_7d = 20000
    c_30d = 30000
    assert c_1d < c_7d < c_30d


def test_claude_quota_metrics_emitted_from_usage_cache(tmp_path, capsys):
    cache = tmp_path / "statusline-usage-cache.json"
    data = {
        "five_hour": {"utilization": 5.0, "resets_at": "2026-11-08T02:39:59.614566+00:00", "limit_dollars": None, "used_dollars": None, "remaining_dollars": None, "locked_reason": None},
        "seven_day": {"utilization": 17.0, "resets_at": "2026-11-12T21:59:59.614590+00:00", "limit_dollars": None, "used_dollars": None, "remaining_dollars": None, "locked_reason": None},
        "seven_day_opus": None,
        "seven_day_sonnet": None,
        "extra_usage": {"is_enabled": False, "monthly_limit": None, "used_credits": 0.0, "utilization": None, "currency": "USD", "disabled_reason": "out_of_credits"}
    }
    cache.write_text(json.dumps(data))
    mtime = 1794000000.0
    os.utime(cache, (mtime, mtime))

    assert dispatch_metrics.main([
        "--dry-run",
        "--claude-usage-cache", str(cache),
        "--codex-home", str(tmp_path / "codex"),
        "--prices", str(tmp_path / "prices.json"),
    ]) == 0
    output = capsys.readouterr().out

    assert f"k3dm_claude_quota_sample_timestamp_seconds {mtime}" in output
    assert 'k3dm_claude_quota_used_ratio{limit="five_hour",window_minutes="300"} 0.05' in output
    assert 'k3dm_claude_quota_resets_at_seconds{limit="five_hour",window_minutes="300"} 1794105599.614566' in output
    assert 'k3dm_claude_quota_used_ratio{limit="seven_day",window_minutes="10080"} 0.17' in output
    assert 'k3dm_claude_quota_resets_at_seconds{limit="seven_day",window_minutes="10080"} 1794520799.61459' in output
    assert "extra_usage" not in output
    assert "locked_reason" not in output
    assert "limit_dollars" not in output


def test_claude_quota_missing_unreadable_or_invalid_json(tmp_path, capsys):
    missing = tmp_path / "missing-cache.json"
    assert dispatch_metrics.main([
        "--dry-run",
        "--claude-usage-cache", str(missing),
        "--codex-home", str(tmp_path / "codex"),
        "--prices", str(tmp_path / "prices.json"),
    ]) == 0
    assert "k3dm_claude_quota_" not in capsys.readouterr().out

    invalid = tmp_path / "invalid-cache.json"
    invalid.write_text("not json {{{")
    assert dispatch_metrics.main([
        "--dry-run",
        "--claude-usage-cache", str(invalid),
        "--codex-home", str(tmp_path / "codex"),
        "--prices", str(tmp_path / "prices.json"),
    ]) == 0
    assert "k3dm_claude_quota_" not in capsys.readouterr().out


def test_claude_quota_null_or_non_numeric_utilization(tmp_path, capsys):
    cache = tmp_path / "statusline-usage-cache.json"
    data = {
        "five_hour": {"utilization": 5.0, "resets_at": "2026-11-08T02:39:59.614566+00:00"},
        "seven_day": None
    }
    cache.write_text(json.dumps(data))
    assert dispatch_metrics.main([
        "--dry-run",
        "--claude-usage-cache", str(cache),
        "--codex-home", str(tmp_path / "codex"),
        "--prices", str(tmp_path / "prices.json"),
    ]) == 0
    output = capsys.readouterr().out
    assert 'k3dm_claude_quota_used_ratio{limit="five_hour",window_minutes="300"} 0.05' in output
    assert 'limit="seven_day"' not in output

    data["five_hour"]["utilization"] = True
    data["seven_day"] = {"utilization": 17.0, "resets_at": "2026-11-12T21:59:59.614590+00:00"}
    cache.write_text(json.dumps(data))
    assert dispatch_metrics.main([
        "--dry-run",
        "--claude-usage-cache", str(cache),
        "--codex-home", str(tmp_path / "codex"),
        "--prices", str(tmp_path / "prices.json"),
    ]) == 0
    output = capsys.readouterr().out
    assert 'k3dm_claude_quota_used_ratio{limit="seven_day",window_minutes="10080"} 0.17' in output
    assert 'limit="five_hour"' not in output


def test_codex_quota_series_byte_identical_before_and_after(tmp_path):
    from datetime import datetime, timezone
    now = time.time()
    day = time.strftime("%Y/%m/%d", time.gmtime(now))
    home = tmp_path / "codex"
    folder = home / "sessions" / day
    folder.mkdir(parents=True)
    path = folder / "rollout-one.jsonl"
    path.write_text("\n".join([
        json.dumps({"type": "session_meta", "payload": {"id": "sid", "timestamp": datetime.fromtimestamp(now - 10, timezone.utc).isoformat(), "cwd": "/repo/shop", "originator": "codex_exec"}}),
        json.dumps({"type": "event_msg", "timestamp": datetime.fromtimestamp(now - 2, timezone.utc).isoformat(), "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 30}}, "rate_limits": {"primary": {"used_percent": 30, "window_minutes": 300, "resets_at": now + 10}, "secondary": {"used_percent": 40, "window_minutes": 10080, "resets_at": now + 20}}}}),
        json.dumps({"type": "event_msg", "payload": {"type": "task_complete", "duration_ms": 1500}}),
    ]) + "\n")
    output = dispatch_metrics.render([], 0, now, prices={}, codex_home=home)
    assert 'k3dm_codex_quota_used_ratio{limit="primary",window_minutes="300"} 0.3' in output
    assert 'k3dm_codex_quota_used_ratio{limit="secondary",window_minutes="10080"} 0.4' in output


def test_cost_attribution_coverage_and_guardian_assignment(tmp_path, monkeypatch):
    now = int(time.time())
    codex_home = tmp_path / "fake-codex"
    worktree_root = tmp_path / "worktrees"
    assert codex_home != Path.home() / ".codex"
    assert worktree_root != Path.home() / ".local/share/k3d-manager/worktrees"
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(worktree_root))

    rates = {
        "gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20},
        "gpt-6-luna": {"input": 0.30, "cached_input": 0.03, "output": 1.50},
    }
    # Note: codex-auto-review is unpriced (not in rates).

    def make_session(sid, started, originator, thread_source, parent_id, cwd, model, usage, prompt="SECRET PROMPT"):
        folder = codex_home / "sessions/2026/11/01"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"rollout-{sid}.jsonl"
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started))
        meta_payload = {
            "id": sid,
            "timestamp": stamp,
            "originator": originator,
            "thread_source": thread_source,
            "source": "exec" if originator == "codex_exec" else "tui",
        }
        if parent_id is not None:
            meta_payload["parent_thread_id"] = parent_id
        if cwd is not None:
            meta_payload["cwd"] = str(cwd)
        lines = [
            json.dumps({"type": "session_meta", "payload": meta_payload}),
            json.dumps({"type": "turn_context", "payload": {"model": model}}),
            json.dumps({"type": "event_msg", "payload": {"user_prompt": prompt}}),
        ]
        if usage is not None:
            lines.append(json.dumps({"type": "event_msg", "payload": {"type": "token_count", "info": {
                "model": model, "total_token_usage": usage}}}))
        path.write_text("\n".join(lines) + "\n")
        os.utime(path, (started, started))

    # 1. Dispatch session (in ledger, cwd under worktree root)
    make_session("s_dispatch", now - 100, "codex_exec", "user", None,
                 worktree_root / "v1.43.15/task-dispatch", "gpt-5.6-luna",
                 {"input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 2. Dispatch unrecorded session (not in ledger, cwd under worktree root)
    make_session("s_unrecorded", now - 100, "codex_exec", "user", None,
                 worktree_root / "v1.43.15/task-unrecorded", "gpt-5.6-luna",
                 {"input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 3. Interactive session (originator codex-tui, outside worktree root)
    make_session("s_interactive", now - 100, "codex-tui", "user", None,
                 tmp_path / "main-checkout", "gpt-5.6-luna",
                 {"input_tokens": 2_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 4. Exec untracked session (originator codex_exec, outside worktree root)
    make_session("s_exec", now - 100, "codex_exec", "user", None,
                 tmp_path / "main-checkout", "gpt-5.6-luna",
                 {"input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 5. Guardian session with dispatch parent (unpriced codex-auto-review)
    make_session("g_dispatch_unpriced", now - 90, "codex_exec", "guardian_review", "s_dispatch",
                 worktree_root / "v1.43.15/task-dispatch", "codex-auto-review",
                 {"input_tokens": 500_000, "cached_input_tokens": 100_000, "output_tokens": 50_000})
    # 6. Guardian session with dispatch parent (priced gpt-5.6-luna)
    make_session("g_dispatch_priced", now - 90, "codex_exec", "guardian_review", "s_dispatch",
                 worktree_root / "v1.43.15/task-dispatch", "gpt-5.6-luna",
                 {"input_tokens": 100_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 7. Guardian session with interactive parent (priced gpt-5.6-luna)
    make_session("g_interactive_priced", now - 80, "codex-tui", "guardian_review", "s_interactive",
                 tmp_path / "main-checkout", "gpt-5.6-luna",
                 {"input_tokens": 200_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 8. Guardian session with missing parent (priced gpt-5.6-luna)
    make_session("g_missing_parent", now - 70, "codex_exec", "guardian_review", "parent_not_scanned",
                 worktree_root / "v1.43.15/task-other", "gpt-5.6-luna",
                 {"input_tokens": 300_000, "cached_input_tokens": 0, "output_tokens": 0})
    # 9. Other session (originator neither codex-tui nor codex_exec)
    make_session("s_other", now - 60, "codex_vscode", "user", None,
                 tmp_path / "other-checkout", "gpt-5.6-luna",
                 {"input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0})
    corrupt_path = codex_home / "sessions/2026/11/01" / "rollout-s_corrupt.jsonl"
    corrupt_path.write_text("not json at all\n")
    os.utime(corrupt_path, (now - 60, now - 60))

    total_sessions = 9

    ledger = [
        event(now - 95, "codex_usage", session="s_dispatch", model="gpt-5.6-luna",
              input=1_000_000, cached_input=0, output=0)
    ]

    output = dispatch_metrics.render(ledger, 0, now, prices=rates, codex_home=codex_home)

    # M1: each fixture session lands in exactly one category from session_meta alone,
    # and k3dm_codex_sessions sums to the total session count
    assert 'k3dm_codex_sessions{window="1d",category="dispatch"} 1' in output
    assert 'k3dm_codex_sessions{window="1d",category="dispatch_unrecorded"} 1' in output
    assert 'k3dm_codex_sessions{window="1d",category="guardian"} 4' in output
    assert 'k3dm_codex_sessions{window="1d",category="interactive"} 1' in output
    assert 'k3dm_codex_sessions{window="1d",category="exec_untracked"} 1' in output
    assert 'k3dm_codex_sessions{window="1d",category="other"} 1' in output

    session_metric_lines = [line for line in output.splitlines()
                            if line.startswith('k3dm_codex_sessions{window="1d",category=')]
    assert len(session_metric_lines) == 6
    assert sum(int(line.split()[-1]) for line in session_metric_lines) == total_sessions

    # M2 & N2: guardian assignment and costs
    # Base costs (at $0.20 per 1M input tokens):
    # s_dispatch: $0.20
    # g_dispatch_priced (100k tokens = $0.02) added to dispatch -> dispatch = $0.22
    # s_interactive: $0.40
    # g_interactive_priced (200k tokens = $0.04) added to interactive -> interactive = $0.44
    # s_unrecorded: $0.20
    # s_exec: $0.20
    # g_missing_parent: 300k tokens = $0.06 -> stays guardian with parent="missing"
    # s_other: $0.00
    # g_dispatch_unpriced: unpriced codex-auto-review -> $0.00
    assert 'k3dm_codex_api_cost_usd{window="1d",category="dispatch"} 0.22' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="interactive"} 0.44' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="dispatch_unrecorded"} 0.2' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="exec_untracked"} 0.2' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="other"} 0' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="guardian",parent="missing"} 0.06' in output
    assert 'k3dm_codex_api_cost_usd{window="1d",category="guardian"} ' not in output  # N2: never counted twice

    cost_lines = [line for line in output.splitlines()
                  if line.startswith('k3dm_codex_api_cost_usd{window="1d",category=')]
    total_priced = sum(float(line.split()[-1]) for line in cost_lines)
    # Total priced = 0.22 + 0.44 + 0.20 + 0.20 + 0.00 + 0.06 = 1.12
    assert total_priced == pytest.approx(1.12)

    # M3: unpriced tokens of model with no price row appear in k3dm_codex_unpriced_tokens
    assert 'k3dm_codex_unpriced_tokens{window="1d",model="codex-auto-review",kind="input"} 500000' in output
    assert 'k3dm_codex_unpriced_tokens{window="1d",model="codex-auto-review",kind="cached_input"} 100000' in output
    assert 'k3dm_codex_unpriced_tokens{window="1d",model="codex-auto-review",kind="output"} 50000' in output

    # M4: coverage calculation: dispatch / (dispatch + dispatch_unrecorded + exec_untracked)
    # Baseline dispatch = 0.22, dispatch_unrecorded = 0.20, exec_untracked = 0.20
    # Base coverage = 0.22 / (0.22 + 0.20 + 0.20) = 0.22 / 0.62 = 0.354838...
    # Adding interactive cost:
    make_session("s_interactive_2", now - 50, "codex-tui", "user", None,
                 tmp_path / "main-checkout", "gpt-5.6-luna",
                 {"input_tokens": 5_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    output_interactive = dispatch_metrics.render(ledger, 0, now, prices=rates, codex_home=codex_home)
    # Interactive cost increased:
    assert 'k3dm_codex_api_cost_usd{window="1d",category="interactive"} 1.44' in output_interactive
    # But dispatch coverage by cost terms remain identical:
    assert 'k3dm_codex_api_cost_usd{window="1d",category="dispatch"} 0.22' in output_interactive
    assert 'k3dm_codex_api_cost_usd{window="1d",category="dispatch_unrecorded"} 0.2' in output_interactive
    assert 'k3dm_codex_api_cost_usd{window="1d",category="exec_untracked"} 0.2' in output_interactive

    # Adding dispatch_unrecorded cost:
    make_session("s_unrecorded_2", now - 40, "codex_exec", "user", None,
                 worktree_root / "v1.43.15/task-unrecorded-2", "gpt-5.6-luna",
                 {"input_tokens": 1_000_000, "cached_input_tokens": 0, "output_tokens": 0})
    output_unrecorded = dispatch_metrics.render(ledger, 0, now, prices=rates, codex_home=codex_home)
    assert 'k3dm_codex_api_cost_usd{window="1d",category="dispatch_unrecorded"} 0.4' in output_unrecorded
    # Denominator increases (0.22 / (0.22 + 0.40 + 0.20) = 0.22 / 0.82 < 0.22 / 0.62), lowering coverage

    # M6: deprecated metrics still emitted with previous values
    assert 'k3dm_dispatch_codex_sessions{window="1d",ledgered="true"} 1' in output
    # Non-ledgered sessions = 8 (s_unrecorded, s_interactive, s_exec, 4 guardians, s_other)
    assert 'k3dm_dispatch_codex_sessions{window="1d",ledgered="false"} 8' in output
    assert 'k3dm_dispatch_unledgered_api_cost_usd{window="1d"}' in output

    # N1: no metric line or label contains a prompt, cwd, session ID or parent ID
    assert "SECRET PROMPT" not in output
    assert "s_dispatch" not in output
    assert "s_interactive" not in output
    assert "g_dispatch_unpriced" not in output
    assert "parent_not_scanned" not in output
    assert str(worktree_root) not in output
    assert str(tmp_path) not in output


def test_parent_limit_matches_dispatcher_slug_limit():
    assert dispatch_metrics.PARENT_RE.fullmatch("p" * 120)
    assert not dispatch_metrics.PARENT_RE.fullmatch("p" * 121)


def test_claude_cost_prices_fable_at_published_rates_and_preserves_opus():
    price_file = dispatch_metrics._repo_root() / "scripts/etc/agent/codex-model-prices.json"
    _, _, _, claude_models = dispatch_metrics._prices(price_file)
    now = 1_800_000_000
    fable_rec = _claude_message("fable-1", now, model="claude-fable-5-1",
                                input=10_000, output=1_000, cache_read=5_000,
                                cache_5m=2_000, cache_1h=1_000)
    opus_rec = _claude_message("opus-1", now, model="claude-opus-5-5",
                               input=10_000, output=1_000, cache_read=5_000,
                               cache_5m=2_000, cache_1h=1_000)
    cost_fable = dispatch_metrics._claude_cost(fable_rec, claude_models)
    cost_opus = dispatch_metrics._claude_cost(opus_rec, claude_models)
    assert cost_opus == pytest.approx(0.079)
    assert cost_fable is not None
    assert cost_fable == pytest.approx(0.19625)


def test_claude_cost_prices_fable_52_and_preserves_fable_51():
    price_file = dispatch_metrics._repo_root() / "scripts/etc/agent/codex-model-prices.json"
    _, _, _, claude_models = dispatch_metrics._prices(price_file)
    now = 1_800_000_000
    fable_51 = _claude_message("fable-51", now, model="claude-fable-5-1",
                               input=10_000, output=1_000, cache_read=5_000,
                               cache_5m=2_000, cache_1h=1_000)
    fable_52 = _claude_message("fable-52", now, model="claude-fable-5-2",
                               input=10_000, output=1_000, cache_read=5_000,
                               cache_5m=2_000, cache_1h=1_000)
    assert dispatch_metrics._claude_cost(fable_51, claude_models) == pytest.approx(0.19625)
    assert dispatch_metrics._claude_cost(fable_52, claude_models) == pytest.approx(0.157)


def test_claude_quota_exports_weekly_fable_limit_and_preserves_five_hour_seven_day(tmp_path):
    cache_path = tmp_path / "statusline-usage-cache.json"
    cache_data = {
        "five_hour": {"utilization": 5.0, "resets_at": "2026-11-10T19:00:00+00:00"},
        "seven_day": {"utilization": 17.0, "resets_at": "2026-11-15T19:00:00+00:00"},
        "limits": [
            {"kind": "session", "group": "session", "percent": 5},
            {"kind": "weekly_all", "group": "weekly", "percent": 17},
            {
                "kind": "weekly_scoped",
                "group": "weekly",
                "percent": 1,
                "scope": {"model": {"id": None, "display_name": "Fable"}},
                "resets_at": "2026-11-12T22:00:00.023023+00:00",
                "is_active": False,
            },
        ],
    }
    cache_path.write_text(json.dumps(cache_data), encoding="utf-8")
    lines = []
    dispatch_metrics._claude_quota(lines, str(cache_path))
    output = "\n".join(lines)
    assert 'k3dm_claude_quota_used_ratio{limit="five_hour",window_minutes="300"} 0.05' in output
    assert 'k3dm_claude_quota_used_ratio{limit="seven_day",window_minutes="10080"} 0.17' in output
    assert 'k3dm_claude_quota_used_ratio{limit="weekly_fable",window_minutes="10080"} 0.01' in output
    assert 'k3dm_claude_quota_resets_at_seconds{limit="weekly_fable",window_minutes="10080"}' in output

    cache_path_no_limits = tmp_path / "cache_no_limits.json"
    cache_path_no_limits.write_text(json.dumps({
        "five_hour": {"utilization": 5.0, "resets_at": "2026-11-10T19:00:00+00:00"},
        "seven_day": {"utilization": 17.0, "resets_at": "2026-11-15T19:00:00+00:00"},
    }), encoding="utf-8")
    lines2 = []
    dispatch_metrics._claude_quota(lines2, str(cache_path_no_limits))
    output2 = "\n".join(lines2)
    assert 'k3dm_claude_quota_used_ratio{limit="five_hour",window_minutes="300"} 0.05' in output2
    assert 'k3dm_claude_quota_used_ratio{limit="seven_day",window_minutes="10080"} 0.17' in output2
    assert "weekly_fable" not in output2


def test_model_identity_allowlists_flash_fable_and_normalizes_unknown_models():
    output = dispatch_metrics.render([
        event(1, "start", "flash-run", agent="agy",
              worker_identity={"vendor": "google", "model": "gemini-3.8-flash-medium", "source": "explicit", "status": "selected"}),
        event(2, "agent_exit", "flash-run", usage={"total_tokens": 100}),
        event(3, "land", "flash-run"),
        event(4, "start", "fable-run", agent="agy",
              worker_identity={"vendor": "anthropic", "model": "claude-fable-5-1", "source": "explicit", "status": "selected"}),
        event(5, "agent_exit", "fable-run", usage={"total_tokens": 100}),
        event(6, "land", "fable-run"),
        event(7, "start", "fable-52-run", agent="agy",
              worker_identity={"vendor": "anthropic", "model": "claude-fable-5-2", "source": "explicit", "status": "selected"}),
        event(8, "agent_exit", "fable-52-run", usage={"total_tokens": 100}),
        event(9, "land", "fable-52-run"),
        event(10, "start", "luna-run", agent="codex",
              worker_identity={"vendor": "openai", "model": "gpt-6-luna", "source": "explicit", "status": "selected"}),
        event(11, "codex_exit", "luna-run", tokens=100),
        event(12, "land", "luna-run"),
        event(13, "start", "madeup-run", agent="codex",
              worker_identity={"vendor": "openai", "model": "unreal-ai-model-x", "source": "explicit", "status": "selected"}),
        event(14, "codex_exit", "madeup-run", tokens=100),
        event(15, "land", "madeup-run"),
    ], 0, 100)
    lines = [line for line in output.splitlines() if line.startswith('k3dm_dispatch_model_identity{window="1d",') and 'role="worker"' in line]
    by_slug = {}
    for line in lines:
        for slug in ("flash-run", "fable-run", "fable-52-run", "luna-run", "madeup-run"):
            if f'slug="{slug}"' in line:
                by_slug[slug] = line
    assert 'model="gemini-3.8-flash-medium"' in by_slug["flash-run"]
    assert 'display="google/gemini-3.8-flash-medium (selected)"' in by_slug["flash-run"]
    assert 'model="claude-fable-5-1"' in by_slug["fable-run"]
    assert 'display="anthropic/claude-fable-5-1 (selected)"' in by_slug["fable-run"]
    assert 'model="claude-fable-5-2"' in by_slug["fable-52-run"]
    assert 'display="anthropic/claude-fable-5-2 (selected)"' in by_slug["fable-52-run"]
    assert 'model="gpt-6-luna"' in by_slug["luna-run"]
    assert 'display="openai/gpt-6-luna (selected)"' in by_slug["luna-run"]
    assert 'model="other"' in by_slug["madeup-run"]
    assert 'display="openai/other (selected)"' in by_slug["madeup-run"]


def test_resume_env_coordinator_overrides_unreported_or_different_start_identity():
    now = time.time()
    sol = {"vendor": "openai", "model": "gpt-6.1-sol", "source": "env", "status": "declared"}
    ledger = [
        event(now - 6, "start", "resume-after-unreported", coordinator_identity={
            "vendor": "unknown", "model": "unknown", "source": "unreported", "status": "unknown"}),
        event(now - 5, "resume", "resume-after-unreported", coordinator_identity=sol),
        event(now - 4, "land", "resume-after-unreported", result="landed"),
        event(now - 3, "start", "resume-after-other", coordinator_identity={
            "vendor": "openai", "model": "gpt-6-luna", "source": "declared", "status": "declared"}),
        event(now - 2, "resume", "resume-after-other", coordinator_identity=sol),
        event(now - 1, "land", "resume-after-other", result="landed"),
    ]
    output = dispatch_metrics.render(ledger, 0, now=now, prices={}, codex_home=Path("/nonexistent"))
    coordinators = _identity_lines(output, "coordinator")
    attributed = [line for line in coordinators if 'source="env"' in line]
    assert len(attributed) == 2, output
    assert all('vendor="openai",model="gpt-6.1-sol",source="env",status="declared"' in line
               for line in attributed)


def test_unreported_coordinator_share_counts_legacy_starts_and_scopes_start_events():
    now = time.time()
    ledger = [
        event(now - 20, "start", "legacy"),
        event(now - 19, "start", "env-run", coordinator_identity={
            "vendor": "openai", "model": "gpt-6.1-sol", "source": "env", "status": "declared"}),
        event(now - 18, "resume", "legacy", coordinator_identity={
            "vendor": "openai", "model": "gpt-6.1-sol", "source": "env", "status": "declared"}),
        event(now - 86401, "start", "outside-one-day"),
    ]
    output = dispatch_metrics.render(ledger, 0, now=now, prices={}, codex_home=Path("/nonexistent"))
    assert 'k3dm_dispatch_coordinator_unreported_share{window="1d"} 0.5' in output
    assert 'k3dm_dispatch_coordinator_unreported_share{window="7d"} 0.6666666666666666' in output


def test_unreported_coordinator_share_emits_no_series_when_window_has_no_starts():
    now = time.time()
    output = dispatch_metrics.render([event(now - 86401, "start", "old-start")], 0,
                                     now=now, prices={}, codex_home=Path("/nonexistent"))
    assert 'k3dm_dispatch_coordinator_unreported_share{window="1d"}' not in output
    assert 'k3dm_dispatch_coordinator_unreported_share{window="7d"} 1.0' in output
    empty = dispatch_metrics.render([], 0, now=now, prices={}, codex_home=Path("/nonexistent"))
    assert "k3dm_dispatch_coordinator_unreported_share" not in empty


def test_dispatch_dashboard_has_unreported_coordinator_share_stat():
    dashboard = load_dispatch_dashboard()
    panel = next(panel for panel in dashboard["panels"] if panel.get("title") == "Unreported coordinator share")
    assert panel["type"] == "stat"
    assert panel["targets"][0]["expr"] == 'k3dm_dispatch_coordinator_unreported_share{window="$window"}'
