# Bug: Slack `k3dm help` has no visible reply while cluster-up is running

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Status:** LIVE-VERIFIED — 2026-10-21: operator Slack screenshot shows the `/k3dm targets` help response arriving while `cluster-up (aws)` is still running. The separate cluster-up progress notification remains top-level; that is tracked by `2026-10-15-cluster-up-progress-slack-thread-missing.md` and is not covered by this fix.
**Live evidence:** 2026-10-21 · run 2b6e4f97 · env slack/k3d-manager · scenario k3dm-help-during-cluster-up · commit 61230daa · proves fix
**Fix commit:** 61230daa
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

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_broadcast.py`
- `scripts/tests/bin/test_webhook_stale_cleanup.py`
- `scripts/tests/lib/webhook.bats`

**Implementation:** landed as `61230daa` on `k3d-manager-v1.43.5`. The help response now uses bounded chunk delivery; delivery attempts and command-handler exceptions are correlated to the Slack event and recorded without secrets. Thread-targeted replies do not fall back to non-thread-capable incoming webhooks.

## Offline verification — 2026-10-20

The dispatched implementation is **not verified for landing**. Focused tests passed:

```text
python3 -m pytest -q scripts/tests/bin/test_webhook_thread_broadcast.py scripts/tests/bin/test_webhook_stale_cleanup.py
29 passed
```

The broader required suite did not pass:

```text
bats scripts/tests/lib/webhook.bats
59 passed, 6 skipped, 3 failed
not ok 25 Slack cluster parser accepts tokens in any order and dry-run isolates execution
not ok 66 webhook role helpers preserve token admin and fail closed
not ok 67 webhook fix mode requires operator+ role, not question phrasing
```

The changes remained in the isolated dispatch worktree and were not landed at that point. No live
Slack command was sent. The three failures were later diagnosed and corrected as described below.

## Follow-up offline verification — 2026-10-21

The three BATS failures were caused by the test harness calling
`SourceFileLoader.load_module()`, which is unavailable in the active Python 3.15.0 runtime. They
failed before reaching the webhook assertions. The test snippets now use `SourceFileLoader` with
`importlib.util`'s spec/module/`exec_module` APIs; production behavior was not changed to address
these interpreter-compatibility failures.

Independent verification in the isolated dispatch worktree:

```text
bats --filter 'Slack cluster parser accepts tokens in any order and dry-run isolates execution' scripts/tests/lib/webhook.bats
1..1
ok 1 Slack cluster parser accepts tokens in any order and dry-run isolates execution

bats --filter 'webhook role helpers preserve token admin and fail closed' scripts/tests/lib/webhook.bats
1..1
ok 1 webhook role helpers preserve token admin and fail closed

bats --filter 'fix mode requires operator' scripts/tests/lib/webhook.bats
1..1
ok 1 webhook fix mode requires operator+ role, not question phrasing

bats scripts/tests/lib/webhook.bats
1..68
68 passed, 5 skipped

python3 -m pytest -p no:cacheprovider -q scripts/tests/bin/test_webhook_thread_broadcast.py scripts/tests/bin/test_webhook_stale_cleanup.py
29 passed in 0.32s

shellcheck scripts/tests/lib/webhook.bats
git diff --check
_agent_lint exit=0
_agent_audit exit=0
```

The operator's 2026-10-21 screenshot shows the `/k3dm targets` response during an active AWS
`cluster-up`, confirming the responsive help path in live Slack. The same screenshot shows the
cluster-up progress update as a separate top-level message; that distinct thread-context defect
remains open under `2026-10-15-cluster-up-progress-slack-thread-missing.md`.
