"""Cluster diagnostic Slack reports retain their webhook job identifier."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import status  # noqa: E402


@pytest.mark.parametrize(
    ("exit_code", "output", "timed_out", "expected_status"),
    [
        (0, "pods ready", False, "success"),
        (2, "kubectl failed", False, "failed"),
        (None, "", True, "failed"),
    ],
    ids=["success", "command-failure", "timeout"],
)
def test_diagnostic_report_contains_job_id(
    tmp_path, monkeypatch, exit_code, output, timed_out, expected_status
):
    job_id = "diag-job-1234"
    (tmp_path / job_id).mkdir()
    posted = []

    monkeypatch.setattr(status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(
        status,
        "_posix_spawn_capture",
        lambda _cmd, **_kwargs: (exit_code, output, timed_out),
    )
    monkeypatch.setattr(status, "_redact_secrets", lambda text: text)
    monkeypatch.setattr(status, "scrub_credentials", lambda text: text)
    monkeypatch.setattr(
        status,
        "_post_status_report",
        lambda job_dir, response_url, text, channel_id, thread_ts: (
            posted.append((job_dir, response_url, text, channel_id, thread_ts)) or True
        ),
    )

    status._run_cluster_diagnostics(
        job_id,
        "https://example.test/response",
        channel_id="C123",
        thread_ts="123.456",
        request={"action": "get-pods", "context": "ubuntu-k3s", "namespace": "default"},
    )

    assert (tmp_path / job_id / "status").read_text() == expected_status
    assert len(posted) == 1
    report = posted[0][2]
    assert report.splitlines()[1] == "_Job: `diag-job-1234`_"
    assert posted[0][1] == "https://example.test/response"
    assert posted[0][3:] == ("C123", "123.456")
