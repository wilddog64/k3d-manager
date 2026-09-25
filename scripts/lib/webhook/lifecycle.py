#!/usr/bin/env python3
"""Long-running cluster orchestration for k3dm-webhook."""

import datetime
import os
import signal
import threading
import traceback
from pathlib import Path

from webhook.config import JOB_DIR, REPO_ROOT
from webhook.proc import _spawn_capture_text
from webhook.render import _slack_post

__all__ = [
    "_run_cleanup", "_run_make_target", "_run_upgrade", "_run_cluster",
    "_run_cluster_resume", "_run_cluster_refresh", "_run_hostinger_refresh",
    "configure_runtime",
]

_log_runtime = None
_notify_job = None
_push_metrics = lambda *args, **kwargs: None
_analyze_stall = lambda lines: ""
_analyze_failure = lambda lines: ""
_redact_secrets = lambda text: text
_spawn_job = None
_helpers = {}


def configure_runtime(log, notify_job, push_metrics, analyze_stall, analyze_failure,
                      redact_secrets, spawn_job, helpers):
    """Inject entrypoint-owned runtime hooks and orchestration state."""
    global _log_runtime, _notify_job, _push_metrics, _analyze_stall
    global _analyze_failure, _redact_secrets, _spawn_job, _helpers
    _log_runtime = log
    _notify_job = notify_job
    _push_metrics = push_metrics
    _analyze_stall = analyze_stall
    _analyze_failure = analyze_failure
    _redact_secrets = redact_secrets
    _spawn_job = spawn_job
    _helpers = helpers
    globals().update({
        "_posix_spawn_job": spawn_job,
        "_current_label": helpers["current_label"],
        "_cluster_name": helpers["cluster_name"],
        "_patch_label": helpers["patch_label"],
        "_running_procs": helpers["running_procs"],
        "_running_procs_lock": helpers["running_procs_lock"],
        "_record_acg_state": helpers["record_acg_state"],
        "_run_post_provision_check": helpers["run_post_provision_check"],
        "_running_cluster_job": helpers["running_cluster_job"],
    })


def _posix_spawn_capture(cmd, timeout, cwd=None, env=None):
    _rc, output, timed_out = _spawn_capture_text(cmd, cwd=cwd, env=env, timeout=timeout)
    return output.strip(), timed_out


def _read_job_tail(output_path, n=3):
    try:
        with open(output_path, errors="replace") as _f:
            _lines = _f.readlines()
        return [line.rstrip() for line in _lines[-n:] if line.strip()]
    except OSError:
        return []


_STALL_TICKS_THRESHOLD = 3

def _run_cleanup(job_id, provider):
    """Remove stale SSH tunnel and kubeconfig context after a failed cluster-up."""
    _notify_job(job_id, f"🧹 *Cleanup triggered* ({provider}) — removing stale SSH tunnel and kubeconfig context")
    try:
        _spawn_capture_text(["pkill", "-f", "autossh"], timeout=10)
        _spawn_capture_text(["kubectl", "config", "delete-context", "ubuntu-k3s"], timeout=20)
        _notify_job(job_id, f"✅ *Cleanup complete* ({provider}) — stale connections removed")
    except Exception as exc:
        _notify_job(job_id, f"⚠️ *Cleanup error* ({provider}): {exc}")
def _run_make_target(job_id, argv_tail, timeout, actor):
    """Run one allowlisted /k3dm make target and post the tail of its output."""
    label = " ".join(argv_tail)
    try:
        (JOB_DIR / job_id / "status").write_text("running")
        _notify_job(job_id, f"🛠️ *make {label}* started by {actor}")
        cmd = ["make", "--no-print-directory", *argv_tail]
        rc, output, timed_out = _spawn_capture_text(cmd, timeout=timeout, cwd=REPO_ROOT)
        lines = output.rstrip().splitlines()
        tail = "\n".join(lines[-40:])[-3000:]
        if timed_out:
            status, icon, verdict = "failed", "⏱️", f"timed out after {timeout}s"
        elif rc == 0:
            status, icon, verdict = "success", "✅", "succeeded"
        else:
            status, icon, verdict = "failed", "❌", f"failed (rc {rc})"
        (JOB_DIR / job_id / "status").write_text(status)
        _notify_job(job_id, f"{icon} *make {label}* {verdict}\n```{tail or '(no output)'}```")
    finally:
        _helpers["make_job_lock"].release()


def _run_upgrade(job_id, chart_version, stage):
    job_dir = JOB_DIR / job_id
    _out_file = job_dir / "output"

    def _write_log(msg):
        with open(_out_file, "a") as _f:
            _f.write(msg + "\n")

    def _finish(status):
        (job_dir / "status").write_text(status)

    try:
        (job_dir / "status").write_text("running")
        env_label = "dev" if stage == "acg" else "infra"

        # Idempotency check
        current = _current_label(env_label)
        if current == chart_version:
            _write_log(f"{stage}: already at {chart_version} — no-op")
            _finish("success")
            return

        if stage == "acg":
            _write_log("Running make up...")
            pid = _posix_spawn_job(["make", "up"], _out_file, cwd=REPO_ROOT)
            _, _status = os.waitpid(pid, 0)
            _rc = os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
            try:
                os.killpg(pid, signal.SIGTERM)
            except (ProcessLookupError, OSError):
                pass
            if _rc != 0:
                raise RuntimeError(f"make up exited {_rc}")
            _write_log("make up complete")

        cluster_ref = _cluster_name(env_label)
        if not cluster_ref:
            raise RuntimeError(f"No cluster secret found for environment={env_label}")

        _patch_label(cluster_ref, chart_version)
        _write_log(f"Patched {cluster_ref}: argocd-chart-version={chart_version}")
        _finish("success")

    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
def _run_cluster(job_id, action, provider="aws", dry_run=False):
    running = _helpers["running_cluster_job"]()
    if running and running[0] != job_id:
        _notify_job(job_id, f"⚠️ Cluster job already running: `{running[0]}` ({running[1]}) — wait for it to finish")
        return
    job_dir = JOB_DIR / job_id
    _out_file = job_dir / "output"
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "az": "k3s-az", "hostinger": "k3s-hostinger"}
    _cluster_provider = _provider_map.get(provider, "k3s-aws")
    _start = datetime.datetime.now(datetime.timezone.utc).timestamp()
    _progress_timer = None
    _last_line_count = 0
    _stall_tick_count = 0
    _stall_analyzed = False

    def _write_log(msg):
        with open(_out_file, "a") as _f:
            _f.write(msg + "\n")

    _notify_job(job_id, f"🚀 *cluster-{action}* ({provider}) started — job `{job_id}`")

    def _post_progress():
        nonlocal _progress_timer, _last_line_count, _stall_tick_count, _stall_analyzed
        elapsed = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - _start) / 60)
        tail = _read_job_tail(_out_file)
        tail_text = "\n".join(tail) if tail else "—"
        _notify_job(job_id, f"⏳ *cluster-{action}* ({provider}) still running — {elapsed}m elapsed\n```{tail_text}```")
        try:
            current_count = sum(1 for _ in open(_out_file))
        except OSError:
            current_count = 0
        if current_count == _last_line_count:
            _stall_tick_count += 1
        else:
            _stall_tick_count = 0
            _stall_analyzed = False
        _last_line_count = current_count
        if _stall_tick_count >= _STALL_TICKS_THRESHOLD and not _stall_analyzed:
            _stall_analyzed = True
            try:
                _all_lines = _out_file.read_text(errors="replace").splitlines()
            except OSError:
                _all_lines = []
            analysis = _analyze_stall(_all_lines)
            _notify_job(
                job_id,
                f"⚠️ *Stall detected* — no new output for {_stall_tick_count * 2}m "
                f"(job `{job_id}`)\n*AI:* {analysis}\n"
                f'To kill: POST `/api/v1/cluster` `{{"action":"kill","job_id":"{job_id}"}}`'
            )
        _progress_timer = threading.Timer(120, _post_progress)
        _progress_timer.daemon = True
        _progress_timer.start()

    def _finish(status):
        if _progress_timer:
            _progress_timer.cancel()
        with _running_procs_lock:
            _running_procs.pop(job_id, None)
        (job_dir / "status").write_text(status)
        emoji = "✅" if status == "success" else "❌"
        elapsed_secs = int(datetime.datetime.now(datetime.timezone.utc).timestamp() - _start)
        elapsed = elapsed_secs // 60
        _dry_tag = " — DRY_RUN preview" if dry_run else ""
        summary = f"{emoji} *cluster-{action}* ({provider}) — {status} in {elapsed}m{_dry_tag}"
        _notify_job(job_id, summary)
        if not dry_run:
            _push_metrics(action, provider, status, elapsed_secs, job_id)

    try:
        if action == "up":
            cmd = ["make", "up", f"CLUSTER_PROVIDER={_cluster_provider}"]
        elif _cluster_provider == "k3s-hostinger":
            cmd = ["make", "down", f"CLUSTER_PROVIDER={_cluster_provider}"]
        else:
            cmd = ["make", "down", "KEEP_LOCAL=1"]
        _write_log(f"DRY_RUN: would {' '.join(cmd)}" if dry_run else f"Running {' '.join(cmd)}...")
        _spawn_env = dict(os.environ)
        if dry_run:
            _spawn_env["DRY_RUN"] = "1"
        _progress_timer = threading.Timer(120, _post_progress)
        _progress_timer.daemon = True
        _progress_timer.start()
        pid = _posix_spawn_job(cmd, _out_file, cwd=REPO_ROOT, env=_spawn_env)
        with _running_procs_lock:
            _running_procs[job_id] = pid
        _, _status = os.waitpid(pid, 0)
        _rc = os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
        try:
            os.killpg(pid, signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass
        if _rc != 0:
            raise RuntimeError(f"{' '.join(cmd)} exited {_rc}")
        _write_log(f"{action} complete")
        if action == "up" and not dry_run:
            _record_acg_state(provider)
            threading.Thread(
                target=_run_post_provision_check,
                args=(job_id, provider),
                daemon=True
            ).start()
        _finish("success")
    except Exception as exc:
        tb = traceback.format_exc()
        _write_log(f"ERROR: {exc}\n{tb}")
        try:
            _all_lines = _out_file.read_text(errors="replace").splitlines() if _out_file.exists() else []
            analysis = _analyze_failure(_all_lines)
            _notify_job(job_id, f"🔍 *Failure analysis* (job `{job_id}`)\n{analysis}")
        except Exception as analysis_exc:
            _write_log(f"WARN: failure analysis skipped: {analysis_exc}")
        _finish("failed")
        if action == "up":
            threading.Thread(
                target=_run_cleanup,
                args=(job_id, provider),
                daemon=True,
            ).start()
def _run_cluster_resume(job_id, provider="aws"):
    """Re-run make up with K3DM_RESUME=1 to skip completed checkpoints."""
    job_dir = JOB_DIR / job_id
    _out_file = job_dir / "output"
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "az": "k3s-az", "hostinger": "k3s-hostinger"}
    _cluster_provider = _provider_map.get(provider, "k3s-aws")
    _start = datetime.datetime.now(datetime.timezone.utc).timestamp()
    _progress_timer = None

    def _write_log(msg):
        with open(_out_file, "a") as _f:
            _f.write(msg + "\n")

    _notify_job(job_id, f"🔄 *cluster-resume* ({provider}) started — job `{job_id}`")

    def _post_progress():
        nonlocal _progress_timer
        elapsed = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - _start) / 60)
        tail = _read_job_tail(_out_file)
        tail_text = "\n".join(tail) if tail else "—"
        _notify_job(job_id, f"⏳ *cluster-resume* ({provider}) still running — {elapsed}m elapsed\n```{tail_text}```")
        _progress_timer = threading.Timer(120, _post_progress)
        _progress_timer.daemon = True
        _progress_timer.start()

    def _finish(status):
        if _progress_timer:
            _progress_timer.cancel()
        with _running_procs_lock:
            _running_procs.pop(job_id, None)
        (job_dir / "status").write_text(status)
        emoji = "✅" if status == "success" else "❌"
        elapsed_secs = int(datetime.datetime.now(datetime.timezone.utc).timestamp() - _start)
        elapsed = elapsed_secs // 60
        _notify_job(job_id, f"{emoji} *cluster-resume* ({provider}) — {status} in {elapsed}m")
        _push_metrics("resume", provider, status, elapsed_secs, job_id)

    try:
        cmd = ["make", "up", f"CLUSTER_PROVIDER={_cluster_provider}", "K3DM_RESUME=1"]
        _write_log(f"Running {' '.join(cmd)}...")
        _progress_timer = threading.Timer(120, _post_progress)
        _progress_timer.daemon = True
        _progress_timer.start()
        pid = _posix_spawn_job(cmd, _out_file, cwd=REPO_ROOT)
        with _running_procs_lock:
            _running_procs[job_id] = pid
        _, _status = os.waitpid(pid, 0)
        _rc = os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
        try:
            os.killpg(pid, signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass
        if _rc != 0:
            raise RuntimeError(f"{' '.join(cmd)} exited {_rc}")
        _write_log("resume complete")
        _record_acg_state(provider)
        threading.Thread(
            target=_run_post_provision_check,
            args=(job_id, provider),
            daemon=True
        ).start()
        _finish("success")
    except Exception as exc:
        tb = traceback.format_exc()
        _write_log(f"ERROR: {exc}\n{tb}")
        try:
            _all_lines = _out_file.read_text(errors="replace").splitlines() if _out_file.exists() else []
            analysis = _analyze_failure(_all_lines)
            _notify_job(job_id, f"🔍 *Failure analysis* (job `{job_id}`)\n{analysis}")
        except Exception as analysis_exc:
            _write_log(f"WARN: failure analysis skipped: {analysis_exc}")
        _finish("failed")
def _run_cluster_refresh(job_id, response_url, thread_ts=None):
    """Run bin/cluster-refresh --no-login-prompt; post result to response_url or thread."""
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
        _write_log("🔄 *ACG Refresh* — refreshing credentials + SSH tunnel…")
        import shlex as _shlex_ref
        repo_root = REPO_ROOT
        refresh_bin = repo_root / "bin" / "cluster-refresh"
        refresh_out, refresh_timeout = _posix_spawn_capture(
            ["/bin/bash", "-c",
             f"{_shlex_ref.quote(str(refresh_bin))} --no-login-prompt && echo __WEBHOOK_SUCCESS__"],
            timeout=300,
        )
        if refresh_timeout:
            _write_log("\n❌ *Refresh timed out* after 300s — run `bin/cluster-refresh` manually")
            _finish("failed")
            return
        if "__WEBHOOK_SUCCESS__" in refresh_out:
            acg_probe = _acg_stack_probe("k3s-aws")
            _write_log(acg_probe["refresh_line"] if acg_probe else "\n✅ *Refresh complete* — credentials and access layer refreshed")
        else:
            tail_lines = [l for l in refresh_out.strip().splitlines()[-5:] if l]
            _write_log("\n❌ *Refresh failed*")
            if tail_lines:
                _write_log("```\n{}\n```".format("\n".join(tail_lines)))
        _finish("success")
    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
def _run_hostinger_refresh(job_id, response_url, thread_ts=None):
    """Run make refresh for k3s-hostinger (restore kubeconfig + ArgoCD); post result."""
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
        (job_dir / "status").write_text("running")
        import shlex as _shlex_hr
        repo_root = REPO_ROOT
        _write_log("🔄 *Hostinger refresh* — restoring kubeconfig + ArgoCD registration…")
        refresh_out, refresh_timeout = _posix_spawn_capture(
            ["/bin/bash", "-c",
             f"cd {_shlex_hr.quote(str(repo_root))} && make refresh CLUSTER_PROVIDER=k3s-hostinger && echo __WEBHOOK_SUCCESS__"],
            timeout=180,
        )
        if refresh_timeout:
            _write_log("\n❌ *Hostinger refresh timed out* after 180s — run `make refresh CLUSTER_PROVIDER=k3s-hostinger` manually")
            _finish("failed")
            return
        if "__WEBHOOK_SUCCESS__" in refresh_out:
            _write_log("\n✅ *Hostinger refresh complete* — `ubuntu-hostinger` context restored")
        else:
            tail_lines = [l for l in refresh_out.strip().splitlines()[-8:] if l]
            _write_log("\n❌ *Hostinger refresh failed*")
            if tail_lines:
                _write_log("```\n{}\n```".format("\n".join(tail_lines)))
        _finish("success")
    except Exception as exc:
        _write_log(f"ERROR: {exc}")
        _finish("failed")
