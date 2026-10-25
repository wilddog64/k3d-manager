# Bug: the sandbox reaper's Slack notice fails every time, and the reason is thrown away

**Status:** OPEN — filed 2026-10-24; not dispatched
**Priority:** P3
**Severity:** low — the reap itself works; only the notice that says it happened is missing
**Release:** bug (does not count toward the five-plan cap); candidate for the vendor-LLM P2/P3 trial
**Filed:** 2026-10-24, by Claude, during the bug-status cleanup, while verifying `docs/bugs/2026-10-09-expired-acg-sandbox-leaves-hub-registration-and-apps.md`
**Approval:** explicit 2026-10-24. The operator approved the bug cleanup ("sounds like a plan"), which was proposed as status paperwork; filing this new finding falls under it. Dispatch is not critical (laptop LaunchAgent only), so it may dispatch once written.
**Component:** `bin/k3dm-sandbox-reaper` (`notify`), `bin/k3dm-slack-notify`
**Related:** `docs/bugs/2026-10-24-prometheus-rotator-never-posts-slack-notice.md` (same symptom class from another LaunchAgent; fixed in `a54d9489` by reading the hub Secret), `docs/plans/v1.43.8-slack-route-system-notices-to-status-channel.md` (system-started notices go where `platform-ops-notifications` points)

## Problem

The LaunchAgent `com.k3d-manager.sandbox-reaper` deregistered an expired ACG sandbox twice, and
both times the Slack notice failed. From `~/.local/share/k3d-manager/logs/sandbox-reaper.log`:

    [2026-10-21T20:02:53Z] deregistered ubuntu-k3s reason=credentials-dead unknown_for=30059s
    [2026-10-21T20:02:54Z] notify failed
    [2026-10-24T14:56:07Z] deregistered ubuntu-k3s reason=credentials-dead unknown_for=1805s
    [2026-10-24T14:56:07Z] notify failed

There were no other notify attempts and no successes. The operator was never told about either reap.

`notify()` runs `"${notify_bin}" >/dev/null 2>&1`, so the reason is lost. The default `notify_bin`
is `bin/k3dm-slack-notify`. It reads the webhook URL with `_keychain_secret("k3dm-slack-webhook")`,
from a LaunchAgent whose environment holds only `HOME` and `PATH`. The likely causes are a
Keychain read that fails in the launchd context, or a missing item. The cause was not confirmed:
confirming it means reading the secret or posting to Slack, and Claude does neither.

The other system notices (Grafana, Keycloak, ArgoCD, ACG expiry, and the Prometheus rotation since
`a54d9489`) read the URL from the hub Secret `platform-ops/platform-ops-notifications`, key
`slack-incoming-webhook-url`.

## Fix

### F1. Keep the failure reason

`notify()` in `bin/k3dm-sandbox-reaper` keeps the notifier's stderr and logs its last line after
`notify failed: `. Before logging, it replaces anything that looks like a URL with `<redacted>`.
The webhook URL must never reach the log.

### F2. Read the URL the way the other system notices do

`bin/k3dm-slack-notify` uses the URL in `SLACK_WEBHOOK_URL` when it is set. When it is unset, it
reads `platform-ops/platform-ops-notifications` key `slack-incoming-webhook-url` with
`kubectl --context k3d-k3d-cluster` (the same read as `_observability_notify_rotation`). Only when
both are empty does it fall back to the Keychain item. If no source gives a URL, it exits non-zero
with `k3dm-slack-notify: no Slack webhook URL` on stderr. The URL never goes into argv, never into
a trace, and never into a log.

## Tests

BATS in `scripts/tests/bin/sandbox_reaper.bats` (or the existing reaper suite), using stub
`kubectl`, a stub notifier and a stub Python poster. There are no real Slack or cluster calls.

1. A notifier that fails with `boom https://hooks.example/x` on stderr makes the reaper log
   `notify failed: boom <redacted>`, and the log contains no `https://`.
2. With `SLACK_WEBHOOK_URL` unset and a stub `kubectl` returning a base64 URL, the poster is called
   with that URL, and the URL does not appear in any process argv the stubs record.
3. With no env URL, `kubectl` failing and no Keychain item, `k3dm-slack-notify` exits non-zero with
   the message above.

## Acceptance

```yaml
must:
  - id: M1
    text: A failed reaper notice logs a reason, with any URL redacted.
  - id: M2
    text: k3dm-slack-notify gets the webhook URL from SLACK_WEBHOOK_URL, then the hub Secret platform-ops/platform-ops-notifications, then the Keychain.
must_not:
  - id: N1
    text: The reaper log must not contain only "notify failed" with no reason (red on the pre-fix reaper, which discards stderr).
  - id: N2
    text: A webhook URL must not appear in the log, in argv or in trace output.
  - id: N3
    text: No test may post to Slack or contact a cluster.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3]
    text: The reaper and notifier BATS are green; N1 is red on the pre-fix reaper in a temp copy.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: On the next sandbox expiry, the reaper log shows deregistered followed by no notify failure, and the notice arrives in Slack (operator confirms); or, if it fails, the logged reason names the cause.
interface:
  - bin/k3dm-sandbox-reaper (K3DM_SANDBOX_REAPER_NOTIFY_BIN, K3DM_SANDBOX_REAPER_LOG, K3DM_SANDBOX_REAPER_STATE_DIR)
  - bin/k3dm-slack-notify (message on stdin; SLACK_WEBHOOK_URL)
```

## What NOT to Do

- Do NOT read or print the webhook URL or the Keychain item, and do not post to Slack, in tests or by hand.
- Do NOT change the reap logic or its timings.
- Do NOT edit `scripts/lib/foundation/`.
