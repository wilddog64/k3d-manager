import importlib.util
import io
import json
import logging
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_thread_broadcast", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_thread_broadcast", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.mark.parametrize(
    ("event", "expected"),
    [
        ({"type": "message", "text": "status", "subtype": ""}, True),
        ({"type": "message", "text": "status", "subtype": "thread_broadcast"}, True),
        ({"type": "message", "text": "status", "subtype": "message_changed"}, False),
        ({"type": "message", "text": "status", "subtype": "message_deleted"}, False),
        ({"type": "message", "text": "status", "subtype": "bot_message"}, False),
        ({"type": "message", "text": "status", "subtype": "channel_join"}, False),
        ({"type": "message", "text": "status", "bot_id": "B1"}, False),
        ({"type": "message", "text": "   "}, False),
        ({"type": "reaction_added", "text": "status"}, False),
    ],
)
def test_slack_message_command_candidate_truth_table(event, expected):
    assert wh._slack_message_is_command_candidate(event) is expected


class _ImmediateThread:
    def __init__(self, *, target, args=(), kwargs=None, daemon=None):
        self.target = target
        self.args = args
        self.kwargs = kwargs or {}

    def start(self):
        self.target(*self.args, **self.kwargs)


def _slack_request(event, event_id="Ev1"):
    body = json.dumps({"type": "event_callback", "event_id": event_id, "event": event}).encode()
    result = {}
    handler = type("FakeHandler", (), {
        "path": "/slack/events",
        "headers": {
            "Content-Length": str(len(body)),
            "X-Slack-Request-Timestamp": "1700000000",
            "X-Slack-Signature": "v0=test",
        },
        "rfile": io.BytesIO(body),
        "wfile": io.BytesIO(),
        "send_response": lambda self, code: result.update(code=code),
        "send_header": lambda self, key, value: None,
        "end_headers": lambda self: None,
        "_json": lambda self, code, response: result.update(code=code, response=response),
    })()
    handler.result = result
    return handler


def test_thread_broadcast_routes_known_job_thread(monkeypatch, caplog):
    calls = []
    monkeypatch.setattr(wh, "_verify_slack_signature", lambda *args: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_slack_user_is_allowlisted", lambda _user: True)
    monkeypatch.setattr(wh, "_slack_user_role", lambda _user: "admin")
    monkeypatch.setattr(wh, "_find_job_by_thread_ts", lambda thread_ts, channel_id="": "job-1")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    monkeypatch.setattr(wh, "_handle_thread_command", lambda *args, **kwargs: calls.append((args, kwargs)))

    request = _slack_request({
        "type": "message",
        "subtype": "thread_broadcast",
        "user": "U1",
        "channel": "C1",
        "thread_ts": "1700000000.000001",
        "ts": "1700000000.000002",
        "text": "cluster-status",
    })
    with caplog.at_level(logging.INFO, logger="webhook"):
        wh._Handler.do_POST(request)

    assert request.result["code"] == 200
    # agent-audit: allow assert-removed same routing assertion, now also checks user_id is passed
    assert calls == [(("job-1", "cluster-status", "admin", "C1"), {"user_id": "U1"})]
    assert "slack message ignored" not in caplog.text


def test_thread_broadcast_routes_orphan_command_to_thread_anchor(monkeypatch, tmp_path):
    calls = []
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "_verify_slack_signature", lambda *args: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_slack_user_is_allowlisted", lambda _user: True)
    monkeypatch.setattr(wh, "_slack_user_role", lambda _user: "operator")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    monkeypatch.setattr(wh, "_handle_thread_command", lambda *args, **kwargs: calls.append((args, kwargs)))

    request = _slack_request({
        "type": "message", "subtype": "", "user": "U1", "channel": "C1",
        "thread_ts": "1700000000.000010", "ts": "1700000000.000011",
        "text": "k3dm e2e-replay RUNNER=m2",
    }, event_id="Ev-orphan")
    wh._Handler.do_POST(request)

    anchors = list(tmp_path.iterdir())
    assert len(anchors) == 1
    assert (anchors[0] / "status").read_text() == "thread-anchor"
    assert (anchors[0] / "thread_ts").read_text() == "1700000000.000010"
    assert calls[0][0][1:] == ("k3dm e2e-replay RUNNER=m2", "operator", "C1")


def test_duplicate_event_id_dispatches_once(monkeypatch):
    calls = []
    monkeypatch.setattr(wh, "_seen_event_ids", __import__("collections").OrderedDict())
    monkeypatch.setattr(wh, "_verify_slack_signature", lambda *args: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_slack_user_is_allowlisted", lambda _user: True)
    monkeypatch.setattr(wh, "_slack_user_role", lambda _user: "operator")
    monkeypatch.setattr(wh, "_find_job_by_thread_ts", lambda _thread_ts, channel_id="": "job-1")
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    monkeypatch.setattr(wh, "_handle_thread_command", lambda *args, **kwargs: calls.append(args))
    event = {
        "type": "message", "subtype": "", "user": "U1", "channel": "C1",
        "thread_ts": "1700000000.000020", "ts": "1700000000.000021",
        "text": "k3dm e2e-replay RUNNER=m2",
    }

    wh._Handler.do_POST(_slack_request(event, event_id="Ev-duplicate"))
    wh._Handler.do_POST(_slack_request(event, event_id="Ev-duplicate"))

    assert len(calls) == 1


def test_top_level_help_delivers_promptly_while_make_lock_is_held(monkeypatch, tmp_path):
    posted = []
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "_seen_event_ids", __import__("collections").OrderedDict())
    monkeypatch.setattr(wh, "_verify_slack_signature", lambda *args: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_slack_user_is_allowlisted", lambda _user: True)
    monkeypatch.setattr(wh, "_slack_user_role", lambda _user: "admin")
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "bot-token")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "")
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", "")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: posted.append((text, kwargs)) or "reply-ts")
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    wh._MAKE_JOB_LOCK.acquire()
    try:
        request = _slack_request({
            "type": "message", "subtype": "", "user": "U1", "channel": "C-help",
            "ts": "1700000000.000030", "text": "k3dm help",
        }, event_id="Ev-help")
        wh._Handler.do_POST(request)
    finally:
        wh._MAKE_JOB_LOCK.release()

    assert request.result["code"] == 200
    assert len(posted) == 1
    assert "targets for role admin" in posted[0][0]
    assert posted[0][1] == {"thread_ts": "1700000000.000030", "channel_id": "C-help"}
    anchor = next(tmp_path.iterdir())
    assert (anchor / "event_id").read_text() == "Ev-help"
    delivery = json.loads((anchor / "delivery.jsonl").read_text().splitlines()[0])
    assert delivery["delivered"] is True
    assert delivery["event_id"] == "Ev-help"


def test_subtype_drop_is_logged_without_message_text(monkeypatch, caplog):
    monkeypatch.setattr(wh, "_verify_slack_signature", lambda *args: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_slack_user_is_allowlisted", lambda _user: True)
    request = _slack_request({
        "type": "message",
        "subtype": "message_changed",
        "user": "U1",
        "text": "cluster-status secret-text",
    }, event_id="Ev2")

    with caplog.at_level(logging.INFO, logger="webhook"):
        wh._Handler.do_POST(request)

    assert "slack message ignored subtype=message_changed" in caplog.text
    assert "secret-text" not in caplog.text
