import importlib.util
import json
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_loader(
    "hermes_e2e_text", SourceFileLoader("hermes_e2e_text", str(ROOT / "bin/k3dm-hermes")))
hermes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hermes)


# Captured from ~/.k3dm/e2e/dispatch/m2-20261107T113949Z.summary.json on the M5,
# 2026-11-07 (reported in docs/bugs/2026-11-07-hermes-e2e-summary-crashes-on-null-counts.md).
NULL_COUNTS = {
    "candidate_digest": None, "commit": "4f46a677...", "duration_seconds": None,
    "exit_code": 1, "failed": None, "failure_details": [], "failure_groups": [],
    "passed": None, "phase": "deploying-substrate", "project": "api+flows",
    "result": "fail", "run_id": "1794051590-16732", "runner": "m2",
    "service": "product-catalog", "tier": "vcluster",
    "timestamp": "2026-11-07T11:40:39.629001+00:00", "total": None,
}


@pytest.mark.parametrize("summary", [
    NULL_COUNTS,
    {"passed": None, "failed": 2, "total": 3, "result": "fail"},
    {"passed": 1, "failed": None, "total": 3, "result": "fail"},
    {"passed": 1, "failed": 1, "total": None, "result": "fail"},
    {"result": "fail"},
])
def test_e2e_text_handles_null_or_missing_counts(summary):
    assert "FAIL" in hermes._e2e_text("slot", "run", summary, {}, {"resolved": []})


def test_e2e_text_zero_counts_names_failure_phase():
    text = hermes._e2e_text("slot", "run", NULL_COUNTS, {}, {"resolved": []})
    assert text.splitlines()[0] == "Hermes e2e slot (run run, M2): FAIL — before tests (phase deploying-substrate)"


def test_e2e_text_real_counts_keep_existing_wording():
    filed = {}
    changes = {"resolved": []}
    failed = {"passed": 3, "failed": 1, "total": 5, "result": "fail"}
    passed = {"passed": 5, "failed": 0, "total": 5, "result": "pass"}
    assert hermes._e2e_text("slot", "run", failed, filed, changes).splitlines()[0].endswith(
        "FAIL — 3 passed, 1 failed, 1 skipped")
    assert hermes._e2e_text("slot", "run", passed, filed, changes).splitlines()[0].endswith("PASS 5/5")


def test_run_e2e_records_null_counts_and_posts_once(tmp_path, monkeypatch):
    home = tmp_path / "scratch-home"
    e2e_dir = tmp_path / "hermes-e2e"
    dispatch_dir = tmp_path / "dispatch"
    home.mkdir()
    dispatch_dir.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("K3DM_HERMES_E2E_DIR", str(e2e_dir))
    monkeypatch.setenv("K3DM_E2E_DISPATCH_DIR", str(dispatch_dir))
    assert Path.home() == home
    assert hermes._e2e_dir() == e2e_dir
    summary_path = dispatch_dir / "m2-test.summary.json"
    summary_path.write_text(json.dumps(NULL_COUNTS))
    summary_path.with_name("m2-test.failures.json").write_text("[]")
    posted = []
    monkeypatch.setattr(hermes, "_keychain_secret", lambda _key: "stub-relay")
    monkeypatch.setattr(hermes, "post_summary", lambda relay, text: posted.append((relay, text)))
    monkeypatch.setattr(hermes.e2e_triage, "triage", lambda *_args: [])
    monkeypatch.setattr(hermes.e2e_bugs, "file_bugs", lambda *_args: {})
    monkeypatch.setattr(hermes, "_e2e_results", lambda _started: (NULL_COUNTS, []))

    calls = []

    def runner(argv, _timeout):
        calls.append(argv)
        return (0, "") if len(calls) == 1 else (1, "dispatch failed")

    assert hermes._run_e2e("slot", runner=runner, now=1794051590) == 0
    record = json.loads((e2e_dir / "slot.json").read_text())
    assert record["outcome"] == "fail"
    assert record["counts"] == {"passed": 0, "failed": 0, "total": 0}
    assert len(posted) == 1
    assert "FAIL — before tests (phase deploying-substrate)" in posted[0][1]
