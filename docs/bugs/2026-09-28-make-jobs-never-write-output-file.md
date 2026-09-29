# Bug: `/api/v1/make` jobs never write `output`, so `job-status` always returns `""`

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), found while live-testing the cloud request helper
**Status:** FIXED 2026-09-29 by Claude (cloud session). The redaction hold is resolved: the output
goes through `_redact_secrets` then `scrub_credentials` (the shared scrubber the artifacts spec's M2
now imports), the same filters diagnostics output uses. Tests: `scripts/tests/bin/test_make_job_output.py`;
removing the write, dropping the scrubber, and writing after `status` each went red.
**Files:** `scripts/lib/webhook/lifecycle.py`, `scripts/tests/bin/` (a new test)

## Problem

A live `make-fix-list` request through the bridge came back `status: success` with
`"output": ""`, yet `make fix-list` prints one line per fix target.

`_run_make_target` (`scripts/lib/webhook/lifecycle.py:82`) captures the output with
`_spawn_capture_text`, posts the last 40 lines to Slack through `_notify_job`, and writes only
`status`. It never writes `JOB_DIR/<job_id>/output`. The `GET /api/v1/status/<id>` handler
(`bin/k3dm-webhook`, near line 2158) returns `""` when that file is missing. So every make job
reads as empty through `job-status`, whether it passed or failed. Every other job runner
(`_run_upgrade`, the agent jobs) writes `output`.

This also breaks a premise in `docs/plans/v1.40.0-cloud-request-artifacts.md`. Its Problem
section says `job-status` returns the last 2000 bytes of `${K3DM_JOB_DIR}/<job_id>/output` and
that "the full output already exists on the host". For make jobs, it does not.

## Fix

In `_run_make_target`, write `output` to `JOB_DIR / job_id / "output"` right after
`_spawn_capture_text` returns, before `status` is written, so a poller that sees a terminal
status always finds the output. Leave the Slack tail unchanged.

Redaction: `job-status` output reaches the `cloud-requests` branch, which is permanent. The
reader-tier targets exposed there today (`fix-list`, `fix-status`, `status-public`,
`observability-status`, `vuln-scan`, `e2e-runner-health`, `test-pytest`, `test-python-unit`,
`find-similar-docs`) already post the same tail to Slack, but a committed copy is a wider
audience. Decide with the artifacts spec's M2 redaction filter whether the output goes through
that filter before it is written. Do not ship this fix ahead of that decision.

## Tests

1. A make job whose command prints text leaves that text in `JOB_DIR/<id>/output`
   (stub `_spawn_capture_text`, point `JOB_DIR` at `tmp_path`).
2. Mutation: remove the write, and test 1 fails.

## Out of scope

- The 2000-byte tail limit on `job-status`. The artifacts spec owns that.
- The Slack notification text.
