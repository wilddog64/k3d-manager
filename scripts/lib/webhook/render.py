#!/usr/bin/env python3
"""Slack response/rendering helpers for k3dm-webhook.

Phase 1 of the in-repo modularization (see
docs/plans/v1.13.0-webhook-modularization.md): Slack output helpers
extracted verbatim from bin/k3dm-webhook. No command behavior changes.
"""

import json
import re
import urllib.parse
import urllib.request

from webhook.config import SLACK_BOT_TOKEN, SLACK_CHANNEL_ID


def _slack_post(url, text):
    """POST a text message to a Slack incoming webhook or response_url."""
    if not url:
        return
    data = json.dumps({"text": text, "response_type": "in_channel"}).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass


def _post_slack_bot(text, thread_ts=None):
    """POST to Slack chat.postMessage API. Returns ts on success, empty string on failure."""
    if not SLACK_BOT_TOKEN or not SLACK_CHANNEL_ID:
        return ""
    payload = {"channel": SLACK_CHANNEL_ID, "text": text}
    if thread_ts:
        payload["thread_ts"] = thread_ts
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=data,
        headers={
            "Authorization": f"Bearer {SLACK_BOT_TOKEN}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            return result.get("ts", "") if result.get("ok") else ""
    except Exception:
        return ""


def _fetch_thread_context(thread_ts, limit=20):
    """Fetch recent messages from a Slack thread; return cleaned text or empty string."""
    if not SLACK_BOT_TOKEN or not SLACK_CHANNEL_ID or not thread_ts:
        return ""
    params = urllib.parse.urlencode({
        "channel": SLACK_CHANNEL_ID,
        "ts": thread_ts,
        "limit": limit,
    })
    req = urllib.request.Request(
        f"https://slack.com/api/conversations.replies?{params}",
        headers={"Authorization": f"Bearer {SLACK_BOT_TOKEN}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        if not data.get("ok"):
            return ""
        lines = []
        for msg in data.get("messages", []):
            if msg.get("bot_id") or msg.get("subtype"):
                continue
            text = msg.get("text", "").strip()
            if not text:
                continue
            # Skip bot status lines (hourglass, checkmarks, progress noise)
            if re.search(r'^[⏳✅❌🔄⚠️]|^\*?k3dm\*?|^:hourglass', text):
                continue
            # Strip ANSI and excessive whitespace
            text = re.sub(r'\x1b\[[0-9;]*[mK]', '', text)
            text = re.sub(r'\n{3,}', '\n\n', text).strip()
            if text:
                lines.append(text)
        return "\n---\n".join(lines) if lines else ""
    except Exception:
        return ""
