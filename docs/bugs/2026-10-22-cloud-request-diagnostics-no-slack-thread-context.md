# Cloud-request diagnostic reports omit the job ID

**Filed:** 2026-10-22
**Status:** FIXED offline — `ec81caa3` (Luna; Claude review: N1 red on pre-fix (3 failed), 15 pytest green); live E2 pending `make restart-webhook`
**Priority:** P3
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "go ahead" to dispatching to Luna
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/lib/webhook/status.py` (`_run_cluster_diagnostics`)
**Related:** `docs/plans/v1.44.0-cloud-request-slack-notification-routing.md` (owns the Slack
destination half split out of this bug; see "Split" below)

## Summary

Diagnostics submitted through `bin/k3dm-cloud-request` produce a Slack result that omits the webhook
job ID. The bridge's HTTP 202 response returns the ID, but nothing in the Slack message lets an
operator match it to that response or query its status.

This is separate from the Hostinger diagnostic exit-status fix (`6be25c92`), which classifies
command failures.

## Evidence

- On 2026-10-22 the operator submitted `diagnose-describe-pod` through `bin/k3dm-cloud-request`
  with `--wait-final`. The bridge returned HTTP 202 with job `a1573d1c`.
- The operator's screenshot of the Slack result shows the `NotFound` diagnostic output with no job ID.
- `scripts/lib/webhook/status.py::_run_cluster_diagnostics(job_id, ...)` receives `job_id`, but the
  report text it builds (the `title` line per action, then provider, output and status) never
  includes it. The same report is posted for direct Slack `cluster-diagnose` commands, so those
  lack the ID too.
- The tmux and cloud-agent evidence show two separate executions of the same safe diagnostic, not
  duplicate delivery from one job. Duplicate posting is not claimed as a defect.

## Split (2026-10-22)

The original filing also reported that the result does not reply in the originating Slack thread.
That half is not a code defect: a cloud session submits from the `cloud-requests` branch and has no
Slack thread of its own, and letting a request carry `channel_id`/`thread_ts` would let any branch
writer post into arbitrary conversations. Choosing the destination is a trust decision. It belongs to
`docs/plans/v1.44.0-cloud-request-slack-notification-routing.md` (approved-channel routing for
cloud requests), not to this bug. This bug changes no Slack destination.

## Fix

- **F1.** In `_run_cluster_diagnostics`, include the job ID in the report: one line
  `_Job: \`<job_id>\`_` written immediately after the action's `title` line, for every action.
- **F2.** Tests in a new `scripts/tests/bin/test_diagnostics_job_id.py`: run
  `_run_cluster_diagnostics` with the command spawn and Slack posting stubbed (as
  `scripts/tests/bin/test_diagnostics_all_pods.py` does) and assert the posted report contains the
  job ID, for a successful, a failing and a timed-out command.

## Files

- `scripts/lib/webhook/status.py`
- `scripts/tests/bin/test_diagnostics_job_id.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every diagnostics report posted by _run_cluster_diagnostics contains the job ID it was called with, for success, command failure and timeout.
  - id: M2
    text: The job ID in the report equals the one in the bridge's HTTP 202 response for the same request.
must_not:
  - id: N1
    text: A diagnostics report must not omit the job ID (red on the pre-fix status.py).
  - id: N2
    text: The fix must not change the Slack destination (channel, thread or response_url) of any report.
  - id: N3
    text: The fix must not change the diagnostic command, its arguments, masking or output clipping.
evidence:
  - id: E1
    proves: [M1, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/test_diagnostics_job_id.py with spawn and posting stubbed; N1 red on the pre-fix status.py; scripts/tests/bin/test_diagnostics_all_pods.py still green.
  - id: E2
    proves: [M1, M2]
    kind: live
    text: After make restart-webhook the operator submits one allowlisted diagnostic via bin/k3dm-cloud-request; Claude reads the Slack screenshot and the 202 response and confirms the IDs match.
interface:
  - scripts/lib/webhook/status.py _run_cluster_diagnostics(job_id, response_url, thread_ts=None, channel_id="", request=None)
  - bin/k3dm-cloud-request diagnostic actions (HTTP 202 response carries job_id)
```

## Definition of Done

- [ ] F1–F2 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix `status.py`.
- [ ] `pytest scripts/tests/bin` green.
- [ ] Commit: `fix(webhook): include the job ID in diagnostics reports`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT add `channel_id`/`thread_ts` to cloud-request payloads or change Slack routing; that is the v1.44.0 plan.
- Do NOT post to Slack or run real diagnostics in tests.
