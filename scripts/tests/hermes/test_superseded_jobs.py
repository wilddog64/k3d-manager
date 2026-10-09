import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.sensors import superseded_jobs


def pod_spec(image="old", env=None):
    container = {"name": "worker", "image": image, "command": ["run"], "args": ["--once"]}
    if env is not None:
        container["env"] = env
    return {"containers": [container]}


def objects(image="old", job_image="new", active=0, owner=True, cron_exists=True, name="job-1"):
    job = {"metadata": {"name": name}, "spec": {"template": {"spec": pod_spec(job_image)}},
           "status": {"active": active, "conditions": [{"type": "Failed", "status": "True",
                                                            "lastTransitionTime": "2026-10-09T00:00:00Z"}]}}
    if owner:
        job["metadata"]["ownerReferences"] = [{"kind": "CronJob", "name": "nightly", "controller": True}]
    cronjobs = [{"metadata": {"name": "nightly"}, "spec": {"jobTemplate": {"spec": {
        "template": {"spec": pod_spec(image)}}}}}] if cron_exists else []
    return {"items": [job]}, {"items": cronjobs}


def fake_run(job_payload, cron_payload, failures=()):
    calls = []

    def run(argv, _env):
        calls.append(argv)
        namespace = argv[4]
        if namespace in failures:
            return 1, "unavailable"
        return (0, json.dumps(job_payload) if argv[6] == "jobs" else json.dumps(cron_payload))

    return run, calls


def test_failed_changed_image_debounces_and_queries_only_allowlist():
    jobs, cronjobs = objects()
    run, calls = fake_run(jobs, cronjobs)
    state = {}
    assert superseded_jobs(run, state, context="ctx", threshold=1)["status"] == "healthy"
    result = superseded_jobs(run, state, context="ctx", threshold=1)
    assert result["status"] == "degraded"
    assert result["data"]["jobs"][0]["name"] == "job-1"
    assert all(argv[4] in ("identity", "monitoring", "cicd") for argv in calls)


def test_matching_image_env_only_active_or_missing_owner_are_not_superseded():
    for kwargs in ({"job_image": "old"}, {"job_image": "new", "active": 1}, {"owner": False}, {"cron_exists": False}):
        jobs, cronjobs = objects(**kwargs)
        run, _calls = fake_run(jobs, cronjobs)
        result = superseded_jobs(run, {}, threshold=0)
        assert result["status"] == "healthy"
        assert result["data"]["jobs"] == []


def test_env_difference_is_not_superseded():
    jobs, cronjobs = objects()
    jobs["items"][0]["spec"]["template"]["spec"] = pod_spec("old", [{"name": "MODE", "value": "debug"}])
    cronjobs["items"][0]["spec"]["jobTemplate"]["spec"]["template"]["spec"] = pod_spec("old")
    run, _calls = fake_run(jobs, cronjobs)
    assert superseded_jobs(run, {}, threshold=0)["data"]["jobs"] == []


def test_all_namespaces_unreadable_is_unknown_and_never_mutating():
    jobs, cronjobs = objects()
    run, calls = fake_run(jobs, cronjobs, failures={"identity", "monitoring", "cicd"})
    result = superseded_jobs(run, {})
    assert result["status"] == "unknown"
    assert all(not set(argv) & {"delete", "patch", "secret"} for argv in calls)
