"""Hermes status publication reports why it failed instead of failing silently."""

import importlib.machinery
import importlib.util
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[3]
loader = importlib.machinery.SourceFileLoader("k3dm_hermes_publish", str(ROOT / "bin" / "k3dm-hermes"))
spec = importlib.util.spec_from_loader("k3dm_hermes_publish", loader)
hermes = importlib.util.module_from_spec(spec)
loader.exec_module(hermes)

RECORDS = [{"sensor": "eso", "status": "healthy"}]


def _runner(fail_at=None, stderr="", exc=None):
    steps = []

    def run(cmd, **_kwargs):
        step = "create" if "create" in cmd else "apply" if "apply" in cmd else "label"
        steps.append(step)
        if exc is not None:
            raise exc
        rc = 1 if step == fail_at else 0
        out = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: hermes-status\n" if step == "create" else ""
        return SimpleNamespace(returncode=rc, stdout=out, stderr=stderr if rc else "")
    return steps, run


def test_success_publishes_and_logs_nothing(monkeypatch, capsys):
    steps, run = _runner()
    monkeypatch.setattr(hermes.subprocess, "run", run)
    assert hermes._publish_status(RECORDS, {}) is True
    assert steps == ["create", "apply", "label"]
    assert capsys.readouterr().err == ""


@pytest.mark.parametrize("step", ["create", "apply", "label"])
def test_each_failing_step_is_named_with_kubectl_stderr(monkeypatch, capsys, step):
    _steps, run = _runner(fail_at=step, stderr='error: context "k3d-k3d-cluster" does not exist')
    monkeypatch.setattr(hermes.subprocess, "run", run)
    assert hermes._publish_status(RECORDS, {}) is False
    err = capsys.readouterr().err
    assert f"status publish failed at {step}" in err
    assert 'context "k3d-k3d-cluster" does not exist' in err
    assert "bytes=" in err


def test_missing_kubectl_is_reported(monkeypatch, capsys):
    _steps, run = _runner(exc=FileNotFoundError(2, "No such file or directory", "kubectl"))
    monkeypatch.setattr(hermes.subprocess, "run", run)
    assert hermes._publish_status(RECORDS, {}) is False
    err = capsys.readouterr().err
    assert "status publish failed at exec" in err and "FileNotFoundError" in err and "kubectl" in err


def test_logged_detail_is_scrubbed_and_bounded(monkeypatch, capsys):
    _steps, run = _runner(fail_at="apply", stderr="Authorization: Bearer hermes-synthetic-token " + "x" * 2000)
    monkeypatch.setattr(hermes.subprocess, "run", run)
    hermes._publish_status(RECORDS, {})
    err = capsys.readouterr().err
    assert "hermes-synthetic-token" not in err
    assert len(err) < 700


def test_disabled_or_empty_records_skip_quietly(monkeypatch, capsys):
    monkeypatch.setattr(hermes.subprocess, "run", lambda *a, **k: pytest.fail("must not run kubectl"))
    assert hermes._publish_status([], {}) is False
    monkeypatch.setenv("K3DM_HERMES_PUBLISH_STATUS", "0")
    assert hermes._publish_status(RECORDS, {}) is False
    assert capsys.readouterr().err == ""
