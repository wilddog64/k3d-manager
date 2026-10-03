import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def _note(job, signature):
    job.mkdir(parents=True)
    (job / "failure.md").write_text(
        f"# Job failure\n\n**Date:** 2026-10-03  **Target:** make fix-list  **Result:** failed (rc 1)\n"
        f"**Signature:** {signature}\n\n## Error\n\nboom\n\n## Fix\n\n(unknown)\n")


def test_harvest_is_idempotent_and_deduplicates(tmp_path):
    jobs = tmp_path / "jobs"
    docs = tmp_path / "docs"
    _note(jobs / "abcd1234", "make fix-list: boom")
    env = {**os.environ, "K3DM_JOB_DIR": str(jobs), "K3DM_FAILURE_DOCS_DIR": str(docs)}
    script = ROOT / "bin/k3dm-harvest-job-failures"
    subprocess.run([sys.executable, str(script)], env=env, check=True, capture_output=True, text=True)
    _note(jobs / "feedface", "make fix-list: boom")
    subprocess.run([sys.executable, str(script)], env=env, check=True, capture_output=True, text=True)
    assert len(list(docs.glob("*.md"))) == 1
    assert "feedface" in next(docs.glob("*.md")).read_text()
