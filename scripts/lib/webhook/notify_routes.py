"""Parse and load the operator's Slack notification route allowlist."""

import os
import re

from webhook.cloud_actions import ACTION_ALLOWLIST

ALIAS_RE = re.compile(r"[a-z][a-z0-9-]{0,31}")
CHANNEL_RE = re.compile(r"[CG][A-Z0-9]{8,11}")
MAX_ALIASES = 8
MAX_RAW_BYTES = 512
RESERVED = {"default"}
ENV_VAR = "K3DM_SLACK_NOTIFICATION_ROUTES"
KEYCHAIN_SERVICE = "k3dm-slack-notification-routes"
INVALID_REASON = "invalid notification route"
UNSUPPORTED_REASON = "notification route not supported for this action"


class RouteMapError(ValueError):
    """A route map failed validation without exposing its contents."""


def parse_routes(raw: str) -> dict[str, str]:
    def invalid():
        raise RouteMapError("invalid notification route map")

    if len(raw.encode("utf-8")) > MAX_RAW_BYTES:
        invalid()
    if not raw.strip():
        return {}
    routes = {}
    channels = set()
    for item in raw.split(","):
        parts = item.split(":")
        if len(parts) != 2:
            invalid()
        alias, channel = (part.strip() for part in parts)
        if (not ALIAS_RE.fullmatch(alias) or alias in RESERVED or not CHANNEL_RE.fullmatch(channel)
                or alias in routes or channel in channels or len(routes) >= MAX_ALIASES):
            invalid()
        routes[alias] = channel
        channels.add(channel)
    return routes


def load_routes() -> tuple[dict[str, str], str]:
    raw = os.environ.get(ENV_VAR)
    if not raw:
        from webhook.auth import _keychain_secret
        raw = _keychain_secret(KEYCHAIN_SERVICE)
    if not raw:
        return {}, "absent"
    try:
        parsed = parse_routes(raw)
        return (parsed, "ok") if parsed else ({}, "absent")
    except RouteMapError:
        return {}, "invalid"


def route_names() -> frozenset[str]:
    return frozenset(load_routes()[0])


def routable(action: str) -> bool:
    return action in ACTION_ALLOWLIST and (ACTION_ALLOWLIST[action][1] == "/api/v1/make"
                                           or action in ("sandbox-up", "sandbox-down"))


def escape_label(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def escape_code_block(text: str) -> str:
    """Escape untrusted text placed inside a Slack triple-backtick block."""
    return escape_label(text).replace("`", "ˋ")
