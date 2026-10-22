# Bug: short cluster-down jobs send no execution summary to Slack

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — implementation not started
**Priority:** P3 — ChatOps observability / operator feedback
**Severity:** low
**Approval:** explicit operator request to file this bug, 2026-10-15
**Dispatch approval:** operator requested review and dispatch of current-release P3 bugs, 2026-10-22
**Evidence:** Slack screenshot of AWS ACG sandbox teardown job `b0e9616d`, which reported `cluster-down (aws) — success in 1m` with no execution details.

## Symptom

The lifecycle job's Slack thread contains a start notification and a terminal green `success in 1m` message, but no log excerpt or teardown summary. The operator cannot tell from Slack which AWS resources were removed, whether CloudFormation stack deletion was verified, or whether there were cleanup warnings. The screenshot does **not** demonstrate that teardown failed or that retained job logs are absent.

## Verified source behavior

In `scripts/lib/webhook/lifecycle.py:_run_cluster`:

- Command output is written to the job-local `output` file.
- A progress timer begins at **120 seconds** and publishes an output tail using `_notify_job`.
- On completion, `_finish` cancels the timer and sends only `✅/❌ cluster-{action} ({provider}) — {status} in {elapsed}m` to Slack.
- Consequently, a job completing in less than two minutes has no scheduled progress excerpt and the success notification never supplies an output excerpt.

This is a **confirmed short-job notification coverage gap**, distinct from the separately tracked Slack thread-context issue (`docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md`).

## Investigation and fix requirements

1. Show a bounded, credential-redacted **terminal output summary** for completed short lifecycle jobs, especially `cluster-down`; include the action, provider, job ID, exit status, and meaningful final log lines, or offer an authenticated job-log lookup reference.
2. Verify whether the underlying `make down KEEP_LOCAL=1` contract provides independent evidence that CloudFormation resources were actually deleted. Do not equate exit code 0 with externally verified destruction. Report this distinction clearly without adding destructive verification steps.
3. Reuse the existing secret scrubbing/redaction pipeline and Slack size constraints. No credential material, raw response URLs, environment secrets, or unbounded command output.
4. Keep the existing periodic progress updates for long-running jobs; avoid duplicate noise if the terminal summary repeats a recent progress tail.
5. Use the same job's intended Slack thread (subject to the separately filed threading regression) and maintain the job ID for correlation.
6. Cover `cluster-up`, `cluster-down`, and `cluster-resume` where the same short-job notification design applies; distinguish refresh handlers with their own final output behavior rather than assuming identical coverage.

## Acceptance and regression tests

- A stubbed `cluster-down` finishing within 120 seconds publishes a meaningful, redacted terminal summary to the expected Slack posting helper.
- A stubbed job exceeding 120 seconds still publishes progress and a terminal result without excessive duplicate text.
- Empty output, output containing secrets, excessively long output, nonzero exit and timeout paths each have safe, informative terminal behavior.
- The completion summary correctly labels **command success** versus **verified external teardown**, where separate verification is unavailable.
- No real AWS lifecycle operation is run in automated tests.

## Files

- `scripts/lib/webhook/lifecycle.py`
- `scripts/tests/bin/webhook_lifecycle.py`
- `scripts/tests/lib/webhook.bats`

**Implementation:** not started. No AWS resources or live job were modified when this bug was filed.
