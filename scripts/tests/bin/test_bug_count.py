import sys
import os
import shutil
import subprocess
from pathlib import Path

import pytest

# agent-audit: allow assert-removed restore deterministic count assertions after the operator-authorized rollback

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import ask_docs, bug_count  # noqa: E402


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


@pytest.mark.parametrize("question", [
    "how many P1 open for v1.43.5",
    "How many p1 OPEN for V1.43.5?",
    "How many are currently P1 open for v1.43.5?",
    "count the open P1 bugs in this release",
    "number of P1 open for last two releases",
])
def test_match_priority_state_count_with_or_without_bug_noun(question):
    expected_release = "last:1" if "this release" in question else (
        "last:2" if "last two releases" in question else "v1.43.5")
    assert bug_count.match(question) == bug_count.CountQuery(expected_release, "P1", "open")


@pytest.mark.parametrize("question", [
    "how many P1 open pods for v1.43.5",
    "count P1 open pull requests for v1.43.5",
    "how many P1 open release plans for v1.43.5",
    "how many P1 open tickets for v1.43.5",
    "how many P1 open incidents for v1.43.5",
    "how many P1 open deployments for v1.43.5",
    "how many P1 open vulnerabilities for v1.43.5",
    "how many P1 open widgets for v1.43.5",
    "how many P1 open alerts for v1.43.5",
    "how many P4 open for v1.43.5",
    "how many P10 open for v1.43.5",
    "how many P1 opened for v1.43.5",
    "how many P1 openish for v1.43.5",
    "how many P1 for v1.43.5",
])
def test_match_does_not_hijack_other_counts_or_invalid_context(question):
    assert bug_count.match(question) is None


@pytest.mark.parametrize("question", [
    "how many P1 open pods for v1.43.5",
    "count P1 open pull requests for v1.43.5",
    "how many P1 open issues for v1.43.5",
    "how many P1 open release plans for v1.43.5",
    "count P1 open alerts for v1.43.5",
    "how many P1 open tickets for v1.43.5",
])
def test_priority_state_with_other_object_falls_through(question):
    assert bug_count.match(question) is None


@pytest.mark.parametrize("question", [
    "how many P1 open",
    "how many p1 OPEN for V1.43.5?",
    "how many P1 open for v1.43.5x",
    "how many P4 open for v1.43.5",
    "how many P10 open for v1.43.5",
    "how many P1 opened for v1.43.5",
])
def test_priority_state_bounded_match_requires_valid_context(question):
    expected = bug_count.CountQuery("v1.43.5", "P1", "open") if question == "how many p1 OPEN for V1.43.5?" else None
    assert bug_count.match(question) == expected


def test_explicit_bug_wording_keeps_priority_result():
    assert bug_count.match("how many P1 bugs open for v1.43.5") == bug_count.CountQuery(
        "v1.43.5", "P1", "open")


def test_explicit_bug_wording_allows_other_words():
    assert bug_count.match("how many P1 open bugs affecting deployments for v1.43.5") == bug_count.CountQuery(
        "v1.43.5", "P1", "open")


def test_reply_formats_counts_and_links(monkeypatch):
    payload = '{"ref":"HEAD","releases":{"v1.42.0":{"total":35,"closed":24,"open":3,"unknown":8,"by_priority":{"P0":{"total":0,"closed":0,"open":0,"unknown":0},"P1":{"total":3,"closed":3,"open":0,"unknown":0},"P2":{"total":0,"closed":0,"open":0,"unknown":0},"P3":{"total":0,"closed":0,"open":0,"unknown":0},"unset":{"total":1,"closed":0,"open":0,"unknown":1}},"open_paths":[],"unknown_paths":[{"path":"docs/bugs/u.md","priority":"unset"}]}}}'
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    answer = bug_count.reply(bug_count.CountQuery("v1.42.0", "P1", None))
    assert "v1.42.0: 3 P1 bug docs" in answer
    assert "no Priority line" in answer
    assert "Could not count" not in answer


def test_state_reply_uses_original_count_format(monkeypatch):
    payload = '{"ref":"HEAD","releases":{"v1.43.5":{"total":81,"closed":75,"open":6,"unknown":0,"by_priority":{},"open_paths":[],"unknown_paths":[]}}}'
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    answer = bug_count.reply(bug_count.CountQuery("v1.43.5", None, "closed"))
    assert "v1.43.5: 75 closed bug docs — 75 fixed, 6 open" in answer  # agent-audit: allow assert-removed operator-requested rollback restores prior count format


def _tally_and_rev_parse(payload, sha_rc, sha):
    def spawn(cmd, **_kwargs):
        if cmd[:2] == ["git", "rev-parse"]:
            return sha_rc, sha, False
        return 0, payload, False
    return spawn


def test_footer_uses_original_ref_without_commit(monkeypatch):
    monkeypatch.setenv("K3DM_INDEX_REF", "HEAD")
    payload = '{"ref":"HEAD","releases":{"v1.43.5":{"total":81,"closed":75,"open":6,"unknown":0,"by_priority":{},"open_paths":[],"unknown_paths":[]}}}'
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text",
                        _tally_and_rev_parse(payload, 0, "5a31cf25" + "0" * 32 + "\n"))
    answer = bug_count.reply(bug_count.CountQuery("v1.43.5", None, None))
    assert "_Counted from docs/bugs/ at HEAD;" in answer  # agent-audit: allow assert-removed operator-requested rollback restores prior footer


def test_footer_omits_the_commit_when_rev_parse_fails(monkeypatch):
    payload = '{"ref":"HEAD","releases":{"v1.43.5":{"total":81,"closed":75,"open":6,"unknown":0,"by_priority":{},"open_paths":[],"unknown_paths":[]}}}'
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", _tally_and_rev_parse(payload, 128, "fatal: bad ref"))
    answer = bug_count.reply(bug_count.CountQuery("v1.43.5", None, None))
    assert "_Counted from docs/bugs/ at HEAD;" in answer
    assert "fatal" not in answer


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


def _closed_payload(count, priority="P1"):
    closed = ",".join(f'{{"path":"docs/bugs/f{i}.md","priority":"{priority}"}}' for i in range(count))
    other = '{"path":"docs/bugs/other.md","priority":"P2"}'
    return ('{"ref":"HEAD","releases":{"v1.43.5":{"total":%d,"closed":%d,"open":0,"unknown":0,'
            '"by_priority":{"P1":{"total":%d,"closed":%d,"open":0,"unknown":0}},'
            '"open_paths":[],"unknown_paths":[],"closed_paths":[%s,%s]}}}'
            % (count + 1, count + 1, count, count, closed, other))


def test_reply_links_fixed_docs_for_a_release(monkeypatch):
    monkeypatch.setenv("K3DM_INDEX_REF", "HEAD")
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, _closed_payload(2), False))
    answer = bug_count.reply(bug_count.CountQuery("v1.43.5", "P1", None))
    assert "Fixed: <https://github.com/" in answer
    assert "|docs/bugs/f0.md>" in answer
    assert "|docs/bugs/f1.md>" in answer
    assert "other.md" not in answer


def test_reply_caps_fixed_links_at_ten(monkeypatch):
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, _closed_payload(13), False))
    answer = bug_count.reply(bug_count.CountQuery("v1.43.5", "P1", None))
    assert answer.count("Fixed: ") == 10
    assert "and 3 more fixed" in answer


@pytest.mark.parametrize("query", [
    bug_count.CountQuery("v1.43.5", "P1", "open"),
    bug_count.CountQuery("*", "P1", None),
])
def test_reply_omits_fixed_links_for_open_or_all_release_questions(monkeypatch, query):
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, _closed_payload(2), False))
    assert "Fixed: " not in bug_count.reply(query)


def test_named_release_budget_reports_exact_omissions(monkeypatch):
    data = _release(87)
    data.update(open=6, closed=81, open_paths=[
        {"path": f"docs/bugs/2026-10-31-open-example-long-description-{i}.md"} for i in range(6)],
        closed_paths=[{"path": f"docs/bugs/2026-10-31-fixed-example-long-description-{i}.md"}
                      for i in range(81)])
    _reply_with(monkeypatch, {"v1.43.5": data}, bug_count.CountQuery("v1.43.5", None, None))
    answer = ask_docs.answer("how many bugs in v1.43.5")
    assert "87 bug docs — 81 fixed, 6 open" in answer
    assert answer.count("Open: ") == 6
    assert f"…and {81 - answer.count('Fixed: ')} more fixed." in answer
    assert answer.index("Open: ") < answer.index("Fixed: ")
    assert "name a release to see the full list" not in answer
    assert len(answer) <= ask_docs.MAX_REPLY_CHARS
    assert answer.count("<") == answer.count(">")


def test_open_links_are_dropped_last_and_counted(monkeypatch):
    data = _release(30)
    data.update(open=20, closed=10, open_paths=[
        {"path": f"docs/bugs/{'open-long-description-' * 5}{i}.md"} for i in range(20)],
        closed_paths=[{"path": f"docs/bugs/fixed-{i}.md"} for i in range(10)])
    answer = _reply_with(monkeypatch, {"v1.43.5": data}, bug_count.CountQuery("v1.43.5", None, None))
    assert "Fixed: " not in answer
    assert f"…and {20 - answer.count('Open: ')} more open." in answer
    assert "…and 10 more fixed." in answer  # agent-audit: allow assert-removed same assertion, f prefix dropped (ruff F541)
    assert len(answer) + len("\n\nSources: none") <= ask_docs.MAX_REPLY_CHARS
    assert answer.count("<") == answer.count(">")


def test_fetched_upstream_and_local_fallback(monkeypatch, tmp_path):
    git = shutil.which("git")
    upstream, clone = tmp_path / "upstream", tmp_path / "clone"

    def run(*args, cwd=None):
        return subprocess.run([git, *map(str, args)], cwd=cwd, check=True,
                              capture_output=True, text=True).stdout.strip()

    run("init", "-b", "k3d-manager-v1.43.13", upstream)
    run("config", "user.email", "test@example.com", cwd=upstream)
    run("config", "user.name", "Test", cwd=upstream)
    def import_commit(message, files, parent=None):
        data = f"commit refs/heads/k3d-manager-v1.43.13\ncommitter Test <test@example.com> 1 +0000\ndata {len(message)}\n{message}\n"
        if parent:
            data += f"from {parent}\n"
        for name, content in files.items():
            data += f"M 100644 inline {name}\ndata {len(content)}\n{content}\n"
        subprocess.run([git, "fast-import", "--quiet"], cwd=upstream, input=data,
                       text=True, check=True, capture_output=True)

    initial_bug = "**Status:** OPEN\n**Priority:** P3\n**Branch:** k3d-manager-v1.43.13\n"
    import_commit("initial", {"docs/bugs/initial.md": initial_bug})
    run("clone", upstream, clone)
    content = "**Status:** OPEN\n**Priority:** P2\n**Branch:** k3d-manager-v1.43.13\n"
    import_commit("add bugs", {f"docs/bugs/{name}.md": content for name in ("one", "two")},
                  run("rev-parse", "HEAD", cwd=upstream))
    run("fetch", "origin", cwd=clone)

    scripts = clone / "scripts"
    (scripts / "lib" / "webhook").mkdir(parents=True)
    shutil.copy(ROOT / "scripts" / "bug-tally.py", scripts)
    shutil.copytree(ROOT / "scripts" / "lib" / "hermes", scripts / "lib" / "hermes")
    monkeypatch.setattr(bug_count, "__file__", str(scripts / "lib" / "webhook" / "bug_count.py"))
    assert Path(bug_count.__file__).resolve().parents[3] == clone
    assert clone != ROOT

    log = tmp_path / "git.log"
    wrapper = tmp_path / "bin"
    wrapper.mkdir()
    (wrapper / "git").write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{log}"\nexec "{git}" "$@"\n')
    (wrapper / "git").chmod(0o755)
    monkeypatch.setenv("PATH", f"{wrapper}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.delenv("K3DM_INDEX_REF", raising=False)
    head = run("rev-parse", "HEAD", cwd=clone)
    reflog = run("reflog", "--format=%H %gs", cwd=clone)
    query = bug_count.CountQuery("v1.43.13", "P2", None)
    answer = bug_count.reply(query)
    assert "v1.43.13: 2 P2 bug docs" in answer
    assert "Counted at local HEAD (no upstream)." not in answer
    assert "origin/k3d-manager-v1.43.13" in answer
    monkeypatch.setenv("K3DM_INDEX_REF", "HEAD")
    assert "0 P2 bug docs" in bug_count.reply(query)
    monkeypatch.delenv("K3DM_INDEX_REF")
    run("branch", "--unset-upstream", cwd=clone)
    answer = bug_count.reply(query)
    assert "Counted at local HEAD (no upstream)." in answer
    assert "0 P2 bug docs" in answer
    assert run("rev-parse", "HEAD", cwd=clone) == head
    assert run("reflog", "--format=%H %gs", cwd=clone) == reflog
    assert not any(line.split()[0] in {"fetch", "pull", "merge", "reset", "checkout"}
                   for line in log.read_text().splitlines())


@pytest.mark.parametrize("result", [(1, "error", False), (0, "", True), (0, "", False)])
def test_upstream_resolution_failure_falls_back(monkeypatch, result):
    monkeypatch.delenv("K3DM_INDEX_REF", raising=False)
    payload = '{"releases":{"v1.43.13":{"total":0}}}'
    def spawn(cmd, **kwargs):
        return result if cmd[0] == "git" else (0, payload, False)
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", spawn)
    answer = bug_count.reply(bug_count.CountQuery("v1.43.13", None, None))
    assert "Counted at local HEAD (no upstream)." in answer
    assert "at HEAD;" in answer
