# Review brief: Gemini-ask fix (Flash) — cross-vendor diff review

**Role:** review child of `2026-11-08-webhook-gemini-ask-has-no-collected-data` (first-pass trial step 2).
**Spec under review:** `docs/bugs/2026-11-08-webhook-gemini-ask-has-no-collected-data.md` (read it in full first).

## Task

Review the worker's diff below against the spec: its Fix steps, its Do-not list and its Acceptance block. Report
findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the tests
(`python3 -m pytest scripts/tests/bin/test_webhook_ask_gemini_context.py scripts/tests/bin/test_webhook_ask_delivery.py -q`)
and to try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`).

For each finding give:
- severity: blocker / should-fix / nit;
- file:line in the diff;
- a concrete input or state that breaks it;
- the spec line (Fix step, Do-not item, or M/N id) it violates.

Check in particular:
1. Each `must_not` (N1–N4) has a test that fails when its guard is removed (try it).
2. The collector matches only the user's own words (`user_question`), never job output or thread context.
3. Order is scrub, truncate, fence; the 3400/1600/1800 truncation; the 120 s timeout and the exact failure reply.
4. `_parse_gemini_observations(file_bugs=False)` on the collector path; the claude and codex branches untouched.
5. `_run_hostinger_status` output unchanged (M5); the stale docstring fixed.
6. No subprocess, `shell=True`, or `kubectl`/`aws`/`bin/cluster-status` on the ask path.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 500 words.

## Worker diff (uncommitted, against `k3d-manager-v1.43.15` at the worker's base)

```diff
diff --git a/bin/k3dm-webhook b/bin/k3dm-webhook
index 69cd746a..c1d60164 100755
--- a/bin/k3dm-webhook
+++ b/bin/k3dm-webhook
@@ -1140,6 +1140,7 @@ def _handle_thread_command(job_id, command, role="admin", channel_id="", user_id
         if not question:
             _notify_job(job_id, "❌ Question rejected — too long or contains disallowed patterns.")
             return
+        user_question = question
         _job_output = read_job_output(JOB_DIR / job_id, redact=_redact_secrets, max_chars=6000)
         if _job_output:
             _ctx_lines = [line.rstrip() for line in _job_output.splitlines() if line.strip()][-80:]
@@ -1167,7 +1168,7 @@ def _handle_thread_command(job_id, command, role="admin", channel_id="", user_id
         threading.Thread(
             target=_run_cluster_ask,
             args=(new_job_id, agent, question, ""),
-            kwargs={"thread_ts": thread_ts, "max_turns": ask_max_turns, "role": role},
+            kwargs={"thread_ts": thread_ts, "max_turns": ask_max_turns, "role": role, "user_question": user_question},
             daemon=True,
         ).start()
         _notify_job(job_id, f"🤖 Asking *{agent}*…")
diff --git a/scripts/lib/webhook/agent.py b/scripts/lib/webhook/agent.py
index 8ad3ab5f..0f3bd870 100644
--- a/scripts/lib/webhook/agent.py
+++ b/scripts/lib/webhook/agent.py
@@ -262,6 +262,8 @@ _INJECTION_RE = re.compile(
     re.IGNORECASE,
 )
 
+_HOSTINGER_RE = re.compile(r"\b(hostinger|k3s-hostinger)\b", re.IGNORECASE)
+
 def _sanitize_question(raw: str) -> str | None:
     """Return sanitized question or None if it looks like prompt injection."""
     q = raw.strip()
@@ -273,7 +275,7 @@ def _sanitize_question(raw: str) -> str | None:
     return q
 
 
-def _parse_gemini_observations(raw):
+def _parse_gemini_observations(raw, file_bugs=True):
     """Split Gemini's structured response into (answer_text, [filed_paths]).
 
     Expected format:
@@ -296,6 +298,8 @@ def _parse_gemini_observations(raw):
 
     answer_part, obs_part = raw.split(obs_marker, 1)
     answer = answer_part.removeprefix("ANSWER:\n").strip()
+    if not file_bugs:
+        return answer, []
 
     filed = []
     for line in obs_part.splitlines():
@@ -332,7 +336,7 @@ def _parse_gemini_observations(raw):
     return answer, filed
 
 
-def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None, max_turns=None, role="admin", channel_id=""):
+def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None, max_turns=None, role="admin", channel_id="", user_question=None):
     """Spawn claude/gemini/codex with the user's question; post the answer to Slack."""
     if max_turns is None:
         max_turns = _ASK_MAX_TURNS_DEFAULT
@@ -427,6 +431,36 @@ def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None, max_
         )
 
         if agent == "gemini":
+            target_question = question if user_question is None else user_question
+            collected_fence = ""
+            if _HOSTINGER_RE.search(target_question):
+                from webhook import status
+                from webhook.redact import scrub_credentials
+                from webhook.untrusted import fence
+
+                import concurrent.futures
+                executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
+                try:
+                    future = executor.submit(status._hostinger_status_text)
+                    collected_text = future.result(timeout=120)
+                except (concurrent.futures.TimeoutError, TimeoutError):
+                    executor.shutdown(wait=False, cancel_futures=True)
+                    _finish("Hostinger status collection failed: timed out after 120s. Run /cluster-status hostinger.")
+                    return
+                except Exception as exc:
+                    executor.shutdown(wait=False, cancel_futures=True)
+                    _finish(f"Hostinger status collection failed: {exc.__class__.__name__}. Run /cluster-status hostinger.")
+                    return
+                else:
+                    executor.shutdown(wait=False)
+
+                text = scrub_credentials(collected_text)
+                if len(text) > 3400:
+                    text = (text[:1600]
+                            + "\n… middle of report truncated …\n"
+                            + text[-1800:])
+                collected_fence = fence("hostinger status", text)
+
             gemini_system = (
                 "You are a Kubernetes troubleshooting assistant. "
                 "The cluster runs Vault, ArgoCD, Istio, ESO, Keycloak (local k3d) and shopping-cart "
@@ -445,18 +479,34 @@ def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None, max_
                 "- TITLE: <short title> | BODY: <one paragraph describing the issue>\n\n"
                 "Rules for OBSERVATIONS: only include issues you are confident are real bugs or "
                 "misconfigurations. Do not speculate. Each observation must be a distinct issue "
-                "unrelated to the question. Limit to 2 observations maximum.\n"
-                "Pod-state rule: if you notice a pod not in Running/Completed state "
-                "(ContainerCreating, CrashLoopBackOff, Pending, Error, OOMKilled), run "
-                "`kubectl describe pod <name> -n <namespace> --context <ctx>` first and include "
-                "the Events section in the BODY. Never guess the cause from status alone."
-            )
-            gemini_prompt = (
-                f"{gemini_system}{_ctx_block}\n\n"
-                f"---USER QUESTION START---\n{question}\n---USER QUESTION END---"
+                "unrelated to the question. Limit to 2 observations maximum."
             )
+
+            if collected_fence:
+                gemini_prompt = (
+                    f"{gemini_system}{_ctx_block}\n\n"
+                    f"{collected_fence}\n\n"
+                    f"---USER QUESTION START---\n{question}\n---USER QUESTION END---"
+                )
+            else:
+                no_data_line = (
+                    "No live data was collected for this question. If it asks about live cluster state, "
+                    "say that /cluster-status hostinger or asking claude answers it; do not ask the user for kubectl output."
+                )
+                gemini_prompt = (
+                    f"{gemini_system}{_ctx_block}\n\n"
+                    f"{no_data_line}\n\n"
+                    f"---USER QUESTION START---\n{question}\n---USER QUESTION END---"
+                )
+
             answer = _call_gemini(gemini_prompt)
-            answer, filed = _parse_gemini_observations(answer)
+            if collected_fence:
+                from webhook.untrusted import filter_suggestion
+                answer = filter_suggestion(answer)
+                answer, filed = _parse_gemini_observations(answer, file_bugs=False)
+                answer = filter_suggestion(answer)
+            else:
+                answer, filed = _parse_gemini_observations(answer)
             suffix = "\n" + "\n".join(f"Also filed: `{f}`" for f in filed) if filed else ""
             _finish(f"🤖 *gemini:* {answer}{suffix}")
             return
diff --git a/scripts/lib/webhook/status.py b/scripts/lib/webhook/status.py
index db7f7e98..c3f6fed1 100644
--- a/scripts/lib/webhook/status.py
+++ b/scripts/lib/webhook/status.py
@@ -13,6 +13,7 @@ from webhook.redact import mask_env_values, scrub_credentials
 
 __all__ = [
     "_run_cluster_status", "_format_status_summary_slack",
+    "_hostinger_status_text",
     "_run_hostinger_status", "_run_cluster_diagnostics", "configure_runtime",
 ]
 
@@ -398,8 +399,34 @@ def _format_status_summary_slack(payload, provider):
     if overall == "unknown":
         out.append("_status source unavailable — run `make restart-webhook` on the hub_")
     return _redact_secrets("\n".join(out))
+def _hostinger_status_text():
+    # A node recovery invalidates several forwards at once. Use the normal
+    # bounded retry window here so `/cluster-status` does not report a
+    # false outage while launchd is rebuilding those forwards.
+    smoke = _smoke_test_services(provider="k3s-hostinger")
+    checks = []
+    for name, ok, detail in smoke:
+        status = "healthy" if ok is True else ("warning" if ok is None else "error")
+        checks.append({"id": name.lower().replace(" ", "_"), "service": name,
+                       "status": status, "message": detail})
+    errors = [item for item in checks if item["status"] == "error"]
+    warnings = [item for item in checks if item["status"] == "warning"]
+    payload = {
+        "overall": "fail" if errors else ("warn" if warnings else "healthy"),
+        "checks": checks,
+        "errors": errors,
+        "warnings": warnings,
+        "counts": {
+            "services_healthy": sum(item["status"] == "healthy" for item in checks),
+            "services_warning": len(warnings),
+            "services_failed": len(errors),
+        },
+    }
+    return _format_status_summary_slack(payload, "k3s-hostinger")
+
+
 def _run_hostinger_status(job_id, response_url, thread_ts=None, provider=None, channel_id=""):
-    """Run bin/cluster-status for k3s-hostinger (read-only); post result to response_url or thread."""
+    """Collect service status for k3s-hostinger (read-only); post result to response_url or thread."""
     job_dir = JOB_DIR / job_id
     if thread_ts:
         (job_dir / "thread_ts").write_text(thread_ts)
@@ -422,29 +449,7 @@ def _run_hostinger_status(job_id, response_url, thread_ts=None, provider=None, c
 
     try:
         (job_dir / "status").write_text("running")
-        # A node recovery invalidates several forwards at once. Use the normal
-        # bounded retry window here so `/cluster-status` does not report a
-        # false outage while launchd is rebuilding those forwards.
-        smoke = _smoke_test_services(provider="k3s-hostinger")
-        checks = []
-        for name, ok, detail in smoke:
-            status = "healthy" if ok is True else ("warning" if ok is None else "error")
-            checks.append({"id": name.lower().replace(" ", "_"), "service": name,
-                           "status": status, "message": detail})
-        errors = [item for item in checks if item["status"] == "error"]
-        warnings = [item for item in checks if item["status"] == "warning"]
-        payload = {
-            "overall": "fail" if errors else ("warn" if warnings else "healthy"),
-            "checks": checks,
-            "errors": errors,
-            "warnings": warnings,
-            "counts": {
-                "services_healthy": sum(item["status"] == "healthy" for item in checks),
-                "services_warning": len(warnings),
-                "services_failed": len(errors),
-            },
-        }
-        _write_log(_format_status_summary_slack(payload, "k3s-hostinger"))
+        _write_log(_hostinger_status_text())
         _finish("success")
     except Exception as exc:
         _write_log(f"ERROR: {exc}")
diff --git a/scripts/tests/bin/test_webhook_ask_gemini_context.py b/scripts/tests/bin/test_webhook_ask_gemini_context.py
new file mode 100644
index 00000000..1885b455
--- /dev/null
+++ b/scripts/tests/bin/test_webhook_ask_gemini_context.py
@@ -0,0 +1,366 @@
+import concurrent.futures
+from importlib.machinery import SourceFileLoader
+import importlib.util
+import os
+from pathlib import Path
+import re
+import shutil
+import subprocess
+import pytest
+
+REPO_ROOT = Path(__file__).resolve().parents[3]
+FIXTURE_PATH = REPO_ROOT / "scripts" / "tests" / "fixtures" / "webhook-hostinger-status-2026-11-08.txt"
+
+import sys
+sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
+
+from webhook import agent
+from webhook import status
+
+_WEBHOOK = REPO_ROOT / "bin" / "k3dm-webhook"
+_spec = importlib.util.spec_from_file_location(
+    "k3dm_webhook_gemini_context", _WEBHOOK,
+    loader=SourceFileLoader("k3dm_webhook_gemini_context", str(_WEBHOOK)),
+)
+wh = importlib.util.module_from_spec(_spec)
+_spec.loader.exec_module(wh)
+
+
+@pytest.fixture(autouse=True)
+def hermetic_test_env(monkeypatch, tmp_path):
+    scratch_home = tmp_path / "home"
+    scratch_home.mkdir()
+    monkeypatch.setenv("HOME", str(scratch_home))
+    assert Path.home() == scratch_home
+
+    clean_bin = tmp_path / "bin"
+    clean_bin.mkdir()
+    monkeypatch.setenv("PATH", str(clean_bin))
+    assert shutil.which("kubectl") is None
+    assert shutil.which("ssh") is None
+    assert shutil.which("gemini") is None
+    assert shutil.which("agy") is None
+
+    fake_repo = tmp_path / "repo"
+    bugs_dir = fake_repo / "docs" / "bugs"
+    bugs_dir.mkdir(parents=True, exist_ok=True)
+    monkeypatch.setattr(agent, "REPO_ROOT", str(fake_repo))
+    assert Path(agent.REPO_ROOT) == fake_repo
+
+    jobs_dir = tmp_path / "jobs"
+    jobs_dir.mkdir()
+    monkeypatch.setattr(agent, "JOB_DIR", jobs_dir)
+    monkeypatch.setattr(status, "JOB_DIR", jobs_dir)
+    monkeypatch.setattr(wh, "JOB_DIR", jobs_dir)
+
+
+def _setup_job(tmp_path, job_id="job123"):
+    job_dir = Path(agent.JOB_DIR) / job_id
+    job_dir.mkdir(parents=True, exist_ok=True)
+    (job_dir / "status").write_text("queued")
+    return job_dir
+
+
+def test_m1_hostinger_question_runs_collector_and_fences_prompt(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "m1_job")
+    fixture_text = FIXTURE_PATH.read_text()
+    collector_calls = []
+
+    def stub_collector():
+        collector_calls.append(True)
+        return fixture_text
+
+    recorded_prompts = []
+
+    def stub_gemini(prompt):
+        recorded_prompts.append(prompt)
+        return "ANSWER:\nHostinger cluster is healthy."
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)
+    recorded_prompts_calls = []
+    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)
+
+    agent._run_cluster_ask(
+        "m1_job", "gemini", "show me hostinger status", "",
+        user_question="show me hostinger status"
+    )
+
+    assert len(collector_calls) == 1
+    assert len(recorded_prompts) == 1
+    prompt = recorded_prompts[0]
+
+    assert "<<<BEGIN UNTRUSTED hostinger_status" in prompt or "<<<BEGIN UNTRUSTED hostinger status" in prompt
+    assert "Cluster status: HEALTHY" in prompt
+    assert (job_dir / "output").read_text().startswith("🤖 *gemini:*")
+
+
+def test_m2_collected_data_filters_suggestion_and_files_no_bugs(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "m2_job")
+    fixture_text = FIXTURE_PATH.read_text()
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", lambda: fixture_text)
+
+    def stub_gemini(prompt):
+        return (
+            "ANSWER:\nHostinger is healthy. Run `make down` to stop.\n\n"
+            "OBSERVATIONS:\n"
+            "- TITLE: Suspicious Pod Crash | BODY: Pod crashed unexpectedly."
+        )
+
+    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)
+
+    agent._run_cluster_ask(
+        "m2_job", "gemini", "check k3s-hostinger status", "",
+        user_question="check k3s-hostinger status"
+    )
+
+    output = (job_dir / "output").read_text()
+    assert "(withheld command)" in output
+    assert "`make down`" not in output
+    assert "OBSERVATIONS:" not in output
+    assert "Also filed:" not in output
+
+    bugs_dir = Path(agent.REPO_ROOT) / "docs" / "bugs"
+    assert list(bugs_dir.glob("*.md")) == []
+
+
+def test_m3_unrelated_question_runs_no_collector_and_prompts_no_data(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "m3_job")
+    collector_calls = []
+
+    def stub_collector():
+        collector_calls.append(True)
+        return "unreachable"
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)
+
+    recorded_prompts = []
+
+    def stub_gemini(prompt):
+        recorded_prompts.append(prompt)
+        return "ANSWER:\nHere is general info."
+
+    monkeypatch.setattr(agent, "_call_gemini", stub_gemini)
+
+    agent._run_cluster_ask(
+        "m3_job", "gemini", "what is kubernetes ingress?", "",
+        user_question="what is kubernetes ingress?"
+    )
+
+    assert len(collector_calls) == 0
+    assert len(recorded_prompts) == 1
+    prompt = recorded_prompts[0]
+    assert "No live data was collected for this question" in prompt
+    assert "/cluster-status hostinger" in prompt
+
+
+def test_m4_collector_failure_and_timeout_handles_gracefully(monkeypatch, tmp_path):
+    job_dir_fail = _setup_job(tmp_path, "m4_fail")
+    gemini_calls = []
+
+    def stub_collector_fail():
+        raise ConnectionResetError("Hostinger unreachable")
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector_fail)
+    monkeypatch.setattr(agent, "_call_gemini", lambda p: gemini_calls.append(p))
+
+    agent._run_cluster_ask(
+        "m4_fail", "gemini", "hostinger status", "",
+        user_question="hostinger status"
+    )
+
+    assert len(gemini_calls) == 0
+    fail_output = (job_dir_fail / "output").read_text()
+    assert fail_output == "Hostinger status collection failed: ConnectionResetError. Run /cluster-status hostinger."
+
+    job_dir_timeout = _setup_job(tmp_path, "m4_timeout")
+
+    def stub_collector_timeout():
+        raise concurrent.futures.TimeoutError("timed out")
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector_timeout)
+
+    agent._run_cluster_ask(
+        "m4_timeout", "gemini", "hostinger status", "",
+        user_question="hostinger status"
+    )
+
+    assert len(gemini_calls) == 0
+    timeout_output = (job_dir_timeout / "output").read_text()
+    assert timeout_output == "Hostinger status collection failed: timed out after 120s. Run /cluster-status hostinger."
+
+
+def test_m5_hostinger_status_report_unchanged(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "m5_job")
+
+    fake_smoke = [
+        ("ArgoCD", True, "HTTP 200"),
+        ("Keycloak", True, "HTTP 200"),
+        ("Prometheus", None, "HTTP 401 (auth enforced)"),
+        ("Grafana", False, "Connection refused"),
+    ]
+    monkeypatch.setattr(status, "_smoke_test_services", lambda provider=None: fake_smoke)
+
+    assert hasattr(status, "_hostinger_status_text")
+    collected_text = status._hostinger_status_text()
+    assert "ArgoCD: HTTP 200" in collected_text
+    assert "Grafana: Connection refused" in collected_text
+
+    posts = []
+    monkeypatch.setattr(status, "_post_status_report", lambda *args: posts.append(args) or True)
+
+    status._run_hostinger_status("m5_job", "https://hooks.slack.com/resp")
+
+    job_output = (job_dir / "output").read_text()
+    assert job_output.strip() == collected_text.strip()
+    assert (job_dir / "status").read_text() == "success"
+
+
+def test_n1_collector_does_not_run_when_hostinger_only_in_context_or_job_output(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "n1_job")
+    collector_calls = []
+
+    def stub_collector():
+        collector_calls.append(True)
+        return FIXTURE_PATH.read_text()
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", stub_collector)
+
+    recorded_prompts = []
+    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nok")
+
+    question_with_job_output = (
+        "Job output context (last 80 lines of job `prev123`):\n"
+        "```\n"
+        "Failed deploying to k3s-hostinger cluster: connection timeout\n"
+        "```\n\n"
+        "User question: why did the previous job fail?"
+    )
+    user_q = "why did the previous job fail?"
+
+    agent._run_cluster_ask(
+        "n1_job", "gemini", question_with_job_output, "",
+        user_question=user_q
+    )
+
+    assert len(collector_calls) == 0
+    assert len(recorded_prompts) == 1
+    assert "No live data was collected for this question" in recorded_prompts[0]
+
+    job_dir_thread = _setup_job(tmp_path, "n1_thread")
+    monkeypatch.setattr(agent, "_fetch_thread_context", lambda ts: "Earlier thread mentioned hostinger outage")
+    agent._run_cluster_ask(
+        "n1_thread", "gemini", "check the cluster status", "",
+        thread_ts="12345.67", user_question="check the cluster status"
+    )
+    assert len(collector_calls) == 0
+
+
+def test_n2_collected_text_inside_fence_and_canary_scrubbed(monkeypatch, tmp_path):
+    job_dir = _setup_job(tmp_path, "n2_job")
+    canary_token = "canary_secret_token_xyz987654"
+    fixture_with_canary = FIXTURE_PATH.read_text() + f"\ntoken={canary_token}\n"
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", lambda: fixture_with_canary)
+
+    recorded_prompts = []
+    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nhealthy")
+
+    agent._run_cluster_ask(
+        "n2_job", "gemini", "show me hostinger status", "",
+        user_question="show me hostinger status"
+    )
+
+    assert len(recorded_prompts) == 1
+    prompt = recorded_prompts[0]
+
+    assert canary_token not in prompt
+    assert "token=***REDACTED***" in prompt
+
+    fence_match = re.search(r"<<<BEGIN UNTRUSTED [^\n]+>>>(.*?)<<<END UNTRUSTED [^\n]+>>>", prompt, re.DOTALL)
+    assert fence_match is not None
+    fence_body = fence_match.group(1)
+
+    assert "Cluster status: HEALTHY" in fence_body
+    before_fence = prompt[:fence_match.start()]
+    after_fence = prompt[fence_match.end():]
+    assert "Cluster status: HEALTHY" not in before_fence
+    assert "Cluster status: HEALTHY" not in after_fence
+
+
+def test_n3_gemini_prompt_does_not_tell_it_to_run_commands(monkeypatch, tmp_path):
+    _setup_job(tmp_path, "n3_job")
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", lambda: FIXTURE_PATH.read_text())
+
+    recorded_prompts = []
+    monkeypatch.setattr(agent, "_call_gemini", lambda p: recorded_prompts.append(p) or "ANSWER:\nhealthy")
+
+    agent._run_cluster_ask("n3_job", "gemini", "hostinger status", "", user_question="hostinger status")
+    agent._run_cluster_ask("n3_job", "gemini", "unrelated question", "", user_question="unrelated question")
+
+    for prompt in recorded_prompts:
+        assert not re.search(r"\brun\s+`?kubectl", prompt, re.IGNORECASE)
+        assert "run `kubectl describe pod" not in prompt
+
+
+def test_n4_ask_path_starts_no_subprocess_for_gemini(monkeypatch, tmp_path):
+    _setup_job(tmp_path, "n4_job")
+
+    if hasattr(status, "_hostinger_status_text"):
+        monkeypatch.setattr(status, "_hostinger_status_text", lambda: FIXTURE_PATH.read_text())
+    monkeypatch.setattr(agent, "_call_gemini", lambda p: "ANSWER:\nhealthy")
+
+    def _forbidden(*args, **kwargs):
+        raise AssertionError(f"Subprocess / spawn primitive invoked: args={args}, kwargs={kwargs}")
+
+    monkeypatch.setattr(subprocess, "Popen", _forbidden)
+    monkeypatch.setattr(subprocess, "run", _forbidden)
+    monkeypatch.setattr(subprocess, "call", _forbidden)
+    if hasattr(os, "posix_spawn"):
+        monkeypatch.setattr(os, "posix_spawn", _forbidden)
+    monkeypatch.setattr(agent, "_spawn_capture_text", _forbidden)
+
+    agent._run_cluster_ask("n4_job", "gemini", "hostinger status", "", user_question="hostinger status")
+    agent._run_cluster_ask("n4_job", "gemini", "other question", "", user_question="other question")
+
+
+def test_slack_ask_route_threads_user_question(monkeypatch, tmp_path):
+    job_id = "testjob1"
+    job_dir = Path(agent.JOB_DIR) / job_id
+    job_dir.mkdir(parents=True, exist_ok=True)
+    (job_dir / "status").write_text("success")
+    (job_dir / "output").write_text("Failed on k3s-hostinger cluster\n")
+
+    notified = []
+    monkeypatch.setattr(wh, "_notify_job", lambda j_id, msg: notified.append((j_id, msg)))
+
+    started_threads = []
+
+    class FakeThread:
+        def __init__(self, target=None, args=(), kwargs=None, daemon=None):
+            self.target = target
+            self.args = args
+            self.kwargs = kwargs or {}
+            started_threads.append(self)
+
+        def start(self):
+            pass
+
+    import threading
+    monkeypatch.setattr(threading, "Thread", FakeThread)
+
+    wh._handle_thread_command(job_id, "ask gemini show me hostinger status", role="operator")
+
+    assert len(started_threads) == 1
+    t = started_threads[0]
+    assert t.kwargs.get("user_question") == "show me hostinger status"
+    assert "Job output context" in t.args[2]
```
