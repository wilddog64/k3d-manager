import importlib.util
from importlib.machinery import SourceFileLoader
import os
from pathlib import Path
import subprocess

import pytest
# agent-audit: allow assert-removed newest-release assertions retargeted to deploy/hub one for one (deploy/hub batch, N6)

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_loader(
    "hermes_checkout_lag", SourceFileLoader("hermes_checkout_lag", str(ROOT / "bin/k3dm-hermes")))
hermes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hermes)


def git(path, *args):
    return subprocess.run(["git", *args], cwd=path, check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def origin_and_clone(tmp_path, monkeypatch):
    origin = tmp_path / "origin.git"
    seed = tmp_path / "seed"
    clone = tmp_path / "clone"
    origin.mkdir()
    subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
    subprocess.run(["git", "init", str(seed)], check=True, capture_output=True)
    git(seed, "config", "user.email", "test@example.invalid")
    git(seed, "config", "user.name", "test")
    (seed / "code.txt").write_text("base\n")
    (seed / "docs").mkdir()
    (seed / "docs" / "base.md").write_text("base\n")
    git(seed, "add", ".")
    git(seed, "commit", "-m", "base")
    git(seed, "branch", "-M", "k3d-manager-v1.43.14")
    git(seed, "remote", "add", "origin", str(origin))
    git(seed, "push", "-u", "origin", "HEAD")
    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
    subprocess.run(["git", f"--git-dir={origin}", "symbolic-ref", "HEAD",
                    "refs/heads/k3d-manager-v1.43.14"], check=True)
    git(seed, "clone", str(origin), str(clone))
    git(clone, "config", "user.email", "test@example.invalid")
    git(clone, "config", "user.name", "test")
    monkeypatch.setattr(hermes, "ROOT", clone)
    monkeypatch.setenv("K3DM_VECTORDB_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    return origin, seed, clone


@pytest.fixture
def older_branch_behind(origin_and_clone):
    origin, seed, clone = origin_and_clone
    base = git(seed, "rev-parse", "HEAD")
    for index in (1, 2):
        with (seed / "code.txt").open("a") as stream:
            stream.write(f"code update {index}\n")
        git(seed, "add", "code.txt")
        git(seed, "commit", "-m", f"code update {index}")
    git(seed, "push", "origin", "HEAD")
    git(seed, "push", "origin", f"{base}:refs/heads/k3d-manager-v1.43.100")
    return origin, seed, clone


def refresh_with_capture(monkeypatch, clone, fail_older_fetch=False):
    real_run = hermes.subprocess.run
    fetches = []
    lag_payloads = []
    index_metrics = []

    class Response:
        def close(self):
            pass

    def run(command, **kwargs):
        if command[0] == "git" and len(command) > 1 and command[1] == "fetch":
            fetches.append((command, kwargs))
            if (fail_older_fetch and
                    command[-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"):
                return type("R", (), {"returncode": 1, "stdout": "", "stderr": "fetch failed"})()
            return real_run(command, **kwargs)
        if command[0] == "git":
            return real_run(command, **kwargs)
        if "index-docs.py" in command[0]:
            return type("R", (), {"returncode": 0,
                                   "stdout": "1 embedded\n0 from cache\n0 pruned\n0 remaining\n",
                                   "stderr": ""})()
        raise AssertionError(f"unexpected subprocess target: {command}")

    def capture_push(request, timeout):
        assert request.full_url.endswith("/metrics/job/k3dm-hub-checkout")
        assert timeout == 5
        lag_payloads.append(request.data.decode())
        return Response()

    monkeypatch.setattr(hermes.subprocess, "run", run)
    monkeypatch.setattr(hermes.urllib.request, "urlopen", capture_push)
    monkeypatch.setattr(hermes, "_push_index_metrics", lambda metrics: index_metrics.append(dict(metrics)))
    assert hermes.ROOT == clone
    state = {"retrieval_probe_last_attempt": 1000}
    result = hermes._refresh_index(state, now=1000)
    return state, result, fetches, lag_payloads, index_metrics


def test_refresh_lag_count_uses_fetched_older_upstream_when_newer_release_exists(
        older_branch_behind, monkeypatch):
    _origin, seed, clone = older_branch_behind
    state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(monkeypatch, clone)
    assert len(lag_payloads) == 1
    assert 'code_commits_behind{branch="deploy/hub"} 0' in lag_payloads[0]
    assert len(fetches) == 2
    assert fetches[0][0][-1] == "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100"
    assert fetches[1][0][-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"
    assert fetches[0][1]["timeout"] == fetches[1][1]["timeout"] == 60
    assert fetches[0][1]["env"] is fetches[1][1]["env"]
    assert index_metrics[0]["result"] == "success"
    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
    next_state, _result, _fetches, next_payloads, _metrics = refresh_with_capture(monkeypatch, clone)
    assert 'code_commits_behind{branch="deploy/hub"} 2' in next_payloads[0]
    assert next_state["index_ref"] == state["index_ref"] == "origin/k3d-manager-v1.43.100"


def test_failed_older_upstream_fetch_skips_lag_without_changing_index_result(
        older_branch_behind, monkeypatch):
    _origin, _seed, clone = older_branch_behind
    _state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(
        monkeypatch, clone, fail_older_fetch=True)
    assert len(fetches) == 2
    assert lag_payloads == []
    assert index_metrics[0]["result"] == "success"


def test_refresh_on_newest_branch_fetches_once(older_branch_behind, monkeypatch):
    _origin, _seed, clone = older_branch_behind
    git(clone, "fetch", "origin",
        "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100")
    git(clone, "switch", "--track", "-c", "k3d-manager-v1.43.100", "origin/k3d-manager-v1.43.100")
    _state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(monkeypatch, clone)
    assert len(fetches) == 2
    assert fetches[0][0][-1] == "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100"
    assert fetches[1][0][-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"
    assert 'code_commits_behind{branch="deploy/hub"} 0' in lag_payloads[0]
    assert index_metrics[0]["result"] == "success"


def test_lag_publishes_code_count_excluding_docs(origin_and_clone, monkeypatch):
    _origin, seed, clone = origin_and_clone
    (seed / "docs" / "new.md").write_text("doc\n")
    git(seed, "add", "docs/new.md"); git(seed, "commit", "-m", "doc")
    (seed / "code.txt").write_text("code\n")
    git(seed, "add", "code.txt"); git(seed, "commit", "-m", "code")
    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
    git(clone, "fetch", "origin", "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub")
    captured = []

    class Response:
        def close(self):
            pass

    def capture(request, timeout):
        assert request.full_url == "http://127.0.0.1:9/metrics/job/k3dm-hub-checkout"
        captured.append(request.data.decode())
        return Response()

    monkeypatch.setattr(hermes.urllib.request, "urlopen", capture)
    hermes._push_checkout_lag("origin/deploy/hub")
    assert 'code_commits_behind{branch="deploy/hub"} 1' in captured[0]
    assert "k3dm_hub_checkout_last_check_timestamp_seconds" in captured[0]
    assert "k3dm_hub_checkout_on_newest_release" not in captured[0]


def test_newest_release_uses_numeric_version_and_never_downgrades(origin_and_clone, monkeypatch):
    origin, seed, _clone = origin_and_clone
    git(seed, "push", "origin", "HEAD:refs/heads/k3d-manager-v1.43.9")
    git(seed, "push", "origin", "HEAD:refs/heads/k3d-manager-v1.43.100")
    env = os.environ.copy()
    assert hermes._newest_release_branch("k3d-manager-v1.43.14", env) == "k3d-manager-v1.43.100"
    assert hermes._newest_release_branch("k3d-manager-v1.43.101", env) == "k3d-manager-v1.43.101"
    assert hermes._newest_release_branch("unparseable", env) == "unparseable"


def test_newest_release_lookup_failure_keeps_current(origin_and_clone, monkeypatch):
    _origin, _seed, _clone = origin_and_clone
    monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k:
                        type("R", (), {"returncode": 1, "stdout": "", "stderr": "offline"})())
    assert hermes._newest_release_branch("k3d-manager-v1.43.14", os.environ.copy()) == "k3d-manager-v1.43.14"


def test_unsafe_branch_and_git_or_gateway_failures_publish_nothing(origin_and_clone, monkeypatch):
    published = []
    monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k: type("R", (), {"returncode": 1, "stdout": ""})())
    monkeypatch.setattr(hermes.urllib.request, "urlopen", lambda *_a, **_k: published.append(1))
    hermes._push_checkout_lag('x"bad')
    hermes._push_checkout_lag("origin/x")
    assert published == []


def test_unreachable_gateway_does_not_escape(origin_and_clone, monkeypatch):
    _origin, _seed, _clone = origin_and_clone
    monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k:
                        type("R", (), {"returncode": 0, "stdout": "0\n"})())
    monkeypatch.setattr(hermes.urllib.request, "urlopen", lambda *_a, **_k: (_ for _ in ()).throw(OSError("offline")))
    assert hermes._push_checkout_lag("origin/deploy/hub") is None


def test_paused_refresh_still_publishes_checkout_lag(origin_and_clone, monkeypatch):
    _origin, _seed, _clone = origin_and_clone
    monkeypatch.delenv("K3DM_INDEX_REF", raising=False)
    monkeypatch.setattr(hermes, "_index_ref", lambda: ("origin/k3d-manager-v1.43.14", "k3d-manager-v1.43.14"))
    monkeypatch.setattr(hermes, "_newest_release_branch", lambda current, _env: current)
    monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k:
                        type("R", (), {"returncode": 0, "stdout": "", "stderr": ""})())
    lag = []
    monkeypatch.setattr(hermes, "_push_checkout_lag", lambda *args: lag.append(args))
    monkeypatch.setattr(hermes, "_push_index_metrics", lambda _metrics: None)
    state = {"index_paused_until": 200}
    assert hermes._refresh_index(state, now=100) is None
    assert state["index_ref"] == "origin/k3d-manager-v1.43.14"
    assert lag == [("origin/deploy/hub",)]


def test_refresh_fetches_newest_release_docs_without_moving_head(origin_and_clone, monkeypatch):
    _origin, seed, clone = origin_and_clone
    base = git(seed, "rev-parse", "HEAD")
    git(seed, "branch", "k3d-manager-v1.43.9", base)
    git(seed, "push", "origin", "k3d-manager-v1.43.9")
    git(seed, "checkout", "-b", "k3d-manager-v1.43.100")
    (seed / "docs" / "newest.md").write_text("newest release docs\n")
    git(seed, "add", "docs/newest.md"); git(seed, "commit", "-m", "newest docs")
    git(seed, "push", "origin", "k3d-manager-v1.43.100")
    head_before = git(clone, "rev-parse", "HEAD")
    monkeypatch.delenv("K3DM_INDEX_REF", raising=False)
    monkeypatch.setattr(hermes, "corpus_fingerprint", lambda *_a, **_k: "same")
    real_run = hermes.subprocess.run

    def run(command, **kwargs):
        if command[0] == "git":
            return real_run(command, **kwargs)
        assert command[-2:] == ["--json"] or command[-1] == "--json"
        return type("R", (), {"returncode": 0, "stdout": '{"available":true,"rows":1,"corpus_docs":1}', "stderr": ""})()

    monkeypatch.setattr(hermes.subprocess, "run", run)
    monkeypatch.setattr(hermes, "_push_checkout_lag", lambda *_args: None)
    monkeypatch.setattr(hermes, "_push_index_metrics", lambda _metrics: None)
    state = {"index_fingerprint": "same", "retrieval_probe_last_attempt": 1000}
    hermes._refresh_index(state, now=1000)
    assert state["index_ref"] == "origin/k3d-manager-v1.43.100"
    assert git(clone, "show", "origin/k3d-manager-v1.43.100:docs/newest.md") == "newest release docs"
    assert git(clone, "rev-parse", "HEAD") == head_before


def test_explicit_index_ref_wins_without_remote_release_lookup(origin_and_clone, monkeypatch):
    _origin, _seed, clone = origin_and_clone
    monkeypatch.setenv("K3DM_INDEX_REF", "origin/k3d-manager-v1.43.14")
    real_run = hermes.subprocess.run
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        if command[0] == "git":
            return real_run(command, **kwargs)
        return type("R", (), {"returncode": 0, "stdout": '{"available":true,"rows":1,"corpus_docs":1}', "stderr": ""})()

    monkeypatch.setattr(hermes.subprocess, "run", run)
    monkeypatch.setattr(hermes, "corpus_fingerprint", lambda *_a, **_k: "same")
    monkeypatch.setattr(hermes, "_newest_release_branch", lambda *_a: pytest.fail("explicit ref must win"))
    monkeypatch.setattr(hermes, "_push_checkout_lag", lambda *_args: None)
    monkeypatch.setattr(hermes, "_push_index_metrics", lambda _metrics: None)
    state = {"index_fingerprint": "same", "retrieval_probe_last_attempt": 1000}
    hermes._refresh_index(state, now=1000)
    assert state["index_ref"] == "origin/k3d-manager-v1.43.14"
    fetch_calls = [command for command in calls if command[:2] == ["git", "fetch"]]
    assert fetch_calls == [
        ["git", "fetch", "--quiet", "origin", "k3d-manager-v1.43.14"],
        ["git", "fetch", "--quiet", "origin",
         "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"],
    ]
    assert not any(command[:3] == ["git", "ls-remote", "--heads"] for command in calls)
