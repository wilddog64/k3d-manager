# ask-docs model failure is reported as success and loses diagnostic detail

**Filed:** 2026-10-06
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** FIXED in branch; live service verification pending
**Severity:** Medium — a sourced Q&A request cannot be summarized and failure is hidden in job status
**Components:** `scripts/lib/webhook/agent.py`, `scripts/lib/webhook/ask_docs.py`, `bin/k3dm-webhook`

## Operator evidence

Slack at 10:44 AM America/Los_Angeles:

```text
ask-docs: what's the most recent bugs filed
```

Reply at 10:48 AM:

```text
AI analysis unavailable — agy: exit 1; gemini: timed out
```

No job ID, deployed revision, CLI diagnostic output, or complete source list was supplied.
Do not infer that sources were absent from this partial Slack paste.

## Findings on the current branch

Inspected at commit `4f1f00868201c06b5225d3535cddcee8840f6f45`.

1. `ask_docs.answer` retrieves allowed, readable excerpts before calling the summary model.
   This sentinel therefore identifies a summary failure on this code path, not an empty
   vector search. The live host revision is not independently verified.
2. `agent._call_gemini` defaults to candidates `agy,gemini`. It reports unrecognized
   nonzero exits as `exit 1`; no matching signature establishes authentication, quota,
   network, or model availability as the cause. Gemini exceeded the remaining budget.
3. The shared total budget defaults to 180 seconds via `K3DM_AI_TOTAL_BUDGET_S`.
   The first candidate may consume the whole budget; a candidate with less than 15 seconds
   remaining is skipped. Fallback is implemented, but a useful attempt is not guaranteed.
   The four-minute Slack interval includes other work and is not an exact model timing.
4. The wrapper captures stdout/stderr in a temporary file, reads it, and deletes it.
   Only a short reason survives failures; timeout handling discards diagnostic content
   without classification. Keeping raw auth output out of Slack is intentional and must
   remain intact, but safe failure metadata is needed for diagnosis.
5. `ask_docs.answer` treats the unavailable sentinel as ordinary prose and retains its
   source list. `_run_ask_docs` then unconditionally writes terminal `success` when
   the function returns. Model failure does not raise, so its failed-status branch is
   not reached. This is a confirmed repository defect, not a verified live status read.

A provider outage or expired credentials is not itself a software bug. Incorrect outcome
reporting and insufficient actionable diagnostics are the bug here.

## Expected behavior / acceptance

- [x] Distinguish successful summarization, intentional sources-only mode, and a failed
  summary with usable retrieved sources. Use explicit result metadata rather than treating
  an unavailable sentinel as a successful answer.
- [x] Failed summarization must not appear as an ordinary successful summary in job status.
  Define and document the degraded/failed status contract while preserving source links.
- [x] Return retrieved titles, dates, and links when summarization fails, with a concise
  reason. `--sources` remains read-only and does not invoke the summary model.
- [x] Preserve bounded, scrubbed diagnostic metadata: candidate, elapsed time, exit code,
  timeout, and a safe error category. Never publish raw prompts, credentials, OAuth URLs,
  or unfiltered stdout/stderr to Slack or GitHub.
- [x] Bound each candidate attempt within the total deadline and reserve a useful budget
  for an enabled fallback. Keep pinned-binary behavior and existing configuration compatible.
- [x] Test nonzero exit, timeout, both candidates unavailable, first candidate success,
  fallback success, exhausted budget, sources retention, status propagation, and redaction.
  Removing failure propagation or fallback budget reservation must turn a test red.
- [ ] Verify the actual service environment on the host; a successful interactive CLI
  invocation alone does not establish service-account credential or keychain access.

## Optional model routing — separate design choice

A cheaper summary model is configurable independently for agy and Gemini using
`K3DM_ANALYSIS_MODEL` and `K3DM_ANALYSIS_MODEL_GEMINI`. Changing price/model does not
fix failed-state reporting or diagnose this incident. Model IDs and current cost/limits
must be verified before deployment.

A different provider could provide a stronger fallback, but adding Claude/Codex requires
a CLI-specific adapter; changing `K3DM_AI_BIN_ORDER` alone does not implement it.
Keep credential configuration, per-attempt deadlines, failure classification, and source
grounding explicit. Do not broaden roles or enable tool execution for summary prompts.
Deterministic date/title/status listings for simple recent-bug requests are also an
optional enhancement, not required to fix this incident.

## Workaround

```text
/ask-docs --sources what's the most recent bugs filed
```

This bypasses summarization and returns date-sorted results among retrieved candidates.
It does not guarantee an exhaustive listing of every newly filed bug.

## Verification and limitations

Offline injected-model check returned:

```text
sentinel_preserved: True
sources_preserved: True
recency_detected: True
```

Existing CLI fallback tests, using fake binaries:

```text
........
----------------------------------------------------------------------
Ran 8 tests in 8.023s

OK
```

Command: `/usr/bin/python3 scripts/tests/bin/test_webhook_ai_fallback.py`.
The runtime Python could not execute the fake CLI spawn path (`NotImplementedError`);
the system Python above passed. The broader pytest attempt could not start:

```text
/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3: No module named pytest
```

These tests do not probe the host's real model credentials or explain the live agy exit.
No runtime change, provider swap, or additional live test job was made.

## Related reports and dedup

- [AI CLI auth failure and fallback](2026-09-23-agy-auth-failure-posts-oauth-url-as-ai-analysis.md):
  earlier fix prevents raw OAuth output reaching Slack and adds candidate fallback.
  This report covers failure propagation, safe diagnosis, and budget behavior after that fix.
- [ask-docs threading and sources-only mode](2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md).
- [ask-docs recency](2026-10-01-ask-docs-ignores-recency.md).
- [AI fallback operator guide](../guides/ai-analysis-fallback.md).

Exact-slug and repository text search found no existing report for this outcome-reporting
defect. Local `make find-similar-docs` could not retrieve because embedding credentials,
security, and kubectl are unavailable in this cloud workspace; advisory vector dedup was
not performed. Filing does not establish that this new report has been indexed.
