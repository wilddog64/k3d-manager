# Bug: Slack logs command substitutes unrelated job ID (2026-10-13)

**Filed:** 2026-10-13
**Status:** OPEN — reproducible symptom; source confirms explicit argument is ignored; exact selected job requires live log verification
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 (ChatOps observability / job correlation)
**Release:** v1.43.5 (triage 2026-10-15, operator-approved placement)
**Reported:** 2026-10-13, operator
**Approval:** standing bug-filing (report only; no runtime changes approved)
**Component:** Slack /k3dm thread command routing; job-ID resolution; webhook job log lookup
**Related:** `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md` (thread association vs arbitrary ID lookup distinction)
**Evidence:** Operator Slack screenshots, 2026-10-13 and 2026-10-14; source inspection of `bin/k3dm-webhook` on `k3d-manager-v1.43.2`. No access to live job directories or webhook logs.

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

- [ ] Exact job-ID selection semantics are documented for Slack `logs` (explicit argument versus thread default).
- [ ] An explicit `logs A` never returns a status message referencing different ID `B`; unauthorized IDs are rejected safely.
- [ ] `logs` with no argument retains documented thread association behavior.
- [ ] Existing job log files / incomplete or running jobs return accurate `running`, `pending`, `not found`, or `unavailable` responses without inventing log content.
- [ ] Regression tests cover two distinct IDs, repeated calls, same-thread and cross-thread access, missing job, and running job; assert that lookup ID and reported ID agree.
- [ ] Verify on a live Slack test job and capture sanitized evidence before closing.
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
