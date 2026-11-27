"""Offline tests for the opt-in live operator acceptance profile and local bug drafts."""
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import urllib.error

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from acceptance import drafts, live  # noqa: E402
from hermes.prior_art import RetrievalUnavailable  # noqa: E402


@pytest.fixture(scope="module", autouse=True)
def real_bugs_tree_unchanged():
    bugs_dir = ROOT / "docs" / "bugs"
    before = _dir_digest(bugs_dir)
    yield
    assert _dir_digest(bugs_dir) == before, "real docs/bugs tree changed during live acceptance tests"


class FakeTTY:
    def __init__(self, interactive=True):
        self._interactive = interactive

    def isatty(self):
        return self._interactive


def _load_real_k3dm_tests_dashboard():
    raw = (ROOT / "scripts" / "etc" / "grafana" / "dashboards" / "k3dm-tests-configmap.yaml").read_text(encoding="utf-8")
    json_block = raw.split("  k3dm-tests.json: |", 1)[1]
    dashboard = json.loads("\n".join(line[4:] for line in json_block.splitlines() if line.startswith("    ")))
    # Shape captured 2026-11-26 on m4-air.local against Grafana 12.4.15 GET /api/dashboards/uid/k3dm-tests.
    return {"dashboard": dashboard, "meta": {"slug": "k3dm-tests", "version": 1}}


class StubGrafana:
    """In-process Grafana 12.4.15 stub (captured 2026-11-26, m4-air.local)."""

    def __init__(self, expected_token, last_run_ms, failed_cases=0, run_complete=1, echo_body=""):
        self.expected_token = expected_token
        self.last_run_ms = last_run_ms
        self.failed_cases = failed_cases
        self.run_complete = run_complete
        self.echo_body = echo_body
        self.observed_urls = []
        self.observed_methods = []
        self.dashboard_doc = _load_real_k3dm_tests_dashboard()

    def __call__(self, req, _timeout_s):
        self.observed_urls.append(req.full_url)
        self.observed_methods.append(req.get_method())
        headers = {k.lower(): v for k, v in req.header_items()}
        ua = headers.get("user-agent", "")
        # Cloudflare returns 403 to Python-urllib's default User-Agent (Proof P1, m4-air.local, 2026-11-26).
        if not ua or ua.startswith("Python-urllib"):
            raise urllib.error.HTTPError(req.full_url, 403, "Forbidden", {}, io.BytesIO(b"error code: 1010"))
        if headers.get("authorization") != f"Bearer {self.expected_token}":
            raise urllib.error.HTTPError(req.full_url, 401, "Unauthorized", {}, io.BytesIO(b'{"message":"Unauthorized"}'))

        if req.full_url.endswith("/api/dashboards/uid/k3dm-tests") and req.get_method() == "GET":
            payload = dict(self.dashboard_doc)
            if self.echo_body:
                payload["note"] = self.echo_body
            return _FakeHTTPResponse(200, payload)

        if req.full_url.endswith("/api/ds/query") and req.get_method() == "POST":
            body = json.loads((req.data or b"{}").decode("utf-8"))
            query = (body.get("queries") or [{}])[0]
            expr = query.get("expr", "")
            if "k3dm_test_last_timestamp_seconds" in expr:
                return _FakeHTTPResponse(200, _frame_payload(self.last_run_ms))
            if "k3dm_test_cases_failed" in expr:
                return _FakeHTTPResponse(200, _frame_payload(self.failed_cases, labels={"target": "test-all"}))
            if "k3dm_test_run_complete" in expr:
                return _FakeHTTPResponse(200, _frame_payload(self.run_complete, labels={"target": "test-all"}))
            return _FakeHTTPResponse(200, {"results": {"A": {"status": 200, "frames": []}}})

        raise urllib.error.HTTPError(req.full_url, 404, "Not Found", {}, io.BytesIO(b"not found"))


class _FakeHTTPResponse:
    def __init__(self, status, payload):
        self.status = status
        self.headers = {"Content-Type": "application/json"}
        self._bytes = json.dumps(payload).encode("utf-8")

    def read(self):
        return self._bytes

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def _frame_payload(value, labels=None):
    field = {"name": "Value", "type": "number"}
    if labels is not None:
        field["labels"] = labels
    return {
        "results": {
            "A": {
                "status": 200,
                "frames": [
                    {
                        "schema": {"fields": [{"name": "Time", "type": "time"}, field]},
                        "data": {"values": [[1795736300000], [value]]},
                    }
                ],
            }
        }
    }


def _write_helper_stub(stub_dir, spec_file, calls_file):
    """Create an offline bin/k3dm-cloud-request stub using Proof P2 response shapes (m4-air.local, 2026-11-26)."""
    helper_path = stub_dir / "k3dm-cloud-request"
    script = f"""#!{sys.executable}
import json
from pathlib import Path
import sys

calls_path = Path({str(calls_file)!r})
spec_path = Path({str(spec_file)!r})
existing = json.loads(calls_path.read_text()) if calls_path.exists() else []
existing.append(sys.argv[1:])
calls_path.write_text(json.dumps(existing))

spec = json.loads(spec_path.read_text())
action = sys.argv[1]
entry = spec.get(action, {{}})
if isinstance(entry, list):
    idx = min(sum(1 for item in existing[:-1] if item and item[0] == action), len(entry) - 1)
    entry = entry[idx]
for line in entry.get("lines", []):
    print(line if isinstance(line, str) else json.dumps(line, sort_keys=True))
if entry.get("stderr"):
    print(entry["stderr"], file=sys.stderr)
raise SystemExit(int(entry.get("rc", 0)))
"""
    helper_path.write_text(script, encoding="utf-8")
    helper_path.chmod(0o700)
    return helper_path


def _write_path_stubs(stub_dir, log_file, viewer_token="glsa_TestViewerToken_1"):
    stub_dir.mkdir(mode=0o700, exist_ok=True)
    sec_script = f"""#!{sys.executable}
import json
from pathlib import Path
import sys

log = Path({str(log_file)!r})
rows = json.loads(log.read_text()) if log.exists() else []
rows.append(["security", *sys.argv[1:]])
log.write_text(json.dumps(rows))
if "-s" in sys.argv:
    svc = sys.argv[sys.argv.index("-s") + 1]
    if svc == "k3dm-grafana-viewer-token":
        print({viewer_token!r})
        raise SystemExit(0)
raise SystemExit(44)
"""
    sec_path = stub_dir / "security"
    sec_path.write_text(sec_script, encoding="utf-8")
    sec_path.chmod(0o700)

    for tool in ("git", "curl"):
        tool_path = stub_dir / tool
        tool_script = f"""#!{sys.executable}
import json
from pathlib import Path
import sys

log = Path({str(log_file)!r})
rows = json.loads(log.read_text()) if log.exists() else []
rows.append([{tool!r}, *sys.argv[1:]])
log.write_text(json.dumps(rows))
raise SystemExit(99)
"""
        tool_path.write_text(tool_script, encoding="utf-8")
        tool_path.chmod(0o700)


def _default_helper_spec(python_unit_exit=0, python_unit_status="success", python_unit_output="Ran 12 tests in 0.4s\nOK\n"):
    # Response shapes captured on m4-air.local, 2026-11-26 (Proof P2 in v1.46.0-p3b-acceptance-live-profile.md).
    return {
        "cluster-status": {
            "rc": 0,
            "lines": [
                "20261126T230531Z-cluster-status",
                {
                    "action": "cluster-status",
                    "body": {"job_id": "63c965bd", "status": "queued"},
                    "completed_at": "2026-11-26T23:05:35Z",
                    "http_status": 202,
                    "id": "20261126T230531Z-cluster-status",
                    "schema": 1,
                    "status": "ok",
                },
            ],
        },
        "job-status": {
            "rc": 0,
            "lines": [
                "20261126T230540Z-job-status",
                {
                    "action": "job-status",
                    "body": {
                        "exit_code": 0,
                        "job_id": "63c965bd",
                        "output": "Cluster HEALTHY 21/0/0\n",
                        "result_classification": "passed",
                        "status": "success",
                    },
                    "completed_at": "2026-11-26T23:05:42Z",
                    "http_status": 200,
                    "id": "20261126T230540Z-job-status",
                    "schema": 1,
                    "status": "ok",
                },
            ],
        },
        "make-test-python-unit": {
            "rc": 0,
            "lines": [
                "20261126T230600Z-make-test-python-unit",
                {
                    "action": "make-test-python-unit",
                    "body": {"job_id": "a1b2c3d4", "status": "queued"},
                    "http_status": 202,
                    "id": "20261126T230600Z-make-test-python-unit",
                    "schema": 1,
                    "status": "ok",
                },
                {
                    "action": "job-status",
                    "body": {
                        "exit_code": python_unit_exit,
                        "job_id": "a1b2c3d4",
                        "output": python_unit_output,
                        "result_classification": "passed" if python_unit_exit == 0 else "failed_untriaged",
                        "status": python_unit_status,
                    },
                    "completed_at": "2026-11-26T23:06:15Z",
                    "http_status": 200,
                    "id": "20261126T230600Z-make-test-python-unit",
                    "schema": 1,
                    "status": "ok",
                },
            ],
        },
        "make-test-all": {
            "rc": 0,
            "lines": [
                "20261126T231000Z-make-test-all",
                {
                    "action": "make-test-all",
                    "body": {"job_id": "deadbeef", "status": "queued"},
                    "http_status": 202,
                    "id": "20261126T231000Z-make-test-all",
                    "schema": 1,
                    "status": "ok",
                },
                {
                    "action": "job-status",
                    "body": {
                        "exit_code": 0,
                        "job_id": "deadbeef",
                        "output": "[k3dm-test-metrics] 120 cases, 0 failed\n[test-all] metrics log: /tmp/test.log\n",
                        "result_classification": "passed",
                        "status": "success",
                    },
                    "completed_at": "2026-11-26T23:25:00Z",
                    "http_status": 200,
                    "id": "20261126T231000Z-make-test-all",
                    "schema": 1,
                    "status": "ok",
                },
            ],
        },
    }


def test_bridge_gate_restores_auth_spawn_without_starting_security(monkeypatch):
    from webhook import proc as webhook_proc

    previous_auth = sys.modules.pop("webhook.auth", None)
    previous_bridge = live._BRIDGE_MODULE
    calls = []
    def guarded_spawn(argv, **_kwargs):
        calls.append(argv)
        return 1, "", False
    monkeypatch.setattr(webhook_proc, "_spawn_capture_text", guarded_spawn)
    monkeypatch.setattr(live, "_BRIDGE_MODULE", None)
    try:
        live._bridge_gated("cluster-status")
        auth = sys.modules.get("webhook.auth")
        assert auth is not None
        assert auth._spawn_capture_text is guarded_spawn
        assert all(argv[0] == "security" for argv in calls)
    finally:
        if previous_auth is None:
            sys.modules.pop("webhook.auth", None)
        else:
            sys.modules["webhook.auth"] = previous_auth
        live._BRIDGE_MODULE = previous_bridge


def _dir_digest(directory):
    h = hashlib.sha256()
    for path in sorted(Path(directory).glob("*.md")):
        h.update(path.name.encode("utf-8") + b"\0")
        h.update(hashlib.sha256(path.read_bytes()).digest() + b"\n")
    return h.hexdigest()


@pytest.fixture()
def isolated_live_env(tmp_path, monkeypatch):
    scratch_home = tmp_path / "scratch-home"
    scratch_home.mkdir(mode=0o700)
    run_root = tmp_path / "acceptance-runs"
    stub_dir = tmp_path / "stubs"
    ext_log = tmp_path / "ext-calls.json"
    helper_spec = tmp_path / "helper-spec.json"
    helper_calls = tmp_path / "helper-calls.json"

    _write_path_stubs(stub_dir, ext_log)
    helper_spec.write_text(json.dumps(_default_helper_spec()), encoding="utf-8")
    helper_stub = _write_helper_stub(stub_dir, helper_spec, helper_calls)

    # Assert fixture isolation targets before running any code under test.
    assert scratch_home.resolve() != Path.home().resolve()
    assert helper_stub.resolve() != (ROOT / "bin" / "k3dm-cloud-request").resolve()
    assert run_root.resolve().is_relative_to(tmp_path.resolve())

    monkeypatch.setenv("HOME", str(scratch_home))
    monkeypatch.setenv("PATH", f"{stub_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}")
    monkeypatch.setenv("K3DM_ACCEPTANCE_RUN_ROOT", str(run_root))
    monkeypatch.setenv("K3DM_ACCEPTANCE_LIVE", "1")

    return {
        "scratch_home": scratch_home,
        "run_root": run_root,
        "stub_dir": stub_dir,
        "ext_log": ext_log,
        "helper_spec": helper_spec,
        "helper_calls": helper_calls,
        "helper_stub": helper_stub,
    }


def test_live_profile_submits_fixed_argv_and_writes_schema1_report(isolated_live_env, tmp_path):
    out = io.StringIO()
    run_dir, report, passed = live.run_live_profile(
        isolated_live_env["run_root"],
        helper_bin=isolated_live_env["helper_stub"],
        stdin=FakeTTY(True),
        out_stream=out,
        monotonic=lambda: 1000.0,
        sleep_fn=lambda _s: None,
        bugs_dir=tmp_path / "bugs",
        repo_root=tmp_path,
    )
    assert passed is True
    assert "planned actions: cluster-status, make-test-python-unit" in out.getvalue()
    assert report["schema"] == 1
    assert [s["id"] for s in report["scenarios"]] == ["cluster-status", "make-test-python-unit"]
    assert all(s["outcome"] == "passed" for s in report["scenarios"])
    assert (run_dir.stat().st_mode & 0o777) == 0o700
    assert ((run_dir / "report.json").stat().st_mode & 0o777) == 0o600

    calls = json.loads(isolated_live_env["helper_calls"].read_text(encoding="utf-8"))
    assert calls == [
        ["cluster-status", "--wait", "--timeout", "120"],
        ["job-status", "--arg", "job_id=63c965bd", "--wait", "--timeout", "120"],
        ["make-test-python-unit", "--wait-final", "--timeout", "600"],
    ]


def test_python_unit_oracle_and_grafana_freshness_and_failed_count(isolated_live_env):
    # 1. make-test-python-unit reports original non-zero exit code and bounded output.
    spec_fail = _default_helper_spec(
        python_unit_exit=7,
        python_unit_status="failed",
        python_unit_output="FAIL: test_widget\nAssertionError: expected 1 got 2\n",
    )
    isolated_live_env["helper_spec"].write_text(json.dumps(spec_fail), encoding="utf-8")
    scratch_bugs = isolated_live_env["run_root"].parent / "empty-bugs"
    scratch_bugs.mkdir()
    _dir1, report_fail, passed_fail = live.run_live_profile(
        isolated_live_env["run_root"] / "unit-fail",
        helper_bin=isolated_live_env["helper_stub"],
        bugs_dir=scratch_bugs,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert passed_fail is False
    py_scenario = next(s for s in report_fail["scenarios"] if s["id"] == "make-test-python-unit")
    assert py_scenario["outcome"] == "failed"
    assert py_scenario["cause"] == "product_contract"
    exit_assert = next(a for a in py_scenario["assertions"] if a["id"] == "python-unit-exit-code")
    assert exit_assert["passed"] is False and "exit_code=7" in exit_assert["detail"]
    bound_assert = next(a for a in py_scenario["assertions"] if a["id"] == "python-unit-bounded-output")
    assert bound_assert["passed"] is True and "AssertionError" in bound_assert["detail"]

    # 2. --with-test-all passes when Grafana last-run >= submitted_at and panel 3 matches job failed count.
    isolated_live_env["helper_spec"].write_text(json.dumps(_default_helper_spec()), encoding="utf-8")
    submitted_epoch = 1795736200.4
    grafana_ok = StubGrafana(
        expected_token="glsa_TestViewerToken_1",
        last_run_ms=1795736245 * 1000,
        failed_cases=0,
        run_complete=1,
    )
    assert grafana_ok.expected_token == "glsa_TestViewerToken_1"
    _dir2, report_all, passed_all = live.run_live_profile(
        isolated_live_env["run_root"] / "all-pass",
        with_test_all=True,
        helper_bin=isolated_live_env["helper_stub"],
        grafana_url="https://grafana.stub.test",
        grafana_opener=grafana_ok,
        bugs_dir=scratch_bugs,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        clock=lambda: submitted_epoch,
        sleep_fn=lambda _s: None,
    )
    assert passed_all is True
    assert [s["id"] for s in report_all["scenarios"]] == [
        "cluster-status",
        "make-test-python-unit",
        "make-test-all",
        "grafana-k3dm-tests",
    ]
    assert len(grafana_ok.observed_urls) == 4

    # 3. Stale panel 1 timestamp or mismatched panel 3 failed count fails the Grafana leg.
    grafana_stale = StubGrafana(
        expected_token="glsa_TestViewerToken_1",
        last_run_ms=(int(submitted_epoch) - 30) * 1000,
        failed_cases=2,
        run_complete=1,
    )
    _dir3, report_stale, passed_stale = live.run_live_profile(
        isolated_live_env["run_root"] / "all-stale",
        with_test_all=True,
        helper_bin=isolated_live_env["helper_stub"],
        grafana_url="https://grafana.stub.test",
        grafana_opener=grafana_stale,
        bugs_dir=scratch_bugs,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        clock=lambda: submitted_epoch,
        sleep_fn=lambda _s: None,
    )
    assert passed_stale is False
    graf_scen = next(s for s in report_stale["scenarios"] if s["id"] == "grafana-k3dm-tests")
    assert graf_scen["outcome"] == "failed"
    assert not next(a for a in graf_scen["assertions"] if a["id"] == "grafana-last-run-fresh")["passed"]
    assert not next(a for a in graf_scen["assertions"] if a["id"] == "grafana-failed-count-matches")["passed"]

    grafana_no_data = StubGrafana(
        expected_token="glsa_TestViewerToken_1",
        last_run_ms=1795736245 * 1000,
        failed_cases=0,
        run_complete=None,
    )
    _dir4, report_no_data, passed_no_data = live.run_live_profile(
        isolated_live_env["run_root"] / "all-no-panel9-data",
        with_test_all=True,
        helper_bin=isolated_live_env["helper_stub"],
        grafana_url="https://grafana.stub.test",
        grafana_opener=grafana_no_data,
        bugs_dir=scratch_bugs,
        repo_root=isolated_live_env["run_root"].parent,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        clock=lambda: submitted_epoch,
        sleep_fn=lambda _s: None,
    )
    no_data_scenario = next(s for s in report_no_data["scenarios"] if s["id"] == "grafana-k3dm-tests")
    assert passed_no_data is False and no_data_scenario["outcome"] == "failed"
    assert not next(a for a in no_data_scenario["assertions"] if a["id"] == "grafana-panels-evaluated")["passed"]


def test_failed_product_contract_writes_canonical_draft_and_dedups_second_run(isolated_live_env, tmp_path):
    scratch_bugs = tmp_path / "bugs"
    scratch_bugs.mkdir()
    spec_fail = _default_helper_spec(python_unit_exit=2, python_unit_status="failed", python_unit_output="FAIL suite\n")
    isolated_live_env["helper_spec"].write_text(json.dumps(spec_fail), encoding="utf-8")

    run_dir_1, report_1, passed_1 = live.run_live_profile(
        isolated_live_env["run_root"],
        helper_bin=isolated_live_env["helper_stub"],
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert passed_1 is False
    draft_files = list((run_dir_1 / "drafts").glob("*.md"))
    assert len(draft_files) == 1
    draft_file = draft_files[0]
    fp = draft_file.stem
    assert len(fp) == 12 and all(ch in "0123456789abcdef" for ch in fp)
    assert (draft_file.stat().st_mode & 0o777) == 0o600
    text = draft_file.read_text(encoding="utf-8")
    for header in (
        "**Status:** OPEN — captured, not triaged",
        "**Priority:** P3 (proposed)",
        "**Introduced by:** unknown",
        "**Should have been caught by:** live check",
        "**Introducing change reviewed:** unknown",
        "**Waiting on:** operator decision — since ",
        "**Classified:** pending",
        "**Prior art:** ",
        f"operator-acceptance run {run_dir_1.name}",
    ):
        assert header in text

    # Second run in the same run_root with the same failure writes no new draft and lists seen before.
    run_dir_2, report_2, passed_2 = live.run_live_profile(
        isolated_live_env["run_root"],
        helper_bin=isolated_live_env["helper_stub"],
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert passed_2 is False
    assert not (run_dir_2 / "drafts").exists()
    assert report_2["drafts"][0]["status"] == "seen_before"
    md_2 = (run_dir_2 / "report.md").read_text(encoding="utf-8")
    assert f"seen before: {draft_file}" in md_2

    # Dedup against docs/bugs/*.md containing the fingerprint.
    existing_bug = scratch_bugs / "2026-11-26-known-unit-failure.md"
    existing_bug.write_text(f"# Bug\n\n**Status:** OPEN\n**Priority:** P3\n**Fingerprint:** {fp}\n", encoding="utf-8")
    run_dir_3, _report_3, _passed_3 = live.run_live_profile(
        tmp_path / "fresh-runs",
        helper_bin=isolated_live_env["helper_stub"],
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert not (run_dir_3 / "drafts").exists()
    assert "seen before: bugs/2026-11-26-known-unit-failure.md" in (run_dir_3 / "report.md").read_text(encoding="utf-8")


def test_disallowed_and_gated_actions_stop_with_harness_error_before_helper(isolated_live_env, monkeypatch):
    # B-N1: sandbox-up, make-e2e and an ungated non-allowlisted action stop with harness_error before helper runs.
    for injected in ("sandbox-up", "make-e2e", "make-find-similar-docs", "hostinger-status"):
        _run_dir, report, passed = live.run_live_profile(
            isolated_live_env["run_root"] / f"reject-{injected}",
            legs=[injected, "cluster-status"],
            helper_bin=isolated_live_env["helper_stub"],
            stdin=FakeTTY(True),
            out_stream=io.StringIO(),
        )
        assert passed is False
        assert report["scenarios"][0]["outcome"] == "inconclusive"
        assert report["scenarios"][0]["cause"] == "harness_error"
        assert not isolated_live_env["helper_calls"].exists()

    # Defense-in-depth proof for B-N1 mutant: even if CLOSED_ACTIONS contained make-e2e, gated("make-e2e") stops it.
    monkeypatch.setattr(live, "CLOSED_ACTIONS", live.CLOSED_ACTIONS | {"make-e2e"})
    _run_dir, report_gated, passed_gated = live.run_live_profile(
        isolated_live_env["run_root"] / "reject-gated-only",
        legs=["make-e2e"],
        helper_bin=isolated_live_env["helper_stub"],
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
    )
    assert passed_gated is False
    assert report_gated["scenarios"][0]["outcome"] == "inconclusive"
    assert report_gated["scenarios"][0]["cause"] == "harness_error"
    assert not isolated_live_env["helper_calls"].exists()


def test_refuses_without_env_or_tty_or_when_locked_with_positive_control(isolated_live_env, monkeypatch, tmp_path):
    cli = str(ROOT / "bin" / "k3dm-operator-acceptance")

    # 1. K3DM_ACCEPTANCE_LIVE unset -> refuses (both API and Makefile/CLI), helper never called.
    monkeypatch.delenv("K3DM_ACCEPTANCE_LIVE", raising=False)
    with pytest.raises(live.LiveRefusedError):
        live.run_live_profile(
            isolated_live_env["run_root"],
            helper_bin=isolated_live_env["helper_stub"],
            stdin=FakeTTY(True),
        )
    env_no_live = {k: v for k, v in os.environ.items() if k != "K3DM_ACCEPTANCE_LIVE"}
    proc_make = subprocess.run(
        ["make", "test-operator-acceptance-live", "PROFILE=k3dm-tests"],
        cwd=ROOT,
        env=env_no_live,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc_make.returncode != 0
    proc_bad_profile = subprocess.run(
        ["make", "test-operator-acceptance-live", "PROFILE=wrong"],
        cwd=ROOT,
        env=os.environ.copy(),
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc_bad_profile.returncode == 2
    proc_flag_err = subprocess.run(
        [sys.executable, cli, "--with-test-all"],
        cwd=ROOT,
        env=os.environ.copy(),
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc_flag_err.returncode == 2
    assert not isolated_live_env["helper_calls"].exists()

    # 2. Variable set, stdin NOT a tty -> refuses, helper never called.
    monkeypatch.setenv("K3DM_ACCEPTANCE_LIVE", "1")
    with pytest.raises(live.LiveRefusedError):
        live.run_live_profile(
            isolated_live_env["run_root"],
            helper_bin=isolated_live_env["helper_stub"],
            stdin=FakeTTY(False),
        )
    proc_notty = subprocess.run(
        [sys.executable, cli, "--live", "--run-root", str(isolated_live_env["run_root"])],
        cwd=ROOT,
        env=os.environ.copy(),
        input="",
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc_notty.returncode != 0
    assert not isolated_live_env["helper_calls"].exists()

    # 3. Variable set + interactive TTY, but live.lock already held -> refuses, helper never called.
    isolated_live_env["run_root"].mkdir(mode=0o700, exist_ok=True)
    lock_fd = os.open(isolated_live_env["run_root"] / "live.lock", os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    master_fd, slave_fd = pty.openpty()
    try:
        with pytest.raises(live.LiveRefusedError):
            live.run_live_profile(
                isolated_live_env["run_root"],
                helper_bin=isolated_live_env["helper_stub"],
                stdin=FakeTTY(True),
            )
        proc_locked = subprocess.run(
            [sys.executable, cli, "--live", "--run-root", str(isolated_live_env["run_root"])],
            cwd=ROOT,
            env=os.environ.copy(),
            stdin=slave_fd,
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc_locked.returncode != 0
        assert not isolated_live_env["helper_calls"].exists()
    finally:
        os.close(slave_fd)
        os.close(master_fd)
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

    # 4. Positive control: K3DM_ACCEPTANCE_LIVE=1 + TTY + lock free -> helper stub IS called and succeeds.
    _run_dir, _report, passed = live.run_live_profile(
        isolated_live_env["run_root"],
        helper_bin=isolated_live_env["helper_stub"],
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
        bugs_dir=tmp_path / "bugs",
        repo_root=tmp_path,
    )
    assert passed is True
    assert isolated_live_env["helper_calls"].exists()
    assert len(json.loads(isolated_live_env["helper_calls"].read_text(encoding="utf-8"))) == 3


def test_viewer_token_and_planted_secrets_never_leak_and_no_admin_or_vault_reads(isolated_live_env, tmp_path, capsys, caplog):
    # Source grep: live.py never references the Grafana admin credential or Vault paths.
    live_source = (ROOT / "scripts" / "lib" / "acceptance" / "live.py").read_text(encoding="utf-8")
    for forbidden in ("observability/grafana", "v1/secret", "vault-root", "X-Vault-Token"):
        assert forbidden not in live_source

    canary_viewer = "glsa_CanaryViewerSecret_998877"
    planted_pw = "PlantedPass_445566"
    planted_hook = "https://hooks.slack.com/services/T000/B111/CanarySlackHook"
    planted_xoxb = "xoxb-CanaryBotToken777"

    _write_path_stubs(isolated_live_env["stub_dir"], isolated_live_env["ext_log"], viewer_token=canary_viewer)
    spec = _default_helper_spec(
        python_unit_exit=1,
        python_unit_status="failed",
        python_unit_output=f"FAIL password={planted_pw} {planted_hook} {planted_xoxb}\n",
    )
    isolated_live_env["helper_spec"].write_text(json.dumps(spec), encoding="utf-8")

    grafana = StubGrafana(
        expected_token=canary_viewer,
        last_run_ms=1795736300 * 1000,
        failed_cases=0,
        run_complete=1,
        echo_body=f"echo={canary_viewer} token={planted_pw}",
    )
    scratch_bugs = tmp_path / "bugs"
    scratch_bugs.mkdir()
    out_buf = io.StringIO()

    run_dir, report, passed = live.run_live_profile(
        isolated_live_env["run_root"],
        with_test_all=True,
        helper_bin=isolated_live_env["helper_stub"],
        grafana_url="https://grafana.stub.test",
        grafana_opener=grafana,
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=out_buf,
        clock=lambda: 1795736200.0,
        sleep_fn=lambda _s: None,
    )
    assert passed is False
    assert any((run_dir / "drafts").glob("*.md"))

    ext_calls = json.loads(isolated_live_env["ext_log"].read_text(encoding="utf-8"))
    assert ext_calls == [["security", "find-generic-password", "-s", "k3dm-grafana-viewer-token", "-w"]]

    helper_calls = json.loads(isolated_live_env["helper_calls"].read_text(encoding="utf-8"))
    argv_and_url_entries = [
        *(json.dumps(row) for row in ext_calls),
        *(json.dumps(row) for row in helper_calls),
        *grafana.observed_urls,
    ]
    canaries = (canary_viewer, planted_pw, "https://hooks.slack.com/services/", planted_xoxb)
    for entry in argv_and_url_entries:
        for secret in canaries:
            assert secret not in entry, f"secret leaked in argv/URL: {entry}"

    for file_path in run_dir.rglob("*"):
        if file_path.is_file():
            content = file_path.read_text(encoding="utf-8", errors="replace")
            for secret in canaries:
                assert secret not in content, f"secret leaked in {file_path}"
    assert canary_viewer not in json.dumps(report)

    captured = capsys.readouterr()
    combined_logs = out_buf.getvalue() + captured.out + captured.err + caplog.text
    for secret in canaries:
        assert secret not in combined_logs


def test_drafts_never_leave_run_dir_or_invoke_git_or_curl_or_reopen_bugs(isolated_live_env, tmp_path):
    real_bugs_dir = ROOT / "docs" / "bugs"
    real_before = _dir_digest(real_bugs_dir)

    scratch_bugs = tmp_path / "docs-bugs"
    scratch_bugs.mkdir()
    closed_bug = scratch_bugs / "2026-10-07-existing-closed-bug.md"
    closed_bug.write_text("# Closed\n\n**Status:** LIVE-VERIFIED\n**Priority:** P2\n", encoding="utf-8")
    scratch_before = _dir_digest(scratch_bugs)

    spec_fail = _default_helper_spec(python_unit_exit=5, python_unit_status="failed", python_unit_output="FAIL case\n")
    isolated_live_env["helper_spec"].write_text(json.dumps(spec_fail), encoding="utf-8")

    run_dir, _report, passed = live.run_live_profile(
        isolated_live_env["run_root"],
        helper_bin=isolated_live_env["helper_stub"],
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert passed is False
    # Negative assertions first: git and curl stubs recorded nothing; docs/bugs and scratch_bugs are untouched.
    assert not isolated_live_env["ext_log"].exists()
    assert _dir_digest(real_bugs_dir) == real_before, "docs/bugs hash changed"
    assert _dir_digest(scratch_bugs) == scratch_before, "bugs_dir hash changed"
    assert "**Status:** LIVE-VERIFIED" in closed_bug.read_text(encoding="utf-8")

    # Positive control: a draft was created inside run_dir/drafts.
    written_drafts = list((run_dir / "drafts").glob("*.md"))
    assert len(written_drafts) == 1


def test_prior_art_unavailable_preserves_outcomes_and_records_unavailability(isolated_live_env, tmp_path):
    scratch_bugs = tmp_path / "bugs"
    scratch_bugs.mkdir()

    def raise_unavailable(_query, k=3):
        raise RetrievalUnavailable("vector store offline")

    # 1. Failing run: without --with-prior-art vs with --with-prior-art raising RetrievalUnavailable.
    spec_fail = _default_helper_spec(python_unit_exit=1, python_unit_status="failed", python_unit_output="FAIL x\n")
    isolated_live_env["helper_spec"].write_text(json.dumps(spec_fail), encoding="utf-8")
    prior_art_called = []

    def unexpected_search(*_args, **_kwargs):
        prior_art_called.append(True)
        return []

    _d_no, rep_no, pass_no = live.run_live_profile(
        tmp_path / "runs-without-pa",
        with_prior_art=False,
        helper_bin=isolated_live_env["helper_stub"],
        search_fn=unexpected_search,
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert prior_art_called == []

    dir_pa, rep_pa, pass_pa = live.run_live_profile(
        tmp_path / "runs-with-pa-down",
        with_prior_art=True,
        helper_bin=isolated_live_env["helper_stub"],
        search_fn=raise_unavailable,
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert pass_pa == pass_no is False
    assert [(s["id"], s["outcome"], s["cause"]) for s in rep_pa["scenarios"]] == [
        (s["id"], s["outcome"], s["cause"]) for s in rep_no["scenarios"]
    ]
    assert "retrieval unavailable" in (dir_pa / "report.md").read_text(encoding="utf-8").lower()
    draft_md = next((dir_pa / "drafts").glob("*.md")).read_text(encoding="utf-8")
    assert "retrieval unavailable" in draft_md.lower()

    # 2. Passing run: RetrievalUnavailable with --with-prior-art does NOT fail the run and is recorded.
    isolated_live_env["helper_spec"].write_text(json.dumps(_default_helper_spec()), encoding="utf-8")
    dir_ok_pa, rep_ok_pa, pass_ok_pa = live.run_live_profile(
        tmp_path / "runs-pass-pa-down",
        with_prior_art=True,
        helper_bin=isolated_live_env["helper_stub"],
        search_fn=raise_unavailable,
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    assert pass_ok_pa is True
    assert all(s["outcome"] == "passed" for s in rep_ok_pa["scenarios"])
    assert "retrieval unavailable" in (dir_ok_pa / "report.md").read_text(encoding="utf-8").lower()

    # 3. Advisory top-3 candidates recorded when prior_art.search succeeds.
    isolated_live_env["helper_spec"].write_text(json.dumps(spec_fail), encoding="utf-8")
    dir_adv, _rep_adv, _pass_adv = live.run_live_profile(
        tmp_path / "runs-pa-advisory",
        with_prior_art=True,
        helper_bin=isolated_live_env["helper_stub"],
        search_fn=lambda _q, k=3: [
            (0.91, "docs/bugs/a.md", "Bug A"),
            (0.84, "docs/bugs/b.md", "Bug B"),
            (0.77, "docs/bugs/c.md", "Bug C"),
            (0.62, "docs/bugs/d.md", "Bug D"),
        ][:k],
        bugs_dir=scratch_bugs,
        repo_root=tmp_path,
        stdin=FakeTTY(True),
        out_stream=io.StringIO(),
        sleep_fn=lambda _s: None,
    )
    adv_draft = next((dir_adv / "drafts").glob("*.md")).read_text(encoding="utf-8")
    assert "docs/bugs/a.md" in adv_draft and "docs/bugs/c.md" in adv_draft and "docs/bugs/d.md" not in adv_draft
    assert drafts.normalise_field("  A  B ") == "a b"
