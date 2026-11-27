"""Job output acceptance scenario."""
import importlib.util
import json
import sys
import tempfile
import os
from pathlib import Path
from importlib.machinery import SourceFileLoader
from .k3dm_tests import ROOT, _assert
sys.path.insert(0, str(ROOT / "scripts/lib"))
from webhook.job_output import read_job_output


def run_job(ctx):
    job_root = tempfile.TemporaryDirectory(prefix="k3dm-acceptance-job-")
    job = Path(job_root.name) / "job"
    job.mkdir()
    (job / "target").write_text("test-all")
    (job / "status").write_text("failed")
    (job / "exit_code").write_text("7")
    (job / "make.log").write_text("not ok 2 failing assertion\n" + "noise\n" * 900 + "final-tail\npassword=CanarySecret-123\n")
    text = read_job_output(job, max_chars=2000)
    passed = "not ok 2 failing assertion" in text and "final-tail" in text and "CanarySecret-123" not in text
    old_env = {key: os.environ.get(key) for key in ("SLACK_SIGNING_SECRET", "K3DM_SLACK_ROLE_MAP")}
    os.environ["SLACK_SIGNING_SECRET"] = "acceptance-placeholder"
    os.environ["K3DM_SLACK_ROLE_MAP"] = "acceptance-placeholder"
    try:
        loader = SourceFileLoader("acceptance_webhook", str(ROOT / "bin/k3dm-webhook"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        webhook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(webhook)
    finally:
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    original = (webhook.JOB_DIR, webhook._safe_job_dir, webhook._rate_limited, webhook._request_role)
    response = {}

    class FakeHandler:
        path = "/api/v1/status/a1b2c3f0"
        headers = {"Authorization": "Bearer fixture"}
        _token_role = "reader"

        def _auth(self):
            return True

        def _json(self, code, body):
            response.update(code=code, body=body)

    try:
        webhook.JOB_DIR = ctx.run_dir
        webhook._safe_job_dir = lambda _job_id: job
        webhook._rate_limited = lambda _key: False
        webhook._request_role = lambda *_args: "reader"
        webhook._Handler.do_GET(FakeHandler())
    finally:
        (webhook.JOB_DIR, webhook._safe_job_dir,
         webhook._rate_limited, webhook._request_role) = original
    payload = response.get("body", {})
    status_ok = (response.get("code") == 200 and payload.get("exit_code") == 7
                 and payload.get("status") == "failed"
                 and payload.get("result_classification") == "failed_untriaged")
    output = payload.get("output", "")
    output_ok = "not ok 2 failing assertion" in output and "final-tail" in output and "CanarySecret-123" not in output
    job_root.cleanup()
    return [_assert("status API reports exit code 7 and failed classification", status_ok, json.dumps(payload)),
            _assert("status API retains failure and tail while redacting canary", output_ok, output[-100:]),
            _assert("bounded output retains failure and final tail, redacts canary", passed, text[-100:])]
