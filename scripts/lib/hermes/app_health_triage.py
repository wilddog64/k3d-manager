"""Pure, rule-based triage for Hermes app-health deltas."""

from hermes.e2e_triage import group_slug, redact

_KIND = "health-probe-gap"


def triage(down_components):
    """One group per service whose aggregate health disagrees with its probe groups."""
    groups = []
    for service in sorted(down_components or {}):
        components = [redact(name) for name in (down_components[service] or [])]
        target = redact(service)
        groups.append({
            "kind": _KIND,
            "target": target,
            "slug": group_slug(_KIND, target),
            "count": len(components) or 1,
            "titles": [{"file": name, "title": f"{name} reports DOWN"} for name in components[:10]],
            "samples": [f"aggregate /actuator/health is not UP while liveness and readiness are UP; "
                        f"DOWN component(s): {', '.join(components) or 'not reported'}"],
        })
    return groups
