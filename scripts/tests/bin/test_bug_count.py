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
    ("how many P1 bugs from last two releases", ("last:2", "P1", None)),
    ("count open bugs in the past 3 releases", ("last:3", None, "open")),
    ("how many bugs in this release", ("last:1", None, None)),
    ("how many bugs in v1.40.0, not the last two releases", ("v1.40.0", None, None)),
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


def _release(total, p1=0, unset=0):
    empty = {"total": 0, "closed": 0, "open": 0, "unknown": 0}
    by_priority = {name: dict(empty) for name in ("P0", "P1", "P2", "P3", "unset")}
    by_priority["P1"] = {"total": p1, "closed": p1, "open": 0, "unknown": 0}
    by_priority["unset"] = {"total": unset, "closed": unset, "open": 0, "unknown": 0}
    return {"total": total, "closed": total, "open": 0, "unknown": 0, "by_priority": by_priority,
            "open_paths": [], "unknown_paths": []}


def _reply_with(monkeypatch, releases, query, ref="origin/k3d-manager-v1.43.0"):
    import json
    payload = json.dumps({"ref": ref, "releases": releases})
    monkeypatch.setenv("K3DM_INDEX_REF", ref)
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    return bug_count.reply(query)


def test_last_n_releases_counts_back_from_the_current_release(monkeypatch):
    releases = {"v1.44.0": _release(1, p1=1), "v1.41.0": _release(9, p1=5),
                "v1.43.0": _release(3, p1=1, unset=1), "v1.42.0": _release(4, p1=2, unset=2)}
    answer = _reply_with(monkeypatch, releases, bug_count.CountQuery("last:2", "P1", None))
    lines = answer.splitlines()
    assert lines[0].startswith("Last 2 release(s) (current release v1.43.0")
    assert lines[1].startswith("v1.43.0: 1 P1 bug docs")
    assert lines[2].startswith("v1.42.0: 2 P1 bug docs")
    assert "v1.44.0:" not in answer and "v1.41.0:" not in answer
    assert answer.count("no Priority line") == 1
    assert "3 docs in these releases have no Priority line" in answer


def test_all_releases_sorted_by_version_and_capped(monkeypatch):
    releases = {f"v1.{minor}.0": _release(1) for minor in range(1, 14)}
    releases["v1.4.7"] = _release(1)
    releases["v1.4.6"] = _release(1)
    answer = _reply_with(monkeypatch, releases, bug_count.CountQuery("*", None, None))
    shown = [line.split(":")[0] for line in answer.splitlines() if line.startswith("v1.")]
    assert shown == [f"v1.{minor}.0" for minor in range(13, 4, -1)] + ["v1.4.7"]
    assert "All releases: 15 bug docs." in answer
    assert "5 older ones omitted" in answer


def test_all_releases_with_priority_skips_releases_without_a_match(monkeypatch):
    releases = {"v1.42.0": _release(4, p1=2, unset=1), "v1.41.0": _release(9, unset=3)}
    answer = _reply_with(monkeypatch, releases, bug_count.CountQuery("*", "P1", None))
    assert "v1.41.0:" not in answer
    assert "4 docs in these releases have no Priority line" in answer
