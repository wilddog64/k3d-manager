import importlib.util
import io
import json
import threading
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_thread_dispatch", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_thread_dispatch", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture
def dispatch_env(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    (tmp_path / "job").mkdir()
    started = []
    notices = []

    class Thread:
        def __init__(self, *, target, args=(), kwargs=None, daemon=None):
            started.append((target, args, kwargs))

        def start(self):
            return None

    monkeypatch.setattr(wh.threading, "Thread", Thread)
    monkeypatch.setattr(wh, "_notify_job", lambda _job, text: notices.append(text))
    monkeypatch.setattr(wh, "_validate_diagnostics_request", lambda _request: None)
    monkeypatch.setattr(wh, "_run_cluster_diagnostics", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_run_make_target", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_run_upgrade_thread_job", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_MAKE_JOB_LOCK", threading.Lock())
    monkeypatch.setattr(wh, "_role_allows", lambda actual, required: (
        actual == "admin" or required == "reader"
    ))
    return started, notices


@pytest.mark.parametrize(
    ("command", "role"),
    [
        ("cluster-diagnose hub pods monitoring", "reader"),
        ("k3dm test-all", "admin"),
        ("argocd-upgrade 7.9.1 acg", "admin"),
    ],
)
def test_successful_new_commands_ack_once_without_unknown(dispatch_env, command, role):
    started, notices = dispatch_env

    wh._handle_thread_command("job", command, role, "C1")

    assert len(started) == 1
    assert sum("queued" in notice for notice in notices) == 1
    assert not any("Unknown command" in notice for notice in notices)


def test_slack_make_job_records_target_for_make_log_selection(dispatch_env):
    _started, notices = dispatch_env

    wh._handle_thread_command("job", "k3dm test-all", "admin", "C1")

    queued = [path for path in wh.JOB_DIR.iterdir() if path.name != "job"]
    assert len(queued) == 1
    assert (queued[0] / "target").read_text() == "test-all"
    assert notices == [f"🛠️ *make test-all* queued — job `{queued[0].name}`"]


def test_e2e_replay_is_acknowledged_before_stub_worker_starts(dispatch_env, monkeypatch):
    started, notices = dispatch_env
    (wh.JOB_DIR / "job" / "thread_ts").write_text("THREAD")
    order = []
    monkeypatch.setattr(wh, "_notify_job", lambda _job, text: order.append(("notice", text)) or True)

    class OrderedThread:
        def __init__(self, *, target, args=(), kwargs=None, daemon=None):
            self.args = args

        def start(self):
            order.append(("worker", self.args[0]))

    monkeypatch.setattr(wh.threading, "Thread", OrderedThread)
    monkeypatch.setattr(wh, "_role_allows", lambda _actual, _required: True)
    wh._handle_thread_command("job", "k3dm e2e-replay RUNNER=m2", "operator", "C1", "U1")

    assert order[0][0] == "notice"
    assert "e2e-replay" in order[0][1] and "queued" in order[0][1]
    assert order[1][0] == "worker"
    assert (wh.JOB_DIR / order[1][1] / "target").read_text() == "e2e-replay"


@pytest.mark.parametrize("command", ["k3dm e2e-replay", "k3dm e2e-replay RUNNER=bad_value"])
def test_e2e_replay_invalid_request_gets_explanation_without_worker(dispatch_env, command, monkeypatch):
    started, notices = dispatch_env
    monkeypatch.setattr(wh, "_role_allows", lambda actual, required: actual == "admin" or (actual == "operator" and required in {"operator", "reader"}))
    wh._handle_thread_command("job", command, "operator", "C1")
    assert started == []
    assert len(notices) == 1
    assert "requires RUNNER" in notices[0] or "invalid value for RUNNER" in notices[0]


def test_direct_make_route_uses_job_id_in_thread_notice_and_response(
    monkeypatch, tmp_path
):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "test-token")
    monkeypatch.setattr(wh, "_MAKE_JOB_LOCK", threading.Lock())
    monkeypatch.setattr(wh, "_rate_limited", lambda _key: False)
    monkeypatch.setattr(wh, "_request_role", lambda _headers, _token_role: "admin")
    monkeypatch.setattr(wh, "_request_actor", lambda _headers: "slack:test")
    monkeypatch.setattr(wh, "_request_source_command", lambda _headers: "make")
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_start_bot_thread", lambda text, channel_id="": notices.append(text) or "THREAD")
    started = []
    notices = []
    response = {}

    class Thread:
        def __init__(self, *, target, args=(), kwargs=None, daemon=None):
            started.append((target, args, kwargs))

        def start(self):
            return None

    monkeypatch.setattr(wh.threading, "Thread", Thread)
    body = json.dumps({"target": "test-all", "channel_id": "C1"}).encode()
    fake = type("FakeHandler", (), {
        "path": "/api/v1/make",
        "headers": {"Content-Length": str(len(body))},
        "rfile": io.BytesIO(body),
        "_auth": lambda self: True,
        "send_response": lambda self, code: None,
        "send_header": lambda self, key, value: None,
        "end_headers": lambda self: None,
        "_json": lambda self, code, payload: response.update(code=code, payload=payload),
    })()

    wh._Handler.do_POST(fake)

    job_id = response["payload"]["job_id"]
    assert response["code"] == 202
    assert notices == [f"🛠️ *make test-all* queued — job `{job_id}`"]
    assert (tmp_path / job_id / "status").read_text() == "queued"
    assert (tmp_path / job_id / "target").read_text() == "test-all"
    assert started[0][0] is wh._run_make_target
    assert started[0][1][0] == job_id


def test_notification_failure_logs_safe_reason_code(monkeypatch, tmp_path, caplog):
    import logging

    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "")
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", "")
    (tmp_path / "job").mkdir()

    with caplog.at_level(logging.WARNING, logger="webhook"):
        delivered = wh._notify_job("job", "private command payload")

    assert delivered is False
    assert "reason=not_delivered" in caplog.text
    assert "private command payload" not in caplog.text


def test_kill_still_dispatches(dispatch_env, monkeypatch):
    _started, notices = dispatch_env
    monkeypatch.setattr(wh, "_running_procs", {"job": 123})
    monkeypatch.setattr(wh.os, "killpg", lambda *args: None)

    wh._handle_thread_command("job", "kill", "admin", "C1")

    assert len(notices) == 1
    assert "Kill requested" in notices[0]


def test_status_still_replies(dispatch_env):
    _started, notices = dispatch_env

    wh._handle_thread_command("job", "status", "reader", "C1")

    assert len(notices) == 1
    assert "status" in notices[0]


def test_unknown_word_still_gets_unknown_reply(dispatch_env):
    _started, notices = dispatch_env

    wh._handle_thread_command("job", "/unknown-word", "reader", "C1")

    assert len(notices) == 1
    assert "Unknown command" in notices[0]


def test_reader_e2e_replay_is_denied_without_worker(dispatch_env):
    started, notices = dispatch_env

    wh._handle_thread_command("job", "k3dm e2e-replay RUNNER=m2", "reader", "C1")

    assert started == []
    assert len(notices) == 1
    assert "requires role *operator*" in notices[0]  # agent-audit: allow assert-removed replay target is operator-scoped


def test_logs_explicit_id_reads_requested_child(dispatch_env):
    _started, notices = dispatch_env
    (wh.JOB_DIR / "job" / "thread_ts").write_text("THREAD")
    child = wh.JOB_DIR / "aabbccdd"
    child.mkdir()
    (child / "thread_ts").write_text("THREAD")
    (child / "target").write_text("test-all")
    (child / "make.log").write_text("child output")

    wh._handle_thread_command("job", "logs aabbccdd", "reader", "C1")

    assert len(notices) == 1
    assert "job `aabbccdd`" in notices[0]
    assert "child output" in notices[0]


def test_logs_rejects_cross_thread_explicit_id(dispatch_env):
    _started, notices = dispatch_env
    (wh.JOB_DIR / "job" / "thread_ts").write_text("THREAD-A")
    child = wh.JOB_DIR / "aabbccdd"
    child.mkdir()
    (child / "thread_ts").write_text("THREAD-B")
    (child / "make.log").write_text("secret child output")

    wh._handle_thread_command("job", "logs aabbccdd", "reader", "C1")

    assert len(notices) == 1
    assert "not in this Slack thread" in notices[0]
    assert "secret child output" not in notices[0]


def test_bare_logs_prefers_newest_non_anchor_job(dispatch_env):
    _started, notices = dispatch_env
    (wh.JOB_DIR / "job" / "thread_ts").write_text("THREAD")
    (wh.JOB_DIR / "job" / "status").write_text("thread-anchor")
    child = wh.JOB_DIR / "aabbccdd"
    child.mkdir()
    (child / "thread_ts").write_text("THREAD")
    (child / "status").write_text("running")
    (child / "target").write_text("test-all")
    (child / "make.log").write_text("newest child output")

    wh._handle_thread_command("job", "logs", "reader", "C1")

    assert len(notices) == 1
    assert "job `aabbccdd`" in notices[0]
    assert "newest child output" in notices[0]
