import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_ask_docs_thread", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_ask_docs_thread", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


class _ImmediateThread:
    def __init__(self, *, target, args=(), kwargs=None, daemon=None):
        self.target = target
        self.args = args
        self.kwargs = kwargs or {}

    def start(self):
        self.target(*self.args, **self.kwargs)


@pytest.fixture
def thread_job(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C1")
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    parent = tmp_path / "parent"
    parent.mkdir()
    (parent / "thread_ts").write_text("T")
    (parent / "channel_id").write_text("C1")
    (parent / "thread_source").write_text("bot")
    (parent / "response_url").write_text("https://example.invalid/response")
    return parent


def test_ask_docs_thread_runs_without_channel_and_replies_in_parent_thread(
    monkeypatch, thread_job, capsys, caplog
):
    calls = []
    bot_calls = []
    monkeypatch.setattr(wh.ask_docs, "answer", lambda question, summarise: calls.append((question, summarise)) or "doc answer")
    monkeypatch.setattr(wh, "_start_bot_thread", lambda header: calls.append(("header", header)) or "NEW")
    monkeypatch.setattr(
        wh,
        "_post_slack_bot",
        lambda text, thread_ts=None, channel_id=None: calls.append((text, thread_ts, channel_id))
        or bot_calls.append((text, thread_ts, channel_id))
        or "reply",
    )

    wh._handle_thread_command("parent", "ask-docs what is X", role="reader")

    subjobs = [p for p in thread_job.parent.iterdir() if p.name != "parent"]
    assert len(subjobs) == 1
    assert (subjobs[0] / "action").read_text() == "ask-docs"
    assert (subjobs[0] / "thread_ts").read_text() == "T"
    assert (subjobs[0] / "channel_id").read_text() == "C1"
    assert (subjobs[0] / "thread_source").read_text() == "bot"
    assert (subjobs[0] / "response_url").read_text() == "https://example.invalid/response"
    assert calls[0] == ("what is X", True)
    assert ("doc answer", "T", "C1") in calls
    assert ("doc answer", "T", "C1") in bot_calls  # agent-audit: allow assert-removed answer now carries the parent channel by design
    assert "what is X" not in capsys.readouterr().out
    assert "what is X" not in caplog.text


def test_ask_docs_thread_without_parent_route_is_not_sent_to_default_channel(
    monkeypatch, thread_job, caplog
):
    parent = thread_job
    (parent / "channel_id").unlink()
    (parent / "thread_source").unlink()
    (parent / "response_url").unlink()
    monkeypatch.setattr(wh.ask_docs, "answer", lambda question, summarise: "doc answer")
    bot_calls = []
    monkeypatch.setattr(
        wh, "_post_slack_bot",
        lambda text, thread_ts=None, channel_id=None: bot_calls.append((text, thread_ts, channel_id)) or "unexpected",
    )

    wh._handle_thread_command("parent", "ask-docs what is X", role="reader")

    subjobs = [p for p in parent.parent.iterdir() if p.name != "parent"]
    assert len(subjobs) == 1
    assert not (subjobs[0] / "channel_id").exists()
    assert not bot_calls
    assert "route=none channel=missing thread_ts=T reason=not_delivered" in caplog.text
    delivery = json.loads((subjobs[0] / "delivery.jsonl").read_text().splitlines()[-1])
    assert delivery["route"] == "none"
    assert delivery["delivered"] is False


def test_ask_docs_sources_preserves_flag_and_usage_has_no_subjob(monkeypatch, thread_job):
    started = []
    notices = []
    monkeypatch.setattr(wh, "_run_ask_docs", lambda *args, **kwargs: started.append((args, kwargs)))
    monkeypatch.setattr(wh, "_notify_job", lambda job_id, text: notices.append((job_id, text)))

    wh._handle_thread_command("parent", "ask-docs --sources what is X", role="reader")
    assert started[0][0][1:] == ("--sources what is X", "", "T")
    assert started[0][1] == {"channel_id": ""}

    subjob_count = len([p for p in thread_job.parent.iterdir() if p.name != "parent"])
    wh._handle_thread_command("parent", "ask-docs --sources", role="reader")
    wh._handle_thread_command("parent", "ask-docs", role="reader")
    assert len([p for p in thread_job.parent.iterdir() if p.name != "parent"]) == subjob_count
    assert notices[-2:] == [
        ("parent", "Usage: `ask-docs [--sources] <question>`"),
        ("parent", "Usage: `ask-docs [--sources] <question>`"),
    ]


def test_slash_ask_docs_is_not_unknown_and_sanitizes(monkeypatch, thread_job):
    started = []
    monkeypatch.setattr(wh, "_run_ask_docs", lambda *args, **kwargs: started.append((args, kwargs)))
    monkeypatch.setattr(wh, "_notify_job", lambda *_args: None)

    wh._handle_thread_command("parent", "/ask-docs what is X", role="reader")

    assert started[0][0][1] == "what is X"


def test_find_job_by_thread_ts_skips_ask_docs_subjob(monkeypatch, thread_job):
    subjob = thread_job.parent / "subjob"
    subjob.mkdir()
    (subjob / "action").write_text("ask-docs")
    (subjob / "thread_ts").write_text("T")
    assert wh._find_job_by_thread_ts("T") == "parent"


def test_ask_docs_role_is_reader_and_reader_is_allowed():
    assert wh._thread_command_min_role("ask-docs") == "reader"
    assert wh._role_allows("reader", wh._thread_command_min_role("ask-docs"))
