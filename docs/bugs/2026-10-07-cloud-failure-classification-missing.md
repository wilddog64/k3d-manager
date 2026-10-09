# Cloud test failures lack an explicit triage classification

**Status:** FIXED in `2833c894`: `result_classification` is in terminal job responses

## Problem

A cloud `make-test-all` run can fail in the cloud environment while the same focused suite passes
locally. The response exposes `status: failed`, but does not say whether that is an untriaged first
failure, a confirmed reproducible defect, or a transient/environment-specific result.

## Fix

Terminal job responses and published summary artifacts now include `result_classification`:

- `passed` — terminal job status is success.
- `failed_untriaged` — terminal job status is failed; no focused rerun has confirmed the cause.
- `in_progress` — job is queued or running.

The original `status` and exit code remain authoritative. A rerun or human triage must explicitly
establish `transient_environment` or `confirmed_defect`; this change does not silently downgrade a
failed run.

## Verification

Cloud artifact summary tests assert `failed_untriaged` for failed jobs. The next cloud response
should expose the same field in `body.result_classification`.
