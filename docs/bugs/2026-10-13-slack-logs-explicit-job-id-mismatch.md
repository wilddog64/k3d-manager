# Slack logs command substitutes unrelated job ID (2026-10-13)

**Status:** OPEN — reported by operator, not yet source-confirmed
**Priority:** P2 (ChatOps observability / job correlation)
**Release:** v1.43.2 (triage; reschedule explicitly if the patch is full)
**Reported:** 2026-10-13, operator
**Approval:** standing bug-filing (report only; no runtime changes approved)
**Component:** Slack /k3dm thread command routing; job-ID resolution; webhook job log lookup
**Related:** `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md` (thread association vs arbitrary ID lookup distinction)
**Evidence:** Operator Slack screenshot, 2026-10-13 ~17:01 Pacific. No access to live job directories or webhook logs; root cause unverified.

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
