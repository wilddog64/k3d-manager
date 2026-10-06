"""Small, redaction-safe logging facade for the webhook processes."""

import logging
import os
import sys
from datetime import datetime, timezone


_LEVELS = {"error": logging.ERROR, "warn": logging.WARNING,
           "info": logging.INFO, "debug": logging.DEBUG}
_configured = set()


class _UtcFormatter(logging.Formatter):
    def formatTime(self, record, datefmt=None):
        return datetime.fromtimestamp(record.created, timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ")


def get_logger(name):
    """Return a stderr logger using the K3DM_LOG_LEVEL contract."""
    logger = logging.getLogger(name)
    if name not in _configured:
        value = os.environ.get("K3DM_LOG_LEVEL", "info").lower()
        level = _LEVELS.get(value, logging.INFO)
        logger.setLevel(level)
        logger.propagate = False
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(_UtcFormatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
        logger.handlers.clear()
        logger.addHandler(handler)
        _configured.add(name)
        if value not in _LEVELS:
            logger.warning("unknown K3DM_LOG_LEVEL=%r; using info", value)
    return logger
