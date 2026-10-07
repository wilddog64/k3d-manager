# Slack status replies lose thread context

## Status

Fixed on `k3d-manager-v1.42.0`.

## Evidence

After `make restart-webhook` succeeded, Slack `/cluster-status` still rendered the
healthy report as a top-level response instead of keeping the report in the command
thread. The companion `cluster-diagnose` path had the same risk.

## Root cause

The Slack relay forwarded `channel_id` for `/cluster-status`, but omitted it for
`/cluster-diagnose`. Separately, native Slack message-event dispatch passed only the
job, command, and role into `_handle_thread_command`; the event's channel ID was
discarded before the status worker was started. The status renderer intentionally
uses the response URL fallback when the request channel cannot be proven to be the
configured bot channel.

## Fix

- Forward `channel_id` with `/cluster-diagnose` requests.
- Preserve the Slack event channel ID through thread-command dispatch.
- Pass that value to Hostinger and provider-aware cluster status workers.

## Verification

- `pytest -q scripts/tests/bin/test_webhook_cluster_status_thread.py` — 11 passed.
- `node --test workers/slack-relay/test/relay.test.mjs` — 33 passed.
- Python compilation and `git diff --check` passed.

## Acceptance

- A status command invoked in the configured Slack channel posts its report in the
  existing thread, or creates one top-level verdict thread when invoked at channel
  level.
- A diagnostics command receives the same channel context and follows the same rule.
- Requests from another channel continue using the response URL and never post to
  the configured bot channel.
