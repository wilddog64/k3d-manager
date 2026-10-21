# Bug: jobs started from a Slack thread record the role, not the user

**Filed:** 2026-10-18 (Claude, from an operator screenshot)
**Status:** LIVE-VERIFIED — 2026-10-21: operator's Slack thread screenshot shows the job started by `slack-thread:U4C9LDQP2`, satisfying E2.
**Live evidence:** 2026-10-21 · run 4148ca73 · env slack/k3d-manager · scenario thread-fix-list-actor · commit bc1399eb · proves fix
**Fix commit:** `bc1399eb`
**Priority:** P3 — audit-trail gap; the command runs correctly
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "file a P3 bug as you mention above"
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-webhook` (`_handle_thread_command`, Slack Events routing)
**Related:** `docs/bugs/2026-10-18-slack-thread-broadcast-reply-silently-ignored.md` (same routing
block; dispatch this after that one lands to avoid a rebase conflict)

## Symptom

On 2026-10-18 the same operator started `e2e-sandbox-provision` twice:

| From | "started by" line |
|---|---|
| top-level `/k3dm e2e-sandbox-provision` | `slack:wilddog64:U4C9LDQP2` |
| thread reply `k3dm e2e-sandbox-provision confirm` (job `f5e6229f`) | `slack-thread:admin` |

A job started in a thread does not say who started it, only the role. With more than one admin the
audit trail cannot tell them apart.

## Root cause

The Slack Events handler knows `ev_user` but passes only `role` to `_handle_thread_command`
(`bin/k3dm-webhook` ~2063, ~2077, ~2092). That function then names the actor
`f"slack-thread:{role}"` for a `/k3dm` make job (~782), and `"slack"` in its `_audit_remote_action`
calls (~712).

## Fix

- **F1.** Add a keyword parameter `user_id=""` to `_handle_thread_command`. Pass `ev_user` from every
  Slack Events call site.
- **F2.** Inside `_handle_thread_command`, build one actor string:
  `f"slack-thread:{user_id}"` when `user_id` is set, else the existing `f"slack-thread:{role}"`. Use it
  for the `_run_make_target` actor and as the `actor` argument of every `_audit_remote_action` call in
  the function (replacing `"slack"`). The `role` argument of those calls is unchanged.
- **F3.** Tests in `scripts/tests/bin/test_webhook_thread_actor.py`, with `_run_make_target`,
  `_audit_remote_action`, `_notify_job` and thread start stubbed.

No Slack API lookup of the display name: the user ID alone identifies the person, and the
allowlist/role map is already keyed by it.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_actor.py`
- `scripts/tests/bin/test_webhook_thread_broadcast.py` (added at verification: its `_handle_thread_command` stub must accept the new `user_id` keyword)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A thread reply "k3dm <target> ..." from user U123 starts _run_make_target with actor "slack-thread:U123".
  - id: M2
    text: A thread command refused for role records an audit entry whose actor is "slack-thread:U123", not "slack".
  - id: M3
    text: A caller that passes no user_id still gets actor "slack-thread:<role>".
must_not:
  - id: N1
    text: A thread-started make job must not be attributed only to the role when the user is known (red on pre-fix, which records "slack-thread:admin").
  - id: N2
    text: Role checks must not change; the user ID must not grant or remove any permission.
  - id: N3
    text: No message text, token or secret is added to the actor or audit entry.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/test_webhook_thread_actor.py; N1 red on the pre-fix webhook.
  - id: E2
    proves: [M1]
    kind: live
    text: After make restart-webhook the operator starts a /k3dm target from a thread; Claude reads the screenshot showing "started by slack-thread:U…".
interface:
  - bin/k3dm-webhook _handle_thread_command(job_id, command, role, channel_id, user_id="")
  - bin/k3dm-webhook _run_make_target(job_id, argv_tail, timeout, actor)
  - scripts/lib/webhook/policy.py _audit_remote_action(path, action_name, actor, role, allowed, body=None, reason="")
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix webhook.
- [ ] `pytest scripts/tests/bin` green.
- [ ] Commit: `fix(webhook): thread-started jobs record the Slack user`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT call the Slack API or start real jobs in tests.
- Do NOT change role resolution, the allowlist, or the top-level `/k3dm` actor.

## Verification log

- 2026-10-19: Codex (dispatcher) fix landed `bc1399eb`. Claude verified: on the pre-fix webhook, 4 of the 5 `test_webhook_thread_actor.py` tests are red (N1). The fallback-to-role test passes either way (M3). Codex's change broke the thread-broadcast routing test, whose stub took no kwargs; Claude updated that test to assert `user_id` is passed. It landed with `--allow-out-of-scope`, and the spec Files now list it. `pytest scripts/tests/bin` 734 passed, 1 skipped.
- 2026-10-21: Operator ran `k3dm fix-list` as a reply in a bot thread. Slack job `4148ca73` displayed `started by slack-thread:U4C9LDQP2` and succeeded, proving the actor is the Slack user rather than the role. E2 is satisfied; marked LIVE-VERIFIED.
