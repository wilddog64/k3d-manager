"""Opt-in live operator acceptance profile for k3dm-tests."""
from dataclasses import dataclass
import fcntl
from importlib.machinery import SourceFileLoader
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
from urllib.parse import urlsplit
import urllib.request

from webhook import proc as webhook_proc
from webhook.cloud_actions import JOB_ID_RE
from .drafts import process_run_drafts, scrub_text
from .runner import Scenario, run_scenarios

ROOT = Path(__file__).resolve().parents[3]
PROFILE_NAME = "k3dm-tests"
CLOSED_ACTIONS = frozenset({
    "cluster-status",
    "job-status",
    "make-test-python-unit",
    "make-test-all",
})
WAIT_FINAL_ACTIONS = frozenset({"make-test-python-unit", "make-test-all"})
TERMINAL_JOB_STATES = frozenset({"success", "succeeded", "failed", "killed", "delivery_failed"})
SUCCESS_JOB_STATES = frozenset({"success", "succeeded"})
IN_PROGRESS_STATES = frozenset({"queued", "running", "in_progress"})
GRAFANA_KEYCHAIN_ITEM = "k3dm-grafana-viewer-token"
GRAFANA_DASHBOARD_UID = "k3dm-tests"
DEFAULT_GRAFANA_URL = "https://grafana.3ai-talk.org"
USER_AGENT = "k3dm-operator-acceptance/1"
MAX_BOUNDED_OUTPUT = 16384
_METRICS_SUMMARY_RE = re.compile(r"\[k3dm-test-metrics\]\s+(\d+)\s+cases,\s+(\d+)\s+failed")
_BRIDGE_MODULE = None


class LiveRefusedError(RuntimeError):
    """Raised when live acceptance preconditions or serialization refuse execution."""


class HarnessError(RuntimeError):
    """Raised when an internal live-profile safety invariant is violated."""


@dataclass(frozen=True)
class LiveLeg:
    id: str
    action: str | None
    deadline_s: int
    run: object


def _bridge_gated(action):
    global _BRIDGE_MODULE
    if _BRIDGE_MODULE is None:
        saved_spawn = webhook_proc._spawn_capture_text
        webhook_auth = sys.modules.get("webhook.auth")
        saved_auth_spawn = getattr(webhook_auth, "_spawn_capture_text", None)
        webhook_proc._spawn_capture_text = lambda *_args, **_kwargs: (1, "", False)
        if webhook_auth is not None:
            webhook_auth._spawn_capture_text = lambda *_args, **_kwargs: (1, "", False)
        try:
            loader = SourceFileLoader("k3dm_cloud_bridge_live", str(ROOT / "bin" / "k3dm-cloud-bridge"))
            spec = importlib.util.spec_from_loader(loader.name, loader)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            _BRIDGE_MODULE = module
        finally:
            webhook_proc._spawn_capture_text = saved_spawn
            webhook_auth = sys.modules.get("webhook.auth")
            if webhook_auth is not None:
                webhook_auth._spawn_capture_text = saved_auth_spawn or saved_spawn
    return bool(_BRIDGE_MODULE.gated(action))


def assert_allowed_action(action):
    """Enforce both the closed action list and the cloud-bridge gated() check."""
    if action not in CLOSED_ACTIONS:
        raise HarnessError(f"refused action outside closed list: {action}")
    if _bridge_gated(action):
        raise HarnessError(f"refused gated action: {action}")


def read_viewer_token():
    """Read the Grafana Viewer token by Keychain item name into memory."""
    proc = subprocess.run(
        ["security", "find-generic-password", "-s", GRAFANA_KEYCHAIN_ITEM, "-w"],
        shell=False,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def _helper_env():
    allowed_keys = (
        "PATH",
        "HOME",
        "USER",
        "LOGNAME",
        "SSH_AUTH_SOCK",
        "GIT_SSH_COMMAND",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "PYTHONPATH",
    )
    env = {key: os.environ[key] for key in allowed_keys if key in os.environ}
    for key, val in os.environ.items():
        if key.startswith("K3DM_") and key != "K3DM_ACCEPTANCE_LIVE":
            env[key] = val
    return env


def _build_helper_argv(helper_bin, action, timeout_s, job_id=None):
    assert_allowed_action(action)
    timeout_arg = str(max(1, int(math.ceil(timeout_s))))
    if action == "job-status":
        if not isinstance(job_id, str) or not JOB_ID_RE.fullmatch(job_id):
            raise HarnessError("job-status requires a valid job_id")
        return [
            str(helper_bin),
            "job-status",
            "--arg",
            f"job_id={job_id}",
            "--wait",
            "--timeout",
            timeout_arg,
        ]
    if job_id is not None:
        raise HarnessError(f"unexpected job_id argument for {action}")
    wait_flag = "--wait-final" if action in WAIT_FINAL_ACTIONS else "--wait"
    return [str(helper_bin), action, wait_flag, "--timeout", timeout_arg]


def _parse_json_lines(stdout_text):
    parsed = []
    for raw_line in (stdout_text or "").splitlines():
        line = raw_line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            parsed.append(obj)
    return parsed


def _write_live_artifact(run_dir, name, payload, extra_secrets):
    live_dir = run_dir / "live"
    live_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(live_dir, 0o700)
    target = live_dir / name
    clean = scrub_text(payload, extra_secrets)
    target.write_text(json.dumps(clean, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(target, 0o600)


def _assertion(aid, name, passed, expected, actual, detail="", inconclusive=False):
    entry = {
        "id": aid,
        "name": name,
        "passed": bool(passed),
        "expected": str(expected),
        "actual": str(actual),
        "detail": str(detail),
    }
    if inconclusive:
        entry["inconclusive"] = True
    return entry


def _extract_failed_count(body):
    if not isinstance(body, dict):
        return None
    for key in ("failed_cases", "cases_failed"):
        val = body.get(key)
        if isinstance(val, int) and not isinstance(val, bool):
            return val
    output = body.get("output")
    if isinstance(output, str):
        matches = _METRICS_SUMMARY_RE.findall(output)
        if matches:
            return int(matches[-1][1])
    exit_code = body.get("exit_code")
    if exit_code == 0 and body.get("status") in SUCCESS_JOB_STATES:
        return 0
    return None


def _open_grafana(req, timeout_s, opener=None):
    if opener is not None:
        return opener(req, timeout_s)
    host = urlsplit(req.full_url).hostname or ""
    if host in {"127.0.0.1", "::1", "localhost"}:
        direct = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        return direct.open(req, timeout=timeout_s)
    return urllib.request.urlopen(req, timeout=timeout_s)


def _grafana_json(method, base_url, path, token, *, payload=None, timeout_s=30, opener=None, trace=None):
    url = base_url.rstrip("/") + path
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }
    body_bytes = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body_bytes, headers=headers, method=method)
    redacted_headers = {
        k: ("Bearer ***REDACTED***" if k.lower() == "authorization" else v)
        for k, v in headers.items()
    }
    try:
        with _open_grafana(req, timeout_s, opener=opener) as resp:
            status = getattr(resp, "status", 200)
            raw = resp.read().decode("utf-8", errors="replace")
            resp_headers = dict(getattr(resp, "headers", {}) or {})
    except urllib.error.HTTPError as exc:
        status = exc.code
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else str(exc)
        resp_headers = dict(exc.headers or {})
    except OSError as exc:
        if trace is not None:
            trace.append({
                "method": method,
                "url": url,
                "request_headers": redacted_headers,
                "request_body": payload,
                "status": 0,
                "error": str(exc),
            })
        return 0, None, str(exc)

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = None
    if trace is not None:
        clean_resp_headers = {
            k: ("***REDACTED***" if k.lower() in {"authorization", "set-cookie"} else v)
            for k, v in resp_headers.items()
        }
        trace.append({
            "method": method,
            "url": url,
            "request_headers": redacted_headers,
            "request_body": payload,
            "status": status,
            "response_headers": clean_resp_headers,
            "response_body": parsed if parsed is not None else raw[:1000],
        })
    return status, parsed, raw


def _extract_frame_numbers(query_payload, prefer_target=None):
    if not isinstance(query_payload, dict):
        return []
    results = query_payload.get("results")
    if not isinstance(results, dict):
        return []
    preferred = []
    fallback = []
    for ref_data in results.values():
        if not isinstance(ref_data, dict):
            continue
        for frame in ref_data.get("frames") or []:
            if not isinstance(frame, dict):
                continue
            fields = (frame.get("schema") or {}).get("fields") or []
            columns = (frame.get("data") or {}).get("values") or []
            if not columns:
                continue
            value_idx = None
            labels = {}
            for idx, field in enumerate(fields):
                if not isinstance(field, dict):
                    continue
                if field.get("type") == "time" or field.get("name") == "Time":
                    continue
                value_idx = idx
                labels = field.get("labels") or {}
                break
            if value_idx is None:
                value_idx = len(columns) - 1
            if value_idx >= len(columns) or not isinstance(columns[value_idx], list):
                continue
            non_null = [v for v in columns[value_idx] if v is not None]
            if not non_null:
                continue
            latest = float(non_null[-1])
            if prefer_target and isinstance(labels, dict) and labels.get("target") == prefer_target:
                preferred.append(latest)
            else:
                fallback.append(latest)
    return preferred if preferred else fallback


def build_k3dm_tests_legs(
    state,
    *,
    with_test_all=False,
    helper_bin=None,
    grafana_url=DEFAULT_GRAFANA_URL,
    token_reader=None,
    grafana_opener=None,
    clock=time.time,
    monotonic=time.monotonic,
    sleep_fn=time.sleep,
    poll_interval_s=5.0,
):
    """Construct the closed leg sequence for PROFILE=k3dm-tests."""
    effective_helper = Path(helper_bin) if helper_bin is not None else (ROOT / "bin" / "k3dm-cloud-request")
    effective_token_reader = read_viewer_token if token_reader is None else token_reader

    def submit(ctx, action, timeout_s, job_id=None, artifact_label=None):
        if state.get("halt_reason"):
            raise HarnessError(state["halt_reason"])
        try:
            argv = _build_helper_argv(effective_helper, action, timeout_s, job_id=job_id)
        except HarnessError as exc:
            state["halt_reason"] = str(exc)
            raise
        proc = subprocess.run(
            argv,
            shell=False,
            env=_helper_env(),
            capture_output=True,
            text=True,
            timeout=max(5, int(timeout_s) + 30),
            check=False,
        )
        responses = _parse_json_lines(proc.stdout)
        label = artifact_label or f"{action}.json"
        _write_live_artifact(
            ctx.run_dir,
            label,
            {
                "action": action,
                "returncode": proc.returncode,
                "responses": responses,
                "stderr": (proc.stderr or "")[:2000],
            },
            state["extra_secrets"],
        )
        return proc.returncode, responses, proc.stdout, proc.stderr

    def run_cluster_status(ctx):
        started = monotonic()
        deadline = started + 120
        rc, responses, stdout_text, stderr_text = submit(
            ctx,
            "cluster-status",
            120,
            artifact_label="cluster-status.json",
        )
        terminal = responses[-1] if responses else {}
        body = terminal.get("body") if isinstance(terminal.get("body"), dict) else {}
        poll_num = 0
        while (
            rc == 0
            and terminal.get("status") == "ok"
            and body.get("status") in IN_PROGRESS_STATES
            and isinstance(body.get("job_id"), str)
            and JOB_ID_RE.fullmatch(body["job_id"])
        ):
            remaining = deadline - monotonic()
            if remaining <= 0:
                break
            sleep_fn(min(poll_interval_s, max(0.0, remaining)))
            remaining = deadline - monotonic()
            if remaining <= 0:
                break
            poll_num += 1
            rc, poll_responses, stdout_text, stderr_text = submit(
                ctx,
                "job-status",
                remaining,
                job_id=body["job_id"],
                artifact_label=f"cluster-status-poll-{poll_num}.json",
            )
            if poll_responses:
                terminal = poll_responses[-1]
                body = terminal.get("body") if isinstance(terminal.get("body"), dict) else {}

        top_status = terminal.get("status")
        body_status = body.get("status") if body else None
        if body_status is not None:
            is_terminal_ok = rc == 0 and top_status == "ok" and body_status in SUCCESS_JOB_STATES
            actual = f"rc={rc} status={top_status} body_status={body_status}"
        else:
            is_terminal_ok = rc == 0 and top_status == "ok" and bool(terminal)
            actual = f"rc={rc} status={top_status}"
        return [
            _assertion(
                "cluster-status-terminal",
                "cluster-status returns a terminal ok response",
                is_terminal_ok,
                expected="rc=0 status=ok terminal",
                actual=actual,
                detail=scrub_text((stderr_text or stdout_text or "")[-400:], state["extra_secrets"]),
            )
        ]

    def run_python_unit(ctx):
        rc, responses, stdout_text, stderr_text = submit(
            ctx,
            "make-test-python-unit",
            600,
            artifact_label="make-test-python-unit.json",
        )
        final = responses[-1] if responses else {}
        body = final.get("body") if isinstance(final.get("body"), dict) else {}
        body_status = body.get("status")
        exit_code = body.get("exit_code")
        raw_output = body.get("output")
        valid_exit = isinstance(exit_code, int) and not isinstance(exit_code, bool)
        bounded_text = scrub_text(raw_output[:MAX_BOUNDED_OUTPUT], state["extra_secrets"]) if isinstance(raw_output, str) else ""
        is_bounded = isinstance(raw_output, str) and 0 < len(raw_output) <= MAX_BOUNDED_OUTPUT
        terminal_ok = rc == 0 and final.get("status") == "ok" and body_status in TERMINAL_JOB_STATES
        exit_ok = terminal_ok and valid_exit and exit_code == 0 and body_status in SUCCESS_JOB_STATES
        return [
            _assertion(
                "python-unit-terminal",
                "make-test-python-unit reached terminal job status",
                terminal_ok,
                expected="rc=0 status=ok body.status in terminal states",
                actual=f"rc={rc} status={final.get('status')} body.status={body_status}",
                detail=scrub_text((stderr_text or stdout_text or "")[-300:], state["extra_secrets"]),
            ),
            _assertion(
                "python-unit-exit-code",
                "make-test-python-unit reports original exit code 0",
                exit_ok,
                expected="exit_code=0 body.status=success",
                actual=f"exit_code={exit_code} body.status={body_status}",
                detail=f"exit_code={exit_code} output_tail={bounded_text[-240:]}",
            ),
            _assertion(
                "python-unit-bounded-output",
                "make-test-python-unit returns bounded output",
                is_bounded,
                expected=f"0 < len(output) <= {MAX_BOUNDED_OUTPUT}",
                actual=f"type={type(raw_output).__name__} len={len(raw_output) if isinstance(raw_output, str) else -1}",
                detail=bounded_text[-240:],
            ),
        ]

    def run_test_all(ctx):
        state["test_all_submitted_at"] = clock()
        rc, responses, stdout_text, stderr_text = submit(
            ctx,
            "make-test-all",
            1200,
            artifact_label="make-test-all.json",
        )
        final = responses[-1] if responses else {}
        body = final.get("body") if isinstance(final.get("body"), dict) else {}
        body_status = body.get("status")
        exit_code = body.get("exit_code")
        valid_exit = isinstance(exit_code, int) and not isinstance(exit_code, bool)
        state["test_all_failed_count"] = _extract_failed_count(body)
        terminal_ok = rc == 0 and final.get("status") == "ok" and body_status in TERMINAL_JOB_STATES
        exit_ok = terminal_ok and valid_exit and exit_code == 0 and body_status in SUCCESS_JOB_STATES
        output_tail = scrub_text(str(body.get("output") or "")[-240:], state["extra_secrets"])
        return [
            _assertion(
                "test-all-terminal",
                "make-test-all reached terminal job status",
                terminal_ok,
                expected="rc=0 status=ok body.status in terminal states",
                actual=f"rc={rc} status={final.get('status')} body.status={body_status}",
                detail=scrub_text((stderr_text or stdout_text or "")[-300:], state["extra_secrets"]),
            ),
            _assertion(
                "test-all-exit-code",
                "make-test-all exited 0",
                exit_ok,
                expected="exit_code=0 body.status=success",
                actual=f"exit_code={exit_code} body.status={body_status}",
                detail=f"exit_code={exit_code} failed_count={state['test_all_failed_count']} tail={output_tail}",
            ),
        ]

    def run_grafana(ctx):
        if state.get("halt_reason"):
            raise HarnessError(state["halt_reason"])
        token = effective_token_reader()
        if not token:
            return [
                _assertion(
                    "grafana-viewer-token",
                    "Keychain item k3dm-grafana-viewer-token available",
                    False,
                    expected="non-empty viewer token",
                    actual="missing_or_empty",
                    detail=f"Keychain item {GRAFANA_KEYCHAIN_ITEM} missing or unreadable",
                    inconclusive=True,
                )
            ]
        state["extra_secrets"].add(token)
        trace = []
        dash_status, dash_json, dash_raw = _grafana_json(
            "GET",
            grafana_url,
            f"/api/dashboards/uid/{GRAFANA_DASHBOARD_UID}",
            token,
            opener=grafana_opener,
            trace=trace,
        )
        dashboard = (dash_json or {}).get("dashboard") if isinstance(dash_json, dict) else None
        panels_by_id = {}
        if isinstance(dashboard, dict):
            for panel in dashboard.get("panels") or []:
                if isinstance(panel, dict) and "id" in panel:
                    panels_by_id[panel["id"]] = panel

        panel_results = {}
        panel_http = {}
        for panel_id in (1, 3, 9):
            panel = panels_by_id.get(panel_id)
            targets = (panel or {}).get("targets") or []
            if dash_status != 200 or not targets:
                panel_http[panel_id] = 0
                panel_results[panel_id] = None
                continue
            target = targets[0]
            expr = str(target.get("expr", "")).replace("$__range", "6h")
            datasource = target.get("datasource") or {"type": "prometheus", "uid": "prometheus"}
            query_body = {
                "from": "now-6h",
                "to": "now",
                "queries": [
                    {
                        "refId": "A",
                        "datasource": datasource,
                        "expr": expr,
                        "instant": bool(target.get("instant", True)),
                        "panelId": panel_id,
                    }
                ],
            }
            q_status, q_json, _q_raw = _grafana_json(
                "POST",
                grafana_url,
                "/api/ds/query",
                token,
                payload=query_body,
                opener=grafana_opener,
                trace=trace,
            )
            panel_http[panel_id] = q_status
            panel_results[panel_id] = q_json

        _write_live_artifact(ctx.run_dir, "grafana-k3dm-tests.json", {"requests": trace}, state["extra_secrets"])

        api_ok = (
            dash_status == 200
            and all(panel_id in panels_by_id for panel_id in (1, 3, 9))
            and all(panel_http.get(panel_id) == 200 for panel_id in (1, 3, 9))
        )
        p1_vals = _extract_frame_numbers(panel_results.get(1))
        last_run_raw = p1_vals[-1] if p1_vals else None
        last_run_s = (last_run_raw / 1000.0 if last_run_raw >= 1e11 else last_run_raw) if last_run_raw is not None else None
        submitted_at = state.get("test_all_submitted_at")
        fresh_ok = (
            api_ok
            and last_run_s is not None
            and submitted_at is not None
            and last_run_s >= int(submitted_at)
        )

        p3_vals = _extract_frame_numbers(panel_results.get(3), prefer_target="test-all")
        panel3_failed = int(round(p3_vals[-1])) if p3_vals else None
        expected_failed = state.get("test_all_failed_count")
        count_ok = api_ok and panel3_failed is not None and expected_failed is not None and panel3_failed == expected_failed

        p9_vals = _extract_frame_numbers(panel_results.get(9), prefer_target="test-all")
        panel9_val = int(round(p9_vals[-1])) if p9_vals else None
        complete_ok = api_ok and panel9_val == 1

        return [
            _assertion(
                "grafana-panels-evaluated",
                "Grafana dashboard k3dm-tests and panels 1, 3 and 9 queried",
                api_ok and complete_ok,
                expected="dashboard=200 panels_1_3_9=200 run_complete!=0",
                actual=f"dashboard={dash_status} http={panel_http} panel9={panel9_val}",
                detail=scrub_text(str(dash_raw or "")[:200], state["extra_secrets"]) if dash_status != 200 else f"panel9={panel9_val}",
            ),
            _assertion(
                "grafana-last-run-fresh",
                "panel 1 last-run timestamp is not older than make-test-all submission",
                fresh_ok,
                expected="last_run_s >= submitted_at_s",
                actual="fresh" if fresh_ok else "stale_or_missing_last_run",
                detail=f"last_run_s={last_run_s} submitted_at_s={int(submitted_at) if submitted_at is not None else None}",
            ),
            _assertion(
                "grafana-failed-count-matches",
                "panel 3 failed cases equals make-test-all failed count",
                count_ok,
                expected="panel3_failed == job_failed_count",
                actual=f"panel3_failed={panel3_failed} job_failed_count={expected_failed}",
                detail=f"panel3={panel3_failed} job_failed={expected_failed}",
            ),
        ]

    legs = [
        LiveLeg("cluster-status", "cluster-status", 120, run_cluster_status),
        LiveLeg("make-test-python-unit", "make-test-python-unit", 600, run_python_unit),
    ]
    if with_test_all:
        legs.extend([
            LiveLeg("make-test-all", "make-test-all", 1200, run_test_all),
            LiveLeg("grafana-k3dm-tests", None, 60, run_grafana),
        ])
    return legs


def _normalize_leg(entry, helper_bin, state):
    if isinstance(entry, LiveLeg):
        return entry
    if isinstance(entry, str):
        action = entry

        def _run_injected(ctx):
            if state.get("halt_reason"):
                raise HarnessError(state["halt_reason"])
            argv = _build_helper_argv(helper_bin, action, 60)
            proc = subprocess.run(argv, shell=False, env=_helper_env(), capture_output=True, text=True, timeout=90, check=False)
            return [_assertion(f"{action}-ok", f"{action} completed", proc.returncode == 0, "rc=0", f"rc={proc.returncode}")]

        return LiveLeg(action, action, 60, _run_injected)
    raise TypeError(f"unsupported leg specification: {entry!r}")


def _rescrub_run_dir(run_dir, extra_secrets):
    if not extra_secrets:
        return
    for path in run_dir.rglob("*"):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        cleaned = scrub_text(content, extra_secrets)
        if cleaned != content:
            path.write_text(cleaned, encoding="utf-8")
        os.chmod(path, 0o600)


def run_live_profile(
    run_root=None,
    *,
    profile=PROFILE_NAME,
    with_test_all=False,
    with_prior_art=False,
    legs=None,
    helper_bin=None,
    grafana_url=DEFAULT_GRAFANA_URL,
    token_reader=None,
    grafana_opener=None,
    search_fn=None,
    bugs_dir=None,
    repo_root=None,
    stdin=None,
    out_stream=None,
    clock=time.time,
    monotonic=time.monotonic,
    sleep_fn=time.sleep,
    poll_interval_s=5.0,
):
    """Execute the serialized, opt-in live acceptance profile."""
    if profile != PROFILE_NAME:
        raise LiveRefusedError(f"unsupported live profile: {profile!r} (expected {PROFILE_NAME!r})")
    if os.environ.get("K3DM_ACCEPTANCE_LIVE") != "1":
        raise LiveRefusedError("refusing live acceptance run: set K3DM_ACCEPTANCE_LIVE=1")
    effective_stdin = sys.stdin if stdin is None else stdin
    if not effective_stdin.isatty():
        raise LiveRefusedError("refusing live acceptance run: interactive terminal (TTY stdin) required")

    root = Path(
        run_root or os.environ.get("K3DM_ACCEPTANCE_RUN_ROOT", Path.home() / ".local/state/k3d-manager/acceptance")
    ).expanduser()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)

    lock_path = root / "live.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    os.fchmod(lock_fd, 0o600)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise LiveRefusedError("refusing live acceptance run: another live run holds live.lock") from exc

        state = {
            "extra_secrets": set(),
            "halt_reason": None,
            "test_all_submitted_at": None,
            "test_all_failed_count": None,
        }
        effective_helper = Path(helper_bin) if helper_bin is not None else (ROOT / "bin" / "k3dm-cloud-request")
        raw_legs = (
            build_k3dm_tests_legs(
                state,
                with_test_all=with_test_all,
                helper_bin=effective_helper,
                grafana_url=grafana_url,
                token_reader=token_reader,
                grafana_opener=grafana_opener,
                clock=clock,
                monotonic=monotonic,
                sleep_fn=sleep_fn,
                poll_interval_s=poll_interval_s,
            )
            if legs is None
            else [_normalize_leg(item, effective_helper, state) for item in legs]
        )

        preflight_errors = {}
        for leg in raw_legs:
            if leg.action is None:
                continue
            try:
                assert_allowed_action(leg.action)
            except HarnessError as exc:
                preflight_errors[leg.id] = str(exc)
                if state["halt_reason"] is None:
                    state["halt_reason"] = str(exc)

        stream = sys.stdout if out_stream is None else out_stream
        if not preflight_errors:
            planned = [leg.action for leg in raw_legs if leg.action is not None]
            print(f"live acceptance ({profile}): planned actions: {', '.join(planned)}", file=stream, flush=True)

        scenarios = []
        for leg in raw_legs:
            def _make_runner(bound_leg):
                def _wrapped(ctx):
                    if bound_leg.id in preflight_errors:
                        raise HarnessError(preflight_errors[bound_leg.id])
                    if state.get("halt_reason"):
                        raise HarnessError(state["halt_reason"])
                    return bound_leg.run(ctx)

                return _wrapped

            scenarios.append(
                Scenario(
                    id=leg.id,
                    fixture_revision="live-v1",
                    requires=(),
                    deadline_s=leg.deadline_s,
                    run=_make_runner(leg),
                )
            )

        run_dir, report, passed = run_scenarios(
            run_root=root,
            registry=scenarios,
            capabilities=(),
            extra_secrets=tuple(state["extra_secrets"]),
        )
        _rescrub_run_dir(run_dir, state["extra_secrets"])
        process_run_drafts(
            run_dir,
            report,
            run_root=root,
            bugs_dir=bugs_dir,
            repo_root=repo_root,
            with_prior_art=with_prior_art,
            search_fn=search_fn,
            extra_secrets=tuple(state["extra_secrets"]),
            caught_by="live check",
        )
        _rescrub_run_dir(run_dir, state["extra_secrets"])
        return run_dir, report, passed
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)
