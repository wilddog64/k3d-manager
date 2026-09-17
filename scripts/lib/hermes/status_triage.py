"""Pure, rule-based triage for Hermes cluster-status results."""

import re

from hermes.e2e_triage import group_slug, redact

_EDGE = re.compile(r"HTTP (?:5\d\d|530)\b")


def classify(check):
    """Classify one status check by stable id before mutable message prose."""
    check_id = redact(check.get("id") or "unknown")
    message = str(check.get("message") or "")
    if check_id == "status_source":
        return "status-source", check_id
    if check_id.endswith("_sso_login") or check_id == "keycloak_admin_login":
        return "sso-auth", check_id
    if _EDGE.search(message):
        return "edge", check_id
    if check_id.endswith("_login"):
        return "credential", check_id
    if check_id.startswith(("eso_", "argocd_")):
        return "sync", check_id
    if check_id in ("data_layer", "product_images"):
        return "data", check_id
    return "service", check_id


def triage(checks):
    """Group failed checks into redacted issue-ready records; status source is R1."""
    groups = {}
    for check in checks or []:
        if not isinstance(check, dict):
            continue
        kind, target = classify(check)
        if kind == "status-source":
            continue
        group = groups.setdefault((kind, target), {
            "kind": kind, "target": target, "slug": group_slug(kind, target),
            "count": 0, "check_ids": [], "titles": [], "samples": [],
        })
        check_id = redact(check.get("id") or "unknown")
        message = redact(check.get("message") or "")
        group["count"] += 1
        group["check_ids"].append(check_id)
        if len(group["titles"]) < 10:
            group["titles"].append({"file": check_id, "title": message or check_id})
        if message and message not in group["samples"] and len(group["samples"]) < 3:
            group["samples"].append(message)
    return list(groups.values())
