# Bug: Slack `logs` command ignores acg-up job output file

## Summary

Slack thread command `logs <job_id>` reports `No log found for job <job_id>` for `acg-up` jobs even when the job directory contains an `output` transcript.

## Observed Output

For job `6190cbb9`, Slack returned:

```text
⚠️ No log found for job `6190cbb9`
```

The job directory exists at:

```text
~/.local/share/k3d-manager/webhook-jobs/6190cbb9
```

It contains `output`, `status`, `action`, `response_url`, and `thread_ts`, but no `log` file.

## Root Cause

`bin/k3dm-webhook` handled the `logs` thread command by reading only `JOB_DIR/<job_id>/log`. `acg-up` jobs write their live transcript to `output`, so the command failed whenever `log` was absent.

## Fix

Make `logs` fall back to `output` when `log` is missing, matching the existing `diagnosis` command behavior.
