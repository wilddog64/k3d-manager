import subprocess
from pathlib import Path

from hermes import e2e_bugs
from hermes.e2e_bugs import _doc, _status


def group():
    return {"kind": "contract-drift", "target": "api-cart", "slug": "e2e-contract-drift-api-cart",
            "count": 1, "titles": [{"file": "api/cart.spec.ts", "title": "returns cart"}],
            "samples": ["password=sentinel-secret"]}


def test_template_is_redacted_and_open(tmp_path):
    text = _doc(group(), {"run_id": "r1", "summary": {"passed": 1, "failed": 1, "total": 2}},
                "k3d-manager-v9.9.9", "2026-09-16")
    path = tmp_path / "bug.md"
    path.write_text(text)
    assert "sentinel-secret" not in text
    assert _status(path).startswith("OPEN")


def test_template_only_names_bug_docs_path():
    assert Path("docs/bugs/2026-09-16-e2e-contract-drift-api-cart.md").parent == Path("docs/bugs")


def _git(*args, cwd):
    subprocess.run(["git", *args], cwd=str(cwd), check=True,
                   capture_output=True, text=True, timeout=120)


def _repo(tmp_path, branch="k3d-manager-v9.9.9"):
    origin, clone = tmp_path / "origin.git", tmp_path / "clone"
    subprocess.run(["git", "init", "--bare", "-b", branch, str(origin)], check=True,
                   capture_output=True, timeout=120)
    subprocess.run(["git", "clone", str(origin), str(clone)], check=True,
                   capture_output=True, timeout=120)
    _git("config", "user.email", "hermes@example.invalid", cwd=clone)
    _git("config", "user.name", "hermes", cwd=clone)
    _git("checkout", "-b", branch, cwd=clone)
    (clone / "docs/bugs").mkdir(parents=True)
    (clone / "docs/bugs/.keep").write_text("")
    _git("add", "--", "docs/bugs/.keep", cwd=clone)
    _git("commit", "--no-verify", "-m", "seed", cwd=clone)
    _git("push", "origin", f"HEAD:refs/heads/{branch}", cwd=clone)
    return origin, clone


def _file(clone, tmp_path, status="created", slot="2026-09-16"):
    return e2e_bugs.file_bugs(clone, [group()], {"run_id": "r1", "summary": {}}, slot,
                              hermes_root=tmp_path / "hermes")


def test_new_group_is_committed_and_pushed_only_under_docs_bugs(tmp_path):
    origin, clone = _repo(tmp_path)
    result = _file(clone, tmp_path)
    assert result["groups"][0]["status"] == "created"
    assert result["push"].startswith("pushed")
    listing = subprocess.run(["git", "-C", str(origin), "show", "--name-only", "--format=", "HEAD"],
                             capture_output=True, text=True, check=True, timeout=120).stdout.split()
    assert listing == ["docs/bugs/2026-09-16-e2e-contract-drift-api-cart.md"]


def test_existing_open_group_is_ongoing_without_a_commit(tmp_path):
    origin, clone = _repo(tmp_path)
    _file(clone, tmp_path)
    before = subprocess.run(["git", "-C", str(origin), "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True, timeout=120).stdout
    result = _file(clone, tmp_path, slot="2026-09-19")
    after = subprocess.run(["git", "-C", str(origin), "rev-parse", "HEAD"],
                           capture_output=True, text=True, check=True, timeout=120).stdout
    assert result["groups"][0]["status"] == "ongoing"
    assert result["push"] == "no changes"
    assert before == after


def test_fixed_group_is_reopened_in_the_same_file(tmp_path):
    origin, clone = _repo(tmp_path)
    _file(clone, tmp_path)
    worktree = tmp_path / "hermes/bugs-worktree"
    doc = worktree / "docs/bugs/2026-09-16-e2e-contract-drift-api-cart.md"
    doc.write_text(doc.read_text().replace("**Status:** OPEN", "**Status:** FIXED"))
    _git("add", "--", "docs/bugs", cwd=worktree)
    _git("-c", "user.email=h@example.invalid", "-c", "user.name=h", "commit",
         "--no-verify", "-m", "fixed", cwd=worktree)
    _git("push", "origin", "HEAD:refs/heads/k3d-manager-v9.9.9", cwd=worktree)
    result = _file(clone, tmp_path, slot="2026-09-19")
    assert result["groups"][0]["status"] == "reopened"
    assert result["groups"][0]["path"] == "docs/bugs/2026-09-16-e2e-contract-drift-api-cart.md"
    text = (worktree / result["groups"][0]["path"]).read_text()
    assert "**Status:** REOPENED 2026-09-19" in text
    assert "## Recurrence 2026-09-19" in text
    assert len(list((worktree / "docs/bugs").glob("*-e2e-contract-drift-api-cart.md"))) == 1


def test_non_release_branch_files_nothing(tmp_path):
    origin, clone = _repo(tmp_path, branch="main")
    result = _file(clone, tmp_path)
    assert result["groups"] == []
    assert result["push"] == "bugs not filed: repo not on a release branch"
    assert not (tmp_path / "hermes/bugs-worktree").exists()


def test_worktree_is_never_the_operator_checkout(tmp_path):
    origin, clone = _repo(tmp_path)
    _file(clone, tmp_path)
    worktree = tmp_path / "hermes/bugs-worktree"
    assert worktree.resolve() != clone.resolve()
    assert not (clone / "docs/bugs/2026-09-16-e2e-contract-drift-api-cart.md").exists()
