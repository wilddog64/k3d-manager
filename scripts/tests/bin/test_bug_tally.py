import importlib.util
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
    assert result["v1.1.0"]["open"] == 1
    assert result["v1.1.0"]["by_source"]["added_branch"] == 1
    assert all("archive" not in item["path"] for item in result["v1.0.0"]["unknown_paths"])


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
