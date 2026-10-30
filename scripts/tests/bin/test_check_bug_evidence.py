"""Tests for the LIVE-VERIFIED evidence lint."""

import subprocess
import pytest
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


def _run(path, cwd, env=None):
    return subprocess.run(["python3", str(SCRIPT), str(path.relative_to(cwd))], cwd=cwd,
                          capture_output=True, text=True, check=False, env=env)


def _commit(cwd, message):
    (cwd / f"{message}.txt").write_text(message, encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=cwd, check=True)
    subprocess.run(["git", "commit", "-qm", message], cwd=cwd, check=True)
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=cwd, text=True).strip()


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
    fix_commit = _commit(tmp_path, "fix")
    path.write_text(
        "**Status:** LIVE-VERIFIED\n"
        f"**Fix commit:** `{fix_commit}`\n"
        f"**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit {fix_commit} · proves E3\n",
        encoding="utf-8",
    )
    result = _run(path, tmp_path)
    assert result.returncode == 0
    assert result.stderr == ""


def test_N1_new_live_verified_doc_requires_fix_commit(tmp_path):
    path = _repo(tmp_path, "FIXED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    path.write_text(
        "**Status:** LIVE-VERIFIED\n"
        "**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit abcdef1 · proves E3\n",
        encoding="utf-8",
    )
    result = _run(path, tmp_path)
    assert result.returncode == 1
    assert "needs a **Fix commit:**" in result.stderr


def test_N2_resolved_evidence_without_fix_is_rejected(tmp_path):
    path = _repo(tmp_path, "FIXED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    path.write_text("unrelated\n", encoding="utf-8")
    evidence_commit = _commit(tmp_path, "evidence")
    fix_commit = _commit(tmp_path, "fix")
    path.write_text(
        "**Status:** LIVE-VERIFIED\n"
        f"**Fix commit:** `{fix_commit}`\n"
        f"**Live evidence:** 2026-10-17 · run 1 · env hub/k3d · scenario test · commit {evidence_commit} · proves E3\n",
        encoding="utf-8",
    )
    result = _run(path, tmp_path)
    assert result.returncode == 1
    assert f"contains the fix commit {fix_commit}" in result.stderr


def test_M3_unresolvable_evidence_does_not_fail(tmp_path):
    path = _repo(tmp_path, "FIXED")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=tmp_path, check=True)
    fix_commit = _commit(tmp_path, "fix")
    path.write_text(
        "**Status:** LIVE-VERIFIED\n"
        f"**Fix commit:** `{fix_commit}`\n"
        "**Live evidence:** 2026-10-17 · run 1 · env other-repo · scenario test · commit deadbee · proves E3\n",
        encoding="utf-8",
    )
    assert _run(path, tmp_path).returncode == 0


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


@pytest.mark.parametrize("header", ["**Fix commit:** not-a-sha", "**Fix commit:**", "**FIX COMMIT:** broken", "**Fix commit:** abcdef1234567"])
def test_investigation_hook_rejects_explicit_fix_headers(tmp_path, header):
    path = _repo(tmp_path, "LIVE-VERIFIED", (
        "**verification type:** INVESTIGATION\n"
        "**live investigation evidence:** 2026-10-28 · source operator · "
        "reference opaque-proof · env local · scenario health · proves m1\n" + header + "\n"))
    result = _run(path, tmp_path)
    assert result.returncode == 1
    assert "only for bugs without a **Fix commit:**" in result.stderr


def test_investigation_hook_case_insensitive_type_and_line(tmp_path):
    path = _repo(tmp_path, "LIVE-VERIFIED", (
        "**verification type:** INVESTIGATION\n"
        "**live investigation evidence:** 2026-10-28 · source operator · "
        "reference opaque-proof · env local · scenario health · proves m1\n"))
    assert _run(path, tmp_path).returncode == 0
    path.write_text(path.read_text().replace("2026-10-28", "2026-02-30"))
    result = _run(path, tmp_path)
    assert result.returncode == 1
    assert "typed **Live investigation evidence:** line" in result.stderr
