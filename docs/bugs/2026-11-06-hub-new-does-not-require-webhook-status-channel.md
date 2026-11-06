# Bug: a new hub can finish with no webhook status channel, so every analyzer post is lost

**Status:** FIXED offline `c1e05278`, independent verify PASS 2026-11-06; live E3 pending. Hand fix on the M5 2026-11-06 (`K3DM_STATUS_CHANNEL_ID=C4CAEH8HX`)
**Priority:** P2
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"
**Filed:** 2026-11-06
**Detected by:** Claude, tracing the missing analyzer posts
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-10-31-hub-migration-drops-webhook-slack-bot-config.md` (Recurrence 2026-11-06); `docs/bugs/2026-11-06-webhook-analyze-reports-success-when-slack-post-fails.md`

## Symptom

From the migration until the 2026-11-06 hand fix, the M5 webhook plist had `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` but no `K3DM_STATUS_CHANNEL_ID`. `_run_analyze` then has no route, so no analysis reached Slack. `make hub-new` and `make webhook-doctor` both reported no problem.

## Cause

`bin/hub-new` checks only `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID`. `bin/k3dm-webhook-doctor` has no check for the status channel. `bin/k3dm-webhook-setup` preserves `K3DM_STATUS_CHANNEL_ID` only from a plist already on that host, and `docs/howto/m5-hub-migration.md` does not name it. `make update-webhook-slack` already accepts it from the environment.

## Files

- `bin/hub-new`
- `bin/k3dm-webhook-doctor`
- `scripts/tests/bin/hub_new.bats`
- `scripts/tests/bin/test_webhook_doctor.py`
- `docs/howto/m5-hub-migration.md`
- `CHANGELOG.md`

## Fix

1. In the `bin/hub-new` plist check, add `K3DM_STATUS_CHANNEL_ID` to the required keys. The `fail` hint names `K3DM_STATUS_CHANNEL_ID` and `make update-webhook-slack`.
2. `bin/k3dm-webhook-doctor --check` adds `status_channel: configured | missing`, from key presence only, following `_slack_bot_status`.
3. The how-to adds the key to the `update-webhook-slack` step, and the check that an analyzer post reaches the channel.

No channel ID is hardcoded: the ID is per-workspace operator configuration.

## Acceptance

```yaml
must:
  - id: M1
    text: "bin/hub-new records a failing check naming K3DM_STATUS_CHANNEL_ID and make update-webhook-slack when the Keychain has the bot token and the webhook plist lacks K3DM_STATUS_CHANNEL_ID."
  - id: M2
    text: "bin/hub-new passes this check when all three keys are present (paired positive control for M1)."
  - id: M3
    text: "bin/k3dm-webhook-doctor --check JSON has status_channel = configured when the key is present and missing when it is absent."
  - id: M4
    text: "docs/howto/m5-hub-migration.md names K3DM_STATUS_CHANNEL_ID and a check that an analyzer post arrives."
must_not:
  - id: N1
    text: "No check, report or log line prints SLACK_BOT_TOKEN or any prefix of it."
  - id: N2
    text: "Tests never read the real login Keychain or write under the real ~/Library/LaunchAgents; fixtures assert a scratch HOME and a stub security first."
  - id: N3
    text: "No Slack channel ID literal is added to bin/hub-new or bin/k3dm-webhook-doctor."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2, N3], kind: offline, text: "BATS and pytest with a scratch HOME, stub security and plist fixtures with and without the key; M1 and M3 red on the pre-fix commit; N1 and N3 red by a mutant."}
  - {id: E2, proves: [M4], kind: offline, text: "make check-doc-links; Claude reviews the how-to step."}
  - {id: E3, proves: [M3], kind: live, text: "On the M5, make webhook-doctor shows status_channel configured."}
interface:
  - "bin/hub-new"
  - "bin/k3dm-webhook-doctor --check"
  - "docs/howto/m5-hub-migration.md"
  - "plist keys: SLACK_BOT_TOKEN, SLACK_CHANNEL_ID, K3DM_STATUS_CHANNEL_ID"
```
