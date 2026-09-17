"""Schedule and claim helpers for detached Hermes E2E jobs."""

import json
import os
from datetime import datetime, timedelta

_DAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


def parse_schedule(value):
    """Parse `wed,sat@02:00`, returning None for invalid configuration."""
    try:
        days, clock = value.split("@")
        hour, minute = (int(piece) for piece in clock.split(":"))
        parsed = {_DAYS[item] for item in days.split(",")}
        if not parsed or not 0 <= hour <= 23 or not 0 <= minute <= 59:
            return None
        return {"days": parsed, "hour": hour, "minute": minute}
    except (KeyError, TypeError, ValueError):
        return None


def configured_schedule(environ=None):
    """Return configured schedule, or None when explicitly disabled/invalid."""
    environ = os.environ if environ is None else environ
    if environ.get("K3DM_HERMES_E2E_ENABLED") == "0":
        return None
    return parse_schedule(environ.get("K3DM_HERMES_E2E_SCHEDULE", "wed,sat@02:00"))


def _read_claim(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def due_slot(now_local, claims_dir, schedule):
    """Return today's eligible slot, accounting for its claim and final marker."""
    if not schedule or now_local.weekday() not in schedule["days"]:
        return None
    if (now_local.hour, now_local.minute) < (schedule["hour"], schedule["minute"]):
        return None
    slot = now_local.date().isoformat()
    claims_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    if (claims_dir / f"{slot}.json").exists():
        return None
    claim = _read_claim(claims_dir / f"{slot}.claim")
    if not claim:
        return slot
    next_try = claim.get("next_try", "")
    try:
        retry_at = datetime.fromisoformat(next_try)
    except ValueError:
        retry_at = now_local
    return slot if int(claim.get("attempts", 0)) < 6 and now_local >= retry_at else None


def pid_alive(pid):
    """Test a pid without signalling it."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def claim_slot(claims_dir, slot, now, pid=0):
    """Atomically claim a slot; stale dead claims are retried as a failed attempt."""
    path = claims_dir / f"{slot}.claim"
    claims_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    old = _read_claim(path)
    if old and pid_alive(old.get("pid")):
        return None
    attempts = int(old.get("attempts", 0))
    if old and now.timestamp() - path.stat().st_mtime > 3 * 3600:
        attempts += 1
    claim = {"attempts": attempts, "next_try": now.isoformat(), "pid": pid}
    flags = os.O_WRONLY | os.O_CREAT | (os.O_EXCL if not path.exists() else os.O_TRUNC)
    try:
        descriptor = os.open(path, flags, 0o600)
    except FileExistsError:
        return None
    with os.fdopen(descriptor, "w") as handle:
        json.dump(claim, handle, sort_keys=True)
    return claim


def retry_claim(claims_dir, slot, now):
    """Record a preflight failure and return its new attempt total."""
    claims_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = claims_dir / f"{slot}.claim"
    claim = _read_claim(path)
    claim["attempts"] = int(claim.get("attempts", 0)) + 1
    claim["next_try"] = (now + timedelta(minutes=30)).isoformat()
    claim["pid"] = 0
    path.write_text(json.dumps(claim, sort_keys=True))
    path.chmod(0o600)
    return claim
