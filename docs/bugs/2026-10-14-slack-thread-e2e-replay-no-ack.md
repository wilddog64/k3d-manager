# Bug: Slack thread k3dm e2e-replay command receives no acknowledgment

**Status:** OPEN — response failure observed; underlying cause requires investigation
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 — ChatOps execution visibility
**Filed:** 2026-10-14, operator request
**Release:** v1.43.5 (triage 2026-10-15, operator-approved placement)
**Approval:** operator explicitly requested investigation and bug filing if necessary
**Component:** Slack Events API / thread reply router / Make target dispatch / thread job association
**Related:** `docs/bugs/2026-10-13-slack-logs-explicit-job-id-mismatch.md`

## Reproduction evidence

1. Operator previously ran `k3dm e2e-remote RUNNER=m2` through Slack. Bot returned `make e2e-remote RUNNER=m2 succeeded` with E2E rollout output in its thread.
2. In the **same Slack thread**, operator sent the bare message `k3dm e2e-replay RUNNER=m2`, which Slack displayed as `Also sent to the channel`.
3. More than approximately one minute later, the screenshot showed **no queued-job acknowledgment, rejection, status, or error reply**.

No live webhook logs or runner replay outcome were provided; the command may have been ignored, rejected, executed without visible acknowledgment, or affected by a Slack transport issue. Do not claim that M2 is unreachable or that replay failed.

## Repository findings

- `bin/k3dm-webhook`: `k3dm` is in `_THREAD_COMMANDS` (around line 640).
- `_handle_thread_command` parses `k3dm <target> KEY=value` and should respond with `k3dm e2e-replay queued — job <id>` after permission/target validation (around lines 744–785); parse or auth errors also notify.
- `/slack/events` routes messages with a `thread_ts` to an existing job or creates a thread anchor for standalone `k3dm` (around lines 2052–2078).
- `_find_job_by_thread_ts` returns the first matching job directory from an unsorted glob, and many jobs may share one Slack thread. This is an ambiguous association and may be related to the separate explicit-log-ID mismatch bug, but **is not yet established as the reason for silence**.
- The allowlisted `e2e-replay` target accepts required `RUNNER` and requires operator permission; `RUNNER=m2` is a valid default runner.

## Investigation requirements

1. Trace the actual Slack event, user role, Events API relay delivery, webhook event log and `_handle_thread_command` invocation at the reported timestamp. Distinguish no event, ignored event, authorization, rejected argument, active Make-job lock, job creation, and failed notification.
2. Inspect sanitized job directories, thread-id mappings, action/status records, queued notifications and `_MAKE_JOB_LOCK`. Determine whether `e2e-replay` actually ran; do not rerun it merely to diagnose history.
3. Verify whether `Also sent to the channel` changes the event's `thread_ts`, `ts`, subtype, or duplicate delivery behavior; honor Slack's event semantics.
4. Check interactions with jobs sharing one thread and the earlier `slack-logs-explicit-job-id-mismatch` issue. Avoid duplicate or competing fixes.
5. Ensure failures in delivery/notification are logged with safe reason codes, without secrets or arbitrary event payloads.

## Acceptance criteria

- [ ] A valid bare `k3dm e2e-replay RUNNER=m2` message in an existing E2E job thread receives an immediate queued-job acknowledgment, then a terminal response.
- [ ] A completed parent `e2e-remote` job does not prevent a subsequent valid thread command.
- [ ] Unsupported target, missing runner, insufficient role, active-job lock, and runner-unreachable paths produce explicit, understandable responses rather than silence.
- [ ] Multiple jobs sharing one thread do not misroute messages or statuses; test both known and orphan thread IDs.
- [ ] Duplicated Slack Events API deliveries do not trigger duplicate replay jobs.
- [ ] Replay remains authorized and scoped; tests use stubs instead of triggering real M2 publication.
- [ ] Tests cover event dispatch, thread association, acknowledgment failure diagnostics, and successful terminal posting.
- [ ] Live acceptance uses a controlled pending/no-pending replay in Slack and records whether reports were actually published; distinguish no pending reports from command failure.

**Scope:** File/report only. No webhook/runtime code or remote E2E results modified.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_dispatch.py`
- `scripts/tests/bin/test_webhook_thread_broadcast.py`
- `scripts/tests/bin/test_webhook_thread_actor.py`
- `scripts/tests/lib/webhook.bats`

## Verification gates

- `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_webhook_thread_dispatch.py scripts/tests/bin/test_webhook_thread_broadcast.py scripts/tests/bin/test_webhook_thread_actor.py`
- `bats scripts/tests/lib/webhook.bats`
- `shellcheck bin/k3dm-webhook`

Do not dispatch a live replay or publish reports during implementation; live acceptance remains operator-controlled.
