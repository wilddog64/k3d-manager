"""Hermes pull-model Slack approvals: drain approved action-ids from the relay worker.

The worker only records intent. Every drained approval still goes through the
unchanged repairs.approve(), which re-validates the precondition and enforces
one attempt per incident.
"""

import json
import re
import urllib.parse
import urllib.request

APPROVAL_DRAIN_SERVICE = "k3dm-hermes-approval-drain-token"
ACTION_ID_RE = re.compile(r"^r[0-9]+-[0-9a-f]{8}$")
NONCE_RE = re.compile(r"^[0-9a-f]{16}$")
SLACK_USER_RE = re.compile(r"^[A-Z0-9]{2,32}$")


def _usable(drain_url, token):
    return bool(token) and str(drain_url).startswith("https://")


def fetch_approvals(drain_url, token, opener=urllib.request.urlopen, timeout=10):
    """Return well-formed approvals from the relay; fail closed to [] on any error."""
    if not _usable(drain_url, token):
        return []
    request = urllib.request.Request(drain_url, method="GET",
                                     headers={"Authorization": f"Bearer {token}"})
    try:
        with opener(request, timeout=timeout) as response:
            items = json.loads(response.read())
    except Exception:
        return []
    if not isinstance(items, list):
        return []
    return [item for item in items
            if isinstance(item, dict)
            and ACTION_ID_RE.match(str(item.get("action_id", "")))
            and NONCE_RE.match(str(item.get("nonce", "")))
            and SLACK_USER_RE.match(str(item.get("approved_by", "")))]


def delete_approval(drain_url, token, action_id, opener=urllib.request.urlopen, timeout=10):
    """Best-effort removal of a processed approval; return success."""
    if not _usable(drain_url, token) or not ACTION_ID_RE.match(str(action_id)):
        return False
    url = f"{drain_url.rstrip('/')}/{urllib.parse.quote(action_id)}"
    request = urllib.request.Request(url, method="DELETE",
                                     headers={"Authorization": f"Bearer {token}"})
    try:
        with opener(request, timeout=timeout):
            return True
    except Exception:
        return False


def interactive_blocks(message, proposals, nonce):
    """Block Kit: the summary plus Approve/Deny buttons carrying '<action_id>|<nonce>'."""
    blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": message[:2900]}}]
    for item in proposals:
        value = f"{item['action_id']}|{nonce}"
        detail = f"*{item['name']}* (`{item['action_id']}`)\nBlast radius: {item['blast_radius']}"
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": detail[:2900]}})
        blocks.append({"type": "actions", "block_id": item["action_id"], "elements": [
            {"type": "button", "action_id": "hermes_approve", "style": "primary",
             "text": {"type": "plain_text", "text": "Approve"}, "value": value,
             "confirm": {"title": {"type": "plain_text", "text": "Approve repair?"},
                         "text": {"type": "plain_text",
                                  "text": f"Run {item['name']}? Blast radius: {item['blast_radius']}"[:300]},
                         "confirm": {"type": "plain_text", "text": "Approve"},
                         "deny": {"type": "plain_text", "text": "Cancel"}}},
            {"type": "button", "action_id": "hermes_deny", "style": "danger",
             "text": {"type": "plain_text", "text": "Deny"}, "value": value},
        ]})
    return blocks
