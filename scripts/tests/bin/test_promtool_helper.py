"""Contract tests for shared promtool resolution."""

from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from promtool_helper import resolve_promtool


def _fake_promtool(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o755)
    return path


def test_configured_promtool_precedes_home_and_path(monkeypatch, tmp_path):
    home = tmp_path / "home"
    configured = _fake_promtool(tmp_path / "configured" / "promtool")
    _fake_promtool(home / ".local/bin/promtool")
    path_bin = tmp_path / "path-bin"
    _fake_promtool(path_bin / "promtool")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("PROMTOOL", str(configured))
    monkeypatch.setenv("PATH", str(path_bin))
    assert resolve_promtool() == str(configured)


def test_home_promtool_precedes_path_when_unconfigured(monkeypatch, tmp_path):
    home = tmp_path / "home"
    home_promtool = _fake_promtool(home / ".local/bin/promtool")
    path_bin = tmp_path / "path-bin"
    _fake_promtool(path_bin / "promtool")
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("PROMTOOL", raising=False)
    monkeypatch.setenv("PATH", str(path_bin))
    assert resolve_promtool() == str(home_promtool)


def test_path_promtool_is_used_as_last_fallback(monkeypatch, tmp_path):
    home = tmp_path / "scratch-home"
    path_bin = tmp_path / "path-bin"
    path_promtool = _fake_promtool(path_bin / "promtool")
    home.mkdir()
    assert home != Path.home()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("PROMTOOL", raising=False)
    monkeypatch.setenv("PATH", str(path_bin))
    assert resolve_promtool() == str(path_promtool)


def test_missing_promtool_fails_with_machine_setup_instruction(monkeypatch, tmp_path):
    home = tmp_path / "scratch-home"
    empty_path = tmp_path / "empty-path"
    home.mkdir()
    empty_path.mkdir()
    assert home != Path.home()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("PROMTOOL", raising=False)
    monkeypatch.setenv("PATH", str(empty_path))
    with pytest.raises(RuntimeError, match="promtool not found; run make machine-setup \\(installs promtool 3\\.1\\.0\\)"):
        resolve_promtool()
