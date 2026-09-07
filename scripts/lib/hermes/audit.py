"""Read-only monthly security-posture audit; callers inject transports for testability.

This is a report, not an actuator: it never writes, never proposes, and never touches the
repair path. Every check degrades gracefully on a missing scope (reports "unavailable")
rather than crashing or fabricating a clean bill of health.
"""

from datetime import datetime, timezone

from hermes.records import timestamp
from hermes.sensors import (GITHUB_EXPIRY_HEADER, GITHUB_SERVICE, WEBHOOK_SERVICE,
                            ARGOCD_SERVICE, _parse_expiry)

REPOSITORY = "wilddog64/k3d-manager"
AUDIT_SERVICE = "k3dm-hermes-audit-token"

_SEVERITIES = ("critical", "high", "medium", "low")
_EXPIRY_WARN_DAYS = 30


def _reason(exc):
    code = getattr(exc, "code", None)
    if code == 403:
        return "unavailable: token lacks required scope (403)"
    if code == 404:
        return "unavailable: resource not found (404)"
    return "unavailable"


def _count_by_severity(alerts, severity_of):
    counts = {level: 0 for level in _SEVERITIES}
    for alert in alerts:
        level = (severity_of(alert) or "").lower()
        if level in counts:
            counts[level] += 1
    return counts


def _code_scanning(github_get, headers, repo):
    try:
        alerts = github_get(
            f"/repos/{repo}/code-scanning/alerts?state=open&per_page=100", headers)
    except Exception as exc:
        return {"available": False, "detail": _reason(exc)}
    if not isinstance(alerts, list):
        return {"available": False, "detail": "unavailable: unexpected response"}
    counts = _count_by_severity(alerts, lambda a: (a.get("rule") or {}).get("security_severity_level"))
    return {"available": True, "counts": counts, "total": len(alerts)}


def _dependabot(github_get, headers, repo):
    try:
        alerts = github_get(
            f"/repos/{repo}/dependabot/alerts?state=open&per_page=100", headers)
    except Exception as exc:
        return {"available": False, "detail": _reason(exc)}
    if not isinstance(alerts, list):
        return {"available": False, "detail": "unavailable: unexpected response"}

    def severity_of(alert):
        advisory = alert.get("security_advisory") or {}
        vuln = alert.get("security_vulnerability") or {}
        return advisory.get("severity") or vuln.get("severity")

    counts = _count_by_severity(alerts, severity_of)
    numbers = sorted(a.get("number") for a in alerts if a.get("number") is not None)
    return {"available": True, "counts": counts, "total": len(alerts), "numbers": numbers}


def _branch_protection(github_get, headers, repo):
    try:
        data = github_get(f"/repos/{repo}/branches/main/protection", headers)
    except Exception as exc:
        return {"available": False, "detail": _reason(exc)}
    if not isinstance(data, dict):
        return {"available": False, "detail": "unavailable: unexpected response"}
    enforce = bool((data.get("enforce_admins") or {}).get("enabled"))
    reviews = int(((data.get("required_pull_request_reviews") or {})
                   .get("required_approving_review_count")) or 0)
    drift = []
    if not enforce:
        drift.append("enforce_admins off")
    if reviews < 1:
        drift.append(f"reviews={reviews} (<1)")
    return {"available": True, "enforce_admins": enforce, "reviews": reviews,
            "ok": not drift, "drift": drift}


def _credential(header_fetch, token, service, now):
    if not token:
        return {"service": service, "status": "credential unavailable"}
    try:
        headers = header_fetch("/", {"Authorization": f"token {token}"})
        raw = headers.get(GITHUB_EXPIRY_HEADER, "") if isinstance(headers, dict) else ""
    except Exception:
        return {"service": service, "status": "unavailable"}
    if not raw:
        return {"service": service, "status": "no expiry"}
    try:
        expires = _parse_expiry(raw)
    except Exception:
        return {"service": service, "status": "unparseable expiry"}
    return {"service": service, "status": "expires", "days": (expires - now).days,
            "expires_at": expires.isoformat().replace("+00:00", "Z")}


def _attention(report):
    items = []
    cs = report["code_scanning"]
    if not cs["available"]:
        items.append(f"code-scanning {cs['detail']}")
    elif cs["counts"]["critical"] or cs["counts"]["high"]:
        items.append(f"code-scanning {cs['counts']['critical']} critical / "
                     f"{cs['counts']['high']} high")
    db = report["dependabot"]
    if not db["available"]:
        items.append(f"dependabot {db['detail']}")
    elif db["total"]:
        numbers = ", ".join(f"#{n}" for n in db["numbers"])
        items.append(f"dependabot {db['total']} open ({numbers})")
    bp = report["branch_protection"]
    if not bp["available"]:
        items.append(f"branch-protection {bp['detail']}")
    elif bp["drift"]:
        items.append("branch-protection drift: " + ", ".join(bp["drift"]))
    for cred in report["credentials"]:
        if cred["status"] == "expires" and cred["days"] < _EXPIRY_WARN_DAYS:
            items.append(f"{cred['service']} expires in {cred['days']}d")
    return items


def run_audit(github_get, header_fetch, keychain, repo=REPOSITORY, now=None):
    """Run the read-only Group-A security audit and return (report_dict, digest_text).

    github_get(path, headers) -> parsed JSON (raises on HTTP error).
    header_fetch(path, headers) -> lowercased response-header dict (HEAD).
    keychain(service) -> token string ("" when absent).
    """
    now = now or datetime.now(timezone.utc)
    token = keychain(AUDIT_SERVICE)
    headers = {"Authorization": f"token {token}"} if token else {}
    unavailable = {"available": False, "detail": f"credential unavailable: {AUDIT_SERVICE}"}

    report = {
        "month": timestamp()[:7],
        "repo": repo,
        "code_scanning": _code_scanning(github_get, headers, repo) if token else dict(unavailable),
        "dependabot": _dependabot(github_get, headers, repo) if token else dict(unavailable),
        "branch_protection": _branch_protection(github_get, headers, repo) if token else dict(unavailable),
        "credentials": [
            _credential(header_fetch, token, AUDIT_SERVICE, now),
            _credential(header_fetch, keychain(GITHUB_SERVICE), GITHUB_SERVICE, now),
            {"service": WEBHOOK_SERVICE, "status": "no expiry"},
            {"service": ARGOCD_SERVICE, "status": "no expiry"},
        ],
    }
    report["attention"] = _attention(report)
    return report, _digest(report)


def monthly_audit_advisory(github_get, header_fetch, keychain, state, this_month,
                           repo=REPOSITORY, now=None):
    """Once-per-calendar-month gate (mirrors sensors.token_expiry_advisory).

    Returns the audit digest the first time `this_month` (YYYY-MM) is seen, then stamps
    state["last_security_audit_month"]; returns None (and makes no network call) on any
    later poll in the same month. The caller persists state and posts the digest.
    """
    if state.get("last_security_audit_month") == this_month:
        return None
    _report, digest = run_audit(github_get, header_fetch, keychain, repo=repo, now=now)
    state["last_security_audit_month"] = this_month
    return digest


def _severity_line(counts):
    return ", ".join(f"{counts[level]} {level}" for level in _SEVERITIES)


def _digest(report):
    lines = [f"🛡️ Hermes monthly security audit — {report['month']} ({report['repo']})"]

    cs = report["code_scanning"]
    if cs["available"]:
        lines.append(f"Code scanning: {_severity_line(cs['counts'])} open")
    else:
        lines.append(f"Code scanning: {cs['detail']}")

    db = report["dependabot"]
    if db["available"]:
        numbers = " (" + ", ".join(f"#{n}" for n in db["numbers"]) + ")" if db["numbers"] else ""
        lines.append(f"Dependabot: {_severity_line(db['counts'])} open{numbers}")
    else:
        lines.append(f"Dependabot: {db['detail']}")

    bp = report["branch_protection"]
    if bp["available"]:
        posture = f"enforce_admins={'on' if bp['enforce_admins'] else 'off'}, reviews={bp['reviews']}"
        lines.append(f"Branch protection: {posture}" + ("  ✅" if bp["ok"] else "  ⚠️"))
    else:
        lines.append(f"Branch protection: {bp['detail']}")

    creds = []
    for cred in report["credentials"]:
        if cred["status"] == "expires":
            creds.append(f"{cred['service']} in {cred['days']}d")
        else:
            creds.append(f"{cred['service']} = {cred['status']}")
    lines.append("Credentials: " + "; ".join(creds))

    attention = report["attention"]
    if attention:
        lines.append(f"Overall: {len(attention)} item(s) need attention → " + "; ".join(attention))
    else:
        lines.append("Overall: clean — no items need attention ✅")
    return "\n".join(lines)
