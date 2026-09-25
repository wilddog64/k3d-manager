#!/usr/bin/env python3
"""Read-only cluster status collection and Slack formatting for k3dm-webhook."""

import datetime
from pathlib import Path

from webhook.config import JOB_DIR
from webhook.proc import _spawn_capture_text
from webhook.render import _slack_post
from webhook.agent import _call_gemini

__all__ = [
    "_run_cluster_status", "_format_status_summary_slack",
    "_run_hostinger_status", "_run_cluster_diagnostics", "configure_runtime",
]

_log_runtime = None
_notify_job = None
_redact_secrets = lambda text: text
_resolve_provider = lambda provider=None: provider
_provider_context = lambda provider=None: provider
_acg_stack_probe = lambda provider: None
_running_cluster_job = lambda: None
_smoke_test_services = lambda **kwargs: []
_ARCH_CONTEXT = ""


def configure_runtime(log, notify_job, redact_secrets, resolve_provider,
                      provider_context, acg_stack_probe, running_cluster_job,
                      smoke_test_services):
    """Inject entrypoint-owned reporting hooks and probes."""
    global _log_runtime, _notify_job, _redact_secrets, _resolve_provider
    global _provider_context, _acg_stack_probe, _running_cluster_job
    global _smoke_test_services
    _log_runtime = log
    _notify_job = notify_job
    _redact_secrets = redact_secrets
    _resolve_provider = resolve_provider
    _provider_context = provider_context
    _acg_stack_probe = acg_stack_probe
    _running_cluster_job = running_cluster_job
    _smoke_test_services = smoke_test_services


def _posix_spawn_capture(cmd, timeout, cwd=None, env=None):
    _rc, output, timed_out = _spawn_capture_text(cmd, cwd=cwd, env=env, timeout=timeout)
    return output.strip(), timed_out


def _run_cluster_status(job_id, response_url, thread_ts=None, provider=None):
    """Check ACG cluster reachability + ArgoCD app health; post result to response_url or thread."""
    job_dir = JOB_DIR / job_id
    if thread_ts:
        (job_dir / "thread_ts").write_text(thread_ts)
    lines = []

    def _write_log(msg):
        lines.append(msg + "\n")

    def _finish(status):
        (job_dir / "status").write_text(status)
        output = _redact_secrets("".join(lines))
        if len(output) > 3400:
            output = (output[:1600]
                      + "\n… middle of report truncated …\n"
                      + output[-1800:])
        (job_dir / "output").write_text(output)
        if response_url:
            _slack_post(response_url, output)
        else:
            _notify_job(job_id, output)

    def _pod_is_ready(line):
        parts = line.split()
        if len(parts) < 4:
            return False
        ready_str = parts[2]
        status_str = parts[3]
        if status_str in ("Completed", "Succeeded"):
            return True
        if "/" in ready_str:
            try:
                n, m = ready_str.split("/", 1)
                return n == m and int(m) > 0 and status_str == "Running"
            except ValueError:
                return False
        return False

    try:
        (job_dir / "status").write_text("running")
        provider = _resolve_provider(provider)
        app_context = _provider_context(provider)
        acg_probe = _acg_stack_probe(provider)

        active = _running_cluster_job()
        if active:
            active_id, active_action = active
            active_dir = JOB_DIR / active_id
            mtime = active_dir.stat().st_mtime
            elapsed = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - mtime) / 60)
            _write_log(f"⏳ *cluster-{active_action}* in progress (running {elapsed}m) — job `{active_id}`")
            _finish("success")
            return

        # Hub cluster — posix_spawn avoids NEF atfork SIGSEGV
        hub_out, hub_timeout = _posix_spawn_capture(
            ["kubectl", "get", "nodes", "--context", "k3d-k3d-cluster",
             "--request-timeout=5s", "--no-headers"],
            timeout=10,
        )
        if not hub_timeout and hub_out.strip() and not hub_out.lstrip().startswith("Error"):
            hub_lines = [l for l in hub_out.strip().splitlines() if l]
            hub_ready = sum(1 for l in hub_lines if "Ready" in l and "NotReady" not in l)
            _write_log(f"🏠 *Hub cluster* — {hub_ready}/{len(hub_lines)} nodes ready")
        else:
            _write_log("🏠 *Hub cluster* — ❌ unreachable")

        # SSH tunnel — Python socket, no subprocess
        import socket as _socket
        try:
            with _socket.create_connection(("localhost", 6443), timeout=3):
                tunnel_ok = True
        except OSError:
            tunnel_ok = False
        _write_log(f"*SSH tunnel (6443):* {'UP ✅' if tunnel_ok else 'DOWN ❌'}")
        if acg_probe:
            _write_log(acg_probe["status_line"])

        # App cluster
        nodes_out, nodes_timeout = _posix_spawn_capture(
            ["kubectl", "get", "nodes", "--context", app_context,
             "--request-timeout=8s", "--no-headers"],
            timeout=15,
        )
        acg_reachable = not nodes_timeout and nodes_out.strip() and not nodes_out.lstrip().startswith("Error")
        if not acg_reachable:
            _write_log(acg_probe["unreachable_line"] if acg_probe else f"\n❌ *{provider} cluster unreachable* — cluster may be rebuilding or unavailable.")
        else:
            node_lines = [l for l in nodes_out.strip().splitlines() if l]
            ready_count = sum(1 for l in node_lines if "Ready" in l and "NotReady" not in l)
            total_count = len(node_lines)

            header = f"\n✅ *{provider} cluster* — {ready_count}/{total_count} nodes ready"
            acg_state_out, _ = _posix_spawn_capture(
                ["kubectl", "get", "configmap", "acg-state", "-n", "platform-ops",
                 "--context", app_context, "--request-timeout=5s",
                 "-o", "jsonpath={.data.provisioned-at} {.data.provider}"],
                timeout=10,
            )
            if acg_state_out.strip() and not acg_state_out.lstrip().startswith("Error"):
                parts = acg_state_out.strip().split()
                try:
                    age_min = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - int(parts[0])) / 60)
                    provider = parts[1] if len(parts) > 1 else "aws"
                    header += f" | {provider} | up {age_min}m"
                except (ValueError, IndexError):
                    pass
            _write_log(header)
            _write_log(f"```{nodes_out.strip()}```")

            # App pods (all namespaces, standard output)
            pods_out, pods_timeout = _posix_spawn_capture(
                ["kubectl", "get", "pods", "-A", "--context", app_context,
                 "--no-headers", "--request-timeout=10s"],
                timeout=20,
            )
            if not pods_timeout and pods_out.strip():
                all_pod_lines = [l for l in pods_out.strip().splitlines() if l]
                skip_ns = {"kube-system", "kube-public", "kube-node-lease", "trivy-system"}
                app_pods = [l for l in all_pod_lines if l.split()[0] not in skip_ns]
                if app_pods:
                    not_ready = [l for l in app_pods if not _pod_is_ready(l)]
                    ready_count_pods = len(app_pods) - len(not_ready)
                    _write_log(f"\n*Pods* — {ready_count_pods}/{len(app_pods)} ready")
                    if not_ready:
                        shown = not_ready[:10]
                        snippet = "\n".join(
                            f"{l.split()[0]}  {l.split()[1]}  {l.split()[2]}  {l.split()[3]}"
                            for l in shown if len(l.split()) >= 4
                        )
                        _write_log(f"```{snippet}```")
                        if len(not_ready) > 10:
                            _write_log(f"_…and {len(not_ready) - 10} more not-ready pods_")
                else:
                    _write_log("\n*Pods* — no app pods deployed yet")
            else:
                _write_log("\n_Pod status unavailable_")

        # ArgoCD apps
        apps_out, apps_timeout = _posix_spawn_capture(
            ["kubectl", "get", "applications", "-n", "cicd",
             "--context", "k3d-k3d-cluster",
             "--no-headers",
             "-o", "custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"],
            timeout=10,
        )
        if not apps_timeout and apps_out.strip() and not apps_out.lstrip().startswith("Error"):
            acg_apps = [l for l in apps_out.strip().splitlines()
                        if l.startswith("acg-") or "ubuntu-k3s" in l]
            if acg_apps:
                _write_log(f"\n*ACG ArgoCD apps:*")
                if not acg_reachable:
                    _write_log("_(cached — ACG cluster was unreachable)_")
                _write_log(f"```{chr(10).join(acg_apps)}```")
            all_apps = apps_out.strip().splitlines()
            unhealthy = [l for l in all_apps
                         if "Degraded" in l or "Missing" in l or "OutOfSync" in l]
            if unhealthy:
                _write_log("\n⚠️ *Unhealthy/OutOfSync apps:*")
                _write_log(f"```{chr(10).join(unhealthy)}```")
        else:
            _write_log("\n_ArgoCD app status unavailable (Hub cluster unreachable)_")

        # AWS credentials
        aws_out, aws_timeout = _posix_spawn_capture(
            ["aws", "sts", "get-caller-identity", "--query", "Arn", "--output", "text"],
            timeout=10,
        )
        if not aws_timeout and aws_out.strip() and "arn:" in aws_out.lower():
            _write_log(f"\n*AWS:* ✅ `{aws_out.strip()}`")
        else:
            _write_log("\n*AWS:* ❌ credentials invalid or expired — run `/cluster-refresh`")

        # Service smoke test (1 retry — fast path for on-demand status)
        smoke = _smoke_test_services(retries=1, provider=provider)
        all_smoke_ok = all(ok is not False for _, ok, _ in smoke)
        _write_log(f"\n*Service smoke test:*{'  all clear ✅' if all_smoke_ok else ''}")
        for svc_name, ok, detail in smoke:
            icon = "✅" if ok is True else ("⚪" if ok is None else "❌")
            _write_log(f"  {icon} {svc_name}: {detail}")
        if all_smoke_ok and not tunnel_ok:
            _write_log("\nℹ️ _Hub/tunnel checks DOWN but service endpoints responding — port-forwards or Cloudflare tunnel still active. Run `/cluster-refresh` to restore kubectl access._")

        failed_smoke = [(name, detail) for name, ok, detail in smoke if ok is False]
        for svc_name, err_detail in failed_smoke[:3]:
            diag_parts = [f"Service `{svc_name}` failed HTTP smoke test: {err_detail}"]
            ns_map = {
                "Frontend":              ("shopping-cart-apps", "app=frontend"),
                "Product images":        ("shopping-cart-apps", "app.kubernetes.io/name=product-catalog"),
                "Keycloak":              ("identity",            "app.kubernetes.io/name=keycloak"),
                "Prometheus":            ("monitoring",          "app.kubernetes.io/name=prometheus"),
                "Grafana":               ("monitoring",          "app.kubernetes.io/name=grafana"),
                "Pushgateway":           ("monitoring",          "app.kubernetes.io/name=prometheus-pushgateway"),
                "ArgoCD":                ("cicd",                "app.kubernetes.io/name=argocd-server"),
                "ESO ClusterSecretStore":("secrets",             "app.kubernetes.io/name=external-secrets"),
                "ESO ExternalSecrets":   ("secrets",             "app.kubernetes.io/name=external-secrets"),
            }
            ns, label_sel = ns_map.get(svc_name, ("shopping-cart-apps", ""))
            if label_sel:
                pod_state_out, pod_state_timeout = _posix_spawn_capture(
                    ["kubectl", "get", "pods", "-n", ns, "-l", label_sel,
                     "--context", app_context, "--no-headers", "--request-timeout=8s"],
                    timeout=15,
                )
                if not pod_state_timeout and pod_state_out.strip():
                    diag_parts.append(f"Pod state ({ns}):\n{pod_state_out.strip()[:800]}")
            prompt = (
                _ARCH_CONTEXT + "\n"
                f"Service `{svc_name}` failed an HTTP smoke test. Error: {err_detail}\n\n"
                "Diagnostics:\n" + "\n\n".join(diag_parts) + "\n\n"
                "Is this a TRANSIENT issue (pod still starting, port-forward not ready, "
                "ESO secret not yet synced — will resolve in a few minutes) or a REAL FAILURE "
                "(crash loop, missing secret, misconfiguration — needs human action)?\n"
                "Use the architecture context above to reason about upstream dependencies. "
                "Reply with TRANSIENT or REAL FAILURE, then one sentence with the most likely "
                "cause. Be brief."
            )
            analysis = _call_gemini(prompt)
            _write_log(f"\n🔍 *{svc_name}:* {analysis}")

        _finish("success")
    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
def _format_status_summary_slack(payload, provider):
    """Render the same per-service status checks shown by ``make status``."""
    payload = payload if isinstance(payload, dict) else {}
    overall = str(payload.get("overall", "unknown"))
    emoji = {"healthy": ":white_check_mark:", "warn": ":warning:",
             "fail": ":x:", "unknown": ":grey_question:"}.get(overall, ":grey_question:")
    counts = payload.get("counts", {}) or {}
    header = f"{emoji} *Cluster status: {overall.upper()}* — `{provider}`"
    if counts:
        header += ("  ({} ok / {} warn / {} fail)".format(
            counts.get("services_healthy", 0),
            counts.get("services_warning", 0),
            counts.get("services_failed", 0)))
    out = [header]
    checks = payload.get("checks", []) or []
    if checks:
        icons = {"healthy": ":white_check_mark:", "warning": ":warning:", "error": ":x:"}
        for item in checks:
            status = item.get("status", "warning")
            out.append("{} {}: {}".format(
                icons.get(status, ":warning:"),
                item.get("service") or item.get("id") or "?",
                str(item.get("message", ""))[:250],
            ))
    else:
        for item in payload.get("errors", []):
            out.append(":x: {}: {}".format(
                item.get("service") or item.get("id") or "?", str(item.get("message", ""))[:250]))
        for item in payload.get("warnings", []):
            out.append(":warning: {}: {}".format(
                item.get("service") or item.get("id") or "?", str(item.get("message", ""))[:250]))
    if overall == "unknown":
        out.append("_status source unavailable — run `make restart-webhook` on the hub_")
    return _redact_secrets("\n".join(out))
def _run_hostinger_status(job_id, response_url, thread_ts=None, provider=None):
    """Run bin/cluster-status for k3s-hostinger (read-only); post result to response_url or thread."""
    job_dir = JOB_DIR / job_id
    if thread_ts:
        (job_dir / "thread_ts").write_text(thread_ts)
    lines = []

    def _write_log(msg):
        lines.append(msg + "\n")

    def _finish(status):
        (job_dir / "status").write_text(status)
        report = _redact_secrets("".join(lines))
        if len(report) > 3400:
            report = (report[:1600]
                      + "\n… middle of report truncated …\n"
                      + report[-1800:])
        output = report
        (job_dir / "output").write_text(output)
        if response_url:
            _slack_post(response_url, output)
        else:
            _notify_job(job_id, output)

    try:
        (job_dir / "status").write_text("running")
        # A node recovery invalidates several forwards at once. Use the normal
        # bounded retry window here so `/cluster-status` does not report a
        # false outage while launchd is rebuilding those forwards.
        smoke = _smoke_test_services(provider="k3s-hostinger")
        checks = []
        for name, ok, detail in smoke:
            status = "healthy" if ok is True else ("warning" if ok is None else "error")
            checks.append({"id": name.lower().replace(" ", "_"), "service": name,
                           "status": status, "message": detail})
        errors = [item for item in checks if item["status"] == "error"]
        warnings = [item for item in checks if item["status"] == "warning"]
        payload = {
            "overall": "fail" if errors else ("warn" if warnings else "healthy"),
            "checks": checks,
            "errors": errors,
            "warnings": warnings,
            "counts": {
                "services_healthy": sum(item["status"] == "healthy" for item in checks),
                "services_warning": len(warnings),
                "services_failed": len(errors),
            },
        }
        _write_log(_format_status_summary_slack(payload, "k3s-hostinger"))
        _finish("success")
    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
def _run_cluster_diagnostics(job_id, response_url, thread_ts=None, request=None):
    """Run an explicit read-only diagnostic command and post the result."""
    job_dir = JOB_DIR / job_id
    if thread_ts:
        (job_dir / "thread_ts").write_text(thread_ts)
    lines = []

    def _write_log(msg):
        lines.append(msg + "\n")

    def _finish(status):
        (job_dir / "status").write_text(status)
        output = _redact_secrets("".join(lines))
        (job_dir / "output").write_text(output)
        if response_url:
            _slack_post(response_url, output)
        else:
            _notify_job(job_id, output)

    try:
        req = dict(request or {})
        action = req["action"]
        context = req["context"]
        provider = req.get("provider", "hostinger")
        namespace = req.get("namespace", "")
        name = req.get("name", "")
        tail_lines = req.get("tail_lines", 120)
        cmd = []
        title = ""

        if action == "get-pods":
            title = f"🔎 *Diagnostics* — pods in `{namespace}` on `{context}`"
            cmd = [
                "kubectl", "get", "pods", "-n", namespace,
                "--context", context, "-o", "wide",
                "--request-timeout=15s",
            ]
        elif action == "describe-pod":
            title = f"🔎 *Diagnostics* — describe pod `{name}` in `{namespace}` on `{context}`"
            cmd = [
                "kubectl", "describe", "pod", name, "-n", namespace,
                "--context", context, "--request-timeout=15s",
            ]
        elif action == "logs":
            title = f"🔎 *Diagnostics* — logs for pod `{name}` in `{namespace}` on `{context}`"
            cmd = [
                "kubectl", "logs", f"pod/{name}", "-n", namespace,
                "--context", context, f"--tail={tail_lines}",
                "--request-timeout=15s",
            ]
            if req.get("container", ""):
                cmd.extend(["-c", req["container"]])
        elif action == "get-apps":
            title = "🔎 *Diagnostics* — ArgoCD applications on `k3d-k3d-cluster`"
            cmd = [
                "kubectl", "get", "applications", "-n", "cicd",
                "--context", "k3d-k3d-cluster", "--no-headers",
                "-o", "custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status",
                "--request-timeout=15s",
            ]
        elif action == "describe-app":
            title = f"🔎 *Diagnostics* — describe ArgoCD app `{name}`"
            cmd = [
                "kubectl", "describe", "application", name, "-n", "cicd",
                "--context", "k3d-k3d-cluster", "--request-timeout=15s",
            ]
        elif action == "get-appsets":
            title = "🔎 *Diagnostics* — ArgoCD ApplicationSets on `k3d-k3d-cluster`"
            cmd = [
                "kubectl", "get", "applicationsets", "-n", "cicd",
                "--context", "k3d-k3d-cluster", "-o", "wide",
                "--request-timeout=15s",
            ]

        _write_log(title)
        _write_log(f"_Target provider: `{provider}`_")
        out, timed_out = _posix_spawn_capture(cmd, timeout=30)
        if timed_out:
            _write_log("\n❌ diagnostics command timed out after 30s")
            _finish("failed")
            return
        if out.strip():
            clipped = out.strip()
            if len(clipped) > 3500:
                clipped = clipped[-3500:]
            _write_log(f"```{clipped}```")
        else:
            _write_log("_(no output returned)_")
        _finish("success")
    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
