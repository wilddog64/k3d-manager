# P2 — Slack logs lookup for find-similar-docs job is rejected with usage

**Filed:** 2026-10-21
**Branch:** `k3d-manager-v1.43.5`
**Status:** OPEN — live failure reproduced by operator screenshot; root cause not yet established
**Priority:** P2 — ChatOps observability / job transcript retrieval
**Component:** Slack thread command parsing and webhook job log lookup
**Related:** `docs/bugs/2026-10-13-slack-logs-explicit-job-id-mismatch.md` (explicit ID lookup fix is LIVE-VERIFIED; preserve it); `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` (query execution is LIVE-VERIFIED)

## Symptom and evidence

The operator successfully ran `make find-similar-docs Q=what's recent e2e-remote issues`; Slack reported success under job ID `08ae7d06` and returned prior-art results. In the same conversational context, the operator then sent:

```text
logs 08ae7d06
```

The webhook replied:

```text
Usage: logs|status|diagnosis|kill <job-id> — include the exact job ID
```

The operator reports that `logs <job-id>` succeeds for other jobs and this failure is specific to the find-similar-docs job. A separate screenshot shows `logs fb7db078` returning the last 20 lines of a `make test-all` job. The find-similar-docs job's successful output is visible, but its transcript could not be retrieved with its displayed job ID.

## Source trace and limits

- In `bin/k3dm-webhook`, `_resolve_thread_job_target()` emits the usage text only when the normalized command does not contain exactly two whitespace-separated tokens or the second token fails `_JOB_ID_RE`.
- `_JOB_ID_RE` is `^[0-9a-f]{8}$`; `08ae7d06` matches it. The visible command also has the expected two tokens. Therefore the screenshot's usage response is inconsistent with the inspected release-branch parser receiving exactly `logs 08ae7d06`.
- This usage branch runs before job-directory lookup. The response does **not** establish that the job directory or transcript is absent, expired, or malformed.
- The `find-similar-docs` API Make path creates a normal eight-hex job directory, writes its target marker and available Slack thread/channel metadata, and uses the common `_run_make_target()` writer for `make.log`. The thread `logs` handler is target-agnostic after explicit ID resolution. Static inspection found no target-specific exclusion for `find-similar-docs`.
- The screenshots do not expose the raw Slack Events API text, event thread timestamp, selected parent/anchor job, or the webhook process revision. The exact point where the visible command diverges from the handler input is unknown. Do not claim stale deployment, bad log persistence, or a `find-similar-docs`-specific code branch without further evidence.

## Reproduction and investigation

1. Run a controlled `find-similar-docs` command through the same Slack entry point and capture its queued/succeeded job ID and thread.
2. In that thread, send the exact plain-text message `logs <that-job-id>` and capture the reply.
3. In the same webhook process and thread, request `logs <known-good-job-id>` for a job already proven to work, to isolate entry point/target effects from channel, user, and runtime differences.
4. Inspect sanitized webhook debug logs for the event's `text`, `thread_ts`, the `_find_job_by_thread_ts()` selected anchor, and `_resolve_thread_job_target()` result. Do not log tokens, response URLs, query secrets, or transcript contents beyond existing redaction policy.
5. Compare the `find-similar-docs` job directory metadata (`target`, `status`, `thread_ts`, `channel_id`) and `make.log` presence with the working job. Confirm the running webhook source/branch without exposing credentials.

No live commands were triggered by this report; reproduction remains operator-controlled.

## Expected behavior

For the displayed valid eight-hex ID, `logs 08ae7d06` must resolve that exact authorized job and return its redacted transcript or a precise same-ID unavailable/expired response. It must never return generic usage for an input matching the documented command contract. Preserve channel/thread authorization and the live-verified explicit-ID behavior for other targets.

## Acceptance criteria

- [ ] Identify which input/context condition makes the handler reject the visible `logs 08ae7d06` request; distinguish event text parsing, thread-anchor selection, runtime-version mismatch, and job-record lifecycle.
- [ ] Add regression coverage for explicit `logs <id>` against a `find-similar-docs` job as well as a known working Make target, with otherwise identical thread/channel context.
- [ ] Exact ID lookup returns that job's `make.log` (or a precise result naming the same ID); usage is reserved for malformed/missing arguments.
- [ ] Preserve rejection of invalid IDs, cross-thread/channel protections, redaction, and the existing explicit-ID regression suite.
- [ ] Update related bug disposition only if investigation establishes a shared root cause; do not reopen the already-live-verified general explicit-ID fix solely from this target-specific symptom.

## Scope

Initial scope is diagnosis and a focused regression test. No broad job-retention change, implicit job selection, Slack permission change, unrelated Make-target modification, deployment, or live operation is authorized by this report.
