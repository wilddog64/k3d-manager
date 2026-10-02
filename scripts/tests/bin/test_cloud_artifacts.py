"""Cloud-request diagnostic artifacts, exercised through real git repositories.

docs/plans/v1.40.0-cloud-request-artifacts.md (M5 gates)
"""

import importlib.machinery
import importlib.util
import json
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
LOADER = importlib.machinery.SourceFileLoader("cloud_bridge_artifacts", str(ROOT / "bin" / "k3dm-cloud-bridge"))
SPEC = importlib.util.spec_from_loader("cloud_bridge_artifacts", LOADER)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

JOB_ID = "abcd1234"
SYNTHETIC_BEARER = "Bearer synthetic0token0value0for0artifact0gate"
SYNTHETIC_STRIPE = "sk_test_synthetic0artifact0gate0value"


def _git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def _request_id(index, action="job-status"):
    return f"20261001T{index:06d}Z-{action}"


def _request(action="job-status", args=None):
    now = datetime.now(timezone.utc)
    return {
        "schema": 1,
        "action": action,
        "args": {"job_id": JOB_ID} if args is None else args,
        "requested_by": "claude-cloud",
        "requested_at": now.isoformat().replace("+00:00", "Z"),
        "expires_at": (now + timedelta(minutes=30)).isoformat().replace("+00:00", "Z"),
    }


@pytest.fixture
def repos(tmp_path):
    origin = tmp_path / "origin.git"
    _git(tmp_path, "init", "-q", "--bare", str(origin))
    work = tmp_path / "work"
    _git(tmp_path, "init", "-q", "-b", "cloud-requests", str(work))
    _git(work, "config", "user.email", "test@example.invalid")
    _git(work, "config", "user.name", "test")
    (work / "ledger").mkdir()
    (work / "ledger" / "processed.txt").write_text("")
    _git(work, "add", ".")
    _git(work, "commit", "-q", "-m", "seed")
    _git(work, "remote", "add", "origin", str(origin))
    _git(work, "push", "-q", "origin", "cloud-requests")
    repo = tmp_path / "bridge.git"
    _git(tmp_path, "clone", "-q", "--bare", str(origin), str(repo))
    return {"origin": origin, "work": work, "repo": repo}


@pytest.fixture
def job_dir(tmp_path, monkeypatch):
    jobs = tmp_path / "jobs"
    (jobs / JOB_ID).mkdir(parents=True)
    monkeypatch.setattr(bridge.webhook_config, "JOB_DIR", jobs)
    (jobs / JOB_ID / "target").write_text("test-pytest")
    return jobs / JOB_ID


def _file_request(repos, request_id, payload):
    work = repos["work"]
    _git(work, "pull", "-q", "origin", "cloud-requests")
    (work / "requests").mkdir(exist_ok=True)
    (work / "requests" / f"{request_id}.json").write_text(json.dumps(payload))
    _git(work, "add", ".")
    _git(work, "commit", "-q", "-m", request_id)
    _git(work, "push", "-q", "origin", "cloud-requests")


def _tick(repos, monkeypatch, job_status):
    def fake_webhook(request):
        return bridge._response("", request["action"], "ok", 200,
                                body={"job_id": JOB_ID, "status": job_status, "output": "tail"})

    monkeypatch.setattr(bridge, "_call_webhook", fake_webhook)
    bridge.process_tick(repos["repo"], ROOT)


def _response(repos, request_id):
    return json.loads(_git(repos["origin"], "show", f"cloud-requests:responses/{request_id}.json"))


def _tree(repos):
    return _git(repos["origin"], "ls-tree", "-r", "--name-only", "cloud-requests").splitlines()


def _junit(job_dir, message="assert 1 == 2"):
    (job_dir / "junit.xml").write_text(
        '<?xml version="1.0"?><testsuites><testsuite name="pytest" failures="1">'
        f'<testcase name="test_x"><failure message="{message}">{message}</failure></testcase>'
        "</testsuite></testsuites>\n")


@pytest.mark.parametrize("job_status", ["queued", "running"])
def test_unfinished_job_writes_no_artifacts_and_omits_the_field(repos, job_dir, monkeypatch, job_status):
    (job_dir / "status").write_text(job_status)
    _junit(job_dir)
    request_id = _request_id(1)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, job_status)

    response = _response(repos, request_id)
    assert "artifacts" not in response
    assert response["status"] == "ok"
    assert not [path for path in _tree(repos) if path.startswith("artifacts/")]


def test_finished_job_publishes_summary_and_junit_in_the_same_commit(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("failed")
    _junit(job_dir)
    request_id = _request_id(2)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, "failed")

    response = _response(repos, request_id)
    assert response["artifacts"] == [
        f"artifacts/{request_id}/junit.xml",
        f"artifacts/{request_id}/summary.json",
    ]
    tree = _tree(repos)
    for path in response["artifacts"]:
        assert path in tree
    summary = json.loads(_git(repos["origin"], "show", f"cloud-requests:artifacts/{request_id}/summary.json"))
    assert summary["job_id"] == JOB_ID
    assert summary["job_status"] == "failed"
    assert summary["request_id"] == request_id
    assert summary["target"] == "test-pytest"
    assert "exit_code" not in summary
    assert "assert 1 == 2" in _git(repos["origin"], "show", f"cloud-requests:artifacts/{request_id}/junit.xml")


def test_missing_junit_report_is_not_an_error(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("success")
    request_id = _request_id(3)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, "success")

    assert _response(repos, request_id)["artifacts"] == [f"artifacts/{request_id}/summary.json"]


def test_later_job_status_relists_existing_artifacts_without_rewriting(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("success")
    first, second = _request_id(4), _request_id(5)
    _file_request(repos, first, _request())
    _tick(repos, monkeypatch, "success")
    _file_request(repos, second, _request())
    _tick(repos, monkeypatch, "success")

    assert _response(repos, second)["artifacts"] == [f"artifacts/{first}/summary.json"]
    assert not [path for path in _tree(repos) if path.startswith(f"artifacts/{second}/")]


def test_no_credential_shape_reaches_an_artifact(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("failed")
    _junit(job_dir, message=f"assert {SYNTHETIC_BEARER!r} == {SYNTHETIC_STRIPE!r}")
    request_id = _request_id(6)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, "failed")

    for path in _tree(repos):
        blob = _git(repos["origin"], "show", f"cloud-requests:{path}")
        assert "synthetic0token0value" not in blob, path
        assert SYNTHETIC_STRIPE not in blob, path
    assert "***REDACTED***" in _git(repos["origin"], "show", f"cloud-requests:artifacts/{request_id}/junit.xml")


def test_prune_keeps_exactly_the_window_and_drops_the_oldest(repos, job_dir, monkeypatch):
    monkeypatch.setattr(bridge, "ARTIFACT_KEEP", 2)
    (job_dir / "status").write_text("success")
    ids = [_request_id(10 + index) for index in range(3)]
    for index, request_id in enumerate(ids):
        job_id = f"abcd123{index + 5}"
        (job_dir.parent / job_id).mkdir()
        (job_dir.parent / job_id / "status").write_text("success")
        _file_request(repos, request_id, _request(args={"job_id": job_id}))
        _tick(repos, monkeypatch, "success")

    remaining = sorted({path.split("/")[1] for path in _tree(repos) if path.startswith("artifacts/")})
    assert remaining == ids[1:]


def test_response_status_vocabulary_and_field_names_are_unchanged(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("failed")
    request_id = _request_id(20)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, "failed")

    response = _response(repos, request_id)
    assert response["status"] in ("ok", "rejected", "error")
    assert "http_status" in response
    assert set(response) == {"schema", "id", "action", "status", "http_status", "completed_at",
                             "body", "artifacts"}


def test_output_log_is_never_published(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("failed")
    (job_dir / "output").write_text("full raw job output\n")
    _junit(job_dir)
    request_id = _request_id(21)
    _file_request(repos, request_id, _request())
    _tick(repos, monkeypatch, "failed")

    assert not [path for path in _tree(repos) if path.endswith("output.log")]
    assert not [path for path in _response(repos, request_id)["artifacts"] if "output" in path]


def test_non_job_status_action_never_publishes_artifacts(repos, job_dir, monkeypatch):
    (job_dir / "status").write_text("success")
    request_id = _request_id(22, "cluster-status")
    _file_request(repos, request_id, _request("cluster-status", {}))
    _tick(repos, monkeypatch, "success")

    assert "artifacts" not in _response(repos, request_id)


def test_job_status_output_is_scrubbed_before_it_is_committed(repos, job_dir, monkeypatch):
    def fake_webhook(request):
        return bridge._response("", request["action"], "ok", 200, body={
            "job_id": JOB_ID, "status": "running",
            "output": f"2026-10-01 payment-0 Authorization: {SYNTHETIC_BEARER}\n"})

    (job_dir / "status").write_text("running")
    request_id = _request_id(30)
    _file_request(repos, request_id, _request())
    monkeypatch.setattr(bridge, "_call_webhook", fake_webhook)
    bridge.process_tick(repos["repo"], ROOT)

    committed = _git(repos["origin"], "show", f"cloud-requests:responses/{request_id}.json")
    assert "synthetic0token0value" not in committed
    assert "***REDACTED***" in committed
