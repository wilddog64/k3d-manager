# Bug: Slack relay drops `channel_id` for `/cluster-up` and `/cluster-down`, so job updates are never threaded and the 6th is lost

**Status:** OPEN
**Priority:** P2
**Severity:** medium — every `/cluster-up` / `/cluster-down` update goes to `response_url` instead of a bot thread; Slack accepts at most five posts per `response_url`, so a long job's later updates (the failure analysis or the final result) are rejected and never shown
**Approval:** operator, 2026-11-01 ("the cluster-up does not post result in a thread")
**Filed:** 2026-11-01
**Detected by:** operator (Slack, job `ec9ce66c`), root cause by Claude
**Affected:** `workers/slack-relay/index.js` (`/cluster-up` branch line ~405, `/cluster-down` line ~420)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md` (thread context for thread-command child jobs; a different path); `docs/bugs/2026-10-22-slack-thread-replies-posted-to-channel-via-response-url.md`

## Observed failure

2026-11-01 07:23 PST, `/cluster-up aws` in Slack → webhook job `ec9ce66c` on the M5. Its replies did not appear in a
thread. The job dir holds `response_url` but no `channel_id` or `thread_ts`. `delivery.jsonl` has six records, all
`route: response_url`, `channel_id: null`, `thread_ts: null`; the first five `delivered: true`, the sixth (15:25:52Z)
`delivered: false, reason: delivery_rejected`. The webhook plist on the M5 has `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID`
set (key presence checked, values not read).

## Root cause

The relay builds `{ action: 'up', provider, response_url }` for `/cluster-up` and the same with `'down'` for
`/cluster-down`. Neither carries `channel_id` (read at line ~385) or the thread timestamp, unlike `/cluster-resume`
(line ~434), the agent commands and `/cleanup-stale-sandbox`. The webhook's `cluster` handler persists whatever
`channel_id`/`thread_ts` the body has (`_persist_notification_context`), and `_notify_job` uses the bot thread only
when the job has `channel_id`; without it the only route is `response_url`, which Slack caps at five uses.

## Fix

1. `workers/slack-relay/index.js`: add `channel_id: channelId` to the `/cluster-up` and `/cluster-down` payloads, and
   `thread_ts` when the command came from a thread, exactly as `/cluster-resume` does.
2. Deploy the worker with `make deploy-worker` (operator), then restart nothing else.

## Files

- `workers/slack-relay/index.js`
- `workers/slack-relay/test/` (existing relay tests)
- `CHANGELOG.md`

## What NOT to do

- Do not change the webhook's `_notify_job` routing or the five-use handling; the webhook already threads when given a channel.
- Do not change the role map or `ADMIN` requirement for these commands.
- Relay tests stub `fetch` and assert the forwarded body; no live Slack or webhook call.

## Acceptance

```yaml
must:
  M1: the relay forwards channel_id from the slash-command form for /cluster-up and /cluster-down to /api/v1/cluster
  M2: a /cluster-up job started from #acg-automation gets a channel_id file and posts its updates via route bot_thread / bot_fallback (a thread)
must_not:
  N1: /cluster-up and /cluster-down never forward a body without channel_id when the Slack form carried one
  N2: /cluster-resume's forwarded body does not change (paired control: it already carries channel_id)
  N3: the action, provider and response_url fields of the up/down bodies do not change
evidence:
  E1:
    proves: [M1, N1, N2, N3]
    kind: offline
    intent: >-
      You will see the relay tests post a /cluster-up and a /cluster-down form with channel_id=C123 and assert the body
      sent to /api/v1/cluster has channel_id C123 plus the unchanged action/provider/response_url (red on the pre-fix
      relay), and the /cluster-resume body unchanged.
    what: node --test workers/slack-relay/test/
  E2:
    proves: [M2]
    kind: live
    intent: >-
      You will see, after make deploy-worker, /cluster-up aws in #acg-automation post its progress in one thread, and the
      job's delivery.jsonl show route bot_thread with a channel_id and no delivery_rejected.
    what: operator in Slack; Claude reads delivery.jsonl on the M5
interface:
  - workers/slack-relay/index.js fetch handler (Slack slash-command form POST)
  - forwarded POST /api/v1/cluster body
  - ~/.local/share/k3d-manager/webhook-jobs/<id>/{channel_id,delivery.jsonl}
```
