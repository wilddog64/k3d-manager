"""Authorization, audit, and request-rate policy for k3dm-webhook."""

import datetime
import json
import os
import threading
import time

from webhook.config import AUDIT_DIR
from webhook.make_targets import MAKE_TARGETS

__all__ = [
    "_ACTION_POLICY",
    "_THREAD_COMMAND_MIN_ROLE",
    "_action_policy",
    "_audit_remote_action",
    "_effective_make_role",
    "effective_policy",
    "_normalize_actor_role",
    "_normalize_role",
    "_rate_limited",
    "_request_actor",
    "_request_role",
    "_role_allows",
    "strictest_role",
    "_thread_command_min_role",
]

_ROLE_LEVELS = {"reader": 1, "operator": 2, "admin": 3}
_ROLE_DEFAULT = "admin"

_RATE_WINDOW_SECS = 60
_RATE_MAX_DEFAULT = int(os.environ.get("K3DM_RATE_MAX_PER_MIN", "60"))
_rate_lock = threading.Lock()
_rate_hits: dict = {}


def _slack_user_role(_user_id):
    """Fallback resolver used when policy is imported independently of the server."""
    return "reader"


def _rate_limited(bucket):
    """Fixed-window per-bucket limiter. Returns True if the caller is over budget."""
    now = time.time()
    with _rate_lock:
        window_start, count = _rate_hits.get(bucket, (now, 0))
        if now - window_start >= _RATE_WINDOW_SECS:
            window_start, count = now, 0
        count += 1
        _rate_hits[bucket] = (window_start, count)
        return count > _RATE_MAX_DEFAULT


_ACTION_POLICY = {
    "/api/v1/argocd-upgrade": {"name": "argocd-upgrade", "min_role": "admin"},
    "/api/v1/cve-remediate": {"name": "cve-remediate", "min_role": "operator"},
    "/api/v1/cluster-status": {"name": "cluster-status", "min_role": "reader"},
    "/api/v1/diagnostics": {"name": "diagnostics", "min_role": "reader"},
    "/api/v1/hostinger-status": {"name": "hostinger-status", "min_role": "reader"},
    "/api/v1/cluster-refresh": {"name": "cluster-refresh", "min_role": "operator"},
    "/api/v1/cluster-resume": {"name": "cluster-resume", "min_role": "admin"},
    "/api/v1/cleanup-stale-sandbox": {"name": "cleanup-stale-sandbox", "min_role": "admin"},
    "/api/v1/analyze": {"name": "analyze", "min_role": "operator"},
    "/api/v1/ask": {"name": "ask", "min_role": "reader"},
}

_THREAD_COMMAND_MIN_ROLE = {
    "kill": "operator",
    "diagnosis": "reader",
    "status": "reader",
    "logs": "reader",
    "ask": "reader",
    "claude": "reader",
    "gemini": "reader",
    "codex": "reader",
    "cluster-status": "reader",
    "hostinger-status": "reader",
    "cluster-refresh": "operator",
    "refresh": "operator",
    "cluster-resume": "admin",
    "resume": "admin",
    "cluster-down": "admin",
    "down": "admin",
    "cluster-up": "admin",
    "up": "admin",
    "cleanup-stale-sandbox": "admin",
}


def _thread_command_min_role(command):
    """Return the min role required for a Slack thread command (default reader)."""
    cmd = command.strip().lstrip("/").lower().split()[0] if command.strip() else ""
    return _THREAD_COMMAND_MIN_ROLE.get(cmd, "reader")


def _normalize_role(role):
    role = (role or "").strip().lower()
    return role if role in _ROLE_LEVELS else _ROLE_DEFAULT


def _normalize_actor_role(role):
    """Normalize a caller's role. Unknown values fail closed to reader."""
    role = (role or "").strip().lower()
    return role if role in _ROLE_LEVELS else "reader"


def _request_role(headers):
    raw = headers.get("X-K3DM-Role")
    if raw is None:
        return _ROLE_DEFAULT  # direct token = admin credential
    raw = raw.strip().lower()
    return raw if raw in _ROLE_LEVELS else "reader"  # present-but-invalid → fail closed


def _effective_make_role(headers, body):
    """Cap a relayed /k3dm role at the caller's mapped Slack role (unknown → reader)."""
    header_role = _request_role(headers)
    if headers.get("X-K3DM-Role") is None:
        return header_role
    user_role = _slack_user_role(str(body.get("slack_user_id", "")))
    if user_role not in _ROLE_LEVELS:
        user_role = "reader"
    return header_role if _ROLE_LEVELS[header_role] <= _ROLE_LEVELS[user_role] else user_role


def _request_actor(headers):
    actor = (headers.get("X-K3DM-Actor", "") or "").strip()
    return actor or "direct-token"


def _role_allows(actual_role, required_role):
    return _ROLE_LEVELS[_normalize_actor_role(actual_role)] >= _ROLE_LEVELS[_normalize_role(required_role)]


def _action_policy(path, body):
    if path == "/api/v1/cluster":
        action = body.get("action", "")
        if action == "kill":
            return {"name": "cluster-kill", "min_role": "operator"}
        if action in ("up", "down"):
            return {"name": f"cluster-{action}", "min_role": "admin"}
    if path == "/api/v1/make":
        target = str(body.get("target", "")).strip()
        spec = MAKE_TARGETS.get(target)
        return {"name": f"make:{target or 'help'}", "min_role": spec["min_role"] if spec else "reader"}
    return _ACTION_POLICY.get(path)


def strictest_role(*roles):
    """Return the highest-privilege requirement among the given roles; None values ignored."""
    present = [_normalize_role(r) for r in roles if r]
    return max(present, key=lambda r: _ROLE_LEVELS[r]) if present else _ROLE_DEFAULT


def effective_policy(route, path, body):
    """Resolve the one (action_name, min_role) pair a request must satisfy."""
    dynamic = _action_policy(path, body)
    if route is None:
        return dynamic
    min_role = strictest_role(route["min_role"], (dynamic or {}).get("min_role"))
    return {"name": (dynamic or {}).get("name") or route["action_name"], "min_role": min_role}


def _audit_remote_action(path, action_name, actor, role, allowed, body=None, reason=""):
    try:
        AUDIT_DIR.mkdir(parents=True, exist_ok=True)
        payload = {
            "ts": datetime.datetime.now(tz=datetime.timezone.utc).isoformat(),
            "path": path,
            "action": action_name,
            "actor": actor,
            "role": _normalize_actor_role(role),
            "allowed": bool(allowed),
            "reason": reason,
            "provider": (body or {}).get("provider", ""),
            "request_action": (body or {}).get("action", ""),
            "source_command": (body or {}).get("_source_command", ""),
        }
        with open(AUDIT_DIR / "remote-operator.jsonl", "a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, separators=(",", ":")) + "\n")
    except OSError:
        pass
