import importlib.util
from importlib.machinery import SourceFileLoader
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "scripts" / "lib"
sys.path.insert(0, str(LIB))

from hermes import prior_art, retrieval_eval  # noqa: E402


@pytest.fixture(autouse=True)
def offline_credential(monkeypatch):
    monkeypatch.setattr(prior_art, "api_key", lambda: "test-secret")


@pytest.fixture
def push_lines(monkeypatch):
    captured = []

    class Response:
        def close(self):
            pass

    def open_request(request, timeout):
        assert request.full_url == "http://127.0.0.1:9/metrics/job/k3dm-vectordb-retrieval"
        assert timeout == 5
        captured.append(request.data.decode())
        return Response()

    monkeypatch.setattr("urllib.request.urlopen", open_request)
    return captured


def test_probe_calculates_recall_and_publishes_only_directory_labels(push_lines):
    docs = [(f"docs/bugs/q{i}.md", f"Q{i}", f"query {i}", f"h{i}") for i in range(4)]
    docs += [(f"docs/bugs/e{i}.md", f"E{i}", f"expected {i}", f"e{i}") for i in range(4)]
    pairs = [{"kind": "positive", "directory": "bugs", "query": f"docs/bugs/q{i}.md",
              "expected": f"docs/bugs/e{i}.md"} for i in range(4)]
    pairs += [{"kind": "hard-negative", "directory": "bugs", "query": f"docs/bugs/q{i}.md",
               "expected": "docs/bugs/negative.md"} for i in range(4)]
    calls = []

    def fake_search(text, k, credential=None):
        assert credential == "test-secret"
        calls.append((text, k))
        index = int(text.rsplit(" ", 1)[1])
        return [(1.0, f"docs/bugs/e{index}.md", "sensitive title")] if index < 3 else []

    result = retrieval_eval.probe(
        repo_root=ROOT, ref="test-ref", search=fake_search,
        iter_corpus=lambda _root, _ref: docs,
        fetch_hashes=lambda: {f"docs/bugs/e{i}.md": f"e{i}" for i in range(4)},
        push_url="http://127.0.0.1:9", now=123, pairs=pairs)
    assert result["recall"] == {"bugs": 0.75}
    assert result["intrusion"] == {"bugs": 0.0}
    assert len(calls) == 8 and all(k == 6 for _text, k in calls)
    assert 'directory="bugs"' in push_lines[0]
    assert "sensitive" not in push_lines[0]
    assert "docs/" not in push_lines[0]
    assert "query" not in push_lines[0]


def test_stale_and_deleted_results_do_not_count_as_recall(push_lines):
    docs = [("docs/bugs/query.md", "Query", "query", "query-hash"),
            ("docs/bugs/expected.md", "Expected", "expected", "current-hash")]
    pairs = [{"kind": "positive", "directory": "bugs", "query": "docs/bugs/query.md",
              "expected": "docs/bugs/expected.md"}]
    result = retrieval_eval.probe(
        repo_root=ROOT, ref="test-ref",
        search=lambda *_a, **_k: [(1, "docs/bugs/expected.md", "title"),
                                  (0.9, "docs/bugs/deleted.md", "deleted title")],
        iter_corpus=lambda *_a: docs,
        fetch_hashes=lambda: {"docs/bugs/expected.md": "old-hash"},
        push_url="http://127.0.0.1:9", now=123, pairs=pairs)
    assert result["recall"] == {"bugs": 0.0}
    assert result["stale_hits"] == 1
    assert result["deleted_hits"] == 1


def test_fetch_hashes_runs_once_per_probe_regardless_of_query_count(push_lines):
    docs = [(f"docs/bugs/q{i}.md", f"Q{i}", f"query {i}", f"h{i}") for i in range(3)]
    pairs = [{"kind": "positive", "directory": "bugs", "query": f"docs/bugs/q{i}.md",
              "expected": "docs/bugs/expected.md"} for i in range(3)]
    calls = []
    retrieval_eval.probe(
        repo_root=ROOT, search=lambda *_a, **_k: [], iter_corpus=lambda *_a: docs,
        fetch_hashes=lambda: calls.append(1) or {}, push_url="http://127.0.0.1:9",
        pairs=pairs)
    assert len(calls) == 1


def test_probe_resolves_credential_once_reuses_it_and_never_publishes_it(
        push_lines, monkeypatch, capsys):
    docs = [(f"docs/bugs/q{i}.md", f"Q{i}", f"query {i}", f"h{i}") for i in range(3)]
    pairs = [{"kind": "positive", "directory": "bugs", "query": f"docs/bugs/q{i}.md",
              "expected": "docs/bugs/expected.md"} for i in range(3)]
    resolved = []
    seen = []
    monkeypatch.setattr(prior_art, "api_key", lambda: resolved.append(1) or "test-secret")

    def fake_search(text, k, credential=None):
        seen.append(credential)
        return []

    retrieval_eval.probe(
        repo_root=ROOT, search=fake_search, iter_corpus=lambda *_a: docs,
        fetch_hashes=lambda: {}, push_url="http://127.0.0.1:9", pairs=pairs)
    assert len(resolved) == 1
    assert seen == ["test-secret"] * 3
    assert "test-secret" not in push_lines[0]
    captured = capsys.readouterr()
    assert "test-secret" not in captured.out + captured.err


def test_hermes_probe_is_skipped_until_more_than_24_hours(monkeypatch):
    spec = importlib.util.spec_from_loader("k3dm_hermes_test", SourceFileLoader("k3dm_hermes_test", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    calls = []
    monkeypatch.setattr(retrieval_eval, "probe", lambda *_a, **_k: calls.append(1))
    state = {"retrieval_probe_last_attempt": 100}
    module._maybe_probe_retrieval(state, "ref", 100 + 86400)
    assert calls == []
    module._maybe_probe_retrieval(state, "ref", 100 + 86401)
    assert calls == [1]
    assert state["retrieval_probe_last_attempt"] == 100 + 86401


def test_hermes_probe_failure_is_advisory_and_does_not_escape(monkeypatch, capsys):
    spec = importlib.util.spec_from_loader("k3dm_hermes_test_failure", SourceFileLoader("k3dm_hermes_test_failure", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(retrieval_eval, "probe", lambda *_a, **_k:
                        (_ for _ in ()).throw(prior_art.RetrievalUnavailable("offline\nnoise")))
    state = {"retrieval_probe_last_attempt": 0}
    assert module._maybe_probe_retrieval(state, "ref", 86401) is None
    assert state["retrieval_probe_last_attempt"] == 86401
    assert capsys.readouterr().err.splitlines() == ["vectordb retrieval probe skipped: offline noise"]


def test_hermes_completed_cycle_marker_is_private_and_atomic(monkeypatch, tmp_path):
    spec = importlib.util.spec_from_loader(
        "k3dm_hermes_marker_test", SourceFileLoader("k3dm_hermes_marker_test", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    marker = tmp_path / "state" / "heartbeat.timestamp"
    monkeypatch.setenv("K3DM_HERMES_HEARTBEAT_MARKER", str(marker))
    module._write_heartbeat_marker(1234.5)
    assert marker.read_text() == "1234.500\n"
    assert marker.stat().st_mode & 0o777 == 0o600
    assert list(marker.parent.iterdir()) == [marker]


def test_hermes_marker_write_failure_is_advisory(monkeypatch, capsys, tmp_path):
    spec = importlib.util.spec_from_loader(
        "k3dm_hermes_marker_failure_test", SourceFileLoader(
            "k3dm_hermes_marker_failure_test", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    parent = tmp_path / "not-a-directory"
    parent.write_text("fixture")
    monkeypatch.setenv("K3DM_HERMES_HEARTBEAT_MARKER", str(parent / "heartbeat.timestamp"))
    assert module._write_heartbeat_marker(1234.5) is None
    assert "non-fatal" in capsys.readouterr().err


@pytest.mark.parametrize("changed", [False, True])
def test_probe_failure_preserves_index_refresh_result(monkeypatch, capsys, changed):
    import subprocess

    spec = importlib.util.spec_from_loader(
        "hermes_probe_refresh", SourceFileLoader("hermes_probe_refresh", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    published = []
    monkeypatch.setattr(module, "_index_ref", lambda: ("origin/test", "test"))
    monkeypatch.setattr(module, "corpus_fingerprint", lambda *_: "same")
    monkeypatch.setattr(module, "_push_index_metrics", lambda metrics: published.append(dict(metrics)))

    def run(argv, **_kwargs):
        if "--json" in argv:
            return subprocess.CompletedProcess(argv, 0, '{"available":true,"rows":2,"corpus_docs":2}', "")
        return subprocess.CompletedProcess(argv, 0, "1 embedded, 0 remaining", "")

    monkeypatch.setattr(module.subprocess, "run", run)
    calls = []

    def unavailable(*_args, **kwargs):
        calls.append(kwargs["ref"])
        raise prior_art.RetrievalUnavailable("offline")

    monkeypatch.setattr(retrieval_eval, "probe", unavailable)
    state = {"index_fingerprint": "old" if changed else "same"}
    assert module._refresh_index(state, now=100000) is None
    assert published[-1]["result"] == ("success" if changed else "noop")
    assert calls == ["origin/test"]
    assert state["index_fingerprint"] == "same"
    assert state["retrieval_probe_last_attempt"] == 100000
    assert "vectordb retrieval probe skipped: offline" in capsys.readouterr().err
    module._refresh_index(state, now=100001)
    assert calls == ["origin/test"]


@pytest.mark.parametrize(("platform", "override", "expected"), [
    ("darwin", None, "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes"),
    ("darwin", "ssh -F /tmp/custom-ssh-config", "ssh -F /tmp/custom-ssh-config"),
    ("linux", None, None),
])
def test_index_fetch_uses_macos_keychain_without_overriding_caller(
        monkeypatch, capsys, platform, override, expected):
    import subprocess

    spec = importlib.util.spec_from_loader(
        "hermes_fetch_ssh", SourceFileLoader("hermes_fetch_ssh", str(ROOT / "bin/k3dm-hermes")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "_index_ref", lambda: ("origin/test", "test"))
    monkeypatch.setattr(module, "_push_index_metrics", lambda _metrics: None)
    monkeypatch.setattr(module.sys, "platform", platform)
    monkeypatch.delenv("SSH_AUTH_SOCK", raising=False)
    if override is None:
        monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
    else:
        monkeypatch.setenv("GIT_SSH_COMMAND", override)
    captured = {}

    def run(argv, **kwargs):
        captured.update(kwargs)
        return subprocess.CompletedProcess(argv, 128, "", "Permission denied (publickey).")

    monkeypatch.setattr(module.subprocess, "run", run)
    assert module._refresh_index({}) is None
    assert captured["env"].get("GIT_SSH_COMMAND") == expected
    assert "SSH_AUTH_SOCK" not in captured["env"]
    assert capsys.readouterr().err.splitlines() == [
        "vectordb index refresh skipped: git fetch failed: Permission denied (publickey)."]
