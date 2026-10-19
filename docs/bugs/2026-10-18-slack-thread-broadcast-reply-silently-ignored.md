# Bug: a Slack thread reply sent with "Also send to channel" is silently ignored

**Filed:** 2026-10-18 (Claude, from an operator screenshot)
**Status:** OPEN
**Priority:** P3 — the command is not run and nothing replies; resending without the checkbox works
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "yes" to filing and dispatching to Codex
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-webhook` (Slack Events API message routing)
**Related:** `docs/bugs/2026-06-08-thread-reply-triggers-unknown-command.md` (thread-reply routing);
`docs/bugs/2026-10-18-slack-cleanup-accepts-apply-as-confirm-synonym.md` (the live check that found this)

## Symptom

On 2026-10-18 the operator replied `cleanup-stale-sandbox confirm` in a thread with **Also send to
channel** ticked. Nothing ran and nothing replied, and `~/Library/Logs/k3dm-webhook.log` has no line
for it. The same command sent in a thread without the checkbox ran normally.

## Root cause

Slack delivers a thread reply that is also sent to the channel as a `message` event with
`subtype: "thread_broadcast"`. `bin/k3dm-webhook` (~2035 and ~2049) routes a message only when
`not ev_subtype`, so the event falls through to `200 ok` with no log line at INFO.
The unallowlisted-user notice (~2035) has the same filter.

## Fix

- **F1.** In `bin/k3dm-webhook`, add a module-level helper
  `_slack_message_is_command_candidate(ev)` that returns True when `ev["type"] == "message"`, there is
  no `bot_id`, the stripped `text` is non-empty, and `subtype` is empty **or** `"thread_broadcast"`.
  Every other subtype (`message_changed`, `message_deleted`, `bot_message`, `channel_join`, …) stays
  False.
- **F2.** Use the helper in both places that test `ev_type == "message" and not ev_bot_id and not
  ev_subtype and ev_text`: the unallowlisted notice and the main routing block. Routing is otherwise
  unchanged: a `thread_broadcast` has `thread_ts != ts`, so it takes the existing thread-reply path
  (job thread → `_handle_thread_command`; orphan thread + standalone command → anchor).
- **F3.** When a `message` event is dropped because of its subtype, log one INFO line
  `slack message ignored subtype=<subtype>` (no text, no user), so the next silent drop is visible.
- **F4.** Tests in a new `scripts/tests/bin/test_webhook_thread_broadcast.py`: the helper truth table,
  and a routing test that posts a `thread_broadcast` event for a known job thread and asserts
  `_handle_thread_command` is called with the text (stub the thread start, Slack posting and the
  signature check the same way the existing webhook tests do).
- **F5.** `docs/howto/slack-slash-commands.md`: one line that thread replies work with or without
  "Also send to channel".

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_broadcast.py`
- `docs/howto/slack-slash-commands.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A message event with subtype "thread_broadcast", thread_ts != ts, a human user and command text is routed exactly like the same event with no subtype (thread reply → _handle_thread_command for the job, or an orphan anchor for a standalone command).
  - id: M2
    text: _slack_message_is_command_candidate is True for subtype "" and "thread_broadcast" with text and no bot_id.
  - id: M3
    text: A message dropped for its subtype logs "slack message ignored subtype=<subtype>" at INFO without the message text.
must_not:
  - id: N1
    text: A thread_broadcast command must not be silently dropped (red on pre-fix, which never calls _handle_thread_command for it).
  - id: N2
    text: message_changed, message_deleted, bot_message and any event with bot_id must still not be routed (no edited message re-runs a command, no bot loop).
  - id: N3
    text: An unallowlisted user's thread_broadcast command must still not run; it gets the existing not-authorized notice.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/test_webhook_thread_broadcast.py with Slack and threads stubbed; N1 red on the pre-fix webhook.
  - id: E2
    proves: [M1]
    kind: live
    text: After make restart-webhook the operator replies "cluster-status" in a bot thread with "Also send to channel" ticked; Claude reads the screenshot showing the reply.
interface:
  - bin/k3dm-webhook _slack_message_is_command_candidate(ev)
  - bin/k3dm-webhook Slack Events POST handler (event_callback with event.type "message")
  - bin/k3dm-webhook _handle_thread_command(job_id, command, role, channel_id), _find_job_by_thread_ts(thread_ts)
```

## Definition of Done

- [ ] F1–F5 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix webhook.
- [ ] `pytest scripts/tests/bin` green.
- [ ] Commit: `fix(webhook): route Slack thread replies also sent to the channel`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT contact Slack or start real jobs in tests; stub them.
- Do NOT route `message_changed` or any other subtype; only `thread_broadcast` is added.
- Do NOT log message text or user IDs in the new INFO line.
