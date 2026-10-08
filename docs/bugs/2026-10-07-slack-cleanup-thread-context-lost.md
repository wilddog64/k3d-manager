# Slack cleanup commands lost their originating thread context

**Status:** FIXED in branch; live verification pending
**Filed:** 2026-10-07
**Affected release:** v1.42.0
**Severity:** Medium — follow-up cleanup actions in a Slack thread were not reliably associated with the cleanup job

## Evidence

The slash command `/cleanup-stale-sandbox preview` queued and completed, but a follow-up
`cleanup-stale-sandbox apply` message in the same Slack thread did not reliably reach the
cleanup job. The relay accepted `thread_ts` but omitted it from the cleanup webhook payload.

## Fix

The relay now forwards `thread_ts`; the webhook persists it with the cleanup job, and thread
dispatch validates `preview`, `confirm`, and `apply` instead of silently treating unknown
arguments as a dry run.

The first live retry persisted `thread_ts` and completed successfully, but produced no visible
reply because bot posting failed silently. Job notifications now fall back to the stored Slack
response URL while preserving the same thread timestamp.

The next live retry showed bot posting could return success while targeting the webhook's
configured channel rather than the command's channel. Notifications now prefer the stored
response URL and use bot posting only as fallback.

The remaining consistency gap was top-level cleanup invocation: unlike status/diagnostics, it did
not create a bot thread when no incoming `thread_ts` existed. Cleanup now forwards the event
channel and creates a thread for top-level requests, matching those commands.

The first top-level-thread retry confirmed the thread was created, but the completion still used
the response URL and appeared at channel level. Newly created bot threads now use `chat.postMessage`
directly for completion; response URLs remain fallback for incoming slash-command threads.

An additional guard now posts a generic authorization failure to the originating thread for
recognized commands from an unallowlisted Slack user. The allowlist remains enforced and no
command is executed.

Live evidence showed user `U0B89H45SUA` was rejected with `reason=unallowlisted`; this explains
the silent follow-up messages and is a configuration follow-up, not permission to bypass the
role map.

## Validation

The Slack relay regression asserts thread/channel propagation, webhook cleanup tests pass 6/6,
and the existing cleanup tests cover preview/apply behavior. Live Slack verification remains
pending.
