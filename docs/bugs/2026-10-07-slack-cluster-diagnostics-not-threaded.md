# Slack cluster diagnostics do not consistently reply in threads

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** FIXED
**Severity:** Low — long diagnostic reports are harder to read when posted as top-level messages
**Component:** Slack status and diagnostics delivery

## Observed behavior

`cluster-status` and some other Slack commands could post a threaded response, but
`cluster-diagnose` posted directly to the slash-command `response_url`. When a command was
issued inside an existing thread, the diagnostic worker saved `thread_ts` but ignored it during
delivery. The result appeared as a new top-level message or was inconsistent with status output.

## Root cause

`_run_cluster_status` and `_run_hostinger_status` used `_post_status_report`, which understands
bot-channel threads. `_run_cluster_diagnostics` called `_slack_post(response_url, output)` directly
and did not receive `channel_id`, so it could not use the shared thread-aware path.

## Fix

- Extend the shared status delivery helper to post directly to an incoming Slack thread when the
  configured bot and channel match.
- Route `cluster-diagnose` through the same helper as `cluster-status`.
- Pass `channel_id` to the diagnostics worker.
- Retain response-URL fallback for channel mismatches, missing bot credentials, and bot API
  failures.

## Acceptance

- [x] A top-level `cluster-status` starts one parent message and posts details in its thread.
- [x] A top-level `cluster-diagnose` uses the same parent/thread layout.
- [x] A command received inside an existing thread replies to that `thread_ts` without creating a
      second header.
- [x] Channel mismatch and missing bot context continue to use `response_url`.
- [x] Focused status/diagnostics tests pass.
