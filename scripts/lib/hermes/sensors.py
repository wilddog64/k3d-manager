"""Read-only Hermes sensors; callers inject transport functions for testability."""

import json
import subprocess
from datetime import datetime, timezone

from hermes.records import record

WEBHOOK_SERVICE = "k3dm-webhook-token"
ARGOCD_SERVICE = "k3dm-hermes-argocd-token"
GITHUB_SERVICE = "k3dm-hermes-gh-token"


def _keychain_secret(service):
    """Read one existing Keychain item without exposing its value in agent argv."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", "k3dm", "-s", service, "-w"],
            capture_output=True, text=True, timeout=10, check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _debounced(sensor, raw_degraded, threshold, state):
    counts = state.setdefault("debounce", {})
    counts[sensor] = counts.get(sensor, 0) + 1 if raw_degraded else 0
    return counts[sensor] > threshold


def _unavailable(sensor, service):
    return record(sensor, "unknown", f"credential unavailable: {service}")


def _webhook_services(fetch, token, provider):
    url = f"https://{provider}/api/v1/health" if provider else "/api/v1/health"
    payload = fetch(url, {"Authorization": f"Bearer {token}"})
    if not isinstance(payload, dict) or not isinstance(payload.get("services"), list):
        raise ValueError("invalid webhook payload")
    return payload


def eso(fetch, state, provider="", token=None, threshold=2):
    token = token if token is not None else _keychain_secret(WEBHOOK_SERVICE)
    if not token:
        return _unavailable("eso", WEBHOOK_SERVICE)
    try:
        services = _webhook_services(fetch, token, provider)["services"]
        entries = [item for item in services if item.get("name") in
                   ("ESO ClusterSecretStore", "ESO ExternalSecrets")]
        if len(entries) != 2 or any(item.get("ok") is None for item in entries):
            return record("eso", "unknown", "ESO status source unavailable")
        failed = [item for item in entries if item.get("ok") is False]
        if failed:
            detail = "; ".join(item.get("detail", item["name"]) for item in failed)
            status = "degraded" if _debounced("eso", True, threshold, state) else "healthy"
            return record("eso", status, detail)
        _debounced("eso", False, threshold, state)
        return record("eso", "healthy", "; ".join(item.get("detail", item["name"]) for item in entries))
    except Exception:
        return record("eso", "unknown", "ESO status source unavailable")


def argocd(run, state, token=None, threshold=3, server="argocd.3ai-talk.org"):
    token = token if token is not None else _keychain_secret(ARGOCD_SERVICE)
    if not token:
        return _unavailable("argocd", ARGOCD_SERVICE)
    try:
        result = run(["argocd", "app", "list", "-o", "json", "--grpc-web"],
                     {"ARGOCD_AUTH_TOKEN": token, "ARGOCD_SERVER": server})
        code, output = result
        apps = json.loads(output) if code == 0 and output else None
        if not isinstance(apps, list):
            raise ValueError("invalid ArgoCD response")
        bad = []
        for app in apps:
            status = app.get("status", {})
            health = status.get("health", {}).get("status")
            sync = status.get("sync", {}).get("status")
            if health == "Degraded" or sync == "OutOfSync":
                bad.append(f"{app.get('project', 'default')}/{app.get('name', 'unnamed')} {health}/{sync}")
        if bad:
            status = "degraded" if _debounced("argocd", True, threshold, state) else "healthy"
            return record("argocd", status, ", ".join(bad[:3]))
        _debounced("argocd", False, threshold, state)
        return record("argocd", "healthy", f"{len(apps)} applications healthy")
    except Exception:
        return record("argocd", "unknown", "ArgoCD status source unavailable")


def reachability(run, state, threshold=2):
    try:
        code, output = run(["bin/public-endpoint-probe", "--json"], {})
        payload = json.loads(output) if output else {}
        verdict = payload.get("verdict")
        if code == 3 or verdict not in ("ok", "single-service", "edge-down"):
            raise ValueError("invalid probe output")
        if verdict == "ok":
            _debounced("reachability", False, threshold, state)
            return record("reachability", "healthy", "public endpoints healthy")
        hosts = payload.get("hosts", [])
        failed = sum(1 for host in hosts if not host.get("healthy"))
        status = "degraded" if _debounced("reachability", True, threshold, state) else "healthy"
        return record("reachability", status, f"{verdict} {failed}/{len(hosts)} hosts healthy")
    except Exception:
        return record("reachability", "unknown", "public probe source unavailable")


def node_pressure(fetch, state, provider="", token=None, threshold=2, service_threshold=2):
    token = token if token is not None else _keychain_secret(WEBHOOK_SERVICE)
    if not token:
        return _unavailable("node_pressure", WEBHOOK_SERVICE)
    try:
        payload = _webhook_services(fetch, token, provider)
        services = payload["services"]
        if not services or all(item.get("ok") is None for item in services):
            return record("node_pressure", "unknown", "node status source unavailable")
        failed = [item for item in services if item.get("ok") is False]
        data_layer = next((item for item in services if item.get("name") == "Data layer"), None)
        raw = bool(data_layer and data_layer.get("ok") is False) or len(failed) >= service_threshold
        if raw:
            detail = ", ".join(item.get("name", "unknown") for item in failed[:3])
            status = "degraded" if _debounced("node_pressure", True, threshold, state) else "healthy"
            return record("node_pressure", status, f"webhook failures: {detail}")
        _debounced("node_pressure", False, threshold, state)
        return record("node_pressure", "healthy", "webhook data layer and services healthy")
    except Exception:
        return record("node_pressure", "unknown", "node status source unavailable")


def _older_than(value, max_age_seconds, now):
    try:
        then = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return (now - then).total_seconds() > max_age_seconds
    except (AttributeError, TypeError, ValueError):
        return False


def ci(fetch, state, repos=None, token=None, threshold=1, max_age_seconds=3600, now=None):
    token = token if token is not None else _keychain_secret(GITHUB_SERVICE)
    if not token:
        return _unavailable("ci", GITHUB_SERVICE)
    repos = repos or ["wilddog64/k3d-manager"]
    now = now or datetime.now(timezone.utc)
    try:
        bad = []
        for repo_name in repos:
            run = fetch(f"/repos/{repo_name}/actions/runs", {"Authorization": f"token {token}"})
            runs = run.get("workflow_runs", []) if isinstance(run, dict) else []
            if not runs:
                raise ValueError("missing workflow run")
            latest = runs[0]
            checks = fetch(f"/repos/{repo_name}/commits/{latest['head_sha']}/check-runs",
                           {"Authorization": f"token {token}"})
            if not isinstance(checks, dict):
                raise ValueError("invalid checks")
            for check in checks.get("check_runs", []):
                if check.get("conclusion") in ("failure", "timed_out", "cancelled"):
                    bad.append(f"{repo_name} {check.get('name', 'check')} {check.get('conclusion')}")
                elif check.get("status") == "in_progress" and _older_than(
                        check.get("started_at"), max_age_seconds, now):
                    bad.append(f"{repo_name} {check.get('name', 'check')} stuck")
        if bad:
            status = "degraded" if _debounced("ci", True, threshold, state) else "healthy"
            return record("ci", status, ", ".join(bad[:3]))
        _debounced("ci", False, threshold, state)
        return record("ci", "healthy", "required CI checks successful")
    except Exception:
        return record("ci", "unknown", "CI status source unavailable")
