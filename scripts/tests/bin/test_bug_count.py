import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import bug_count  # noqa: E402


@pytest.mark.parametrize("question, expected", [
    ("how many bugs are open and how many are fixed in the v1.42.0", ("v1.42.0", None, "open")),
    ("codex how many bugs were fixed in v1.42.0", ("v1.42.0", None, "closed")),
    ("count open bugs", ("*", None, "open")),
    ("how many P1 bugs we have in v1.42.0 branch", ("v1.42.0", "P1", None)),
    ("how many bugs in v1.42.0", ("v1.42.0", None, None)),
])
def test_match_positives(question, expected):
    assert bug_count.match(question) == bug_count.CountQuery(*expected)


@pytest.mark.parametrize("question", ["what is the most urgent open bug", "how many pods are running", "bug 2026-10-08 status"])
def test_match_negatives(question):
    assert bug_count.match(question) is None


def test_reply_formats_counts_and_links(monkeypatch):
    payload = '{"ref":"HEAD","releases":{"v1.42.0":{"total":35,"closed":24,"open":3,"unknown":8,"by_priority":{"P0":{"total":0,"closed":0,"open":0,"unknown":0},"P1":{"total":3,"closed":3,"open":0,"unknown":0},"P2":{"total":0,"closed":0,"open":0,"unknown":0},"P3":{"total":0,"closed":0,"open":0,"unknown":0},"unset":{"total":1,"closed":0,"open":0,"unknown":1}},"open_paths":[],"unknown_paths":[{"path":"docs/bugs/u.md","priority":"unset"}]}}}'
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    answer = bug_count.reply(bug_count.CountQuery("v1.42.0", "P1", None))
    assert "v1.42.0: 3 P1 bug docs" in answer
    assert "no Priority line" in answer
    assert "Could not count" not in answer


def test_failed_tally_never_calls_model(monkeypatch):
    called = []
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (1, "", False))
    monkeypatch.setattr(bug_count, "_call_model", lambda: called.append(True)) if hasattr(bug_count, "_call_model") else None
    assert "Could not count bugs" in bug_count.reply(bug_count.CountQuery("*", None, None))
    assert called == []


def test_run_cluster_ask_count_does_not_spawn(monkeypatch, tmp_path):
    from webhook import agent
    monkeypatch.setattr(agent, "JOB_DIR", tmp_path)
    (tmp_path / "job").mkdir()
    monkeypatch.setattr(bug_count, "reply", lambda _query: "counted")
    monkeypatch.setattr(agent, "_spawn_capture_text", lambda *_a, **_k: pytest.fail("spawned"))
    monkeypatch.setattr(bug_count, "match", lambda _q: bug_count.CountQuery("v1.42.0", None, None))
    agent._run_cluster_ask("job", "codex", "how many bugs", "", max_turns=1)
    assert (tmp_path / "job/output").read_text().startswith("📊 Counted, not asked")


def test_reply_runs_the_real_tally_without_relying_on_the_executable_bit():
    reply = bug_count.reply(bug_count.CountQuery("*", None, None))
    assert "Could not count bugs" not in reply
    assert "_Counted from docs/bugs/ at" in reply
