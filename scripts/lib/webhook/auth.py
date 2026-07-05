#!/usr/bin/env python3
"""Authentication helpers for k3dm-webhook.

In-repo modularization (see docs/plans/v1.13.0-webhook-modularization.md):
Keychain lookup, bearer-token resolution, and Slack request-signature
verification extracted verbatim from bin/k3dm-webhook. The module-level
SLACK_SIGNING_SECRET is computed at import time exactly as before.
No command behavior changes.
"""

import hmac
import os

from webhook.config import TOKEN_FILE
from webhook.proc import _spawn_capture_text


def _keychain_secret(service):
    try:
        rc, output, timed_out = _spawn_capture_text(
            ["security", "find-generic-password", "-s", service, "-a", "k3dm", "-w"],
            timeout=10,
        )
        return output.strip() if rc == 0 and not timed_out else ""
    except Exception:
        return ""


SLACK_SIGNING_SECRET = os.environ.get("SLACK_SIGNING_SECRET") or _keychain_secret("k3dm-slack-signing-secret")


def _get_token():
    token = os.environ.get("K3DM_WEBHOOK_TOKEN")
    if token:
        return token
    try:
        rc, output, timed_out = _spawn_capture_text(
            ["security", "find-generic-password",
             "-s", "k3dm-webhook-token", "-a", "k3dm", "-w"],
            timeout=10,
        )
        if rc == 0 and not timed_out and output.strip():
            return output.strip()
    except Exception:
        pass
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    return None


def _verify_slack_signature(raw_body, timestamp, signature):
    """Return True if the Slack request signature is valid."""
    if not SLACK_SIGNING_SECRET:
        return False
    import time
    if abs(time.time() - int(timestamp)) > 300:
        return False
    base = f"v0:{timestamp}:{raw_body.decode()}"
    expected = "v0=" + hmac.new(
        SLACK_SIGNING_SECRET.encode(),
        base.encode(),
        digestmod="sha256",
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
