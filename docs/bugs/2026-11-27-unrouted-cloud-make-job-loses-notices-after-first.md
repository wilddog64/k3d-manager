# Bug: a job with no Slack context posts only its first Slack notice; every later notice is dropped

**Status:** LIVE-VERIFIED — `35d42bc8` (Luna; Claude-verified offline); U-E2 PASS on the hub 2026-11-27 (job `497709c4`)
**Priority:** P2
**Live evidence:** 2026-11-27 · run 497709c4 · env hub-m5 · scenario unrouted-cloud-make-job · commit 1c74deb3 · proves fix
**Fix commit:** 35d42bc8
**Introduced by:** v1.43.5 `401e4eca` (fallback guard `not thread_ts and not response_url and SLACK_CHANNEL_ID`)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (fell back to glob). Read
`2026-11-01-slack-relay-cluster-up-down-omit-channel-id.md` — related shape (job without `channel_id` loses later
notices), different entry point (Slack relay); `2026-10-23-api-cluster-status-posts-to-command-channel.md` — routing of
API-origin reports, different defect.
**Severity:** medium — the cloud session still gets the result through the bridge, but Slack shows "started" and never
the outcome for every cloud-request make job, so the operator cannot follow cloud work in Slack
**Filed:** 2026-11-27, Claude, from the v1.46.0 p2b live control (operator: "go ahead to file those two P2 bugs")
**Approval:** operator, 2026-11-27 ("go ahead to file those two P2 bugs and have Fable and Neon to review them. after that dispatch to Flash and Luna")
**Intent approved:** operator, 2026-11-27
**Component:** `bin/k3dm-webhook` `_notify_job` (~1318-1391)

## Evidence (live, 2026-11-27, hub m5 on `deploy/hub` `54a13982`)

Unrouted control `bin/k3dm-cloud-request make-find-similar-docs --arg "Q=unrouted control probe" --wait-final` from
m4 → job `ecadcf06`. Its `delivery.jsonl` (operator `cat` on m5):

```
{"at": "2026-11-27T01:42:54.945019+00:00", "channel_id": null, "delivered": true,  "job_id": "ecadcf06", "notify_route": null, "route": "bot_fallback", "thread_ts": null}
{"at": "2026-11-27T01:42:55.999734+00:00", "channel_id": null, "delivered": false, "job_id": "ecadcf06", "notify_route": null, "route": "none", "thread_ts": "1795743774.934689"}
```

The routed probe `4416b771` (same action, `--notify-route testing`) delivered both notices as `bot_thread` replies in
one thread, because routing persists `channel_id` in the job directory.

## Cause

A cloud-request make job has no `channel_id`, `thread_ts` or `response_url` file. In `_notify_job`:

1. First notice: `bot_thread` is skipped (no `channel_id`); `bot_fallback` applies (`not thread_ts and not response_url
   and SLACK_CHANNEL_ID`) and posts to `SLACK_CHANNEL_ID`; the returned `ts` is written to `thread_ts`. The channel is
   **not** written.
2. Every later notice: `thread_ts` now exists and `channel_id` does not, so `bot_fallback`'s guard is false
   (deliberately: a thread reply to an unknown channel is unsafe), `webhook_fallback` is skipped (`thread_ts` set), and
   the notice is recorded `route: none`, `delivered: false`.

The guard is right for Slack-originated jobs whose channel is unknown; it is wrong for a thread the webhook itself just
started in `SLACK_CHANNEL_ID`.

**Scope (reviews):** `_notify_job` is shared, so every job with no Slack context is affected, not only cloud make
jobs: unrouted `/api/v1/cluster` up/down (`lifecycle._run_cluster`), `/api/v1/cluster-resume`, stale-sandbox cleanup
(`_run_stale_sandbox_cleanup`), the `_clear_stale_jobs` orphan notice, and the test-metrics notice. All of them improve.

## Fix

In `_notify_job`'s `bot_fallback` branch, when the post succeeded and started a new thread in `SLACK_CHANNEL_ID` —
exactly `ts and not thread_ts and not channel_id` — write `thread_ts` (as today) **first**, then write `SLACK_CHANNEL_ID`
to the job's `channel_id` file. Later notices then take the `bot_thread` path into the same thread.

- Never write `channel_id` when the job already had one (a routed or Slack job whose `bot_thread` post failed and whose
  `bot_fallback` retry succeeded must keep its own channel), when the post failed, or on the exception path.
- Write order `thread_ts` then `channel_id`: a concurrent notifier that reads between the two writes drops one notice
  (today's behaviour); the reverse order could start a second parent thread.
- Do not change the shape of the first delivery record (it stays `channel_id: null`, `thread_ts: null`; asserted by
  `test_webhook_notify_route.py:256,276`). Do not change any other branch.
- `test_BM2_unrouted_make_and_cluster_match_golden_baseline` (`test_webhook_notify_route.py:237`) must pass
  **unmodified**: it pins job files before the first notice and the first record's shape, and proves U-M2.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_notify_route.py`
- `scripts/tests/bin/test_webhook_unrouted_thread.py` (new)

(Read-only regression suites to run: `test_webhook_ask_delivery.py`, `test_webhook_stale_cleanup.py`,
`test_webhook_thread_dispatch.py`.)

## Contract readers

Job-directory file `channel_id` (grep, `bin/k3dm-webhook`, 2026-11-27):

- **Writers today:** `_copy_thread_context` `:747-753`, `_persist_notification_context` `:777-780`, thread/slash
  handlers `:833`, `:868`, `:921`, `:946`, `:1216`, `:2508`, `:2526`, `:2846`, `:2893`. **New writer:** `_notify_job`
  `bot_fallback` (value always `SLACK_CHANNEL_ID`, only for a thread it just started).
- **Readers:** `_notify_job` `:1326`; `_find_job_by_thread_ts` `:680-681` and `_resolve_thread_job_target` `:716-717`
  (become stricter: a same-ts event from another channel no longer matches — correct); `_copy_thread_context` `:748`
  (children inherit the channel — correct); `:1213`, `:1241`. `status.py` and `agent.py` take the channel as a
  parameter, not from the file; the bridge does not read it.

## Acceptance

```yaml
must:
  - id: U-M1
    text: "a job with no Slack context (make and cluster up) posts its first notice to SLACK_CHANNEL_ID and every later notice as a reply in that thread (http payload channel = SLACK_CHANNEL_ID, thread_ts = the job's thread_ts file), each recorded delivered true"
  - id: U-M2
    text: "routed jobs and Slack-originated jobs (channel_id, thread_ts or response_url present) behave exactly as before; test_BM2 passes unmodified"
must_not:
  - id: U-N1
    text: "a later notice of a job with no Slack context is dropped (route none, delivered false) after a successful first post"
    red_on_current: "red: test_U_N1_second_notice_delivered — the second _notify_job call records route none, delivered false on the current code"
  - id: U-N2
    text: "a job whose thread_ts came from Slack but whose channel_id is unknown gets a reply posted into SLACK_CHANNEL_ID"
    red_on_current: "green on current and after the fix — positive control that the fallback is not widened (test_U_N2_slack_thread_unknown_channel_not_posted)"
  - id: U-N3
    text: "a failed first post, the exception path, or a webhook_fallback delivery writes a channel_id file"
    red_on_current: "green on current; a mutant that writes channel_id before the post result is known turns test_U_N3_failed_first_post_writes_no_channel_id red (cases: SLACK_WEBHOOK_URL empty and set)"
  - id: U-N4
    text: "a job with its own channel_id whose bot_thread post fails and bot_fallback retry succeeds has that channel_id overwritten with SLACK_CHANNEL_ID"
    red_on_current: "green on current; a mutant that drops the 'not channel_id' guard turns test_U_N4_existing_channel_not_overwritten red"
evidence:
  - id: U-E1
    proves: [U-M1, U-M2, U-N1, U-N2, U-N3, U-N4]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_webhook_unrouted_thread.py scripts/tests/bin/test_webhook_notify_route.py scripts/tests/bin/test_webhook_ask_delivery.py scripts/tests/bin/test_webhook_stale_cleanup.py scripts/tests/bin/test_webhook_thread_dispatch.py -q passes; on the current code plus only the new tests, test_U_N1 fails and test_U_N2/U_N3/U_N4 pass; mutants (drop the channel_id write; write it before the post result; drop 'not channel_id') each turn their test red"
    intent: "Cloud jobs you did not route show their whole story — started, progress and result — in one thread in the usual channel."
  - id: U-E2
    proves: [U-M1]
    kind: live
    command: "after a hub promote: bin/k3dm-cloud-request make-find-similar-docs --arg Q=... --wait-final; the job's delivery.jsonl second record is route bot_thread, delivered true, thread_ts equal to the job's thread_ts file, channel_id equal to the default channel; the operator sees the result reply under the started message in #acg-automation"
    intent: "In Slack you see the result of a cloud job under its started message."
interface:
  - "job-directory file channel_id now also written by _notify_job bot_fallback for a thread it started"
```

## Live evidence

- **U-E2 PASS — 2026-11-27 03:52Z, hub m5 on `deploy/hub` `1c74deb3`, after `make restart-webhook`** (operator): Claude
  `bin/k3dm-cloud-request make-find-similar-docs --arg "Q=unrouted thread live check after restart" --wait-final` →
  job `497709c4`, exit 0. `delivery.jsonl` (operator `cat` on m5): record 1 `bot_fallback`, delivered true,
  `channel_id` null; record 2 `bot_thread`, delivered true, `channel_id` `C0B7ZHG2LR4` (default channel),
  `thread_ts` `1795751540.503239`. Slack (operator screenshot, 19:52 PST): "succeeded — job 497709c4" as the one reply
  under the started message in #acg-automation; the pre-fix control `ecadcf06` (17:42) has no reply.
- First attempt `d812d065` (03:12Z) failed with the pre-fix shape because `make hub-deploy` had not restarted the
  webhook — see the recurrence in
  [`2026-11-22-hub-deploy-leaves-webhook-on-stale-code.md`](2026-11-22-hub-deploy-leaves-webhook-on-stale-code.md).
