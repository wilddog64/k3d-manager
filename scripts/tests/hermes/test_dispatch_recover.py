"""Offline safety tests for the dispatch recovery drain."""
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
loader = importlib.machinery.SourceFileLoader("dispatch_recover", str(ROOT / "bin" / "k3dm-dispatch-recover"))
spec = importlib.util.spec_from_loader("dispatch_recover", loader)
recover = importlib.util.module_from_spec(spec)
loader.exec_module(recover)


def git(path, *args):
    return subprocess.run(["git", "-C", str(path), *args], capture_output=True, check=True)


def setup(monkeypatch, tmp_path, approval=None):
    repo = tmp_path / "repo"; repo.mkdir()
    git(repo, "init", "-q", "-b", "k3d-manager-v1.45.0")
    git(repo, "config", "user.email", "test@example.invalid"); git(repo, "config", "user.name", "Test")
    (repo / "base").write_text("base"); git(repo, "add", "base"); git(repo, "commit", "-qm", "base")
    root = tmp_path / "worktrees"; run = root / "v1.45.0" / "demo.run"
    worktree = root / "v1.45.0" / "demo"; worktree.mkdir(parents=True)
    git(worktree, "init", "-q"); git(worktree, "config", "user.email", "test@example.invalid")
    git(worktree, "config", "user.name", "Test"); (worktree / "base").write_text("base")
    git(worktree, "add", "base"); git(worktree, "commit", "-qm", "base")
    run.mkdir(); (run / "exit").write_text("0\n")
    stall = run / "stall-2026-11-14T00-00-00Z"; stall.mkdir()
    (stall / "correction.md").write_text("approved correction\n")
    (stall / "diagnosis.md").write_text("Diagnosis summary")
    state_path = tmp_path / "state.json"
    monkeypatch.setattr(recover, "ROOT", repo)
    monkeypatch.setenv("HOME", str(tmp_path / "home")); Path(os.environ["HOME"]).mkdir()
    monkeypatch.setenv("K3DM_WORKTREE_ROOT", str(root)); monkeypatch.setenv("K3DM_DISPATCH_RECOVER_STATE", str(state_path))
    monkeypatch.setenv("K3DM_HERMES_APPROVAL_DRAIN_URL", "https://relay.invalid/drain")
    monkeypatch.setattr(recover, "_keychain_secret", lambda service: "token-secret" if "drain-token" in service else "https://webhook.invalid/x")
    cards, summaries, calls = [], [], []
    monkeypatch.setattr(recover, "post_interactive", lambda url, text, blocks: cards.append((text, blocks)) or True)
    monkeypatch.setattr(recover, "post_summary", lambda url, text: summaries.append(text) or True)
    monkeypatch.setattr(recover, "_health_probe", lambda *_: None)
    monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [])
    monkeypatch.setattr(recover, "delete_approval", lambda *a, **k: True)
    real_run = subprocess.run
    argv_seen = []
    def runner(argv, **kwargs):
        argv_seen.append(list(argv))
        if str(argv[0]).endswith("k3dm-codex-dispatch"):
            calls.append((argv, kwargs)); return subprocess.CompletedProcess(argv, 0, "", "")
        return real_run(argv, **kwargs)
    runner.argv_seen = argv_seen
    monkeypatch.setattr(recover.subprocess, "run", runner)
    assert os.environ["HOME"] == str(tmp_path / "home")
    assert os.environ["K3DM_WORKTREE_ROOT"] == str(root)
    assert repo.name == "repo" and root.parent == tmp_path
    return repo, root, run, stall, state_path, cards, summaries, calls


def test_proposal_records_card_hashes_and_second_stall_pages(monkeypatch, tmp_path, capsys):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    recover.main()
    payload = json.loads(state.read_text()); proposal = next(iter(payload["proposals"].values()))
    assert len(cards) == 1
    assert cards[0][1][2]["elements"][0]["value"].startswith("d1-")
    assert proposal["status"] == "proposed" and proposal["resume_count"] == 0
    assert proposal["correction_sha256"] == recover._sha(stall / "correction.md")
    assert proposal["worktree_sha256"] == recover._worktree_hash(root / "v1.45.0" / "demo")
    second = run / "stall-2026-11-15T00-00-00Z"; second.mkdir()
    (second / "correction.md").write_text("another"); (second / "diagnosis.md").write_text("again")
    recover.main()
    assert len(cards) == 1 and any("second stall" in line for line in summaries)
    assert not calls


def test_dispatch_pattern_separates_r_and_d_ids():
    from hermes import approvals
    assert approvals.fetch_approvals("https://relay", "t", lambda *_a, **_k: type("R", (), {"__enter__": lambda s:s, "__exit__": lambda *_:False, "read":lambda s:json.dumps([{"action_id":"r2-0123abcd","nonce":"0123456789abcdef","approved_by":"UAPPROVER"},{"action_id":"d1-0123abcd","nonce":"0123456789abcdef","approved_by":"UAPPROVER"}]).encode()})())


def test_approved_unchanged_dispatch_resumes_once_then_replay_is_dropped(monkeypatch, tmp_path):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    recover.main()
    proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
    approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
    monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
    recover.main()
    assert len(calls) == 1
    argv, kwargs = calls[0]
    assert argv[1:] == ["resume", "--slug", "demo", "--prompt-file", str(stall / "correction.md"),
                        "--reason", "correction", "--coordinator", "anthropic/claude-opus-5-5"]
    assert "--model" not in argv and kwargs["timeout"] == 300
    recover.main()
    assert len(calls) == 1
    assert json.loads(state.read_text())["proposals"][str(stall.resolve())]["status"] == "resumed"
    assert any("dropped stale" in item for item in summaries)


def test_resume_preconditions_refuse_changed_files_and_branch(monkeypatch, tmp_path):
    for change, reason in [("tracked", "worktree changed"), ("untracked", "worktree changed"),
                           ("correction", "correction changed"), ("prompt", "resume count changed"),
                           ("branch", "wrong release branch")]:
        case = tmp_path / change; case.mkdir()
        repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, case)
        recover.main()
        proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
        approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
        if change == "tracked": (root / "v1.45.0" / "demo" / "base").write_text("changed")
        if change == "untracked": (root / "v1.45.0" / "demo" / "new").write_text("changed")
        if change == "correction": (stall / "correction.md").write_text("rewritten")
        if change == "prompt": (run / "prompt-1.md").write_text("someone resumed")
        if change == "branch": git(repo, "checkout", "-qb", "other")
        monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
        recover.main()
        assert not calls, change
        assert any(reason in item for item in summaries), change


def test_expired_wrong_nonce_running_and_crash_attempts_fail_closed(monkeypatch, tmp_path):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    recover.main()
    key, proposal = next(iter(json.loads(state.read_text())["proposals"].items()))
    proposal["expires_at"] = 0
    payload = {"proposals": {key: proposal}, "health_alert_at": 0}; state.write_text(json.dumps(payload))
    approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
    monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
    recover.main()
    assert not calls and "expired" in summaries[-1]
    payload["proposals"][key]["status"] = "attempting"; payload["proposals"][key]["expires_at"] = 9999999999
    state.write_text(json.dumps(payload)); recover.main()
    assert not calls


def test_wrong_nonce_and_live_worker_are_refused(monkeypatch, tmp_path):
    for case_name in ("nonce", "worker"):
        case = tmp_path / case_name
        case.mkdir()
        repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, case)
        recover.main()
        proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
        nonce = "f" * 16 if case_name == "nonce" else proposal["nonce"]
        if case_name == "worker":
            (run / "pid").write_text(str(os.getpid()))
        approval = {"action_id": proposal["action_id"], "nonce": nonce, "approved_by": "UAPPROVER"}
        monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
        recover.main()
        assert not calls
        reason = "wrong nonce" if case_name == "nonce" else "worker is running"
        assert any(reason in line for line in summaries)


def test_credentials_stay_out_of_argv_state_and_logs(monkeypatch, tmp_path, capsys):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    used = []
    class Response:
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def read(self): return b"[]"
    def opener(request, timeout):
        used.append((request.full_url, request.get_header("Authorization")))
        return Response()
    from hermes.approvals import fetch_approvals as original_fetch
    monkeypatch.setattr(recover, "fetch_approvals", lambda url, token, **kwargs:
                        original_fetch(url, token, opener=opener, id_pattern=kwargs["id_pattern"]))
    recover.main()
    captured = capsys.readouterr()
    state_text = state.read_text()
    argv_text = repr(recover.subprocess.run.argv_seen)
    for secret in ("token-secret", "https://webhook.invalid/x", "https://relay.invalid/drain"):
        assert secret not in state_text and secret not in argv_text
        assert secret not in captured.out and secret not in captured.err
    assert used == [("https://relay.invalid/drain", "Bearer token-secret")]


def test_resume_attempt_is_saved_before_process_and_retry_is_blocked(monkeypatch, tmp_path):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    recover.main()
    proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
    approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
    monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
    real_run = subprocess.run
    resume_calls = []

    def fail_resume(argv, **kwargs):
        if str(argv[0]).endswith("k3dm-codex-dispatch"):
            resume_calls.append(argv)
            saved = json.loads(state.read_text())
            assert saved["proposals"][str(stall.resolve())]["status"] == "attempting"
            raise subprocess.TimeoutExpired(argv, 300, stderr="simulated crash")
        return real_run(argv, **kwargs)

    monkeypatch.setattr(recover.subprocess, "run", fail_resume)
    recover.main()
    assert len(resume_calls) == 1
    assert json.loads(state.read_text())["proposals"][str(stall.resolve())]["status"] == "resume_failed"
    recover.main()
    assert len(resume_calls) == 1
    assert any("dropped stale" in line for line in summaries)


def test_resume_stderr_redacts_relay_webhook_url(monkeypatch, tmp_path, capsys):
    repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, tmp_path)
    recover.main()
    proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
    approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
    monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
    real_run = subprocess.run
    resume_calls = []

    def failed_resume(argv, **kwargs):
        if str(argv[0]).endswith("k3dm-codex-dispatch"):
            resume_calls.append(argv)
            return subprocess.CompletedProcess(argv, 1, "", "failed at https://webhook.invalid/x")
        return real_run(argv, **kwargs)

    monkeypatch.setattr(recover.subprocess, "run", failed_resume)
    recover.main()
    captured = capsys.readouterr()
    assert len(resume_calls) == 1
    assert "https://webhook.invalid/x" not in captured.out + captured.err
    assert all("https://webhook.invalid/x" not in line for line in summaries)
    assert "https://webhook.invalid/x" not in state.read_text()


def test_hermes_setup_steps_remain_continuous():
    guide = (ROOT / "docs/guides/hermes.md").read_text(encoding="utf-8")
    setup_text = guide.split("Operator setup (run in Terminal.app):", 1)[1].split("`APPROVERS`", 1)[0]
    assert re.findall(r"(?m)^([1-9])\. ", setup_text) == ["1", "2", "3", "4"]
    recovery = "Dispatch recovery uses `d` action IDs"
    step_four = setup_text.index("4. The LaunchAgent template")
    assert setup_text.index(recovery) > step_four


def test_non_exited_landed_and_violation_dispatches_refuse_resume(monkeypatch, tmp_path):
    for state_kind in ("not_exited", "landed", "violation"):
        case = tmp_path / state_kind
        case.mkdir()
        repo, root, run, stall, state, cards, summaries, calls = setup(monkeypatch, case)
        if state_kind == "not_exited":
            (run / "exit").unlink()
        elif state_kind == "landed":
            (run / "landed").touch()
        else:
            (run / "violation").touch()
        recover.main()
        proposal = next(iter(json.loads(state.read_text())["proposals"].values()))
        approval = {"action_id": proposal["action_id"], "nonce": proposal["nonce"], "approved_by": "UAPPROVER"}
        monkeypatch.setattr(recover, "fetch_approvals", lambda *a, **k: [approval])
        recover.main()
        assert calls == [], state_kind
        assert any("dispatch is not exited cleanly" in line for line in summaries), state_kind


def test_health_probe_sends_user_agent_bearer_and_returns_error_code(monkeypatch):
    # E2 proves [M3, N1, N2]
    captured = []
    token = "test-drain-token-xyz"

    class FakeOkResponse:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    def stub_urlopen(request, timeout=10):
        captured.append(request)
        return FakeOkResponse()

    monkeypatch.setattr(recover, "urlopen", stub_urlopen)
    res = recover._health_probe("https://relay.invalid/drain", token)
    assert res is None
    assert len(captured) == 1
    req = captured[0]
    headers_lower = {k.lower(): v for k, v in req.header_items()}
    assert headers_lower.get("user-agent") == "k3dm-hermes/1"
    assert headers_lower.get("authorization") == f"Bearer {token}"
    for header, value in req.header_items():
        if header.lower() != "authorization":
            assert token not in str(value)

    # Positive control: stub answering 403 makes probe return 403
    from urllib.error import HTTPError

    def stub_urlopen_403(request, timeout=10):
        raise HTTPError(request.full_url, 403, "Forbidden", {}, None)

    monkeypatch.setattr(recover, "urlopen", stub_urlopen_403)
    res_403 = recover._health_probe("https://relay.invalid/drain", token)
    assert res_403 == 403
