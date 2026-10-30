import http.server
import importlib.machinery
import importlib.util
import json
import threading
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parents[3] / "bin" / "k3dm-dispatch-logs"
LOADER = importlib.machinery.SourceFileLoader("dispatch_logs", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("dispatch_logs", LOADER)
dispatch_logs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dispatch_logs)


class LokiHandler(http.server.BaseHTTPRequestHandler):
    requests = []
    status = 204

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.__class__.requests.append(json.loads(body))
        self.send_response(self.__class__.status)
        self.end_headers()

    def log_message(self, *_args):
        pass


@pytest.fixture
def loki(monkeypatch):
    LokiHandler.requests = []
    LokiHandler.status = 204
    server = http.server.HTTPServer(("127.0.0.1", 0), LokiHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setenv("K3DM_DISPATCH_LOKI_URL", f"http://127.0.0.1:{server.server_port}")
    LokiHandler.server = server
    yield LokiHandler
    server.shutdown()
    thread.join()
    server.server_close()


@pytest.fixture
def setup_run(tmp_path, monkeypatch):
    home = tmp_path / "home"
    root = tmp_path / "worktrees"
    run_dir = root / "v1.43.7" / "sample.run"
    run_dir.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root))
    monkeypatch.setattr(Path, "home", classmethod(lambda _cls: home))
    ledger = [
        {"ts": 1, "event": "start", "version": "v1.43.7", "slug": "sample", "run": 1},
        {"ts": 2, "event": "codex_exit", "version": "v1.43.7", "slug": "sample", "run": 1, "exit": 0, "tree": "abc"},
        {"ts": 3, "event": "land", "version": "v1.43.7", "slug": "sample", "test_result": "passed", "tree": "abc"},
    ]
    (root / "ledger.jsonl").write_text("\n".join(json.dumps(row) for row in ledger) + "\n")
    return root, run_dir


def test_pushes_exact_labels_once_and_repushes_changed_content(setup_run, loki):
    _, run_dir = setup_run
    log = run_dir / "land-test.log"
    log.write_text("test summary\n")
    assert dispatch_logs.main([]) == 0
    assert dispatch_logs.main([]) == 0
    streams = loki.requests
    assert len(streams) == 1
    assert set(streams[0]["streams"][0]["stream"]) == {"job", "version", "slug", "run"}
    log.write_text("changed summary\n")
    assert dispatch_logs.main([]) == 0
    assert len(loki.requests) == 2


def test_redacts_credentials_and_home(setup_run, loki, tmp_path):
    _, run_dir = setup_run
    values = ["hvs." + "a" * 20, "ghp_" + "b" * 30, "github_pat_" + "c" * 20,
              "sk_test_" + "d" * 10, "xoxb-" + "e" * 6,
              "https://hooks.slack.com/services/T000/B000/secret", "AKIA" + "A" * 16,
              "-----BEGIN RSA PRIVATE KEY-----"]
    (run_dir / "land-test.log").write_text("\n".join(values + [str(Path.home() / "private/file")]) + "\n")
    dispatch_logs.main([])
    body = json.dumps(loki.requests)
    assert all(value not in body for value in values)
    assert str(Path.home()) not in body
    assert "<redacted>" in body and "~/private/file" in body


def test_caps_lines_within_loki_query_limit(setup_run, loki):
    _, run_dir = setup_run
    (run_dir / "land-test.log").write_text("".join(f"line-{i}\n" for i in range(5999)) + "z" * 2501 + "\nlast-line\n")
    dispatch_logs.main([])
    lines = [item[1] for item in loki.requests[0]["streams"][0]["values"]]
    assert len(lines) == 5000
    assert lines[0].startswith("[shipped ") and "sha256:" in lines[0]
    assert lines[1] == "[truncated: 1003 earlier lines]"
    assert lines[-1] == "last-line"
    assert all(len(line) <= 2000 for line in lines)


def test_never_reads_codex_log_or_ships_non_test_evidence(setup_run, loki):
    root, run_dir = setup_run
    (run_dir / "land-test.log").write_text("safe\n")
    (run_dir / "codex.log").write_text("PLANTED_CODEX_MARKER\n")
    dispatch_logs.main([])
    assert "PLANTED_CODEX_MARKER" not in json.dumps(loki.requests)
    events = [json.loads(line) for line in (root / "ledger.jsonl").read_text().splitlines()]
    events[-1]["test_result"] = "failed"
    events[-1]["tree"] = "other"
    events[1]["exit"] = 1
    (root / "ledger.jsonl").write_text("\n".join(json.dumps(row) for row in events) + "\n")
    (root / "dispatch-logs-shipped.json").unlink()
    loki.requests.clear()
    dispatch_logs.main([])
    assert loki.requests == []


def test_unreachable_retries_without_recording_state(setup_run, monkeypatch, loki):
    root, run_dir = setup_run
    (run_dir / "land-test.log").write_text("retry me\n")
    monkeypatch.setenv("K3DM_DISPATCH_LOKI_URL", "http://127.0.0.1:9")
    assert dispatch_logs.main([]) == 0
    assert not (root / "dispatch-logs-shipped.json").exists()
    monkeypatch.setenv("K3DM_DISPATCH_LOKI_URL", f"http://127.0.0.1:{loki.server.server_port}")
    assert dispatch_logs.main([]) == 0
    assert len(loki.requests) == 1


def test_server_error_does_not_record_state(setup_run, loki):
    root, run_dir = setup_run
    (run_dir / "land-test.log").write_text("retry after 500\n")
    loki.status = 500
    assert dispatch_logs.main([]) == 0
    assert not (root / "dispatch-logs-shipped.json").exists()


def test_dry_run_does_not_send_request(setup_run, loki, capsys):
    _, run_dir = setup_run
    (run_dir / "land-test.log").write_text("preview only\n")
    assert dispatch_logs.main(["--dry-run"]) == 0
    assert loki.requests == []
    assert "lines=2" in capsys.readouterr().out


def test_metrics_calls_shipper_only_after_successful_non_dry_push(monkeypatch, tmp_path):
    import importlib.machinery
    import importlib.util
    metrics_path = SCRIPT.with_name("k3dm-dispatch-metrics")
    loader = importlib.machinery.SourceFileLoader("dispatch_metrics_for_logs", str(metrics_path))
    spec = importlib.util.spec_from_loader("dispatch_metrics_for_logs", loader)
    metrics = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(metrics)
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(tmp_path / "worktrees"))
    monkeypatch.setenv("K3DM_AGENT_LEDGER_DIR", str(tmp_path / "agents"))
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda *_a, **_k: type("Response", (), {"__enter__": lambda s: s, "__exit__": lambda *_: None})())
    monkeypatch.setattr(metrics, "_verified_specs", lambda *_a: {
        window: {level: 0 for level in ("live", "verified", "unverified")}
        for window in ("1d", "7d", "30d")
    })
    calls = []
    monkeypatch.setattr(metrics.subprocess, "run", lambda *a, **_k: calls.append(a) or type("Result", (), {"returncode": 0, "stdout": ""})())
    assert metrics.main(["--prices", str(tmp_path / "missing")]) == 0
    assert len(calls) == 1 and calls[0][0][0].endswith("k3dm-dispatch-logs")
    calls.clear()
    assert metrics.main(["--dry-run", "--prices", str(tmp_path / "missing")]) == 0
    assert calls == []


def test_ships_only_the_latest_run_of_a_slug(setup_run, loki):
    root, run_dir = setup_run
    (run_dir / "land-test.log").write_text("second attempt\n")
    rows = [json.loads(line) for line in (root / "ledger.jsonl").read_text().splitlines()]
    rows[1]["tree"] = "old"
    rows += [
        {"ts": 4, "event": "land_refused", "version": "v1.43.7", "slug": "sample", "reason": "tests"},
        {"ts": 5, "event": "resume", "version": "v1.43.7", "slug": "sample", "run": 2},
        {"ts": 6, "event": "codex_exit", "version": "v1.43.7", "slug": "sample", "run": 2, "exit": 0, "tree": "new"},
        {"ts": 7, "event": "land", "version": "v1.43.7", "slug": "sample", "test_result": "passed", "tree": "new"},
    ]
    (root / "ledger.jsonl").write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    assert dispatch_logs.main([]) == 0
    assert [request["streams"][0]["stream"]["run"] for request in loki.requests] == ["2"]


def test_run_log_panel_reads_every_shipped_line():
    dashboard = (SCRIPT.parents[1] / "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-run-log.yaml").read_text()
    assert '"maxLines": 5000' in dashboard
    assert dispatch_logs.KEEP_LINES + 2 <= 5000
