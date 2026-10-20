# Bug: cluster lifecycle asynchronous notifications may lose Slack thread context

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — reproduce and trace timestamp propagation; root cause unconfirmed
**Priority:** P3 (ChatOps UX); raise to P2 if correlation or completion notification is lost, particularly for terminal cluster lifecycle outcomes
**Severity:** low
**Approval:** explicit operator request 2026-10-15 to file bug; no implementation approved
**Evidence:** operator Slack screenshot 2026-10-15 approximately 07:35 PDT, AWS ACG sandbox `cluster-up` job `5f5cff23`

## Symptom

A Slack `k3d-manager` app message at 07:33 announced `🚀 cluster-up (aws) started — job 5f5cff23` in response to the operator's sandbox-up request. At 07:35, the app posted `⏳ cluster-up (aws) still running — 2m elapsed` and log excerpts as a separate top-level message rather than a visible reply in the initial job thread. The excerpts included `Waiting for changeset to be created..`, `Waiting for stack create/update to complete`, and `Successfully created/updated stack - k3d-manager-cluster`. This last stack message does **not** establish completion of the overall cluster-up task.

Expected: when the initial job notification establishes a Slack thread, progress, completion, and failure updates for that same job consistently reply to that thread, preserving context and the job ID. If a top-level fallback is necessary, make it visible and diagnosable rather than silently losing thread correlation.

## Existing code and investigation

The repository already has threading support; this is **not** a request to invent general Slack threading:
- `scripts/lib/webhook/render.py`: `_post_slack_bot(text, thread_ts=None, channel_id=None)` passes `thread_ts` to `chat.postMessage` when provided.
- `scripts/lib/webhook/status.py`: `_post_status_report(..., channel_id, thread_ts)` attempts threaded posting; `_run_cluster_status` accepts/persists `thread_ts`.

Trace the **actual async `cluster-up` notification path**, not only `cluster-status`:
1. Identify how the originating slash-command or webhook obtains Slack `channel_id` and parent message `ts`/`thread_ts`. Determine whether the initial ack message created a new parent thread or uses an existing request thread.
2. Follow both values through job enqueue/persistence, worker process boundaries, progress timer, terminal success/failure notifications, and any response_url fallback.
3. Verify whether `cluster-up` posts via the same helper as status reports, or whether some paths use `response_url` / separate `chat.postMessage` calls without `thread_ts`.
4. Inspect Slack API outcomes and fallback behavior if threaded posting fails, without leaking tokens or response URLs. Confirm required Slack scopes and channel membership.
5. Determine whether the screenshot's two messages are truly top-level via Slack metadata, since the screenshot alone does not expose raw `thread_ts`.
6. Do not conflate thread display with job success or failure. A successful AWS CloudFormation stack operation can precede later `cluster-up` steps.

## Acceptance / regression

- For a simulated asynchronous `cluster-up (aws)`, initial, progress, completion, and failure notifications carry a consistent job ID and appear under the intended parent thread.
- Thread context survives a long-running job and a worker restart/retry if job state persistence is part of the existing design.
- Tests assert actual outbound `chat.postMessage` payloads include the expected `channel` and `thread_ts`, including the progress path (not just status command coverage).
- When threading is unavailable, fallback to top-level message is explicit, records a reason, and retains job correlation.
- No change to cluster provisioning, execution permissions, or AWS resources is required to correct message routing.

**Implementation:** not started.


## Expanded source audit — 2026-10-15 (operator-requested)

**Scope:** Inspect cluster lifecycle commands for the same threading failure mode, not just the observed AWS `cluster-up`. **Method:** read-only source review of `bin/k3dm-webhook`, `scripts/lib/webhook/lifecycle.py`, `scripts/lib/webhook/status.py`, and `scripts/lib/webhook/render.py` on `k3d-manager-v1.43.2`. No live Slack API inspection, runtime replay, AWS action, or confirmation of each individual symptom; distinguish structural risks from verified defects.

| Command | Routing and notification evidence | Assessment |
|---|---|---|
| `cluster-up` / `up` | Dispatcher creates a child job, copies the parent's `thread_ts` only, starts `_run_cluster(job_id, "up", ...)`; worker emits started, 120-second progress, stall, failure-analysis, terminal success/failure via `_notify_job`. Operator screenshot of job `5f5cff23` showed top-level-looking progress message. | **Observed symptom; cause unconfirmed.** Shared metadata propagation is a strong lead. |
| `cluster-down` / `down` | Same child-job creation and same `_run_cluster` implementation, including start/progress/end notifications and `thread_ts`-only copy. | **Same structural risk as up**, not independently observed live. |
| `cluster-resume` / `resume` | Child job also copies only `thread_ts`; `_run_cluster_resume` posts through `_notify_job`. | **Same metadata risk**; assess start, progress (if any), and terminal replies. |
| `cluster-refresh` / `refresh` | Child handler passes `thread_ts` into `_run_cluster_refresh`, but `_finish` calls `_slack_post(response_url, output)` **without** the optional `thread_ts` whenever `response_url` exists. | **Confirmed source-level omission**; whether Slack actually starts a new top-level message depends on response_url behavior. |
| `hostinger-refresh` | `_run_hostinger_refresh` similarly calls `_slack_post(response_url, output)` without `thread_ts` in `_finish`. | **Confirmed source-level omission**; runtime outcome unverified. |
| `cluster-status` and `hostinger-status` | Dedicated `scripts/lib/webhook/status.py` accepts `thread_ts` and chooses bot-thread post when channel/context are available; fallback may create a new status thread. | **Thread-aware by design**, but test original-parent correlation and fallback; do not claim observed failure. |
| `cluster-diagnose` | Dedicated status/diagnostic path explicitly accepts `thread_ts`. | **Thread-aware by design**, but this does not verify live command routing or successful delivery. |
| `cleanup-stale-sandbox` | Uses the original job and `_notify_job`, and can create a bot thread if absent. | **Different implementation**, review fallback/original-thread handling; do not equate with cluster-up bug without evidence. |

### Strong leads from the shared notification helper

`bin/k3dm-webhook:_notify_job` reads job-local `thread_ts`, `channel_id`, `thread_source`, and `response_url`. When `thread_source == "bot"` plus token/channel/timestamp are present it uses `chat.postMessage` with `thread_ts`; otherwise it may use `response_url`, then bot fallback, then incoming webhook. For `up/down/resume`, the dispatcher explicitly copies only `thread_ts` into the child directory. Check whether missing `channel_id`, `thread_source`, and `response_url` in the child change the chosen post mechanism or silently prevent notification. The bot fallback may still thread when the global channel/token are valid; do **not** claim the partial copy is proven root cause without tracing the actual runtime values.

The fallback to `SLACK_WEBHOOK_URL` calls `_slack_post(SLACK_WEBHOOK_URL, text)` without `thread_ts`, creating an unthreaded-post risk when earlier delivery attempts fail. `_post_slack_bot` and `_slack_post` largely return empty/False on error without capturing actionable Slack API diagnostic details; failures can be silent.

### Expanded implementation acceptance and tests

1. Define an explicit canonical thread-context record (`channel_id`, `thread_ts`, `thread_source`, allowed `response_url` where relevant) propagated to **every child lifecycle job**; avoid copying only one field, and preserve thread/job correlation across dispatch, progress and completion.
2. Test `cluster-up`, `cluster-down`, `cluster-resume`, `cluster-refresh`, `hostinger-refresh` and status/diagnostics separately with stubbed Slack backends; assert payload destination, `thread_ts`, and channel, including timer callbacks, worker failures, and fallbacks. Do not run actual cluster up/down for regression tests.
3. Ensure `_run_cluster_refresh` and `_run_hostinger_refresh` honor the saved thread context even when a `response_url` is available. Avoid guessing Slack response_url semantics: verify payload and reply placement with a safe integration test.
4. Capture **redacted**, operator-actionable delivery errors and fallback reasons. Distinguish inability to thread from inability to notify; no tokens, raw response URLs or sensitive output in logs.
5. Check whether the dispatcher emits its queued message to the original parent job while the worker posts against a new job. Assert both refer to the same intended Slack conversation; avoid duplicate top-level parent messages when a thread exists.
6. Do not mark all lifecycle commands as currently broken based solely on one `cluster-up` screenshot. Document independently verified failures and passing paths in the bug before closure.

**Result of this audit:** one **observed** `cluster-up` symptom; two **confirmed source-level omissions** of `thread_ts` in refresh-family `response_url` calls; shared structural threading/correlation risk for `up/down/resume`; status/diagnostics already thread-aware in source. End-to-end live confirmation remains outstanding.


## Suspected regression and test-coverage escape — 2026-10-15

**Classification:** suspected regression, not yet confirmed by a last-known-good version or introducing commit. The operator observed that existing tests did not catch the misthreaded lifecycle progress notification. Existing Slack threading support and recent asynchronous routing changes make regression plausible, but the source history still needs inspection.

### Required regression investigation

1. Trace `git log` / `git blame` for child-job dispatch, `_notify_job`, `thread_ts`/`channel_id`/`thread_source` propagation, timer-based progress, and refresh response handling. Identify a demonstrable last-known-good behavior and the earliest offending change, if one exists.
2. Audit the current Slack/webhook tests: determine which paths they execute and which assertions merely check that a message was sent, without verifying the **destination thread and channel**. Record the actual coverage gap rather than assuming all tests are weak.
3. **Before implementing the fix**, introduce a deterministic regression test that fails on the current behavior, specifically for the parent-request → child-job → async progress → outbound Slack payload path. Assert exact `thread_ts`, `channel`, and job correlation, not only send-call count or returned success.
4. Cover start, 120-second timer progress, completion, failure, retry/fallback, and a persisted/restarted child job as applicable. Matrix: `cluster-up`, `cluster-down`, `cluster-resume`, `cluster-refresh`, and Hostinger refresh. Verify dedicated `cluster-status`/diagnostics do not regress.
5. Use stubbed Slack requests and stubbed lifecycle commands for automated tests; never run real AWS provisioning or destructive cluster commands just to test message routing. Include negative tests for lost/mismatched thread metadata and Slack API rejection with safe diagnostic fallback.
6. Demonstrate red-before/green-after: the pre-fix test fails for the observed contract violation, passes after correction, and the relevant existing suites remain green. Record any remaining limitations of source-only tests versus actual Slack rendering.

**Acceptance condition added:** do not close the bug solely because the messaging helper's unit tests pass. Show that the complete asynchronous dispatcher-to-Slack-payload behavior is covered and that the original error cannot recur unnoticed by the regression suite.


## Additional operator evidence — 2026-10-15 ~08:44 PDT: threading starts partway through job

**Observed:** A later Slack screenshot of the same AWS `cluster-up` job `5f5cff23` shows the 8-minute progress update and 10-minute progress update as top-level channel messages; the 10-minute update has a **“6 replies”** thread indicator. The previous screenshot showed subsequent 14-minute, 16-minute, 18-minute, terminal-success and post-provision messages in a conversation pane. Together these screenshots support a **mid-job switch in message placement** rather than consistent threading from the original job announcement. The earlier interpretation that all progress updates were correctly threaded was mistaken. A thread appearing on the 10-minute message does not establish it was the intended original parent.

**Investigation focus:** Obtain the actual Slack message `ts`, `thread_ts`, and `channel` for the initial announcement, the 2/4/6/8/10-minute updates, and later replies. Compare these to job-local `thread_ts`, `thread_source`, `channel_id`, and `response_url` values as persisted over time (redact response URL). Determine whether the bot starts a new thread after an earlier fallback fails, or whether child-job metadata is introduced or overwritten mid-execution. Account for the code's `_notify_job` branch ordering and thread-parent creation behavior. Do not assert a root cause without these timestamps or a deterministic reproduction.

**Additional regression requirement:** Exercise successive 120-second timer callbacks with the same child job, including empty/partial thread metadata and changes in posting backend. Verify that *every* notification uses the **original intended thread parent**, and that a failure to post in-thread never silently switches later notifications to a different parent. The test must fail before fixing this observed behavior.

## Additional incident — 2026-10-20 (cloud-bridge Make job notification)

Operator screenshot at approximately 13:58 PDT shows the `k3d-manager` Slack app announcing a cloud-bridge initiated `make test-all` job. The operator reported that the call **did not return its result within the expected Slack thread**. This resembles the existing asynchronous job lifecycle / thread-correlation failure mode, but is a **different entry path** than the original `cluster-up (aws)` incident.

The same invocation is corroborated by GitHub-backed bridge responses: request `20261020T205644Z-make-test-all` queued job `a3ec539d` at 20:58:08 UTC. A subsequent `job-status` response at 21:00:15 UTC showed `running` and a nonempty redacted Make test tail. **Do not classify absence of a terminal Slack reply as a failure until the job is actually terminal.** Determine whether later completion/failure messages are posted as thread replies, separate top-level messages, or not delivered.

**Status: OPEN — live verification=false.** Reopened/investigation expanded for async Make notifications; no verified fix or confirmed regression yet. Retain P3 initially; consider P2 if a completed job lacks notification or loses important completion status. The `2026-10-18-slack-thread-broadcast-reply-silently-ignored.md` issue is about incoming human `thread_broadcast` commands, so it should **not** be marked regressed solely on the basis of outbound job notifications.

### Additional checks / evidence

- Confirm terminal status for `a3ec539d` via `job-status` / `.final.json` before evaluating missing final Slack notifications.
- Inspect recorded `channel_id`, parent `thread_ts`, job metadata, and Slack post responses for the cloud-bridge `make-test-all` path (without exposing tokens or private content).
- Verify that queued, started, progress and terminal notifications attach to the same Slack thread, or surface an explicit, diagnosable fallback.
- Capture actual Slack `ts` and `thread_ts` for the sent messages; do not infer them from the screenshot alone.
- Add regression coverage specifically for externally queued Make jobs, distinct from the existing `cluster-up` assertions; do not run another large test suite only to exercise Slack notification formatting.

Evidence: https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261020T205950Z-job-status-test-all.json
