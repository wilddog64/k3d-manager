# Bug: an unrouted cloud-request make job posts only its first Slack notice; every later notice is dropped

**Status:** OPEN — filed, under review (Fable + Neon) before dispatch
**Priority:** P2
**Introduced by:** v1.43.5 `401e4eca` (fallback guard `not thread_ts and not response_url and SLACK_CHANNEL_ID`)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-27 (spec review), then dispatch to Luna
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (fell back to glob). Read
`2026-11-01-slack-relay-cluster-up-down-omit-channel-id.md` — related shape (job without `channel_id` loses later
notices), different entry point (Slack relay); `2026-10-23-api-cluster-status-posts-to-command-channel.md` — routing of
API-origin reports, different defect.
**Severity:** medium — the cloud session still gets the result through the bridge, but Slack shows "started" and never
the outcome for every cloud-request make job, so the operator cannot follow cloud work in Slack
**Filed:** 2026-11-27, Claude, from the v1.46.0 p2b live control (operator: "go ahead to file those two P2 bugs")
**Approval:** operator, 2026-11-27 ("go ahead to file those two P2 bugs and have Fable and Neon to review them. after that dispatch to Flash and Luna")
**Intent approved:** operator, 2026-11-27
**Component:** `bin/k3dm-webhook` `_notify_job` (~1296-1395)

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

## Fix

When `bot_fallback` starts a new thread in `SLACK_CHANNEL_ID` (no `channel_id`, no `thread_ts`), persist
`SLACK_CHANNEL_ID` to the job's `channel_id` file together with `thread_ts`, so later notices take the `bot_thread`
path into the same thread. Do not change any other branch; do not persist anything when the post fails.

`scripts/tests/bin/test_webhook_notify_route.py::test_BM2_unrouted_make_and_cluster_match_golden_baseline` (`:237`)
pins unrouted job files to the pre-p2b baseline; this fix intentionally adds a `channel_id` file after the first post,
so update that golden case deliberately (and say so in the test), not by loosening it.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_notify_route.py`
- `scripts/tests/bin/test_webhook_unrouted_thread.py` (new)

## Contract readers

- Job-directory file `channel_id`: written today by `_persist_notification_context` (Slack routes, p2b routing); read
  by `_notify_job`, `_copy_thread_context`, thread handlers. New writer: `_notify_job` `bot_fallback` (value always
  `SLACK_CHANNEL_ID`). Readers unchanged.

## Acceptance

```yaml
must:
  - id: U-M1
    text: "an unrouted job with no Slack context posts its first notice to SLACK_CHANNEL_ID and every later notice as a reply in that thread, each recorded delivered true"
  - id: U-M2
    text: "routed jobs and Slack-originated jobs (channel_id, thread_ts or response_url present) behave exactly as before"
must_not:
  - id: U-N1
    text: "a later notice of an unrouted cloud job is dropped (route none, delivered false) after a successful first post"
    red_on_current: "red: on the current code the second _notify_job call for a job with no Slack context records route none, delivered false"
  - id: U-N2
    text: "a job whose thread_ts came from Slack but whose channel_id is unknown gets a reply posted into SLACK_CHANNEL_ID"
    red_on_current: "green on current (the guard holds); stays green — positive control that the fix does not widen the fallback"
  - id: U-N3
    text: "a failed first post writes a channel_id file"
    red_on_current: "green on current; mutant that writes channel_id before the post result is known turns it red"
evidence:
  - id: U-E1
    proves: [U-M1, U-M2, U-N1, U-N2, U-N3]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_webhook_unrouted_thread.py scripts/tests/bin/test_webhook_notify_route.py -q passes; on the current code plus only the new tests, the U-N1 test fails and U-N2 passes"
    intent: "Cloud jobs you did not route show their whole story — started, progress and result — in one thread in the usual channel."
  - id: U-E2
    proves: [U-M1]
    kind: live
    command: "after a hub promote: bin/k3dm-cloud-request make-find-similar-docs --arg Q=... --wait-final; the job's delivery.jsonl shows every record delivered true, the second as bot_thread in the first record's thread; the operator sees the result reply in #acg-automation"
    intent: "In Slack you see the result of a cloud job under its started message."
interface:
  - "job-directory file channel_id now also written by _notify_job bot_fallback"
```
