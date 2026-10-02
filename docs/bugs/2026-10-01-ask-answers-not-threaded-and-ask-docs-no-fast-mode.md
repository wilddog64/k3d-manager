# `/ask` and `/ask-docs` answers are not threaded; `/ask-docs` has no fast mode

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. Answers land as loose top-level channel messages, so a follow-up has no thread to
go in. `/ask-docs` always waits several seconds on the summary model, even when the caller only
wants the matching documents.
**Status:** FIXED (Codex, 2026-10-01)

## Resolution

Added `_start_bot_thread` in `scripts/lib/webhook/render.py`. The fix is implemented in
`workers/slack-relay/index.js`, `bin/k3dm-webhook`, `scripts/lib/webhook/agent.py`,
`scripts/lib/webhook/render.py`, and `scripts/lib/webhook/ask_docs.py`, with coverage in the
ask-docs and relay tests. Documentation was updated in the Slack corpus guide, slash-command
how-to, and changelog.

## Observed (operator, 2026-10-01)

- `/ask-docs <question>` answered after a few seconds, and the answer was **not** in a thread.
- `/ask` behaves the same way. Both job bodies deliver through `_slack_post(response_url, text)`:
  `_run_ask_docs` in `bin/k3dm-webhook` and `_finish` in `_run_cluster_ask`
  (`scripts/lib/webhook/agent.py`).

## Cause

1. **Threading.** Slack slash-command payloads carry no `thread_ts`. The relay reads
   `p.get('thread_ts')`, which is always empty for slash commands. A `response_url` message cannot
   start a thread. The threaded path, `_post_slack_bot(text, thread_ts=...)`
   (`scripts/lib/webhook/render.py`), runs only when there is no `response_url`, which never
   happens for slash commands.
2. **Latency.** About 80–90% of `/ask-docs` time is the summary step: a fresh `agy` process running
   `gemini-3.8-flash-medium`. Retrieval (one embedding call plus a vector query) takes about 1 s.

## Fix

### A. Threaded delivery for `/ask` and `/ask-docs`

1. Relay (`workers/slack-relay/index.js`): read `channel_id` from the slash payload. In the `/ask`
   branch and the `/ask-docs` branch only, add `channel_id` to the relayed payload. Change no other
   command.
2. Webhook request handlers for `ask` and `ask_docs`: read `channel_id` from the body and pass it to
   the job function. Missing means `""`.
3. Add a delivery helper to `scripts/lib/webhook/render.py`, something like
   `_start_bot_thread(header) -> ts`. Use the bot path **only when all of these hold**:
   `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` are set, and `channel_id == SLACK_CHANNEL_ID`.
   - Otherwise keep today's behaviour exactly, with `_slack_post(response_url, text)`.
   - Never post to a channel other than `SLACK_CHANNEL_ID`: `_notify_job` follow-ups are bound to it.
4. When the bot path applies, at job **start**:
   - Post a top-level header with `_post_slack_bot`:
     - `/ask-docs`: `📚 *ask-docs:* <question>`
     - `/ask`: `🤖 *ask <agent>:* <question>`
   - The question in the header is scrubbed (`redact.scrub_credentials`, plus the ask_docs IPv4 and
     phone redaction for `/ask-docs`) and truncated to 200 chars with `…`.
   - On success, write the returned ts to the job's `thread_ts` file. Existing thread replies then
     route to this job through `_find_job_by_thread_ts`, so `ask …` follow-ups work in the thread.
5. At job **end**, post the answer with `_post_slack_bot(text, thread_ts=<header ts>)`.
6. Fallbacks:
   - Header post fails (returns `""`): deliver the answer with `_slack_post(response_url, text)`.
   - Threaded answer post fails: same.
   - An answer is never lost, and never posted twice.
7. Logging: the question text still never appears in any log line. The header goes to Slack, not
   to a log.
8. Do not change `_notify_job`, `_slack_post`, the `/cluster-*` commands, or `/slack/events` routing.

### B. `/ask-docs --sources <question>` fast mode

1. Webhook `ask_docs` handler, or `_run_ask_docs`: if the question starts with `--sources ` (also
   `-s `), strip the flag and call `ask_docs.answer(question, summarise=False)`.
2. In `scripts/lib/webhook/ask_docs.py`, `answer(..., summarise=True)`. When `summarise=False`:
   - Make **no model call**.
   - Reply `Top matching documents:`, then one line per kept doc: `<score:.2f>  <path> — <title>`.
   - Then the usual `Sources:` block.
   - Same floor, allowlist, redaction and 3000-char cap as the summarised path.
   - No-match and unavailable replies are unchanged.
3. Relay: if text is only `--sources` or `-s`, reply with the usage text, the same as empty text.
   Update the usage string to `Usage: /ask-docs [--sources] <question>`.

## Tests

Offline only (pytest plus the relay `node --test`). No real Slack, no real model.

- Bot path, `/ask-docs` and `/ask`: stub `_post_slack_bot`, returning a ts for the header and
  recording calls.
  - Expect a header call with no `thread_ts`.
  - Expect the answer call with `thread_ts` equal to the header ts.
  - `_slack_post` is called 0 times.
  - The job `thread_ts` file holds the header ts.
- Channel mismatch: `channel_id` differs from `SLACK_CHANNEL_ID`. `_post_slack_bot` is called 0
  times and `_slack_post(response_url, …)` once.
- No bot token: same as the mismatch case.
- Header post fails: `_slack_post` is called once with the answer, and there is no threaded call.
- Answer post fails: `_slack_post` is called once with the answer.
- Header redaction: a question containing `Bearer synthetic0token` and `10.1.2.3` does not show
  either value in the header. A 300-char question gets truncated.
- Question not logged: capture logging and stderr for a bot-path run. The question string is absent.
- `--sources`: the model stub is called 0 times, the reply has scores, paths and `Sources:`, and
  the floor and allowlist still apply.
- Relay:
  - `/ask` and `/ask-docs` forward `channel_id`.
  - `/cluster-status` payload is unchanged.
  - `/ask-docs --sources` with no question gets usage.
  - `/ask` still routes to `/api/v1/ask`.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) drop the `channel_id == SLACK_CHANNEL_ID` check → mismatch test red;
(b) post the answer without `thread_ts` → bot-path test red;
(c) remove the header-failure fallback → that test red;
(d) let `summarise=False` call the model → fast-mode test red;
(e) remove header redaction → redaction test red.

## Operator steps after the fix

- `make restart-webhook`.
- Redeploy the relay from the release branch: `make deploy-worker`, or
  `gh workflow run deploy-worker.yml --ref k3d-manager-v1.40.0`.
- The bot must be a member of the `SLACK_CHANNEL_ID` channel (see
  `docs/issues/2026-08-18-slack-cluster-status-thread-delivery.md`).
- Commands run in other channels keep the unthreaded behaviour.

Claude review addition: `_redact_thread_question` also escapes `&`, `<` and `>` (Slack control
sequences), so a question containing `<!channel>` or a user mention cannot ping from the bot
header. Covered by `test_header_escapes_slack_control_sequences` (mutation: drop the escape → red).
