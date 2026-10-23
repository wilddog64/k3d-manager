# Bug: thread commands under a slash-command message reply in the channel, not the thread

**Filed:** 2026-10-22 (Claude, from the operator's Slack screenshots ~18:14 PDT)
**Status:** OPEN
**Priority:** P2 — answers land as top-level channel posts, detached from the question; workaround: ask with a new top-level `/ask-docs`
**Severity:** medium
**Approval:** pending
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-webhook` (`_notify_job`, `_handle_thread_command` ask-docs branch)
**Related:** `docs/bugs/2026-10-01-ask-docs-thread-follow-up-silently-dropped.md` (its 2026-10-22 recurrence fix `18a9e7ef` added the `response_url` copy), `docs/bugs/2026-10-18-slack-thread-broadcast-reply-silently-ignored.md`

## Symptom

Under the 18:11 `/ask-docs what is the bug tally?` message, the operator replied in the thread with
`ask-docs please provide a bug count` and `ask-docs what is the latest bugs`. Both answers, and the
"📚 Searching docs…" acknowledgement, were posted as new top-level channel messages. A third follow-up at 18:17 did land in the thread (see Evidence).

## Evidence

Job directories under `~/.local/share/k3d-manager/webhook-jobs/`:

| Job | Kind | Files | Delivery route |
|---|---|---|---|
| `9fef9c7e`, `73f924c2` | ask-docs thread follow-ups | thread_ts, channel_id, response_url; no thread_source | `response_url` |
| `843fe24a` | parent of the thread | thread_ts, channel_id, response_url | `response_url` (the acks) |
| `c7648a53` | third follow-up, 18:17 ("what's everything else") — same files as above | `bot_fallback` — landed in the thread. The parent's `response_url` had already been used 5 times (3 acks + 2 answers); Slack allows 5 posts per response_url within 30 minutes, so this post was refused and fell back to the bot. |
| `b5433d86` | ask-docs follow-up in the diagnostics thread (live-verified earlier) | thread_ts, channel_id; no response_url | `bot_fallback` — landed in the thread |

## Root cause

`_notify_job` tries routes in this order:
1. `bot_thread`, only when `thread_source == "bot"` and channel_id and thread_ts are set;
2. `response_url` whenever the job has one;
3. `bot_fallback` (bot post with thread_ts, to channel_id).

A slash-command job has a `response_url` and no `thread_source`, so route 2 wins. A post to a
slash command's `response_url` lands as a channel message, not in the thread. This affects every
`_notify_job(parent_job_id, …)` call from `_handle_thread_command` on a thread under a slash-command message. The ask-docs recurrence fix
(`18a9e7ef`) also copies `response_url` into the follow-up sub-job, so the answer takes the same route.
The diagnostics thread worked only because that parent job had no `response_url`.

## Fix

- **F1.** In `_notify_job`, when `SLACK_BOT_TOKEN`, `channel_id` and `thread_ts` are all set, try the
  bot thread post first, regardless of `thread_source`. If that post fails, fall through to the
  existing `response_url` and fallback routes unchanged. Keep the guard that refuses the default
  channel when `thread_ts` is set and `channel_id` is unknown.
- **F2.** In the `ask-docs` branch of `_handle_thread_command`, copy `channel_id` and
  `thread_source` only; stop copying `response_url` into the sub-job.
- **F3.** Tests in `scripts/tests/bin/test_webhook_ask_docs_thread.py` and a new or existing
  `_notify_job` routing test: a job with channel_id + thread_ts + response_url and no thread_source
  posts via the bot into the thread, and `response_url` is not called; when the bot post fails, it
  falls back to `response_url`; a job with thread_ts and no channel_id still never posts to the
  default channel; the ask-docs sub-job has no `response_url` file.
- **F4.** `CHANGELOG.md` entry.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_ask_docs_thread.py`
- `scripts/tests/bin/test_webhook_ask_delivery.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A job with channel_id and thread_ts posts its notification as a bot reply in that thread (thread_ts and channel_id passed to the bot post), whether or not it has thread_source or response_url.
  - id: M2
    text: If that bot post fails, delivery falls back to response_url as before.
  - id: M3
    text: An ask-docs thread follow-up sub-job carries channel_id and thread_ts and no response_url.
must_not:
  - id: N1
    text: A job with channel_id, thread_ts and response_url must not deliver through response_url while the bot thread post succeeds (red on the pre-fix code).
  - id: N2
    text: A job with thread_ts but no channel_id and no response_url must not post to the configured default channel.
  - id: N3
    text: The ask-docs follow-up sub-job must not contain a response_url file (red on the pre-fix code).
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest scripts/tests/bin -k webhook; N1 and N3 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M3]
    text: After make restart-webhook, the operator runs /ask-docs <question>, then replies `ask-docs <question>` in that thread; the "Searching docs…" ack and the answer both appear in the thread, and the delivery route recorded for the sub-job is bot_thread.
interface:
  - bin/k3dm-webhook _notify_job(job_id, text) reading JOB_DIR/<job_id>/{thread_ts,channel_id,thread_source,response_url}
  - bin/k3dm-webhook _post_slack_bot(text, thread_ts=, channel_id=), _slack_post(url, text, thread_ts=)
  - bin/k3dm-webhook _handle_thread_command(job_id, "ask-docs <question>", role=)
  - JOB_DIR/<job_id>/delivery.jsonl route field
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N3 shown red against the pre-fix code.
- [ ] Commit: `fix(webhook): reply in the Slack thread before falling back to response_url`

## What NOT to Do

- Do NOT remove or weaken the default-channel guard for jobs with thread_ts and no channel_id.
- Do NOT change top-level slash-command replies (jobs with no thread_ts).
- Do NOT edit this bug doc, create a PR, commit to `main`, or use `--no-verify`.
