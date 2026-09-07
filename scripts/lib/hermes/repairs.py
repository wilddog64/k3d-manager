"""Hermes Phase 2: closed repair allowlist with human-approved execution.

No repair runs outside approve(); the poll cycle only proposes. See
docs/architecture/hermes-phase2-repair-scope.md. Phase 3 (cooldowns, budgets,
durable audit, auto-verification) is NOT implemented and needs its own scope doc.
"""

import hashlib
from pathlib import Path
import shlex
import subprocess

from hermes.records import timestamp
from hermes.sensors import GITHUB_SERVICE, _keychain_secret

ROOT = Path(__file__).resolve().parents[3]
WEBHOOK_LABEL = "com.k3d-manager.webhook"
# Public host -> the launchd port-forward label that actually serves it. Grounded
# in scripts/etc/cloudflared/config.yml (ingress local port) matched against the
# installed com.k3d-manager.*-port-forward.plist listen ports: only
# prometheus.3ai-talk.org (ingress :19090) maps cleanly to the prometheus PF
# (19090:9090). The other public hosts are served by different mechanisms
# (argocd via port-forward-wrapper.sh, keycloak/grafana/frontend by their own
# services) and alertmanager's ingress (:9093) does not match its PF listen port
# (:19093) -- none has a known launchd PF label, so R2 is not proposable for them.
PORT_FORWARD_LABELS = {
    "prometheus.3ai-talk.org": "com.k3d-manager.prometheus-port-forward",
}


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
    node = _rec(records, "node_pressure")
    return (_status(records, "eso") == "unknown" and
            _status(records, "node_pressure") == "unknown" and
            "source unavailable" in (eso or {}).get("evidence", "").lower() and
            "source unavailable" in (node or {}).get("evidence", "").lower())


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
            _status(records, "node_pressure") == "healthy" and bool(_r2_label(records)))


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


def _r1_command(_records):
    return ["make", "restart-webhook"], {}


def _r2_command(records):
    return ["launchctl", "kickstart", "-k", _r2_label(records)], {}


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


REPAIRS = {
    "r1": {"key": "r1", "name": "Restart webhook", "precondition": _r1_precondition,
           "build_command": _r1_command, "cwd": ROOT,
           "blast_radius": "one local webhook LaunchAgent", "reversible": True,
           "needs_scope": None},
    "r2": {"key": "r2", "name": "Kick zombie port-forward", "precondition": _r2_precondition,
           "build_command": _r2_command, "cwd": None,
           "blast_radius": "one local port-forward LaunchAgent", "reversible": True,
           "needs_scope": None},
    "r3": {"key": "r3", "name": "Refresh Hostinger edge access layer", "precondition": _r3_precondition,
           "build_command": _r3_command, "cwd": ROOT,
           "blast_radius": "local edge and port-forward access layer", "reversible": True,
           "needs_scope": None},
    "r4": {"key": "r4", "name": "Rerun transient CI jobs", "precondition": _r4_precondition,
           "build_command": _r4_command, "cwd": None,
           "blast_radius": "one GitHub Actions run re-execution", "reversible": True,
           "needs_scope": "actions:write"},
}


def _update_r1_debounce(records, state):
    debounce = state.setdefault("repair_debounce", {})
    debounce["r1"] = debounce.get("r1", 0) + 1 if _unknown_webhook(records) else 0


def _evidence(records, key):
    relevant = {"r1": ("eso", "node_pressure"), "r2": ("reachability", "node_pressure"),
                "r3": ("reachability",), "r4": ("ci",)}[key]
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
                    "proposed_at": proposed_at, "evidence": _evidence(records, key)}
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
    history = state.setdefault("correlation_history", [])
    if not repair["precondition"](records_now, history, state):
        return {"outcome": "refused: precondition no longer holds", "action_id": action_id}
    if key == "r1" and not _webhook_agent_present():
        return {"outcome": "refused: webhook LaunchAgent not present", "action_id": action_id}

    argv, env = repair["build_command"](records_now)
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
