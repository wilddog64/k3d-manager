import importlib.util
import io
import json
import socket
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_cluster_status_thread", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_cluster_status_thread", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture
def status_env(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh._status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C1")
    monkeypatch.setattr(wh._status, "_slack_bot_token", lambda: wh.SLACK_BOT_TOKEN)
    monkeypatch.setattr(wh._status, "_slack_channel_id", lambda: wh.SLACK_CHANNEL_ID)
    monkeypatch.setattr(wh, "_slack_post", lambda *args: None)
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: "HEADER-TS")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: "BODY-TS")
    monkeypatch.setattr(wh._status, "_slack_post", lambda *args: wh._slack_post(*args))
    monkeypatch.setattr(wh._status, "_start_bot_thread", lambda header: wh._start_bot_thread(header))
    monkeypatch.setattr(wh._status, "_post_slack_bot", lambda *args, **kwargs: wh._post_slack_bot(*args, **kwargs))
    monkeypatch.setattr(wh._status, "_redact_secrets", lambda text: text)
    monkeypatch.setattr(wh._status, "_notify_job", lambda *args: None)
    monkeypatch.setattr(wh._status, "_smoke_test_services", lambda **kwargs: [("API", True, "ok")])


def _run_hostinger(monkeypatch, job_dir, **kwargs):
    (job_dir / "job").mkdir()
    wh._status._run_hostinger_status("job", "https://hooks.slack.test/response", **kwargs)
    return (job_dir / "job" / "output").read_text()


def test_hostinger_bot_path_posts_verdict_and_details_in_thread(monkeypatch, status_env, tmp_path):
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: calls.append(("header", header)) or "HEADER-TS")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, thread_ts=None: calls.append(("body", text, thread_ts)) or "BODY-TS")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(("fallback", args)))
    output = _run_hostinger(monkeypatch, tmp_path, channel_id="C1")
    assert calls[0] == ("header", output.splitlines()[0])
    assert calls[1] == ("body", "\n".join(output.splitlines()[1:]) + "\n", "HEADER-TS")
    assert (tmp_path / "job" / "thread_ts").read_text() == "HEADER-TS"
    assert not any(call[0] == "fallback" for call in calls)


def test_cluster_bot_path_uses_same_thread_delivery(monkeypatch, status_env, tmp_path):
    (tmp_path / "job").mkdir()
    responses = iter([
        ("hub Ready 1 1", False), ("app Ready 1 1", False), ("", False),
        ("", False), ("", False), ("", False),
    ])
    monkeypatch.setattr(wh._status, "_posix_spawn_capture", lambda *args, **kwargs: next(responses))
    monkeypatch.setattr(wh._status, "_resolve_provider", lambda provider: provider or "hostinger")
    monkeypatch.setattr(wh._status, "_provider_context", lambda provider: "app-context")
    monkeypatch.setattr(wh._status, "_acg_stack_probe", lambda provider: None)
    monkeypatch.setattr(wh._status, "_running_cluster_job", lambda: None)
    class _Connection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    monkeypatch.setattr(socket, "create_connection", lambda *args, **kwargs: _Connection())
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: calls.append(("header", header)) or "CLUSTER-TS")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, thread_ts=None: calls.append(("body", text, thread_ts)) or "BODY-TS")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(("fallback", args)))
    wh._status._run_cluster_status("job", "https://hooks.slack.test/response", provider="hostinger", channel_id="C1")
    output = (tmp_path / "job" / "output").read_text()
    assert calls[0] == ("header", output.splitlines()[0])
    assert calls[1][2] == "CLUSTER-TS"
    assert (tmp_path / "job" / "thread_ts").read_text() == "CLUSTER-TS"
    assert not any(call[0] == "fallback" for call in calls)


@pytest.mark.parametrize("channel_id", ["C2", ""])
def test_wrong_or_empty_channel_uses_response_url_only(monkeypatch, status_env, tmp_path, channel_id):
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: calls.append("header") or "TS")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: calls.append("body") or "TS")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(args))
    output = _run_hostinger(monkeypatch, tmp_path, channel_id=channel_id)
    assert calls == [("https://hooks.slack.test/response", output)]


def test_incoming_thread_does_not_start_new_header(monkeypatch, status_env, tmp_path):
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: calls.append("header") or "NEW")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: calls.append("body") or "OK")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(args))
    output = _run_hostinger(monkeypatch, tmp_path, channel_id="C1", thread_ts="INCOMING")
    assert calls == [("https://hooks.slack.test/response", output)]
    assert (tmp_path / "job" / "thread_ts").read_text() == "INCOMING"


def test_header_failure_posts_full_report_once(monkeypatch, status_env, tmp_path):
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: "")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(args))
    output = _run_hostinger(monkeypatch, tmp_path, channel_id="C1")
    assert calls == [("https://hooks.slack.test/response", output)]


def test_body_failure_posts_body_only(monkeypatch, status_env, tmp_path):
    calls = []
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: "HEADER-TS")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: "")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: calls.append(args))
    output = _run_hostinger(monkeypatch, tmp_path, channel_id="C1")
    body = "\n".join(output.splitlines()[1:]) + "\n"
    assert calls == [("https://hooks.slack.test/response", body)]


def test_cluster_status_route_passes_channel_id(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh._Handler, "_auth", lambda self: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda key: False)
    monkeypatch.setattr(wh, "_request_role", lambda headers, token_role: "admin")
    monkeypatch.setattr(wh, "_request_actor", lambda headers: "test")
    started = []

    class Thread:
        def __init__(self, *, target, args=(), kwargs=None, daemon=None):
            started.append((target, args, kwargs))

        def start(self):
            return None

    monkeypatch.setattr(wh.threading, "Thread", Thread)
    body = json.dumps({"provider": "hostinger", "response_url": "", "channel_id": "C1"}).encode()
    fake = type("FakeHandler", (), {
        "path": "/api/v1/cluster-status",
        "headers": {"Content-Length": str(len(body))},
        "rfile": io.BytesIO(body),
        "wfile": io.BytesIO(),
        "_auth": lambda self: True,
        "send_response": lambda self, code: None,
        "send_header": lambda self, key, value: None,
        "end_headers": lambda self: None,
        "_json": lambda self, code, response: None,
    })()
    wh._Handler.do_POST(fake)
    assert started
    assert started[0][2]["channel_id"] == "C1"
