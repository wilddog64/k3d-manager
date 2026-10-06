# Bug: `/api/v1/make` jobs never write `output`, so `job-status` always returns `""`

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), found while live-testing the cloud request helper
**Status:** OPEN — regression confirmed in v1.41.0 on 2026-10-06 (see below).
**Historical fix:** FIXED 2026-09-29 by Claude (cloud session). The redaction hold is resolved: the output
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

## Original fix (2026-09-29)

In `_run_make_target`, write `output` to `JOB_DIR / job_id / "output"` right after
`_spawn_capture_text` returns, before `status` is written, so a poller that sees a terminal
status always finds the output. Leave the Slack tail unchanged.

Redaction: `job-status` output reaches the `cloud-requests` branch, which is permanent. The
reader-tier targets exposed there today (`fix-list`, `fix-status`, `status-public`,
`observability-status`, `vuln-scan`, `e2e-runner-health`, `test-pytest`, `test-python-unit`,
`find-similar-docs`) already post the same tail to Slack, but a committed copy is a wider
audience. Decide with the artifacts spec's M2 redaction filter whether the output goes through
that filter before it is written. Do not ship this fix ahead of that decision.

## Original tests

1. A make job whose command prints text leaves that text in `JOB_DIR/<id>/output`
   (stub `_spawn_capture_text`, point `JOB_DIR` at `tmp_path`).
2. Mutation: remove the write, and test 1 fails.

## Out of scope

- The 2000-byte tail limit on `job-status`. The artifacts spec owns that.
- The Slack notification text.

## Regression in v1.41.0 — 2026-10-06

This is the canonical bug for the recurring empty Make-job output. The
[October 6 report](2026-10-06-cloud-bridge-make-job-status-empty-output.md)
preserves live request IDs, final bridge responses, Slack observations, and current
acceptance criteria. Failed test-all `ccc20dc9`, successful Python unit job `5cc7f225`,
and failed E2E `033ceddc` all returned empty output.

### Regression commit and validation gap

[Commit 73d0ef5682ed33f4792ab82181f37d41497fc96e](https://github.com/wilddog64/k3d-manager/commit/73d0ef5682ed33f4792ab82181f37d41497fc96e)
(`feat(webhook): write make job output to make.log`) changed `_run_make_target`
from captured output to streaming into `make.log`. Its diff removed the previously
fixed `output.write_text(scrub_credentials(_redact_secrets(output)))` operation
before terminal status. The HTTP job-status reader still selects only `output`.

The same commit changed `scripts/tests/bin/test_make_job_output.py` to assert
`make.log` exists at terminal status and contains command output. It replaced the
scrubbed-output test with a local-log preservation test that explicitly asserts
`output` does not exist. Those producer tests no longer check that the HTTP consumer
can retrieve a bounded, redacted tail. This identifies the repository regression;
the deployed host revision and actual job directories still need operator verification.

Slack's on-demand `logs`, `diagnosis`, and `ask` consumers also omit `make.log`,
while automatic Make notifications read it. The operator's exact Slack lookup error
is still needed to distinguish thread association from missing-file selection.

### Current fix direction

Preserve streaming local logs and restore the external retrieval contract. Use a
consistent selector for `make.log` and legacy `log` / `output` files, with explicit
precedence, bounded tails, existing job-ID/path validation, and credential redaction
before HTTP/Slack output or bridge publication. Raw local-log retention is not a
reason to expose raw logs externally. The original fix above is historical, not a
requirement to revert streaming.

Implement the acceptance criteria in the October 6 report, including consumer tests
for Make-only and legacy logs, multiple-file precedence, absent files, truncation,
and redaction. Removing Make-log selection must fail a retrieval test. Then verify
both cloud job-status and Slack retrieval on the actual job thread. The underlying
test-all/E2E failures remain separate and undiagnosed.

### Dedup and indexing evidence

The operator pasted output from cloud `make-find-similar-docs` request
`20261006T174341Z-make-find-similar-docs`, job `a4301fd9`: this September report
scored 0.778 and the October evidence report scored 0.856. This confirms retrieval
of both indexed reports at that time. The earlier offline search missed this older
file; retain the October path as linked evidence rather than a competing fix spec.

Documentation-only investigation: no runtime fix, additional test job, or raw log
publication in this update.
