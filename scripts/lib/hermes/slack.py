"""Slack relay delivery for Hermes summaries and approval buttons."""

import json
import logging
import urllib.request
from urllib.error import HTTPError
from urllib.parse import urlsplit


_LOG = logging.getLogger("k3dm-hermes")


def _short_reply(error, relay_url):
    try:
        reply = error.read(800 + len(relay_url.encode("utf-8"))).decode("utf-8", errors="replace")
    except Exception:
        reply = ""
    if relay_url:
        reply = reply.replace(relay_url, "[redacted]")
        path = urlsplit(relay_url).path
        if path and path != "/":
            reply = reply.replace(path, "[redacted]")
    return " ".join(reply.split())[:200] or "empty reply"


def post_summary(relay_url, message, opener=urllib.request.urlopen):
    """Deliver a summary to the existing incoming-webhook relay; return success."""
    if not relay_url:
        return False
    request = urllib.request.Request(
        relay_url,
        data=json.dumps({"text": message, "response_type": "in_channel"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with opener(request, timeout=10):
            return True
    except HTTPError as error:
        _LOG.warning("Slack summary post failed: HTTP %s %s", error.code,
                     _short_reply(error, relay_url))
        return False
    except Exception:
        return False


def post_interactive(relay_url, message, blocks, opener=urllib.request.urlopen):
    """Deliver a summary with Block Kit approval buttons; return success."""
    if not relay_url:
        return False
    request = urllib.request.Request(
        relay_url,
        data=json.dumps({"text": message, "blocks": blocks,
                         "response_type": "in_channel"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with opener(request, timeout=10):
            return True
    except Exception:
        return False
