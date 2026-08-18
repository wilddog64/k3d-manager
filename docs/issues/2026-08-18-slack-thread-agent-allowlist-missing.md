# Slack agent stopped replying to authorized threads

## Symptom

Slack events reached the webhook and signature verification succeeded, but the agent stopped
replying to messages from the owner. The webhook log recorded:

```text
[slack/events] ignored type='message' user='U4C9LDQP2' reason=unallowlisted
```

## Investigation

The v1.21 webhook hardening correctly changed Slack authorization to fail closed. The role map is
loaded from `K3DM_SLACK_ROLE_MAP` or the Keychain item `k3dm-slack-role-map`. On this host the
Keychain lookup failed with:

```text
security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.
```

The LaunchAgent also has no `SLACK_BOT_TOKEN` or `SLACK_CHANNEL_ID`, so the bot API fallback used
for older-thread context is unavailable until those existing deployment credentials are injected.

## Root cause

The hardening release documented that an owner must provision the role map, but the deployment path
did not provide a Make target to do that. A fresh or rebuilt host therefore treated every Slack
user as unallowlisted. This is a deployment/configuration bug, not a Slack signature failure.

## Fix

`make update-webhook-slack-roles K3DM_SLACK_ROLE_MAP=U123:admin[,U456:operator...]` now stores the
allowlist in the macOS Keychain without printing it, restarts the webhook, and keeps the secret out
of source control. The current owner mapping was provisioned as `U4C9LDQP2:admin` and the webhook
was restarted.

For thread history and bot-authenticated replies, separately run the existing
`make update-webhook-slack SLACK_BOT_TOKEN=... SLACK_CHANNEL_ID=...` target with the deployment's
real values; no token is hardcoded or recorded here.

## Verification

- Confirm the Keychain item is readable by the webhook process without printing its value.
- Restart the LaunchAgent and verify the health endpoint and webhook import succeed.
- A live Slack message from `U4C9LDQP2` should no longer log `reason=unallowlisted`.

The import check after provisioning reported `role_map_loaded=True` and `role=admin`, and the
LaunchAgent rebound `127.0.0.1:7443`. The full webhook BATS suite was attempted, but the local HTTP
harness was unavailable; its affected requests exited with curl status 7. This is an environment
failure, not a role-map assertion failure, and must be rerun when the test harness is available.
