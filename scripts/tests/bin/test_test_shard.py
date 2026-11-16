"""Offline contract for CI shard selection and execution."""
import os
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
DIRS = ("lib", "core", "plugins", "etc", "bin")


def run_make(root, target, shard, home):
    assert home.is_dir() and home != Path.home()
    env = os.environ.copy()
    env["HOME"] = str(home)
    env.setdefault("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    return subprocess.run(["make", "--no-print-directory", target, f"SHARD={shard}"],
                          cwd=root, env=env, text=True, capture_output=True)


def lists(root, home):
    result = []
    for i in range(1, 5):
        proc = run_make(root, "test-shard-list", f"{i}/4", home)
        assert proc.returncode == 0, proc.stderr
        result.extend(proc.stdout.splitlines())
    return result


def serial_files(root):
    return sorted(str(p.relative_to(root)) for d in DIRS
                  for p in (root / "scripts/tests" / d).glob("*.bats") if p.is_file())


def fake_tree(tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    assert root != ROOT and root.parent == tmp_path
    shutil.copy(ROOT / "Makefile", root / "Makefile")
    for directory in DIRS:
        (root / "scripts/tests" / directory).mkdir(parents=True, exist_ok=True)
    (root / "scripts/ci").mkdir(parents=True)
    helper = ROOT / "scripts/ci/test_shard.sh"
    if helper.exists():
        shutil.copy(helper, root / "scripts/ci/test_shard.sh")
    shutil.copy(ROOT / "scripts/tests/tripwire.sh", root / "scripts/tests/tripwire-real.sh")
    tripwire = root / "scripts/tests/tripwire.sh"
    tripwire.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> tripwire-calls\n'
                        'exec scripts/tests/tripwire-real.sh "$@"\n')
    tripwire.chmod(0o755)
    dispatcher = root / "scripts/k3d-manager"
    dispatcher.write_text('#!/usr/bin/env bash\nset -eu\n[ "$1" = test ]\nexec bats "scripts/tests/$2"\n')
    dispatcher.chmod(0o755)
    home = tmp_path / "home"
    home.mkdir()
    return root, home


def test_e1_union_additions_and_determinism(tmp_path):
    root, home = fake_tree(tmp_path)
    for directory in DIRS:
        (root / "scripts/tests" / directory / f"{directory}.bats").write_text("#!/usr/bin/env bats\n")
    first = lists(root, home)
    assert first == lists(root, home)
    assert Counter(first) == Counter(serial_files(root))
    for directory in ("bin", "plugins"):
        (root / "scripts/tests" / directory / "new.bats").write_text("#!/usr/bin/env bats\n")
    actual = lists(root, home)
    assert Counter(actual) == Counter(serial_files(root))
    assert all(count == 1 for count in Counter(actual).values())
    assert Counter(lists(ROOT, home)) == Counter(serial_files(ROOT))


def test_e2_failure_propagates_and_pass_control(tmp_path):
    root, home = fake_tree(tmp_path)
    for directory in ("lib", "bin"):
        (root / "scripts/tests" / directory / f"{directory}.bats").write_text(
            '#!/usr/bin/env bats\n@test "passes" { true; }\n')
    passing = [run_make(root, "test-shard", f"{i}/4", home) for i in range(1, 5)]
    assert all(p.returncode == 0 for p in passing), [p.stderr for p in passing]
    calls = (root / "tripwire-calls").read_text().splitlines()
    assert "./scripts/k3d-manager test lib/lib.bats" in calls
    assert "bats scripts/tests/bin/bin.bats" in calls
    failing = root / "scripts/tests/bin/bin.bats"
    failing.write_text('#!/usr/bin/env bats\n@test "fails" { false; }\n')
    outcomes = [run_make(root, "test-shard", f"{i}/4", home) for i in range(1, 5)]
    assert sum(p.returncode != 0 for p in outcomes) == 1
    assert sum(p.returncode == 0 for p in outcomes) == 3
    assert any("not ok" in p.stdout for p in outcomes)


def test_e3_workflow_contract():
    workflow = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
    jobs = workflow["jobs"]
    lint, test, python = (jobs[name] for name in ("lint", "test", "test-python"))
    def commands(job):
        return "\n".join(step.get("run", "") for step in job["steps"])
    assert "make test" not in commands(lint)
    for command in ("shellcheck", "bash -n", "yamllint", "make lint-python", "make validate-manifests"):
        assert command in commands(lint)
    assert test["strategy"]["fail-fast"] is False
    assert test["strategy"]["matrix"]["shard"] == [1, 2, 3, 4]
    assert "make test-shard SHARD=${{ matrix.shard }}/4" in commands(test)
    assert "make test-python-unit" in commands(python)
    assert "make test-pytest" in commands(python)
    for job in (test, python):
        assert job["if"] == lint["if"] and job["runs-on"] == lint["runs-on"]
        assert job.get("permissions", workflow["permissions"]) == {"contents": "read"}
        steps = job["steps"]
        assert not job.get("continue-on-error", False)
        assert all(not step.get("continue-on-error", False) for step in steps)
        assert "_install_promtool" in commands(job)
        assert "pytest==9.1.1 ruff==0.15.8" in commands(job)
        assert any(step.get("uses") == "./.github/actions/setup" for step in steps)
        assert any(step.get("name") == "Install Copilot CLI" for step in steps)
        envs = [step.get("env", {}) for step in steps]
        assert any(env.get("COPILOT_GITHUB_TOKEN") == "${{ secrets.COPILOT_TOKEN }}"
                   and env.get("K3DM_ENABLE_AI") == "1"
                   and env.get("K3DM_COPILOT_LIVE_TESTS") == "1" for env in envs)
