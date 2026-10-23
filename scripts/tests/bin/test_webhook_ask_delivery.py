from pathlib import Path
import sys
import importlib.util
from importlib.machinery import SourceFileLoader

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from webhook import agent

_WEBHOOK = REPO_ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_ask_delivery", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_ask_delivery", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


def _run(monkeypatch, tmp_path, *, channel_id="C1", header_ts="1700000000.000001", answer_ts="1700000000.000002"):
    calls = []
    monkeypatch.setattr(agent, "JOB_DIR", Path(tmp_path))
    monkeypatch.setattr(agent, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(agent, "SLACK_CHANNEL_ID", "C1")
    monkeypatch.setattr(agent, "_call_gemini", lambda _prompt: "grounded answer")
    monkeypatch.setattr(agent, "_parse_gemini_observations", lambda text: (text, []))
    monkeypatch.setattr(agent, "_start_bot_thread", lambda header: calls.append(("header", header)) or header_ts)
    monkeypatch.setattr(agent, "_post_slack_bot", lambda text, thread_ts=None: calls.append(("bot", text, thread_ts)) or answer_ts)
    monkeypatch.setattr(agent, "_slack_post", lambda url, text: calls.append(("response", url, text)))
    job_dir = Path(tmp_path) / "deadbeef"
    job_dir.mkdir()
    agent._run_cluster_ask("deadbeef", "gemini", "Bearer synthetic0token", "https://hooks.slack.com/resp", channel_id=channel_id)
    return calls, job_dir


def test_bot_delivery_starts_and_replies_in_thread(monkeypatch, tmp_path):
    calls, job_dir = _run(monkeypatch, tmp_path)
    assert calls[0][0] == "header"
    assert calls[1] == ("bot", "🤖 *gemini:* grounded answer", "1700000000.000001")
    assert not any(call[0] == "response" for call in calls)
    assert (job_dir / "thread_ts").read_text() == "1700000000.000001"


def test_channel_mismatch_uses_response_url(monkeypatch, tmp_path):
    calls, _ = _run(monkeypatch, tmp_path, channel_id="OTHER")
    assert not any(call[0] == "header" for call in calls)
    assert calls == [("response", "https://hooks.slack.com/resp", "🤖 *gemini:* grounded answer")]


def test_header_failure_falls_back_once(monkeypatch, tmp_path):
    calls, _ = _run(monkeypatch, tmp_path, header_ts="")
    assert calls == [("header", "🤖 *ask gemini:* Bearer ***REDACTED***"),
                     ("response", "https://hooks.slack.com/resp", "🤖 *gemini:* grounded answer")]


def test_answer_failure_falls_back_once(monkeypatch, tmp_path):
    delivery, _ = _run(monkeypatch, tmp_path, answer_ts="")
    assert delivery[-1] == ("response", "https://hooks.slack.com/resp", "🤖 *gemini:* grounded answer")


def test_header_redacts_and_truncates_question(monkeypatch, tmp_path):
    captured = []
    monkeypatch.setattr(agent, "_start_bot_thread", lambda header: captured.append(header) or "ts")
    question = "Bearer synthetic0token " + "x" * 300 + " 10.1.2.3"
    job_dir = Path(tmp_path) / "deadbeef"
    job_dir.mkdir()
    monkeypatch.setattr(agent, "JOB_DIR", Path(tmp_path))
    monkeypatch.setattr(agent, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(agent, "SLACK_CHANNEL_ID", "C1")
    monkeypatch.setattr(agent, "_call_gemini", lambda _prompt: "answer")
    monkeypatch.setattr(agent, "_parse_gemini_observations", lambda text: (text, []))
    monkeypatch.setattr(agent, "_post_slack_bot", lambda *_args, **_kwargs: "reply-ts")
    agent._run_cluster_ask("deadbeef", "gemini", question, "", channel_id="C1")
    assert "synthetic0token" not in captured[0]
    assert len(captured[0].split(":* ", 1)[1]) == 200


def test_header_escapes_slack_control_sequences():
    from webhook.render import _redact_thread_question
    header = _redact_thread_question("ping <!channel> & <@U123>")
    assert "<!channel>" not in header
    assert "<@U123>" not in header
    assert header == "ping &lt;!channel&gt; &amp; &lt;@U123&gt;"


def _notification_job(tmp_path, *, channel_id=True, response_url=True):
    job_dir = Path(tmp_path) / "job"
    job_dir.mkdir()
    (job_dir / "thread_ts").write_text("1700000000.000001")
    if channel_id:
        (job_dir / "channel_id").write_text("C-THREAD")
    if response_url:
        (job_dir / "response_url").write_text("https://example.invalid/response")


def test_thread_notification_prefers_bot_without_thread_source(monkeypatch, tmp_path):
    _notification_job(tmp_path)
    calls = []
    monkeypatch.setattr(wh, "JOB_DIR", Path(tmp_path))
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C-DEFAULT")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: calls.append((args, kwargs)) or "reply-ts")
    monkeypatch.setattr(wh, "_slack_post", lambda *args, **kwargs: calls.append((args, kwargs)) or True)

    assert wh._notify_job("job", "thread reply") is True
    assert calls == [(('thread reply',), {"thread_ts": "1700000000.000001", "channel_id": "C-THREAD"})]


def test_thread_notification_falls_back_to_response_url_when_bot_fails(monkeypatch, tmp_path):
    _notification_job(tmp_path)
    calls = []
    monkeypatch.setattr(wh, "JOB_DIR", Path(tmp_path))
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C-DEFAULT")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: calls.append(("bot", args, kwargs)) or "")
    monkeypatch.setattr(wh, "_slack_post", lambda *args, **kwargs: calls.append(("response", args, kwargs)) or True)

    assert wh._notify_job("job", "thread reply") is True
    assert [call[0] for call in calls] == ["bot", "response"]
    assert calls[-1][1][0] == "https://example.invalid/response"


def test_thread_without_channel_or_response_url_never_uses_default_channel(monkeypatch, tmp_path):
    _notification_job(tmp_path, channel_id=False, response_url=False)
    calls = []
    monkeypatch.setattr(wh, "JOB_DIR", Path(tmp_path))
    monkeypatch.setattr(wh, "SLACK_BOT_TOKEN", "xoxb-test")
    monkeypatch.setattr(wh, "SLACK_CHANNEL_ID", "C-DEFAULT")
    monkeypatch.setattr(wh, "_post_slack_bot", lambda *args, **kwargs: calls.append((args, kwargs)) or "unexpected")

    assert wh._notify_job("job", "thread reply") is False
    assert calls == []
