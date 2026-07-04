# Issue: `/cluster-status` can appear silent when the Worker waits on the webhook before acking Slack

**Date:** 2026-07-01
**Branch:** `k3d-manager-v1.12.0`
**Area:** `workers/slack-relay/index.js`

## Symptom

Issuing `/cluster-status` in Slack produced no visible reply even after waiting
more than 2 minutes.

## Investigation

The live Slack channel history showed earlier `/cluster-status` confusion but
no fresh bot reply for the new invocation. Repo inspection showed the slash
command path was implemented, but the Cloudflare Worker handled slash commands
like this:

- verify Slack signature
- `await relay(...)` to the webhook
- only then return the ephemeral Slack ack

That means Slack does not receive any immediate acknowledgement if the relay
call is slow or unreachable. The user experience is "no response", even though
the command handler itself is correct.

## Root Cause

The Worker serialized the user-facing ack behind the webhook dispatch instead of
returning the ack immediately and completing the relay in the background.

## Fix

`workers/slack-relay/index.js` now:

- returns the slash-command ack immediately
- uses `event.waitUntil(...)` to send the webhook request in the background
- posts a fallback error back to the slash command `response_url` if the relay
  fails

`scripts/tests/plugins/slack_relay_ack.bats` now guards the new ack-first
behavior.
