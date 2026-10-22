# Cloud-request diagnostic reports omit job ID and Slack thread context

**Filed:** 2026-10-22
**Status:** OPEN — observed during live verification; no fix dispatched
**Priority:** P3
**Component:** `bin/k3dm-cloud-request`, diagnostics cloud-bridge route, Slack result delivery

## Summary

Diagnostics submitted through `bin/k3dm-cloud-request` can produce a Slack result message that omits the webhook job ID and does not reply in the originating Slack thread. The cloud-request action payload carries the diagnostic action and its allowlisted arguments, but no Slack `channel_id` or `thread_ts` context. The diagnostics webhook endpoint accepts optional `channel_id` and `thread_ts`; without those values it cannot target an originating Slack thread. The diagnostic report text also does not include the generated job ID, even though the HTTP 202 response returns it.

This is separate from the Hostinger diagnostic exit-status fix (`6be25c92`): that fix classifies command failures, while this issue concerns job identification and placement of cloud-request results. Direct Slack `cluster-diagnose` commands have a separate route that propagates the Slack thread context.

## Evidence

- On 2026-10-22, the operator submitted `diagnose-describe-pod` through `bin/k3dm-cloud-request` with `--wait-final`. The captured initial bridge response was HTTP 202 with job `a1573d1c` still queued; that capture alone does not establish whether final polling later timed out.
- The operator supplied a cloud-agent Slack screenshot showing the `NotFound` diagnostic output as a standalone result without a job ID, and reported that it did not reply in a thread.
- The tmux and cloud-agent evidence show two separate executions of the same safe diagnostic, not duplicate delivery from one job. Duplicate posting is not claimed as a defect.
- `scripts/lib/webhook/cloud_actions.py` defines the cloud-request diagnostic actions with only diagnostic resource arguments (`provider`, `namespace`, and `name` as applicable); no Slack thread-destination arguments are exposed.
- `bin/k3dm-webhook`'s `/api/v1/diagnostics` handler accepts optional `thread_ts` and `channel_id`, and `scripts/lib/webhook/status.py::_post_status_report` uses those values to select an existing thread or start a status thread. The cloud-request CLI route supplies no originating Slack context.
- `scripts/lib/webhook/status.py::_run_cluster_diagnostics` constructs and posts the diagnostic output without adding `job_id`; the bridge's initial HTTP 202 response carries the ID separately.

## Expected behavior

Diagnostic reports should include the job ID so operators can correlate the Slack result with the bridge response and query its status. When an operator intentionally requests a diagnostic from a Slack thread through the cloud-request workflow, the result should be associated with that same thread, or the workflow should clearly state that it will be posted separately. A caller must not be able to use arbitrary channel/thread values to post into unauthorized Slack conversations.

## Scope for follow-up

Investigate a safe context-propagation design, with tests for thread association, missing context, and rejection of unauthorized destinations. Do not change Hostinger diagnostics, Slack direct-command routing, or cloud-request final-polling behavior under this bug unless investigation establishes a direct dependency. No live Slack posting or code change is authorized by this finding.

## Reproduction

1. Submit an allowlisted diagnostic using `bin/k3dm-cloud-request`.
2. Observe its result delivered to Slack.
3. Observe that the Slack result omits the job ID returned by the bridge and is not a reply in the initiating Slack thread because the request payload contains no originating Slack thread identifier.
