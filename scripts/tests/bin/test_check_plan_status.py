"""Tests for the plan Status pre-commit guard."""

import importlib.util
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "check_plan_status", ROOT / "scripts" / "check-plan-status.py"
)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


def test_pair_parses_status_and_approved_intent():
    text = "# Plan\n**Status:** DRAFT v5 — notes\n**Intent approved:** operator, 2026-11-19\n## Details\n"
    assert CHECK._pair(text) == ("draft", True)


def test_intent_pending_or_no_is_not_approved():
    assert CHECK._pair("**Status:** DRAFT\n**Intent approved:** pending\n") == ("draft", False)
    assert CHECK._pair("**Status:** DRAFT\n**Intent approved:** no — reason\n") == (
        "draft",
        False,
    )


def test_umbrella_landed_word_is_not_status():
    assert CHECK._pair(
        "**Status:** IN PROGRESS — Part 1 landed\n"
        "**Intent approved:** operator, 2026-11-19\n"
    ) == ("in", True)


def test_draft_approved_refuses_new_and_changed_pair(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/new.md"
    plan.parent.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    (repo / "README.md").write_text("base\n")
    subprocess.run(["git", "-C", str(repo), "add", "README.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "base"], check=True)
    plan.write_text("**Status:** DRAFT\n**Intent approved:** operator, 2026-11-19\n")
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/new.md"]) == 1
    assert "Status DRAFT but intent is approved" in capsys.readouterr().err


@pytest.mark.parametrize("intent", ["pending", "no — reason"])
def test_main_accepts_draft_with_pending_or_no_intent(tmp_path, monkeypatch, intent):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/draft.md"
    plan.parent.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    (repo / "README.md").write_text("base\n")
    subprocess.run(["git", "-C", str(repo), "add", "README.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "base"], check=True)
    plan.write_text(f"**Status:** DRAFT\n**Intent approved:** {intent}\n")
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/draft.md"]) == 0


def test_existing_draft_approved_pair_allows_edit(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/existing.md"
    plan.parent.mkdir(parents=True)
    plan.write_text("**Status:** DRAFT\n**Intent approved:** operator, 2026-11-19\n")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "base"], check=True)
    plan.write_text(plan.read_text() + "edited\n")
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/existing.md"]) == 0


def test_existing_draft_getting_approval_is_refused(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/existing.md"
    plan.parent.mkdir(parents=True)
    plan.write_text("**Status:** DRAFT\n**Intent approved:** pending\n")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "base"], check=True)
    plan.write_text("**Status:** DRAFT\n**Intent approved:** operator, 2026-11-19\n")
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/existing.md"]) == 1
    assert "Status DRAFT but intent is approved" in capsys.readouterr().err


def test_ready_is_positive_control(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/ready.md"
    plan.parent.mkdir(parents=True)
    plan.write_text("**Status:** READY\n**Intent approved:** operator, 2026-11-19\n")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/ready.md"]) == 0


def test_umbrella_with_landed_in_status_is_accepted(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    plan = repo / "docs/plans/umbrella.md"
    plan.parent.mkdir(parents=True)
    plan.write_text(
        "**Status:** IN PROGRESS — Part 1 landed\n"
        "**Intent approved:** operator, 2026-11-19\n"
    )
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    monkeypatch.chdir(repo)
    assert CHECK.main(["docs/plans/umbrella.md"]) == 0


def test_pre_commit_plan_status_bypass(tmp_path):
    repo = tmp_path / "repo"
    hook = repo / ".githooks/pre-commit"
    scripts = repo / "scripts"
    (hook.parent).mkdir(parents=True)
    (scripts / "lib").mkdir(parents=True)
    (repo / "docs/plans").mkdir(parents=True)
    shutil.copy2(ROOT / ".githooks/pre-commit", hook)
    shutil.copy2(ROOT / "scripts/check-plan-status.py", scripts / "check-plan-status.py")
    (scripts / "lib/agent_rigor.sh").write_text(
        "#!/usr/bin/env bash\n_agent_audit() { return 0; }\n"
    )
    (scripts / "lib/system.sh").write_text("#!/usr/bin/env bash\n")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    (repo / "README.md").write_text("base\n")
    subprocess.run(["git", "-C", str(repo), "add", "README.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "base"], check=True)
    (repo / "docs/plans/draft.md").write_text(
        "**Status:** DRAFT\n**Intent approved:** operator, 2026-11-19\n"
    )
    subprocess.run(["git", "-C", str(repo), "add", "docs/plans/draft.md"], check=True)
    env = os.environ.copy()
    env["K3DM_SKIP_RELEASE_MILESTONES"] = "1"
    rejected = subprocess.run(
        [str(hook)], cwd=repo, env=env, capture_output=True, text=True, check=False
    )
    assert rejected.returncode == 1
    assert "Status DRAFT but intent is approved" in rejected.stderr
    env["K3DM_SKIP_PLAN_STATUS"] = "1"
    bypassed = subprocess.run(
        [str(hook)], cwd=repo, env=env, capture_output=True, text=True, check=False
    )
    assert bypassed.returncode == 0, bypassed.stderr
