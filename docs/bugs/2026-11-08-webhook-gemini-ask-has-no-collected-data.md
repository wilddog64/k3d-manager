# Bug: a Slack "gemini …" status question gets "please provide kubectl output": the ask path collects nothing

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** pre-existing (the no-tools guard in `_call_gemini` dates from `fd281c85`, v1.24.0; the Gemini ask
branch has no collection step)
**Should have been caught by:** unknown
**Severity:** low — a Gemini ask about live state never gets an answer; workarounds: `/k3dm hostinger-status` (or
`cluster-status`), or ask Claude, whose ask path has read-only kubectl
**Approval:** operator, 2026-11-08 ("go ahead to file a P3 and put it on dispatch queue")
**Filed:** 2026-11-08
**Detected by:** operator, Slack, 2026-11-08 (screenshot: "gemini show me the current hostinger status")
**Affected:** `scripts/lib/webhook/agent.py` (`_run_cluster_ask`, gemini branch; `_call_gemini`)
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-10-30-webhook-ai-analysis-trusts-log-text-prompt-injection.md` (FIXED `e9cb9129`: collected
text reaches a model only through `webhook.untrusted.fence`, and its answer through `filter_suggestion`)

## Symptom

Slack, 2026-11-08, the operator: "gemini show me the current hostinger status". k3d-manager replied "Asking gemini…",
then: "🤖 gemini: The provided context contains no pre-collected data, cluster diagnostics, or telemetry regarding
Hostinger or the remote k3s environment. Please provide the relevant `kubectl` output (e.g., node status, pod states,
or ingress metrics) or Hostinger VPS status data to analyze."

## Root cause

- `_run_cluster_ask` with `agent == "gemini"` (`scripts/lib/webhook/agent.py:429-461`) builds the prompt from the
  system text, the Slack thread context and the question only. No command runs.
- `_call_gemini` (`agent.py:117-121`) prefixes: "You are analyzing pre-collected data in a HEADLESS session … Do NOT
  run any commands or call any tools … if it is insufficient, say so briefly." Gemini did exactly that.
- The Gemini system text still says to "run `kubectl describe pod …` first" (`agent.py:449-452`), which the guard
  forbids.
- The Claude and Codex ask paths run with read-only kubectl tools; the status commands (`status.py`,
  `_run_hostinger_status` → `bin/cluster-status`) collect first and pass the output through `fence(...)`. The Gemini
  ask path does neither.

## Fix

Keep the no-tools guard (it is a safety property).
- Before calling Gemini, the webhook picks a read-only collector from the question: a question naming Hostinger
  (`hostinger`, `k3s-hostinger`, `app cluster`) runs the same read-only report `hostinger-status` runs
  (`bin/cluster-status` for `k3s-hostinger`); a question naming the hub or cluster status runs the `cluster-status`
  report. Its output, bounded in size and credential-scrubbed as the status path does, goes into the prompt only
  through `fence(...)`, and the answer through `filter_suggestion`, as `status.py` does.
- A question that matches no collector is not sent to Gemini as if data were there: the reply says which command
  answers it (`/k3dm hostinger-status`, `/k3dm cluster-status`, or ask claude), or Gemini is told explicitly that no
  data was collected and must name that command. No "please provide kubectl output".
- Remove the "run `kubectl describe pod …` first" instruction from the Gemini system text.
- A collector failure or timeout is reported in the reply; Gemini is not asked to analyse an empty block.

## Files

- `scripts/lib/webhook/agent.py`
- `scripts/tests/bin/test_webhook_ask_gemini_context.py` (new)

## Acceptance

```yaml
must:
  - id: M1
    text: "a gemini ask naming Hostinger runs the read-only k3s-hostinger status report once, and the prompt given to Gemini contains that report's output inside a fence block"
  - id: M2
    text: "a gemini ask naming the hub or cluster status runs the cluster-status report, and its output reaches the prompt inside a fence block"
  - id: M3
    text: "a gemini ask matching no collector gets a reply naming the command that answers it (hostinger-status, cluster-status, or ask claude)"
  - id: M4
    text: "when the collector fails or times out, the reply says so and names the command"
must_not:
  - id: N1
    text: "the Gemini call gains tool or command permission (the no-tools guard text stays in the prompt)"
  - id: N2
    text: "collected output reaches the prompt outside a fence block, or unscrubbed of credentials (paired with M1: the fenced output is present)"
  - id: N3
    text: "the Gemini system text tells it to run kubectl or any command"
  - id: N4
    text: "a collector runs any command that changes state (only the read-only status reports are invoked)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    intent: "tests call the Gemini ask path with a stub Gemini that records its prompt and stub status reports that record their arguments, for a Hostinger question, a cluster question, an unrelated question and a failing report, and read the recorded prompt, the commands run and the Slack reply"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the webhook restarts on the fixed code, the operator asks in Slack 'gemini show me the current hostinger status' and gets an answer that cites real Hostinger node and pod state"
interface:
  - "webhook.agent._run_cluster_ask(job_id, 'gemini', question, response_url, ...) with _call_gemini and the status report command stubbed"
  - "bin/cluster-status (k3s-hostinger and hub) as the read-only collectors, invoked as the status commands invoke them"
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

- First-pass trial dispatch 1 of 3 (`docs/howto/dispatch-first-pass-trial.md`): a spec review by a second agent runs
  before intent approval, and a cross-vendor diff review runs before Claude's review.
- Stubbed status-report output must be taken from a real read-only run of `bin/cluster-status` (host and date in a
  comment), not imagined. Fixtures assert first that no real `kubectl`, `ssh` or Gemini binary is reachable on PATH.
- The webhook must be restarted after the fix lands for E2 (`feedback_restart_webhook_after_verify`).
- Needs `**Intent approved:**` before dispatch.
