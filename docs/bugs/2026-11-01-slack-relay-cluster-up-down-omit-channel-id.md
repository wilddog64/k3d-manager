# Bug: Slack relay drops `channel_id` for `/cluster-up` and `/cluster-down`, so job updates are never threaded and the 6th is lost

**Status:** OPEN — relay half `63be0e33` live-confirmed (job `87c78389` has `channel_id`); webhook half missing, see "Second cause"
**Fix commit:** 63be0e33
**Priority:** P2
**Severity:** medium — every `/cluster-up` / `/cluster-down` update goes to `response_url` instead of a bot thread; Slack accepts at most five posts per `response_url`, so a long job's later updates (the failure analysis or the final result) are rejected and never shown
**Approval:** operator, 2026-11-01 ("the cluster-up does not post result in a thread"); dispatch go: operator, 2026-11-01 ("go ahead to dispatch hub fixes")
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
`/cluster-down`. Neither carries `channel_id` (read at line ~385) or the thread timestamp, unlike `/cluster-status`
(line ~434), `/cluster-diagnose`, the agent commands and `/cleanup-stale-sandbox`. `/cluster-resume` (line ~491) has the
same gap, although the webhook's `cluster_resume` handler persists `channel_id`/`thread_ts` when given them. The webhook's `cluster` handler persists whatever
`channel_id`/`thread_ts` the body has (`_persist_notification_context`), and `_notify_job` uses the bot thread only
when the job has `channel_id`; without it the only route is `response_url`, which Slack caps at five uses.

## Fix

1. `workers/slack-relay/index.js`: add `channel_id: channelId` to the `/cluster-up`, `/cluster-down` and `/cluster-resume`
   payloads, and `thread_ts` when the command came from a thread, exactly as `/cluster-status` does.
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
  N2: /cluster-status's forwarded body does not change (paired control: it already carries channel_id)
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

## Verification (2026-11-01, Claude)

- Review: Luna's diff added `channel_id` and optional `thread_ts` to the up/down payloads. The spec wrongly named
  `/cluster-resume` as the precedent (line 434 is `/cluster-status`), so Luna's control test pinned resume's broken body.
  Claude corrected the spec, applied the same two lines to `/cluster-resume`, and replaced the control with a
  `/cluster-status` body test.
- Pre-fix red: on a scratch copy with `HEAD:index.js` the suite gives 48 pass / 2 fail —
  `cluster up and down forward channel and optional thread context`, `cluster resume forwards channel and optional thread context`;
  the `/cluster-status` control passes on both.
- Post-fix: `node --test workers/slack-relay/test/` 50/50. Land fast gate PASS (`slack_slash_commands.bats`, doc-links).
- Land: first refused, `out-of-scope: workers/slack-relay/test/relay.test.mjs` (Files names the directory
  `workers/slack-relay/test/`; the scope check does not match a directory entry); landed with `--allow-out-of-scope`.
- Errors seen: the refused land above (explained). None other.
- Pending: E2 — operator `make deploy-worker`, then `/cluster-up aws` in #acg-automation; Claude reads the job's
  `delivery.jsonl` (expect `route: bot_thread`, a channel_id, no `delivery_rejected`).

## Second cause (2026-11-01, live E2 on job `87c78389`)

E2 failed after `make deploy-worker` (Version `64998a50`). The relay half works: the job dir has `channel_id`
`C0B7ZHG2LR4`. All five posts still went `route: response_url`, `thread_ts: null`.

`_notify_job` in `bin/k3dm-webhook` (~line 1283) takes `bot_thread` only when the job has **both** `channel_id` and
`thread_ts`. A slash command typed in the channel (not in a thread) has no `thread_ts`, so the first post goes to
`response_url`, which returns no `ts`. No thread is ever started, and the 6th post is rejected. The original root
cause ("`_notify_job` uses `bot_thread` when the job has a `channel_id`") was wrong.

### Fix (webhook half)

In `_notify_job`: when `SLACK_BOT_TOKEN` is set, the job has `channel_id`, and there is no `thread_ts`, post the
message with the bot to `channel_id` first, write the returned `ts` to the job's `thread_ts`, and record
`route: bot_thread`. Later posts then reply in that thread. If the bot post fails, keep the current `response_url`
path. A job without `channel_id` behaves exactly as today.

Also make the webhook's Slack API rejections visible: on the M5 (job `e7a0ecfb`) the 6th post went
`route: bot_fallback`, `delivery_rejected`, but `~/Library/Logs/k3dm-webhook.log` has 0 `chat.postMessage` lines.
The `render.py` logger (`get_logger(__name__)`) does not reach the webhook's log handler. Route it to the same
handler, so `slack chat.postMessage rejected channel=... error=...` appears in the log (never the token).

### Files (webhook half)

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_notify*.py` (or the existing `_notify_job` test file)
- `scripts/lib/webhook/render.py`, `scripts/lib/webhook/` logging setup (only if needed to reach the handler)
- `CHANGELOG.md`

### Acceptance (webhook half)

```yaml
must:
  M3: a job with channel_id, no thread_ts and a bot token posts its first message with the bot to channel_id, writes thread_ts, and records route bot_thread
  M4: the next post for that job replies in that thread (thread_ts set) with route bot_thread
must_not:
  N2: a job without channel_id never posts with the bot to SLACK_CHANNEL_ID; it keeps the response_url route (paired control for M3)
  N3: when the first bot post fails, the message is still delivered via response_url
  N4: a chat.postMessage rejection is never silent — the webhook log gets a line with the Slack error code and channel, and no token
evidence:
  E3:
    proves: [M3, M4, N2, N3, N4]
    kind: offline
    intent: You will see pytest with a stubbed _post_slack_bot/_slack_post and a scratch JOB_DIR route the first post to the bot and the second into its thread, a channel-less job stay on response_url, and a failed bot post fall back (M3/M4 red on the pre-fix webhook).
    what: pytest on the notify tests
  E4:
    proves: [M3, M4]
    kind: live
    intent: You will see /cluster-up aws in #acg-automation post all updates in one thread, and delivery.jsonl show route bot_thread.
    what: operator Slack + Claude reads delivery.jsonl on the M5
interface:
  - bin/k3dm-webhook _notify_job(job_id, text)
  - job dir files channel_id, thread_ts, response_url, delivery.jsonl
  - env SLACK_BOT_TOKEN, SLACK_CHANNEL_ID
```

## Live evidence (2026-11-01, job `cdff3cea`)

`delivery.jsonl` on the M5: updates 1-5 `response_url` delivered; update 6 `bot_fallback` delivered with reason
`delivery_rejected` (the 6th `response_url` post was refused at Slack's 5-post cap) and recorded thread_ts
`1793551009.895759`; updates 7-8 `bot_thread` in that thread. The operator saw "two out of thread, the third one
replied in a thread" (screenshot 521). This is the pre-fix behavior the webhook half fixes: the thread should start
at update 1, not at update 6. Not a regression.
