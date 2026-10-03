import importlib
import logging
import sys


def _logger(monkeypatch, level):
    monkeypatch.setenv("K3DM_LOG_LEVEL", level)
    sys.modules.pop("webhook.log", None)
    return importlib.import_module("webhook.log").get_logger("test.webhook-log")


def test_levels_filter(monkeypatch, capsys):
    for level, visible in (("error", ["error"]), ("warn", ["error", "warn"]),
                           ("info", ["error", "warn", "info"]),
                           ("debug", ["error", "warn", "info", "debug"])):
        logger = _logger(monkeypatch, level)
        logger.error("error")
        logger.warning("warn")
        logger.info("info")
        logger.debug("debug")
        output = capsys.readouterr().err
        assert [line.rsplit(" ", 1)[-1] for line in output.splitlines()] == visible


def test_unknown_level_warns_and_uses_info(monkeypatch, capsys):
    logger = _logger(monkeypatch, "verbose")
    assert logger.level == logging.INFO
    assert "unknown K3DM_LOG_LEVEL" in capsys.readouterr().err


def test_logger_does_not_emit_request_body_or_bearer(capsys, monkeypatch):
    logger = _logger(monkeypatch, "info")
    body = '{"password":"synthetic-body"}'
    token = "synthetic-bearer"
    logger.info("request method=POST path=/api/v1/status/{job_id} status=200 role=reader duration_ms=1")
    text = capsys.readouterr().err
    assert body not in text and token not in text
    assert "/api/v1/status/{job_id}" in text
