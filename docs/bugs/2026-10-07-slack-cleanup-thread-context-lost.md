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

## Validation

The Slack relay regression asserts thread propagation and the existing cleanup tests cover the
preview/apply behavior. Live Slack verification remains pending.
