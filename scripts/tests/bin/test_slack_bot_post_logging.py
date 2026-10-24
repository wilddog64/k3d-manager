import json
import logging
import sys
from pathlib import Path
from urllib.error import URLError


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import render


CHANNEL = "C123TEST"


class _Response:
    def __init__(self, result):
        self.result = result

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.result).encode()


def _post(monkeypatch, result=None, error=None, *, text="safe body", thread_ts=None):
    monkeypatch.setattr(render, "SLACK_BOT_TOKEN", "xoxb-TESTTOKEN")
    monkeypatch.setattr(render, "SLACK_CHANNEL_ID", CHANNEL)
    test_logger = logging.getLogger("webhook.render")
    monkeypatch.setattr(render, "logger", test_logger, raising=False)
    monkeypatch.setattr(test_logger, "propagate", True)
    monkeypatch.setattr(test_logger, "handlers", [])

    def fake_urlopen(_request, timeout):
        assert timeout == 10
        if error:
            raise error
        return _Response(result)

    monkeypatch.setattr(render.urllib.request, "urlopen", fake_urlopen)
    return render._post_slack_bot(text, thread_ts=thread_ts, channel_id=CHANNEL)


def test_rejection_logs_error_and_channel(monkeypatch, caplog):
    with caplog.at_level("WARNING", logger="webhook.render"):
        assert _post(monkeypatch, {"ok": False, "error": "not_in_channel"}) == ""

    assert len(caplog.records) == 1
    assert "not_in_channel" in caplog.text
    assert CHANNEL in caplog.text


def test_missing_scope_logs_needed_scope(monkeypatch, caplog):
    with caplog.at_level("WARNING", logger="webhook.render"):
        _post(monkeypatch, {"ok": False, "error": "missing_scope", "needed": "chat:write"})

    assert "needed=chat:write" in caplog.text


def test_transport_failure_logs_exception_class(monkeypatch, caplog):
    with caplog.at_level("WARNING", logger="webhook.render"):
        assert _post(monkeypatch, error=URLError("network unavailable")) == ""

    assert len(caplog.records) == 1
    assert "URLError" in caplog.text
    assert CHANNEL in caplog.text


def test_logs_exclude_token_message_and_thread(monkeypatch, caplog):
    with caplog.at_level("WARNING", logger="webhook.render"):
        _post(
            monkeypatch,
            {"ok": False, "error": "not_in_channel"},
            text="SECRET-BODY",
            thread_ts="SECRET-THREAD-TS",
        )

    for record in caplog.records:
        assert "xoxb-TESTTOKEN" not in record.getMessage()
        assert "Authorization" not in record.getMessage()
        assert "SECRET-BODY" not in record.getMessage()
        assert "SECRET-THREAD-TS" not in record.getMessage()


def test_success_returns_timestamp_without_warning(monkeypatch, caplog):
    with caplog.at_level("WARNING", logger="webhook.render"):
        assert _post(monkeypatch, {"ok": True, "ts": "1.2"}) == "1.2"

    assert not caplog.records
