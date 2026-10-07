# Slack cluster status fallback was posted outside the command thread

## Observed behavior

The live `/cluster-status` response was rendered as one top-level Slack message instead of a
thread reply. This happened when the incoming Slack channel differed from the configured bot
channel: status delivery treated that as unavailable for bot posting and fell back to the
response webhook/top-level notification.

## Fix

Status delivery now uses the incoming Slack channel for `chat.postMessage`, including existing
thread replies and newly-created status threads. The configured channel remains the fallback when
the event does not provide a channel. Empty-channel delivery still uses the response URL fallback.

## Verification

The focused thread tests cover the actual-channel path, existing-thread delivery, new-thread
delivery, and empty-channel fallback. A live Slack verification is required after webhook restart.
