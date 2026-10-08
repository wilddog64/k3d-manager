# Slack cleanup thread messages were dropped at the relay root

**Status:** Relay compatibility fixed and deployed; Slack Events delivery still blocked
**Severity:** P1 — cleanup follow-up commands were silently ignored
**Component:** Cloudflare Slack relay / Slack Events forwarding

## Evidence

The operator posted `cleanup-stale-sandbox apply` in the cleanup thread. The bot did not
respond. The local webhook log showed the slash-command API request but no `POST /slack/events`
for the plain thread message, while other thread commands are known to use that event path.

## Root cause

The relay handled Slack Events only when the request path was exactly `/slack/events`. The same
worker root URL is used for slash commands. If Slack Event Subscriptions points at that root,
the JSON event was treated as URL-encoded slash-command data and was never forwarded to the
webhook. This was silent because the root handler returned its normal command response path.

## Fix

The relay now recognizes a root `POST` with `Content-Type: application/json` as a Slack Event
and forwards it to `/slack/events` on the webhook. The explicit `/slack/events` path remains
supported. This preserves form-encoded slash-command behavior at the root.

## Validation

```text
node --test workers/slack-relay/test/relay.test.mjs
ℹ tests 41
ℹ pass 41
ℹ fail 0
```

The new regression test proves that a signed root JSON Slack Event is forwarded unchanged to
the webhook event endpoint. The worker was deployed as Cloudflare version
`e9d3dfc2-ee92-4444-938f-440b4bcc9aad` on 2026-10-08, but the retry still produced no
webhook request or job. The next required check is the Slack app Event Subscriptions Request
URL and `message.channels`/`message.groups` bot subscriptions; the repository cannot change
those workspace settings. The immediate supported path remains invoking
`/cleanup-stale-sandbox apply` as a slash command.
