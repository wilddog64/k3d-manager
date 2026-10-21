# Follow-up: preserve Slack delivery context for explicit job replies

**Branch:** `k3d-manager-v1.43.5`
**Priority:** P2
**Status:** DISPATCH SPEC — operator live check showed an explicit `status <job-id>` reply did not appear
**Approval:** operator authorized this scoped offline fix on 2026-10-21. Do not send Slack messages, run live jobs, deploy, or create a PR.
**Parent bug:** `docs/bugs/2026-10-21-slack-multi-job-thread-implicit-job-correlation.md`

## Problem

The explicit-target handler resolves a job ID and then sends successful `status`/`logs` replies using that target job's notification context. A target job such as a `cluster-status` child can have `thread_ts` but lack `channel_id`; its parent thread anchor has the channel context. The live operator check showed the explicit status request received no visible bot reply. Preserve trusted parent Slack delivery context on the target before sending the response.

## Scope

Only change these files:

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_dispatch.py`

## Acceptance criteria

- After a valid same-thread explicit target is resolved, its delivery context includes the parent thread's channel and thread metadata before a successful `status` or `logs` response is sent.
- An explicit target from another thread or channel remains rejected, and the rejection is delivered through the parent context.
- Add isolated regression coverage for successful explicit-target reply context and retain cross-thread/channel rejection coverage.
- No tests make real Slack calls or run live jobs.

## Gates

Run focused tests:

```bash
python3 -m pytest -q -p no:cacheprovider scripts/tests/bin/test_webhook_thread_dispatch.py scripts/tests/bin/test_webhook_thread_broadcast.py
```

Also run `git diff --check`, parse `bin/k3dm-webhook` with Python AST (avoid writing `__pycache__`), and run `bash ./scripts/k3d-manager _agent_audit`.

## Stop conditions

Do not modify deployment configuration, send Slack messages, trigger jobs, mark LIVE-VERIFIED, or create a PR. Report any additional delivery defect outside this scope without silently expanding the task.
