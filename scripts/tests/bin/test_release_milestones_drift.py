import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def test_release_milestones_stay_in_sync_with_roadmap():
    staged = os.environ.get("RELEASE_MILESTONES_STAGED") == "1"
    def read(path):
        if staged:
            return subprocess.run(["git", "show", f":{path}"], cwd=ROOT, text=True,
                                  capture_output=True, check=True).stdout
        return (ROOT / path).read_text()
    payload = json.loads(read("docs/release-milestones.json"))
    versions = [item["version"] for item in payload["milestones"]]
    assert sum(bool(item.get("target")) for item in payload["milestones"]) == 1
    assert versions == sorted(versions, key=lambda v: tuple(map(int, v[1:].split("."))))
    roadmap = read("docs/roadmap.md")
    tags = set(subprocess.run(["git", "tag", "--list", "v*"], cwd=ROOT,
                              text=True, capture_output=True, check=True).stdout.splitlines())
    version_key = lambda v: tuple(map(int, v[1:].split(".")))
    release_tags = [v for v in tags if re.fullmatch(r"v\d+\.\d+\.\d+", v)]
    newest = max(map(version_key, release_tags), default=(0, 0, 0))
    target = next(item["version"] for item in payload["milestones"] if item.get("target"))
    limit = version_key(target)
    headings = re.findall(r"^### (?:Candidate milestone|Patch release) — (v\d+\.\d+\.\d+)", roadmap, re.M)
    if staged:
        paths = subprocess.run(["git", "ls-files", "--", "docs/plans/*.md"], cwd=ROOT,
                               text=True, capture_output=True, check=True).stdout.splitlines()
    else:
        paths = (ROOT / "docs/plans").glob("v*.md")
    plans = [match.group(1) for path in paths
             if (match := re.match(r"^(v\d+\.\d+\.\d+)-.+\.md$", Path(path).name))]
    missing = sorted({v for v in headings + plans if newest < version_key(v) <= limit
                      and v not in versions}, key=version_key)
    # agent-audit: allow assert-removed both old asserts are restated below as missing and missing_roadmap
    assert not missing, "missing milestones: " + ", ".join(missing)
    missing_roadmap = [item["version"] for item in payload["milestones"]
                       if item["version"] not in tags and item.get("state") != "folded"
                       and item["version"] not in roadmap]
    assert not missing_roadmap, "missing from roadmap: " + ", ".join(missing_roadmap)


def _fixture_repo(tmp_path):
    import shutil

    root = tmp_path / "fixture-repo"
    root.mkdir()
    assert root.resolve() != ROOT.resolve()
    (root / "docs/plans").mkdir(parents=True)
    (root / "scripts/tests/bin").mkdir(parents=True)
    (root / "scripts/lib").mkdir(parents=True)
    (root / ".githooks").mkdir()
    shutil.copy2(__file__, root / "scripts/tests/bin/test_release_milestones_drift.py")
    shutil.copy2(ROOT / ".githooks/pre-commit", root / ".githooks/pre-commit")
    shutil.copy2(ROOT / "Makefile", root / "Makefile")
    (root / "scripts/lib/system.sh").write_text("")
    (root / "scripts/lib/agent_rigor.sh").write_text("_agent_audit() { return 0; }\n")
    (root / "docs/roadmap.md").write_text("### Candidate milestone — v1.0.2\n")
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.0.2", "target": True}]}))
    import site
    env = {**os.environ, "HOME": str(tmp_path),
           "PYTHONUSERBASE": os.environ.get("PYTHONUSERBASE") or site.getuserbase(),
           "GIT_AUTHOR_NAME": "Test",
           "GIT_AUTHOR_EMAIL": "test@example.invalid", "GIT_COMMITTER_NAME": "Test",
           "GIT_COMMITTER_EMAIL": "test@example.invalid"}
    def git(*args, input_text=None):
        return subprocess.run(["git", *args], cwd=root, env=env, input=input_text,
                              text=True, capture_output=True, check=True).stdout.strip()
    git("init", "-q", "-b", "k3d-manager-v1.0.1")
    tree = git("mktree", input_text="")
    commit = git("commit-tree", tree, input_text="fixture\n")
    git("update-ref", "refs/heads/k3d-manager-v1.0.1", commit)
    git("update-ref", "refs/tags/v1.0.0", commit)
    def stage(path):
        blob = git("hash-object", "-w", "--", path)
        git("update-index", "--add", "--cacheinfo", f"100644,{blob},{path}")
    stage("docs/roadmap.md")
    stage("docs/release-milestones.json")
    base = git("commit-tree", git("write-tree"), input_text="fixture files\n")
    git("update-ref", "refs/heads/k3d-manager-v1.0.1", base)
    return root, env, stage


def _run_drift(root, env):
    import sys
    return subprocess.run([sys.executable, "-m", "pytest", "-q",
                           "scripts/tests/bin/test_release_milestones_drift.py::test_release_milestones_stay_in_sync_with_roadmap"],
                          cwd=root, env=env, capture_output=True, text=True)


def test_patch_and_plan_versions_are_checked(tmp_path):
    root, env, _stage = _fixture_repo(tmp_path)
    roadmap = root / "docs/roadmap.md"
    roadmap.write_text(roadmap.read_text() + "### Patch release — v1.0.1\n")
    result = _run_drift(root, env)
    assert result.returncode != 0 and "v1.0.1" in result.stdout
    roadmap.write_text("### Candidate milestone — v1.0.2\n")
    (root / "docs/plans/v1.0.1-example.md").write_text("plan\n")
    result = _run_drift(root, env)
    assert result.returncode != 0 and "v1.0.1" in result.stdout
    make = subprocess.run(["make", "check-release-milestones"], cwd=root, env=env,
                          capture_output=True, text=True)
    assert make.returncode != 0 and "v1.0.1" in make.stdout + make.stderr
    (root / "docs/plans/v1.0.1-example.md").unlink()
    (root / "docs/plans/v0.9.0-history.md").write_text("history\n")
    assert _run_drift(root, env).returncode == 0


def test_precommit_blocks_drift_and_allows_control(tmp_path):
    root, env, stage = _fixture_repo(tmp_path)
    roadmap = root / "docs/roadmap.md"
    roadmap.write_text(roadmap.read_text() + "### Patch release — v1.0.1\n")
    stage("docs/roadmap.md")
    def hook():
        return subprocess.run(["bash", ".githooks/pre-commit"], cwd=root, env=env,
                              capture_output=True, text=True)
    result = hook()
    assert result.returncode != 0 and "v1.0.1" in result.stdout + result.stderr
    assert "make check-release-milestones" in result.stderr
    roadmap.write_text("### Candidate milestone — v1.0.2\n")
    assert hook().returncode != 0
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.0.1"}, {"version": "v1.0.2", "target": True}]}))
    stage("docs/release-milestones.json")
    assert hook().returncode == 0
    subprocess.run(["git", "reset", "-q"], cwd=root, env=env, check=True)
    (root / "unrelated.txt").write_text("unrelated\n")
    stage("unrelated.txt")
    (root / "docs/release-milestones.json").write_text(json.dumps({"milestones": [
        {"version": "v1.0.2", "target": True}]}))
    fake_bin = root / "fake-bin"
    fake_bin.mkdir()
    fake_make = fake_bin / "make"
    marker = root / "make-was-run"
    assert marker.parent == root and root.resolve() != ROOT.resolve()
    fake_make.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 1\n")
    fake_make.chmod(0o755)
    env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
    assert hook().returncode == 0
    assert not marker.exists()
