"""Read-only Hermes sensors; callers inject transport functions for testability."""

import base64
import binascii
import json
import os
import subprocess
import time
import re
from datetime import datetime, timezone

from hermes.records import record
from hermes.e2e_triage import redact

WEBHOOK_SERVICE = "k3dm-webhook-token"
ARGOCD_SERVICE = "k3dm-hermes-argocd-token"
GITHUB_SERVICE = "k3dm-hermes-gh-token"
TERMINAL_OPERATION_FAILURES = ("Error", "Failed")
RELEASE_BRANCH = re.compile(r"\Ak3d-manager-v\d+\.\d+\.\d+\Z")


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
    url = f"http://{provider}/api/v1/health" if provider else "/api/v1/health"
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
        entries = [item for item in services
                   if isinstance(item.get("name"), str)
                   and item["name"].endswith(("ESO ClusterSecretStore", "ESO ExternalSecrets"))]
        graded = [item for item in entries if item.get("ok") is not None]
        if not graded:
            return record("eso", "unknown", "ESO status source unavailable")
        failed = [item for item in graded if item.get("ok") is False]
        if failed:
            detail = "; ".join(item.get("detail", item["name"]) for item in failed)
            status = "degraded" if _debounced("eso", True, threshold, state) else "healthy"
            return record("eso", status, detail)
        _debounced("eso", False, threshold, state)
        return record("eso", "healthy", "; ".join(item.get("detail", item["name"]) for item in graded))
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
        if code != 0 and "Unauthenticated" in (output or ""):
            return record("argocd", "unknown",
                          f"ArgoCD status source unavailable: credential rejected; re-mint {ARGOCD_SERVICE}")
        apps = json.loads(output) if code == 0 and output else None
        if not isinstance(apps, list):
            raise ValueError("invalid ArgoCD response")
        bad = []
        for app in apps:
            status = app.get("status", {})
            health = status.get("health", {}).get("status")
            sync = status.get("sync", {}).get("status")
            phase = status.get("operationState", {}).get("phase")
            name = app.get("name") or app.get("metadata", {}).get("name", "unnamed")
            project = app.get("project") or app.get("spec", {}).get("project", "default")
            if health == "Degraded" or sync == "OutOfSync":
                bad.append(f"{project}/{name} {health}/{sync}")
            elif phase in TERMINAL_OPERATION_FAILURES:
                bad.append(f"{project}/{name} {health}/{sync} last-op={phase}")
        if bad:
            status = "degraded" if _debounced("argocd", True, threshold, state) else "healthy"
            detail = ", ".join(bad[:3])
            if len(bad) > 3:
                detail = f"{detail} (+{len(bad) - 3} more)"
            return record("argocd", status, detail)
        _debounced("argocd", False, threshold, state)
        return record("argocd", "healthy", f"{len(apps)} applications healthy")
    except Exception:
        return record("argocd", "unknown", "ArgoCD status source unavailable")


def _values_branch_expected(run, expected=None):
    if expected:
        return expected, None
    configured = os.environ.get("K3DM_RELEASE_BRANCH", "").strip()
    if configured:
        return configured, None
    try:
        code, output = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], {})
        if code != 0 or not output.strip():
            return None, "checkout branch could not be determined"
        return output.strip(), None
    except Exception:
        return None, "checkout branch could not be determined"


def values_branch(run, argocd_run, state, token=None, expected=None, threshold=3,
                  server="argocd.3ai-talk.org"):
    """Check k3d-manager Application sources against the checked-out release branch."""
    branch, error = _values_branch_expected(run, expected)
    if error:
        return record("values_branch", "unknown", error)
    if not RELEASE_BRANCH.fullmatch(branch):
        return record("values_branch", "healthy",
                      f"skipped: checkout on {branch}, not a release branch",
                      data={"expected": branch, "skipped": True})
    token = token if token is not None else _keychain_secret(ARGOCD_SERVICE)
    if not token:
        return _unavailable("values_branch", ARGOCD_SERVICE)
    try:
        code, output = argocd_run(["argocd", "app", "list", "-o", "json", "--grpc-web"],
                                  {"ARGOCD_AUTH_TOKEN": token, "ARGOCD_SERVER": server})
        if code != 0:
            if "Unauthenticated" in (output or ""):
                return record("values_branch", "unknown",
                              f"ArgoCD status source unavailable: credential rejected; re-mint {ARGOCD_SERVICE}")
            return record("values_branch", "unknown", "ArgoCD status source unavailable")
        apps = json.loads(output) if output else None
        if not isinstance(apps, list):
            raise ValueError("invalid ArgoCD response")
        stale = []
        checked = 0
        tracking_head = 0
        for app in apps:
            spec = app.get("spec", {}) if isinstance(app, dict) else {}
            sources = spec.get("sources") or ([spec["source"]] if "source" in spec else [])
            for source in sources:
                if not isinstance(source, dict) or "github.com/wilddog64/k3d-manager" not in source.get("repoURL", ""):
                    continue
                revision = source.get("targetRevision", "")
                if revision == "HEAD":
                    tracking_head += 1
                    continue
                checked += 1
                if revision != branch:
                    name = app.get("name") or app.get("metadata", {}).get("name", "unnamed")
                    stale.append({"app": name, "revision": revision})
        data = {"expected": branch, "stale": stale, "checked": checked,
                "tracking_head": tracking_head}
        if checked == 0:
            return record("values_branch", "unknown", "no k3d-manager references found", data=data)
        if stale:
            status = "degraded" if _debounced("values_branch", True, max(1, threshold - 1), state) else "healthy"
            names = ", ".join(f"{item['app']}@{item['revision']}" for item in stale[:3])
            if len(stale) > 3:
                names += f" (+{len(stale) - 3} more)"
            return record("values_branch", status,
                          f"{len(stale)} apps not on {branch}: {names}", data=data)
        _debounced("values_branch", False, threshold, state)
        return record("values_branch", "healthy", f"{checked} references on {branch}", data=data)
    except Exception:
        return record("values_branch", "unknown", "ArgoCD status source unavailable")


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
        failed_hosts = [host.get("host") or host.get("name") or host.get("url")
                        for host in hosts if not host.get("healthy")]
        status = "degraded" if _debounced("reachability", True, threshold, state) else "healthy"
        evidence = f"{verdict} {failed}/{len(hosts)} hosts failing"
        if failed_hosts:
            evidence += ": " + ", ".join(str(host) for host in failed_hosts[:5])
        return record("reachability", status, evidence,
                      data={"verdict": verdict,
                            "failed_hosts": [host for host in failed_hosts if host]})
    except Exception:
        return record("reachability", "unknown", "public probe source unavailable")


def _redact_status(value):
    """Sanitize the entire JSON boundary before records can reach stdout or state."""
    if isinstance(value, str):
        return redact(value)
    if isinstance(value, list):
        return [_redact_status(item) for item in value]
    if isinstance(value, dict):
        return {redact(key): _redact_status(item) for key, item in value.items()}
    return value


def status_checks(run, state, threshold=2):
    """Sample the machine-readable cluster status contract without scraping text."""
    try:
        code, output = run(["bin/cluster-status", "--json"], {})
        payload = _redact_status(json.loads(output)) if code in (0, 1, 2) and output else {}
        overall = payload.get("overall")
        checks = payload.get("checks", [])
        counts = payload.get("counts", {})
        if overall not in ("healthy", "warn", "fail", "unknown") or not isinstance(checks, list):
            raise ValueError("invalid status output")
        failed = [item for item in checks if isinstance(item, dict) and item.get("status") == "error"]
        warned = [item for item in checks if isinstance(item, dict) and item.get("status") == "warning"]
        data = {"failed_ids": [item.get("id") for item in failed if item.get("id")],
                "warned_ids": [item.get("id") for item in warned if item.get("id")],
                "counts": counts if isinstance(counts, dict) else {}, "checks": failed}
        if overall == "unknown":
            return record("status_checks", "unknown", "cluster status source unavailable", data=data)
        if overall == "fail":
            status = "degraded" if _debounced("status_checks", True, threshold - 1, state) else "healthy"
            return record("status_checks", status, f"{len(failed)} status checks failing", data=data)
        _debounced("status_checks", False, threshold, state)
        evidence = "status warnings present" if overall == "warn" else "cluster status healthy"
        return record("status_checks", "healthy", evidence, data=data)
    except Exception:
        return record("status_checks", "unknown", "cluster status source unavailable")


APP_HEALTH_PROBE_GROUPS = ("liveness", "readiness")


def _health_payload(run, context, namespace, service, port, path):
    """Read one actuator endpoint through the API server's service proxy."""
    proxy = f"/api/v1/namespaces/{namespace}/services/{service}:{port}/proxy{path}"
    code, output = run(["kubectl", "--context", context, "get", "--raw", proxy], {})
    if code != 0 or not output:
        return None
    payload = json.loads(output)
    return payload if isinstance(payload, dict) else None


def _health_delta(run, context, target):
    """Return (delta_detail, down_components) for one service; delta_detail is '' when none."""
    namespace = target["namespace"]
    service = target["service"]
    port = target["port"]
    aggregate = _health_payload(run, context, namespace, service, port, "/actuator/health")
    if aggregate is None or not aggregate.get("status"):
        raise ValueError(f"{service}: aggregate health unavailable")
    if aggregate["status"] == "UP":
        return "", []
    groups = {}
    for group in APP_HEALTH_PROBE_GROUPS:
        payload = _health_payload(run, context, namespace, service, port,
                                  f"/actuator/health/{group}")
        if payload is None or not payload.get("status"):
            raise ValueError(f"{service}: {group} group unavailable")
        groups[group] = payload["status"]
    if any(value != "UP" for value in groups.values()):
        return "", []
    components = aggregate.get("components") or {}
    down = sorted(name for name, body in components.items()
                  if isinstance(body, dict) and body.get("status") not in (None, "UP"))
    return f"{service} aggregate {aggregate['status']} while both probe groups UP", down


def app_health(run, state, targets=None, context="", threshold=2):
    """Flag services whose aggregate health disagrees with the probe groups k8s polls."""
    if not targets:
        return record("app_health", "unknown", "no app health targets configured")
    if not context:
        return record("app_health", "unknown", "no app cluster context configured")
    deltas, down = [], {}
    try:
        for target in targets:
            detail, components = _health_delta(run, context, target)
            if detail:
                deltas.append(detail)
                down[target["service"]] = components
    except Exception:
        return record("app_health", "unknown", "app health source unavailable")
    if not deltas:
        _debounced("app_health", False, threshold, state)
        return record("app_health", "healthy",
                      f"{len(targets)} service(s) agree with their probe groups "
                      "(a group-visible outage is covered by the argocd sensor, not this one)")
    status = "degraded" if _debounced("app_health", True, threshold, state) else "healthy"
    detail = "; ".join(deltas[:3])
    if len(deltas) > 3:
        detail = f"{detail} (+{len(deltas) - 3} more)"
    return record("app_health", status, redact(detail),
                  data={"deltas": [redact(item) for item in deltas],
                        "down_components": {key: [redact(name) for name in value]
                                            for key, value in down.items()}})


def _node_contexts(contexts):
    if contexts is not None:
        return [item for item in contexts if item]
    configured = os.environ.get("K3DM_HERMES_NODE_CONTEXTS", "")
    values = configured.split(",") if configured else ["k3d-k3d-cluster", "ubuntu-hostinger"]
    return [item.strip() for item in values if item.strip()]


def node_pressure(run, state, contexts=None, threshold=2):
    """Report node Ready and pressure conditions from each configured cluster."""
    problems = []
    unreadable = []
    for context in _node_contexts(contexts):
        try:
            code, output = run(["kubectl", "--context", context, "get", "nodes", "-o", "json",
                                "--request-timeout=10s"], {})
            payload = json.loads(output) if code == 0 and output else {}
            nodes = payload.get("items")
            if not isinstance(nodes, list):
                raise ValueError("invalid node payload")
        except Exception:
            unreadable.append(context)
            continue
        for node in nodes:
            name = node.get("metadata", {}).get("name", "unknown")
            conditions = {item.get("type"): item.get("status")
                          for item in node.get("status", {}).get("conditions", [])
                          if isinstance(item, dict)}
            if conditions.get("Ready") != "True":
                problems.append({"context": context, "node": name, "condition": "NotReady"})
            for pressure in ("MemoryPressure", "DiskPressure", "PIDPressure"):
                if conditions.get(pressure) == "True":
                    problems.append({"context": context, "node": name, "condition": pressure})
    data = {"problems": problems, "unreadable": unreadable}
    if not problems and len(unreadable) == len(_node_contexts(contexts)):
        return record("node_pressure", "unknown", "node status source unavailable", data=data)
    if problems:
        status = "degraded" if _debounced("node_pressure", True, threshold, state) else "healthy"
        evidence = "; ".join(f"{item['context']}/{item['node']} {item['condition']}"
                             for item in problems[:3])
    else:
        _debounced("node_pressure", False, threshold, state)
        evidence = "all readable nodes healthy"
        if unreadable:
            evidence += "; unreadable: " + ", ".join(unreadable)
        status = "healthy"
    return record("node_pressure", status, evidence, data=data)


def data_layer(fetch, state, provider="", token=None, threshold=2):
    """Report only the webhook's Data layer check."""
    token = token if token is not None else _keychain_secret(WEBHOOK_SERVICE)
    if not token:
        return _unavailable("data_layer", WEBHOOK_SERVICE)
    try:
        services = _webhook_services(fetch, token, provider)["services"]
        if not services:
            return record("data_layer", "unknown", "data layer status source unavailable: webhook returned no service checks")
        check = next((item for item in services if item.get("name") == "Data layer"), None)
        detail = (check or {}).get("detail", "Data layer")
        not_deployed = check is not None and check.get("ok") is None and str(detail).startswith("not deployed")
        if not not_deployed and all(item.get("ok") is None for item in services):
            return record("data_layer", "unknown", "data layer status source unavailable: all webhook checks ungraded")
        if check is None:
            return record("data_layer", "unknown", "data layer check absent from webhook payload")
        if check.get("ok") is False:
            status = "degraded" if _debounced("data_layer", True, threshold, state) else "healthy"
            return record("data_layer", status, f"data layer: {detail}")
        if check.get("ok") is None and not not_deployed:
            return record("data_layer", "unknown", f"data layer ungraded: {detail}")
        _debounced("data_layer", False, threshold, state)
        return record("data_layer", "healthy", detail)
    except Exception as exc:
        return record("data_layer", "unknown", f"data layer status source unavailable: {type(exc).__name__}")


def stale_acg_registration(items, marker="host.k3d.internal"):
    """Return True when an ArgoCD cluster Secret points at the retired ACG endpoint.

    Secret ``data`` values are base64-encoded, so they are decoded before matching;
    ``stringData`` and metadata are matched as plain text.
    """
    for item in items or []:
        if not isinstance(item, dict):
            continue
        texts = [json.dumps(item.get("metadata") or {}), json.dumps(item.get("stringData") or {})]
        for value in (item.get("data") or {}).values():
            try:
                texts.append(base64.b64decode(value, validate=True).decode("utf-8", "replace"))
            except (binascii.Error, TypeError, ValueError):
                continue
        if any(marker in text for text in texts):
            return True
    return False


def kine_log_signals(text):
    """Extract Kine compaction signals from raw K3s log text.

    Compaction progress must be matched on the K3s event markers, never on the
    bare substring "compact": every Kine "Slow SQL" line embeds the literal
    column name compact_rev_key, so a substring test reports compaction as
    recent precisely when compaction has stalled and Slow SQL is spiking.
    """
    lowered = text.lower()
    return {
        "slow_sql_count": lowered.count("slow sql"),
        "compaction_recent": ("compact compacted from" in lowered or
                              "compact deleted" in lowered),
        "compaction_failed": "compact failed" in lowered,
    }


def kine(run, state, threshold=2, max_db_bytes=8 * 1024 * 1024 * 1024):
    """Report local hub Kine pressure from a read-only, injected probe."""
    try:
        code, output = run(["bin/k3dm-hub-datastore-status", "--json"], {})
        payload = json.loads(output) if code == 0 and output else {}
        required = ("available", "state_db_bytes", "slow_sql_count",
                    "compaction_recent", "stale_acg_registration")
        if not all(name in payload for name in required) or not payload["available"]:
            raise ValueError("invalid datastore probe")
        db_bytes = int(payload["state_db_bytes"])
        slow_sql = int(payload["slow_sql_count"])
        compacting = bool(payload["compaction_recent"])
        stale = bool(payload["stale_acg_registration"])
        failed = bool(payload.get("compaction_failed", False))
        data = {"state_db_bytes": db_bytes, "slow_sql_count": slow_sql,
                "compaction_recent": compacting, "compaction_failed": failed,
                "stale_acg_registration": stale}
        raw = db_bytes >= max_db_bytes or failed or (slow_sql > 0 and not compacting)
        if raw:
            status = "degraded" if _debounced("kine", True, threshold, state) else "healthy"
            evidence = (f"state.db={db_bytes}B, slow_sql={slow_sql}, "
                        f"compaction_recent={compacting}, compaction_failed={failed}")
            return record("kine", status, evidence, data=data)
        _debounced("kine", False, threshold, state)
        return record("kine", "healthy", f"state.db={db_bytes}B; compaction recent",
                      data=data)
    except Exception:
        return record("kine", "unknown", "hub datastore status source unavailable")


def hostnet_drift(run, state, threshold=2):
    """Report host-network pods whose recorded IP differs from the node IP."""
    try:
        code, output = run(["bin/k3dm-hostnet-drift", "--json"], {})
        payload = json.loads(output) if code == 0 and output else {}
        drifted = payload.get("drifted")
        if not isinstance(drifted, list):
            raise ValueError("invalid host-network drift probe")
        data = {"drifted": drifted}
        if drifted:
            status = ("degraded" if _debounced("hostnet_drift", True, max(0, threshold - 1), state)
                      else "healthy")
            names = ", ".join(f"{item.get('namespace', 'default')}/{item.get('pod', '?')}"
                              for item in drifted[:3])
            return record("hostnet_drift", status,
                          f"{len(drifted)} host-network pods on stale IPs: {names}", data=data)
        _debounced("hostnet_drift", False, threshold, state)
        return record("hostnet_drift", "healthy", "no host-network pods on stale IPs", data=data)
    except Exception:
        return record("hostnet_drift", "unknown", "host-network drift source unavailable")


def vectordb(run, state, threshold=2, max_index_age_seconds=7 * 86400, now=None):
    """Report vector-store health from a read-only, injected probe."""
    try:
        code, output = run(["bin/k3dm-vectordb-status", "--json"], {})
        payload = json.loads(output) if code == 0 and output else {}
        required = ("available", "external_secret_synced", "pod_ready", "rows",
                    "corpus_docs", "last_indexed_epoch")
        if not all(name in payload for name in required):
            raise ValueError("invalid vectordb probe")
        data = {name: payload[name] for name in required}
        readable = ("available", "external_secret_synced", "pod_ready", "rows", "corpus_docs")
        if any(payload[name] is None for name in readable):
            return record("vectordb", "unknown", "vectordb status source unavailable", data=data)
        if payload["external_secret_synced"] is False:
            status = "degraded" if _debounced("vectordb", True, threshold, state) else "healthy"
            return record("vectordb", status,
                          "ExternalSecret vectordb-postgres not synced — the pod cannot start until it is",
                          data=data)
        if payload["pod_ready"] is False:
            status = "degraded" if _debounced("vectordb", True, threshold, state) else "healthy"
            return record("vectordb", status, "pod vectordb-0 is not ready", data=data)
        if payload["available"] is False:
            status = "degraded" if _debounced("vectordb", True, threshold, state) else "healthy"
            return record("vectordb", status, "vector store did not answer", data=data)
        if payload["last_indexed_epoch"] is None:
            # A readable "never indexed" state, not an unreadable source: the probe answered
            # every other field. Zero rows and no timestamp means the index was never built or
            # the volume was lost, which is exactly what this sensor exists to surface.
            if payload["rows"] == 0:
                status = "degraded" if _debounced("vectordb", True, threshold, state) else "healthy"
                return record("vectordb", status,
                              f"index never built — corpus={payload['corpus_docs']}, rows=0; "
                              "run make index-docs", data=data)
            return record("vectordb", "unknown",
                          "vectordb reports rows with no index timestamp", data=data)
        now = time.time() if now is None else now
        age_seconds = max(0, now - float(payload["last_indexed_epoch"]))
        age_days = age_seconds / 86400
        if age_seconds > max_index_age_seconds:
            status = "degraded" if _debounced("vectordb", True, threshold, state) else "healthy"
            return record("vectordb", status,
                          f"index is {age_days:.1f}d old, rows={payload['rows']}", data=data)
        _debounced("vectordb", False, threshold, state)
        return record("vectordb", "healthy",
                      f"rows={payload['rows']}, corpus={payload['corpus_docs']}, indexed {age_days:.1f}d ago",
                      data=data)
    except Exception:
        return record("vectordb", "unknown", "vectordb status source unavailable")


def alert_delivery(run, state, threshold=1):
    """Report clusters whose Alertmanager cannot deliver any alert at all.

    Two independent blackout modes are checked, because either one alone silences
    every rule: a referenced configSecret that does not exist (the Prometheus
    Operator then generates route.receiver=null), and a live route tree whose root
    receiver is a null sink with no child routes to escape through.

    ``config_ref`` carries the *name* of the Secret named by the Alertmanager CR's
    ``spec.configSecret``, never its contents -- the probe only checks that the object
    exists. The field is deliberately not called ``config_secret``: CodeQL's
    ``py/clear-text-logging-sensitive-data`` classifies any ``secret``-shaped name as
    sensitive, and this record is printed as JSON by ``bin/k3dm-hermes``.
    """
    try:
        code, output = run(["bin/k3dm-alert-delivery-status", "--json"], {})
        payload = json.loads(output) if code == 0 and output else {}
        clusters = payload.get("clusters")
        if not payload.get("available") or not isinstance(clusters, list) or not clusters:
            raise ValueError("invalid alert delivery probe")
        blackout = []
        for item in clusters:
            if not isinstance(item, dict) or "context" not in item:
                raise ValueError("invalid cluster entry")
            name = item["context"]
            if item.get("config_ref_missing"):
                blackout.append(
                    f"{name}: configSecret {item.get('config_ref', 'unset')} absent")
            elif item.get("root_receiver_is_null") and not item.get("child_routes"):
                blackout.append(f"{name}: root receiver is a null sink with no child routes")
        data = {"clusters": len(clusters), "blackout": blackout}
        if blackout:
            status = ("degraded" if _debounced("alert_delivery", True, threshold, state)
                      else "healthy")
            return record("alert_delivery", status, "; ".join(blackout[:3]), data=data)
        _debounced("alert_delivery", False, threshold, state)
        return record("alert_delivery", "healthy",
                      f"{len(clusters)} Alertmanager route tree(s) can deliver", data=data)
    except Exception:
        return record("alert_delivery", "unknown", "alert delivery probe unavailable")


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
        first_bad = {}
        rerunnable = {}
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
                conclusion = None
                if check.get("conclusion") in ("failure", "timed_out", "cancelled"):
                    conclusion = check["conclusion"]
                    bad.append(f"{repo_name} {check.get('name', 'check')} {conclusion}")
                elif check.get("status") == "in_progress" and _older_than(
                        check.get("started_at"), max_age_seconds, now):
                    conclusion = "stuck"
                    bad.append(f"{repo_name} {check.get('name', 'check')} stuck")
                if conclusion is None:
                    continue
                candidate = {"repo": repo_name, "run_id": latest["id"],
                             "run_url": latest.get("html_url", ""),
                             "conclusion": conclusion}
                if not first_bad:
                    first_bad = candidate
                if not rerunnable and conclusion in ("timed_out", "cancelled", "stuck"):
                    rerunnable = candidate
        ci_data = rerunnable or first_bad
        if bad:
            status = "degraded" if _debounced("ci", True, threshold, state) else "healthy"
            return record("ci", status, ", ".join(bad[:3]), data=ci_data)
        _debounced("ci", False, threshold, state)
        return record("ci", "healthy", "required CI checks successful")
    except Exception:
        return record("ci", "unknown", "CI status source unavailable")


GITHUB_EXPIRY_HEADER = "github-authentication-token-expiration"


def _parse_expiry(raw):
    value = str(raw).strip()
    if value.endswith(" UTC"):
        value = value[:-4].strip()
    try:
        return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))


def github_token_expiry(header_fetch, token=None, warn_days=14, now=None):
    token = token if token is not None else _keychain_secret(GITHUB_SERVICE)
    if not token:
        return None
    now = now or datetime.now(timezone.utc)
    try:
        headers = header_fetch("/", {"Authorization": f"token {token}"})
        raw = headers.get(GITHUB_EXPIRY_HEADER, "") if isinstance(headers, dict) else ""
        if not raw:
            return None
        expires = _parse_expiry(raw)
    except Exception:
        return None
    if (expires - now).total_seconds() > warn_days * 86400:
        return None
    return {"service": GITHUB_SERVICE, "days": (expires - now).days,
            "expires_at": expires.isoformat().replace("+00:00", "Z")}


def token_expiry_advisory(header_fetch, state, today, token=None, warn_days=14, now=None):
    info = github_token_expiry(header_fetch, token=token, warn_days=warn_days, now=now)
    if not info:
        return None
    if state.get("token_expiry_notified_on") == today:
        return None
    state["token_expiry_notified_on"] = today
    days = info["days"]
    horizon = f"in {days} day(s)" if days >= 0 else f"{abs(days)} day(s) ago"
    return (f"Hermes advisory: GitHub token {info['service']} expires {horizon} "
            f"({info['expires_at']}). Renew as a no-expiration classic PAT "
            f"(scopes: repo + workflow) in the same Keychain slot, then verify: "
            f"bin/k3dm-hermes preflight.")
