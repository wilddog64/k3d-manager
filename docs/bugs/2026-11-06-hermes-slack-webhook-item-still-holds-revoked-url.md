# Bug: Hermes still reads the revoked Slack webhook after the replacement

**Status:** OPEN — confirmed 2026-11-06 on the M5; hand fix given to the operator, not yet confirmed
**Priority:** P2
**Approval:** pending
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-10-31-rotator-slack-notice-failure-is-silent.md` (found the revocation); `docs/bugs/2026-10-24-sandbox-reaper-slack-notice-always-fails.md` (same item); `docs/bugs/2026-11-06-hub-cutover-verify-accepts-hermes-unknown.md`

## Symptom

Slack test from the M5, 2026-11-06, using the Hermes code path: `delivered: False`. The same URL through `curl`, with the operator's terminal output showing only the reply: `no_service http=404`. Hermes reads this URL for all its summaries, pages and E2E results, and `bin/k3dm-slack-notify` for sandbox reaper notices. Any Hermes alert raised now is lost, and `post_summary` swallows the reason.

## Cause

Two Keychain items hold a Slack webhook. The 2026-11-06 replacement updated `k3dm-platform-ops-slack-url` (date 2026-11-06T02:11:13Z) and the cluster Secret. `k3dm-slack-webhook` still dates from 2026-10-30T16:39:07Z, and nothing connects the two. Nothing tests the item either: `make hub-cutover-verify` only prints a request to check Slack.

## Files

- `bin/k3dm-hermes`
- `scripts/lib/hermes/slack.py`
- `docs/howto/platform-ops-notifications.md`
- `docs/guides/hermes.md`
- `scripts/tests/hermes/test_hermes.py`

## Fix direction

Decide whether one Keychain item can serve both, or document that a replacement must update both. Have Hermes record a failed post with the HTTP status and Slack's short reply, never the URL. Hermes should report a failing Slack route on its own status.

## Acceptance

```yaml
must:
  - id: M1
    text: "When a Hermes Slack post is refused, the Hermes log records the HTTP status and Slack's short reply."
  - id: M2
    text: "When the post is accepted, no failure is logged."
  - id: M3
    text: "The webhook replacement how-to names every Keychain item and Secret that must change, and the check that proves each."
must_not:
  - id: N1
    text: "No log line contains the webhook URL (paired with M1)."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, text: "Test with a stub endpoint returning the 404 no_service reply captured 2026-10-31 from the M5, and a 200; M1 red on the pre-fix commit; N1 red by a mutant."}
  - {id: E2, proves: [M1, M2], kind: live, text: "The Hermes code path posts to Slack from the M5, and the operator sees the message."}
interface:
  - "scripts/lib/hermes/slack.py post_summary"
  - "bin/k3dm-slack-notify"
  - "Keychain items: k3dm-slack-webhook, k3dm-platform-ops-slack-url"
```
