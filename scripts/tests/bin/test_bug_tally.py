import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


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


def _dated_commit(root, message, date):
    subprocess.run(["git", "add", "docs/bugs"], cwd=root, check=True)
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(["git", "commit", "-qm", message], cwd=root, check=True, env=env)


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
    _dated_commit(tmp_path, "v1.1 fixes", "2025-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.1.0"], cwd=tmp_path, check=True)
    write("a", "VERIFIED")
    write("f", "FIXED")
    _dated_commit(tmp_path, "v1.2 fixes", "2024-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.2.0"], cwd=tmp_path, check=True)
    subprocess.run(["git", "switch", "-q", "-c", "k3d-manager-v1.3.0"], cwd=tmp_path, check=True)
    write("b", "FIXED")
    write("c", "OPEN")
    write("e", "OPEN", "k3d-manager-v1.2.0")
    (bugs / "e.md").write_text("# e\n\n**Priority:** P1\n## Status\nOPEN\n")
    _dated_commit(tmp_path, "branch docs", "2023-01-01T00:00:00Z")
    write("c", "LIVE-VERIFIED")
    (bugs / "e.md").write_text("# e\n\n**Priority:** P1\n**Branch:** k3d-manager-v1.2.0\n## Status\nFIXED\n")
    _dated_commit(tmp_path, "branch fix", "2022-01-01T00:00:00Z")

    fixed = tally_module.fixed_in("HEAD")
    assert fixed == {
        "docs/bugs/a.md": {"release": "v1.1.0", "source": "status_change"},
        "docs/bugs/b.md": {"release": "v1.3.0", "source": "added_fixed"},
        "docs/bugs/c.md": {"release": "v1.3.0", "source": "status_change"},
        "docs/bugs/e.md": {"release": "unknown", "source": "no_transition"},
        "docs/bugs/f.md": {"release": "v1.2.0", "source": "status_change"},
    }
    before = tally_module.tally("k3d-manager-v1.3.0")
    subprocess.run(["git", "switch", "-q", "-c", "scratch"], cwd=tmp_path, check=True)
    assert tally_module.fixed_in("HEAD")["docs/bugs/b.md"]["release"] == "unknown"
    assert tally_module.fixed_in("HEAD")["docs/bugs/c.md"]["release"] == "unknown"
    assert tally_module.tally("k3d-manager-v1.3.0") == before


def test_json_main_includes_fixed_in_without_changing_releases(tally_module, capsys):
    bugs = tally_module.ROOT / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    _dated_commit(tally_module.ROOT, "fixed", "2026-01-01T00:00:00Z")
    expected = tally_module.tally("HEAD")
    assert tally_module.main(["--json", "--ref", "HEAD"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["releases"] == expected
    assert payload["fixed_in"]["docs/bugs/fixed.md"]["source"] == "added_fixed"


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


def test_fixed_in_status_backfilled_onto_an_existing_doc_is_unknown(tally_module, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "old.md").write_text("# old\n\nno status line yet\n")
    (bugs / "new.md").write_text("# new\n\n**Status:** OPEN\n")
    _dated_commit(tmp_path, "docs without status", "2026-01-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.0.0"], cwd=tmp_path, check=True)
    (bugs / "old.md").write_text("# old\n\n**Status:** CLOSED — status sweep\n\nno status line yet\n")
    (bugs / "new.md").write_text("# new\n\n**Status:** FIXED\n")
    _dated_commit(tmp_path, "status sweep", "2026-02-01T00:00:00Z")
    subprocess.run(["git", "tag", "v1.1.0"], cwd=tmp_path, check=True)

    assert tally_module.fixed_in("HEAD") == {
        "docs/bugs/new.md": {"release": "v1.1.0", "source": "status_change"},
        "docs/bugs/old.md": {"release": "unknown", "source": "status_backfill"},
    }
