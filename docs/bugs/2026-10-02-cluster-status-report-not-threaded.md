# `/cluster-status` posts its whole report as one top-level message instead of threading it

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. Each `/cluster-status` drops a report of about 21 lines into the channel, so two runs
bury everything else. A follow-up has no thread to go in.
**Status:** FIXED (deployed 2026-10-02; threading confirmed in Slack)
**Related:** `docs/bugs/2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`. `/ask` and
`/ask-docs` got threaded delivery there. This doc applies the same pattern to `/cluster-status`.

## Cause

Same cause as the related doc. A slash payload has no `thread_ts`, and a `response_url` message cannot
start a thread. `_run_hostinger_status` and `_run_cluster_status` (`scripts/lib/webhook/status.py`)
deliver through `_slack_post(response_url, output)`. The relay sends no `channel_id` for
`/cluster-status`, and `workers/slack-relay/test/relay.test.mjs` asserts that it doesn't.

## Fix

Goal: the channel shows **one line**, the verdict (for example `✅ *Cluster status: HEALTHY* — k3s-hostinger (21 ok / 0 warn / 0 fail)`),
and the per-check report goes **in that line's thread**.

1. **Relay** (`workers/slack-relay/index.js`): in the `/cluster-status` branch only, add `channel_id: channelId`
   to the payload.
   - Update the relay test: `/cluster-status` now relays `channel_id`.
   - Every other non-ask command still does not.
2. **Webhook handler** (`bin/k3dm-webhook`, `route["handler"] == "cluster_status"`): read
   `channel_id = body.get("channel_id", "")` and pass it to the job as the kwarg `channel_id`.
   - Do not change the thread-typed `cluster-status` path, the `elif cmd == "cluster-status"` branch around line 669. It already has a
     `thread_ts` and posts with `_notify_job`.
3. **Jobs** (`_run_hostinger_status` and `_run_cluster_status` in `scripts/lib/webhook/status.py`): add
   `channel_id=""`.
   - The bot path applies only when **all** of these hold:
     - `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` are set;
     - `channel_id == SLACK_CHANNEL_ID`;
     - the job was started **without** an incoming `thread_ts`.
   - Read the token and channel at call time, not as values bound at import. The tests must be able to monkeypatch them the way
     `scripts/tests/bin/test_webhook_ask_docs_thread.py` does. A small helper in `render.py` is fine.
   - In `_finish`, when the bot path applies:
     1. Split the already-redacted, already-truncated `output` into `header` (the first non-empty line)
        and `body` (the rest, with leading blank lines stripped).
     2. `ts = _start_bot_thread(header)`. If that succeeds, write `ts` to `job_dir/thread_ts`, so later
        thread replies route to this job through `_find_job_by_thread_ts`.
     3. Then `_post_slack_bot(body, thread_ts=ts)`, only if `body` is non-empty.
   - Fallbacks. The report is never lost and never posted twice:
     - the header post fails → `_slack_post(response_url, output)`, the whole report, exactly as today;
     - the body post fails → `_slack_post(response_url, body)`.
   - When the bot path does not apply, behaviour is byte-for-byte unchanged.
   - Do **not** change `_run_cluster_diagnostics`.
4. Do not change `_notify_job`, `_slack_post`, `_post_slack_bot`, the redaction, or the 3400-char truncation.
5. Docs: add one line to the `/cluster-status` entry in `docs/howto/slack-slash-commands.md`: "In the bot channel, the verdict posts top-level and the details go in its thread."

## Tests (stubbed; no Slack, no cluster)

Python, a new `scripts/tests/bin/test_webhook_cluster_status_thread.py`, modelled on
`test_webhook_ask_docs_thread.py`. Stub `_smoke_test_services` and the spawns, so the report is deterministic.
Record `_post_slack_bot`, `_start_bot_thread` and `_slack_post` calls.

1. Bot path, both `_run_hostinger_status` and `_run_cluster_status`:
   - the header is the verdict line only;
   - the body goes to `thread_ts=<header ts>`;
   - `thread_ts` is written;
   - `_slack_post` is not called.
2. `channel_id` differs, or is empty → only `_slack_post(response_url, output)`, with the same text as before.
3. An incoming `thread_ts` → no new header; existing behaviour.
4. Header post returns `""` → one `_slack_post` with the full report.
5. Body post fails → one `_slack_post` with the body.
6. The webhook `cluster_status` route passes `channel_id` through to the job.

Relay: `node --test workers/slack-relay/test/` is green, with the updated assertion.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) drop the `channel_id == SLACK_CHANNEL_ID` check → test 2 is red;
(b) post the full `output`, not `body`, into the thread → test 1 is red.

## Rules

- `pytest scripts/tests/bin/test_webhook_cluster_status_thread.py scripts/tests/bin/test_webhook_ask_docs_thread.py`
  and `pytest scripts/tests/bin/` are green.
- `node --test workers/slack-relay/test/` is green.
- No Slack, network or cluster calls. No git commits. Leave the changes uncommitted.
- Do not touch `CHANGELOG.md`; Claude adds the bullet.
- Update this doc: Status FIXED (pending deploy), plus a short Resolution section.

## Rollout (operator)

`make deploy-worker` for the relay, then `make restart-webhook`. Then run `/cluster-status` in the bot channel.

## Resolution

The relay now forwards the slash command's `channel_id`. The webhook passes it to both status jobs;
when the request is a top-level command in the configured bot channel, the verdict is posted as a
top-level message and the redacted details are posted in its thread. Failed header/body posts fall
back to the response URL without duplicating the report. Tests cover the bot-channel, fallback,
incoming-thread, route-forwarding, and relay behavior; Slack, cluster, and network calls remain stubbed.
