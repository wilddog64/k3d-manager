# Bug: Slack logs command substitutes unrelated job ID (2026-10-13)

**Filed:** 2026-10-13
**Status:** LIVE-VERIFIED — 2026-10-20: operator ran `logs 26f2035e` in Slack; the bot returned `Last 20 lines (job 26f2035e)` and the transcript showed E2E run `1792455493-30189` with `exit_code=0` / `result=pass`.
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 (ChatOps observability / job correlation)
**Release:** v1.43.5 (triage 2026-10-15, operator-approved placement)
**Reported:** 2026-10-13, operator
**Approval:** standing bug-filing (report only; no runtime changes approved)
**Component:** Slack /k3dm thread command routing; job-ID resolution; webhook job log lookup
**Fix commit:** `177ba541`
**Related:** `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md` (thread association vs arbitrary ID lookup distinction)
**Evidence:** Operator Slack screenshots, 2026-10-13 and 2026-10-14; source inspection of `bin/k3dm-webhook`; live Slack-thread job `26f2035e` with `target=e2e-sandbox`, `status=success`, and `make.log`; E2E result `/Users/cliang/.k3dm/e2e/1792455493-30189.json` with `exit_code=0` and `result=pass`.
**Live evidence:** 2026-10-20 · run 1792455493-30189 · env Slack/e2e-sandbox · scenario slack-logs-26f2035e · commit 177ba541 · proves fix

## Files

| File | Scope |
|---|---|
| `bin/k3dm-webhook` | Parse an explicit Slack `logs <job-id>` argument and resolve that authorized job without substituting a thread anchor. |
| `scripts/tests/bin/test_webhook_thread_dispatch.py` | Add regression coverage for explicit IDs, thread anchors, repeated lookups, and running/finished jobs. |

Do not change job log retention, authorization policy, or unrelated Make producers.

## Symptom

After issuing `k3dm e2e-remote RUNNER=m2` through Slack, the bot reported:

- `k3dm e2e-remote queued — job c83ef98a`
- `make e2e-remote RUNNER=m2 started by slack-thread:admin`

The operator then entered `logs c83ef98a` in the same Slack thread (twice).
Both replies were:

- `No log found for job a2e57e32`

**The ID in the response does not equal the explicitly requested ID.** The screenshot alone does not prove whether the requested job has logs, whether E2E succeeded, or why `a2e57e32` was selected.

## Reproduction

1. Queue `k3dm e2e-remote RUNNER=m2` through Slack and capture queued job ID `A`.
2. In the Slack thread, send `logs A`.
3. Observe whether the bot looks up `A` or instead uses unrelated job ID `B` from a thread binding or parser default.
4. Repeat with another existing job ID from the same and a different thread. Verify authorization checks still apply.

**Actual observed:** explicit `logs c83ef98a` returned missing-log message for `a2e57e32`.

**Expected:** For an accepted explicit job-ID argument, resolve exactly that job ID (subject to authorization), returning its transcript or a precise error naming the same ID. If explicit job-ID lookup is unsupported by design, reject it with clear usage guidance; never silently substitute a thread-linked ID. The thread-only `logs` form may continue to use the associated job when documented.

## Investigation (do not presume cause)

- Trace Slack command parsing, thread/job mapping, webhook routing, and log-storage filename selection.
- Determine whether `logs A` is parsed as an explicit ID or ignored while selecting the thread's current job.
- Check actual job metadata and transcript paths for `c83ef98a` and `a2e57e32`. Do not infer that either job is missing merely from this response.
- Verify whether the newer job launch updates the correct thread association and whether the command is authorized to access explicitly supplied IDs.
- Check for overlap with the 2026-10-06 job-status/log bug and avoid a duplicate fix.
- Explain why both repeated explicit requests returned the same different job ID.

## Acceptance criteria

- [x] Exact job-ID selection semantics are documented for Slack `logs` (explicit argument versus thread default).
- [x] An explicit `logs A` never returns a status message referencing different ID `B`; unauthorized IDs are rejected safely.
- [x] `logs` with no argument retains documented thread association behavior.
- [x] Existing job log files / incomplete or running jobs return accurate `running`, `pending`, `not found`, or `unavailable` responses without inventing log content.
- [x] Regression tests cover two distinct IDs, repeated calls, same-thread and cross-thread access, missing job, and running job; assert that lookup ID and reported ID agree.
- [x] Verify on a live Slack test job and capture sanitized evidence before closing.
- [ ] Preserve logging redaction, job authorization, retention, and thread security policy.

## Files

Locate and modify only relevant Slack webhook thread-command parsing, job lookup, tests and documentation after root-cause verification. No infrastructure/E2E-runner modification is implied by this report.

## Additional reproduction and source investigation — 2026-10-14

The operator queued `k3dm test` in Slack. Bot confirmed `k3dm test queued — job e45ba2fd` and `make test started by slack-thread:admin`. In the same thread the operator sent `logs e45ba2fd`, but the bot replied `No log found for job e45ba2fd`. Unlike the Oct 13 example, this response uses the same visible ID; it still does **not** demonstrate a lookup of the requested ID, because the message is constructed with the resolved thread job ID. The test may still have been running. Its outcome and the contents of its real log were not established.

Code inspection confirms a defect:
- `bin/k3dm-webhook` `_handle_thread_command`, around lines 841–847, handles `logs` with `read_job_output(JOB_DIR / job_id, ...)`, ignoring every argument after the command. Thus `logs e45ba2fd` does **not** explicitly resolve `e45ba2fd`.
- `/slack/events`, around lines 2052–2064, determines `job_id` via `_find_job_by_thread_ts(thread_ts)`.
- `_find_job_by_thread_ts`, around lines 624–637, returns the **first** matching `*/thread_ts` found by an unsorted glob. The original thread anchor and newly spawned test job share the same `thread_ts`, so selection can be ambiguous. This may cause lookup of an anchor without output, but the exact lookup result is not established without runtime evidence.

**Expected fix:** Parse and validate optional explicit `logs <job-id>` and use that specific authorized job. Define the default for bare `logs` in a multi-job thread deterministically (e.g. most recent relevant child), rather than first arbitrary glob match. Ensure a running job with no output yet is distinct from absent job/log; preserve redaction and per-user authorization. Add regression cases for `k3dm test` followed by immediate `logs <queued-id>`, both while running and after completion. Do not silently replace a supplied ID with any thread ancestor.

## Live reproduction — 2026-10-19

Slack job `d5261dfb` was reported as having no log. The local job directory contained only:

```text
status=thread-anchor
thread_ts=1792455452.742509
```

The same thread contained the actual Make child job:

```text
26f2035e status=running target=e2e-sandbox make.log=yes
```

The target marker and `make.log` were present on the child, proving the preceding Make-log marker fix was active. Slack still looked up the anchor when the operator requested `logs d5261dfb`, confirming the explicit-ID/thread-association defect remains reproducible live.

## Verification evidence

- Focused Python tests: `25/25` passed across thread dispatch, ask-docs thread behavior, and job-output selection.
- Relevant BATS suites: `14/14` passed.
- Syntax validation and `_agent_audit`: passed.
