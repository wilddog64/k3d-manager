"""Tests for the LIVE-VERIFIED evidence lint."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "check-bug-evidence.py"


def _repo(tmp_path, status, evidence=""):
    path = tmp_path / "docs/bugs/example.md"
    path.parent.mkdir(parents=True)
    path.write_text(f"**Status:** {status}\n{evidence}", encoding="utf-8")
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=tmp_path, check=True)
    return path


def _run(path, cwd):
    return subprocess.run(["python3", str(SCRIPT), str(path.relative_to(cwd))], cwd=cwd,
                          capture_output=True, text=True, check=False)


def test_M6_new_live_verified_doc_requires_evidence(tmp_path):
    path = _repo(tmp_path, "FIXED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    path.write_text("**Status:** LIVE-VERIFIED\n", encoding="utf-8")
    result = _run(path, tmp_path)
    assert result.returncode == 1
    assert "docs/bugs/example.md" in result.stderr


def test_M6_evidence_line_allows_live_verified_transition(tmp_path):
    path = _repo(tmp_path, "FIXED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    path.write_text(
        "**Status:** LIVE-VERIFIED\n"
        "**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit abcdef1 · proves E3\n",
        encoding="utf-8",
    )
    result = _run(path, tmp_path)
    assert result.returncode == 0
    assert result.stderr == ""


def test_N2_existing_live_and_non_live_docs_are_not_retroactively_blocked(tmp_path):
    path = _repo(tmp_path, "LIVE-VERIFIED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    path.write_text("**Status:** LIVE-VERIFIED\nchanged\n", encoding="utf-8")
    assert _run(path, tmp_path).returncode == 0

    path.write_text("**Status:** FIXED\n", encoding="utf-8")
    assert _run(path, tmp_path).returncode == 0


def test_non_bug_path_passes(tmp_path):
    path = tmp_path / "docs/notes.md"
    path.parent.mkdir()
    path.write_text("**Status:** LIVE-VERIFIED\n", encoding="utf-8")
    assert _run(path, tmp_path).returncode == 0
