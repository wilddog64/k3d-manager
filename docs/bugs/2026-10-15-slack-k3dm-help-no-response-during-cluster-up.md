# Bug: Slack `k3dm help` has no visible reply while cluster-up is running

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — missing response observed; delivery root cause not yet established
**Priority:** P2 — ChatOps command reliability
**Reported incident:** AWS `cluster-up` job `f58814c3`, Oct 15 around 10:52–10:54 local time

## Reproduction evidence

Operator screenshot shows `cluster-up (aws)` started at 10:52 (job `f58814c3`), operator posted `k3dm help` at 10:53, and `cluster-up` still-running progress arrived at 10:54. The operator explicitly confirmed **no help response appeared anywhere in Slack**, including threads. Actual Slack event delivery and webhook logs were not accessible during triage; do not treat this screenshot as proof of which backend stage failed.

## Expected

`k3dm help` responds promptly and independently of asynchronous cluster provisioning. Help is a read-only, lightweight operation and must not queue behind or be blocked by `cluster-up`. If delivery fails, the server records a correlated error and preserves retry/diagnostic information.

## Verified source observations

- `bin/k3dm-webhook:_THREAD_COMMANDS` and `_STANDALONE_CMDS` both recognize `k3dm`.
- Slack Events route (`/slack/events`) dispatches recognized top-level commands by creating a `thread-anchor` job and spawning `_handle_thread_command` in a daemon thread; it returns HTTP 200 without waiting for actual command processing or Slack response delivery.
- `_handle_thread_command` handles `target == "help"` by calling `_notify_job` and returning **before** acquiring `_MAKE_JOB_LOCK`; cluster lifecycle admission uses a separate job-status check. Thus a cluster-up should not block this handler by design.
- For top-level events, the anchor's `thread_ts` is set to the user's message `ev_ts`. `_notify_job` tries bot / response URL / incoming webhook routes. It has no reliable success/failure result propagated back to the help dispatcher; fallback `SLACK_WEBHOOK_URL` is not threaded.
- Prior thread routing defects exist in `docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md`, but **this missing-help-response case is distinct**: no response was visible, not merely misthreaded.

## Investigation

1. Correlate the actual Slack event for the 10:53 `k3dm help` message with `event_id`, Slack user/channel/message timestamp, webhook reception status, authorization result, event deduplication decision, command worker startup and any exception. Compare to contemporaneous `cluster-up` events; avoid printing tokens or signing secrets.
2. Instrument the help execution and response delivery: record chosen path, intended `channel_id/thread_ts`, Slack API/response URL status and any fallback. Do not treat HTTP 200 for Events as proof that Slack received a command response.
3. Determine whether `_notify_job` silently drops replies when bot posting fails, when channel configuration is missing/mismatched, or when thread anchoring is invalid. Verify `_post_slack_bot` error handling. Distinguish event non-delivery, authorization rejection, handler exception, and outgoing message failure.
4. Inspect message-size limits and target-list formatting from `make_target_help`; test whether the full help response exceeds Slack transport limits and whether a bounded/paginated response is needed. Do not assert this is the cause without a measured payload/error.
5. Ensure the lifecycle process cannot starve Slack event handling or its outbound worker threads during long provisioning, including high output volume.
6. Confirm expected immediate response even if another general `/k3dm` Make job holds `_MAKE_JOB_LOCK` and if cluster lifecycle job is running.
7. Preserve event acknowledgments but add durable/structured delivery-failure observability and safe retry or clear error reporting where possible.

## Acceptance tests

- Simulate running `cluster-up` with a top-level Slack `k3dm help` event; assert prompt help delivery to the intended channel/thread.
- Repeat as a thread reply, with a Make execution lock occupied, and with other concurrent progress posts.
- Inject Slack bot API failure, missing `channel_id`, invalid thread, excessive help output, and alternate fallback; assert no silent loss and appropriate correlation/logging, without leaking secrets.
- Verify unauthorized actors get explicit feedback, authorized actors are not dropped by dedupe/role handling, and Slack event HTTP acknowledgment isn't conflated with successful command execution.
- Use mocked Slack calls; no live cluster provision or destructive operation in tests.

**Implementation:** not started. No Slack command or live infrastructure was invoked to file this report.
