import concurrent.futures
from importlib.machinery import SourceFileLoader
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = REPO_ROOT / "scripts" / "tests" / "fixtures" / "webhook-hostinger-status-2026-11-08.txt"

import sys
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from webhook import agent
from webhook import status

_WEBHOOK = REPO_ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_gemini_context", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_gemini_context", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture(autouse=True)
def hermetic_test_env(monkeypatch, tmp_path):
    if agent._hostinger_collector_lock.locked():
        agent._hostinger_collector_lock.release()

    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    assert Path.home() == scratch_home

    clean_bin = tmp_path / "bin"
    clean_bin.mkdir()
    monkeypatch.setenv("PATH", str(clean_bin))
    assert shutil.which("kubectl") is None
    assert shutil.which("ssh") is None
    assert shutil.which("gemini") is None
    assert shutil.which("agy") is None

    fake_repo = tmp_path / "repo"
    bugs_dir = fake_repo / "docs" / "bugs"
    bugs_dir.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(agent, "REPO_ROOT", str(fake_repo))
    assert Path(agent.REPO_ROOT) == fake_repo

    jobs_dir = tmp_path / "jobs"
    jobs_dir.mkdir()
    monkeypatch.setattr(agent, "JOB_DIR", jobs_dir)
    monkeypatch.setattr(status, "JOB_DIR", jobs_dir)
    monkeypatch.setattr(wh, "JOB_DIR", jobs_dir)

    yield

    if agent._hostinger_collector_lock.locked():
        agent._hostinger_collector_lock.release()


def _setup_job(tmp_path, job_id="job123"):
    job_dir = Path(agent.JOB_DIR) / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    (job_dir / "status").write_text("queued")
    return job_dir


def test_m1_hostinger_question_runs_collector_and_fences_prompt(monkeypatch, tmp_path):
    job_dir = _setup_job(tmp_path, "m1_job")
    fixture_text = FIXTURE_PATH.read_text()
    collector_calls = []

    def stub_collector():
        collector_calls.append(True)
        return fixture_text

    recorded_prompts = []

    def stub_gemini(prompt):
        recorded_prompts.append(prompt)
        return "ANSWER:\nHostinger cluster is healthy."

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)
    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)

    agent._run_cluster_ask(
        "m1_job", "gemini", "show me hostinger status", "",
        user_question="show me hostinger status"
    )

    assert len(collector_calls) == 1
    assert len(recorded_prompts) == 1
    prompt = recorded_prompts[0]

    assert "<<<BEGIN UNTRUSTED hostinger_status" in prompt or "<<<BEGIN UNTRUSTED hostinger status" in prompt
    assert "Cluster status: HEALTHY" in prompt
    assert (job_dir / "output").read_text().startswith("🤖 *gemini:*")


def test_m2_collected_data_filters_suggestion_and_files_no_bugs(monkeypatch, tmp_path):
    job_dir = _setup_job(tmp_path, "m2_job")
    fixture_text = FIXTURE_PATH.read_text()

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", lambda: fixture_text)

    def stub_gemini(prompt):
        return (
            "ANSWER:\nHostinger is healthy. Run `make down` to stop.\n\n"
            "OBSERVATIONS:\n"
            "- TITLE: Suspicious Pod Crash | BODY: Pod crashed unexpectedly."
        )

    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)

    agent._run_cluster_ask(
        "m2_job", "gemini", "check k3s-hostinger status", "",
        user_question="check k3s-hostinger status"
    )

    output = (job_dir / "output").read_text()
    assert "(withheld command)" in output
    assert "`make down`" not in output
    assert "OBSERVATIONS:" not in output
    assert "Also filed:" not in output

    bugs_dir = Path(agent.REPO_ROOT) / "docs" / "bugs"
    assert list(bugs_dir.glob("*.md")) == []


def test_m3_unrelated_question_runs_no_collector_and_prompts_no_data(monkeypatch, tmp_path):
    _setup_job(tmp_path, "m3_job")
    collector_calls = []

    def stub_collector():
        collector_calls.append(True)
        return "unreachable"

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)

    recorded_prompts = []

    def stub_gemini(prompt):
        recorded_prompts.append(prompt)
        return "ANSWER:\nHere is general info."

    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)

    agent._run_cluster_ask(
        "m3_job", "gemini", "what is kubernetes ingress?", "",
        user_question="what is kubernetes ingress?"
    )

    assert len(collector_calls) == 0
    assert len(recorded_prompts) == 1
    prompt = recorded_prompts[0]
    assert "No live data was collected for this question" in prompt
    assert "/cluster-status hostinger" in prompt


def test_m4_collector_failure_and_timeout_handles_gracefully(monkeypatch, tmp_path):
    job_dir_fail = _setup_job(tmp_path, "m4_fail")
    gemini_calls = []

    def stub_collector_fail():
        raise ConnectionResetError("Hostinger unreachable")

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector_fail)
    monkeypatch.setattr(agent, "_call_gemini", lambda p: gemini_calls.append(p))

    agent._run_cluster_ask(
        "m4_fail", "gemini", "hostinger status", "",
        user_question="hostinger status"
    )

    assert len(gemini_calls) == 0
    fail_output = (job_dir_fail / "output").read_text()
    assert fail_output == "Hostinger status collection failed: ConnectionResetError. Run /cluster-status hostinger."

    job_dir_timeout = _setup_job(tmp_path, "m4_timeout")

    def stub_collector_timeout():
        raise concurrent.futures.TimeoutError("timed out")

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector_timeout)

    agent._run_cluster_ask(
        "m4_timeout", "gemini", "hostinger status", "",
        user_question="hostinger status"
    )

    assert len(gemini_calls) == 0
    timeout_output = (job_dir_timeout / "output").read_text()
    assert timeout_output == "Hostinger status collection failed: timed out after 120s. Run /cluster-status hostinger."


def test_m5_hostinger_status_report_unchanged(monkeypatch, tmp_path):
    job_dir = _setup_job(tmp_path, "m5_job")

    fake_smoke = [
        ("ArgoCD", True, "HTTP 200"),
        ("Keycloak", True, "HTTP 200"),
        ("Prometheus", None, "HTTP 401 (auth enforced)"),
        ("Grafana", False, "Connection refused"),
    ]
    monkeypatch.setattr(status, "_smoke_test_services", lambda provider=None: fake_smoke)

    assert hasattr(status, "_hostinger_status_text")
    collected_text = status._hostinger_status_text()
    assert "ArgoCD: HTTP 200" in collected_text
    assert "Grafana: Connection refused" in collected_text

    posts = []
    monkeypatch.setattr(status, "_post_status_report", lambda *args: posts.append(args) or True)

    status._run_hostinger_status("m5_job", "https://hooks.slack.com/resp")

    job_output = (job_dir / "output").read_text()
    assert job_output.strip() == collected_text.strip()
    assert (job_dir / "status").read_text() == "success"


def test_n1_collector_does_not_run_when_hostinger_only_in_job_output(monkeypatch, tmp_path):
    _setup_job(tmp_path, "n1_job_output")
    collector_calls = []

    def stub_collector():
        collector_calls.append(True)
        return FIXTURE_PATH.read_text()

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)

    recorded_prompts = []
    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nok")

    question_with_job_output = (
        "Job output context (last 80 lines of job `prev123`):\n"
        "```\n"
        "Failed deploying to k3s-hostinger cluster: connection timeout\n"
        "```\n\n"
        "User question: why did the previous job fail?"
    )
    user_q = "why did the previous job fail?"

    agent._run_cluster_ask(
        "n1_job_output", "gemini", question_with_job_output, "",
        user_question=user_q
    )

    assert len(collector_calls) == 0
    assert len(recorded_prompts) == 1
    assert "No live data was collected for this question" in recorded_prompts[0]


def test_n1_collector_does_not_run_when_hostinger_only_in_thread_context(monkeypatch, tmp_path):
    _setup_job(tmp_path, "n1_thread")
    collector_calls = []

    def stub_collector():
        collector_calls.append(True)
        return FIXTURE_PATH.read_text()

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)

    recorded_prompts = []
    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nok")
    monkeypatch.setattr(agent, "_fetch_thread_context", lambda ts: "Earlier thread mentioned hostinger outage")

    user_q = "check the cluster status"
    agent._run_cluster_ask(
        "n1_thread", "gemini", user_q, "",
        thread_ts="12345.67", user_question=user_q
    )

    assert len(collector_calls) == 0
    assert len(recorded_prompts) == 1
    assert "No live data was collected for this question" in recorded_prompts[0]


def test_single_collector_guard_rejects_concurrent_collection_and_releases_after_finish(monkeypatch, tmp_path):
    import threading
    import time

    job1_dir = _setup_job(tmp_path, "concurrent1")
    job2_dir = _setup_job(tmp_path, "concurrent2")
    job3_dir = _setup_job(tmp_path, "concurrent3")

    block_event = threading.Event()
    started_event = threading.Event()
    collector_calls = []

    def stub_blocking_collector():
        collector_calls.append(True)
        started_event.set()
        block_event.wait(timeout=5)
        return FIXTURE_PATH.read_text()

    monkeypatch.setattr(status, "_hostinger_status_text", stub_blocking_collector)
    monkeypatch.setattr(agent, "_HOSTINGER_COLLECT_TIMEOUT", 0.05)

    gemini_calls = []
    monkeypatch.setattr(agent, "_call_gemini", lambda p: gemini_calls.append(p) or "ANSWER:\nhealthy")

    try:
        # First ask: collector starts and blocks on block_event, caller times out after 0.05s
        agent._run_cluster_ask(
            "concurrent1", "gemini", "show me hostinger status", "",
            user_question="show me hostinger status"
        )
        assert (job1_dir / "output").read_text() == "Hostinger status collection failed: timed out after 120s. Run /cluster-status hostinger."
        assert len(collector_calls) == 1
        assert len(gemini_calls) == 0
        assert started_event.is_set()
        assert agent._hostinger_collector_lock.locked()

        # (a) Second ask while first collector is still running:
        # Must not start another collector, must not call Gemini, and must reply with "still running" message
        agent._run_cluster_ask(
            "concurrent2", "gemini", "show me hostinger status", "",
            user_question="show me hostinger status"
        )
        assert len(collector_calls) == 1
        assert len(gemini_calls) == 0
        assert (job2_dir / "output").read_text() == "Hostinger status collection failed: a previous collection is still running. Run /cluster-status hostinger."

        # (b) Paired positive control: release the blocked collector
        block_event.set()
        for _ in range(50):
            if not agent._hostinger_collector_lock.locked():
                break
            time.sleep(0.01)
        assert not agent._hostinger_collector_lock.locked()

        # Third ask: collector runs again, Gemini is called
        agent._run_cluster_ask(
            "concurrent3", "gemini", "show me hostinger status", "",
            user_question="show me hostinger status"
        )
        assert len(collector_calls) == 2
        assert len(gemini_calls) == 1
        assert (job3_dir / "status").read_text() == "success"
    finally:
        block_event.set()


def test_n2_collected_text_inside_fence_and_canary_scrubbed(monkeypatch, tmp_path):
    _setup_job(tmp_path, "n2_job")
    canary_token = "canary_secret_token_xyz987654"
    fixture_with_canary = FIXTURE_PATH.read_text() + f"\ntoken={canary_token}\n"

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", lambda: fixture_with_canary)

    recorded_prompts = []
    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nhealthy")

    agent._run_cluster_ask(
        "n2_job", "gemini", "show me hostinger status", "",
        user_question="show me hostinger status"
    )

    assert len(recorded_prompts) == 1
    prompt = recorded_prompts[0]

    assert canary_token not in prompt
    assert "token=***REDACTED***" in prompt

    fence_match = re.search(r"<<<BEGIN UNTRUSTED [^\n]+>>>(.*?)<<<END UNTRUSTED [^\n]+>>>", prompt, re.DOTALL)
    assert fence_match is not None
    fence_body = fence_match.group(1)

    assert "Cluster status: HEALTHY" in fence_body
    before_fence = prompt[:fence_match.start()]
    after_fence = prompt[fence_match.end():]
    assert "Cluster status: HEALTHY" not in before_fence
    assert "Cluster status: HEALTHY" not in after_fence


def test_n3_gemini_prompt_does_not_tell_it_to_run_commands(monkeypatch, tmp_path):
    _setup_job(tmp_path, "n3_job")

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", lambda: FIXTURE_PATH.read_text())

    recorded_prompts = []
    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nhealthy")

    agent._run_cluster_ask("n3_job", "gemini", "hostinger status", "", user_question="hostinger status")
    agent._run_cluster_ask("n3_job", "gemini", "unrelated question", "", user_question="unrelated question")

    for prompt in recorded_prompts:
        assert not re.search(r"\brun\s+`?kubectl", prompt, re.IGNORECASE)
        assert "run `kubectl describe pod" not in prompt


def test_n4_ask_path_starts_no_subprocess_for_gemini(monkeypatch, tmp_path):
    _setup_job(tmp_path, "n4_job")

    if hasattr(status, "_hostinger_status_text"):
        monkeypatch.setattr(status, "_hostinger_status_text", lambda: FIXTURE_PATH.read_text())
    monkeypatch.setattr(agent, "_call_gemini", lambda p: "ANSWER:\nhealthy")

    def _forbidden(*args, **kwargs):
        raise AssertionError(f"Subprocess / spawn primitive invoked: args={args}, kwargs={kwargs}")

    monkeypatch.setattr(subprocess, "Popen", _forbidden)
    monkeypatch.setattr(subprocess, "run", _forbidden)
    monkeypatch.setattr(subprocess, "call", _forbidden)
    if hasattr(os, "posix_spawn"):
        monkeypatch.setattr(os, "posix_spawn", _forbidden)
    monkeypatch.setattr(agent, "_spawn_capture_text", _forbidden)

    agent._run_cluster_ask("n4_job", "gemini", "hostinger status", "", user_question="hostinger status")
    agent._run_cluster_ask("n4_job", "gemini", "other question", "", user_question="other question")


def test_slack_ask_route_threads_user_question(monkeypatch, tmp_path):
    job_id = "testjob1"
    job_dir = Path(agent.JOB_DIR) / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    (job_dir / "status").write_text("success")
    (job_dir / "output").write_text("Failed on k3s-hostinger cluster\n")

    notified = []
    monkeypatch.setattr(wh, "_notify_job", lambda j_id, msg: notified.append((j_id, msg)))

    started_threads = []

    class FakeThread:
        def __init__(self, target=None, args=(), kwargs=None, daemon=None):
            self.target = target
            self.args = args
            self.kwargs = kwargs or {}
            started_threads.append(self)

        def start(self):
            pass

    import threading
    monkeypatch.setattr(threading, "Thread", FakeThread)

    wh._handle_thread_command(job_id, "ask gemini show me hostinger status", role="operator")

    assert len(started_threads) == 1
    t = started_threads[0]
    assert t.kwargs.get("user_question") == "show me hostinger status"
    assert "Job output context" in t.args[2]
