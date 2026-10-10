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


def test_render_has_no_slug():
    output = dispatch_metrics.render([event(1, "start", "secret-slug")], 0, 100)
    assert "secret-slug" not in output
