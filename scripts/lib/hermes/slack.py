"""One-way Slack relay delivery for Hermes advisory summaries."""

import json
import urllib.request


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
    except Exception:
        return False
