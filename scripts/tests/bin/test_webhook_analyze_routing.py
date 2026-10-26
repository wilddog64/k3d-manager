import importlib.util
import os
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

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


def test_failed_bot_post_falls_back_to_incoming_webhook(monkeypatch, analyze_env, tmp_path):
    bot_calls = []
    webhook_calls = []
    monkeypatch.setattr(wh, "_post_slack_bot", lambda text, **kwargs: bot_calls.append((text, kwargs)) or "")
    monkeypatch.setattr(wh, "_slack_post", lambda *args: webhook_calls.append(args))

    _run(monkeypatch, tmp_path, [_alert()])

    assert len(bot_calls) == 1
    assert webhook_calls == [("https://hooks.invalid/test", bot_calls[0][0])]


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
