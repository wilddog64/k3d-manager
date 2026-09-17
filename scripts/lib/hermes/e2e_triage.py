"""Pure, rule-based classification for Hermes E2E failures."""

import re

_UNREACHABLE = re.compile(r"ECONNREFUSED|ENOTFOUND|EAI_AGAIN|connect ETIMEDOUT")
_TIMEOUT = re.compile(r"Timeout \d+ms exceeded")
_CONTRACT = re.compile(r"Received: undefined|Cannot read properties of undefined|must have a length property|received value must be a number|toHaveProperty|Expected: \"number\".*Received: \"string\"", re.S)
_PORT = re.compile(r":(8000|8083|8080|8084)(?:\D|$)")
_BEARER = re.compile(r"Bearer\s+\S+")
_JWT = re.compile(r"eyJ[\w-]+\.[\w-]+\.[\w-]+")
_SECRET = re.compile(r"(?i)(password|secret|token|api[_-]?key)[\"'=:\s]+\S+")
_PORTS = {"8000": "product-catalog", "8083": "basket", "8080": "order", "8084": "payment"}


def redact(value):
    """Return a log-safe string before it is written or posted."""
    text = str(value or "")
    for pattern in (_BEARER, _JWT, _SECRET):
        text = pattern.sub("<redacted>", text)
    return text


def spec_slug(failure):
    """Convert a Playwright spec path into a stable target."""
    path = str(failure.get("file") or failure.get("spec") or "unknown")
    path = re.sub(r"\.spec\.(ts|js)$", "", path)
    path = re.sub(r"[^a-z0-9]+", "-", path.lower()).strip("-")
    return path or "unknown"


def _unreachable_target(text):
    match = _PORT.search(text)
    return _PORTS.get(match.group(1), f"host-{match.group(1)}") if match else "host-unknown"


def classify(failure):
    """Classify one failure; ordering is deliberately the public policy."""
    error = str(failure.get("error", ""))
    status = str(failure.get("status", ""))
    combined = f"{error}\n{status}"
    if _UNREACHABLE.search(combined):
        return "service-unreachable", _unreachable_target(combined)
    if status == "timedOut" or _TIMEOUT.search(combined):
        return "timeout", spec_slug(failure)
    if _CONTRACT.search(combined):
        return "contract-drift", spec_slug(failure)
    return "assertion", spec_slug(failure)


def group_slug(kind, target):
    """Create a bounded filesystem-safe group id."""
    value = re.sub(r"[^a-z0-9]+", "-", f"e2e-{kind}-{target}".lower())
    return value.strip("-")[:60].rstrip("-")


def _failure_title(failure):
    return redact(failure.get("title") or failure.get("name") or "unnamed test")


def triage(summary, failures):
    """Group failed E2E tests into small, redacted issue-ready records."""
    if summary.get("result") == "pass":
        return []
    if not failures:
        if summary.get("result") == "fail":
            target = str(summary.get("phase") or "dispatch")
            return [{"kind": "harness", "target": target, "slug": group_slug("harness", target),
                     "count": 1, "titles": [], "samples": []}]
        return []
    groups = {}
    for failure in failures:
        kind, target = classify(failure)
        group = groups.setdefault((kind, target), {"kind": kind, "target": target,
            "slug": group_slug(kind, target), "count": 0, "titles": [], "samples": []})
        group["count"] += 1
        if len(group["titles"]) < 10:
            group["titles"].append({"file": redact(failure.get("file") or failure.get("spec") or "unknown"),
                                    "title": _failure_title(failure)})
        sample = redact(failure.get("error", ""))
        if sample and sample not in group["samples"] and len(group["samples"]) < 3:
            group["samples"].append(sample)
    return list(groups.values())


def diff_groups(previous, current):
    """Return group states relative to a prior final marker."""
    old = {item.get("slug") for item in previous}
    new = {item.get("slug") for item in current}
    return {"new": sorted(new - old), "ongoing": sorted(new & old), "resolved": sorted(old - new)}
