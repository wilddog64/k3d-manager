# Bug: asynchronous cluster-up progress posts outside initiating Slack thread

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — reproduce and trace timestamp propagation; root cause unconfirmed
**Priority:** P3 (ChatOps UX); raise to P2 if correlation or completion notification is lost
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
