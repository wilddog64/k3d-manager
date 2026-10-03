"""Pure validation tests for the cloud bridge."""

import importlib.machinery
import importlib.util
import json
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
LOADER = importlib.machinery.SourceFileLoader("cloud_bridge", str(ROOT / "bin" / "k3dm-cloud-bridge"))
SPEC = importlib.util.spec_from_loader("cloud_bridge", LOADER)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

from webhook import make_targets

REQUEST_LOADER = importlib.machinery.SourceFileLoader(
    "cloud_request", str(ROOT / "bin" / "k3dm-cloud-request"))
REQUEST_SPEC = importlib.util.spec_from_loader("cloud_request", REQUEST_LOADER)
helper = importlib.util.module_from_spec(REQUEST_SPEC)
REQUEST_SPEC.loader.exec_module(helper)


NOW = datetime(2026, 9, 25, 20, 14, 3, tzinfo=timezone.utc)


def request(action="cluster-status", args=None, expires=None):
    return {
        "schema": 1,
        "action": action,
        "args": {} if args is None else args,
        "requested_by": "claude-cloud",
        "requested_at": "2026-09-25T20:14:03Z",
        "expires_at": (expires or NOW + timedelta(minutes=30)).isoformat().replace("+00:00", "Z"),
    }


@pytest.mark.parametrize("action", ["ask", "analyze", "nope"])
def test_unknown_action_is_rejected(action):
    value, reason = bridge.validate_request(request(action), now=NOW)
    assert value is None
    assert reason == "unknown action"


def test_schema_is_pinned():
    value, reason = bridge.validate_request({**request(), "schema": 2}, now=NOW)
    assert value is None
    assert reason == "unsupported schema"


def test_job_id_metacharacter_is_rejected():
    value, reason = bridge.validate_request(
        request("job-status", {"job_id": "a" * 8 + ";echo pwned"}), now=NOW)
    assert value is None
    assert reason == "invalid job_id"


def test_extra_argument_is_rejected():
    value, reason = bridge.validate_request(
        request("cluster-status", {"unexpected": "value"}), now=NOW)
    assert value is None
    assert reason == "unexpected argument"


def test_expired_request_is_rejected_and_response_consumes_id():
    processed = set()
    value, response = bridge.prepare_request(
        "expired-id", request(expires=NOW - timedelta(seconds=1)), processed, now=NOW)
    assert value is None
    assert "expired-id" in processed
    assert response["id"] == "expired-id"
    assert response["status"] == "rejected"
    assert response["reason"] == "request expired"


def test_replayed_id_is_skipped():
    processed = {"replayed-id"}
    value, response = bridge.prepare_request("replayed-id", request(), processed, now=NOW)
    assert value is None
    assert response is None


def test_oversized_file_is_rejected():
    assert len(json.dumps(request()).encode()) < bridge.MAX_REQUEST_BYTES
    assert bridge.MAX_REQUEST_BYTES == 8 * 1024
    value, reason = bridge.validate_request_bytes(b"{" + b"x" * bridge.MAX_REQUEST_BYTES, now=NOW)
    assert value is None
    assert reason == "request exceeds size cap"


def test_every_allowlisted_parameter_declares_its_own_pattern():
    import re
    """The allowlist binds each parameter to a compiled pattern, so declaring a
    parameter without one is impossible. The first implementation validated on
    `key == "job_id"`, which was correct only because job_id was the sole
    parameter — adding a second would have sent its value into the request path
    with no validation at all."""
    for action, (method, path_template, params, _) in bridge.ACTION_ALLOWLIST.items():
        assert method in ("GET", "POST"), action
        assert isinstance(params, dict), f"{action}: params must map name -> pattern"
        for name, pattern in params.items():
            assert hasattr(pattern, "fullmatch"), f"{action}.{name} has no compiled pattern"
        placeholders = set(re.findall(r"\{([a-z_]+)\}", path_template))
        expected = set() if action.startswith(("make-", "diagnose-")) else set(params)
        assert placeholders == expected, f"{action}: path placeholders and params disagree"


def test_a_second_parameter_is_validated_not_just_job_id(monkeypatch):
    """Proves the value check is pattern-driven rather than keyed on the literal
    name job_id: a synthetic action with a different parameter still rejects a
    value that does not match its pattern."""
    import re
    allowlist = dict(bridge.ACTION_ALLOWLIST)
    allowlist["synthetic"] = ("GET", "/api/v1/synthetic/{cluster}", {"cluster": re.compile(r"[a-z]{1,10}")}, None)
    monkeypatch.setattr(bridge, "ACTION_ALLOWLIST", allowlist)

    bad = request(action="synthetic", args={"cluster": "a; rm -rf /"})
    result, reason = bridge.validate_request(bad, now=NOW)
    assert result is None
    assert reason == "invalid cluster"

    good = request(action="synthetic", args={"cluster": "hub"})
    result, reason = bridge.validate_request(good, now=NOW)
    assert reason is None
    assert result is not None


def test_fetch_updates_the_local_branch_ref_not_only_fetch_head(monkeypatch):
    """git fetch origin cloud-requests writes FETCH_HEAD only — a bare branch name
    makes git ignore the configured refspec, so refs/heads/cloud-requests went
    stale and _write_commit's update-ref failed its old-value check on every
    tick. The refspec must name the local ref explicitly."""
    calls = []

    def fake_spawn(argv, cwd=None, env=None, timeout=15):
        calls.append(argv)
        return 0, "deadbeef\n", False

    monkeypatch.setattr(bridge, "_spawn_capture_text", fake_spawn)
    bridge._fetch(Path("/nonexistent"))

    fetch_argv = [argv for argv in calls if "fetch" in argv][0]
    refspec = fetch_argv[-1]
    assert ":" in refspec, f"fetch refspec {refspec!r} does not write a local ref"
    assert refspec.split(":")[1] == "refs/heads/cloud-requests"


def test_process_tick_skips_fetch_when_remote_tip_is_unchanged(monkeypatch):
    tip = "a" * 40
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: tip)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: pytest.fail("fetch must be skipped"))

    assert bridge.process_tick(Path("/nonexistent"), ROOT, last_tip=tip) == (tip, 0)


def test_process_tick_fetches_once_and_returns_pushed_tip(monkeypatch):
    calls = []
    pushed = "b" * 40
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)

    def fake_fetch(repo):
        calls.append("fetch")
        return "parent"

    monkeypatch.setattr(bridge, "_fetch", fake_fetch)
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: ["20260925T201403Z-cluster-status"])
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, request_id: (request(), None))
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response("", "cluster-status", "ok", 200, body={}))
    monkeypatch.setattr(bridge, "_write_commit", lambda *args: calls.append("write") or pushed)

    assert bridge.process_tick(Path("/nonexistent"), ROOT) == (pushed, 1)
    assert calls == ["fetch", "write"]


def test_process_tick_refetches_after_hitting_max_per_tick(monkeypatch):
    request_ids = [f"20260925T2014{index:02d}Z-cluster-status" for index in range(11)]
    processed = set()
    fetches = []
    remote_tip = ["a" * 40]
    commits = iter(letter * 40 for letter in "bcdefghijkl")

    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: remote_tip[0])
    monkeypatch.setattr(bridge, "_fetch", lambda repo: fetches.append("fetch") or "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set(processed))
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: request_ids)
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, request_id: (request(), None))
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response("", "cluster-status", "ok", 200, body={}))

    def fake_write_commit(repo, parent, request_id, response, artifacts):
        processed.add(request_id)
        commit = next(commits)
        if len(processed) == bridge.MAX_PER_TICK:
            remote_tip[0] = commit
        return commit

    monkeypatch.setattr(bridge, "_write_commit", fake_write_commit)

    first_tip, first_count = bridge.process_tick(Path("/nonexistent"), ROOT)
    second_tip, second_count = bridge.process_tick(Path("/nonexistent"), ROOT, last_tip=first_tip)

    assert (first_tip, first_count) == (None, bridge.MAX_PER_TICK)
    assert (second_tip, second_count) == ("l" * 40, 1)
    assert fetches == ["fetch", "fetch"]
    assert processed == set(request_ids)


def test_slow_health_runs_off_loop_and_main_thread_commits(monkeypatch):
    health_started = threading.Event()
    release_health = threading.Event()
    writes = []
    pushed = "b" * 40
    requests = {
        "20260925T201400Z-health": request("health"),
        "20260925T201401Z-cluster-status": request("cluster-status"),
    }

    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    request_id_calls = [0]
    def request_ids(_repo, _ref):
        request_id_calls[0] += 1
        return list(requests) if request_id_calls[0] == 1 else []
    monkeypatch.setattr(bridge, "_request_ids", request_ids)
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, request_id: (requests[request_id], None))

    def fake_call(value):
        if value["action"] == "health":
            health_started.set()
            assert release_health.wait(2)
        return bridge._response("", value["action"], "ok", 200, body={})

    monkeypatch.setattr(bridge, "_call_webhook", fake_call)
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append(
        (args[2], threading.get_ident())) or pushed)
    bridge._slow_pending.clear()
    first_tip, count = bridge.process_tick(Path("/nonexistent"), ROOT)
    assert health_started.wait(1)
    assert count == 1
    assert [request_id for request_id, _thread_id in writes] == ["20260925T201401Z-cluster-status"]
    assert all(thread_id == threading.get_ident() for _request_id, thread_id in writes)

    release_health.set()
    deadline = time.monotonic() + 2
    while not bridge._slow_responses.qsize() and time.monotonic() < deadline:
        time.sleep(0.01)
    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT, last_tip=first_tip)
    assert count == 1
    assert [request_id for request_id, _thread_id in writes] == [
        "20260925T201401Z-cluster-status", "20260925T201400Z-health"]


def test_queued_make_response_adds_one_watch_entry(monkeypatch):
    watched = []
    pushed = "b" * 40
    make_request = request("make-test-pytest")
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: ["20260925T201403Z-make-test-pytest"])
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, request_id: (make_request, None))
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response(
        "", value["action"], "ok", 202, body={"status": "queued", "job_id": "a" * 8}))
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: watched.append(
        kwargs.get("watch_add")) or pushed)
    bridge.process_tick(Path("/nonexistent"), ROOT)
    assert len(watched) == 1
    assert watched[0]["request_id"] == "20260925T201403Z-make-test-pytest"
    assert watched[0]["job_id"] == "a" * 8


def test_terminal_watch_writes_one_final_response_and_clears_entry(monkeypatch):
    writes = []
    entry = {"request_id": "20260925T201403Z-make-test-pytest", "job_id": "a" * 8,
             "created_at": time.time(), "timeout": 600}
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_read_watching", lambda repo, ref: [entry])
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response(
        "", "job-status", "ok", 200, body={"status": "success", "output": "done"}))
    monkeypatch.setattr(bridge, "job_artifacts", lambda *args: ({"artifacts/x/summary.json": b"{}\n"},
                                                                   ["artifacts/x/summary.json"]))
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append((args, kwargs)) or "a" * 40)
    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT, last_tip="a" * 40)
    assert count == 1
    assert writes[0][1]["final"] is True
    assert writes[0][1]["watch_remove"] == entry["request_id"]
    assert writes[0][0][4] == {"artifacts/x/summary.json": b"{}\n"}


def test_expired_watch_writes_watch_expired_final_response(monkeypatch):
    writes = []
    entry = {"request_id": "20260925T201403Z-make-test-pytest", "job_id": "a" * 8,
             "created_at": 0, "timeout": 1}
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_read_watching", lambda repo, ref: [entry])
    monkeypatch.setattr(bridge.time, "time", lambda: 1000)
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append((args, kwargs)) or "a" * 40)
    bridge.process_tick(Path("/nonexistent"), ROOT, last_tip="a" * 40)
    response = writes[0][0][3]
    assert response["status"] == "error"
    assert response["reason"] == "watch expired"
    assert writes[0][1]["final"] is True


def test_terminal_state_check_is_load_bearing(monkeypatch):
    entry = {"request_id": "20260925T201403Z-make-test-pytest", "job_id": "a" * 8,
             "created_at": time.time(), "timeout": 600}
    writes = []
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_read_watching", lambda repo, ref: [entry])
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response(
        "", "job-status", "ok", 200, body={"status": "success"}))
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append(kwargs) or "a" * 40)
    monkeypatch.setattr(bridge, "TERMINAL_JOB_STATES", ("never",))
    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT, last_tip="a" * 40)
    assert count == 0
    assert writes == []


def test_next_sleep_uses_active_then_idle_interval():
    assert bridge._next_sleep(bridge.IDLE_AFTER_SECONDS - 1, 0) == bridge.ACTIVE_POLL_SECONDS
    assert bridge._next_sleep(bridge.IDLE_AFTER_SECONDS, 0) == bridge.IDLE_POLL_SECONDS


@pytest.mark.parametrize("value", ["not-a-number", "0", "-1"])
def test_invalid_active_poll_override_uses_default(monkeypatch, value):
    monkeypatch.setenv("K3DM_CLOUD_BRIDGE_ACTIVE_POLL", value)
    loader = importlib.machinery.SourceFileLoader("cloud_bridge_override", str(ROOT / "bin" / "k3dm-cloud-bridge"))
    spec = importlib.util.spec_from_loader("cloud_bridge_override", loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.ACTIVE_POLL_SECONDS == 5


@pytest.mark.parametrize("value", ["0", "-1"])
def test_poll_interval_rejects_non_positive_values(value):
    with pytest.raises(SystemExit) as error:
        helper._parse_args(["cluster-status", "--poll-interval", value])
    assert error.value.code == 2


def test_wait_fetches_before_sleep_and_caps_sleep_at_deadline(monkeypatch):
    calls = []
    clock = iter([0, 2, 10])

    monkeypatch.setattr(helper, "_commit_request", lambda request_id, payload: None)
    monkeypatch.setattr(helper.time, "monotonic", lambda: next(clock))
    monkeypatch.setattr(helper.time, "sleep", lambda seconds: calls.append(("sleep", seconds)))

    def fake_git(args, **kwargs):
        calls.append(args[0])
        if args[0] == "show":
            raise RuntimeError("not ready")
        return ""

    monkeypatch.setattr(helper, "_git", fake_git)
    assert helper.main(["cluster-status", "--wait", "--timeout", "5", "--poll-interval", "5"]) == 5
    assert calls == ["fetch", "show", ("sleep", 3), "fetch", "show"]


def test_wait_final_polls_the_final_response_after_queued_response(monkeypatch):
    calls = []
    clock = iter([0, 1, 2])
    monkeypatch.setattr(helper, "_commit_request", lambda request_id, payload: None)
    monkeypatch.setattr(helper.time, "monotonic", lambda: next(clock))
    monkeypatch.setattr(helper.time, "sleep", lambda seconds: calls.append(("sleep", seconds)))

    def fake_git(args, **kwargs):
        calls.append(args)
        if args[0] == "show" and args[1].endswith(".final.json"):
            return json.dumps({"status": "ok", "body": {"status": "success"}})
        if args[0] == "show":
            return json.dumps({"status": "ok", "body": {"status": "queued", "job_id": "a" * 8}})
        return ""

    monkeypatch.setattr(helper, "_git", fake_git)
    assert helper.main(["make-test-pytest", "--wait-final", "--timeout", "5"]) == 0
    assert any(args[0] == "show" and args[1].endswith(".final.json") for args in calls)


def test_request_helper_fetches_the_ref_it_reads_the_response_from():
    """The --wait poll read `git show origin/cloud-requests:responses/<id>.json` but
    refreshed with `git fetch origin cloud-requests` — a bare branch name, which
    writes only FETCH_HEAD. A single-branch or shallow clone, which is what a cloud
    session gets, has no refspec covering the branch, so origin/cloud-requests is
    never created and --wait always exited 5 even with the response on the branch.
    Confirmed against a real `git clone --depth 1 --branch main`."""
    assert ":" in helper.FETCH_REFSPEC, "fetch refspec writes no local ref"
    source, destination = helper.FETCH_REFSPEC.lstrip("+").split(":")
    assert source == "refs/heads/cloud-requests"
    assert destination == helper.RESPONSE_REF


def test_request_helper_fetches_an_unfetched_remote_tip_before_committing(monkeypatch):
    parent = "a" * 40
    calls = []
    fetched = False

    def fake_git(args, cwd=helper.ROOT, env=None, timeout=60):
        nonlocal fetched
        calls.append(args)
        if args[:2] == ["ls-remote", "origin"]:
            return f"{parent}\trefs/heads/cloud-requests\n"
        if args[:2] == ["fetch", "origin"]:
            fetched = True
            return ""
        if args[:3] == ["rev-parse", "--verify", "--quiet"]:
            assert fetched
            return f"{parent}\n"
        if args[0] == "hash-object":
            return "b" * 40 + "\n"
        if args[0] == "write-tree":
            return "c" * 40 + "\n"
        if args[0] == "commit-tree":
            return "d" * 40 + "\n"
        return ""

    monkeypatch.setattr(helper, "_git", fake_git)
    helper._commit_request("20260925T201403Z-cluster-status", request())

    assert calls.index(["fetch", "origin", helper.FETCH_REFSPEC]) < calls.index(
        ["rev-parse", "--verify", "--quiet", helper.RESPONSE_REF])
    assert ["read-tree", parent] in calls


def test_request_helper_actions_and_arguments_match_bridge():
    assert set(helper.ACTION_ALLOWLIST) == set(bridge.ACTION_ALLOWLIST)
    for action in bridge.ACTION_ALLOWLIST:
        assert set(helper.ACTION_ALLOWLIST[action][2]) == set(bridge.ACTION_ALLOWLIST[action][2])


@pytest.mark.parametrize("action, argument", [
    ("make-fix-status", "NS=bad;ns"),
    ("make-find-similar-docs", "Q=$(x)"),
])
def test_request_helper_rejects_invalid_action_arguments_without_filing(action, argument):
    with pytest.raises(SystemExit) as error:
        helper._parse_args([action, "--arg", argument])
    assert error.value.code == 2


KNOWN_UNEXPOSED = frozenset()


def test_make_action_argument_patterns_match_webhook_patterns():
    for action, (_, _, args, target) in bridge.ACTION_ALLOWLIST.items():
        if not action.startswith("make-"):
            continue
        for key, pattern in args.items():
            assert pattern.pattern == make_targets._ARG_PATTERNS[key].pattern


def test_make_actions_are_reader_targets():
    for action, (_, _, _, target) in bridge.ACTION_ALLOWLIST.items():
        if not action.startswith("make-"):
            continue
        assert target in make_targets.MAKE_TARGETS
        if target in {"e2e", "e2e-remote"}:
            continue
        assert make_targets.MAKE_TARGETS[target]["min_role"] == "reader"


def test_make_action_args_match_required_args_only():
    for action, (_, _, args, target) in bridge.ACTION_ALLOWLIST.items():
        if not action.startswith("make-"):
            continue
        required = make_targets.MAKE_TARGETS[target].get("required", ())
        assert set(args) == set(required)


def test_cloud_runner_actions_are_explicit_and_use_the_webhook_runner_pattern():
    assert bridge.ACTION_ALLOWLIST["make-e2e"] == ("POST", "/api/v1/make", {}, "e2e")
    action = bridge.ACTION_ALLOWLIST["make-e2e-remote"]
    assert action[:2] == ("POST", "/api/v1/make")
    assert action[2]["RUNNER"].pattern == make_targets._ARG_PATTERNS["RUNNER"].pattern
    assert action[3] == "e2e-remote"
    assert make_targets.MAKE_TARGETS["e2e"]["min_role"] == "operator"
    assert make_targets.MAKE_TARGETS["e2e"]["timeout"] == 3600


def test_cloud_runner_actions_select_cloud_token_and_other_actions_select_reader(monkeypatch):
    class Response:
        status = 202

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            return b"{}"

    seen = []

    def fake_urlopen(request, timeout):
        seen.append((request.get_header("Authorization"), timeout))
        return Response()

    monkeypatch.setattr(bridge.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(bridge, "_get_cloud_runner_token", lambda: "cloud-runner-test-token")
    monkeypatch.setattr(bridge, "_get_reader_token", lambda: "reader-test-token")
    bridge._call_webhook(request("make-e2e"))
    bridge._call_webhook(request("cluster-status"))
    assert seen == [("Bearer cloud-runner-test-token", bridge.HTTP_TIMEOUT),
                    ("Bearer reader-test-token", bridge.HTTP_TIMEOUT)]
    assert "_get_token" not in Path(ROOT / "bin" / "k3dm-cloud-bridge").read_text()


def test_all_reader_targets_are_exposed_or_explicitly_unexposed():
    exposed = {
        target for action, (_, _, _, target) in bridge.ACTION_ALLOWLIST.items()
        if action.startswith("make-") and target not in {"e2e", "e2e-remote"}
    }
    reader_targets = {
        target for target, spec in make_targets.MAKE_TARGETS.items()
        if spec["min_role"] == "reader"
    }
    assert reader_targets == exposed | KNOWN_UNEXPOSED


def test_make_vuln_scan_rejects_arguments():
    value, reason = bridge.validate_request(
        request("make-vuln-scan", {"NS": "identity"}), now=NOW)
    assert value is None
    assert reason == "unexpected argument"


def test_make_fix_status_requires_ns():
    value, reason = bridge.validate_request(request("make-fix-status"), now=NOW)
    assert value is None
    assert reason == "missing argument"


@pytest.mark.parametrize("namespace, reason", [
    ("identity; rm -rf /", "invalid NS"),
    ("Identity", "invalid NS"),
])
def test_make_fix_status_rejects_invalid_ns(namespace, reason):
    value, actual_reason = bridge.validate_request(
        request("make-fix-status", {"NS": namespace}), now=NOW)
    assert value is None
    assert actual_reason == reason


def test_operator_make_action_is_unknown():
    value, reason = bridge.validate_request(request("make-sync-apps"), now=NOW)
    assert value is None
    assert reason == "unknown action"


def test_make_body_and_empty_post_body():
    make_request = request("make-fix-status", {"NS": "identity"})
    assert bridge._request_body(make_request) == (
        b'{"args": {"NS": "identity"}, "target": "fix-status"}')
    assert bridge._request_body(request("cluster-status")) == b"{}"


TEST_SUITE_ACTIONS = {
    "make-test": ("test", 1200),
    "make-test-bin": ("test-bin", 300),
    "make-test-pytest": ("test-pytest", 600),
    "make-test-python-unit": ("test-python-unit", None),
    "make-test-python": ("test-python", 900),
    "make-test-all": ("test-all", 1800),
}
NEVER_EXPOSED = {
    "up", "down", "cluster", "cluster-up", "cluster-down", "fix-delete-pod", "fix-force-sync",
    "e2e-sandbox", "e2e-replay", "e2e-runner-unlock", "cleanup-stale-sandbox",
    "argocd-upgrade", "index-docs", "sync-apps",
}


@pytest.mark.parametrize("action", sorted(TEST_SUITE_ACTIONS))
def test_test_suite_action_resolves_to_its_reader_target_with_a_declared_timeout(action):
    target, timeout = TEST_SUITE_ACTIONS[action]
    method, path, params, fixed = bridge.ACTION_ALLOWLIST[action]
    assert (method, path, params, fixed) == ("POST", "/api/v1/make", {}, target)
    spec = make_targets.MAKE_TARGETS[target]
    assert spec["min_role"] == "reader"
    if timeout is not None:
        assert spec["timeout"] == timeout


def test_no_lifecycle_or_mutating_target_is_reachable():
    exposed = {fixed for _m, _p, _a, fixed in bridge.ACTION_ALLOWLIST.values() if isinstance(fixed, str)}
    assert not exposed & NEVER_EXPOSED
    assert not {name.removeprefix("make-") for name in bridge.ACTION_ALLOWLIST} & NEVER_EXPOSED
    for _m, _p, _a, fixed in bridge.ACTION_ALLOWLIST.values():
        if isinstance(fixed, str):
            if fixed in {"e2e", "e2e-remote"}:
                continue
            assert make_targets.MAKE_TARGETS[fixed]["min_role"] == "reader", fixed


def test_cloud_runner_set_is_scoped_and_unranked():
    from webhook import policy
    assert policy.CLOUD_RUNNER_TARGETS == {"e2e-remote", "e2e"}
    assert "cloud-runner" not in policy._ROLE_LEVELS
    assert not {"up", "down", "cleanup-stale-sandbox"} & policy.CLOUD_RUNNER_TARGETS
    assert not {"up", "down", "cleanup-stale-sandbox"} & set(bridge.ACTION_ALLOWLIST)
    assert "/api/v1/cluster" not in {entry[1] for entry in bridge.ACTION_ALLOWLIST.values()}


def test_bridge_has_no_runner_lock_probe_or_ssh_call():
    source = Path(ROOT / "bin" / "k3dm-cloud-bridge").read_text()
    assert "E2E_M2_LOCK" not in source
    assert "ssh" not in source.lower()


def test_no_cluster_lifecycle_path_is_reachable_from_the_bridge_or_e2e_verify():
    bridge_source = Path(ROOT / "bin" / "k3dm-cloud-bridge").read_text()
    actions_source = Path(ROOT / "scripts" / "lib" / "webhook" / "cloud_actions.py").read_text()
    assert all(name not in bridge_source for name in ("/api/v1/cluster", "/cluster-up", "/cluster-down", "/cluster-resume"))
    assert "/api/v1/cluster" not in {entry[1] for entry in bridge.ACTION_ALLOWLIST.values()}
    assert all(name not in actions_source for name in ("/cluster-up", "/cluster-down", "/cluster-resume"))
    for relative in ("scripts/plugins/e2e.sh", "scripts/plugins/vcluster.sh"):
        source = Path(ROOT / relative).read_text()
        assert all(name not in source for name in ("deploy_cluster", "destroy_cluster", "bin/cluster-up", "bin/cluster-down"))


def test_cloud_runner_cannot_reach_sandbox():
    from webhook import policy
    assert not policy._policy_allows("cloud-runner", policy._action_policy("/api/v1/make", {"target": "e2e-sandbox"}))


def test_test_suite_actions_take_no_arguments():
    for action in TEST_SUITE_ACTIONS:
        value, reason = bridge.validate_request(
            request(action, {"NS": "identity"}), now=NOW)
        assert value is None
        assert reason == "unexpected argument"


def test_test_suite_actions_post_their_target():
    assert bridge._request_body(request("make-test-pytest")) == (
        b'{"args": {}, "target": "test-pytest"}')
    assert bridge._request_body(request("make-test-python-unit")) == (
        b'{"args": {}, "target": "test-python-unit"}')


DIAGNOSE_ACTIONS = {
    "diagnose-pods": ("get-pods", {"provider": "hostinger", "namespace": "identity"}),
    "diagnose-describe-pod": ("describe-pod", {"provider": "hub", "namespace": "identity", "name": "keycloak-0"}),
    "diagnose-logs": ("logs", {"provider": "aws", "namespace": "shopping-cart-payment", "name": "payment-0"}),
    "diagnose-apps": ("get-apps", {}),
    "diagnose-app": ("describe-app", {"name": "shopping-cart-payment"}),
    "diagnose-appsets": ("get-appsets", {}),
}


@pytest.mark.parametrize("action", sorted(DIAGNOSE_ACTIONS))
def test_diagnose_action_sends_exactly_its_fixed_webhook_action(action):
    webhook_action, args = DIAGNOSE_ACTIONS[action]
    value, reason = bridge.validate_request(request(action, args), now=NOW)
    assert reason is None
    body = json.loads(bridge._request_body(value))
    assert body["action"] == webhook_action
    assert {key: body[key] for key in args} == args
    assert bridge.ACTION_ALLOWLIST[action][1] == "/api/v1/diagnostics"


@pytest.mark.parametrize("action", sorted(DIAGNOSE_ACTIONS))
def test_diagnose_request_cannot_choose_the_webhook_action(action):
    _webhook_action, args = DIAGNOSE_ACTIONS[action]
    value, reason = bridge.validate_request(request(action, {**args, "action": "get-pods-all"}), now=NOW)
    assert value is None
    assert reason == "unexpected argument"


@pytest.mark.parametrize("args, reason", [
    ({"provider": "azure", "namespace": "identity"}, "invalid provider"),
    ({"provider": "hub; id", "namespace": "identity"}, "invalid provider"),
    ({"provider": "hub", "namespace": "Identity"}, "invalid namespace"),
    ({"provider": "hub", "namespace": "identity", "name": "-bad"}, "invalid name"),
])
def test_diagnose_arguments_are_pattern_checked(args, reason):
    action = "diagnose-describe-pod" if "name" in args else "diagnose-pods"
    value, actual = bridge.validate_request(request(action, args), now=NOW)
    assert value is None
    assert actual == reason


@pytest.mark.parametrize("action", sorted(DIAGNOSE_ACTIONS))
def test_diagnose_bodies_pass_the_webhooks_own_validator(action):
    from importlib.machinery import SourceFileLoader
    loader = SourceFileLoader("k3dm_webhook_bridge", str(ROOT / "bin" / "k3dm-webhook"))
    spec = importlib.util.spec_from_loader("k3dm_webhook_bridge", loader)
    webhook = importlib.util.module_from_spec(spec)
    loader.exec_module(webhook)
    _webhook_action, args = DIAGNOSE_ACTIONS[action]
    value, _reason = bridge.validate_request(request(action, args), now=NOW)
    assert webhook._validate_diagnostics_request(json.loads(bridge._request_body(value))) is None
