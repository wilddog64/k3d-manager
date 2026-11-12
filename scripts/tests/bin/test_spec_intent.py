import os
import shutil
import subprocess
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.lib.spec_intent import check
from scripts.lib import spec_intent


def _spec(tmp_path: Path, filed: str, evidence: str, approved: str = "") -> Path:
    root = tmp_path / "scratch-specs"
    root.mkdir(exist_ok=True)
    path = root / "fixture.md"
    path.write_text(
        f"**Filed:** {filed}\n{approved}\n## Acceptance\n```yaml\n"
        f"must: []\nmust_not: []\nevidence:\n{evidence}\n```\n",
        encoding="utf-8",
    )
    assert root != Path(__file__).resolve().parents[3] / "docs/plans"
    return path


def test_approved_recent_spec_passes(tmp_path):
    path = _spec(
        tmp_path,
        "2026-11-07",
        "  - id: E1\n    intent: >-\n      You will see a result. It failed if absent.\n",
        "**Intent approved:** operator, 2026-11-07",
    )
    assert check(path) == []


def test_missing_evidence_intent_names_gap(tmp_path):
    path = _spec(tmp_path, "2026-11-08", "  - id: E1\n    kind: offline\n")
    assert check(path) == [
        "evidence item E1 is missing intent",
        "missing **Intent approved:** header",
    ]


def test_empty_block_intent_is_missing(tmp_path):
    path = _spec(
        tmp_path,
        "2026-11-08",
        "  - id: E1\n    intent: >-\n\n",
        "**Intent approved:** operator, 2026-11-08",
    )
    assert check(path) == ["evidence item E1 is missing intent"]


def test_intents_without_approval_are_refused(tmp_path):
    path = _spec(tmp_path, "2026-11-08", "  - id: E1\n    intent: visible result\n")
    assert check(path) == ["missing **Intent approved:** header"]


def test_old_spec_is_exempt(tmp_path):
    path = _spec(tmp_path, "2026-11-06", "  - id: E1\n")
    assert check(path) == []


def test_first_commit_date_is_used_when_filed_is_absent(tmp_path):
    path = _spec(tmp_path, "2026-11-08", "  - id: E1\n")
    text = path.read_text(encoding="utf-8").replace("**Filed:** 2026-11-08\n", "")
    path.write_text(text, encoding="utf-8")
    from datetime import date

    assert check(path, first_commit_date=date(2026, 11, 6)) == []


def test_positive_control_accepts_complete_recent_spec(tmp_path):
    path = _spec(
        tmp_path,
        "2026-11-08",
        "  - id: E1\n    intent: visible result\n",
        "**Intent approved:** operator, 2026-11-08",
    )
    assert check(path) == []


def test_checker_subprocess_without_yaml_dependency(tmp_path):
    module = Path(__file__).resolve().parents[2] / "lib/spec_intent.py"
    if os.environ.get("SPEC_INTENT_CHECKER_BASELINE") == "1":
        module = tmp_path / "baseline_spec_intent.py"
        source = (Path(__file__).resolve().parents[2] / "lib/spec_intent.py").read_text(
            encoding="utf-8"
        )
        source = source.replace(
            "from __future__ import annotations\n",
            "from __future__ import annotations\n\nimport yaml\n",
            1,
        )
        module.write_text(source, encoding="utf-8")
    isolated = shutil.which("python3")
    assert isolated
    poison = tmp_path / "no-yaml"
    poison.mkdir()
    (poison / "yaml.py").write_text("raise ImportError('yaml must not be imported')\n")
    env = os.environ.copy()
    env["PYTHONPATH"] = str(poison)

    old = _spec(tmp_path, "2026-11-07", "not: valid: yaml: [", "")
    old_result = subprocess.run(
        [isolated, "-I", str(module), str(old)], capture_output=True, text=True, env=env
    )
    assert old_result.returncode == 0, old_result.stdout + old_result.stderr

    recent = _spec(
        tmp_path,
        "2026-11-08",
        "  - id: E1\n    intent: >-\n      Visible result.\n",
        "**Intent approved:** operator, 2026-11-08",
    )
    recent_result = subprocess.run(
        [isolated, "-I", str(module), str(recent)], capture_output=True, text=True, env=env
    )
    assert recent_result.returncode == 0, recent_result.stdout + recent_result.stderr


def test_all_existing_specs_are_exempt_as_of_this_commit():
    if os.environ.get("SPEC_INTENT_DATE_BASELINE") == "1":
        spec_intent.INTENT_RULE_DATE = spec_intent.dt.date(2026, 11, 7)
    repo = Path(__file__).resolve().parents[3]
    specs = list((repo / "docs/plans").glob("*.md")) + list((repo / "docs/bugs").glob("*.md"))
    assert specs
    assert all(path.is_file() for path in specs)
    gaps = {}
    existing = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", "--name-only", "c5d28596", "--", "docs/plans", "docs/bugs"],
        check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    assert len(existing) > 500
    specs = [path for path in specs if str(path.relative_to(repo)) in existing]
    for path in specs:
        result = check(path)
        if result:
            gaps[str(path.relative_to(repo))] = result
    assert gaps == {}


def _scratch_dispatch_repo(tmp_path: Path, monkeypatch, *, baseline: bool = False):
    source_repo = Path(__file__).resolve().parents[3]
    repo = tmp_path / "dispatch-fixture"
    repo.mkdir()
    assert repo != source_repo
    (repo / "bin").mkdir()
    (repo / "scripts/lib").mkdir(parents=True)
    dispatcher = source_repo / "bin/k3dm-codex-dispatch"
    dispatcher_text = dispatcher.read_text(encoding="utf-8")
    gate = '''  local spec_intent_output spec_intent_rc
  if spec_intent_output="$(python3 "$_dispatch_script_dir/../scripts/lib/spec_intent.py" "$_dispatch_repo_root/$spec" 2>&1)"; then
    :
  else
    spec_intent_rc=$?
    if (( spec_intent_rc == 1 )); then
      _dispatch_error "refused: ${spec_intent_output}"
    fi
    _dispatch_error "spec-intent checker failed (rc ${spec_intent_rc}): ${spec_intent_output}"
  fi
'''
    if baseline:
        assert gate in dispatcher_text
        dispatcher_text = dispatcher_text.replace(gate, "", 1)
    (repo / "bin/k3dm-codex-dispatch").write_text(dispatcher_text, encoding="utf-8")
    (repo / "bin/k3dm-codex-dispatch").chmod(0o755)
    shutil.copy2(source_repo / "scripts/lib/system.sh", repo / "scripts/lib/system.sh")
    shutil.copy2(source_repo / "scripts/lib/spec_intent.py", repo / "scripts/lib/spec_intent.py")
    shutil.copytree(source_repo / "scripts/lib/foundation", repo / "scripts/lib/foundation")

    stub_bin = tmp_path / "stub-bin"
    stub_bin.mkdir()
    marker = tmp_path / "agent-started"
    stub = stub_bin / "codex"
    stub.write_text(f"#!/bin/sh\nprintf started > '{marker}'\nexit 88\n", encoding="utf-8")
    stub.chmod(0o755)
    (stub_bin / "agy").write_text(stub.read_text(encoding="utf-8"), encoding="utf-8")
    (stub_bin / "agy").chmod(0o755)

    subprocess.run(["git", "init", "-q", "-b", "k3d-manager-v1.43.15", str(repo)], check=True)
    fixture_root = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--show-toplevel"], text=True
    ).strip()
    assert Path(fixture_root).resolve() == repo.resolve()
    assert Path(fixture_root).resolve() != source_repo.resolve()
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Fixture"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "fixture@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "bin", "scripts"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "fixture dispatcher"], check=True)

    env = os.environ.copy()
    env["HOME"] = str(tmp_path / "home")
    Path(env["HOME"]).mkdir()
    env["PATH"] = f"{stub_bin}{os.pathsep}{env['PATH']}"
    monkeypatch.setenv("SPEC_INTENT_TEST_BASELINE", "1" if baseline else "0")
    return repo, marker, env


def _run_dispatch(repo: Path, env, evidence: str, approved: str = ""):
    spec = repo / "specs/fixture.md"
    spec.parent.mkdir(exist_ok=True)
    spec.write_text(
        "**Filed:** 2026-11-08\n"
        f"{approved}\n## Files\n- `scripts/lib/spec_intent.py`\n"
        f"## Acceptance\n```yaml\nmust: []\nmust_not: []\nevidence:\n{evidence}```\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "-C", str(repo), "add", "specs/fixture.md"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "fixture spec"], check=True)
    return subprocess.run(
        [str(repo / "bin/k3dm-codex-dispatch"), "start", "--spec", "specs/fixture.md"],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
    )


def test_dispatch_n1_refuses_missing_intent_before_agent_launch(tmp_path, monkeypatch):
    baseline = os.environ.get("SPEC_INTENT_TEST_BASELINE") == "1"
    repo, marker, env = _scratch_dispatch_repo(tmp_path, monkeypatch, baseline=baseline)
    result = _run_dispatch(repo, env, "  - id: E1\n    kind: offline\n")
    output = result.stdout + result.stderr
    assert result.returncode != 0
    assert "evidence item E1" in output
    assert not marker.exists()


def test_dispatch_n2_refuses_missing_approval_before_agent_launch(tmp_path, monkeypatch):
    baseline = os.environ.get("SPEC_INTENT_TEST_BASELINE") == "1"
    repo, marker, env = _scratch_dispatch_repo(tmp_path, monkeypatch, baseline=baseline)
    result = _run_dispatch(
        repo,
        env,
        "  - id: E1\n    intent: Visible result.\n",
    )
    output = result.stdout + result.stderr
    assert result.returncode != 0
    assert "missing **Intent approved:** header" in output
    assert not marker.exists()


def test_dispatch_positive_control_passes_intent_gate_before_offline_fetch_failure(
    tmp_path, monkeypatch
):
    repo, marker, env = _scratch_dispatch_repo(tmp_path, monkeypatch)
    result = _run_dispatch(
        repo,
        env,
        "  - id: E1\n    intent: Visible result.\n",
        "**Intent approved:** operator, 2026-11-08",
    )
    output = result.stdout + result.stderr
    assert result.returncode != 0
    assert "could not fetch origin/" in output
    assert "spec intent approval is required" not in output
    assert not marker.exists()
