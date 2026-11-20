"""Offline contract tests for the remote promotion mover."""
import inspect
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import hub_approval
import promote_mover


class Clock:
    def now(self):
        return 1790000000


class Api:
    """Synthesized check-runs response pending a captured hub response."""
    def get_all(self, path, list_key, budget):
        budget()
        if list_key == "check_runs":
            return 200, [{"status": "completed", "conclusion": "success"}]
        return 200, []

    def get(self, path, timeout):
        return 200, []


def git(binary, cwd, *args, input_text=None):
    result = subprocess.run([binary, "-c", "core.hooksPath=/dev/null", *args], cwd=cwd,
                            input=input_text, text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


@pytest.fixture
def repo(tmp_path):
    """Assert all git operations target this fixture's temporary repositories."""
    binary = os.path.realpath(shutil_which("git"))
    origin = tmp_path / "origin.git"
    work = tmp_path / "work"
    mirror = tmp_path / "mirror.git"
    origin.mkdir()
    subprocess.run([binary, "init", "--bare", "-q", str(origin)], check=True)
    work.mkdir()
    git(binary, work, "init", "-q")
    git(binary, work, "config", "user.name", "Test")
    git(binary, work, "config", "user.email", "test@example.invalid")
    (work / "file").write_text("old\n", encoding="utf-8")
    git(binary, work, "add", "file")
    git(binary, work, "commit", "-qm", "old")
    old = git(binary, work, "rev-parse", "HEAD")
    git(binary, work, "branch", "-M", "main")
    git(binary, work, "remote", "add", "origin", str(origin))
    git(binary, work, "push", "-q", str(origin), "main:refs/heads/deploy/hub")
    (work / "file").write_text("new\n", encoding="utf-8")
    git(binary, work, "commit", "-qam", "new")
    new = git(binary, work, "rev-parse", "HEAD")
    git(binary, work, "push", "-q", str(origin), "HEAD:refs/heads/k3d-manager-v1.45.0")
    return {"git": binary, "origin": origin, "work": work, "mirror": mirror, "old": old, "new": new}


def shutil_which(command):
    import shutil
    result = shutil.which(command)
    assert result
    return result


def mover(repo, api=None):
    return promote_mover.Mover(str(repo["origin"]), "owner/repo", api or Api(), "", str(repo["mirror"]), Clock(), git=repo["git"])


def approved_engine(repo, tmp_path):
    state = tmp_path / "state"
    state.mkdir(mode=0o700, parents=True)
    os.chmod(state, 0o700)
    key = b"relay-key-for-offline-test"
    secret = b"totp-secret-for-offline-test"
    engine = hub_approval.Engine(str(state), Clock(), secret, {"cli"}, key)
    request = engine.request(repo["new"], "k3d-manager-v1.45.0", "cli", "cli")
    now = Clock().now()
    code = hub_approval.totp_code(secret, (now // 30 + 1) * 30)
    at = str(now)
    signature = hub_approval.approval_mac(key, request["id"], request["nonce"], "cli", request["check"], code, at)
    engine.approve(request["id"], request["nonce"], "cli", code, request["check"], at, signature)
    return engine, request["id"]


def attempt_object(instance, repo, id, tag, old=None, message_old=None):
    instance.prime()
    old = old or repo["old"]
    message_old = message_old or old
    data = "object {}\ntype commit\ntag {}\ntagger k3dm-promote <k3dm-promote@localhost> {} +0000\n\naction: promote\nold: {}\nnew: {}\nREF: {}\napproval: {}\n".format(
        repo["new"], tag, Clock().now(), message_old, repo["new"], repo["new"], id)
    obj = instance._git(["mktag"], input_text=data).stdout.strip()
    instance._git(["update-ref", "refs/k3dm/pending/{}".format(tag.rsplit("/", 1)[1]), obj])
    return {"tag": tag, "object": obj, "old": old}


def commit_file(repo, name, content, message):
    (repo["work"] / name).write_text(content, encoding="utf-8")
    git(repo["git"], repo["work"], "add", name)
    git(repo["git"], repo["work"], "commit", "-qm", message)
    return git(repo["git"], repo["work"], "rev-parse", "HEAD")


class ScriptedApi(Api):
    def __init__(self, checks=None, pulls=None):
        self.checks = checks or {}
        self.pulls = pulls or []
        self.calls = []

    def get_all(self, path, list_key, budget):
        self.calls.append(path)
        budget()
        if list_key == "check_runs":
            return 200, self.checks.get(path.rsplit("/", 2)[-2], [{"status": "completed", "conclusion": "success"}])
        return 200, self.pulls


def test_e8_m14_n1_n3_n6_n7_signature_has_no_skip_switches():
    assert list(inspect.signature(promote_mover.Mover.move).parameters) == ["self", "id", "sha", "branch", "authorize", "deadline"]
    assert list(inspect.signature(promote_mover.Mover.witness).parameters) == ["self", "id", "sha", "branch", "attempt", "deadline"]
    source = Path(promote_mover.__file__).read_text(encoding="utf-8")
    assert "os.environ" not in source
    assert "os.getenv" not in source
    assert "BREAK_GLASS" not in source
    assert "SKIP_CHECK_RUNS" not in source


def test_e1_m1_n5_fresh_move_records_exact_witness_after_real_branch_update(repo, monkeypatch):
    instance = mover(repo)
    authorized = []
    original = subprocess.run
    pushes = []
    def recording_run(args, **kwargs):
        if "push" in args:
            pushes.append(list(args))
            if len(pushes) == 2:
                assert git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/moved")
        return original(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", recording_run)
    outcome = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0",
                            authorized.append, time.monotonic() + 60)
    assert outcome["outcome"] == "moved"
    assert len(authorized) == 1
    attempt = authorized[0]
    assert set(attempt) == {"tag", "object", "old"}
    assert attempt["old"] == repo["old"]
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["new"]
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/tags/{}".format(attempt["tag"])) == attempt["object"]
    assert git(repo["git"], repo["mirror"], "remote") == ""
    refs = git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm")
    assert "refs/k3dm/remote/heads/k3d-manager-v1.45.0" in refs
    assert "refs/k3dm/moved/" in refs
    assert "refs/tags/" not in refs
    assert git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/tags") == ""
    assert len(pushes) == 2
    assert "--force-with-lease=refs/heads/deploy/hub:{}".format(repo["old"]) in pushes[0]
    assert "--atomic" not in pushes[0]
    assert not any("refs/tags/" in arg for arg in pushes[0])
    assert pushes[1][-1] == "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])
    assert not any("refs/heads/" in arg for arg in pushes[1])
    tag = git(repo["git"], repo["origin"], "cat-file", "tag", attempt["object"])
    assert "tagger k3dm-promote <k3dm-promote@localhost>" in tag
    assert tag.split("\n\n", 1)[1].splitlines() == [
        "action: promote", "old: {}".format(repo["old"]), "new: {}".format(repo["new"]),
        "REF: {}".format(repo["new"]), "approval: p1-1234abcd"]


def test_e4_m4_n2_witness_tag_blocks_second_attempt(repo):
    instance = mover(repo)
    instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["old"], "k3d-manager-v1.45.0", lambda attempt: pytest.fail("authorized"), time.monotonic() + 60)
    assert error.value.code == "already_spent"


def test_e4_m4_one_foreign_witness_blocks_even_when_deploy_is_old(repo):
    instance = mover(repo)
    attempt = attempt_object(instance, repo, "p1-1234abcd", "hub-promote/20261021T010001Z")
    instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])])
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: pytest.fail("authorized"), time.monotonic() + 30)
    assert error.value.code == "already_spent"


def test_e4_m4_two_annotated_witnesses_are_conflict(repo):
    instance = mover(repo)
    for stamp in ("20261021T010002Z", "20261021T010003Z"):
        attempt = attempt_object(instance, repo, "p1-1234abcd", "hub-promote/{}".format(stamp))
        instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])])
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: pytest.fail("authorized"), time.monotonic() + 30)
    assert error.value.code == "witness_conflict"


def test_e4_m4_lightweight_tag_commit_message_is_ignored_and_old_equal_sha_refuses(repo):
    tree = git(repo["git"], repo["work"], "rev-parse", "{}^{{tree}}".format(repo["new"]))
    light_commit = git(repo["git"], repo["work"], "commit-tree", tree, "-p", repo["old"], input_text="approval: p1-1234abcd\n")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/tags/hub-promote/20200101T000000Z".format(light_commit))
    instance = mover(repo)
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert result["outcome"] == "moved"
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/deploy/hub".format(repo["new"]))
    with pytest.raises(hub_approval.Refused) as error:
        mover(repo).move("p2-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: pytest.fail("authorized"), time.monotonic() + 30)
    assert error.value.code == "deploy_moved"


def test_e7_m16_n8_other_writer_already_at_sha_gets_no_witness_tag(repo, tmp_path, monkeypatch):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    original_authorize = engine.authorize_push
    def authorize(request_id, sha, attempt):
        result = original_authorize(request_id, sha, attempt)
        # The callback represents a concurrent writer after the final recheck.
        git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]),
            "{}:refs/heads/deploy/hub".format(repo["new"]))
        return result
    engine.authorize_push = authorize
    original_git = instance._git
    branch_outputs = []
    def record_branch(args, *positional, **kwargs):
        result = original_git(args, *positional, **kwargs)
        if args and args[0] == "push" and any(str(arg).startswith("--force-with-lease=") for arg in args):
            branch_outputs.append(result.stdout)
        return result
    monkeypatch.setattr(instance, "_git", record_branch)
    commits = []
    original_commit = engine.commit_moved
    engine.commit_moved = lambda *args: (commits.append(args), original_commit(*args))[1]
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert error.value.code == "deploy_moved"
    assert "not by this approval" in error.value.message
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote") == ""
    assert git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/moved") == ""
    assert commits == []
    assert len(branch_outputs) == 1
    assert any(line.startswith("=\t") and "refs/heads/deploy/hub" in line for line in branch_outputs[0].splitlines())
    assert engine.show(id)["state"] == "approved"
    assert engine.show(id)["reason"] == "deploy_moved"


@pytest.mark.parametrize("runs, expected", [
    ([], "none"),
    ([{"status": "in_progress", "conclusion": None}], "pending"),
    ([{"status": "completed", "conclusion": "failure"}], "failed"),
    ([{"status": "completed", "conclusion": "neutral"}], "green"),
    ([{"status": "completed", "conclusion": "skipped"}], "green"),
])
def test_e3_m3_n7_check_run_classification(repo, runs, expected):
    class ScriptedApi(Api):
        def get_all(self, path, list_key, budget):
            budget()
            return 200, runs

    instance = mover(repo, ScriptedApi())
    assert instance._check(repo["new"], time.monotonic() + 20) == expected


def test_e6_m6_n4_failed_check_run_lookup_is_unknown(repo):
    class FailedApi(Api):
        def get_all(self, path, list_key, budget):
            budget()
            return 403, []

    with pytest.raises(hub_approval.Unknown) as error:
        mover(repo, FailedApi())._check(repo["new"], time.monotonic() + 20)
    assert error.value.code == "lookup_failed"


def test_e2_m2_branch_sort_is_numeric_and_rejects_loose_names():
    assert promote_mover.BRANCH.fullmatch("k3d-manager-v1.45.0")
    assert not promote_mover.BRANCH.fullmatch("k3d-manager-v1.45.0-evil")
    assert not promote_mover.BRANCH.fullmatch("k3d-manager-vX")


def test_e2_m2_requested_older_release_branch_is_refused(repo):
    git(repo["git"], repo["origin"], "update-ref", "-d", "refs/heads/k3d-manager-v1.45.0")
    for name in ("k3d-manager-v1.43.9", "k3d-manager-v1.43.15"):
        git(repo["git"], repo["origin"], "update-ref", "refs/heads/{}".format(name), repo["new"])
    with pytest.raises(hub_approval.Refused) as error:
        mover(repo).move("p1-1234abcd", repo["new"], "k3d-manager-v1.43.9", lambda attempt: pytest.fail("authorized"), time.monotonic() + 30)
    assert error.value.code == "not_newest_branch"


@pytest.mark.parametrize("names, expected", [
    (["k3d-manager-v1.43.9", "k3d-manager-v1.43.15"], "k3d-manager-v1.43.15"),
    (["k3d-manager-v1.43.15", "k3d-manager-vX", "k3d-manager-v1.45.0-evil", "k3d-manager-v1.045.0"], "k3d-manager-v1.43.15"),
    (["k3d-manager-v1.9.0", "k3d-manager-v1.10.0"], "k3d-manager-v1.10.0"),
])
def test_e2_m2_numeric_branch_sets_beat_plain_string_sort(repo, names, expected):
    git(repo["git"], repo["origin"], "update-ref", "-d", "refs/heads/k3d-manager-v1.45.0")
    for name in names:
        git(repo["git"], repo["origin"], "update-ref", "refs/heads/{}".format(name), repo["new"])
    instance = mover(repo)
    instance._fetch(time.monotonic() + 20)
    winner, _ = instance._branches()
    assert winner == expected
    assert sorted(names)[-1] != expected


def test_e3_m3_first_parent_walk_is_limited_to_twenty_and_ignores_side_parent(repo):
    # Synthesized first-parent/check-runs fixture pending the captured hub response.
    chain = [repo["new"]]
    for index in range(20):
        chain.append(commit_file(repo, "chain", "{}\n".format(index), "chain {}".format(index)))
    git(repo["git"], repo["work"], "branch", "side", repo["old"])
    git(repo["git"], repo["work"], "checkout", "-q", "side")
    side_commit = commit_file(repo, "side-only", "green\n", "side green")
    git(repo["git"], repo["work"], "checkout", "-q", "main")
    git(repo["git"], repo["work"], "merge", "--no-ff", "-qm", "merge side", "side")
    tip = git(repo["git"], repo["work"], "rev-parse", "HEAD")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/k3d-manager-v1.45.0".format(tip))
    class SideGreenApi(Api):
        def get_all(self, path, list_key, budget):
            budget()
            commit = path.rsplit("/", 2)[-2]
            runs = [{"status": "completed", "conclusion": "success"}] if commit == side_commit else []
            return 200, runs
    instance = mover(repo, SideGreenApi())
    instance._fetch(time.monotonic() + 30)
    walked, states, green = instance._green_walk("k3d-manager-v1.45.0", time.monotonic() + 30)
    assert len(walked) == 20
    assert side_commit not in walked
    assert green is None
    assert len(states) == 20


def test_e3_m3_first_green_at_commit_twenty_is_found_but_commit_twenty_one_is_not(repo):
    # Synthesized check-runs fixture pending the captured hub response.
    chain = [repo["new"]]
    for index in range(20):
        chain.append(commit_file(repo, "walk", "{}\n".format(index), "walk {}".format(index)))
    tip = chain[-1]
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/k3d-manager-v1.45.0".format(tip))
    class OldestOnly(Api):
        def __init__(self, green):
            self.green = green
        def get_all(self, path, list_key, budget):
            budget()
            commit = path.rsplit("/", 2)[-2]
            runs = [{"status": "completed", "conclusion": "success"}] if commit == self.green else []
            return 200, runs
    instance = mover(repo, OldestOnly(chain[-2]))
    instance._fetch(time.monotonic() + 30)
    walked, states, green = instance._green_walk("k3d-manager-v1.45.0", time.monotonic() + 30)
    assert len(walked) == 20
    assert green == chain[-2]
    missing = mover(repo, OldestOnly(chain[0]))
    _, _, not_found = missing._green_walk("k3d-manager-v1.45.0", time.monotonic() + 30)
    assert not_found is None


def _squash_fixture(repo):
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "target", repo["old"])
    squash = commit_file(repo, "merge-result", "merged\n", "squash merge")
    target = commit_file(repo, "target-result", "target\n", "target")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(target))
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "deploy-diverged", repo["old"])
    old = commit_file(repo, "deploy-only", "deployment\n", "deploy-only")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/deploy/hub".format(old))
    repo["old"] = old
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "pull-head", old)
    head = commit_file(repo, "pull-result", "pull\n", "pull head")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/pull/17/head".format(head))
    return squash, target, head


def test_e5_m5_patch_equivalent_target_is_contained(repo):
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "equivalent", repo["old"])
    equivalent = commit_file(repo, "file", "new\n", "equivalent change")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/deploy/hub".format(equivalent))
    instance = mover(repo)
    instance._fetch(time.monotonic() + 30)
    instance._contains(repo["new"], equivalent, time.monotonic() + 30)


def test_e5_m5_squash_pr_fetches_missing_head_from_pull_ref(repo):
    squash, target, head = _squash_fixture(repo)
    assert git(repo["git"], repo["work"], "cherry", target, repo["old"]).startswith("+ ")
    row = {"number": 17, "head": {"sha": head}, "merge_commit_sha": squash, "merged_at": "2026-01-01T00:00:00Z"}
    instance = mover(repo, ScriptedApi(pulls=[row]))
    instance._fetch(time.monotonic() + 30)
    assert instance._git(["cat-file", "-e", head], time.monotonic() + 10, check=False).returncode != 0
    instance._contains(target, repo["old"], time.monotonic() + 30)
    assert instance._git(["cat-file", "-e", head], time.monotonic() + 10).returncode == 0


def test_e5_m5_pulls_rows_are_read_across_two_pages(repo, monkeypatch):
    squash, target, head = _squash_fixture(repo)
    row = {"number": 17, "head": {"sha": head}, "merge_commit_sha": squash, "merged_at": "2026-01-01T00:00:00Z"}
    api = promote_mover.CurlApi("unused-token-path")
    requests = []
    def get(path, timeout):
        requests.append((path, timeout))
        page = 1 if path.endswith("page=1") else 2
        return 200, ([{"ignored": index} for index in range(100)] if page == 1 else [row])
    monkeypatch.setattr(api, "get", get)
    instance = mover(repo, api)
    instance._fetch(time.monotonic() + 30)
    instance._contains(target, repo["old"], time.monotonic() + 30)
    assert len(requests) == 2
    assert "per_page=100&page=1" in requests[0][0]
    assert "per_page=100&page=2" in requests[1][0]


def test_e5_m5_uncontained_commits_are_refused(repo):
    _squash, target, _head = _squash_fixture(repo)
    instance = mover(repo, ScriptedApi(pulls=[]))
    instance._fetch(time.monotonic() + 30)
    with pytest.raises(hub_approval.Refused) as error:
        instance._contains(target, repo["old"], time.monotonic() + 30)
    assert error.value.code == "not_contained"


def test_e5_m5_unresolved_pull_row_does_not_hide_later_accepted_row(repo):
    squash, target, head = _squash_fixture(repo)
    # Synthesized PR rows pending proof owed 3; the first row's head ref is absent.
    rows = [
        {"number": 18, "head": {"sha": "f" * 40}, "merge_commit_sha": squash, "merged_at": "2026-01-01"},
        {"number": 17, "head": {"sha": head}, "merge_commit_sha": squash, "merged_at": "2026-01-01"},
    ]
    instance = mover(repo, ScriptedApi(pulls=rows))
    instance._fetch(time.monotonic() + 30)
    instance._contains(target, repo["old"], time.monotonic() + 30)


def test_e5_m5_m6_mixed_rejected_and_unresolved_rows_are_unknown(repo):
    squash, target, head = _squash_fixture(repo)
    # Synthesized PR rows pending proof owed 3; one head mismatches and one lookup is absent.
    rows = [
        {"number": 17, "head": {"sha": "f" * 40}, "merge_commit_sha": squash, "merged_at": "2026-01-01"},
        {"number": 18, "head": {"sha": head}, "merge_commit_sha": squash, "merged_at": "2026-01-01"},
    ]
    instance = mover(repo, ScriptedApi(pulls=rows))
    instance._fetch(time.monotonic() + 30)
    with pytest.raises(hub_approval.Unknown) as error:
        instance._contains(target, repo["old"], time.monotonic() + 30)
    assert error.value.code == "lookup_failed"


def test_e6_m6_failed_pulls_lookup_is_unknown_when_evidence_is_needed(repo):
    _squash, target, _head = _squash_fixture(repo)
    class FailedPulls(Api):
        def get_all(self, path, list_key, budget):
            budget()
            return 429, []
    instance = mover(repo, FailedPulls())
    instance._fetch(time.monotonic() + 30)
    with pytest.raises(hub_approval.Unknown) as error:
        instance._contains(target, repo["old"], time.monotonic() + 30)
    assert error.value.code == "lookup_failed"


def test_e3_m3_newest_green_must_equal_requested_sha(repo):
    newer = commit_file(repo, "newer-green", "green\n", "newer green")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(newer))
    instance = mover(repo)
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert error.value.code == "not_newest_green"
    assert newer[:7] in error.value.message


def test_e3_m3_no_green_refuses_not_green(repo):
    class NoGreen(Api):
        def get_all(self, path, list_key, budget):
            budget()
            return 200, []
    with pytest.raises(hub_approval.Refused) as error:
        mover(repo, NoGreen()).move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert error.value.code == "not_green"


def test_e9_m10_consumed_record_returns_without_remote_calls(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    attempt = {"tag": "hub-promote/20261021T000000Z", "object": repo["new"], "old": repo["old"]}
    engine.authorize_push(id, repo["new"], attempt)
    engine.commit_moved(id, repo["old"], repo["new"], attempt["tag"])
    class NoRemote:
        def move(self, *args):
            pytest.fail("consumed record called move")
        def witness(self, *args):
            pytest.fail("consumed record called witness")
    result = promote_mover.promote(engine, NoRemote(), id, repo["new"], time.monotonic() + 30)
    assert result == {"outcome": "already", "old": repo["old"], "new": repo["new"], "tag": attempt["tag"]}


def test_e9_m10_m17_recover_marker_and_exact_tag_commits_then_drops_refs(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id, "hub-promote/20261021T000001Z")
    engine.authorize_push(id, repo["new"], attempt)
    marker = "refs/k3dm/moved/20261021T000001Z"
    instance._git(["update-ref", marker, attempt["object"]])
    instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])])
    result = promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 30)
    assert result["outcome"] == "moved"
    assert engine.show(id)["state"] == "consumed"
    assert instance._git(["show-ref", "--verify", "refs/k3dm/pending/20261021T000001Z"], check=False).returncode != 0
    assert instance._git(["show-ref", "--verify", marker], check=False).returncode != 0


def test_e9_m10_m17_recover_marker_without_tag_pushes_tag_only(repo, tmp_path, monkeypatch):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id, "hub-promote/20261021T000002Z")
    engine.authorize_push(id, repo["new"], attempt)
    instance._git(["update-ref", "refs/k3dm/moved/20261021T000002Z", attempt["object"]])
    original = subprocess.run
    pushes = []
    def recording_run(args, **kwargs):
        if "push" in args:
            pushes.append(args)
        return original(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", recording_run)
    result = promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 30)
    assert result["outcome"] == "moved"
    assert len(pushes) == 1
    assert all("refs/heads/" not in arg for arg in pushes[0])
    assert pushes[0][-1] == "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


def test_e9_m11_recover_exact_remote_tag_without_marker_is_final_witness_conflict(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id, "hub-promote/20261021T000003Z")
    engine.authorize_push(id, repo["new"], attempt)
    instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])])
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 30)
    assert error.value.code == "witness_conflict"
    assert error.value.approval == "final"
    assert engine.show(id)["state"] == "approved"
    assert engine.show(id)["push_at"] is not None


def test_e9_m11_authentic_but_different_object_is_already_spent(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id, "hub-promote/20261021T000004Z", message_old=repo["old"])
    engine.authorize_push(id, repo["new"], attempt)
    foreign = attempt_object(instance, repo, id, "hub-promote/20261021T000004Z", message_old=repo["new"])
    instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(foreign["object"], foreign["tag"])])
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 30)
    assert error.value.code == "already_spent"
    assert error.value.approval == "final"
    assert engine.show(id)["push_at"] is not None


def test_e9_m16_recovery_race_finishes_unmoved_then_freshly_refuses_deploy_at_sha(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id, "hub-promote/20261021T000005Z")
    engine.authorize_push(id, repo["new"], attempt)
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/deploy/hub".format(repo["new"]))
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert error.value.code == "deploy_moved"
    assert engine.show(id)["push_at"] is None
    assert engine.show(id)["reason"] == "deploy_moved"
    assert engine.show(id)["state"] == "approved"
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote") == ""
    assert git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/moved") == ""


@pytest.mark.parametrize("stage", [
    "fetch", "witness", "old", "branches", "contains", "check", "tag_preflight",
    "recheck_fetch", "recheck_witness", "recheck_branches", "recheck_check", "recheck_deploy",
])
def test_e6_m6_n4_each_pre_authorize_lookup_failure_is_unknown(repo, monkeypatch, stage):
    instance = mover(repo)
    calls = {"fetch": 0, "witness": 0, "branches": 0, "check": 0, "old": 0}
    def fail(*args, **kwargs):
        raise hub_approval.Unknown("lookup_failed", "scripted lookup failure")
    if stage in ("fetch", "recheck_fetch"):
        original = instance._fetch
        def wrapped(*args, **kwargs):
            calls["fetch"] += 1
            if (stage == "fetch" and calls["fetch"] == 1) or (stage == "recheck_fetch" and calls["fetch"] == 2):
                return fail()
            return original(*args, **kwargs)
        monkeypatch.setattr(instance, "_fetch", wrapped)
    elif stage in ("witness", "recheck_witness"):
        original = instance._block_witness
        def wrapped(*args, **kwargs):
            calls["witness"] += 1
            if (stage == "witness" and calls["witness"] == 1) or (stage == "recheck_witness" and calls["witness"] == 2):
                return fail()
            return original(*args, **kwargs)
        monkeypatch.setattr(instance, "_block_witness", wrapped)
    elif stage in ("branches", "recheck_branches"):
        original = instance._branches
        def wrapped(*args, **kwargs):
            calls["branches"] += 1
            if (stage == "branches" and calls["branches"] == 1) or (stage == "recheck_branches" and calls["branches"] == 2):
                return fail()
            return original(*args, **kwargs)
        monkeypatch.setattr(instance, "_branches", wrapped)
    elif stage in ("check", "recheck_check"):
        original = instance._check
        def wrapped(*args, **kwargs):
            calls["check"] += 1
            if (stage == "check" and calls["check"] == 1) or (stage == "recheck_check" and calls["check"] == 2):
                return fail()
            return original(*args, **kwargs)
        monkeypatch.setattr(instance, "_check", wrapped)
    elif stage == "contains":
        monkeypatch.setattr(instance, "_contains", fail)
    else:
        original = instance._ls_remote
        def wrapped(refs, *args, **kwargs):
            refs = list(refs)
            is_old = refs == ["refs/heads/deploy/hub"]
            if stage == "old" and is_old and calls["old"] == 0:
                calls["old"] += 1
                return fail()
            if stage == "recheck_deploy" and is_old:
                calls["old"] += 1
                if calls["old"] == 2:
                    return fail()
            if stage == "tag_preflight" and refs == ["refs/tags/hub-promote/{}".format(instance._stamp())]:
                return fail()
            return original(refs, *args, **kwargs)
        monkeypatch.setattr(instance, "_ls_remote", wrapped)
    class RecordingEngine:
        def __init__(self):
            self.calls = []
        def authorize_push(self, request_id, sha, attempt):
            self.calls.append(("authorize_push", request_id, sha, attempt))
        def note_refusal(self, request_id, code):
            self.calls.append(("note_refusal", request_id, code))
        def commit_moved(self, request_id, old, new, tag):
            self.calls.append(("commit_moved", request_id, old, new, tag))
    engine = RecordingEngine()
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0",
                      lambda attempt: engine.authorize_push("p1-1234abcd", repo["new"], attempt), time.monotonic() + 60)
    assert error.value.code == "lookup_failed"
    assert engine.calls == []
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


def test_e6_m6_n5_post_push_tag_observation_failure_stays_unknown(repo, monkeypatch):
    instance = mover(repo)
    original = instance._git
    def fail_tag_observation(args, *positional, **kwargs):
        if args and args[0] == "ls-remote" and len(args) > 2 and str(args[-1]).startswith("refs/tags/hub-promote/"):
            return subprocess.CompletedProcess(args, 1, "", "scripted observation failure")
        return original(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", fail_tag_observation)
    authorizations = []
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorizations.append, time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert len(authorizations) == 1
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["new"]


def test_e6_m6_n5_engine_observation_failure_calls_only_begin_and_authorize(repo, tmp_path, monkeypatch):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    original_git = instance._git
    def fail_tag_observation(args, *positional, **kwargs):
        if args and args[0] == "ls-remote" and len(args) > 2 and str(args[-1]).startswith("refs/tags/hub-promote/"):
            return subprocess.CompletedProcess(args, 1, "", "observation unavailable")
        return original_git(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", fail_tag_observation)
    calls = []
    for name in ("begin_promote", "authorize_push", "note_refusal", "commit_moved", "finish_unmoved"):
        original = getattr(engine, name)
        def record(*args, _name=name, _original=original, **kwargs):
            calls.append(_name)
            return _original(*args, **kwargs)
        setattr(engine, name, record)
    with pytest.raises(hub_approval.Unknown) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert calls == ["begin_promote", "authorize_push"]
    assert engine.show(id)["push_at"] is not None


def test_e1_n9_authorize_runs_after_recheck_and_authorize_refusal_stops_push(repo, monkeypatch):
    events = []
    class OrderedApi(Api):
        def get_all(self, path, list_key, budget):
            events.append("check")
            return super().get_all(path, list_key, budget)
    instance = mover(repo, OrderedApi())
    original = subprocess.run
    def recording_run(args, **kwargs):
        if "push" in args:
            events.append("push")
        return original(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", recording_run)
    def reject(_attempt):
        events.append("authorize")
        raise hub_approval.Refused("expired", approval="kept")
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", reject, time.monotonic() + 60)
    assert error.value.code == "expired"
    assert events[-1] == "authorize"
    assert events.index("authorize") > max(index for index, event in enumerate(events) if event == "check")
    assert "push" not in events
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


@pytest.mark.parametrize("error", [hub_approval.Refused("expired", approval="kept"), hub_approval.Unknown("deadline")])
def test_e9_n9_authorize_engine_error_is_not_noted_or_rewritten(repo, error):
    calls = []
    class EngineDouble:
        def begin_promote(self, request_id, sha):
            calls.append("begin_promote")
            return {"mode": "fresh", "record": {"branch": "k3d-manager-v1.45.0"}}
        def authorize_push(self, request_id, sha, attempt):
            calls.append("authorize_push")
            raise error
        def note_refusal(self, request_id, code):
            calls.append("note_refusal")
            pytest.fail("engine authorize refusal must not be noted")
    with pytest.raises(type(error)) as caught:
        promote_mover.promote(EngineDouble(), mover(repo), "p1-1234abcd", repo["new"], time.monotonic() + 60)
    assert caught.value is error
    assert calls == ["begin_promote", "authorize_push"]
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


def test_e9_m10_fresh_refusal_is_noted_but_final_witness_is_not(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    class NoGreen(Api):
        def get_all(self, path, key, budget):
            budget()
            return 200, []
    no_green = mover(repo, NoGreen())
    with pytest.raises(hub_approval.Refused) as refusal:
        promote_mover.promote(engine, no_green, id, repo["new"], time.monotonic() + 60)
    assert refusal.value.code == "not_green"
    assert refusal.value.approval == "kept"
    assert engine.show(id)["reason"] == "not_green"

    engine2, id2 = approved_engine(repo, tmp_path / "second")
    instance = mover(repo)
    attempt = attempt_object(instance, repo, id2, "hub-promote/20261021T020001Z")
    engine2.authorize_push(id2, repo["new"], attempt)
    foreign = attempt_object(instance, repo, id2, "hub-promote/20261021T020002Z")
    instance._git(["push", "--porcelain", str(repo["origin"]), "{}:refs/tags/{}".format(foreign["object"], foreign["tag"])])
    with pytest.raises(hub_approval.Refused) as final:
        promote_mover.promote(engine2, instance, id2, repo["new"], time.monotonic() + 30)
    assert final.value.code == "already_spent"
    assert final.value.approval == "final"
    assert engine2.show(id2)["reason"] is None


@pytest.mark.parametrize("exception", [hub_approval.Refused("clock_backwards"), hub_approval.Unknown("io")])
def test_e9_m10_commit_moved_error_becomes_unknown_and_retry_recovers(repo, tmp_path, exception):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    original = engine.commit_moved
    engine.commit_moved = lambda *args: (_ for _ in ()).throw(exception)
    with pytest.raises(hub_approval.Unknown) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert engine.show(id)["push_at"] is not None
    engine.commit_moved = original
    result = promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert result["outcome"] == "moved"
    assert engine.show(id)["state"] == "consumed"


def test_e8_n1_n3_n6_hostile_environment_isolated_and_hooks_disabled(repo, tmp_path, monkeypatch):
    instance = mover(repo)
    key_path = tmp_path / "deploy_key"
    key_path.write_text("deploy-key-secret-material", encoding="utf-8")
    instance.ssh_command = "/usr/bin/ssh -i {} -o IdentitiesOnly=yes".format(key_path)
    instance.prime()
    hooks = repo["mirror"] / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    marker = tmp_path / "hook-ran"
    hook = hooks / "pre-push"
    hook.write_text("#!/bin/sh\nprintf ran > '{}'\n".format(marker), encoding="utf-8")
    os.chmod(hook, 0o700)
    positive = subprocess.run([repo["git"], "-c", "core.hooksPath={}".format(hooks), "push", str(repo["origin"]),
                               "{}:refs/heads/hook-control".format(repo["new"])], cwd=repo["mirror"],
                              env={"PATH": "/usr/bin:/bin", "HOME": str(tmp_path)}, capture_output=True, text=True, check=False)
    assert positive.returncode == 0
    assert marker.read_text(encoding="utf-8") == "ran"
    marker.unlink()
    monkeypatch.setenv("GH_REPO", "hostile/elsewhere")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(tmp_path / "hostile-gitconfig"))
    monkeypatch.setenv("HOME", str(tmp_path / "hostile-home"))
    monkeypatch.setenv("PATH", "/hostile/path")
    monkeypatch.setenv("K3DM_HOSTILE_SENTINEL", "hostile-value")
    original = subprocess.run
    calls = []
    def recording_run(args, **kwargs):
        if args and os.path.realpath(args[0]) == repo["git"]:
            calls.append((list(args), kwargs.get("env")))
        return original(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", recording_run)
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert result["outcome"] == "moved"
    expected = {"PATH": "/usr/bin:/bin", "HOME": str(repo["mirror"]), "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": instance.ssh_command}
    assert calls and all(env == expected for _args, env in calls)
    assert all("deploy-key-secret-material" not in " ".join(args) for args, _env in calls)
    assert not marker.exists()


@pytest.mark.parametrize("stage", ["new_branch", "branch_tip", "deploy"])
def test_e7_m7_recheck_changes_reject_before_authorize(repo, stage):
    instance = mover(repo)
    api = instance.api
    original_all = api.get_all
    fired = {"value": False}
    def mutate(path, key, budget):
        if not fired["value"]:
            fired["value"] = True
            if stage == "new_branch":
                git(repo["git"], repo["origin"], "update-ref", "refs/heads/k3d-manager-v9.0.0", repo["new"])
            elif stage == "branch_tip":
                git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(repo["old"]))
            else:
                git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/deploy/hub".format(repo["new"]))
        return original_all(path, key, budget)
    api.get_all = mutate
    authorized = []
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized.append, time.monotonic() + 60)
    assert error.value.code == ("deploy_moved" if stage == "deploy" else "release_moved")
    assert authorized == []


def test_e7_m7_pending_object_is_not_a_recheck_witness(repo):
    instance = mover(repo)
    seen = []
    class CheckPending(Api):
        def get_all(self, path, list_key, budget):
            budget()
            if list_key == "check_runs":
                pending = git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/pending")
                witnesses = git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/witness")
                if pending:
                    seen.append((pending, witnesses))
                return 200, [{"status": "completed", "conclusion": "success"}]
            return 200, []
    instance.api = CheckPending()
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert result["outcome"] == "moved"
    assert seen and all("refs/k3dm/pending/" in pending and "refs/k3dm/witness/" not in witnesses for pending, witnesses in seen)


@pytest.mark.parametrize("change", ["newer_green", "sha_stopped_green"])
def test_e7_m7_recheck_revalidates_green_prefix(repo, change):
    newer = commit_file(repo, "newer", "newer\n", "newer tip")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(newer))
    class ChangingChecks(Api):
        def __init__(self):
            self.seen = {}
        def get_all(self, path, list_key, budget):
            budget()
            commit = path.rsplit("/", 2)[-2]
            self.seen[commit] = self.seen.get(commit, 0) + 1
            if change == "newer_green" and commit == newer:
                status = "in_progress" if self.seen[commit] == 1 else "completed"
                conclusion = None if status != "completed" else "success"
            elif change == "sha_stopped_green" and commit == repo["new"] and self.seen[commit] > 1:
                status, conclusion = "completed", "failure"
            else:
                status, conclusion = "completed", "success" if commit == repo["new"] else None
            runs = [{"status": status, "conclusion": conclusion}] if status else []
            return 200, runs
    instance = mover(repo, ChangingChecks())
    authorized = []
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized.append, time.monotonic() + 60)
    assert error.value.code == "release_moved"
    assert authorized == []


def test_e7_m8_existing_generated_tag_blocks_authorize(repo):
    instance = mover(repo)
    name = "hub-promote/{}".format(instance._stamp())
    git(repo["git"], repo["work"], "tag", "-a", name, "-m", "taken")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "refs/tags/{}:refs/tags/{}".format(name, name))
    authorized = []
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized.append, time.monotonic() + 60)
    assert error.value.code == "tag_exists"
    assert authorized == []


def test_e7_m12_stale_lease_rejects_even_when_unleased_update_would_fast_forward(repo):
    middle = commit_file(repo, "middle", "middle\n", "middle")
    newest = commit_file(repo, "newest", "newest\n", "newest")
    repo["new"] = newest
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(newest))
    instance = mover(repo)
    def authorize(attempt):
        git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "{}:refs/heads/deploy/hub".format(middle))
    with pytest.raises(hub_approval.Refused) as error:
        instance.move("p1-1234abcd", newest, "k3d-manager-v1.45.0", authorize, time.monotonic() + 60)
    assert error.value.code == "deploy_moved"
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == middle
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote") == ""


def test_e7_m15_deny_non_fast_forwards_never_attempts_tag_push(repo, monkeypatch):
    base = repo["old"]
    deploy_old = commit_file(repo, "deploy-only", "deploy\n", "deploy only")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/deploy/hub".format(deploy_old))
    repo["old"] = deploy_old
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "diverged", base)
    diverged = commit_file(repo, "diverged", "other\n", "diverged")
    repo["new"] = diverged
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(diverged))
    git(repo["git"], repo["origin"], "config", "receive.denyNonFastForwards", "true")
    instance = mover(repo)
    # Isolate the server's non-fast-forward rejection; containment is exercised in E5.
    instance._contains = lambda target, old, deadline: None
    original = subprocess.run
    pushes = []
    def recording_run(args, **kwargs):
        if "push" in args:
            pushes.append(args)
        return original(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", recording_run)
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", diverged, "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert len(pushes) == 1
    assert not any("refs/tags/" in arg for arg in pushes[0])
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


def test_e7_m9_forced_update_porcelain_plus_flag_is_credited(repo):
    base = repo["old"]
    deploy_old = commit_file(repo, "deploy-only", "deploy\n", "deploy only")
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/deploy/hub".format(deploy_old))
    repo["old"] = deploy_old
    git(repo["git"], repo["work"], "checkout", "-q", "-B", "forced-target", base)
    target = commit_file(repo, "forced-target", "target\n", "forced target")
    repo["new"] = target
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(target))
    instance = mover(repo)
    # Containment is separately exercised in E5; this fixture isolates the forced-update report.
    instance._contains = lambda sha, old, deadline: None
    result = instance.move("p1-1234abcd", target, "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert result["outcome"] == "moved"
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == target


@pytest.mark.parametrize("shape, expected", [
    ("no_line", "push_unknown"), ("duplicate", "push_unknown"), ("unknown_flag", "push_unknown"),
    ("failed_after_update", "deploy_moved"), ("timeout_after_update", "deploy_moved"),
    ("timeout_at_old", "push_unknown"),
])
def test_e7_m9_n8_unconfirmed_branch_push_shapes_never_write_tag_or_marker(repo, monkeypatch, shape, expected):
    instance = mover(repo)
    original = instance._git
    ref = "refs/heads/deploy/hub"
    line = " \t{}:{}\t{}..{}\n".format(repo["new"], ref, repo["old"][:7], repo["new"][:7])
    branch_pushes = []
    tag_pushes = []
    def scripted(args, *positional, **kwargs):
        if args and args[0] == "push":
            if "--force-with-lease={}:{}".format(ref, repo["old"]) in args:
                branch_pushes.append(args)
                if shape in ("failed_after_update", "timeout_after_update"):
                    original(args, *positional, **kwargs)
                    if shape == "timeout_after_update":
                        return None
                    return subprocess.CompletedProcess(args, 1, line, "interrupted after update")
                if shape == "no_line":
                    return subprocess.CompletedProcess(args, 0, "To origin\nDone\n", "")
                if shape == "duplicate":
                    return subprocess.CompletedProcess(args, 0, line + line, "")
                if shape == "unknown_flag":
                    return subprocess.CompletedProcess(args, 0, "?\t{}:{}\tunknown\n".format(repo["new"], ref), "")
                return None
            tag_pushes.append(args)
        return original(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", scripted)
    with pytest.raises((hub_approval.Refused, hub_approval.Unknown)) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() + 60)
    assert error.value.code == expected
    assert len(branch_pushes) == 1
    assert tag_pushes == []
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote") == ""
    assert git(repo["git"], repo["mirror"], "for-each-ref", "--format=%(refname)", "refs/k3dm/moved") == ""


def test_e7_m9_n8_tag_name_taken_after_real_branch_update_is_final_conflict(repo, tmp_path):
    engine, id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    original = engine.authorize_push
    def competing_authorize(request_id, sha, attempt):
        result = original(request_id, sha, attempt)
        git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]),
            "{}:refs/tags/{}".format(repo["new"], attempt["tag"]))
        return result
    engine.authorize_push = competing_authorize
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, id, repo["new"], time.monotonic() + 60)
    assert error.value.code == "witness_conflict"
    assert error.value.approval == "final"
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["new"]


def test_e10_m13_deadline_refuses_before_fetch(repo):
    instance = mover(repo)
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, time.monotonic() - 1)
    assert error.value.code == "deadline"


def test_e10_m13_get_all_checks_budget_between_pages(monkeypatch):
    api = promote_mover.CurlApi("unused")
    requests = []
    monkeypatch.setattr(api, "get", lambda path, timeout: (requests.append((path, timeout)) or (200, [1] * 100)))
    calls = {"n": 0}
    def budget():
        calls["n"] += 1
        if calls["n"] == 1:
            return 7
        raise hub_approval.Unknown("deadline")
    with pytest.raises(hub_approval.Unknown) as error:
        api.get_all("/repos/a/b/pulls", None, budget)
    assert error.value.code == "deadline"
    assert len(requests) == 1
    assert requests[0][1] == 7


@pytest.mark.parametrize("status, body", [(403, None), (429, None), (500, None), (200, {"wrong": []})])
def test_e6_m6_n4_api_failures_never_become_green(tmp_path, monkeypatch, status, body):
    api = promote_mover.CurlApi("unused")
    monkeypatch.setattr(api, "get", lambda path, timeout: (status, body if body is not None else []))
    instance = promote_mover.Mover("unused", "owner/repo", api, "", str(tmp_path),
                                   Clock(), git=shutil_which("git"))
    with pytest.raises(hub_approval.Unknown) as error:
        instance._api_all("/repos/owner/repo/commits/deadbeef/check-runs", "check_runs", time.monotonic() + 30)
    assert error.value.code == "lookup_failed"


def test_e6_m6_more_than_ten_api_pages_is_a_lookup_failure(monkeypatch):
    api = promote_mover.CurlApi("unused")
    calls = []
    monkeypatch.setattr(api, "get", lambda path, timeout: (calls.append(path) or (200, [0] * 100)))
    status, items = api.get_all("/repos/a/b/pulls", None, lambda: 20)
    assert status == 0
    assert items == []
    assert len(calls) == 10


def test_e10_m13_deadline_before_fifth_walk_lookup_prevents_authorize(repo):
    now = {"value": 0.0}
    deadline = 100.0
    tip = repo["new"]
    for index in range(5):
        tip = commit_file(repo, "deadline-walk", "{}\n".format(index), "deadline {}".format(index))
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]), "+{}:refs/heads/k3d-manager-v1.45.0".format(tip))
    class TightAfterFour(Api):
        def __init__(self):
            self.calls = 0
        def get_all(self, path, list_key, budget):
            budget()
            self.calls += 1
            if self.calls == 4:
                now["value"] = deadline - 0.5
            return 200, []
    instance = promote_mover.Mover(str(repo["origin"]), "owner/repo", TightAfterFour(), "", str(repo["mirror"]),
                                   Clock(), monotonic=lambda: now["value"], git=repo["git"])
    authorized = []
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized.append, deadline)
    assert error.value.code == "deadline"
    assert instance.api.calls == 4
    assert authorized == []


def test_e10_m13_deadline_expires_after_final_recheck_before_push(repo, monkeypatch):
    now = {"value": 0.0}
    deadline = 100.0
    instance = promote_mover.Mover(str(repo["origin"]), "owner/repo", Api(), "", str(repo["mirror"]),
                                   Clock(), monotonic=lambda: now["value"], git=repo["git"])
    original = instance._ls_remote
    calls = {"old": 0}
    def final_recheck(refs, *args, **kwargs):
        result = original(refs, *args, **kwargs)
        if list(refs) == ["refs/heads/deploy/hub"]:
            calls["old"] += 1
            if calls["old"] == 2:
                now["value"] = deadline - 0.5
        return result
    monkeypatch.setattr(instance, "_ls_remote", final_recheck)
    authorized = []
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized.append, deadline)
    assert error.value.code == "deadline"
    assert authorized == []
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["old"]


def test_e10_m13_push_and_observation_finish_after_deadline_passes(repo):
    now = {"value": 0.0}
    deadline = 100.0
    instance = promote_mover.Mover(str(repo["origin"]), "owner/repo", Api(), "", str(repo["mirror"]),
                                   Clock(), monotonic=lambda: now["value"], git=repo["git"])
    def authorized(_attempt):
        now["value"] = deadline + 0.5
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", authorized, deadline)
    assert result["outcome"] == "moved"


def test_e8_m14_n1_n3_curl_uses_stdin_config_and_isolated_environment(monkeypatch, tmp_path):
    token = tmp_path / "token"
    token.write_text("secret-token\n", encoding="utf-8")
    captured = {}

    class Result:
        returncode = 0
        stdout = '{"ok":true}\n200'

    def run(args, **kwargs):
        captured.update(args=args, **kwargs)
        return Result()

    monkeypatch.setattr(promote_mover.subprocess, "run", run)
    status, body = promote_mover.CurlApi(str(token)).get("/repos/a/b", 5)
    assert status == 200 and body == {"ok": True}
    assert captured["args"][1] == "-q"
    assert "-K" in captured["args"] and "-H" not in captured["args"]
    assert captured["env"] == {"PATH": "/usr/bin:/bin"}
    assert "secret-token" in captured["input"]
    assert "secret-token" not in " ".join(captured["args"])


def test_e8_n3_curl_failure_does_not_return_secret_in_body_or_error(monkeypatch, tmp_path):
    token = tmp_path / "token"
    token.write_text("secret-token\n", encoding="utf-8")
    class Failure:
        returncode = 22
        stdout = ""
        stderr = "curl failed while using secret-token"
    monkeypatch.setattr(promote_mover.subprocess, "run", lambda *args, **kwargs: Failure())
    result = promote_mover.CurlApi(str(token)).get("/repos/a/b", 2)
    assert result == (0, None)
    assert "secret-token" not in repr(result)


def test_e7_m9_n8_absent_tag_after_real_update_is_unknown(repo, monkeypatch):
    instance = mover(repo)
    original = instance._git
    def hide_tag_observation(args, *positional, **kwargs):
        if args and args[0] == "ls-remote" and len(args) > 2 and str(args[-1]).startswith("refs/tags/hub-promote/"):
            return subprocess.CompletedProcess(args, 0, "", "")
        return original(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", hide_tag_observation)
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None,
                      time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert git(repo["git"], repo["origin"], "rev-parse", "refs/heads/deploy/hub") == repo["new"]
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote")


def test_e7_m9_n8_rejected_flag_with_zero_exit_is_not_a_real_update(repo, monkeypatch):
    instance = mover(repo)
    original = instance._git
    branch_ref = "refs/heads/deploy/hub"
    branch_pushes = []
    tag_pushes = []
    def reject_with_zero(args, *positional, **kwargs):
        if args and args[0] == "push":
            if any(str(arg).startswith("--force-with-lease=") for arg in args):
                branch_pushes.append(args)
                line = "!\t{}:{}\t[rejected]\n".format(repo["new"], branch_ref)
                return subprocess.CompletedProcess(args, 0, line, "")
            tag_pushes.append(args)
        return original(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", reject_with_zero)
    with pytest.raises(hub_approval.Unknown) as error:
        instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None,
                      time.monotonic() + 60)
    assert error.value.code == "push_unknown"
    assert len(branch_pushes) == 1
    assert tag_pushes == []
    assert git(repo["git"], repo["origin"], "rev-parse", branch_ref) == repo["old"]
    assert git(repo["git"], repo["origin"], "for-each-ref", "--format=%(refname)", "refs/tags/hub-promote") == ""


def test_e9_m10_fresh_already_spent_does_not_call_note_refusal(repo, tmp_path):
    engine, request_id = approved_engine(repo, tmp_path)
    instance = mover(repo)
    attempt = attempt_object(instance, repo, request_id, "hub-promote/20261021T030001Z")
    instance._git(["push", "--porcelain", str(repo["origin"]),
                   "{}:refs/tags/{}".format(attempt["object"], attempt["tag"])])
    note_calls = []
    original_note = engine.note_refusal
    def record_note(*args, **kwargs):
        note_calls.append(args)
        return original_note(*args, **kwargs)
    engine.note_refusal = record_note
    with pytest.raises(hub_approval.Refused) as error:
        promote_mover.promote(engine, instance, request_id, repo["new"], time.monotonic() + 30)
    assert error.value.code == "already_spent"
    assert error.value.approval == "final"
    assert note_calls == []


def test_e5_m5_squash_pr_merge_not_ancestor_does_not_authorize(repo):
    _squash, target, head = _squash_fixture(repo)
    tree = git(repo["git"], repo["work"], "rev-parse", "{}^{{tree}}".format(target))
    unrelated_merge = git(repo["git"], repo["work"], "commit-tree", tree, input_text="unrelated merge\n")
    ancestry = subprocess.run([repo["git"], "merge-base", "--is-ancestor", unrelated_merge, target],
                              cwd=repo["work"], capture_output=True, text=True, check=False)
    assert ancestry.returncode == 1
    git(repo["git"], repo["work"], "push", "-q", str(repo["origin"]),
        "{}:refs/heads/mutant-fixture-merge".format(unrelated_merge))
    row = {"number": 17, "head": {"sha": head}, "merge_commit_sha": unrelated_merge,
           "merged_at": "2026-01-01T00:00:00Z"}
    instance = mover(repo, ScriptedApi(pulls=[row]))
    instance._fetch(time.monotonic() + 30)
    with pytest.raises(hub_approval.Refused) as error:
        instance._contains(target, repo["old"], time.monotonic() + 30)
    assert error.value.code == "not_contained"


def test_e1_m1_fetches_disable_implicit_tags(repo, monkeypatch):
    instance = mover(repo)
    original = instance._git
    fetches = []
    def record_git(args, *positional, **kwargs):
        if args and args[0] == "fetch":
            fetches.append(list(args))
        return original(args, *positional, **kwargs)
    monkeypatch.setattr(instance, "_git", record_git)
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None,
                           time.monotonic() + 60)
    assert result["outcome"] == "moved"
    assert len(fetches) >= 2
    assert all("--no-tags" in args for args in fetches)


def test_e10_m13_pre_push_git_call_uses_remaining_budget(repo, monkeypatch):
    deadline = 20.0
    instance = promote_mover.Mover(str(repo["origin"]), "owner/repo", Api(), "", str(repo["mirror"]),
                                   Clock(), monotonic=lambda: 10.0, git=repo["git"])
    original_run = subprocess.run
    calls = []
    def record_run(args, **kwargs):
        if "fetch" in args:
            calls.append((list(args), kwargs.get("timeout")))
        return original_run(args, **kwargs)
    monkeypatch.setattr(promote_mover.subprocess, "run", record_run)
    result = instance.move("p1-1234abcd", repo["new"], "k3d-manager-v1.45.0", lambda attempt: None, deadline)
    assert result["outcome"] == "moved"
    assert calls
    assert all(timeout == 10.0 for _args, timeout in calls)
