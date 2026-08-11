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
        import stat
        mode = TOKEN_FILE.stat().st_mode
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            print(f"[k3dm-webhook] ignoring {TOKEN_FILE}: group/other-accessible (chmod 600)", flush=True)
            return None
        return TOKEN_FILE.read_text().strip()
    return None


def _verify_slack_signature(raw_body, timestamp, signature):
    """Return True if the Slack request signature is valid."""
    if not SLACK_SIGNING_SECRET:
        return False
    import time
    try:
        timestamp_value = int(timestamp)
        body_text = raw_body.decode()
    except (AttributeError, TypeError, UnicodeDecodeError, ValueError):
        return False
    if abs(time.time() - timestamp_value) > 300:
        return False
    base = f"v0:{timestamp}:{body_text}"
    expected = "v0=" + hmac.new(
        SLACK_SIGNING_SECRET.encode(),
        base.encode(),
        digestmod="sha256",
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def _load_slack_role_map():
    """Parse 'U012:admin,U045:operator' from env or Keychain into {user_id: role}."""
    raw = os.environ.get("K3DM_SLACK_ROLE_MAP") or _keychain_secret("k3dm-slack-role-map")
    mapping = {}
    for pair in (raw or "").split(","):
        pair = pair.strip()
        if not pair or ":" not in pair:
            continue
        uid, _, role = pair.partition(":")
        uid = uid.strip()
        role = role.strip().lower()
        if uid and role in ("reader", "operator", "admin"):
            mapping[uid] = role
    return mapping


SLACK_ROLE_MAP = _load_slack_role_map()


def _slack_user_role(user_id):
    """Resolve a Slack user ID to reader|operator|admin. Unknown → reader (fail closed)."""
    return SLACK_ROLE_MAP.get((user_id or "").strip(), "reader")


def _slack_user_is_allowlisted(user_id):
    """Return True only when a non-empty Slack user ID is explicitly mapped."""
    return bool((user_id or "").strip() in SLACK_ROLE_MAP)
