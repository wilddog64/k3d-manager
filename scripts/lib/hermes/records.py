"""Normalized Hermes sensor records."""

from datetime import datetime, timezone

STATUSES = frozenset(("healthy", "degraded", "unknown"))


def timestamp():
    """Return the current UTC timestamp in the Hermes wire format."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def record(sensor, status, evidence, sampled_at=None):
    """Create the uniform, source-agnostic sensor record."""
    if status not in STATUSES:
        raise ValueError("invalid Hermes status")
    return {
        "sensor": sensor,
        "status": status,
        "evidence": str(evidence)[:200],
        "sampled_at": sampled_at or timestamp(),
    }
