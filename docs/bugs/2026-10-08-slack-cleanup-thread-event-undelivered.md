# Slack cleanup thread messages were dropped at the relay root

**Status:** Fixed in `f127fd7b` and `d0eb99e8`; delivery resolved (bot was not in the channel)
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

## Recurrence — 2026-10-08 23:11Z (v1.42.0 live check)

A thread reply `cluster-diagnose` produced no `POST /slack/events` at all; the slash-command
form worked. Webhook log, `/slack/events` by hour (UTC) on 2026-10-08: 15h 18×200 / 80×401,
16h 2×200 / 14×401, 17h 2×401, then **nothing** — Slack stopped delivering after 17:00:35Z.
Slack disables an app's event delivery after sustained failures, which matches a 401 burst
followed by silence (unconfirmed — check the Slack app's Event Subscriptions page).

Second, independent risk: `scripts/lib/webhook/auth.py:33` reads `k3dm-slack-signing-secret`
from the keychain once, at import. The current webhook (pid 20722) started 23:03:02Z; the login
keychain was unlocked at 23:05:35Z, after a `make deploy-worker` failed on a locked keychain.
If the read failed, `SLACK_SIGNING_SECRET` is empty and every event is a 401 until restart.

Operator steps: `make restart-webhook` (keychain now unlocked), then re-enable/re-verify the
Request URL under the Slack app's Event Subscriptions, then retry the thread reply.

## Resolution + residual 401s — 2026-10-08 23:44Z

**Delivery resolved.** The test channel did not contain the bot. Slash-command replies go out
through `response_url`, which works in any channel, but `message.channels` events are only
sent for channels the bot has joined. In a channel the bot is in, a plain thread reply
`cluster-diagnose hub pods monitoring` worked end to end: the log shows
`slack orphan thread anchor_id='fbe1aa7e'`, and job `08d3e617` posted the pod table into the thread.

**Residual defect — oversized events fail the signature check.** In the same window, about one
`/slack/events` in three still returns 401. Each one arrives 1–2s after the bot has posted:

```
23:44:44Z slack top-level command='cluster-diagnose'   200
23:44:46Z /slack/events 401
23:44:46Z /slack/events 401
23:46:04Z ... 200 (job post)  23:46:06Z 401  23:46:07Z 401
```

Cause: `do_POST` reads `self.rfile.read(min(length, MAX_BODY))`, and
`MAX_BODY = 4096` (`scripts/lib/webhook/config.py:15`). When the bot posts a message, Slack
sends an event for it, and that event carries the full `text` and `blocks`. A diagnostics table
is far larger than 4 KB, so the body is truncated and the HMAC over the truncated body fails. The
relay checked the same request against the full body, and it passed there. The bot's own messages
would be dropped anyway (`bot_id`), so nothing visible breaks today, but:
- every bot post adds 401s to Slack's failure count. Slack disables an app's event delivery when
  most of its events fail within an hour, and the 15–16h 80×401 run fits this pattern;
- a human message over 4 KB would be rejected the same way.

### Fix (spec for Codex)

Files: `scripts/lib/webhook/config.py`, `bin/k3dm-webhook`, `workers/slack-relay/index.js`,
`workers/slack-relay/test/relay.test.mjs`, `scripts/tests/lib/webhook.bats`, this doc, memory-bank.

**1. `scripts/lib/webhook/config.py`** — after `MAX_BODY = 4096` add:

```python
SLACK_EVENT_MAX_BODY = 65536
```

**2. `bin/k3dm-webhook`**
- Add `SLACK_EVENT_MAX_BODY,` to the `from webhook.config import (...)` list, directly after `MAX_BODY,`.
- In `do_POST`'s `/slack/events` branch:

Old:
```python
            raw_body = self.rfile.read(min(length, MAX_BODY))
```
New:
```python
            if length > SLACK_EVENT_MAX_BODY:
                self._json(413, {"error": "request too large"})
                return
            raw_body = self.rfile.read(length)
```

- Thread usage text (around line 724). Make it match the relay's slash usage, `pod <namespace> <pod>`.
  The parser already accepts both `pod` and `describe-pod`:

Old: `describe-pod <namespace> <pod>` inside the ``Usage: `cluster-diagnose ...` `` string
New: `pod <namespace> <pod>`

**3. `workers/slack-relay/index.js`** — in the `/slack/events` branch, directly after the
`verifySlack` 401 line, add:

```js
    let parsedEvent = null
    try { parsedEvent = JSON.parse(body) } catch (_) { parsedEvent = null }
    const innerEvent = parsedEvent && parsedEvent.type === 'event_callback' ? (parsedEvent.event || {}) : null
    if (innerEvent && (innerEvent.bot_id || innerEvent.subtype)) {
      return new Response('{"ok":true}', { status: 200, headers: { 'Content-Type': 'application/json' } })
    }
```
(url_verification and human messages are still forwarded unchanged.)

**4. Tests**
- `workers/slack-relay/test/relay.test.mjs`, next to the root-JSON forwarding test:
  - `event_callback` with `event.bot_id` → 200 and `worker.fetches.length === 0`.
  - `event_callback` with `event.subtype: 'message_changed'` → not forwarded.
  - a human `event_callback` (user set, no bot_id or subtype) → forwarded once to
    `https://webhook.test/slack/events`, with the body unchanged.
- `scripts/tests/lib/webhook.bats`:
  - `Slack event larger than 4 KB is verified on the full body`: build a signed
    `{"type":"event_callback","event":{"type":"message","bot_id":"B1","text":"<5000 x's>","ts":"9"}}`
    with `_slack_event`, then assert the response contains `"ok":true`. Before the fix it returns
    `invalid signature`.
  - `Slack event over the Slack cap returns 413`: send 70000 bytes with
    `curl -s -o /dev/null -w "%{http_code}"`, signed or not, and assert `413`.
- **RED is mandatory:** run the new webhook test against the pre-fix `bin/k3dm-webhook` on a
  temp copy. It must fail with `invalid signature`. Do NOT revert the working tree to do this.

**Gates:** `node --test workers/slack-relay/test/relay.test.mjs`;
`bats scripts/tests/lib/webhook.bats` (it starts its own webhook — leave `K3DM_JOB_DIR`/`K3DM_RUN_DIR`
to the harness and never touch the live :7443 instance); `python3 -m py_compile bin/k3dm-webhook`.

**Operator after merge to branch:** `make restart-webhook` and `make deploy-worker`.

## Fix applied

Implemented the specified full-body Slack event verification and 64 KiB cap in
`f127fd7b`, plus edge acknowledgment for Slack bot-echo and subtype events in
`d0eb99e8`. Human event callbacks and URL verification remain forwarded unchanged.
