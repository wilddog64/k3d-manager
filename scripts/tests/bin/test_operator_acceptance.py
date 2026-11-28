"""Tests for the isolated operator acceptance runner."""
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import urllib.request
import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from acceptance.runner import REGISTRY, run_scenarios
from acceptance.guard import validate_url


def test_acceptance_runner_writes_secure_reports_and_all_scenarios(tmp_path):
    root = tmp_path / "runs"
    run_dir, report, passed = run_scenarios(root)
    assert passed
    assert report["schema"] == 1
    assert len(report["scenarios"]) == len(REGISTRY) == 9
    assert sum(len(s["assertions"]) for s in report["scenarios"]) > 0
    assert {"report.json", "junit.xml", "report.md", "home", "stubs", "stub.log", "transport.log"}.issubset({p.name for p in run_dir.iterdir()})
    assert not (run_dir / "job").exists()  # agent-audit: allow assert-removed p3d replaced both asserts with stronger ones (job dir must be absent; token scan widened to glsa_ and the returned report)
    assert run_dir.stat().st_mode & 0o777 == 0o700
    for name in ("report.json", "junit.xml", "report.md"):
        assert (run_dir / name).stat().st_mode & 0o777 == 0o600
    for path in run_dir.rglob("*"):
        assert path.stat().st_mode & 0o077 == 0, path
        if path.is_dir():
            assert path.stat().st_mode & 0o777 == 0o700, path
        else:
            assert path.stat().st_mode & 0o777 == 0o600, path
    all_text = "".join(path.read_text(errors="ignore") for path in run_dir.rglob("*") if path.is_file())
    assert all(token not in all_text for token in ("CanarySecret-123", "https://hooks.slack.com/", "xoxb-"))
    assert json.loads((run_dir / "report.json").read_text())["schema"] == 1
    assert {s["id"]: (s["outcome"], s["linked_bug"]) for s in report["scenarios"] if s["outcome"] == "known_failing"} == {
        "metrics-publication-failure": ("known_failing", "docs/bugs/2026-11-26-test-metrics-exporter-exits-zero-when-push-fails.md"),
        "panels-multi-target": ("known_failing", "docs/bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md"),
        "cleanup-ambient-confirm": ("known_failing", "docs/bugs/2026-11-26-stale-sandbox-cleanup-inherits-ambient-confirm.md"),
        "cleanup-vocabulary": ("known_failing", "docs/bugs/2026-11-26-cleanup-stale-sandbox-apply-accepted-by-slash-command-refused-in-thread.md"),
    }


def test_guard_refuses_unsafe_urls_before_child_execution():
    for url in ("http://127.0.0.1:9091", "http://127.0.0.1:19094", "http://127.0.0.1:7443", "http://localhost:9091", "http://192.0.2.1:8000"):
        try:
            validate_url(url)
        except RuntimeError:
            continue
        raise AssertionError(f"accepted unsafe URL {url}")


def test_offline_cli_never_starts_security(tmp_path):
    stub_dir = tmp_path / "path"
    stub_dir.mkdir()
    calls = tmp_path / "security.log"
    security = stub_dir / "security"
    security.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{calls}"\nexit 1\n')
    security.chmod(0o700)
    env = os.environ.copy()
    env["PATH"] = f"{stub_dir}:{env.get('PATH', '/usr/bin:/bin')}"
    run_root = tmp_path / "runs"
    proc = subprocess.run(
        [sys.executable, str(ROOT / "bin/k3dm-operator-acceptance"), "--run-root", str(run_root)],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert not calls.exists()


def test_prior_art_requires_live_without_search(tmp_path):
    from importlib.machinery import SourceFileLoader
    import importlib.util

    loader = SourceFileLoader("operator_acceptance_cli", str(ROOT / "bin/k3dm-operator-acceptance"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    cli = importlib.util.module_from_spec(spec)
    loader.exec_module(cli)
    calls = []
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(cli, "run_scenarios", lambda *_args: (tmp_path, {"scenarios": []}, True))
    monkeypatch.setattr(cli, "process_run_drafts", lambda *_args, **_kwargs: calls.append("search"))
    try:
        try:
            cli.main(["--with-prior-art", "--run-root", str(tmp_path)])
        except SystemExit as exc:
            assert exc.code == 2
        else:
            raise AssertionError("CLI accepted offline --with-prior-art")
    finally:
        monkeypatch.undo()
    assert calls == []

    proc = subprocess.run(
        [sys.executable, str(ROOT / "bin/k3dm-operator-acceptance"), "--with-prior-art", "--run-root", str(tmp_path)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 2
    assert "--with-prior-art requires --live" in proc.stderr


def test_empty_registry_zero_assertions_and_raised_scenario_fail(tmp_path):
    empty_dir, empty, passed = run_scenarios(tmp_path / "empty", registry=[])
    assert not passed and empty["scenarios"] == []
    no_assertions = [("empty-case", [], lambda _ctx: [])]
    _dir, _report, passed = run_scenarios(tmp_path / "zero", registry=no_assertions)
    assert not passed
    raised = [("raise-case", [], lambda _ctx: 1 / 0)]
    _dir, report, passed = run_scenarios(tmp_path / "raise", registry=raised)
    assert not passed and report["scenarios"][0]["outcome"] == "inconclusive"
    _dir, report, passed = run_scenarios(tmp_path / "missing", registry=[REGISTRY[3]], capabilities=[])
    assert not passed
    assert all(s["outcome"] == "inconclusive" for s in report["scenarios"])


def test_report_redacts_all_three_canary_patterns(tmp_path, monkeypatch):
    import acceptance.runner as runner
    planted = "password=CanarySecret-123 https://hooks.slack.com/services/TOKEN xoxb-CanaryToken glsa_CanaryToken RuntimeSecret123"
    monkeypatch.setattr(runner, "REGISTRY", [("canary-test", [], lambda _ctx: [{"name": "secret", "passed": True, "detail": planted}])])
    run_dir, report, passed = runner.run_scenarios(tmp_path, extra_secrets=("RuntimeSecret123",))
    assert passed
    all_text = "".join(p.read_text(errors="ignore") for p in run_dir.rglob("*") if p.is_file())
    assert all(token not in all_text for token in ("CanarySecret-123", "https://hooks.slack.com/", "xoxb-CanaryToken", "glsa_CanaryToken", "RuntimeSecret123"))
    assert all(token not in json.dumps(report) for token in ("CanarySecret-123", "https://hooks.slack.com/", "xoxb-CanaryToken", "glsa_CanaryToken", "RuntimeSecret123"))


def test_parent_environment_sentinels_do_not_change_results(tmp_path, monkeypatch):
    clean_dir, clean, clean_passed = run_scenarios(tmp_path / "clean")
    clean_bytes = (clean_dir / "report.json").read_bytes()
    for key, value in {"CONFIRM": "1", "CLUSTER_PROVIDER": "sentinel", "ACG_KUBE_CONTEXT": "sentinel", "SLACK_BOT_TOKEN": "xoxb-SENTINEL", "SLACK_CHANNEL_ID": "sentinel", "K3DM_PUSHGATEWAY_URL": "http://localhost:9091", "HTTP_PROXY": "http://127.0.0.1:9", "http_proxy": "http://127.0.0.1:9", "NO_PROXY": "", "no_proxy": "", "SLACK_SIGNING_SECRET": "CanarySecret-123"}.items():
        monkeypatch.setenv(key, value)
    monkeypatch.setattr(urllib.request, "_opener", None)
    monkeypatch.setattr(urllib.request, "proxy_bypass", lambda _host: False)
    dirty_dir, dirty, dirty_passed = run_scenarios(tmp_path / "dirty")
    assert clean_passed is True and dirty_passed is True
    dirty_bytes = (dirty_dir / "report.json").read_bytes()
    def normalize(data, run_dir):
        data = re.sub(rb'("(?:started|finished)": )"[^"]+"', rb'\1"<TIMESTAMP>"', data)
        return data.replace(str(run_dir).encode(), b"<RUN_DIR>")
    assert normalize(clean_bytes, clean_dir) == normalize(dirty_bytes, dirty_dir)
    sentinels = ("sentinel", "SENTINEL", "localhost:9091")
    for run_dir in (clean_dir, dirty_dir):
        for path in run_dir.rglob("*"):
            if path.is_file():
                raw = path.read_bytes()
                assert not any(token.encode() in raw for token in sentinels), path
    assert "transport.log" in {p.name for p in clean_dir.iterdir()}


def test_retention_only_deletes_matching_run_directories(tmp_path, monkeypatch):
    import acceptance.runner as runner
    root = tmp_path / "root"
    root.mkdir()
    matching = root / "20200101T000000Z-0123abcd"
    matching.mkdir()
    (matching / "old").write_text("old")
    os.utime(matching, (1, 1))
    sibling = root / "notes.txt"
    sibling.write_text("keep")
    other = root / "not-a-run"
    other.mkdir()
    (other / "keep").write_text("keep")
    monkeypatch.setenv("K3DM_ACCEPTANCE_RETENTION_DAYS", "1")
    runner._retention(root)
    assert not matching.exists()
    assert sibling.exists() and other.exists() and (other / "keep").exists()
