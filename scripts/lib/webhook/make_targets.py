"""Allowlisted Makefile targets reachable from the Slack ``/k3dm`` command."""
import re

MAKE_JOB_TIMEOUT_DEFAULT = 300

_ARG_PATTERNS = {
    "RUNNER": re.compile(r"[a-z0-9][a-z0-9-]{0,31}"),
    "APP": re.compile(r"[a-z0-9]([-.a-z0-9]{0,251}[a-z0-9])?"),
    "NS": re.compile(r"[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?"),
    "DIGEST": re.compile(r"sha256:[0-9a-f]{64}"),
    "FIX_CONTEXT": re.compile(r"ubuntu-k3s|ubuntu-hostinger|k3d-k3d-cluster"),
    "CRONJOB": re.compile(r"app-cve-scan|argocd-cve-scan"),
}

MAKE_TARGETS = {
    "fix-list": {"min_role": "reader", "summary": "list fix targets"},
    "fix-status": {"min_role": "reader", "required": ("NS",), "optional": ("FIX_CONTEXT",), "summary": "node + pod status for a namespace"},
    "status-public": {"min_role": "reader", "summary": "probe public Cloudflare hostnames"},
    "observability-status": {"min_role": "reader", "summary": "monitoring/trivy-system pods on both clusters"},
    "vuln-scan": {"min_role": "reader", "summary": "VulnerabilityReport summary"},
    "e2e-runner-health": {"min_role": "reader", "optional": ("RUNNER",), "summary": "hub vs remote-runner health"},
    "test-pytest": {"min_role": "reader", "timeout": 600, "summary": "offline pytest suites"},
    "test-python-unit": {"min_role": "reader", "summary": "offline unittest suites"},
    "e2e-remote": {"min_role": "operator", "required": ("RUNNER",), "optional": ("DIGEST",), "timeout": 3600, "summary": "Tier 1 e2e on a remote runner"},
    "e2e-sandbox": {"min_role": "operator", "optional": ("DIGEST",), "timeout": 3600, "summary": "Tier 2 e2e on the live ACG sandbox"},
    "e2e-replay": {"min_role": "operator", "required": ("RUNNER",), "timeout": 900, "summary": "replay retained runner results"},
    "sync-apps": {"min_role": "operator", "timeout": 600, "summary": "sync data-layer apps"},
    "app-cve-scan": {"min_role": "operator", "timeout": 900, "optional": ("CRONJOB",), "summary": "trigger the app-cluster CVE scan now"},
    "monitoring-pause": {"min_role": "operator", "timeout": 600, "summary": "scale hub observability to zero"},
    "monitoring-resume": {"min_role": "operator", "timeout": 600, "summary": "restore paused hub observability"},
    "fix-restart": {"min_role": "operator", "required": ("APP", "NS"), "optional": ("FIX_CONTEXT",), "summary": "rollout restart a deployment"},
    "fix-sync": {"min_role": "operator", "required": ("APP",), "summary": "ArgoCD app sync"},
    "fix-eso-refresh": {"min_role": "operator", "optional": ("FIX_CONTEXT",), "summary": "force ESO ClusterSecretStore reconcile"},
    "e2e-runner-unlock": {"min_role": "admin", "confirm": True, "required": ("RUNNER",), "summary": "clear a stale remote-runner lock"},
    "fix-delete-pod": {"min_role": "admin", "confirm": True, "required": ("APP", "NS"), "optional": ("FIX_CONTEXT",), "summary": "delete pods with label app=APP"},
    "fix-force-sync": {"min_role": "admin", "confirm": True, "required": ("APP",), "summary": "ArgoCD force sync"},
}


def parse_make_request(target, args, confirm):
    """Validate a /k3dm request. Return (argv_tail, None) or (None, error_text)."""
    spec = MAKE_TARGETS.get(target)
    if spec is None:
        return None, f"unknown target `{target}` — try `/k3dm help`"
    if not isinstance(args, dict):
        return None, "args must be an object"
    required = spec.get("required", ())
    allowed = set(required) | set(spec.get("optional", ()))
    for key in args:
        if key not in allowed:
            return None, f"`{target}` does not accept {key}"
    for key in required:
        if key not in args:
            return None, f"`{target}` requires {key}=…"
    assignments = []
    for key in sorted(args):
        value = args[key]
        if not isinstance(value, str) or not _ARG_PATTERNS[key].fullmatch(value):
            return None, f"invalid value for {key}"
        assignments.append(f"{key}={value}")
    if spec.get("confirm") and confirm is not True:
        return None, f"`{target}` is destructive — rerun with `confirm`"
    return [target, *assignments], None


def make_target_help(role, role_allows):
    """Return one Slack line per target the role may run."""
    lines = []
    for name, spec in MAKE_TARGETS.items():
        if not role_allows(role, spec["min_role"]):
            continue
        parts = [name]
        parts += [f"{key}=…" for key in spec.get("required", ())]
        parts += [f"[{key}=…]" for key in spec.get("optional", ())]
        if spec.get("confirm"):
            parts.append("confirm")
        lines.append(f"• `{' '.join(parts)}` — {spec['summary']} ({spec['min_role']})")
    return "\n".join(lines)
