"""Contract tests for the agent instruction drift check."""
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
CHECK = ROOT / 'bin/k3dm-check-agent-docs'


@pytest.fixture
def scratch(tmp_path):
    root = tmp_path / 'repo'
    root.mkdir()
    assert root.resolve() != ROOT.resolve() and tmp_path in root.parents
    for name in ('CLAUDE.md', 'AGENTS.md', 'GEMINI.md'):
        shutil.copy(ROOT / name, root / name)
    for name in ('scripts', 'docs', 'memory-bank'):
        (root / name).mkdir()
    (root / 'docs/plans').mkdir()
    (root / 'docs/bugs').mkdir()
    (root / 'docs/roadmap.md').touch()
    (root / 'scripts/lib').mkdir()
    (root / 'scripts/lib/system.sh').touch()
    return root


def run(root):
    return subprocess.run([str(CHECK), str(root)], capture_output=True, text=True)


def test_valid_blocks_and_paths(scratch):
    result = run(scratch)
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize('mutation', ['plan-cap', 'bug-priority', 'security', 'missing', 'path', 'bind', 'commit'])
def test_rejects_drift(scratch, mutation):
    target = scratch / 'AGENTS.md'
    assert target.resolve().is_relative_to(scratch.resolve())
    text = target.read_text()
    if mutation in ('plan-cap', 'bug-priority', 'security'):
        marker = f'<!-- shared:begin {mutation} -->'
        pos = text.index(marker) + len(marker)
        pos = text.index('\n', pos) + 1
        text = text[:pos] + ('x' if text[pos] != 'x' else 'y') + text[pos + 1:]
    elif mutation == 'missing':
        text = text.replace('<!-- shared:begin security -->', '', 1)
    elif mutation == 'path':
        text += '\n`scripts/does-not-exist`\n'
    elif mutation == 'bind':
        text += '\nBind 0.0.0.0:1234.\n'
    else:
        text += '\nCommit and push the work.\n'
    target.write_text(text)
    result = run(scratch)
    assert result.returncode != 0, result.stdout
