"""Pure validation tests for the cloud bridge."""

import importlib.machinery
import importlib.util
import json
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
        expected = set() if action.startswith("make-") else set(params)
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
        assert make_targets.MAKE_TARGETS[target]["min_role"] == "reader"


def test_make_action_args_match_required_args_only():
    for action, (_, _, args, target) in bridge.ACTION_ALLOWLIST.items():
        if not action.startswith("make-"):
            continue
        required = make_targets.MAKE_TARGETS[target].get("required", ())
        assert set(args) == set(required)


def test_all_reader_targets_are_exposed_or_explicitly_unexposed():
    exposed = {
        target for action, (_, _, _, target) in bridge.ACTION_ALLOWLIST.items()
        if action.startswith("make-")
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
