"""Regressions for threads started by default-channel notification fallback."""

from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "tests" / "bin"))
from test_webhook_notify_route import (  # noqa: E402
    _DEFAULT_CHANNEL,
    _WEBHOOK_URL,
    _post,
    _read_delivery,
    _setup_webhook,
    wh,
)


@pytest.mark.parametrize(("path", "body"), [
    ("/api/v1/make", {"target": "test-all"}),
    ("/api/v1/cluster", {"action": "up", "provider": "aws"}),
])
def test_U_N1_second_notice_delivered(monkeypatch, tmp_path, path, body):
    ctx = _setup_webhook(monkeypatch, tmp_path, fixed_job_id="aaaaaaaa-bbbb")
    status, payload = _post(path, body)
    assert status == 202
    job_id = payload["job_id"]
    job_dir = tmp_path / job_id

    assert wh._notify_job(job_id, "started") is True
    thread_ts = (job_dir / "thread_ts").read_text()
    second_delivered = wh._notify_job(job_id, "finished")

    records = _read_delivery(job_dir)
    assert [record["route"] for record in records] == ["bot_fallback", "bot_thread"]
    assert [record["delivered"] for record in records] == [True, True]
    assert second_delivered is True
    assert [body.get("thread_ts") for _, body in ctx["http_calls"]] == [None, thread_ts]
    assert all(body["channel"] == _DEFAULT_CHANNEL for _, body in ctx["http_calls"])
    assert (job_dir / "channel_id").read_text() == _DEFAULT_CHANNEL


def test_U_N2_slack_thread_unknown_channel_not_posted(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path)
    job_dir = tmp_path / "slack-origin"
    job_dir.mkdir()
    (job_dir / "thread_ts").write_text("1700000000.000001")

    assert wh._notify_job("slack-origin", "reply") is False
    assert ctx["http_calls"] == []
    record = _read_delivery(job_dir)[0]
    assert record["route"] == "none"
    assert record["delivered"] is False


@pytest.mark.parametrize("webhook_url", ["", _WEBHOOK_URL])
def test_U_N3_failed_first_post_writes_no_channel_id(monkeypatch, tmp_path, webhook_url):
    ctx = _setup_webhook(
        monkeypatch,
        tmp_path,
        post_message_replies=lambda _payload: {"ok": False, "error": "rejected"},
    )
    monkeypatch.setattr(wh, "SLACK_WEBHOOK_URL", webhook_url)
    job_dir = tmp_path / "failed"
    job_dir.mkdir()

    assert wh._notify_job("failed", "started") is (webhook_url != "")
    assert not (job_dir / "channel_id").exists()
    record = _read_delivery(job_dir)[0]
    assert record["delivered"] is (webhook_url != "")
    if webhook_url:
        assert record["route"] == "webhook_fallback"
    assert ctx["http_calls"]


def test_U_N3_exception_writes_no_channel_id(monkeypatch, tmp_path):
    _setup_webhook(monkeypatch, tmp_path)
    job_dir = tmp_path / "exception"
    job_dir.mkdir()
    def raise_error(*_args, **_kwargs):
        raise RuntimeError("boom")
    monkeypatch.setattr(wh, "_post_slack_bot", raise_error)

    assert wh._notify_job("exception", "started") is False
    assert not (job_dir / "channel_id").exists()
    assert _read_delivery(job_dir)[0]["delivered"] is False


def test_U_N4_existing_channel_not_overwritten(monkeypatch, tmp_path):
    _setup_webhook(monkeypatch, tmp_path)
    job_dir = tmp_path / "routed"
    job_dir.mkdir()
    (job_dir / "channel_id").write_text("COWNCHANNEL")
    calls = []
    def post(_text, *, thread_ts=None, channel_id=None):
        calls.append((channel_id, thread_ts))
        return None if len(calls) == 1 else "1700000001.000001"
    monkeypatch.setattr(wh, "_post_slack_bot", post)

    assert wh._notify_job("routed", "started") is True
    assert (job_dir / "channel_id").read_text() == "COWNCHANNEL"
    assert calls == [("COWNCHANNEL", None), ("COWNCHANNEL", None)]


def test_U_N3_webhook_delivery_does_not_write_channel_id(monkeypatch, tmp_path):
    ctx = _setup_webhook(monkeypatch, tmp_path)
    job_dir = tmp_path / "webhook"
    job_dir.mkdir()
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "")

    assert wh._notify_job("webhook", "started") is True
    assert not (job_dir / "channel_id").exists()
    assert ctx["http_calls"][-1][0] == _WEBHOOK_URL
    assert _read_delivery(job_dir)[0]["route"] == "webhook_fallback"
