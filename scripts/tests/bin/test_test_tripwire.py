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
