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
    # Q is base64 transported across Make's recipe boundary before decoding to argv.
    # Restrict it to printable ASCII so it is safe for logs and the retrieval CLI.
    "Q": re.compile(r"[!-~][\x20-\x7e]{0,199}"),
    "K": re.compile(r"[1-9]|[1-4][0-9]|50"),
    "SMOKE_ONLY": re.compile(r"offline|cluster"),
    # A DNS-style ArgoCD application prefix, including the separator before
    # the application name (for example, ubuntu-hostinger-).
    "ARGOCD_APP_PREFIX": re.compile(r"(?=.{2,64}\Z)[a-z0-9]+(?:-[a-z0-9]+)*-"),
}

MAKE_TARGETS = {
    "fix-list": {"min_role": "reader", "summary": "list fix targets"},
    "fix-status": {"min_role": "reader", "required": ("NS",), "optional": ("FIX_CONTEXT",), "summary": "node + pod status for a namespace"},
    "status-public": {"min_role": "reader", "summary": "probe public Cloudflare hostnames"},
    "observability-status": {"min_role": "reader", "summary": "monitoring/trivy-system pods on both clusters"},
    "vuln-scan": {"min_role": "reader", "summary": "VulnerabilityReport summary"},
    "e2e-runner-health": {"min_role": "reader", "optional": ("RUNNER",), "summary": "hub vs remote-runner health"},
    "test": {"min_role": "reader", "timeout": 1200, "summary": "offline BATS dispatcher suites"},
    "test-bin": {"min_role": "reader", "timeout": 300, "summary": "offline BATS suites under scripts/tests/bin"},
    "test-pytest": {"min_role": "reader", "timeout": 600, "summary": "offline pytest suites"},
    "test-python-unit": {"min_role": "reader", "summary": "offline unittest suites"},
    "test-python": {"min_role": "reader", "timeout": 900, "summary": "every offline Python suite"},
    "test-all": {"min_role": "reader", "timeout": 1800, "summary": "every offline suite (BATS + Python)"},
    "find-similar-docs": {"min_role": "reader", "required": ("Q",), "optional": ("K",), "timeout": 120, "summary": "search docs/ for prior art by similarity"},
    "index-docs": {"min_role": "operator", "timeout": 1800, "summary": "re-embed changed docs into the vector store"},
    "e2e-remote": {"min_role": "operator", "required": ("RUNNER",), "optional": ("DIGEST",), "timeout": 3600, "summary": "Tier 1 e2e on a remote runner"},
    "e2e": {"min_role": "operator", "optional": ("DIGEST",), "timeout": 3600, "summary": "Tier 1 e2e in a disposable vCluster"},
    "e2e-sandbox": {"min_role": "operator", "optional": ("DIGEST",), "timeout": 3600, "summary": "Tier 2 e2e on the live ACG sandbox"},
    "e2e-sandbox-provision": {"min_role": "admin", "confirm": True, "preview": "e2e-sandbox-provision-preview", "optional": ("DIGEST",), "timeout": 7200, "summary": "Tier 2 e2e; provisions the ACG sandbox first if it is missing"},
    "e2e-sandbox-provision-preview": {"min_role": "admin", "optional": ("DIGEST",), "timeout": 300, "summary": "read-only preview of e2e-sandbox-provision"},
    "e2e-replay": {"min_role": "operator", "required": ("RUNNER",), "timeout": 900, "summary": "replay retained runner results"},
    "sync-apps": {"min_role": "operator", "timeout": 600, "summary": "sync data-layer apps"},
    "smoke": {"min_role": "operator", "optional": ("SMOKE_ONLY", "ARGOCD_APP_PREFIX"), "timeout": 900, "summary": "run the smoke gate (offline always; cluster when reachable)"},
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

# The cluster lifecycle commands are NOT make targets. They are separate slash
# commands the relay routes to /api/v1/cluster, which reaches _run_cluster --
# the only path that carries the running-job guard, the stall timer and the
# Pushgateway metrics push. They are listed here for discoverability only:
# /k3dm help is the sole self-describing surface in Slack, and an operator who
# cannot see these commands cannot find the one that records a deployment.
# Roles mirror COMMAND_ROLES in workers/slack-relay/index.js -- keep in sync.
CLUSTER_COMMANDS = (
    ("/cluster-status [provider]", "reader", "cluster + access-layer status"),
    ("/cluster-diagnose [provider|hub] [verb]", "reader", "no verb: pods in all namespaces; pods, logs, apps, appsets"),
    ("/hostinger-status", "reader", "permanent app-cluster status"),
    ("/cluster-refresh [provider]", "operator", "refresh the access layer"),
    ("/cluster-up [provider]", "admin", "bring a cluster up (records deployment metrics)"),
    ("/cluster-down [provider]", "admin", "tear a cluster down (records deployment metrics)"),
    ("/cluster-resume [provider]", "admin", "resume a partially provisioned cluster"),
)


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
        if spec.get("preview"):
            return [spec["preview"], *assignments], None
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
            parts.append("[confirm]" if spec.get("preview") else "confirm")
        lines.append(f"• `{' '.join(parts)}` — {spec['summary']} ({spec['min_role']})")
    cluster_lines = [
        f"• `{name}` — {summary} ({min_role})"
        for name, min_role, summary in CLUSTER_COMMANDS
        if role_allows(role, min_role)
    ]
    if cluster_lines:
        lines.append("")
        lines.append("*Cluster lifecycle* — separate slash commands, not `/k3dm` targets:")
        lines.extend(cluster_lines)
    lines.append('Use `find-similar-docs Q="what\'s recent e2e-remote issues" [K=5]` for a natural-language search.')
    return "\n".join(lines)
