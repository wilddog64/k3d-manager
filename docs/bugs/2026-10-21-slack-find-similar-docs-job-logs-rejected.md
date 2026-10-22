# P2 — Slack logs lookup for find-similar-docs job is rejected with usage

**Filed:** 2026-10-21
**Branch:** `k3d-manager-v1.43.5`
**Status:** OPEN — live failure reproduced by operator screenshot; root cause not yet established
**Priority:** P2 — ChatOps observability / job transcript retrieval
**Component:** Slack thread command parsing and webhook job log lookup
**Related:** `docs/bugs/2026-10-13-slack-logs-explicit-job-id-mismatch.md` (explicit ID lookup fix is LIVE-VERIFIED; preserve it); `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` (query execution is LIVE-VERIFIED)

## Symptom and evidence

The operator ran a Slack find-similar-docs query and received a successful job with prior-art results. The observed command/result sequence is:

```text
make find-similar-docs Q=what's recent e2e-remote issues
✅ make find-similar-docs Q=what's recent e2e-remote issues succeeded — job 08ae7d06
Prior art for: "what's recent e2e-remote issues"

logs 08ae7d06
Usage: logs|status|diagnosis|kill <job-id> — include the exact job ID

status 08ae7d06
Failed (operator-reported); exact Slack response was not supplied.
```

The operator reports that `logs <job-id>` succeeds for other jobs and that both `logs 08ae7d06` and `status 08ae7d06` fail for this find-similar-docs job. A separate screenshot provides a positive comparison:

```text
logs fb7db078
📋 Last 20 lines (job fb7db078)
...
make: *** [test-all] Error 2
```

The find-similar-docs job's successful output is visible, but its transcript and status could not be retrieved using its displayed job ID. The status failure is operator-reported; its exact response is not yet evidenced, so it must not be assumed to be the same usage error.

### Comparator retry — 2026-10-21

In a later `k3dm fix-list` thread, the operator sent the visible command `logs 013fdfe9` and received the same generic usage response, then repeated the same visible command and received `Last 20 lines (job 013fdfe9)` with the expected `fix-list` Make output. This is an intermittent parse/routing symptom across targets, not uniquely a find-similar-docs log-file issue. It also shows that the explicit lookup and log-selection path can succeed. The screenshots do not provide raw Slack event bodies, so whether the first event differed invisibly or was routed through different runtime state remains unknown. Keep this issue OPEN pending exact cause; do not infer that the earlier `status 08ae7d06` failure is resolved.

### Operator hypothesis: annotated/truncated ID — 2026-10-21

The operator suspects the failed inline command may have contained `...` (or another
non-hex suffix), while the successful retry was plain text. This is consistent with the
current parser: `_resolve_thread_job_target()` splits on whitespace and requires the ID
token to match `^[0-9a-f]{8}$`; for example, `logs 013fdfe9...` is intentionally rejected
with usage, while `logs 013fdfe9` is accepted. The screenshots' rendered text alone cannot
confirm the exact underlying message body. This is a plausible explanation, not a confirmed
root cause. It would also need to be checked against the reported `status 08ae7d06` attempt;
its exact submitted text and response remain unavailable.

## Source trace and limits

- In `bin/k3dm-webhook`, `_resolve_thread_job_target()` emits the usage text only when the normalized command does not contain exactly two whitespace-separated tokens or the second token fails `_JOB_ID_RE`.
- `_JOB_ID_RE` is `^[0-9a-f]{8}$`; `08ae7d06` matches it. The visible command also has the expected two tokens. Therefore the screenshot's usage response is inconsistent with the inspected release-branch parser receiving exactly `logs 08ae7d06`.
- This usage branch runs before job-directory lookup. The response does **not** establish that the job directory or transcript is absent, expired, or malformed.
- The `find-similar-docs` API Make path creates a normal eight-hex job directory, writes its target marker and available Slack thread/channel metadata, and uses the common `_run_make_target()` writer for `make.log`. The thread `logs` handler is target-agnostic after explicit ID resolution. Static inspection found no target-specific exclusion for `find-similar-docs`.
- The screenshots do not expose the raw Slack Events API text, event thread timestamp, selected parent/anchor job, or the webhook process revision. The exact point where the visible command diverges from the handler input is unknown. Do not claim stale deployment, bad log persistence, or a `find-similar-docs`-specific code branch without further evidence.

## Reproduction and investigation

1. Confirm the exact message text of the failed `logs 08ae7d06` and `status 08ae7d06` attempts, including any trailing ellipsis, punctuation, Slack markup, or copied placeholder. Do not infer the raw text from a visually similar screenshot.
2. If the failed token included non-hex text, classify that individual usage response as expected validation, then retry the exact plain-text command in the same thread.
3. If the raw ID was exactly eight lowercase hex characters, reproduce with a controlled find-similar-docs job and compare it with `logs <known-good-job-id>` in otherwise identical context.
4. Inspect sanitized webhook debug logs for the event's `text`, `thread_ts`, the `_find_job_by_thread_ts()` selected anchor, and `_resolve_thread_job_target()` result. Do not log tokens, response URLs, query secrets, or transcript contents beyond existing redaction policy.
5. Compare the find-similar-docs job directory metadata (`target`, `status`, `thread_ts`, `channel_id`) and `make.log` presence with the working job. Confirm the running webhook source/branch without exposing credentials.

No live commands were triggered by this report; reproduction remains operator-controlled.

## Expected behavior

For the displayed valid eight-hex ID, `logs 08ae7d06` must resolve that exact authorized job and return its redacted transcript or a precise same-ID unavailable/expired response. It must never return generic usage for an input matching the documented command contract. Preserve channel/thread authorization and the live-verified explicit-ID behavior for other targets.

## Acceptance criteria

- [ ] Determine whether the rejected inline commands actually included an ellipsis or other non-hex suffix; if not, identify the input/context condition causing rejection (event text parsing, thread-anchor selection, runtime-version mismatch, or job-record lifecycle).
- [ ] Add regression coverage for explicit `logs <id>` against a `find-similar-docs` job as well as a known working Make target, with otherwise identical thread/channel context.
- [ ] Exact ID lookup returns that job's `make.log` (or a precise result naming the same ID); usage is reserved for malformed/missing arguments.
- [ ] Preserve rejection of invalid IDs, cross-thread/channel protections, redaction, and the existing explicit-ID regression suite.
- [ ] Update related bug disposition only if investigation establishes a shared root cause; do not reopen the already-live-verified general explicit-ID fix solely from this target-specific symptom.

## Scope

Initial scope is diagnosis and a focused regression test. No broad job-retention change, implicit job selection, Slack permission change, unrelated Make-target modification, deployment, or live operation is authorized by this report.
