"""Hermes Phase 2: closed repair allowlist with human-approved execution.

No repair runs outside approve(); the poll cycle only proposes. See
docs/architecture/hermes-phase2-repair-scope.md. Phase 3 (cooldowns, budgets,
durable audit, auto-verification) is NOT implemented and needs its own scope doc.
"""

import hashlib
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
import shlex
import subprocess

from hermes.records import timestamp
from hermes.sensors import GITHUB_SERVICE, _keychain_secret

ROOT = Path(__file__).resolve().parents[3]
WEBHOOK_LABEL = "com.k3d-manager.webhook"
HUB_K3S_CONTAINER = "k3d-k3d-cluster-server-0"
# Public host -> the launchd label listening on cloudflared's ingress port.
# prometheus.3ai-talk.org enters at :19090 on the auth proxy
# (com.k3d-manager.prometheus-auth-proxy); that proxy forwards to the backend
# port-forward on :19091. The other public hosts are served by different
# mechanisms (argocd via port-forward-wrapper.sh, keycloak/grafana/frontend by
# their own services), and alertmanager's ingress (:9093) does not match its
# PF listen port (:19093), so R2 is not proposable for them.
PORT_FORWARD_LABELS = {
    "prometheus.3ai-talk.org": "com.k3d-manager.prometheus-auth-proxy",
}
R10_NAMESPACES = ("identity", "monitoring", "cicd")
R10_NAME = re.compile(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?")
PROPOSAL_TTL = timedelta(minutes=30)


def _git_revision(ref):
    """Resolve a commit from this Hermes checkout without fetching."""
    try:
        result = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet",
                                 f"{ref}^{{commit}}"], capture_output=True, text=True,
                                check=False, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def _utc_now():
    return datetime.now(timezone.utc)


def _parse_utc(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _expired(proposal):
    try:
        return _utc_now() > _parse_utc(proposal.get("expires_at", ""))
    except (TypeError, ValueError):
        return True


VOLATILE_DATA_FIELDS = {"kine": frozenset(("last_compaction_ts", "state_db_bytes", "slow_sql_count"))}


def _records_digest(records, reads):
    selected = {}
    for item in records:
        sensor = item.get("sensor")
        if sensor not in reads:
            continue
        volatile = VOLATILE_DATA_FIELDS.get(sensor, frozenset())
        data = {key: value for key, value in (item.get("data") or {}).items()
                if key not in volatile}
        selected[sensor] = {"sensor": sensor, "status": item.get("status"), "data": data}
    encoded = json.dumps(selected, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(encoded.encode()).hexdigest()


def _rec(records, name):
    for item in records:
        if item.get("sensor") == name:
            return item
    return None


def _status(records, name):
    item = _rec(records, name)
    return item["status"] if item else "unknown"


def _sustained(history, predicate, cycles):
    """True if `predicate(cycle_degraded_list)` held for the last `cycles` cycles."""
    window = history[-cycles:]
    return len(window) >= cycles and all(predicate(cycle) for cycle in window)


def _unknown_webhook(records):
    eso = _rec(records, "eso")
    data = _rec(records, "data_layer")
    return (_status(records, "eso") == "unknown" and
            _status(records, "data_layer") == "unknown" and
            "source unavailable" in (eso or {}).get("evidence", "").lower() and
            "source unavailable" in (data or {}).get("evidence", "").lower())


def _r1_precondition(records, _history, state):
    return _unknown_webhook(records) and state.get("repair_debounce", {}).get("r1", 0) > 1


def _r2_label(records):
    reachability = _rec(records, "reachability") or {}
    hosts = reachability.get("data", {}).get("failed_hosts", [])
    labels = {PORT_FORWARD_LABELS[host] for host in hosts if host in PORT_FORWARD_LABELS}
    return next(iter(labels)) if len(hosts) == 1 and len(labels) == 1 else ""


def _r2_precondition(records, _history, _state):
    reachability = _rec(records, "reachability") or {}
    return (_status(records, "reachability") == "degraded" and
            reachability.get("data", {}).get("verdict") == "single-service" and
            _status(records, "node_pressure") == "healthy" and
            _status(records, "data_layer") != "degraded" and bool(_r2_label(records)))


def _r3_precondition(records, history, _state):
    reachability = _rec(records, "reachability") or {}
    return (_status(records, "reachability") == "degraded" and
            reachability.get("data", {}).get("verdict") == "edge-down" and
            _sustained(history, lambda cycle: "reachability" in cycle, 2))


def _r4_precondition(records, _history, _state):
    ci = _rec(records, "ci") or {}
    data = ci.get("data", {})
    return (_status(records, "ci") == "degraded" and
            bool(data.get("run_id")) and bool(data.get("repo")) and
            data.get("conclusion") in ("timed_out", "cancelled", "stuck"))


def _r5_precondition(records, _history, _state):
    kine = _rec(records, "kine") or {}
    data = kine.get("data", {})
    return (_status(records, "kine") == "degraded" and
            data.get("stale_acg_registration") is True and
            data.get("state_db_bytes", 0) >= 8 * 1024 * 1024 * 1024)


def _r1_command(_records):
    return ["make", "restart-webhook"], {}


def _r2_command(records):
    # kickstart takes a service target (gui/<uid>/<label>); a bare label is rejected.
    return ["launchctl", "kickstart", "-k", f"gui/{os.getuid()}/{_r2_label(records)}"], {}


def _r3_command(_records):
    # The private provider lever is not dispatcher-routable; this public wrapper
    # calls only _hostinger_refresh_access_layer for the Hostinger provider.
    return ["scripts/k3d-manager", "refresh_access_layer"], {}


def _r4_command(records):
    data = (_rec(records, "ci") or {}).get("data", {})
    token = _keychain_secret(GITHUB_SERVICE)
    return (["gh", "api", "--method", "POST",
             f"/repos/{data['repo']}/actions/runs/{data['run_id']}/rerun-failed-jobs"],
            {"GH_TOKEN": token})


def _r5_command(_records):
    return (["kubectl", "--context", "k3d-k3d-cluster", "-n", "cicd", "scale",
             "statefulset/argocd-application-controller", "--replicas=0"], {})


def _compaction_stalled(data):
    """True when Kine reports compaction failing or not progressing under load."""
    return (data.get("compaction_failed") is True or
            (data.get("slow_sql_count", 0) > 0 and
             data.get("compaction_recent") is False))


def _r6_precondition(records, _history, _state):
    kine = _rec(records, "kine") or {}
    return (_status(records, "kine") == "degraded" and
            _compaction_stalled(kine.get("data", {})))


def _r6_command(_records):
    return (["docker", "restart", HUB_K3S_CONTAINER], {})


def _r7_precondition(records, history, _state):
    eso = _rec(records, "eso") or {}
    return (_status(records, "eso") == "degraded" and
            "cosign-public-key" in eso.get("evidence", "").lower() and
            _sustained(history, lambda cycle: "eso" in cycle, 2))


def _r7_command(_records):
    return (["make", "signing-restore"], {})


def _r8_precondition(records, _history, _state):
    drift = _rec(records, "hostnet_drift") or {}
    return (_status(records, "hostnet_drift") == "degraded" and
            any(item.get("owner_kind") == "DaemonSet"
                for item in drift.get("data", {}).get("drifted", [])))


def _r8_command(_records):
    return (["bin/k3dm-hostnet-drift", "--fix"], {})


def _r9_precondition(records, _history, _state):
    item = _rec(records, "values_branch") or {}
    expected = item.get("data", {}).get("expected", "")
    return (_status(records, "values_branch") == "degraded" and
            bool(item.get("data", {}).get("stale")) and expected == "deploy/hub")


def _r9_command(records):
    return (["./scripts/k3d-manager", "deploy_argocd_applicationsets", "--confirm"],
            {"K3D_MANAGER_BRANCH": "deploy/hub"})


def _r10_targets(records):
    item = _rec(records, "superseded_jobs") or {}
    data = item.get("data", {})
    context = data.get("context")
    for namespace in sorted(R10_NAMESPACES):
        names = sorted({job.get("name") for job in data.get("jobs", [])
                        if isinstance(job, dict) and job.get("namespace") == namespace
                        and isinstance(job.get("name"), str)
                        and len(job["name"]) <= 63
                        and R10_NAME.fullmatch(job["name"])})
        if names and context:
            return context, namespace, names
    return None


def _r10_precondition(records, _history, _state):
    return _status(records, "superseded_jobs") == "degraded" and _r10_targets(records) is not None


def _r10_command(records):
    context, namespace, names = _r10_targets(records)
    return (["kubectl", "--context", context, "-n", namespace, "delete", "job", "--wait=false", "--", *names], {})


REPAIRS = {
    "r1": {"key": "r1", "name": "Restart webhook", "precondition": _r1_precondition,
           "build_command": _r1_command, "cwd": ROOT,
           "reads": ("eso", "data_layer"),
           "blast_radius": "one local webhook LaunchAgent", "reversible": True,
           "needs_scope": None},
    "r2": {"key": "r2", "name": "Kick zombie port-forward", "precondition": _r2_precondition,
           "build_command": _r2_command, "cwd": None,
           "reads": ("reachability", "node_pressure", "data_layer"),
           "blast_radius": "one local port-forward LaunchAgent", "reversible": True,
           "needs_scope": None},
    "r3": {"key": "r3", "name": "Refresh Hostinger edge access layer", "precondition": _r3_precondition,
           "build_command": _r3_command, "cwd": ROOT,
           "reads": ("reachability",),
           "blast_radius": "local edge and port-forward access layer", "reversible": True,
           "needs_scope": None},
    "r4": {"key": "r4", "name": "Rerun transient CI jobs", "precondition": _r4_precondition,
           "build_command": _r4_command, "cwd": None,
           "reads": ("ci",),
           "blast_radius": "one GitHub Actions run re-execution", "reversible": True,
           "needs_scope": "actions:write"},
    "r5": {"key": "r5", "name": "Quarantine stale ACG reconciliation", "precondition": _r5_precondition,
           "build_command": _r5_command, "cwd": None,
           "reads": ("kine",),
           "blast_radius": "hub ArgoCD application controller; GitOps reconciliation pauses", "reversible": True,
           "needs_scope": "local hub kubeconfig"},
    # Proposal-only on purpose. The 2026-09-11 incident established that pausing
    # the ArgoCD controller (R5) relieves Kine pressure but does NOT revive a
    # stalled compaction goroutine -- only restarting the K3s server did. R5 is
    # therefore the wrong lever for a stall, and this one is never auto-executed:
    # restarting the control plane is a human decision.
    "r6": {"key": "r6", "name": "Restart hub K3s server to revive stalled Kine compaction",
           "precondition": _r6_precondition, "build_command": _r6_command, "cwd": None,
           "reads": ("kine",),
           "blast_radius": "hub control plane restarts; brief apiserver outage", "reversible": False,
           "needs_scope": "local docker socket"},
    "r7": {"key": "r7", "name": "Restore cosign signing key and ESO grant",
           "precondition": _r7_precondition, "build_command": _r7_command, "cwd": ROOT,
           "reads": ("eso",),
           "blast_radius": "Vault secret/cosign/signing, cosign-verify policy, ESO role grant, one ExternalSecret resync",
           "reversible": True, "needs_scope": "macOS Keychain (k3d-manager-signing), local hub kubeconfig"},
    "r8": {"key": "r8", "name": "Recycle drifted host-network DaemonSet pods",
           "precondition": _r8_precondition, "build_command": _r8_command, "cwd": ROOT,
           "reads": ("hostnet_drift",),
           "blast_radius": "DaemonSet pods on stale node IPs are recreated", "reversible": True,
           "needs_scope": "local hub kubeconfig"},
    "r9": {"key": "r9", "name": "Reapply ApplicationSets pinned to deploy/hub",
           "precondition": _r9_precondition, "build_command": _r9_command, "cwd": ROOT,
           "reads": ("values_branch",),
           "blast_radius": "every k3d-manager-sourced Application on the hub and app cluster re-targets deploy/hub and syncs",
           "reversible": False, "needs_scope": "local hub kubeconfig"},
    "r10": {"key": "r10", "name": "Delete failed Jobs superseded by a newer CronJob spec",
            "precondition": _r10_precondition, "build_command": _r10_command, "cwd": None,
            "reads": ("superseded_jobs",),
            "blast_radius": "named failed Job objects (and their finished pods) in one allowlisted namespace; CronJobs untouched",
            "reversible": False, "needs_scope": "local hub kubeconfig"},
}


def _update_r1_debounce(records, state):
    debounce = state.setdefault("repair_debounce", {})
    debounce["r1"] = debounce.get("r1", 0) + 1 if _unknown_webhook(records) else 0


def _evidence(records, key):
    relevant = {"r1": ("eso", "data_layer"), "r2": ("reachability", "node_pressure", "data_layer"),
                "r3": ("reachability",), "r4": ("ci",), "r5": ("kine",),
                "r6": ("kine",), "r7": ("eso",), "r8": ("hostnet_drift",),
                "r9": ("values_branch",), "r10": ("superseded_jobs",)}[key]
    return "; ".join(item.get("evidence", "") for item in records
                     if item.get("sensor") in relevant)


def propose(records, state):
    """Store and return pending allowlisted repair proposals without executing them."""
    _update_r1_debounce(records, state)
    history = state.setdefault("correlation_history", [])
    pending = state.setdefault("pending_repairs", {})
    attempted = state.setdefault("repairs_attempted_this_incident", [])
    proposals = []
    for key, repair in REPAIRS.items():
        if key in attempted or not repair["precondition"](records, history, state):
            continue
        argv, _env = repair["build_command"](records)
        command = shlex.join(argv)
        proposed_at = timestamp()
        action_id = f"{key}-" + hashlib.sha1((key + command).encode()).hexdigest()[:8]
        proposal = {"action_id": action_id, "key": key, "name": repair["name"],
                    "command": command, "blast_radius": repair["blast_radius"],
                    "proposed_at": proposed_at,
                    "expires_at": (_parse_utc(proposed_at) + PROPOSAL_TTL).isoformat().replace("+00:00", "Z"),
                    "records_digest": _records_digest(records, repair["reads"]),
                    "hermes_revision": _git_revision("HEAD"),
                    "deploy_hub_revision": (_git_revision("refs/remotes/origin/deploy/hub")
                                             if key == "r9" else ""),
                    "evidence": _evidence(records, key)}
        pending[action_id] = proposal
        proposals.append(proposal)
    return proposals


def _webhook_agent_present():
    try:
        result = subprocess.run(["launchctl", "list"], capture_output=True, text=True,
                                check=False, timeout=10)
        return result.returncode == 0 and WEBHOOK_LABEL in result.stdout
    except (OSError, subprocess.SubprocessError):
        return False


def approve(action_id, state, records_now, runner):
    """Re-validate and execute one pending, allowlisted repair after human approval."""
    proposal = state.setdefault("pending_repairs", {}).get(action_id)
    if not proposal:
        return {"outcome": "refused: unknown action-id", "action_id": action_id}
    state["pending_repairs"].pop(action_id, None)
    key = proposal.get("key")
    repair = REPAIRS.get(key)
    if not repair:
        return {"outcome": "refused: action is not allowlisted", "action_id": action_id}
    if key in state.get("repairs_attempted_this_incident", []):
        return {"outcome": "refused: repair already attempted this incident", "action_id": action_id}
    if _expired(proposal):
        return {"outcome": "refused: proposal expired", "action_id": action_id}
    current_revision = _git_revision("HEAD")
    if not proposal.get("hermes_revision") or not current_revision or proposal["hermes_revision"] != current_revision:
        return {"outcome": "refused: Hermes code revision changed", "action_id": action_id}
    if key == "r9":
        stored_deploy = proposal.get("deploy_hub_revision", "")
        current_deploy = _git_revision("refs/remotes/origin/deploy/hub")
        if not stored_deploy or not current_deploy:
            return {"outcome": "refused: deploy-ref-unknown", "action_id": action_id}
        if stored_deploy != current_deploy:
            return {"outcome": "refused: deploy-ref-moved", "action_id": action_id}
    history = state.setdefault("correlation_history", [])
    if not repair["precondition"](records_now, history, state):
        return {"outcome": "refused: precondition no longer holds", "action_id": action_id}
    if key == "r1" and not _webhook_agent_present():
        return {"outcome": "refused: webhook LaunchAgent not present", "action_id": action_id}

    argv, env = repair["build_command"](records_now)
    if shlex.join(argv) != proposal["command"]:
        return {"outcome": "refused: command changed since proposal", "action_id": action_id}
    if proposal.get("records_digest") != _records_digest(records_now, repair["reads"]):
        return {"outcome": "refused: sensor records changed since proposal", "action_id": action_id}
    if key == "r4" and not env.get("GH_TOKEN"):
        return {"outcome": "skipped: hermes GitHub token unavailable", "action_id": action_id}
    command = shlex.join(argv)
    rc, output = runner(argv, env, repair["cwd"])
    audit = {"action_id": action_id, "command": command, "key": key,
             "approved_at": timestamp(), "rc": rc}
    state.setdefault("repair_audit", []).append(audit)
    state.setdefault("repairs_attempted_this_incident", []).append(key)
    if key == "r4" and "resource not accessible" in output.lower():
        return {"outcome": "skipped: token lacks actions:write", "action_id": action_id,
                "rc": rc}
    return {"outcome": "executed" if rc == 0 else "failed", "action_id": action_id,
            "rc": rc, "output": output}


def auto_remediate_kine(records, state, runner, enabled=False):
    """Execute only the opt-in, bounded Kine circuit breaker once per incident."""
    if not enabled or "r5" in state.get("repairs_attempted_this_incident", []):
        return None
    repair = REPAIRS["r5"]
    if not repair["precondition"](records, state.get("correlation_history", []), state):
        return None
    argv, env = repair["build_command"](records)
    rc, output = runner(argv, env, repair["cwd"])
    action_id = "r5-" + hashlib.sha1(("r5" + shlex.join(argv)).encode()).hexdigest()[:8]
    state.setdefault("pending_repairs", {}).pop(action_id, None)
    state.setdefault("repair_audit", []).append(
        {"action_id": action_id, "command": shlex.join(argv), "key": "r5",
         "approved_at": timestamp(), "rc": rc, "automatic": True})
    state.setdefault("repairs_attempted_this_incident", []).append("r5")
    return {"outcome": "executed" if rc == 0 else "failed", "action_id": action_id,
            "rc": rc, "output": output, "automatic": True}
