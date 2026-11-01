import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]


def _run_target(tmp_path, *make_args):
    root = tmp_path / "repo"
    (root / "scripts").mkdir(parents=True)
    shutil.copy(REPO / "Makefile", root / "Makefile")
    stub = root / "scripts" / "find-similar-docs.py"
    stub.write_text("import sys\nprint(repr(sys.argv[1:]))\n")
    assert root.resolve() != REPO.resolve()
    assert stub.resolve().is_relative_to(tmp_path.resolve())
    env = {k: v for k, v in os.environ.items() if k not in ("Q", "K", "Q_B64", "MAKEFLAGS")}
    return subprocess.run(["make", "-s", "-C", str(root), "find-similar-docs", *make_args],
                          capture_output=True, text=True, env=env, timeout=60)


def test_k_reaches_the_script_as_separate_option_and_value(tmp_path):
    result = _run_target(tmp_path, "Q=rotator not redeployed", "K=10")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "['--k', '10', '--', 'rotator not redeployed']"


def test_without_k_only_the_query_is_passed(tmp_path):
    result = _run_target(tmp_path, "Q=rotator not redeployed")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "['--', 'rotator not redeployed']"


@pytest.mark.skipif(shutil.which("base64") is None, reason="needs base64")
def test_relay_base64_query_with_k(tmp_path):
    q_b64 = subprocess.run(["base64"], input="what's recent e2e issues", capture_output=True, text=True).stdout.strip()
    result = _run_target(tmp_path, f"Q_B64={q_b64}", "K=5")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "['--k', '5', '--', \"what's recent e2e issues\"]"
