# Bug: hub migration drops the webhook Slack bot config, so every /ask-docs and /ask reply is ephemeral

**Status:** OPEN
**Priority:** P2
**Severity:** medium — Slack answers still arrive, but only as "Only visible to you"; no bot threads, no thread follow-ups
**Approval:** operator, 2026-10-31 ("go ahead"), in reply to Claude's proposal to file it
**Filed:** 2026-10-31
**Detected by:** operator (`/ask-docs` in #acg-automation answered "Only visible to you" at 07:32 and 07:33 PDT)
**Affected:** `bin/k3dm-webhook-setup` (called by `bin/hub-new`), `bin/k3dm-webhook-doctor`, `docs/howto/m5-hub-migration.md`
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/plans/v1.43.12-m5-new-hub-one-command.md`; `docs/bugs/2026-10-24-platform-ops-notifications-slack-url-lost-on-hub-rebuild.md` (same class: a hub rebuild loses a Slack setting that lived outside git)

## Observed failure

After the move to the M5 hub, `/ask-docs` asked in #acg-automation came back as "Only visible to you" instead of a bot thread. The webhook jobs `4f33a864` and `fbfe5299` have no `thread_ts` file.

Live facts, 2026-10-31 (read-only):

- M4 `~/Library/LaunchAgents/com.k3d-manager.webhook.plist` `EnvironmentVariables` keys: `KUBECONFIG`, `PATH`, `SLACK_BOT_TOKEN`, `SLACK_CHANNEL_ID`, `SLACK_SIGNING_SECRET`.
- M5 webhook process (pid 49875, started 2026-10-31T01:43Z) environment: no `SLACK_*` variable at all.
- The bot token was in the M5 Keychain (`k3d-manager-slack-bot-token-bot`); only the plist step was missing.
- Signing still worked, because `scripts/lib/webhook/auth.py` falls back to the Keychain for `SLACK_SIGNING_SECRET`. That is why commands reached the webhook at all.

The operator ran `SLACK_CHANNEL_ID=C0B7ZHG2LR4 make update-webhook-slack` on the M5 (14:36Z). The webhook restarted with both values, and the 07:37 PDT `/ask-docs` question replied in a thread.

## Root cause

`bot_thread` in `bin/k3dm-webhook` and `scripts/lib/webhook/agent.py` needs `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID`, and both come only from the plist environment (`scripts/lib/webhook/config.py`). The only writer of those two keys is `make update-webhook-slack`. `bin/k3dm-webhook-setup` renders the plist from `scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl` without them. `bin/hub-new` calls `bin/k3dm-webhook-setup`. Neither `hub-new`, `bin/k3dm-machine-setup` nor `docs/howto/m5-hub-migration.md` runs or names `update-webhook-slack`, so a new hub silently loses the bot config. `make webhook-doctor` checks the launchd job, listener and health, not the Slack config, so nothing flagged it.

## Fix

1. `bin/k3dm-webhook-setup` keeps `SLACK_BOT_TOKEN`, `SLACK_CHANNEL_ID` and `K3DM_STATUS_CHANNEL_ID` when it rewrites an existing plist. It does not drop keys that were already there.
2. `bin/hub-new` gets a check: when the hub Keychain holds `k3d-manager-slack-bot-token-bot` and the rendered plist has no `SLACK_BOT_TOKEN` or `SLACK_CHANNEL_ID`, the report records a failure that names `make update-webhook-slack` with `SLACK_CHANNEL_ID` exported. `hub-new` never reads or prints the token value.
3. `bin/k3dm-webhook-doctor --check` reports `slack_bot: configured | missing_token | missing_channel` from the plist's key presence only, never the values.
4. `docs/howto/m5-hub-migration.md` adds the step `SLACK_CHANNEL_ID=<id> make update-webhook-slack`, run in a local terminal because it reads the login Keychain, and the check that a `/ask-docs` question in the channel replies in a thread.

## Acceptance

```yaml
must:
  - id: M1
    text: rerunning bin/k3dm-webhook-setup on a plist that has SLACK_BOT_TOKEN, SLACK_CHANNEL_ID and K3DM_STATUS_CHANNEL_ID keeps all three with their values
  - id: M2
    text: bin/hub-new records a failing check naming make update-webhook-slack when the Keychain has the bot token but the webhook plist lacks SLACK_BOT_TOKEN or SLACK_CHANNEL_ID
  - id: M3
    text: bin/k3dm-webhook-doctor --check JSON has slack_bot = configured when both keys are present, missing_token or missing_channel otherwise
  - id: M4
    text: docs/howto/m5-hub-migration.md names make update-webhook-slack and the threaded-reply check
must_not:
  - id: N1
    text: no check, report or log line prints the SLACK_BOT_TOKEN value or any prefix of it
  - id: N2
    text: bin/hub-new passes the Slack check when both keys are present (paired positive control for M2)
  - id: N3
    text: tests never read the real login Keychain or write under the real ~/Library/LaunchAgents; fixtures assert a scratch HOME and a stub security first
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: BATS/pytest with scratch HOME, stub security and plist fixtures with and without the keys; N1 greps every captured output for the fixture token; each must_not red on the pre-fix code
  - id: E2
    proves: [M4]
    kind: offline
    text: make check-doc-links; Claude reviews the how-to step
  - id: E3
    proves: [M2, M3]
    kind: live
    text: on the M5, make webhook-doctor shows slack_bot configured; a /ask-docs question in #acg-automation replies in a thread
interface:
  - bin/k3dm-webhook-setup
  - bin/hub-new
  - bin/k3dm-webhook-doctor --check
  - docs/howto/m5-hub-migration.md
```
