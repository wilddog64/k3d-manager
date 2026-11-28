"""Offline tests for webhook notification route resolution, persistence, and no-spill."""

import base64
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
from pathlib import Path
import sys
import threading
import types

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from webhook import lifecycle, notify_routes, render  # noqa: E402

_WEBHOOK = REPO_ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_notify_route",
    _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_notify_route", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)

_DEFAULT_CHANNEL = "CDEFAULT1"
_WEBHOOK_URL = "https://hooks.slack.com/services/T00000000/B00000000/testwebhook"

# Captured via P-SLACK probe on m4-air.local at 2026-11-26T21:34:25+00:00:
# chat.postMessage to nonexistent channel C0000000000 reply:
# {"error": "channel_not_found", "ok": false}
_P_SLACK_CHANNEL_NOT_FOUND = {"error": "channel_not_found", "ok": False}

# Golden baselines for unrouted requests (captured on base commit 496479d7):
_GOLDEN_UNROUTED_MAKE = {
    "status": 202,
    "response": {"job_id": "11111111", "status": "queued"},
    "job_files": {"status": "queued", "target": "test-all"},
    "post_http_calls": [],
    "notify_payload": {"channel": _DEFAULT_CHANNEL, "text": "unrouted make notice"},
    "delivery_route": "bot_fallback",
}
_GOLDEN_UNROUTED_CLUSTER_UP = {
    "status": 202,
    "response": {"job_id": "22222222", "status": "queued"},
    "job_files": {"status": "running", "action": "up"},
    "post_http_calls": [],
    "notify_payload": {"channel": _DEFAULT_CHANNEL, "text": "unrouted cluster notice"},
    "delivery_route": "bot_fallback",
}


class _FakeHTTPResponse:
    def __init__(self, body_bytes):
        self._body = body_bytes

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        return False


class _ThreadStub:
    def __init__(self, sink, **kwargs):
        self.kwargs = kwargs
        sink.append(kwargs)

    def start(self):
        pass


def _setup_webhook(monkeypatch, tmp_path, *, routes=None, routes_status="ok",
                   post_message_replies=None, fixed_job_id=None):
    """Isolate webhook state under tmp_path and stub Slack HTTP + route loading."""
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(lifecycle, "JOB_DIR", tmp_path)
    assert wh.JOB_DIR == tmp_path
    assert lifecycle.JOB_DIR == tmp_path

    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test-token")
    monkeypatch.setattr(render, "SLACK_BOT_TOKEN", "xoxb-test-token")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", _DEFAULT_CHANNEL)
    monkeypatch.setattr(render, "SLACK_CHANNEL_ID", _DEFAULT_CHANNEL)
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", _WEBHOOK_URL)

    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(wh, "_running_cluster_job", lambda: None)

    make_lock = threading.Lock()
    monkeypatch.setattr(wh, "_MAKE_JOB_LOCK", make_lock)
    monkeypatch.setitem(lifecycle._helpers, "make_job_lock", make_lock)

    if fixed_job_id is not None:
        monkeypatch.setattr(wh.uuid, "uuid4", lambda: fixed_job_id)

    load_calls = []
    route_state = {"map": {} if routes is None else dict(routes), "status": routes_status}

    def _fake_load_routes():
        load_calls.append(True)
        return dict(route_state["map"]), route_state["status"]

    monkeypatch.setattr(notify_routes, "load_routes", _fake_load_routes)

    http_calls = []
    ts_counter = [0]

    def _fake_urlopen(req, timeout=10):
        payload = json.loads(req.data.decode("utf-8"))
        http_calls.append((req.full_url, payload))
        if req.full_url == "https://slack.com/api/chat.postMessage":
            if post_message_replies is not None:
                reply = post_message_replies(payload)
            else:
                ts_counter[0] += 1
                reply = {"ok": True, "ts": f"170000000{ts_counter[0]}.000001"}
            return _FakeHTTPResponse(json.dumps(reply).encode("utf-8"))
        return _FakeHTTPResponse(b"ok")

    monkeypatch.setattr(render.urllib.request, "urlopen", _fake_urlopen)

    threads = []
    monkeypatch.setattr(
        wh,
        "threading",
        types.SimpleNamespace(
            Thread=lambda **kwargs: _ThreadStub(threads, **kwargs),
            Lock=threading.Lock,
        ),
    )

    return {
        "http_calls": http_calls,
        "load_calls": load_calls,
        "route_state": route_state,
        "threads": threads,
        "make_lock": make_lock,
    }


def _post(path, body, *, role="admin"):
    encoded = json.dumps(body).encode("utf-8")
    handler = object.__new__(wh._Handler)
    handler.path = path
    handler.headers = {"Content-Length": str(len(encoded))}
    handler.rfile = io.BytesIO(encoded)
    responses = []
    handler._auth = lambda: True
    handler._token_role = role
    handler._json = lambda status, payload: responses.append((status, payload))
    handler.do_POST()
    assert len(responses) == 1
    return responses[0]


def _read_delivery(job_dir):
    return [json.loads(line) for line in (job_dir / "delivery.jsonl").read_text(encoding="utf-8").splitlines()]


def test_BM1_make_with_notify_route_persists_and_posts_in_one_thread(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    status, payload = _post("/api/v1/make", {"target": "test-all", "notify_route": "ci"})

    assert status == 202
    job_id = payload["job_id"]
    job_dir = tmp_path / job_id
    assert (job_dir / "notify_route").read_text() == "ci"
    assert (job_dir / "channel_id").read_text() == "C99999999"
    assert (job_dir / "thread_ts").read_text() == "1700000001.000001"
    assert (job_dir / "thread_source").read_text() == "bot"
    assert len(ctx["load_calls"]) == 1

    assert len(ctx["http_calls"]) == 1
    assert ctx["http_calls"][0][0] == "https://slack.com/api/chat.postMessage"
    assert ctx["http_calls"][0][1]["channel"] == "C99999999"
    assert "thread_ts" not in ctx["http_calls"][0][1]

    assert wh._notify_job(job_id, "started") is True
    assert wh._notify_job(job_id, "finished") is True

    assert len(ctx["http_calls"]) == 3
    for url, body in ctx["http_calls"][1:]:
        assert url == "https://slack.com/api/chat.postMessage"
        assert body["channel"] == "C99999999"
        assert body["thread_ts"] == "1700000001.000001"
    assert all(url != _WEBHOOK_URL for url, _ in ctx["http_calls"])
    assert all(body.get("channel") != _DEFAULT_CHANNEL for _, body in ctx["http_calls"])

    records = _read_delivery(job_dir)
    assert len(records) == 2
    assert all(rec["notify_route"] == "ci" for rec in records)
    assert all(rec["route"] == "bot_thread" for rec in records)
    assert all(rec["delivered"] is True for rec in records)


@pytest.mark.parametrize("action", ["up", "down"])
def test_BM1_cluster_up_down_with_notify_route_persists_and_posts_in_one_thread(monkeypatch, tmp_path, action):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"sandbox": "C88888888"})
    status, payload = _post("/api/v1/cluster", {"action": action, "provider": "aws", "notify_route": "sandbox"})

    assert status == 202
    job_id = payload["job_id"]
    job_dir = tmp_path / job_id
    assert (job_dir / "notify_route").read_text() == "sandbox"
    assert (job_dir / "channel_id").read_text() == "C88888888"
    assert len(ctx["load_calls"]) == 1

    assert wh._notify_job(job_id, f"cluster-{action} started") is True
    assert wh._notify_job(job_id, f"cluster-{action} complete") is True

    assert len(ctx["http_calls"]) == 2
    first_url, first_body = ctx["http_calls"][0]
    second_url, second_body = ctx["http_calls"][1]
    assert first_url == "https://slack.com/api/chat.postMessage"
    assert first_body["channel"] == "C88888888"
    assert "thread_ts" not in first_body
    assert second_url == "https://slack.com/api/chat.postMessage"
    assert second_body["channel"] == "C88888888"
    assert second_body["thread_ts"] == "1700000001.000001"
    assert (job_dir / "thread_ts").read_text() == "1700000001.000001"

    records = _read_delivery(job_dir)
    assert len(records) == 2
    assert all(rec["notify_route"] == "sandbox" for rec in records)
    assert all(rec["delivered"] is True for rec in records)


def test_BM2_unrouted_make_and_cluster_match_golden_baseline(monkeypatch, tmp_path):
    make_ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"}, fixed_job_id="11111111-aaaa")
    make_status, make_resp = _post("/api/v1/make", {"target": "test-all"})
    assert make_status == _GOLDEN_UNROUTED_MAKE["status"]
    assert make_resp == _GOLDEN_UNROUTED_MAKE["response"]
    assert make_ctx["load_calls"] == []
    assert make_ctx["http_calls"] == _GOLDEN_UNROUTED_MAKE["post_http_calls"]

    make_dir = tmp_path / "11111111"
    make_files = {p.name: p.read_text() for p in make_dir.iterdir()}
    assert make_files == _GOLDEN_UNROUTED_MAKE["job_files"]

    assert wh._notify_job("11111111", "unrouted make notice") is True
    assert make_ctx["http_calls"] == [
        ("https://slack.com/api/chat.postMessage", _GOLDEN_UNROUTED_MAKE["notify_payload"]),
    ]
    make_delivery = _read_delivery(make_dir)[-1]
    assert make_delivery["route"] == _GOLDEN_UNROUTED_MAKE["delivery_route"]
    assert make_delivery["delivered"] is True
    assert make_delivery["channel_id"] is None

    cluster_ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"}, fixed_job_id="22222222-bbbb")
    cluster_status, cluster_resp = _post("/api/v1/cluster", {"action": "up", "provider": "aws"})
    assert cluster_status == _GOLDEN_UNROUTED_CLUSTER_UP["status"]
    assert cluster_resp == _GOLDEN_UNROUTED_CLUSTER_UP["response"]
    assert cluster_ctx["load_calls"] == []
    assert cluster_ctx["http_calls"] == _GOLDEN_UNROUTED_CLUSTER_UP["post_http_calls"]

    cluster_dir = tmp_path / "22222222"
    cluster_files = {p.name: p.read_text() for p in cluster_dir.iterdir()}
    assert cluster_files == _GOLDEN_UNROUTED_CLUSTER_UP["job_files"]

    assert wh._notify_job("22222222", "unrouted cluster notice") is True
    assert cluster_ctx["http_calls"] == [
        ("https://slack.com/api/chat.postMessage", _GOLDEN_UNROUTED_CLUSTER_UP["notify_payload"]),
    ]
    cluster_delivery = _read_delivery(cluster_dir)[-1]
    assert cluster_delivery["route"] == _GOLDEN_UNROUTED_CLUSTER_UP["delivery_route"]
    assert cluster_delivery["delivered"] is True
    assert cluster_delivery["channel_id"] is None


def test_BM3_map_change_after_creation_does_not_move_later_or_orphan_messages(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C11111111"})
    status, payload = _post("/api/v1/cluster", {"action": "up", "provider": "aws", "notify_route": "ci"})
    assert status == 202
    job_id = payload["job_id"]

    assert wh._notify_job(job_id, "first message") is True
    assert ctx["http_calls"][-1][1]["channel"] == "C11111111"

    # Change the map to point the alias at a different channel, then remove it altogether.
    ctx["route_state"]["map"] = {"ci": "C22222222"}
    assert wh._notify_job(job_id, "second message after remap") is True
    assert ctx["http_calls"][-1][1]["channel"] == "C11111111"
    assert ctx["http_calls"][-1][1]["thread_ts"] == "1700000001.000001"

    ctx["route_state"]["map"] = {}
    ctx["route_state"]["status"] = "absent"
    wh._clear_stale_jobs()
    assert ctx["http_calls"][-1][1]["channel"] == "C11111111"
    assert ctx["http_calls"][-1][1]["thread_ts"] == "1700000001.000001"
    assert "orphaned" in ctx["http_calls"][-1][1]["text"]
    assert all(body.get("channel") == "C11111111" for _, body in ctx["http_calls"])


def test_BM4_delivery_jsonl_records_notify_route_key_for_routed_and_unrouted(monkeypatch, tmp_path):
    _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    routed_dir = tmp_path / "aaaa0001"
    routed_dir.mkdir()
    (routed_dir / "channel_id").write_text("C99999999")
    (routed_dir / "notify_route").write_text("ci")
    assert wh._notify_job("aaaa0001", "routed ok") is True
    routed_rec = _read_delivery(routed_dir)[-1]
    assert routed_rec["notify_route"] == "ci"
    assert routed_rec["route"] == "bot_thread"
    assert routed_rec["delivered"] is True

    unrouted_dir = tmp_path / "aaaa0002"
    unrouted_dir.mkdir()
    assert wh._notify_job("aaaa0002", "unrouted ok") is True
    unrouted_rec = _read_delivery(unrouted_dir)[-1]
    assert "notify_route" in unrouted_rec
    assert unrouted_rec["notify_route"] is None
    assert unrouted_rec["route"] == "bot_fallback"
    assert unrouted_rec["delivered"] is True


def test_BN1_routed_job_all_posts_fail_never_spills_to_webhook_or_default(monkeypatch, tmp_path):
    ctx = _setup_webhook(
        monkeypatch,
        tmp_path,
        routes={"ci": "C0000000000"},
        post_message_replies=lambda _payload: _P_SLACK_CHANNEL_NOT_FOUND,
    )
    job_dir = tmp_path / "deadbeef"
    job_dir.mkdir()
    (job_dir / "channel_id").write_text("C0000000000")
    (job_dir / "notify_route").write_text("ci")

    assert wh._notify_job("deadbeef", "routed failure notice") is False

    assert len(ctx["http_calls"]) >= 1
    assert all(url == "https://slack.com/api/chat.postMessage" for url, _ in ctx["http_calls"])
    assert all(url != _WEBHOOK_URL for url, _ in ctx["http_calls"])
    assert all(body["channel"] == "C0000000000" for _, body in ctx["http_calls"])
    assert all(body["channel"] != _DEFAULT_CHANNEL for _, body in ctx["http_calls"])

    records = _read_delivery(job_dir)
    assert len(records) == 1
    assert records[0]["notify_route"] == "ci"
    assert records[0]["delivered"] is False
    assert records[0]["channel_id"] == "C0000000000"
    assert records[0]["route"] == "bot_fallback"


def test_BN1_routed_job_missing_channel_id_never_falls_back_to_default_or_webhook(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C0000000000"})
    job_dir = tmp_path / "deadb000"
    job_dir.mkdir()
    (job_dir / "notify_route").write_text("ci")

    assert wh._notify_job("deadb000", "routed without channel") is False
    assert ctx["http_calls"] == []
    records = _read_delivery(job_dir)
    assert records[0]["notify_route"] == "ci"
    assert records[0]["delivered"] is False


def test_BN1_control_unrouted_job_all_posts_fail_still_falls_back_to_webhook(monkeypatch, tmp_path):
    ctx = _setup_webhook(
        monkeypatch,
        tmp_path,
        routes={"ci": "C0000000000"},
        post_message_replies=lambda _payload: _P_SLACK_CHANNEL_NOT_FOUND,
    )
    job_dir = tmp_path / "cafebabe"
    job_dir.mkdir()
    (job_dir / "channel_id").write_text("C0000000000")

    assert wh._notify_job("cafebabe", "unrouted failure notice") is True
    assert any(url == _WEBHOOK_URL for url, _ in ctx["http_calls"])
    records = _read_delivery(job_dir)
    assert records[-1]["route"] == "webhook_fallback"
    assert records[-1]["delivered"] is True


@pytest.mark.parametrize("endpoint,base_body", [
    ("/api/v1/make", {"target": "test-all"}),
    ("/api/v1/cluster", {"action": "up", "provider": "aws"}),
    ("/api/v1/cluster", {"action": "down", "provider": "aws"}),
])
@pytest.mark.parametrize("field,value", [
    ("channel_id", "C12345678"),
    ("response_url", "https://hooks.slack.com/commands/T1/B1/resp"),
    ("thread_ts", "1700000000.000001"),
])
def test_BN2_rejects_notify_route_combined_with_slack_context(monkeypatch, tmp_path, endpoint, base_body, field, value):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    body = {**base_body, "notify_route": "ci", field: value}
    status, payload = _post(endpoint, body)

    assert status == 400
    assert payload == {"error": "notify_route cannot be combined with Slack context"}
    assert list(tmp_path.iterdir()) == []
    assert ctx["threads"] == []
    assert ctx["http_calls"] == []
    assert not ctx["make_lock"].locked()


@pytest.mark.parametrize("body", [
    {"action": "kill", "job_id": "deadbeef", "notify_route": "ci"},
    {"action": "trust-vault-ca", "notify_route": "ci"},
    {"action": "resume", "notify_route": "ci"},
    {"action": "status", "notify_route": "ci"},
    {"notify_route": "ci"},
])
def test_BN2_rejects_notify_route_on_unsupported_cluster_actions(monkeypatch, tmp_path, body):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    status, payload = _post("/api/v1/cluster", body)

    assert status == 400
    assert payload == {"error": notify_routes.UNSUPPORTED_REASON}
    assert list(tmp_path.iterdir()) == []
    assert ctx["threads"] == []


@pytest.mark.parametrize("endpoint,base_body", [
    ("/api/v1/cluster-status", {"provider": "hostinger"}),
    ("/api/v1/diagnostics", {"provider": "hostinger", "action": "get-pods-all"}),
    ("/api/v1/hostinger-status", {}),
])
def test_BN2_rejects_notify_route_on_status_and_diagnostics_endpoints(monkeypatch, tmp_path, endpoint, base_body):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    status, payload = _post(endpoint, {**base_body, "notify_route": "ci"})

    assert status == 400
    assert payload == {"error": notify_routes.UNSUPPORTED_REASON}
    assert list(tmp_path.iterdir()) == []
    assert ctx["threads"] == []


@pytest.mark.parametrize("endpoint,base_body", [
    ("/api/v1/cluster-status", {"provider": "hostinger"}),
    ("/api/v1/diagnostics", {"provider": "hostinger", "action": "get-pods-all"}),
    ("/api/v1/hostinger-status", {}),
])
def test_BN2_control_status_and_diagnostics_without_notify_route_accepted(monkeypatch, tmp_path, endpoint, base_body):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    status, payload = _post(endpoint, base_body)

    assert status == 202
    assert "job_id" in payload
    assert len(ctx["threads"]) == 1


@pytest.mark.parametrize("endpoint,base_body", [
    ("/api/v1/make", {"target": "test-all"}),
    ("/api/v1/cluster", {"action": "up", "provider": "aws"}),
])
@pytest.mark.parametrize("alias,routes,routes_status", [
    ("BAD_ALIAS", {"secretalias": "C77777777"}, "ok"),
    ("", {"secretalias": "C77777777"}, "ok"),
    ("1bad", {"secretalias": "C77777777"}, "ok"),
    ("bad space", {"secretalias": "C77777777"}, "ok"),
    (None, {"secretalias": "C77777777"}, "ok"),
    (123, {"secretalias": "C77777777"}, "ok"),
    ("unknownalias", {"secretalias": "C77777777"}, "ok"),
    ("default", {"secretalias": "C77777777"}, "ok"),
    ("ci", {}, "absent"),
    ("ci", {}, "invalid"),
])
def test_BN3_rejects_invalid_unknown_absent_or_corrupt_route_without_disclosure(
    monkeypatch, tmp_path, endpoint, base_body, alias, routes, routes_status,
):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes=routes, routes_status=routes_status)
    status, payload = _post(endpoint, {**base_body, "notify_route": alias})

    assert status == 400
    assert payload == {"error": notify_routes.INVALID_REASON}
    serialized = json.dumps(payload)
    for forbidden in ("secretalias", "C77777777", "unknownalias", "BAD_ALIAS", _DEFAULT_CHANNEL):
        assert forbidden not in serialized
    assert list(tmp_path.iterdir()) == []
    assert ctx["threads"] == []
    assert ctx["http_calls"] == []
    assert not ctx["make_lock"].locked()


def test_BN4_routed_make_label_escapes_slack_mentions(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    job_id = "f1e2d3c4"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    (job_dir / "channel_id").write_text("C99999999")
    (job_dir / "notify_route").write_text("ci")

    posted = []
    spawned_cmds = []
    monkeypatch.setattr(lifecycle, "_notify_job", lambda jid, text: posted.append((jid, text)) or True)
    monkeypatch.setattr(lifecycle, "_spawn_job", lambda cmd, *_args, **_kwargs: spawned_cmds.append(cmd) or 424242)
    monkeypatch.setattr(os, "waitpid", lambda pid, _opts: (pid, 0))
    ctx["make_lock"].acquire()

    lifecycle._run_make_target(job_id, ["find-similar-docs", "Q=<!channel> & <@U123>"], 30, "tester")

    assert not ctx["make_lock"].locked()
    assert len(posted) == 2
    for jid, text in posted:
        assert jid == job_id
        assert "<!channel>" not in text
        assert "<@U123>" not in text
        assert "&lt;!channel&gt; &amp; &lt;@U123&gt;" in text

    expected_b64 = base64.b64encode(b"<!channel> & <@U123>").decode("ascii")
    assert spawned_cmds == [["make", "--no-print-directory", "find-similar-docs", f"Q_B64={expected_b64}"]]


def test_BN4_control_unrouted_make_label_not_escaped(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    job_id = "f1e2d3c5"
    job_dir = tmp_path / job_id
    job_dir.mkdir()

    posted = []
    monkeypatch.setattr(lifecycle, "_notify_job", lambda jid, text: posted.append((jid, text)) or True)
    monkeypatch.setattr(lifecycle, "_spawn_job", lambda *_args, **_kwargs: 424243)
    monkeypatch.setattr(os, "waitpid", lambda pid, _opts: (pid, 0))
    ctx["make_lock"].acquire()

    lifecycle._run_make_target(job_id, ["find-similar-docs", "Q=<!channel>"], 30, "tester")

    assert not ctx["make_lock"].locked()
    assert len(posted) == 2
    for jid, text in posted:
        assert jid == job_id
        assert "Q=<!channel>" in text
        assert "&lt;!channel&gt;" not in text


@pytest.mark.parametrize("text, expected", [
    ("<!channel>", "&lt;!channel&gt;"),
    ("<@U12345678>", "&lt;@U12345678&gt;"),
    ("```", "ˋˋˋ"),
    ("a&b", "a&amp;b"),
    ("plain text", "plain text"),
])
def test_escape_code_block(text, expected):
    assert notify_routes.escape_code_block(text) == expected


def test_routed_make_output_escapes_mentions_and_fences(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    job_id = "f1e2d3c6"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    (job_dir / "notify_route").write_text("ci")
    source = "``` <!channel> <@U12345678> &"
    posted = []
    timer = {}

    class DeferredTimer:
        def __init__(self, _delay, callback):
            timer["callback"] = callback

        def start(self):
            pass

        def cancel(self):
            pass

    def spawn(_cmd, log_file, **_kwargs):
        log_file.write_text(source)
        timer["callback"]()
        return 424244

    monkeypatch.setattr(threading, "Timer", DeferredTimer)
    monkeypatch.setattr(lifecycle, "_notify_job", lambda jid, text: posted.append((jid, text)) or True)
    monkeypatch.setattr(lifecycle, "_spawn_job", spawn)
    monkeypatch.setattr(os, "waitpid", lambda pid, _opts: (pid, 0))
    ctx["make_lock"].acquire()

    lifecycle._run_make_target(job_id, ["find-similar-docs", "Q=ignored"], 30, "tester")

    messages = [text for jid, text in posted if jid == job_id]
    assert len(messages) == 3
    for message in messages[1:]:
        assert "<!" not in message
        assert "<@" not in message
        assert message.count("```") == 2
        assert "ˋˋˋ &lt;!channel&gt; &lt;@U12345678&gt; &amp;" in message


def test_unrouted_make_output_remains_raw(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path, routes={"ci": "C99999999"})
    job_id = "f1e2d3c7"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    source = "``` <!channel> <@U12345678> &"
    posted = []

    def spawn(_cmd, log_file, **_kwargs):
        log_file.write_text(source)
        return 424245

    monkeypatch.setattr(lifecycle, "_notify_job", lambda jid, text: posted.append((jid, text)) or True)
    monkeypatch.setattr(lifecycle, "_spawn_job", spawn)
    monkeypatch.setattr(os, "waitpid", lambda pid, _opts: (pid, 0))
    ctx["make_lock"].acquire()

    lifecycle._run_make_target(job_id, ["find-similar-docs", "Q=ignored"], 30, "tester")

    final = posted[-1][1]
    assert final == f"✅ *make find-similar-docs Q=ignored* succeeded — job `{job_id}`\n```{source}```"
