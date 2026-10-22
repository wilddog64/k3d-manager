# P2 — Slack logs lookup for find-similar-docs job is rejected with usage

**Filed:** 2026-10-21
**Branch:** `k3d-manager-v1.43.5`
**Status:** OPEN — offline Slack Events-path regression coverage and redacted rejection diagnostics are landed and verified; the historical/live intermittent rejection remains unexplained pending operator verification
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
Usage: logs|status|diagnosis|kill <job-id> — include the exact job ID
```

The operator reports that `logs <job-id>` succeeds for other jobs. Slack history confirms exact plain-text `logs 08ae7d06` and `status 08ae7d06` both received the generic usage response. A separate screenshot provides a positive comparison:

```text
logs fb7db078
📋 Last 20 lines (job fb7db078)
...
make: *** [test-all] Error 2
```

The find-similar-docs job's successful output is visible, but its transcript and status could not be retrieved using its displayed job ID. Slack history confirms that the status attempt also received the generic usage response.

### Slack message-history confirmation — 2026-10-21

Read-only Slack history search retrieved the original message texts and timestamps:

- `logs` alone at 17:15:58 PDT received usage; this response is expected for a missing ID.
- Exact plain-text `logs 08ae7d06` at 17:16:26 PDT received usage.
- Exact plain-text `status 08ae7d06` at 17:18:48 PDT received usage.
- Exact plain-text `logs 08ae7d06` at 17:19:05 PDT again received usage.
- In the `fix-list` thread, exact plain-text `logs 013fdfe9` at 17:27:51 PDT received usage; the identical visible text at 17:28:01 PDT returned that job's transcript.

Slack message links: [find-similar-docs failed lookup](https://devopsautomationhq.slack.com/archives/C0B7ZHG2LR4/p1792628186085839?thread_ts=1792628158.377709&cid=C0B7ZHG2LR4), [find-similar-docs status attempt](https://devopsautomationhq.slack.com/archives/C0B7ZHG2LR4/p1792628328800859?thread_ts=1792628158.377709&cid=C0B7ZHG2LR4), [fix-list usage attempt](https://devopsautomationhq.slack.com/archives/C0B7ZHG2LR4/p1792628871335539?thread_ts=1792628849.468139&cid=C0B7ZHG2LR4), [same visible command succeeding](https://devopsautomationhq.slack.com/archives/C0B7ZHG2LR4/p1792628881299689?thread_ts=1792628849.468139&cid=C0B7ZHG2LR4).

This confirms that the exact visible syntax was rejected at least once; it is not explained solely by an ellipsis in the displayed message. The retry shows the symptom is intermittent across different jobs.

### Comparator retry — 2026-10-21

In a later `k3dm fix-list` thread, the operator sent exact plain-text `logs 013fdfe9` and received the generic usage response, then repeated the same visible text and received `Last 20 lines (job 013fdfe9)` with the expected `fix-list` Make output. This confirms an intermittent rejection across targets, not a find-similar-docs log-file-specific issue. Slack search exposes the text and confirms both commands were visibly identical; the webhook's parsed arguments and serving process/runtime state remain unknown. The successful retry does not resolve the failed `status 08ae7d06` attempt.

### Operator hypothesis: annotated/truncated ID — 2026-10-21

The operator initially suspected an ellipsis or other non-hex suffix. Slack search now
shows the failed messages as exact plain-text commands with valid eight-hex IDs, so that
hypothesis alone does not explain the failures. Slack search exposes the message text, not
the webhook process/version or its internal parsed argument representation.

## Source trace and limits

- In `bin/k3dm-webhook`, `_resolve_thread_job_target()` emits the usage text only when the normalized command does not contain exactly two whitespace-separated tokens or the second token fails `_JOB_ID_RE`.
- `_JOB_ID_RE` is `^[0-9a-f]{8}$`; `08ae7d06` matches it. The visible command also has the expected two tokens. Therefore the screenshot's usage response is inconsistent with the inspected release-branch parser receiving exactly `logs 08ae7d06`.
- Focused tests for explicit `logs`/`status` IDs and cross-thread/channel rejection passed 5/5 against this checkout (`pytest -q scripts/tests/bin/test_webhook_thread_dispatch.py -k 'status_requires_exact_thread_job_id or status_explicit_id_resolves_once_and_ignores_mtime or logs_explicit_id_reads_requested_child or logs_rejects_cross_thread_explicit_id or logs_rejects_cross_channel_explicit_id_through_parent'`). These unit tests exercise the thread handler, not the live Slack Events request or its process/runtime selection.
- Follow-up local Events-path regression now exercises exact `logs aabbccdd` through `_Handler.do_POST`, `_find_job_by_thread_ts`, the guarded thread worker, and the explicit-ID resolver for both `find-similar-docs` and `test-all`, using the same thread/channel context. The focused selector including these cases passed 7/7; the complete `test_webhook_thread_dispatch.py` module passed 36/36. This proves the current checkout routes both target records correctly, but does not identify the historical event payload or live serving code that produced the usage replies.
- Malformed or missing explicit-target arguments now emit a reason-coded warning with only the normalized command name, rejection reason, and token count. No message body, ID, response URL, credentials, or transcript content is logged. This instrumentation can distinguish malformed argument count from an invalid ID in future runtime logs; no such historical logs are available to classify the reported events.
- Landed diagnostic/regression change: `7e176833` on `k3d-manager-v1.43.5`. Independent verification: `pytest -q scripts/tests/bin/test_webhook_thread_dispatch.py` passed 36/36; Python AST parse, `git diff --check`, `_agent_audit`, `_agent_lint`, and `make check-doc-links` passed (`2300 file(s) OK`); dispatcher landing gate passed. A local `py_compile` attempt could not write its cache under the isolated task worktree (`Operation not permitted`); AST parsing passed instead. This verifies current source behavior and safe diagnostics, but does not establish why the historical Slack events were parsed differently or confirm the deployed webhook revision.
- The local LaunchAgent plist's `ProgramArguments` points at `/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook`. This establishes the configured path, not the code revision loaded by the process at the time of the Slack events. `launchctl list` produced no matching service row in this session, and `pgrep` could not inspect processes (`sysmon request failed with error: sysmond service not found`); the active process/revision therefore remains unverified.
- This usage branch runs before job-directory lookup. The response does **not** establish that the job directory or transcript is absent, expired, or malformed.
- The `find-similar-docs` API Make path creates a normal eight-hex job directory, writes its target marker and available Slack thread/channel metadata, and uses the common `_run_make_target()` writer for `make.log`. The thread `logs` handler is target-agnostic after explicit ID resolution. Static inspection found no target-specific exclusion for `find-similar-docs`.
- Slack history provides the visible message text and thread timestamps, but not the raw Events API payload as received by the webhook, selected parent/anchor job, parsed token values, or webhook process revision. The exact point where the visible command diverges from handler input remains unknown. Do not claim stale deployment, bad log persistence, or a `find-similar-docs`-specific code branch without further evidence.

## Reproduction and investigation

1. Exercise the exact plain-text commands through the Slack Events request-handling path in a local test harness, not only by calling `_handle_thread_command()` directly; assert valid IDs never produce usage and preserve authorization boundaries.
2. Trace the command safely from event receipt through `_run_thread_command_guarded`, `_handle_thread_command`, and `_resolve_thread_job_target`. Add reason-coded diagnostics for rejected arguments and a reliable runtime build/source identifier if needed. Do not log message bodies, response URLs, credentials, or transcript contents.
3. Determine whether a stale or duplicate webhook process/runtime can account for the intermittent replies. This requires evidence; the plist path alone is not proof of the running revision.
4. Implement the narrowest source fix supported by a reproducing test. If current code remains correct and the cause is strictly deployment/runtime state, report that and document the exact operator-safe confirmation/restart path rather than changing command semantics.

No live commands were triggered by this report. The instrumentation is now landed, but the original symptom remains open until an operator tests the updated webhook process and confirms exact-ID lookup behavior (or captures a reason-coded warning for a rejected command).

## Expected behavior

For the displayed valid eight-hex ID, `logs 08ae7d06` must resolve that exact authorized job and return its redacted transcript or a precise same-ID unavailable/expired response. It must never return generic usage for an input matching the documented command contract. Preserve channel/thread authorization and the live-verified explicit-ID behavior for other targets.

## Acceptance criteria

- [ ] Determine whether the rejected inline commands actually included an ellipsis or other non-hex suffix; if not, identify the input/context condition causing rejection (event text parsing, thread-anchor selection, runtime-version mismatch, or job-record lifecycle).
- [ ] Add regression coverage for explicit `logs <id>` against a `find-similar-docs` job as well as a known working Make target, with otherwise identical thread/channel context.
- [ ] Exact ID lookup returns that job's `make.log` (or a precise result naming the same ID); usage is reserved for malformed/missing arguments.
- [ ] Preserve rejection of invalid IDs, cross-thread/channel protections, redaction, and the existing explicit-ID regression suite.
- [ ] Update related bug disposition only if investigation establishes a shared root cause; do not reopen the already-live-verified general explicit-ID fix solely from this target-specific symptom.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_thread_dispatch.py`
- `docs/bugs/2026-10-21-slack-find-similar-docs-job-logs-rejected.md`
- `docs/issues/2026-10-21-slack-job-lookup-intermittent-usage-investigation.md` (only if a distinct root-cause report is needed)

## Scope

Diagnose and fix (or prove the absence of a source defect in) the intermittent rejection of exact valid IDs, adding focused regression coverage. Preserve explicit-ID-only semantics and all authorization boundaries. No broad job-retention change, implicit job selection, Slack permission change, unrelated Make-target modification, deployment/restart, or live operation is authorized.
