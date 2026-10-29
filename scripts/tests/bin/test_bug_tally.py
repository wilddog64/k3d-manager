import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
import sys
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import doc_meta, doc_status  # noqa: E402
from webhook import bug_count  # noqa: E402


@pytest.fixture
def tally_module(tmp_path):
    spec = importlib.util.spec_from_file_location("bug_tally", ROOT / "scripts/bug-tally.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.ROOT = tmp_path
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=tmp_path, check=True)
    return module


def _commit(root, message):
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", message], cwd=root, check=True)


def test_tally_releases_sources_and_excludes_archive(tally_module, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("# fixed\n\n**Branch:** k3d-manager-v1.0.0\n**Status:** FIXED\n**Priority:** P1\n")
    (bugs / "unknown.md").write_text("# unknown\n\n**Priority:** P2\n")
    (bugs / "archive").mkdir()
    (bugs / "archive/ignored.md").write_text("# ignored\n\n**Status:** Open\n")
    _commit(tmp_path, "first")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tmp_path, check=True)
    (bugs / "open.md").write_text("# open\n\n**Status:** Open\n")
    _commit(tmp_path, "second")
    subprocess.run(["git", "switch", "-q", "-c", "k3d-manager-v1.1.0"], cwd=tmp_path, check=True)
    result = tally_module.tally("HEAD")
    assert result["v1.0.0"]["total"] == 2
    assert result["v1.0.0"]["closed"] == 1
    assert result["v1.0.0"]["unknown"] == 1
    assert result["v1.0.0"]["closed_paths"] == [{"path": "docs/bugs/fixed.md", "priority": "P1"}]
    assert result["v1.1.0"]["open"] == 1
    assert result["v1.1.0"]["by_source"]["added_branch"] == 1
    assert all("archive" not in item["path"] for item in result["v1.0.0"]["unknown_paths"])


def test_tally_reads_docs_without_git_show(tally_module, tmp_path, monkeypatch):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "open.md").write_text("# open\n\n**Status:** Open\n")
    _commit(tmp_path, "seed")
    original_git = tally_module._git
    calls = []

    def tracked_git(*args):
        calls.append(args)
        return original_git(*args)

    monkeypatch.setattr(tally_module, "_git", tracked_git)
    assert tally_module.tally("HEAD")["unknown"]["total"] == 1
    assert not any(args and args[0] == "show" for args in calls)


def test_tally_unknown_status_and_all_priority_buckets(tally_module, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "unknown.md").write_text("# unknown\n\nno Status line\n")
    _commit(tmp_path, "seed")
    data = tally_module.tally("HEAD")["unknown"]
    assert data["unknown"] == 1 and data["open"] == 0
    assert set(data["by_priority"]) == {"P0", "P1", "P2", "P3", "unset"}
    assert data["by_priority"]["unset"]["unknown"] == 1


def test_implemented_is_closed_and_deferred_is_labeled_in_tally_and_reply(tally_module, tmp_path, monkeypatch):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "implemented.md").write_text("**Priority:** P1\n**Status:** IMPLEMENTED — landed\n")
    (bugs / "deferred.md").write_text("**Priority:** P1\n**Status:** DEFERRED — later\n")
    (bugs / "open.md").write_text("**Priority:** P1\n**Status:** OPEN\n")
    _commit(tmp_path, "seed")

    release = tally_module.tally("HEAD")["unknown"]
    assert (release["closed"], release["open"]) == (1, 2)
    assert {item["path"] for item in release["open_paths"]} == {
        "docs/bugs/deferred.md", "docs/bugs/open.md"}
    assert next(item for item in release["open_paths"] if item["path"].endswith("deferred.md"))["status"] == "deferred"
    assert doc_meta("**Status:** IMPLEMENTED\n")[1] == "closed"
    assert doc_status("**Status:** DEFERRED\n")[1] == "deferred"
    assert doc_status("**Status:** OPEN\n")[1] == "open"
    assert doc_status("no status\n")[1] == "unknown"

    payload = json.dumps({"ref": "HEAD", "releases": {"unknown": release}})
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    answer = bug_count.reply(bug_count.CountQuery("unknown", None, None))
    assert "2 open (1 deferred)" in answer
    assert "Deferred: " in answer and "Open: " in answer


def test_bug_count_omits_zero_deferred_count(monkeypatch):
    release = {
        "by_priority": {}, "total": 1, "closed": 0, "open": 1, "unknown": 0,
        "open_paths": [{"path": "docs/bugs/open.md", "status": "open"}],
        "unknown_paths": [],
    }
    payload = json.dumps({"ref": "HEAD", "releases": {"unknown": release}})
    monkeypatch.setattr(bug_count.proc, "_spawn_capture_text", lambda *_a, **_k: (0, payload, False))
    answer = bug_count.reply(bug_count.CountQuery("unknown", None, None))
    assert "1 open," in answer
    assert "deferred" not in answer


def test_tally_read_failure_returns_exit_two_and_no_stdout(tally_module, monkeypatch, capsys):
    monkeypatch.setattr(tally_module, "tally", lambda _ref: (_ for _ in ()).throw(OSError("unreadable")))
    assert tally_module.main(["--json", "--ref", "HEAD"]) == 2
    assert capsys.readouterr().out == ""


@pytest.mark.parametrize("ref", ["k3d-manager-v1.1.0", "origin/k3d-manager-v1.1.0"])
def test_tally_a_named_ref_uses_its_branch_name(tally_module, tmp_path, ref):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "open.md").write_text("# open\n\n**Status:** Open\n")
    _commit(tmp_path, "seed")
    subprocess.run(["git", "switch", "-q", "-c", "k3d-manager-v1.1.0"], cwd=tmp_path, check=True)
    subprocess.run(["git", "update-ref", "refs/remotes/origin/k3d-manager-v1.1.0", "HEAD"], cwd=tmp_path, check=True)
    subprocess.run(["git", "switch", "-q", "main"], cwd=tmp_path, check=True)
    result = tally_module.tally(ref)
    assert result["v1.1.0"]["open"] == 1
    assert result["v1.1.0"]["by_source"]["added_branch"] == 1
    assert tally_module._scan(ref, include_fixed=False)[0] == result


def _dated_commit(root, message, date):
    subprocess.run(["git", "add", "docs/bugs"], cwd=root, check=True)
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(["git", "commit", "-qm", message], cwd=root, check=True, env=env)
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()


def test_fixed_in_tracks_latest_fix_by_tag_ancestry_and_branch(tally_module, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)

    def write(name, status, branch=None):
        text = f"# {name}\n\n**Priority:** P1\n"
        if branch:
            text += f"**Branch:** {branch}\n"
        text += f"**Status:** {status}\n"
        (bugs / f"{name}.md").write_text(text)

    write("a", "OPEN")
    write("d", "IMPLEMENTED")
    write("f", "FIXED")
    _dated_commit(tmp_path, "v1.0 docs", "2026-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tmp_path, check=True)
    write("a", "IMPLEMENTED")
    write("d", "OPEN — reopened")
    write("f", "OPEN — reopened")
    a_commit = _dated_commit(tmp_path, "v1.1 fixes", "2025-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.1.0"], cwd=tmp_path, check=True)
    write("a", "VERIFIED")
    write("f", "FIXED")
    f_commit = _dated_commit(tmp_path, "v1.2 fixes", "2024-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.2.0"], cwd=tmp_path, check=True)
    subprocess.run(["git", "switch", "-q", "-c", "k3d-manager-v1.3.0"], cwd=tmp_path, check=True)
    write("b", "FIXED")
    write("c", "OPEN")
    write("e", "OPEN", "k3d-manager-v1.2.0")
    (bugs / "e.md").write_text("# e\n\n**Priority:** P1\n## Status\nOPEN\n")
    branch_docs_commit = _dated_commit(tmp_path, "branch docs", "2023-01-01T00:00:00Z")
    write("c", "LIVE-VERIFIED")
    (bugs / "e.md").write_text("# e\n\n**Priority:** P1\n**Branch:** k3d-manager-v1.2.0\n## Status\nFIXED\n")
    branch_fix_commit = _dated_commit(tmp_path, "branch fix", "2022-01-01T00:00:00Z")

    fixed = tally_module.fixed_in("HEAD")
    assert fixed == {
        "docs/bugs/a.md": {"release": "v1.1.0", "source": "status_change", "commit": a_commit},
        "docs/bugs/b.md": {"release": "v1.3.0", "source": "added_fixed", "commit": branch_docs_commit},
        "docs/bugs/c.md": {"release": "v1.3.0", "source": "status_change", "commit": branch_fix_commit},
        "docs/bugs/e.md": {"release": "unknown", "source": "no_transition", "commit": None},
        "docs/bugs/f.md": {"release": "v1.2.0", "source": "status_change", "commit": f_commit},
    }
    before = tally_module.tally("k3d-manager-v1.3.0")
    assert tally_module._scan("k3d-manager-v1.3.0", include_fixed=False)[0] == before
    subprocess.run(["git", "switch", "-q", "-c", "scratch"], cwd=tmp_path, check=True)
    assert tally_module.fixed_in("HEAD")["docs/bugs/b.md"]["release"] == "unknown"
    assert tally_module.fixed_in("HEAD")["docs/bugs/c.md"]["release"] == "unknown"
    assert tally_module.tally("k3d-manager-v1.3.0") == before
    assert tally_module._scan("HEAD", include_fixed=False)[0] == tally_module.tally("HEAD")


def test_json_main_includes_fixed_in_without_changing_releases(tally_module, capsys):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    _dated_commit(tally_module.ROOT, "fixed", "2026-01-01T00:00:00Z")
    expected = tally_module.tally("HEAD")
    assert tally_module.main(["--json", "--ref", "HEAD"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert list(payload) == ["ref", "generated_at", "releases", "fixed_in", "repo"]
    assert payload["releases"] == expected
    assert payload["fixed_in"]["docs/bugs/fixed.md"]["source"] == "added_fixed"


def test_counts_only_matches_full_tally_and_skips_fixed_history(tally_module, monkeypatch, capsys):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "open.md").write_text("**Priority:** P1\n**Status:** OPEN\n")
    (bugs / "unknown.md").write_text("**Priority:** P2\n")
    _dated_commit(tally_module.ROOT, "seed", "2026-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tally_module.ROOT, check=True)
    (bugs / "open.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    _dated_commit(tally_module.ROOT, "fixed status transition", "2026-02-01T00:00:00Z")

    full = tally_module._scan("HEAD")
    monkeypatch.setattr(tally_module, "_fixed_commits", lambda _ref: pytest.fail("scanned fixed history"))
    count_only = tally_module._scan("HEAD", include_fixed=False)
    assert count_only == (full[0], None)

    assert tally_module.main(["--json", "--counts-only", "--ref", "HEAD"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["releases"] == full[0]
    assert "fixed_in" not in payload


def test_counts_only_avoids_attributing_history_for_explicit_branch_docs(tally_module, monkeypatch):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "branch.md").write_text("**Branch:** k3d-manager-v1.0.0\n**Status:** OPEN\n")
    branch_commit = _dated_commit(tally_module.ROOT, "branch metadata", "2026-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tally_module.ROOT, check=True)
    (bugs / "fallback.md").write_text("**Priority:** P1\n**Status:** OPEN\n")
    fallback_commit = _dated_commit(tally_module.ROOT, "fallback", "2026-02-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.1.0"], cwd=tally_module.ROOT, check=True)
    expected = tally_module._scan("HEAD")[0]
    calls = []
    original = tally_module._git

    def tracked(*args):
        calls.append(args)
        return original(*args)

    monkeypatch.setattr(tally_module, "_git", tracked)
    assert tally_module._scan("HEAD", include_fixed=False)[0] == expected
    contains = [args[2] for args in calls if args[:2] == ("tag", "--contains")]
    assert contains == [fallback_commit]
    assert branch_commit not in contains


def test_counts_only_needs_no_added_history_when_all_releases_are_explicit(tally_module, monkeypatch):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "branch.md").write_text("**Branch:** k3d-manager-v1.0.0\n**Status:** OPEN\n")
    _dated_commit(tally_module.ROOT, "branch metadata", "2026-01-01T00:00:00Z")
    expected = tally_module._scan("HEAD")[0]
    original = tally_module._git

    def tracked(*args):
        assert not args or args[0] != "log"
        return original(*args)

    monkeypatch.setattr(tally_module, "_git", tracked)
    assert tally_module._scan("HEAD", include_fixed=False)[0] == expected


def test_json_main_default_still_includes_fixed_in(tally_module, capsys):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    _dated_commit(tally_module.ROOT, "fixed", "2026-01-01T00:00:00Z")
    assert tally_module.main(["--json", "--ref", "HEAD"]) == 0
    assert "fixed_in" in json.loads(capsys.readouterr().out)


def test_counts_only_requires_json(tally_module, capsys):
    with pytest.raises(SystemExit) as exc:
        tally_module.main(["--counts-only"])
    assert exc.value.code == 2
    assert "--counts-only requires --json" in capsys.readouterr().err


def test_lib_foundation_uses_tag_ancestry_and_reports_repo(tally_module, capsys):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "tagged.md").write_text(
        "# tagged\n\n**Branch:** k3d-manager-v1.40.0\n**Status:** OPEN\n")
    _commit(tally_module.ROOT, "tagged bug")
    subprocess.run(["git", "tag", "v0.1.0"], cwd=tally_module.ROOT, check=True)
    (bugs / "untagged.md").write_text("# untagged\n\n**Status:** OPEN\n")
    _commit(tally_module.ROOT, "untagged bug")
    assert tally_module.main(["--json", "--ref", "HEAD", "--repo-dir", str(tally_module.ROOT),
                              "--repo-name", "lib-foundation"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["repo"] == "lib-foundation"
    assert payload["releases"]["v0.1.0"]["open"] == 1
    assert payload["releases"]["unknown"]["open"] == 1
    assert "v1.40.0" not in payload["releases"]
    assert tally_module._scan("HEAD", include_fixed=False)[0] == payload["releases"]


def test_fixed_in_status_backfilled_onto_an_existing_doc_is_unknown(tally_module, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "old.md").write_text("# old\n\nno status line yet\n")
    (bugs / "new.md").write_text("# new\n\n**Status:** OPEN\n")
    _dated_commit(tmp_path, "docs without status", "2026-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tmp_path, check=True)
    (bugs / "old.md").write_text("# old\n\n**Status:** CLOSED — status sweep\n\nno status line yet\n")
    (bugs / "new.md").write_text("# new\n\n**Status:** FIXED\n")
    sweep_commit = _dated_commit(tmp_path, "status sweep", "2026-02-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.1.0"], cwd=tmp_path, check=True)

    assert tally_module.fixed_in("HEAD") == {
        "docs/bugs/new.md": {"release": "v1.1.0", "source": "status_change", "commit": sweep_commit},
        "docs/bugs/old.md": {"release": "unknown", "source": "status_backfill", "commit": sweep_commit},
    }
