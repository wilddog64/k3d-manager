"""Pure state and Slack-card helpers for cloud request approval."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import secrets
import tempfile

from hermes.approvals import interactive_blocks

CLOUD_ACTION_ID_RE = re.compile(r"^c[0-9]+-[0-9a-f]{8}$")
NONCE_RE = re.compile(r"^[0-9a-f]{16}$")
REQUESTED_BY_RE = re.compile(r"^[A-Za-z0-9._@:-]{1,64}$")
MAX_PENDING = 3
MAX_CARDS_PER_HOUR = 10
MIN_LIFETIME = 300
MAX_LIFETIME = 1800
DRAIN_INTERVAL = 30


class StoreError(Exception):
    """Persisted approval state is invalid."""


@dataclass
class Pending:
    request_id: str
    approval_id: str
    nonce: str
    request: dict
    created_at: float
    expires_at: float
    notice_published: bool


@dataclass
class Store:
    pending: dict[str, Pending] = field(default_factory=dict)
    cards: list[float] = field(default_factory=list)
    last_drain: float = 0


@dataclass
class Refusal:
    reason: str


@dataclass
class Decision:
    kind: str
    request_id: str | None = None
    request: dict | None = None
    approval_id: str | None = None
    expires_at: float | None = None


def _finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def load(path) -> Store:
    path = Path(path)
    if not path.exists():
        return Store()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or type(data.get("v")) is not int or data.get("v") != 1:
            raise ValueError("unsupported store version")
        raw_pending = data["pending"]
        cards = data["cards"]
        last_drain = data["last_drain"]
        if not isinstance(raw_pending, dict) or not isinstance(cards, list):
            raise ValueError("invalid store collections")
        if not _finite(last_drain) or not all(_finite(card_time) for card_time in cards):
            raise ValueError("invalid store time")
        pending = {}
        for request_id, raw in raw_pending.items():
            if not isinstance(raw, dict):
                raise ValueError("invalid pending record")
            record = Pending(**raw)
            if (request_id != record.request_id or not CLOUD_ACTION_ID_RE.fullmatch(record.approval_id)
                    or not NONCE_RE.fullmatch(record.nonce) or not isinstance(record.request, dict)
                    or not _finite(record.created_at) or not _finite(record.expires_at)
                    or not isinstance(record.notice_published, bool)):
                raise ValueError("invalid pending fields")
            pending[request_id] = record
        return Store(pending=pending, cards=cards, last_drain=last_drain)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        raise StoreError(f"invalid approval store: {exc}") from exc


def save(path, store):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = {"v": 1, "pending": {key: vars(value) for key, value in store.pending.items()},
               "cards": store.cards, "last_drain": store.last_drain}
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, allow_nan=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def admit(store, request_id, request, now, rand=secrets):
    if request_id in store.pending:
        return store.pending[request_id]
    raw_expiry = request["expires_at"]
    expires_at = datetime.fromisoformat(raw_expiry.replace("Z", "+00:00"))
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    expiry = min(expires_at.timestamp(), now + MAX_LIFETIME)
    if expiry - now < MIN_LIFETIME:
        return Refusal("request expires too soon for approval; file it with at least 5 minutes left")
    store.cards[:] = [card_time for card_time in store.cards if card_time >= now - 3600]
    if len(store.pending) >= MAX_PENDING or len(store.cards) >= MAX_CARDS_PER_HOUR:
        return Refusal("too many requests awaiting approval; try again later")
    action_id = "c1-" + rand.token_hex(4)
    record = Pending(request_id, action_id, rand.token_hex(8), request, now, expiry, False)
    store.cards.append(now)
    store.pending[request_id] = record
    return record


def remove(store, request_id):
    store.pending.pop(request_id, None)


BLAST = {
    "sandbox-up": "creates an AWS sandbox; it costs money until sandbox-down",
    "sandbox-down": "destroys the AWS sandbox and everything on it",
    "make-e2e": "runs the e2e suite on the hub",
}


def _safe(value):
    text = str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return "".join(char for char in text if char != "`" and ord(char) >= 32 and ord(char) != 127)[:120]


def card(pending):
    request = pending.request
    action = str(request.get("action", ""))
    if action == "make-e2e-remote":
        blast = f"runs the e2e suite on runner {_safe(request.get('args', {}).get('runner', ''))}"
    elif action in BLAST:
        blast = BLAST[action]
    else:
        raise ValueError(f"unsupported cloud action: {action}")
    args = request.get("args", {})
    pairs = [f"`{_safe(key)}={_safe(value)}`" for key, value in args.items()] if isinstance(args, dict) else []
    rendered_args = ", ".join(pairs) if pairs else "none"
    requested_by = request.get("requested_by")
    submitter = str(requested_by) if isinstance(requested_by, str) and REQUESTED_BY_RE.fullmatch(requested_by) else "(invalid)"
    expiry = datetime.fromtimestamp(pending.expires_at, timezone.utc).strftime("%H:%M")
    text = (f"Cloud request `{_safe(pending.request_id)}` asks to run `{_safe(action)}` with {rendered_args}. "
            f"Submitter not verified (requested_by: `{_safe(submitter)}`). Expires {expiry} UTC. Deny or ignore to do nothing.")
    item = {"action_id": pending.approval_id, "name": f"Run cloud request {action}", "blast_radius": blast}
    return text, interactive_blocks(text, [item], pending.nonce)


def due_for_drain(store, now):
    return bool(store.pending) and now - store.last_drain >= DRAIN_INTERVAL


def decide(store, items, now):
    store.last_drain = now
    output = []
    # Any valid denial for an approval wins over an approval in the same drain batch.
    denied = {(item.get("action_id"), item.get("nonce")) for item in items if isinstance(item, dict)
              and item.get("decision", "approve") == "deny"}
    for item in items:
        approval_id = item.get("action_id")
        drop = Decision("drop", approval_id=approval_id if isinstance(approval_id, str) else None)
        record = next((entry for entry in store.pending.values() if entry.approval_id == approval_id), None)
        if record is None or item.get("nonce") != record.nonce:
            output.append(drop)
            continue
        if now >= record.expires_at:
            store.pending.pop(record.request_id, None)
            output.extend((drop, Decision("expire", record.request_id, record.request,
                                                        record.approval_id, record.expires_at)))
        elif (approval_id, record.nonce) in denied:
            store.pending.pop(record.request_id, None)
            output.extend((drop, Decision("deny", record.request_id, record.request,
                                                        record.approval_id, record.expires_at)))
        elif item.get("decision", "approve") == "approve":
            store.pending.pop(record.request_id, None)
            output.extend((drop, Decision("execute", record.request_id, record.request,
                                                        record.approval_id, record.expires_at)))
        else:
            output.append(drop)
    for record in list(store.pending.values()):
        if now >= record.expires_at:
            store.pending.pop(record.request_id, None)
            output.append(Decision("expire", record.request_id, record.request,
                                   record.approval_id, record.expires_at))
    return output
