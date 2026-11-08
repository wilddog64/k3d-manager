# Bug: a Slack "gemini …" status question gets "please provide kubectl output": the ask path collects nothing

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** pre-existing (the no-tools guard in `_call_gemini` dates from `fd281c85`, v1.24.0; the Gemini ask
branch has no collection step)
**Should have been caught by:** unknown
**Severity:** low — a Gemini ask about live state never gets an answer; workarounds: `/cluster-status hostinger`, or ask
Claude, whose ask path has read-only kubectl
**Approval:** operator, 2026-11-08 ("go ahead to file a P3 and put it on dispatch queue")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, Slack, 2026-11-08 (screenshot: "gemini show me the current hostinger status")
**Affected:** `scripts/lib/webhook/agent.py` (`_run_cluster_ask`, gemini branch)
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-10-30-webhook-ai-analysis-trusts-log-text-prompt-injection.md` (FIXED `e9cb9129`: collected
text reaches a model only through `webhook.untrusted.fence`, and its answer through `filter_suggestion`)

## Symptom

Slack, 2026-11-08, the operator: "gemini show me the current hostinger status". k3d-manager replied "Asking gemini…",
then: "🤖 gemini: The provided context contains no pre-collected data, cluster diagnostics, or telemetry regarding
Hostinger or the remote k3s environment. Please provide the relevant `kubectl` output (e.g., node status, pod states,
or ingress metrics) or Hostinger VPS status data to analyze."

## Root cause

- `_run_cluster_ask` with `agent == "gemini"` (`scripts/lib/webhook/agent.py:429-462`) builds the prompt from the
  system text, the Slack thread context and the question only. No data is collected.
- `_call_gemini` (`agent.py:117-122`) prefixes: "You are analyzing pre-collected data in a HEADLESS session … Do NOT
  run any commands or call any tools … if it is insufficient, say so briefly." Gemini did exactly that.
- The Gemini system text still says to "run `kubectl describe pod …` first" (`agent.py:449-452`), which the guard
  forbids.
- `/hostinger-status` (`_run_hostinger_status`, `scripts/lib/webhook/status.py:401`) does collect, in Python:
  `_smoke_test_services(provider="k3s-hostinger")` (`status.py:428`), a payload, and
  `_format_status_summary_slack(payload, "k3s-hostinger")` (`status.py:447`). It does not run `bin/cluster-status`;
  the docstring at `status.py:402` saying so is stale.

## Fix

Scope: Hostinger only (the reported case). Other live-state questions get a pointer, not a new collector.

1. **Extract the collector.** In `status.py`, move the smoke-test-to-text part of `_run_hostinger_status`
   (`status.py:428-447`) into `_hostinger_status_text()`, which returns the formatted summary.
   `_run_hostinger_status` calls it, and its own behaviour and output stay unchanged. Fix the stale docstring.
2. **Match on the user's own words only.** The Slack route (`bin/k3dm-webhook:1146-1170`) prepends up to 80 lines of
   earlier job output to `question`. Add a keyword argument `user_question=None` to `_run_cluster_ask`. The Slack
   route passes the user's original text; when it is `None`, `question` is used. A collector runs only when
   `user_question` matches `\bhostinger\b` or `\bk3s-hostinger\b`, case-insensitive. Job output and thread context
   are never matched.
3. **Collect, then fence.** On a match, the gemini branch calls `status._hostinger_status_text()`, imported inside
   the function to avoid the circular `status → agent` import. It runs synchronously in the ask thread with a hard
   timeout of 120 s (a `concurrent.futures` worker joined with that timeout), with no extra retries. Its text is then
   passed through `redact.scrub_credentials`, truncated as `status.py:414-417` does (over 3400 chars, keep the first
   1600 and the last 1800), and put in the prompt only through `fence("hostinger status", text)`. Order: scrub,
   truncate, fence.
4. **Filter the answer, and file nothing.** When a collector fed the prompt, the answer passes through
   `filter_suggestion`, and `_parse_gemini_observations` still strips `OBSERVATIONS:` lines but files no bug docs
   (add `file_bugs=True` as a keyword argument; this path passes `False`). Collected log text must not be able to
   file a bug.
5. **Failure.** If the collector raises or times out, Gemini is not called. The reply is exactly:
   `Hostinger status collection failed: <reason>. Run /cluster-status hostinger.`, where `<reason>` is the exception's
   class name or `timed out after 120s`.
6. **No match.** Gemini is called as today, and the prompt gains this line before the question:
   `No live data was collected for this question. If it asks about live cluster state, say that /cluster-status hostinger or asking claude answers it; do not ask the user for kubectl output.`
7. Remove the "run `kubectl describe pod …` first" instruction (`agent.py:449-452`) from the Gemini system text.
8. All replies go through the existing `_finish` (`agent.py:355-366`). The job `output` file gets only the scrubbed
   reply, never the raw collector text.

## Files

- `scripts/lib/webhook/agent.py`
- `scripts/lib/webhook/status.py`
- `bin/k3dm-webhook` (pass `user_question` on the Slack ask route)
- `scripts/tests/bin/test_webhook_ask_gemini_context.py` (new)
- `scripts/tests/fixtures/webhook-hostinger-status-2026-11-08.txt` (captured; read-only for the worker)

## Do not

- Change `_call_gemini`, its guard text or `_ai_candidates`.
- Touch the claude or codex branches of `_run_cluster_ask`.
- Pass the question, or any part of it, into a collector's arguments or environment.
- Use `shell=True`, or call `bin/cluster-status`, `aws`, `kubectl` or `scripts/k3d-manager` from the ask path.
- Add retries beyond those `_smoke_test_services` already has.

## Acceptance

```yaml
must:
  - id: M1
    text: "a gemini ask whose user text names Hostinger runs the Hostinger status collector once, and the prompt given to Gemini contains that collector's text inside a fence block"
  - id: M2
    text: "a gemini ask with collected data gets an answer that has passed filter_suggestion, and files no docs/bugs file even when the answer carries an OBSERVATIONS line"
  - id: M3
    text: "a gemini ask whose user text does not name Hostinger runs no collector, and its prompt contains 'No live data was collected for this question' and '/cluster-status hostinger'"
  - id: M4
    text: "when the collector raises or exceeds 120 s, Gemini is not called and the reply is 'Hostinger status collection failed: <reason>. Run /cluster-status hostinger.'"
  - id: M5
    text: "the report _run_hostinger_status posts (webhook route /api/v1/hostinger-status) is unchanged (paired control for the collector extraction)"
must_not:
  - id: N1
    text: "a collector runs because earlier job output or thread context names Hostinger when the user's own text does not (paired with M1)"
  - id: N2
    text: "collected text reaches the prompt outside a fence block, or with a credential still in it (a canary token in the stubbed collector text must be absent from the prompt; paired with M1)"
  - id: N3
    text: "the Gemini system text or prompt tells it to run kubectl or any command"
  - id: N4
    text: "the ask path starts a subprocess while serving a gemini ask (the collector stubbed; subprocess and spawn primitives faked and asserted uncalled)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    kind: offline
    intent: "tests run the Gemini ask with a stub Gemini that records its prompt and a stub Hostinger collector, for four cases: a Hostinger question, a question about something else, a Hostinger mention only in earlier job output, and a collector that fails or hangs. They read the recorded prompt, the reply, whether a bug file appeared, and whether anything was spawned. They also check that the webhook's hostinger-status report is the same as before."
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the webhook restarts on the fixed code, the operator asks in Slack 'gemini show me the current hostinger status' and gets an answer that cites real Hostinger service status"
interface:
  - "webhook.agent._run_cluster_ask(job_id, 'gemini', question, response_url, thread_ts=None, user_question=None), with webhook.agent._call_gemini stubbed"
  - "webhook.status._hostinger_status_text() — the collector, stubbed in tests"
  - "webhook.status._run_hostinger_status(job_id, response_url) with webhook.status._smoke_test_services stubbed"
  - "the Slack ask route in bin/k3dm-webhook, passing user_question"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- Replies name `/cluster-status hostinger`: the `/hostinger-status` Slack command is being retired
  (`docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md`). The webhook route and
  `_run_hostinger_status` stay. Operator, 2026-11-08: the command named in M3/M4 changed; the E1 and E2 intents did not.
- The Slack command is `/hostinger-status`, a slash command of its own (`workers/slack-relay/index.js:1,460`). `/k3dm hostinger-status` is parsed as a make target and fails with `unknown target` (operator screenshot, 2026-11-08).
- First-pass trial dispatch 1 of 3 (`docs/howto/dispatch-first-pass-trial.md`). The spec review by a separate agent
  (2026-11-08) found that the first draft named the wrong collector (`bin/cluster-status`) and missed the job-output
  injection path and the bug-filing path; this version fixes all three.
- Existing tests in `scripts/tests/bin/test_webhook_ask_delivery.py` ask gemini with no Hostinger mention and expect
  the stubbed answer verbatim; under fix step 6 they stay green.
- Stub capture: `scripts/tests/fixtures/webhook-hostinger-status-2026-11-08.txt`, the `_format_status_summary_slack`
  output for `k3s-hostinger` from a real `/cluster-status hostinger` reply in Slack (M5 hub, 2026-11-08, operator
  screenshot; Slack rendering turned back into raw markup by Claude). Use it as the stubbed `_hostinger_status_text()`
  return value; add your own canary for N2. `/hostinger-status` itself timed out in Slack ("app did not respond") the
  same morning while `/cluster-status hostinger` worked; that is a Slack app setting, not part of this fix. Fixtures assert first that no real `kubectl`, `ssh` or Gemini binary
  is reachable on PATH.
- The webhook must be restarted after the fix lands for E2 (`feedback_restart_webhook_after_verify`).
