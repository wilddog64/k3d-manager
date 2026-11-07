"""Tests for the bug Status first-word guard."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "check-bug-status.py"
HOOK = ROOT / ".githooks" / "pre-commit"


def _repo(tmp_path):
    root = tmp_path / "scratch-repo"
    root.mkdir()
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    assert root.resolve() == Path(subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], cwd=root, text=True
    ).strip()).resolve()
    assert root.resolve() != ROOT.resolve()
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
    return root


def _doc(root, status, path="docs/bugs/example.md"):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(f"**Status:** {status}\n**Priority:** P3\n", encoding="utf-8")
    return target


def _run(root, path):
    return subprocess.run(
        ["python3", str(SCRIPT), path.relative_to(root).as_posix()], cwd=root,
        capture_output=True, text=True, check=False,
    )


def _commit(root, *paths):
    subprocess.run(["git", "add", "--", *[path.relative_to(root).as_posix() for path in paths]], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=root, check=True)


@pytest.mark.parametrize("status", ["Correction 4 LANDED 632ac235", "FIX IN SUBTREE — both scripts resolve"])
def test_M1_changed_bad_status_is_refused(tmp_path, status):
    root = _repo(tmp_path)
    path = _doc(root, "OPEN")
    _commit(root, path)
    path.write_text(f"**Status:** {status}\n", encoding="utf-8")
    result = _run(root, path)
    assert result.returncode == 1
    assert "docs/bugs/example.md" in result.stderr
    assert status[:60] in result.stderr


def test_M2_open_fix_landed_is_refused(tmp_path):
    root = _repo(tmp_path)
    path = _doc(root, "FIXED")
    _commit(root, path)
    path.write_text("**Status:** OPEN — fix landed 6d42c201\n", encoding="utf-8")
    assert _run(root, path).returncode == 1


def test_M3_new_bad_status_is_refused(tmp_path):
    root = _repo(tmp_path)
    path = _doc(root, "FIX IN SUBTREE")
    result = _run(root, path)
    assert result.returncode == 1
    assert "docs/bugs/example.md" in result.stderr


def test_N1_unchanged_legacy_status_passes_and_changed_bad_status_fails(tmp_path):
    root = _repo(tmp_path)
    path = _doc(root, "Correction 4 LANDED old")
    _commit(root, path)
    path.write_text("**Status:** Correction 4 LANDED old\nOther line edited\n", encoding="utf-8")
    assert _run(root, path).returncode == 0
    path.write_text("**Status:** FIX IN SUBTREE\nOther line edited\n", encoding="utf-8")
    assert _run(root, path).returncode == 1


@pytest.mark.parametrize("word", ["OPEN", "OPEN — machine-setup half landed", "REOPENED", "LANDED", "VERIFIED", "LIVE-VERIFIED", "FIXED", "CLOSED", "DEFERRED", "open", "reopened", "landed", "verified", "live-verified", "fixed", "closed", "deferred"])
def test_N2_accepted_first_words_pass(tmp_path, word):
    root = _repo(tmp_path)
    path = _doc(root, f"{word} details")
    assert _run(root, path).returncode == 0


def test_N3_non_bug_path_and_missing_status_pass(tmp_path):
    root = _repo(tmp_path)
    outside = _doc(root, "FIX IN SUBTREE", "docs/notes.md")
    missing = root / "docs/bugs/missing.md"
    missing.parent.mkdir(parents=True, exist_ok=True)
    missing.write_text("No status here\n", encoding="utf-8")
    assert _run(root, outside).returncode == 0
    assert _run(root, missing).returncode == 0
    bad = _doc(root, "FIX IN SUBTREE")
    assert _run(root, bad).returncode == 1


def test_nested_bug_path_passes_and_direct_bug_path_fails(tmp_path):
    root = _repo(tmp_path)
    nested = _doc(root, "FIX IN SUBTREE", "docs/bugs/sub/x.md")
    direct = _doc(root, "FIX IN SUBTREE", "docs/bugs/x.md")
    assert _run(root, nested).returncode == 0
    assert _run(root, direct).returncode == 1


def _install_hook_repo(root):
    script_dir = root / "scripts"
    (script_dir / "lib").mkdir(parents=True)
    shutil.copy2(SCRIPT, script_dir / "check-bug-status.py")
    shutil.copytree(ROOT / "scripts" / "lib" / "hermes", script_dir / "lib" / "hermes")
    shutil.copytree(ROOT / ".githooks", root / ".githooks")
    shutil.copy2(ROOT / "scripts" / "check-bug-evidence.py", script_dir / "check-bug-evidence.py")
    (script_dir / "lib" / "system.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (script_dir / "lib" / "agent_rigor.sh").write_text(
        "_agent_audit() { return 0; }\n", encoding="utf-8"
    )
    return root


def _hook_commit(root, env=None):
    subprocess.run(["git", "add", "--all"], cwd=root, check=True)
    return subprocess.run(["git", "commit", "-m", "hook test"], cwd=root,
                          capture_output=True, text=True, check=False, env=env)


def test_M4_hook_blocks_bad_status_and_bypass_allows_commit(tmp_path):
    root = _install_hook_repo(_repo(tmp_path))
    (root / ".git" / "hooks" / "pre-commit").write_text(
        f"#!/bin/sh\nexec bash '{root / '.githooks' / 'pre-commit'}'\n", encoding="utf-8"
    )
    (root / ".git" / "hooks" / "pre-commit").chmod(0o755)
    path = _doc(root, "FIX IN SUBTREE")
    blocked = _hook_commit(root)
    assert blocked.returncode != 0
    assert "docs/bugs/example.md" in blocked.stderr
    env = os.environ.copy()
    env["K3DM_SKIP_BUG_STATUS"] = "1"
    allowed = _hook_commit(root, env=env)
    assert allowed.returncode == 0, allowed.stderr


def test_N4_evidence_guard_still_blocks_with_status_bypass(tmp_path):
    root = _install_hook_repo(_repo(tmp_path))
    (root / ".git" / "hooks" / "pre-commit").write_text(
        f"#!/bin/sh\nexec bash '{root / '.githooks' / 'pre-commit'}'\n", encoding="utf-8"
    )
    (root / ".git" / "hooks" / "pre-commit").chmod(0o755)
    path = _doc(root, "LIVE-VERIFIED")
    env = os.environ.copy()
    env["K3DM_SKIP_BUG_STATUS"] = "1"
    blocked = _hook_commit(root, env=env)
    assert blocked.returncode != 0
    assert "LIVE-VERIFIED" in blocked.stderr
    path.write_text(
        "**Status:** LIVE-VERIFIED\n**Priority:** P3\n**Fix commit:** abcdef1234567\n"
        "**Live evidence:** 2026-11-06 · run test · env scratch · scenario hook · "
        "commit abcdef1234567 · proves E1\n", encoding="utf-8"
    )
    allowed = _hook_commit(root, env=env)
    assert allowed.returncode == 0, allowed.stderr
