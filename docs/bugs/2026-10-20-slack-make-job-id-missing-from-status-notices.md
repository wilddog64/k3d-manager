# Slack Make job acknowledgements and status notices omit the job ID inconsistently

**Filed:** 2026-10-20 (operator-reported live Slack run)
**Status:** VERIFIED — fix landed at `abb0a526`; offline tests pass. Slack live attempt `be53f685` still showed queued/started notices without IDs; webhook rollout state is unconfirmed, so retest after restart. Not LIVE-VERIFIED.
**Priority:** P2 — job execution continues, but operators may not be able to correlate or request its logs by ID; bare `logs` is a workaround
**Branch:** `k3d-manager-v1.43.5`
**Fix commit:** `abb0a526`
**Release:** v1.43.5 (bug; no new plan slot)
**Component:** Slack `/make` and `/k3dm` async Make job acknowledgement/progress notices
**Related:** `docs/bugs/2026-10-13-slack-logs-explicit-job-id-mismatch.md`, `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`

## Symptom and live evidence

In the `#acg-automation` Slack thread for the operator's 2026-10-20 `make e2e-sandbox-provision` run, job `05f2be6c`:

- The initial `make e2e-sandbox-provision queued` notice did not show a job ID.
- The `make e2e-sandbox-provision started by slack:...` notice did not show a job ID.
- The 2-minute progress notice did not show a job ID. Its output showed the run waiting for the AWS changeset/stack update.
- `logs <user-id>` returned usage, because the user had no job ID to supply.
- Bare `logs` then returned `Last 20 lines (job 05f2be6c)`, proving the running job could be found, but only via the implicit thread lookup.

The operator reports that a job ID appears in some Slack acknowledgements but not others. Source inspection confirms two Make dispatch paths differ: the `/k3dm` thread-command path includes the generated ID in its queued notice, while the direct webhook Make path creates its queued thread notice before generating the ID. The shared Make worker's started, progress, and terminal notices also omit the ID.

## Expected behavior

Every asynchronous Make job lifecycle notice—queued, started, progress, and terminal success/failure/timeout—must include the exact same job ID in a copyable form, regardless of whether the job was launched through Slack `/make` or a `/k3dm` thread command. The initial notice must make the ID available before the operator needs to query logs. Existing bare `logs` behavior, explicit-ID authorization, redaction, and thread routing must remain unchanged.

## Acceptance criteria

- [x] The direct `/make` queued message includes the ID returned in its queued response and used for its job directory.
- [x] `/k3dm <target>` queued notices and direct `/make` notices use the same visible ID format.
- [x] Started, progress, and terminal Make notifications identify the same job ID, including failure and timeout paths.
- [x] Tests assert exact ID consistency across both enqueue paths and worker notifications; tests do not launch real Make targets, AWS resources, or clusters.
- [x] Regression tests preserve bare `logs` and explicit `logs <job-id>` lookup behavior and do not expose response URLs, credentials, or unredacted job output.
- [x] Focused Python/BATS tests and `_agent_audit` pass. No shell files changed, so ShellCheck is not applicable.

## Files

- `bin/k3dm-webhook`
- `scripts/lib/webhook/lifecycle.py`
- `scripts/tests/bin/test_webhook_thread_dispatch.py`
- `scripts/tests/bin/webhook_lifecycle.py`

Do not change Make job authorization, log retention, cluster execution, or AWS provisioning behavior. Keep implementation within the listed files.

## Source pointers

- `bin/k3dm-webhook` `/k3dm` thread-command branch creates a job ID before sending `queued — job <id>`.
- `bin/k3dm-webhook` direct Make webhook branch currently calls `_start_bot_thread("… queued")` before generating the Make job ID.
- `scripts/lib/webhook/lifecycle.py::_run_make_target` sends started, timed progress, and terminal notices without including the ID already passed as `job_id`.

## Verification

- Fix landed on `k3d-manager-v1.43.5` as `abb0a526`; deterministic progress/failure regression coverage follow-up is `cb7f37dc`.
- `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_webhook_thread_dispatch.py scripts/tests/bin/webhook_lifecycle.py`: 26 passed. Coverage includes direct `/make` queued ID/response/directory consistency, `/k3dm` queued format, explicit and bare logs behavior, and started/progress/success/failure/timeout notices.
- `bats scripts/tests/bin/makefile_webhook_slack.bats`: 10/10 passed. Python syntax compilation, `git diff --check`, and `_agent_audit` passed.
- No shell source files changed; ShellCheck is not applicable. Operator Slack live verification remains pending after webhook rollout; this record is not LIVE-VERIFIED.
- Live attempt 2026-10-20: `/make test-all` thread still showed `make test-all queued` and `make test-all started by slack:wilddog64:U4C9LDQP2` without an ID; `logs` returned job `be53f685`. The LaunchAgent plist points at the updated repository checkout, but process inspection was blocked, so it is unknown whether the running process loaded the landed code. See `docs/issues/2026-10-20-slack-make-job-id-live-verification-still-omits-ids.md`. Keep status VERIFIED, not LIVE-VERIFIED, until a post-restart run shows consistent IDs.
