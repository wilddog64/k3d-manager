import importlib.util
import json
import logging
from http.server import BaseHTTPRequestHandler
import os
import sys
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
import webhook.render as render

_WEBHOOK = Path(os.environ.get("K3DM_TEST_WEBHOOK_FILE", ROOT / "bin" / "k3dm-webhook"))
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_analyze_routing", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_analyze_routing", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture
def analyze_env(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "test-token")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C-TASK")
    monkeypatch.setattr(wh, "STATUS_CHANNEL_ID", "C-STATUS")
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", "https://hooks.invalid/test")
    monkeypatch.setattr(wh, "_posix_spawn_capture", lambda *args, **kwargs: ("diagnostic output", False))
    monkeypatch.setattr(wh, "_call_gemini", lambda prompt: "test analysis")


def _run(monkeypatch, tmp_path, alerts, response_url=""):
    job_dir = tmp_path / "job"
    job_dir.mkdir()
    wh._run_analyze("job", {"alerts": alerts}, response_url=response_url)
    return (job_dir / "output").read_text()


def _alert(name="DiskFull", app="api"):
    return {"status": "firing", "labels": {"alertname": name, "app": app}}


def test_posts_to_status_channel_when_bot_is_available(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: bot_calls.append((text, kwargs)) or "123.45")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args))

    _run(monkeypatch, tmp_path, [_alert()])

    assert len(bot_calls) == 1
    assert bot_calls[0][1] == {"channel_id": "C-STATUS"}
    assert "🔍 *DiskFull* — `api`\ntest analysis" == bot_calls[0][0]
    assert webhook_calls == []
    assert (tmp_path / "job" / "status").read_text() == "success"


def test_failed_bot_post_falls_back_to_incoming_webhook(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: bot_calls.append((text, kwargs)) or "")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args) or True)

    _run(monkeypatch, tmp_path, [_alert()])

    assert len(bot_calls) == 1
    assert webhook_calls == [("https://hooks.invalid/test", bot_calls[0][0])]
    assert (tmp_path / "job" / "status").read_text() == "success"


def test_failed_routes_record_delivery_failed_keep_analysis_and_redact_secrets(
    monkeypatch, analyze_env, tmp_path, caplog
):
    monkeypatch.setattr(wh, "STATUS_CHANNEL_ID", "")
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", "https://hooks.invalid/secret-url")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: False)
    with caplog.at_level(logging.WARNING, logger="webhook"):
        _run(monkeypatch, tmp_path, [_alert()])

    assert (tmp_path / "job" / "status").read_text() == "delivery_failed"
    assert "test analysis" in (tmp_path / "job" / "output").read_text()
    assert "route=webhook" in caplog.text
    assert "reason=webhook_post_failed" in caplog.text
    assert "secret-url" not in caplog.text
    assert "test-token" not in caplog.text


def test_no_configured_route_records_delivery_failed(monkeypatch, analyze_env, tmp_path, caplog):
    monkeypatch.setattr(wh, "STATUS_CHANNEL_ID", "")
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", "")
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "")
    with caplog.at_level(logging.WARNING, logger="webhook"):
        _run(monkeypatch, tmp_path, [_alert()])

    assert (tmp_path / "job" / "status").read_text() == "delivery_failed"
    assert "route=none" in caplog.text
    assert "reason=no_route_configured" in caplog.text


def test_response_url_failure_records_delivery_failed(monkeypatch, analyze_env, tmp_path, caplog):
    monkeypatch.setattr(wh, "_slack_post", lambda *args: False)
    with caplog.at_level(logging.WARNING, logger="webhook"):
        _run(monkeypatch, tmp_path, [_alert()], response_url="https://hooks.invalid/response")

    assert (tmp_path / "job" / "status").read_text() == "delivery_failed"
    assert "route=response_url" in caplog.text


@pytest.mark.parametrize(("response_code", "expected_status"), [(200, "success"), (500, "delivery_failed")])
def test_local_response_endpoint_result_controls_job_status(
    monkeypatch, analyze_env, tmp_path, caplog, response_code, expected_status
):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self.send_response(response_code)
            self.end_headers()

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        assert server.server_address[0] == "127.0.0.1"
        local_url = f"http://127.0.0.1:{server.server_address[1]}/slack"
        monkeypatch.setattr(render, "_is_allowed_slack_url", lambda url: url == local_url)
        monkeypatch.setattr(wh, "_slack_post", render._slack_post)
        with caplog.at_level(logging.WARNING, logger="webhook"):
            _run(monkeypatch, tmp_path, [_alert()], response_url=local_url)
        assert (tmp_path / "job" / "status").read_text() == expected_status
        if response_code == 500:
            assert "route=response_url" in caplog.text
            assert "reason=post_failed" in caplog.text
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_response_url_takes_precedence(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: bot_calls.append((args, kwargs)) or "123")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args))

    _run(monkeypatch, tmp_path, [_alert()], response_url="https://hooks.invalid/response")

    assert bot_calls == []
    assert webhook_calls == [("https://hooks.invalid/response", "🔍 *DiskFull* — `api`\ntest analysis")]


def test_empty_status_channel_uses_incoming_webhook(monkeypatch, analyze_env, tmp_path):
    monkeypatch.setattr(wh, "STATUS_CHANNEL_ID", "")
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: bot_calls.append((args, kwargs)))
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args))

    _run(monkeypatch, tmp_path, [_alert()])

    assert bot_calls == []
    assert webhook_calls == [("https://hooks.invalid/test", "🔍 *DiskFull* — `api`\ntest analysis")]


def test_each_firing_alert_posts_to_status_channel(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: bot_calls.append((text, kwargs)) or "123")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args))

    _run(monkeypatch, tmp_path, [_alert("DiskFull"), _alert("PodCrash", "worker")])

    assert len(bot_calls) == 2
    assert [call[1] for call in bot_calls] == [{"channel_id": "C-STATUS"}] * 2
    assert webhook_calls == []


def test_bot_never_posts_to_task_channel(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: bot_calls.append(kwargs) or "123")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: None)

    _run(monkeypatch, tmp_path, [_alert()])

    assert bot_calls == [{"channel_id": "C-STATUS"}]
    assert all(call.get("channel_id") != "C-TASK" for call in bot_calls)


def test_http_analyze_accepts_captured_alertmanager_batch(monkeypatch, analyze_env, tmp_path):
    fixture = ROOT / "scripts/tests/fixtures/webhook/alertmanager-analyze-batch.json"
    # Captured alert data: m5-air.local, 2026-11-06; largest TrivyCriticalVulnerabilityDetected group.
    assert fixture.is_file(), "expected the task's captured Alertmanager fixture"
    payload = json.loads(fixture.read_text())
    body = json.dumps(payload, separators=(",", ":")).encode()
    assert len(body) > wh.MAX_BODY
    assert len(body) <= getattr(wh, "ANALYZE_MAX_BODY", 262144)
    assert wh.JOB_DIR == tmp_path

    monkeypatch.setattr(wh, "_get_token", lambda: "operator-test-token")
    monkeypatch.setattr(wh, "_get_reader_token", lambda: "")
    monkeypatch.setattr(wh, "_get_cloud_runner_token", lambda: "")
    monkeypatch.setattr(wh, "_resolve_token_role", lambda token: "operator" if token == "operator-test-token" else None)
    monkeypatch.setattr(wh, "_rate_limited", lambda *_: False)
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_run_analyze", lambda *args, **kwargs: None)

    server = ThreadingHTTPServer(("127.0.0.1", 0), wh._Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        # The bound loopback address asserts this test cannot contact the live webhook.
        assert server.server_address[0] == "127.0.0.1"
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/v1/analyze",
            data=body,
            headers={"Authorization": "Bearer operator-test-token", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 202
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_analyze_body_over_new_limit_is_rejected(monkeypatch, analyze_env):
    monkeypatch.setattr(wh, "_get_token", lambda: "operator-test-token")
    monkeypatch.setattr(wh, "_get_reader_token", lambda: "")
    monkeypatch.setattr(wh, "_get_cloud_runner_token", lambda: "")
    monkeypatch.setattr(wh, "_resolve_token_role", lambda token: "operator" if token == "operator-test-token" else None)
    _assert_http_rejected(monkeypatch, "/api/v1/analyze", b" " * (wh.ANALYZE_MAX_BODY + 1), "operator-test-token", 413)


def test_cve_remediate_accepts_body_over_4096_bytes(monkeypatch, analyze_env):
    monkeypatch.setattr(wh, "_get_token", lambda: "operator-test-token")
    monkeypatch.setattr(wh, "_get_reader_token", lambda: "")
    monkeypatch.setattr(wh, "_get_cloud_runner_token", lambda: "")
    monkeypatch.setattr(wh, "_resolve_token_role", lambda token: "operator" if token == "operator-test-token" else None)
    monkeypatch.setattr(wh, "_rate_limited", lambda *_: False)
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_active_cve_scan_job", lambda: "")
    body = json.dumps({"alerts": [], "padding": "x" * 5000}, separators=(",", ":")).encode()
    assert len(body) > wh.MAX_BODY

    server = ThreadingHTTPServer(("127.0.0.1", 0), wh._Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        assert server.server_address[0] == "127.0.0.1"
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/v1/cve-remediate",
            data=body,
            headers={"Authorization": "Bearer operator-test-token", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_other_routes_keep_4096_byte_limit(monkeypatch, analyze_env):
    monkeypatch.setattr(wh, "_get_token", lambda: "operator-test-token")
    monkeypatch.setattr(wh, "_get_reader_token", lambda: "")
    monkeypatch.setattr(wh, "_get_cloud_runner_token", lambda: "")
    monkeypatch.setattr(wh, "_resolve_token_role", lambda token: "operator" if token == "operator-test-token" else None)
    _assert_http_rejected(monkeypatch, "/api/v1/ask", b" " * (wh.MAX_BODY + 1), "operator-test-token", 413)


def test_unauthenticated_large_analyze_body_is_rejected(monkeypatch, analyze_env):
    _assert_http_rejected(monkeypatch, "/api/v1/analyze", b" " * (wh.MAX_BODY + 1), "", 401)


def _assert_http_rejected(monkeypatch, path, body, token, expected_status):
    monkeypatch.setattr(wh, "_rate_limited", lambda *_: False)
    server = ThreadingHTTPServer(("127.0.0.1", 0), wh._Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        assert server.server_address[0] == "127.0.0.1"
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}{path}",
            data=body,
            headers=headers,
            method="POST",
        )
        with pytest.raises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request, timeout=5)
        assert error.value.code == expected_status
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
