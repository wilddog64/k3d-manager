"""The offline test targets cannot reach a real cluster, cloud API or host keychain.

docs/plans/v1.40.0-cloud-bridge-test-targets.md (M2). The cloud bridge exposes make test,
test-bin, test-python and test-all at reader tier, so "the suites are offline" has to be a
property of the targets, not a convention each test is trusted to follow.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
TRIPWIRE = ROOT / "scripts" / "tests" / "tripwire.sh"
REQUIRED_TOOLS = {"kubectl", "helm", "k3d", "docker", "aws", "gcloud", "az", "vault", "argocd",
                  "security", "launchctl", "ssh", "gh"}


def _recipe(target):
    lines = (ROOT / "Makefile").read_text().splitlines()
    start = lines.index(f"{target}:")
    body = []
    for line in lines[start + 1:]:
        if not line.startswith("\t"):
            break
        body.append(line)
    return "\n".join(body)


@pytest.mark.parametrize("target, suite_command", [
    ("test", "./scripts/k3d-manager test all"),
    ("test-bin", "bats scripts/tests/bin"),
    ("test-python-unit", 'python3 "$$f"'),
    ("test-pytest", '"$$@" scripts/tests/hermes'),
])
def test_every_offline_test_recipe_runs_its_suite_through_the_tripwire(target, suite_command):
    recipe = _recipe(target)
    assert f"scripts/tests/tripwire.sh {suite_command}" in recipe, recipe


def test_aggregate_targets_only_compose_tripwired_targets():
    makefile = (ROOT / "Makefile").read_text()
    assert re.search(r"^test-python: test-python-unit test-pytest$", makefile, re.M)
    assert re.search(r"^test-all: test test-bin test-python$", makefile, re.M)
    assert "scripts/tests/tripwire.sh" not in _recipe("test-host")


def test_the_tripwire_covers_the_cluster_cloud_and_credential_tools():
    text = TRIPWIRE.read_text()
    tools = set(re.search(r"TRIPWIRE_TOOLS=\(([^)]*)\)", text).group(1).split())
    assert REQUIRED_TOOLS <= tools


@pytest.fixture
def real_tools(tmp_path):
    """A stand-in for the host's real binaries: each writes a marker if it ever runs."""
    real = tmp_path / "real"
    real.mkdir()
    marker = tmp_path / "reached-real-binary"
    for tool in ("kubectl", "security", "gh"):
        path = real / tool
        path.write_text(f'#!/bin/sh\necho "{tool} $*" >> "{marker}"\necho real-{tool}\n')
        path.chmod(0o755)
    return {"path": f"{real}{os.pathsep}{os.environ['PATH']}", "marker": marker}


def _tripwire(command, real_tools):
    return subprocess.run([str(TRIPWIRE), "bash", "-c", command], cwd=ROOT,
                          env={**os.environ, "PATH": real_tools["path"]},
                          capture_output=True, text=True, timeout=60, check=False)


def test_a_mutating_call_is_blocked_and_fails_the_run_even_when_the_command_passes(real_tools):
    result = _tripwire("kubectl --context hub -n identity delete pod keycloak-0; exit 0", real_tools)
    assert result.returncode != 0
    assert "FAIL" in result.stderr
    assert not real_tools["marker"].exists()


def test_a_blocked_read_is_reported_but_does_not_change_the_exit_code(real_tools):
    result = _tripwire("kubectl --context hub get pods; security find-generic-password -s x -w; exit 0",
                       real_tools)
    assert result.returncode == 0
    assert "blocked 2 call(s)" in result.stderr
    assert not real_tools["marker"].exists()


@pytest.mark.parametrize("command", [
    "kubectl -n secrets get secret vault-root -o jsonpath={.data.root_token}",
    "gh pr merge 1 --squash",
    "security add-generic-password -s x -w y",
])
def test_credential_reads_and_writes_are_not_treated_as_reads(real_tools, command):
    result = _tripwire(f"{command}; exit 0", real_tools)
    assert result.returncode != 0, result.stderr
    assert not real_tools["marker"].exists()


def test_offline_subcommands_pass_through_to_the_real_binary(real_tools):
    result = _tripwire("kubectl kustomize scripts/etc/e2e", real_tools)
    assert result.returncode == 0
    assert result.stdout.strip() == "real-kubectl"
    assert "blocked" not in result.stderr


def test_the_command_exit_code_is_preserved(real_tools):
    assert _tripwire("exit 3", real_tools).returncode == 3


def test_tripwire_leaves_an_absent_tool_absent_and_shims_an_installed_tool(tmp_path):
    real_bin = tmp_path / "real-bin"
    real_bin.mkdir()
    kubectl = real_bin / "kubectl"
    kubectl.write_text("#!/bin/sh\nexit 0\n")
    kubectl.chmod(0o755)
    assert kubectl.is_file()

    system_path = ("/usr/bin", "/bin", "/usr/sbin", "/sbin")
    tools = set(re.search(r"TRIPWIRE_TOOLS=\(([^)]*)\)", TRIPWIRE.read_text()).group(1).split())
    missing_tool = next(
        tool for tool in tools - {"kubectl"}
        if not any((Path(directory) / tool).is_file() and os.access(Path(directory) / tool, os.X_OK)
                   for directory in system_path)
    )
    path = os.pathsep.join((str(real_bin), *system_path))
    result = subprocess.run(
        [str(TRIPWIRE), "bash", "-c",
         'if command -v "$ABSENT_TOOL" >/dev/null 2>&1; then exit 11; fi; '
         'printf "absent=%s\\nkubectl=%s\\n" "$ABSENT_TOOL" "$(command -v kubectl)"'],
        cwd=ROOT, env={**os.environ, "PATH": path, "ABSENT_TOOL": missing_tool},
        capture_output=True, text=True, timeout=60, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert f"absent={missing_tool}" in result.stdout
    assert "k3dm-tripwire." in result.stdout
    assert str(kubectl) not in result.stdout


@pytest.mark.parametrize("mutation", ["create", "modify", "same-bytes", "remove", "create-dir"])
def test_launch_agent_plist_changes_fail_and_name_the_sentinel(tmp_path, mutation):
    watch = tmp_path / "home" / "Library" / "LaunchAgents"
    watch.mkdir(parents=True)
    target = watch / "com.k3d-manager.fixture.plist"
    if mutation in {"modify", "same-bytes", "remove"}:
        target.write_text("before\n")
    assert watch == tmp_path / "home" / "Library" / "LaunchAgents"
    if mutation == "create-dir":
        watch.rmdir()
    command = {
        "create": f"printf after > '{target}'",
        "modify": f"printf after > '{target}'",
        "same-bytes": f"cat '{target}' > '{target}.tmp' && mv '{target}.tmp' '{target}'",
        "remove": f"rm '{target}'",
        "create-dir": f"mkdir -p '{watch}' && printf after > '{target}'",
    }[mutation]
    result = subprocess.run([str(TRIPWIRE), "bash", "-c", command], cwd=ROOT,
                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(watch)},
                            capture_output=True, text=True, timeout=60, check=False)
    assert result.returncode != 0
    action = {"create": "created", "modify": "modified", "same-bytes": "modified",
              "remove": "removed", "create-dir": "created"}[mutation]
    assert f"[tripwire] FAIL: {target} {action} during the run" in result.stderr


def test_future_mtime_plist_rewrite_is_reported_even_when_it_was_already_newer(tmp_path):
    watch = tmp_path / "home" / "Library" / "LaunchAgents"
    watch.mkdir(parents=True)
    target = watch / "com.k3d-manager.future.plist"
    target.write_text("before\n")
    future_mtime = 2_145_916_800  # 2038-01-01 UTC
    os.utime(target, (future_mtime, future_mtime))
    assert watch == tmp_path / "home" / "Library" / "LaunchAgents"
    assert target.stat().st_mtime > future_mtime - 1
    command = f"printf after > '{target}'; touch -t 203801010000 '{target}'"
    result = subprocess.run([str(TRIPWIRE), "bash", "-c", command], cwd=ROOT,
                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(watch)},
                            capture_output=True, text=True, timeout=60, check=False)
    assert result.returncode != 0
    assert f"[tripwire] FAIL: {target} modified during the run" in result.stderr


def test_launch_agent_watch_is_green_when_unchanged_or_missing(tmp_path):
    missing = tmp_path / "not-created"
    assert not missing.exists()
    env = {**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(missing)}
    result = subprocess.run([str(TRIPWIRE), "bash", "-c", "true"], cwd=ROOT, env=env,
                            capture_output=True, text=True, timeout=60, check=False)
    assert result.returncode == 0
    assert not result.stderr
    assert not missing.exists()
    unchanged = tmp_path / "home" / "Library" / "LaunchAgents"
    unchanged.mkdir(parents=True)
    (unchanged / "com.k3d-manager.fixture.plist").write_text("stable\n")
    result = subprocess.run([str(TRIPWIRE), "bash", "-c", "true"], cwd=ROOT,
                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(unchanged)},
                            capture_output=True, text=True, timeout=60, check=False)
    assert result.returncode == 0
    assert not result.stderr


def test_launch_agent_watch_preserves_nonzero_command_status(tmp_path):
    watch = tmp_path / "home" / "Library" / "LaunchAgents"
    watch.mkdir(parents=True)
    target = watch / "com.k3d-manager.fixture.plist"
    assert watch.is_dir()
    result = subprocess.run([str(TRIPWIRE), "bash", "-c", f"printf x > '{target}'; exit 3"], cwd=ROOT,
                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(watch)},
                            capture_output=True, text=True, timeout=60, check=False)
    assert result.returncode == 3
    assert f"[tripwire] FAIL: {target} created" in result.stderr
