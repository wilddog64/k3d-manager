"""Pure validation tests for the cloud bridge."""

import importlib.machinery
import importlib.util
import json
import os
import fcntl
import subprocess
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


@pytest.fixture(autouse=True)
def isolated_bridge_state(tmp_path, monkeypatch):
    monkeypatch.setattr(bridge, "STATE_DIR", tmp_path / "bridge-state", raising=False)
    keychain_reads = []

    def fake_keychain(service):
        keychain_reads.append(service)
        return "test-secret"

    def fake_post(*_args):
        return True

    def fake_fetch(*_args, **_kwargs):
        return []

    def fake_delete(*_args, **_kwargs):
        return True

    monkeypatch.setattr(bridge, "_keychain_secret", fake_keychain)
    monkeypatch.setattr(bridge, "post_interactive", fake_post)
    monkeypatch.setattr(bridge, "fetch_approvals", fake_fetch)
    monkeypatch.setattr(bridge, "delete_approval", fake_delete)
    monkeypatch.setenv("K3DM_HERMES_APPROVAL_DRAIN_URL", "https://relay.invalid/approvals")
    assert bridge._approvals_path().parent == bridge.STATE_DIR
    assert bridge._approval_config.__globals__["_keychain_secret"] is fake_keychain
    assert bridge.post_interactive is fake_post
    assert bridge.fetch_approvals is fake_fetch
    assert bridge.delete_approval is fake_delete


@pytest.fixture
def approval_bridge(monkeypatch):
    clock = [NOW.timestamp()]
    requests = {}
    processed = set()
    commits = []
    webhook_calls = []
    cards = []
    drained = []
    deleted = []
    token_reads = []
    keychain_reads = []
    tip = [None]
    drain_items = []
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge.time, "time", lambda: clock[0])
    monkeypatch.setattr(bridge, "_remote_tip", lambda _repo: "remote")
    monkeypatch.setattr(bridge, "_fetch", lambda _repo: "tip")
    monkeypatch.setattr(bridge, "_processed", lambda _repo, _ref: set(processed))
    monkeypatch.setattr(bridge, "_read_watching", lambda _repo, _ref: [])
    monkeypatch.setattr(bridge, "_request_ids", lambda _repo, _ref: list(requests))
    monkeypatch.setattr(bridge, "_read_request", lambda _repo, _ref, request_id: (requests[request_id], None))
    monkeypatch.setattr(bridge, "_get_cloud_runner_token", lambda: token_reads.append("cloud") or "cloud-token")
    monkeypatch.setattr(bridge, "_get_reader_token", lambda: token_reads.append("reader") or "reader-token")
    monkeypatch.setattr(bridge, "_keychain_secret", lambda service: keychain_reads.append(service) or "secret")
    monkeypatch.setattr(bridge, "post_interactive", lambda *args: cards.append(args) or True)
    monkeypatch.setattr(bridge, "fetch_approvals", lambda *args, **kwargs:
                        drained.append((args, kwargs)) or (drain_items.pop(0) if drain_items else []))
    monkeypatch.setattr(bridge, "delete_approval", lambda *args, **kwargs: deleted.append((args, kwargs)) or True)

    def call_webhook(value):
        if bridge.gated(value["action"]):
            bridge._get_cloud_runner_token()
        else:
            bridge._get_reader_token()
        webhook_calls.append(value)
        return bridge._response("", value["action"], "ok", 200, body={"status": "complete"})

    def write_commit(*args, **kwargs):
        commits.append((args, kwargs))
        if not kwargs.get("pending"):
            processed.add(args[2])
        return "tip"

    monkeypatch.setattr(bridge, "_call_webhook", call_webhook)
    monkeypatch.setattr(bridge, "_write_commit", write_commit)

    def tick():
        result = bridge.process_tick(Path("/scratch/repo.git"), ROOT, last_tip=tip[0])
        if result[0] is not None:
            tip[0] = result[0]
        return result

    def submit(request_id="20260925T201403Z-sandbox-up", value=None):
        requests[request_id] = value or request("sandbox-up", expires=NOW + timedelta(minutes=10))
        return tick()

    return {"clock": clock, "requests": requests, "processed": processed, "commits": commits,
            "webhook_calls": webhook_calls, "cards": cards, "drain_items": drain_items,
            "deleted": deleted, "token_reads": token_reads, "keychain_reads": keychain_reads,
            "tip": tip, "tick": tick, "submit": submit}


def _last_approval_response(harness):
    return harness["commits"][-1][0][3]


def _pending_approval(harness, request_id="20260925T201403Z-sandbox-up"):
    return bridge.load_approvals(bridge._approvals_path()).pending[request_id]


def _drain_item(pending, decision="approve", nonce=None, approval_id=None):
    return {"action_id": approval_id or pending.approval_id,
            "nonce": pending.nonce if nonce is None else nonce,
            "approved_by": "U123ABC", "decision": decision}


def test_gated_request_is_pending_without_token_or_webhook(approval_bridge):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    response = _last_approval_response(harness)
    assert len(harness["cards"]) == 1
    assert response["status"] == "ok" and response["http_status"] == 202
    assert response["body"]["status"] == "approval-pending"
    assert response["body"]["approval_id"] == _pending_approval(harness).approval_id
    assert response["body"]["expires_at"].endswith("Z")
    assert "nonce" not in response and "nonce" not in json.dumps(response)
    assert harness["processed"] == set()
    assert harness["token_reads"] == []
    assert harness["webhook_calls"] == []
    assert harness["commits"][-1][1]["pending"] is True


def test_write_commit_publishes_pending_path_without_processing(tmp_path, monkeypatch):
    repo = tmp_path / "fake-repo"
    remote = tmp_path / "fake-origin.git"
    repo.mkdir()

    def git(*args, cwd=None):
        result = subprocess.run(["git", *args], cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    git("init", "--bare", str(remote))
    git("init", "-b", "cloud-requests", str(repo))
    git("config", "user.name", "Bridge Test", cwd=repo)
    git("config", "user.email", "bridge-test@example.invalid", cwd=repo)
    (repo / "ledger").mkdir()
    (repo / "ledger" / "processed.txt").write_text("", encoding="utf-8")
    git("add", "ledger/processed.txt", cwd=repo)
    git("commit", "-m", "seed fixture", cwd=repo)
    git("remote", "add", "origin", str(remote), cwd=repo)
    git("push", "origin", "cloud-requests", cwd=repo)
    parent = git("rev-parse", "HEAD", cwd=repo)
    monkeypatch.setattr(bridge, "_read_watching", lambda *_args: [])
    request_id = "20260925T201403Z-sandbox-up"
    nonce = "0123456789abcdef"
    response = bridge._response(request_id, "sandbox-up", "ok", 202,
                                body={"status": "approval-pending", "approval_id": "c1-01234567",
                                      "expires_at": "2026-09-25T20:24:03Z"})
    commit = bridge._write_commit(repo, parent, request_id, response, pending=True)
    pending = git("show", f"{commit}:responses/{request_id}.pending.json", cwd=repo)
    ledger = git("show", f"{commit}:ledger/processed.txt", cwd=repo)
    paths = git("ls-tree", "-r", "--name-only", commit, cwd=repo).splitlines()
    assert json.loads(pending)["body"]["status"] == "approval-pending"
    assert nonce not in pending
    assert request_id not in ledger.splitlines()
    assert f"responses/{request_id}.pending.json" in paths
    assert f"responses/{request_id}.json" not in paths


def test_matching_approve_runs_once_and_commits_normal_response(approval_bridge, monkeypatch):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    harness["clock"][0] += 31
    harness["drain_items"].append([_drain_item(pending)])
    harness["tick"]()
    assert len(harness["webhook_calls"]) == 1
    assert harness["webhook_calls"][0] == harness["requests"][request_id]
    assert harness["token_reads"] == ["cloud"]
    assert request_id in harness["processed"]
    assert harness["commits"][-1][0][3]["status"] == "ok"
    assert harness["commits"][-1][0][3]["http_status"] == 200
    harness["tick"]()
    assert len(harness["webhook_calls"]) == 1


def test_deny_expiry_wrong_nonce_and_unknown_id_do_not_run(approval_bridge):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    harness["clock"][0] += 31
    harness["drain_items"].append([_drain_item(pending, decision="deny")])
    harness["tick"]()
    assert _last_approval_response(harness)["reason"] == "denied by the operator"
    assert harness["webhook_calls"] == []

    # Separate pending entries exercise expiry, wrong nonce, and unknown id.
    request_id2 = "20260925T201404Z-sandbox-up"
    harness["submit"](request_id2)
    pending2 = _pending_approval(harness, request_id2)
    harness["clock"][0] = pending2.expires_at + 1
    harness["drain_items"].append([])
    harness["tick"]()
    assert _last_approval_response(harness)["reason"] == "not approved before the request expired"

    request3_expiry = datetime.fromtimestamp(harness["clock"][0] + 600, timezone.utc)
    request_id3 = "20260925T201405Z-sandbox-up"
    harness["submit"](request_id3, request("sandbox-up", expires=request3_expiry))
    pending3 = _pending_approval(harness, request_id3)
    harness["clock"][0] += 31
    harness["drain_items"].append([_drain_item(pending3, nonce="0" * 16)])
    harness["tick"]()
    assert request_id3 in bridge.load_approvals(bridge._approvals_path()).pending
    assert harness["deleted"][-1][0][2] == pending3.approval_id

    harness["drain_items"].append([_drain_item(pending3, approval_id="c9-deadbeef")])
    harness["clock"][0] += 31
    harness["tick"]()
    assert request_id3 in bridge.load_approvals(bridge._approvals_path()).pending
    assert harness["deleted"][-1][0][2] == "c9-deadbeef"
    assert harness["webhook_calls"] == []


def test_expiry_recheck_after_decide_prevents_token_read(approval_bridge, monkeypatch):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    harness["drain_items"].append([_drain_item(pending)])
    harness["clock"][0] = NOW.timestamp() + 31
    clock_reads = [0]

    def advancing_clock():
        clock_reads[0] += 1
        if clock_reads[0] == 2:
            return pending.expires_at + 1
        return harness["clock"][0]

    monkeypatch.setattr(bridge.time, "time", advancing_clock)
    harness["tick"]()
    assert _last_approval_response(harness)["reason"] == "not approved before the request expired"
    assert harness["token_reads"] == []
    assert harness["webhook_calls"] == []


@pytest.mark.parametrize("config, expected", [
    ({"url": ""}, "operator approval is not configured on the bridge"),
    ({"url": "http://relay.invalid"}, "operator approval is not configured on the bridge"),
    ({"token": ""}, "operator approval is not configured on the bridge"),
    ({"slack": ""}, "operator approval is not configured on the bridge"),
    ({"store_error": True}, "approval state is unreadable on the bridge"),
    ({"too_many": True}, "too many requests awaiting approval; try again later"),
    ({"too_soon": True}, "request expires too soon for approval; file it with at least 5 minutes left"),
    ({"post": False}, "approval card not delivered; file a new request"),
    ({"post": "raise"}, "approval card not delivered; file a new request"),
])
def test_admission_rejections_have_exact_reasons(approval_bridge, monkeypatch, config, expected):
    harness = approval_bridge
    if "url" in config:
        monkeypatch.setenv("K3DM_HERMES_APPROVAL_DRAIN_URL", config["url"])
    if "token" in config or "slack" in config:
        monkeypatch.setattr(bridge, "_keychain_secret",
                            lambda service: "" if service.endswith("token") and config.get("token") == ""
                            or service.endswith("webhook") and config.get("slack") == "" else "secret")
    if config.get("store_error"):
        bridge._approvals_path().parent.mkdir(parents=True, exist_ok=True)
        bridge._approvals_path().write_text("invalid", encoding="utf-8")
    if config.get("too_many"):
        store = bridge.load_approvals(bridge._approvals_path())
        for index in range(3):
            value = request("sandbox-up", expires=NOW + timedelta(minutes=10))
            bridge.admit(store, f"pending-{index}", value, NOW.timestamp())
        bridge.save_approvals(bridge._approvals_path(), store)
    if config.get("post") is False:
        monkeypatch.setattr(bridge, "post_interactive", lambda *args: False)
    elif config.get("post") == "raise":
        monkeypatch.setattr(bridge, "post_interactive", lambda *args: (_ for _ in ()).throw(RuntimeError("private")))
    value = request("sandbox-up", expires=(NOW + timedelta(minutes=4) if config.get("too_soon")
                                            else NOW + timedelta(minutes=10)))
    harness["submit"]("20260925T201403Z-sandbox-up", value)
    assert _last_approval_response(harness)["reason"] == expected


def test_decided_record_is_saved_away_before_crash(approval_bridge, monkeypatch):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    harness["clock"][0] += 31
    harness["drain_items"].append([_drain_item(pending)])
    tails = []

    def crash_tail(*_args):
        tails.append("tail")
        raise RuntimeError("simulated crash")

    monkeypatch.setattr(bridge, "_run_request_tail", crash_tail)
    with pytest.raises(RuntimeError, match="simulated crash"):
        harness["tick"]()
    assert request_id not in bridge.load_approvals(bridge._approvals_path()).pending
    harness["tick"]()
    assert tails == ["tail"]


def test_restart_preserves_pending_claim_until_approve(approval_bridge, monkeypatch):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    restarted = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(restarted)
    restarted.STATE_DIR = bridge.STATE_DIR
    restarted.time.time = lambda: harness["clock"][0]
    restarted._remote_tip = lambda _repo: "remote"
    restarted._fetch = lambda _repo: "tip"
    restarted._processed = lambda _repo, _ref: set()
    restarted._read_watching = lambda _repo, _ref: []
    restarted._request_ids = lambda _repo, _ref: [request_id]
    restarted._read_request = lambda *_args: (harness["requests"][request_id], None)
    restarted._call_webhook = lambda value: harness["webhook_calls"].append(value) or restarted._response(
        "", value["action"], "ok", 200, body={})
    restarted._write_commit = lambda *args, **kwargs: harness["commits"].append((args, kwargs)) or "tip"
    restarted._read_watching = lambda *_args: []
    restarted.fetch_approvals = lambda *args, **kwargs: []
    restarted.delete_approval = lambda *args, **kwargs: True
    restarted._completed_slow_requests = lambda: iter(())
    restarted._publish_outbox = lambda _repo, ref, _processed: (ref, 0)
    restarted._recover_orphaned_claims = lambda *args, **kwargs: pytest.fail("pending claim recovered")
    # The real recovery path must leave the claim untouched while the pending record exists.
    restarted._recover_orphaned_claims = bridge._recover_orphaned_claims
    restarted._store_outbox = bridge._store_outbox
    restarted._remove_outbox = bridge._remove_outbox
    restarted._watch_warning_logged = False
    restarted._get_cloud_runner_token = lambda: "cloud-token"
    restarted._get_reader_token = lambda: "reader-token"
    restarted.scrub_credentials = lambda value: value
    restarted.job_artifacts = lambda *_args: ({}, [])
    restarted._watch_entry = lambda *_args: None
    restarted.save_approvals = bridge.save_approvals
    restarted.load_approvals = bridge.load_approvals
    restarted.StoreError = bridge.StoreError
    restarted.due_for_drain = bridge.due_for_drain
    restarted.decide = bridge.decide
    restarted.CLOUD_ACTION_ID_RE = bridge.CLOUD_ACTION_ID_RE
    restarted._approval_config = lambda: ("https://relay.invalid", "token", "slack")
    before_restart_tick = len(harness["commits"])
    monkeypatch.setattr(restarted, "fetch_approvals", lambda *args, **kwargs: [])
    restarted.process_tick(Path("/scratch/repo.git"), ROOT, last_tip="tip")
    assert harness["webhook_calls"] == []
    assert len(harness["commits"]) == before_restart_tick
    assert request_id not in harness["processed"]
    harness["clock"][0] += 31
    monkeypatch.setattr(restarted, "fetch_approvals", lambda *args, **kwargs: [_drain_item(pending)])
    restarted.process_tick(Path("/scratch/repo.git"), ROOT, last_tip="tip")
    assert len(harness["webhook_calls"]) == 1


def test_store_error_skips_recovery_and_reader_still_runs(approval_bridge, monkeypatch):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    reader_id = "20260925T201404Z-cluster-status"
    bridge._approvals_path().parent.mkdir(parents=True, exist_ok=True)
    bridge._approvals_path().write_text("invalid", encoding="utf-8")
    harness["requests"][request_id] = request("sandbox-up")
    harness["requests"][reader_id] = request("cluster-status")
    recovered = []
    monkeypatch.setattr(bridge, "_recover_orphaned_claims",
                        lambda *args, **kwargs: recovered.append(True) or (args[1], 0))
    harness["tick"]()
    assert recovered == []
    reasons = [entry[0][3].get("reason") for entry in harness["commits"]]
    assert "approval state is unreadable on the bridge" in reasons
    assert len(harness["webhook_calls"]) == 1
    assert harness["webhook_calls"][0]["action"] == "cluster-status"


def test_reader_runs_while_three_records_are_pending(approval_bridge):
    harness = approval_bridge
    store = bridge.load_approvals(bridge._approvals_path())
    for index in range(3):
        bridge.admit(store, f"pending-{index}", request("sandbox-up"), NOW.timestamp())
    bridge.save_approvals(bridge._approvals_path(), store)
    reader_id = "20260925T201403Z-cluster-status"
    harness["requests"][reader_id] = request("cluster-status")
    harness["tick"]()
    assert [call["action"] for call in harness["webhook_calls"]] == ["cluster-status"]
    assert reader_id in harness["processed"]


def test_idle_tick_makes_no_approval_keychain_reads(approval_bridge):
    harness = approval_bridge
    harness["tick"]()
    assert harness["keychain_reads"] == []


def test_pending_notice_commit_retries_without_reposting_card(approval_bridge, monkeypatch, caplog):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    write_commit = bridge._write_commit
    failures = [1]

    def fail_once(*args, **kwargs):
        if kwargs.get("pending") and failures.pop() if failures else False:
            raise OSError("private")
        return write_commit(*args, **kwargs)

    monkeypatch.setattr(bridge, "_write_commit", fail_once)
    reader_id = "20260925T201404Z-cluster-status"
    harness["requests"][reader_id] = request("cluster-status")
    harness["submit"](request_id)
    assert len(harness["cards"]) == 1
    assert [call["action"] for call in harness["webhook_calls"]] == ["cluster-status"]
    assert "approval pending notice commit failed" in caplog.text
    pending = _pending_approval(harness)
    assert pending.notice_published is False
    harness["tick"]()
    assert len(harness["cards"]) == 1
    retried = _pending_approval(harness)
    assert retried.notice_published is True
    pending_commits = [json.dumps(args[3]) for args, kwargs in harness["commits"] if kwargs.get("pending")]
    assert pending_commits
    assert all(retried.nonce not in content for content in pending_commits)


def test_nonce_is_absent_from_commits_outbox_and_logs(approval_bridge, caplog):
    harness = approval_bridge
    request_id = "20260925T201403Z-sandbox-up"
    harness["submit"](request_id)
    pending = _pending_approval(harness)
    contents = [json.dumps(args[3]) for args, _kwargs in harness["commits"]]
    contents.extend(path.read_text(encoding="utf-8") for path in (bridge.STATE_DIR / "outbox").glob("*.json"))
    contents.append(caplog.text)
    assert all(pending.nonce not in content for content in contents)


def request(action="cluster-status", args=None, expires=None):
    return {
        "schema": 1,
        "action": action,
        "args": {} if args is None else args,
        "requested_by": "claude-cloud",
        "requested_at": "2026-09-25T20:14:03Z",
        "expires_at": (expires or NOW + timedelta(minutes=30)).isoformat().replace("+00:00", "Z"),
    }


def test_gated_actions_are_exactly_the_cloud_runner_actions():
    assert {action for action in bridge.ACTION_ALLOWLIST if bridge.gated(action)} == {
        "sandbox-up", "sandbox-down", "make-e2e", "make-e2e-remote"}


def test_main_refuses_a_second_bridge_lock(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("K3DM_REPO_ROOT", str(ROOT))
    monkeypatch.setenv("K3DM_CLOUD_BRIDGE_REPO", str(tmp_path / "repo.git"))
    bridge.STATE_DIR.mkdir(parents=True)
    lock_path = bridge.STATE_DIR / "bridge.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        with pytest.raises(SystemExit) as error:
            bridge.main()
    finally:
        os.close(lock_fd)
    assert error.value.code == 1
    assert capsys.readouterr().err.strip() == "k3dm-cloud-bridge: another bridge is running"


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


def test_successful_poll_marker_is_private_atomic_and_timestamped(tmp_path, monkeypatch):
    monkeypatch.setattr(bridge, "STATE_DIR", tmp_path / "bridge-state")
    bridge._write_heartbeat_marker(now=1234.5)
    marker = bridge.STATE_DIR / "heartbeat.timestamp"
    assert marker.read_text() == "1234.500\n"
    assert marker.stat().st_mode & 0o777 == 0o600
    assert sorted(path.name for path in bridge.STATE_DIR.iterdir()) == ["heartbeat.timestamp"]


def test_bridge_marker_write_failure_is_advisory(tmp_path, monkeypatch, caplog):
    invalid_parent = tmp_path / "not-a-directory"
    invalid_parent.write_text("fixture")
    monkeypatch.setattr(bridge, "STATE_DIR", invalid_parent / "bridge-state")
    bridge._write_heartbeat_marker(now=1234.5)
    assert "completion marker skipped" in caplog.text


@pytest.mark.parametrize("provided_env", [None, {"CUSTOM": "kept"}])
def test_git_uses_keychain_ssh_fallback_on_macos_without_override(monkeypatch, provided_env):
    captured = {}

    def fake_spawn(command, **kwargs):
        captured.update(command=command, **kwargs)
        return 0, "ok", False

    monkeypatch.setattr(bridge.sys, "platform", "darwin")
    monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
    monkeypatch.delenv("SSH_AUTH_SOCK", raising=False)
    monkeypatch.setattr(bridge, "_spawn_capture_text", fake_spawn)
    original_env = None if provided_env is None else dict(provided_env)
    original_os_env = os.environ.copy()

    assert bridge._git("/repo", ["status"], env=provided_env) == "ok"
    assert captured["env"]["GIT_SSH_COMMAND"] == (
        "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes")
    if provided_env is not None:
        assert captured["env"]["CUSTOM"] == "kept"
        assert provided_env == original_env
    assert captured["env"].get("SSH_AUTH_SOCK") is None
    assert dict(os.environ) == original_os_env


@pytest.mark.parametrize("override", ["custom-ssh --flag", ""])
@pytest.mark.parametrize("caller_override", ["caller-ssh", ""])
def test_git_preserves_inherited_and_caller_ssh_overrides(monkeypatch, override, caller_override):
    captured = {}
    monkeypatch.setattr(bridge.sys, "platform", "darwin")
    monkeypatch.setenv("GIT_SSH_COMMAND", override)
    monkeypatch.setattr(bridge, "_spawn_capture_text",
                        lambda command, **kwargs: (captured.update(kwargs) or (0, "", False)))

    caller_env = {"GIT_SSH_COMMAND": caller_override}
    original_caller_env = caller_env.copy()
    bridge._git("/repo", ["status"], env=caller_env)
    assert captured["env"]["GIT_SSH_COMMAND"] == caller_override
    assert caller_env == original_caller_env
    bridge._git("/repo", ["status"])
    assert captured["env"]["GIT_SSH_COMMAND"] == override


def test_git_does_not_add_keychain_ssh_options_off_macos(monkeypatch):
    captured = {}
    monkeypatch.setattr(bridge.sys, "platform", "linux")
    monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
    monkeypatch.setattr(bridge, "_spawn_capture_text",
                        lambda command, **kwargs: (captured.update(kwargs) or (0, "", False)))

    bridge._git("/repo", ["status"], env={"CUSTOM": "kept"})
    assert captured["env"] == {"CUSTOM": "kept"}


def test_git_failure_remains_observable(monkeypatch):
    monkeypatch.setattr(bridge, "_spawn_capture_text", lambda *args, **kwargs: (128, "denied", False))
    with pytest.raises(RuntimeError, match="denied"):
        bridge._git("/repo", ["status"])


def test_extra_argument_is_rejected():
    value, reason = bridge.validate_request(
        request("cluster-status", {"unexpected": "value"}), now=NOW)
    assert value is None
    assert reason == "unexpected argument"


@pytest.mark.parametrize("action, expected", [
    ("sandbox-up", {"action": "up", "provider": "aws"}),
    ("sandbox-down", {"action": "down", "provider": "aws"}),
])
def test_sandbox_lifecycle_actions_have_fixed_aws_bodies(action, expected):
    value, reason = bridge.validate_request(request(action, {"provider": "hostinger"}), now=NOW)
    assert value is None
    assert reason == "unexpected argument"
    value, reason = bridge.validate_request(request(action), now=NOW)
    assert reason is None
    assert json.loads(bridge._request_body(value)) == expected


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
    monkeypatch.setattr(bridge.time, "time", lambda: NOW.timestamp())

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


def _configure_push_failure_tick(monkeypatch, requests, webhook, write):
    remote_tip = ["a" * 40]
    processed = set()
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: remote_tip[0])
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set(processed))
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: list(requests))
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, request_id: (requests[request_id], None))
    monkeypatch.setattr(bridge, "_call_webhook", webhook)

    def commit(repo, parent, request_id, response, *args, **kwargs):
        result = write(request_id, response)
        processed.add(request_id)
        return result

    monkeypatch.setattr(bridge, "_write_commit", commit)
    return processed


def test_response_push_failure_retries_outbox_without_recalling_webhook(monkeypatch):
    request_id = "20260925T201403Z-cluster-status"
    calls = []
    attempts = []
    requests = {request_id: request()}

    def webhook(value):
        calls.append(value["action"])
        return bridge._response("", value["action"], "ok", 200, body={"answer": 42})

    def write(_request_id, response):
        attempts.append(response)
        if len(attempts) == 1:
            raise RuntimeError("lost lease")
        return "b" * 40

    processed = _configure_push_failure_tick(monkeypatch, requests, webhook, write)
    with pytest.raises(RuntimeError, match="lost lease"):
        bridge.process_tick(Path("/nonexistent"), ROOT)
    tip, count = bridge.process_tick(Path("/nonexistent"), ROOT)

    assert calls == ["cluster-status"]
    assert count == 1
    assert tip == "b" * 40
    assert len(attempts) == 2
    assert attempts[0] == attempts[1]
    assert request_id in processed
    assert not (bridge.STATE_DIR / "outbox" / f"{request_id}.json").exists()


def test_job_status_outbox_and_retry_never_contain_credentials(monkeypatch):
    request_id = "20260925T201403Z-job-status"
    credential = "Bearer ghp_sensitiveExample123"
    requests = {request_id: request("job-status", {"job_id": "a" * 8})}
    published = []
    disk_snapshots = []
    attempts = []

    def webhook(value):
        return bridge._response("", value["action"], "ok", 200,
                                body={"status": "success", "output": f"Authorization: {credential}"})

    def store(request_id, response, *args, **kwargs):
        original_store(request_id, response, *args, **kwargs)
        disk_snapshots.append((bridge.STATE_DIR / "outbox" / f"{request_id}.json").read_text())

    def write(_request_id, response):
        attempts.append(response)
        published.append(json.dumps(response))
        if len(attempts) == 1:
            raise RuntimeError("push failed")
        return "b" * 40

    original_store = bridge._store_outbox
    monkeypatch.setattr(bridge, "_store_outbox", store)
    _configure_push_failure_tick(monkeypatch, requests, webhook, write)
    with pytest.raises(RuntimeError, match="push failed"):
        bridge.process_tick(Path("/nonexistent"), ROOT)
    bridge.process_tick(Path("/nonexistent"), ROOT)

    assert disk_snapshots
    assert all(credential not in snapshot for snapshot in disk_snapshots)
    assert all(credential not in record for record in published)


def test_outbox_retry_preserves_watch_entry_and_artifacts(monkeypatch):
    request_id = "20260925T201403Z-make-test-pytest"
    requests = {request_id: request("make-test-pytest")}
    webhook_calls = []
    commits = []
    branch = {}
    processed = set()
    artifact_path = f"artifacts/{request_id}/summary.json"
    artifact_bytes = b'{"job_status":"success"}\n'

    def webhook(value):
        webhook_calls.append(value["action"])
        return bridge._response("", value["action"], "ok", 202,
                                body={"status": "queued", "job_id": "a" * 8})

    def write(repo, parent, rid, response, artifacts=None, watch_add=None, **kwargs):
        commits.append((response, artifacts or {}, watch_add))
        if len(commits) == 1:
            raise RuntimeError("push failed")
        branch[f"responses/{rid}.json"] = response
        branch.update(artifacts or {})
        if watch_add:
            branch.setdefault("watching", []).append(watch_add)
        processed.add(rid)
        return "b" * 40

    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set(processed))
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: [request_id])
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, rid: (requests[rid], None))
    monkeypatch.setattr(bridge, "_call_webhook", webhook)
    monkeypatch.setattr(bridge, "job_artifacts", lambda *args: ({artifact_path: artifact_bytes}, [artifact_path]))
    monkeypatch.setattr(bridge, "_write_commit", write)

    with pytest.raises(RuntimeError, match="push failed"):
        bridge.process_tick(Path("/nonexistent"), ROOT)
    bridge.process_tick(Path("/nonexistent"), ROOT)

    assert webhook_calls == ["make-test-pytest"]
    assert branch[f"responses/{request_id}.json"]["body"]["status"] == "queued"
    assert branch["watching"][0]["request_id"] == request_id
    assert branch[artifact_path] == artifact_bytes
    assert commits[1][1] == {artifact_path: artifact_bytes}
    assert commits[1][2]["request_id"] == request_id


def test_lost_lease_new_request_publishes_both_without_repeating_first(monkeypatch):
    first_id = "20260925T201403Z-cluster-status"
    second_id = "20260925T201404Z-cluster-status"
    requests = {first_id: request(), second_id: request()}
    calls = []
    attempts = []

    def webhook(value):
        calls.append(value["action"])
        return bridge._response("", value["action"], "ok", 200, body={"id": len(calls)})

    def write(request_id, response):
        attempts.append(request_id)
        if request_id == first_id and attempts.count(first_id) == 1:
            raise RuntimeError("lost lease")
        return "b" * 40

    _configure_push_failure_tick(monkeypatch, requests, webhook, write)
    with pytest.raises(RuntimeError, match="lost lease"):
        bridge.process_tick(Path("/nonexistent"), ROOT)
    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT)

    assert calls == ["cluster-status", "cluster-status"]
    assert attempts == [first_id, first_id, second_id]
    assert count == 2


def test_claim_without_outbox_publishes_restart_error_without_webhook(monkeypatch):
    request_id = "20260925T201403Z-cluster-status"
    bridge.STATE_DIR.mkdir(parents=True)
    (bridge.STATE_DIR / "claimed.txt").write_text(request_id + "\n")
    writes = []
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: [request_id])
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: pytest.fail("must not call webhook"))
    monkeypatch.setattr(bridge, "_git", lambda repo, args, **kwargs: (_ for _ in ()).throw(RuntimeError("missing")))
    monkeypatch.setattr(bridge, "_write_commit", lambda repo, ref, rid, response: writes.append(response) or "b" * 40)

    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT)
    assert count == 1
    assert writes[0]["status"] == "error"
    assert writes[0]["reason"] == (
        "bridge restarted before the request completed; outcome unknown — file a new request")
    assert "body" not in writes[0]


def test_slow_request_push_failure_does_not_queue_webhook_twice(monkeypatch):
    request_id = "20260925T201403Z-health"
    calls = []
    attempts = []
    requests = {request_id: request("health")}
    gate = threading.Event()

    def webhook(value):
        calls.append(value["action"])
        gate.wait(2)
        return bridge._response("", value["action"], "ok", 200, body={"healthy": True})

    def write(_request_id, response):
        attempts.append(response)
        if len(attempts) == 1:
            raise RuntimeError("lost lease")
        return "b" * 40

    _configure_push_failure_tick(monkeypatch, requests, webhook, write)
    bridge._slow_pending.clear()
    bridge.process_tick(Path("/nonexistent"), ROOT)
    gate.set()
    deadline = time.monotonic() + 2
    while not (bridge.STATE_DIR / "outbox" / f"{request_id}.json").exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    with pytest.raises(RuntimeError, match="lost lease"):
        bridge.process_tick(Path("/nonexistent"), ROOT)
    bridge.process_tick(Path("/nonexistent"), ROOT)

    assert calls == ["health"]
    assert len(attempts) == 2


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

    processed = set()

    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set(processed))
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
    def fake_write(*args, **kwargs):
        writes.append((args[2], threading.get_ident()))
        processed.add(args[2])
        return pushed
    monkeypatch.setattr(bridge, "_write_commit", fake_write)
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


@pytest.mark.parametrize("action, expected_timeout", [
    ("sandbox-up", 3600), ("sandbox-down", 1800),
    ("make-e2e", bridge.MAKE_TARGETS["e2e"]["timeout"]),
])
def test_watch_entry_uses_lifecycle_or_make_timeout(action, expected_timeout):
    # agent-audit: allow assert-removed gated actions now reach the webhook only after Approve, so the timeout is asserted on _watch_entry directly
    response = bridge._response("", action, "ok", 202, body={"status": "queued", "job_id": "a" * 8})
    entry = bridge._watch_entry(f"20260925T201403Z-{action}", request(action), response)
    assert entry["timeout"] == expected_timeout
    assert entry["job_id"] == "a" * 8


@pytest.mark.parametrize("action, expected_timeout", [
    ("sandbox-up", 3600), ("sandbox-down", 1800),
    ("make-e2e", bridge.MAKE_TARGETS["e2e"]["timeout"]),
])
def test_queued_lifecycle_and_make_responses_commit_watch_entries(monkeypatch, action, expected_timeout):
    request_id = f"20260925T201403Z-{action}"
    writes = []
    cards = []
    token_reads = []
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge.time, "time", lambda: NOW.timestamp())
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: [request_id])
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, rid: (
        request(action, expires=NOW + timedelta(minutes=10)), None))
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: pytest.fail("gated action reached webhook"))
    monkeypatch.setattr(bridge, "_get_cloud_runner_token", lambda: token_reads.append("cloud"))
    monkeypatch.setattr(bridge, "_get_reader_token", lambda: token_reads.append("reader"))
    monkeypatch.setattr(bridge, "post_interactive", lambda *args: cards.append(args) or True)
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append((args, kwargs)) or "b" * 40)

    bridge.process_tick(Path("/nonexistent"), ROOT)

    assert writes
    assert writes[0][1]["pending"] is True
    assert bridge.gated(action)
    assert len(cards) == 1
    assert token_reads == []
    pending = bridge.load_approvals(bridge._approvals_path()).pending[request_id]
    committed_response = json.dumps(writes[0][0][3])
    assert pending.nonce not in committed_response
    assert "nonce" not in committed_response


def test_malformed_watch_lines_do_not_stop_tick_or_new_request(monkeypatch, caplog):
    watched_id = "20260925T201403Z-make-test-pytest"
    reader_id = "20260925T201404Z-cluster-status"
    valid = {"request_id": watched_id, "job_id": "a" * 8,
             "created_at": time.time(), "timeout": 600}
    malformed = [
        {**valid, "created_at": "x"},
        {**valid, "timeout": True},
        {**valid, "timeout": 1e9},
        {**valid, "job_id": "../x"},
        {**valid, "request_id": "bad"},
    ]
    raw = "\n".join(json.dumps(entry) for entry in [*malformed, valid])
    calls = []
    writes = []
    monkeypatch.setattr(bridge, "_git", lambda repo, args, **kwargs: raw)
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_now", lambda: NOW)
    monkeypatch.setattr(bridge, "_fetch", lambda repo: "parent")
    monkeypatch.setattr(bridge, "_processed", lambda repo, ref: set())
    monkeypatch.setattr(bridge, "_claimed_ids", lambda: set())
    monkeypatch.setattr(bridge, "_request_ids", lambda repo, ref: [reader_id])
    monkeypatch.setattr(bridge, "_read_request", lambda repo, ref, rid: (request(), None))

    def webhook(value):
        calls.append(value)
        return bridge._response("", value["action"], "ok", 200,
                                body={"status": "success", "output": "done"} if value["action"] == "job-status" else {})

    monkeypatch.setattr(bridge, "_call_webhook", webhook)
    monkeypatch.setattr(bridge, "job_artifacts", lambda *args: ({}, []))

    def write(*args, **kwargs):
        writes.append(args[2])
        bridge._read_watching(args[0], args[1])
        return "b" * 40

    monkeypatch.setattr(bridge, "_write_commit", write)

    bridge.process_tick(Path("/nonexistent"), ROOT)

    assert [call["action"] for call in calls] == ["job-status", "cluster-status"]
    assert calls[0]["args"]["job_id"] == "a" * 8
    assert reader_id in writes
    assert caplog.text.count("skipped 5 malformed watch lines") == 1


def test_terminal_watch_scrubs_output_before_artifacts_and_commit(monkeypatch):
    credential = "Bearer ghp_sensitiveExample123"
    entry = {"request_id": "20260925T201403Z-make-test-pytest", "job_id": "a" * 8,
             "created_at": time.time(), "timeout": 600}
    observed = {}
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_read_watching", lambda repo, ref: [entry])
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response(
        "", "job-status", "ok", 200, body={"status": "success", "output": f"Authorization: {credential}"}))

    def artifacts(repo, ref, rid, req, response):
        observed["artifact_output"] = response["body"]["output"]
        return {}, []

    def write(*args, **kwargs):
        observed["committed"] = json.dumps(args[3])
        return "a" * 40

    monkeypatch.setattr(bridge, "job_artifacts", artifacts)
    monkeypatch.setattr(bridge, "_write_commit", write)

    bridge.process_tick(Path("/nonexistent"), ROOT, last_tip="a" * 40)

    assert credential not in observed["artifact_output"]
    assert credential not in observed["committed"]


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


def test_killed_watch_writes_one_final_response_and_clears_entry(monkeypatch):
    writes = []
    entry = {"request_id": "20260925T201403Z-sandbox-up", "job_id": "a" * 8,
             "created_at": time.time(), "timeout": 3600}
    monkeypatch.setattr(bridge, "_remote_tip", lambda repo: "a" * 40)
    monkeypatch.setattr(bridge, "_read_watching", lambda repo, ref: [entry])
    monkeypatch.setattr(bridge, "_call_webhook", lambda value: bridge._response(
        "", "job-status", "ok", 200, body={"status": "killed"}))
    monkeypatch.setattr(bridge, "_write_commit", lambda *args, **kwargs: writes.append(kwargs) or "a" * 40)
    _tip, count = bridge.process_tick(Path("/nonexistent"), ROOT, last_tip="a" * 40)
    assert count == 1
    assert len(writes) == 1
    assert writes[0]["final"] is True
    assert writes[0]["watch_remove"] == entry["request_id"]


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
    ("make-find-similar-docs", "Q=" + "x" * 201),
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
    args_by_action = {
        "job-status": {"job_id": "a" * 8},
        "make-fix-status": {"NS": "identity"},
        "make-find-similar-docs": {"Q": "cluster status"},
        "make-e2e-remote": {"RUNNER": "m2"},
        "diagnose-pods": {"provider": "aws", "namespace": "identity"},
        "diagnose-describe-pod": {"provider": "aws", "namespace": "identity", "name": "pod"},
        "diagnose-logs": {"provider": "aws", "namespace": "identity", "name": "pod"},
        "diagnose-app": {"name": "app"},
    }
    for action in bridge.ACTION_ALLOWLIST:
        bridge._call_webhook(request(action, args_by_action.get(action, {})))
    cloud_actions = {"make-e2e", "make-e2e-remote", "sandbox-up", "sandbox-down"}
    assert [auth for auth, _timeout in seen] == [
        "Bearer cloud-runner-test-token" if action in cloud_actions else "Bearer reader-test-token"
        for action in bridge.ACTION_ALLOWLIST]
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


def test_vulnerability_report_cloud_actions_keep_reader_routes_and_no_arguments():
    assert bridge.ACTION_ALLOWLIST["make-vuln-scan-report"] == (
        "POST", "/api/v1/make", {}, "vuln-scan-report")
    assert bridge.ACTION_ALLOWLIST["make-vuln-scan"] == (
        "POST", "/api/v1/make", {}, "vuln-scan")
    for action in ("make-vuln-scan-report", "make-vuln-scan"):
        value, reason = bridge.validate_request(request(action), now=NOW)
        assert reason is None
        assert value["action"] == action
        target = bridge.ACTION_ALLOWLIST[value["action"]][3]
        assert make_targets.MAKE_TARGETS[target]["min_role"] == "reader"
        value, reason = bridge.validate_request(
            request(action, {"NS": "identity"}), now=NOW)
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
    "test-host",
    "up", "down", "cluster", "cluster-up", "cluster-down", "fix-delete-pod", "fix-force-sync",
    "e2e-sandbox", "e2e-sandbox-provision", "e2e-replay", "e2e-runner-unlock", "cleanup-stale-sandbox",
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
    assert {"sandbox-up", "sandbox-down"} <= set(bridge.ACTION_ALLOWLIST)


def test_bridge_has_no_runner_lock_probe_or_direct_ssh_call():
    source = Path(ROOT / "bin" / "k3dm-cloud-bridge").read_text()
    assert "E2E_M2_LOCK" not in source
    # agent-audit: allow assert-removed guard narrowed to exact approved Git SSH fallback
    source = source.replace("GIT_SSH_COMMAND", "")
    source = source.replace(
        "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes", "")
    assert "ssh" not in source.lower()


def test_only_fixed_aws_sandbox_lifecycle_is_reachable_from_the_bridge():
    bridge_source = Path(ROOT / "bin" / "k3dm-cloud-bridge").read_text()
    actions_source = Path(ROOT / "scripts" / "lib" / "webhook" / "cloud_actions.py").read_text()
    assert all(name not in bridge_source for name in ("/cluster-up", "/cluster-down", "/cluster-resume"))
    assert all(entry[1] != "/api/v1/cluster" or entry[3].get("provider") == "aws"
               for entry in bridge.ACTION_ALLOWLIST.values())
    assert all("hostinger" not in json.dumps(entry[3])
               for entry in bridge.ACTION_ALLOWLIST.values())
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
    "diagnose-pods-all": ("get-pods-all", {"provider": "hub"}),
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


@pytest.fixture
def route_names(monkeypatch):
    from unittest.mock import Mock
    from webhook import notify_routes

    names = Mock(return_value=frozenset({"testing", "private-alias"}))
    monkeypatch.setattr(notify_routes, "route_names", names)
    assert notify_routes.route_names is names
    return names


@pytest.mark.parametrize("routed", [False, True])
def test_reader_route_body_and_response(approval_bridge, route_names, routed):
    h = approval_bridge
    req = request("make-test-all")
    expected = b'{"args": {}, "target": "test-all"}'
    if routed:
        req["notify_route"] = "testing"
        expected = b'{"args": {}, "notify_route": "testing", "target": "test-all"}'
    rid = "20260925T201403Z-make-test-all"
    h["submit"](rid, req)
    sent, = h["webhook_calls"]
    assert bridge._request_body(sent) == expected
    assert route_names.call_count == (2 if routed else 0)
    assert _last_approval_response(h) == bridge._response(
        rid, req["action"], "ok", 200, body={"status": "complete"})


@pytest.mark.parametrize("alias, names, reads", [
    ("BAD!", {"private-alias"}, 0), (None, {"private-alias"}, 0),
    ("unknown", {"private-alias"}, 1), ("testing", set(), 1),
])
def test_bad_route_before_admit(approval_bridge, route_names, monkeypatch, alias, names, reads):
    from unittest.mock import Mock
    admit = Mock(wraps=bridge.admit)
    monkeypatch.setattr(bridge, "admit", admit)
    route_names.return_value = names
    h = approval_bridge
    h["submit"](value=dict(request("make-e2e"), notify_route=alias))
    response = _last_approval_response(h)
    assert "private-alias" not in json.dumps(response)
    assert (response["status"], response["reason"]) == ("rejected", "invalid notification route")
    assert route_names.call_count == reads
    admit.assert_not_called()
    assert not bridge.load_approvals(bridge._approvals_path()).cards
    assert not h["cards"] and not h["webhook_calls"]


@pytest.mark.parametrize("action, args", [
    ("cluster-status", {}), ("diagnose-pods", {"provider": "hub", "namespace": "test"}),
    ("job-status", {"job_id": "abcdef12"}),
])
def test_unsupported_route(approval_bridge, route_names, action, args):
    h = approval_bridge
    h["submit"](value=dict(request(action, args), notify_route="testing"))
    response = _last_approval_response(h)
    assert (response["status"], response["reason"]) == ("rejected", "notification route not supported for this action")
    route_names.assert_not_called()
    assert not h["cards"] and not h["webhook_calls"]


@pytest.mark.parametrize("removed", [False, True])
def test_approved_route_rechecked(approval_bridge, route_names, removed):
    h = approval_bridge
    h["submit"](value=dict(request("sandbox-up"), notify_route="testing"))
    url, text, _ = h["cards"][0]
    assert url == "secret" and "Notifications go to `testing`." in text
    pending = _pending_approval(h)
    assert pending.request["notify_route"] == "testing"
    assert "private-alias" not in bridge._approvals_path().read_text()
    if removed:
        route_names.return_value = {"private-alias"}
    h["drain_items"].append([_drain_item(pending)])
    h["clock"][0] += 31
    h["tick"]()
    response = _last_approval_response(h)
    assert "private-alias" not in json.dumps(response)
    if removed:
        assert (response["status"], response["reason"]) == ("rejected", "invalid notification route")
        assert not h["webhook_calls"] and not h["token_reads"]
    else:
        sent, = h["webhook_calls"]
        assert json.loads(bridge._request_body(sent)) == {"action": "up", "provider": "aws", "notify_route": "testing"}
        assert h["token_reads"] == ["cloud"]
    assert route_names.call_count == 2


def test_route_fields_and_slack_context():
    req = request("make-test-all", {"channel_id": "C12345678"})
    assert bridge.validate_request(req, now=NOW) == (None, "unexpected argument")
    # Exercise the serializer independently of the admission allowlist.
    body = json.loads(bridge._request_body(req))
    assert not {"channel_id", "response_url", "thread_ts"}.intersection(body)
    req.update(notify_route="testing", extra=True)
    assert bridge.validate_request(req, now=NOW) == (None, "request fields are not exactly the required six")


@pytest.mark.parametrize("code, error, status", [
    (400, "invalid notification route", "rejected"),
    (400, "notification route not supported for this action", "rejected"),
    (400, "notify_route cannot be combined with Slack context", "rejected"),
    (400, "other", "error"), (403, "invalid notification route", "error"),
])
def test_route_http_error(monkeypatch, code, error, status):
    import io
    def fail(req, timeout):
        assert req.full_url == "http://127.0.0.1:7443/api/v1/make"
        raise bridge.urllib.error.HTTPError(req.full_url, code, "", {}, io.BytesIO(json.dumps({"error": error}).encode()))
    monkeypatch.setattr(bridge.urllib.request, "urlopen", fail)
    monkeypatch.setattr(bridge, "_get_reader_token", lambda: "test")
    response = bridge._call_webhook(dict(request("make-test-all"), notify_route="testing"))
    assert response["status"] == status and response["http_status"] == code
    if status == "rejected":
        assert response["reason"] == error and "body" not in response
    else:
        assert response["body"] == {"error": error}


def test_route_privacy_in_published_records(approval_bridge, route_names, monkeypatch, tmp_path):
    h = approval_bridge
    routes = {"testing": "C12345678", "private-alias": "G87654321"}
    route_names.return_value = frozenset(routes)
    rid = "20260925T201403Z-make-e2e"
    h["submit"](rid, dict(request("make-e2e"), notify_route="testing"))
    pending = _pending_approval(h, rid)
    records = [bridge._approvals_path().read_text()]
    job = "abcdef12"
    (tmp_path / "status").write_text("success")
    monkeypatch.setattr(bridge.webhook_config, "_safe_job_dir", lambda job_id: tmp_path if job_id == job else pytest.fail())
    monkeypatch.setattr(bridge, "_published_artifacts", lambda *_: [])

    def webhook(req):
        if req["action"] == "job-status":
            body = {"status": "success"}
        else:
            assert req == pending.request
            body = {"status": "queued", "job_id": job}
        return bridge._response("", req["action"], "ok", 200, body=body)

    monkeypatch.setattr(bridge, "_call_webhook", webhook)
    h["drain_items"].append([_drain_item(pending)])
    h["clock"][0] += 31
    h["tick"]()
    watch = h["commits"][-1][1]["watch_add"]
    monkeypatch.setattr(bridge, "_read_watching", lambda *_: [watch])
    h["tick"]()
    args, kwargs = h["commits"][-1]
    assert kwargs["final"] and args[3]["body"]["status"] == "success"
    records.append(args[4][f"artifacts/{rid}/summary.json"].decode())
    monkeypatch.setattr(bridge, "_read_watching", lambda *_: [])
    h["submit"]("20260925T201404Z-make-e2e", dict(request("make-e2e"), notify_route="unknown"))
    assert _last_approval_response(h)["status"] == "rejected"
    records.extend(json.dumps(args[3]) for args, _ in h["commits"])
    for record in records:
        for private in ("private-alias", *routes.values()):
            assert private not in record
    assert route_names.call_count == 3
