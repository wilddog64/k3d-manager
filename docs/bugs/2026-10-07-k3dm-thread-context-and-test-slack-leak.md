# k3dm threaded jobs lose context and test-all leaks fixture notifications

**Filed:** 2026-10-07
**Severity:** High — threaded job output is misplaced and offline tests create misleading Slack activity
**Status:** FIXED in the local branch; live verification pending

## Evidence

During a Slack-triggered `k3dm test-all`, the acknowledgement/progress did not appear in the
originating thread. The same run posted apparent live lifecycle messages for `cluster-up (aws)`
and `cluster-down (aws)` while the test suite was reporting its cases.

## Root cause

The `/k3dm` relay payload omitted Slack `thread_ts` and `channel_id`, and the webhook Make route
did not persist those fields. A threaded slash invocation therefore had no job-to-thread link.
The webhook BATS fixture also inherited live Slack bot/webhook environment variables from the
parent `make test-all` process, allowing stubbed cluster test jobs to post notifications.

The live follow-up also exposed a second edge: a bare threaded event could have a thread
timestamp but no persisted channel metadata. The notifier then fell back to the configured
channel, so the final failure appeared outside the originating thread.

A top-level `/k3dm` slash command also had no incoming `thread_ts`, so it could run in the
channel without creating a parent thread.

## Fix

The relay forwards and the webhook persists `thread_ts` and `channel_id` for Make jobs. The BATS
fixture now unsets Slack delivery variables so local test jobs cannot post to the real channel.
Regression coverage verifies threaded `/k3dm` metadata and the existing lifecycle stubs remain
isolated. Thread dispatch now persists the incoming channel on the anchor before launching the
child job.
The Make route now creates a bot parent thread for top-level jobs when the originating channel
and bot token are available.
