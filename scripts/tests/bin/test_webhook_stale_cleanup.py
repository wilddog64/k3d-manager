import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "bin" / "k3dm-webhook"
SPEC = importlib.util.spec_from_file_location(
    "k3dm_webhook_test_module", SOURCE,
    loader=SourceFileLoader("k3dm_webhook_test_module", str(SOURCE)),
)
webhook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(webhook)


def _run(monkeypatch, tmp_path, rc, output, confirm=False, timed_out=False, channel_id=""):
    job_id = "a1b2c3f0"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    notifications = []
    monkeypatch.setattr(webhook, "JOB_DIR", tmp_path)
    monkeypatch.setattr(webhook, "_notify_job", lambda job, text: notifications.append((job, text)))
    monkeypatch.setattr(webhook, "_redact_secrets", lambda text: text)
    monkeypatch.setattr(webhook, "_spawn_capture_text", lambda *_args, **_kwargs: (rc, output, timed_out))
    monkeypatch.setattr(webhook, "_start_bot_thread", lambda *_args, **_kwargs: "1700000000.000099")
    webhook._run_stale_sandbox_cleanup(job_id, confirm=confirm, channel_id=channel_id)
    return job_dir, notifications


def test_stale_cleanup_persists_success_and_output(monkeypatch, tmp_path):
    job_dir, notifications = _run(monkeypatch, tmp_path, 0, "already absent\n")
    assert (job_dir / "status").read_text() == "success"
    assert (job_dir / "exit_code").read_text() == "0"
    assert (job_dir / "output").read_text() == "already absent\n"
    assert "cleanup complete" in notifications[0][1].lower()


def test_stale_cleanup_persists_failure_and_exit_code(monkeypatch, tmp_path):
    job_dir, notifications = _run(monkeypatch, tmp_path, 1, "permission denied\n", confirm=True)
    assert (job_dir / "status").read_text() == "failed"
    assert (job_dir / "exit_code").read_text() == "1"
    assert (job_dir / "output").read_text() == "permission denied\n"
    assert "incomplete" in notifications[0][1].lower()


def test_notify_job_falls_back_to_response_url_in_same_thread(monkeypatch, tmp_path):
    job_dir = tmp_path / "deadbeef"
    job_dir.mkdir()
    (job_dir / "thread_ts").write_text("1700000000.000001")
    (job_dir / "response_url").write_text("https://hooks.slack.com/commands/test")
    calls = []
    monkeypatch.setattr(webhook, "JOB_DIR", tmp_path)
    monkeypatch.setattr(webhook, "SLACK_BOT_TOKEN", "bot-token")
    monkeypatch.setattr(webhook, "SLACK_CHANNEL_ID", "configured-channel")
    monkeypatch.setattr(webhook, "_post_slack_bot", lambda *_args, **_kwargs: "")
    monkeypatch.setattr(webhook, "_slack_post", lambda *args, **kwargs: calls.append((args, kwargs)))

    webhook._notify_job("deadbeef", "cleanup failed")

    assert calls == [(("https://hooks.slack.com/commands/test", "cleanup failed"),
                      {"thread_ts": "1700000000.000001"})]


def test_notify_job_prefers_response_url_over_configured_bot_channel(monkeypatch, tmp_path):
    job_dir = tmp_path / "deadbeef"
    job_dir.mkdir()
    (job_dir / "thread_ts").write_text("1700000000.000001")
    (job_dir / "response_url").write_text("https://hooks.slack.com/commands/test")
    calls = []
    monkeypatch.setattr(webhook, "JOB_DIR", tmp_path)
    monkeypatch.setattr(webhook, "SLACK_BOT_TOKEN", "bot-token")
    monkeypatch.setattr(webhook, "SLACK_CHANNEL_ID", "wrong-channel")
    monkeypatch.setattr(webhook, "_post_slack_bot", lambda *_args, **_kwargs: calls.append("bot") or "bot-ts")
    monkeypatch.setattr(webhook, "_slack_post", lambda *args, **kwargs: calls.append((args, kwargs)) or True)

    webhook._notify_job("deadbeef", "cleanup complete")

    assert calls == [(('https://hooks.slack.com/commands/test', 'cleanup complete'),
                      {'thread_ts': '1700000000.000001'})]


def test_top_level_cleanup_starts_a_thread(monkeypatch, tmp_path):
    job_dir, _ = _run(monkeypatch, tmp_path, 0, "preview\n", channel_id="C123")
    assert (job_dir / "thread_ts").read_text() == "1700000000.000099"
    assert (job_dir / "thread_source").read_text() == "bot"


def test_notify_job_uses_bot_for_a_new_thread(monkeypatch, tmp_path):
    job_dir = tmp_path / "deadbeef"
    job_dir.mkdir()
    (job_dir / "thread_ts").write_text("1700000000.000001")
    (job_dir / "thread_source").write_text("bot")
    (job_dir / "channel_id").write_text("C123")
    (job_dir / "response_url").write_text("https://hooks.slack.com/commands/test")
    calls = []
    monkeypatch.setattr(webhook, "JOB_DIR", tmp_path)
    monkeypatch.setattr(webhook, "SLACK_BOT_TOKEN", "bot-token")
    monkeypatch.setattr(webhook, "SLACK_CHANNEL_ID", "wrong-channel")
    monkeypatch.setattr(webhook, "_post_slack_bot", lambda *args, **kwargs: calls.append((args, kwargs)) or "bot-ts")
    monkeypatch.setattr(webhook, "_slack_post", lambda *args, **kwargs: calls.append((args, kwargs)) or True)

    webhook._notify_job("deadbeef", "cleanup complete")

    assert calls == [(('cleanup complete',), {'thread_ts': '1700000000.000001', 'channel_id': 'C123'})]
