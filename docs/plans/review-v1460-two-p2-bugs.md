# Review: two P2 bug specs from the v1.46.0 p2b live check (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review these two bug specs against the code on this branch. You get the specs and the repository, not any other
discussion. Do not edit any file; write your review as your final answer. No network calls; never read Keychain values.

- [`docs/bugs/2026-11-27-unrouted-cloud-make-job-loses-notices-after-first.md`](../bugs/2026-11-27-unrouted-cloud-make-job-loses-notices-after-first.md)
- [`docs/bugs/2026-11-27-hub-make-test-all-exceeds-1800s-job-timeout.md`](../bugs/2026-11-27-hub-make-test-all-exceeds-1800s-job-timeout.md)

For each spec answer:

- Is the cause right? Trace the code path yourself and cite file:line. For the first, walk `_notify_job` for a job with
  no Slack context across two calls; for the second, find every reader of the test-all timeout.
- Is the fix the smallest correct one? What else could break (thread handlers, `_copy_thread_context`, relay paths,
  dashboards, alerts, the p3b live leg)? Is anything missing from `## Files` or `## Contract readers` (grep for every
  reader and writer)?
- For the timeout bug: is raising the limit before measuring justified, or should measurement come first? Is there a
  cheaper way to learn where the time goes on the hub? Could the hub slowness have a cause the spec ignores?
- Acceptance: can every `must_not` actually fail on the current code as stated? Are the evidence commands concrete
  enough for an independent verifier? Is anything untestable offline that is claimed as offline?
- Priority: is P2 right for each?

## Files

| File | Change |
|---|---|
| `docs/bugs/2026-11-27-unrouted-cloud-make-job-loses-notices-after-first.md` | read only (start here; read anything else you need) |
| `docs/bugs/2026-11-27-hub-make-test-all-exceeds-1800s-job-timeout.md` | read only |
| `bin/k3dm-webhook` | read only |
| `scripts/lib/webhook/make_targets.py` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not run cloud requests or contact the hub.

## Output

Per spec: findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix,
then a verdict READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; each spec gets a verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and two verdicts
    intent: A second model checks both bug write-ups against the code before they go to Luna and Flash, so the fixes target the real cause.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "go ahead to file those two P2 bugs and have Fable and Neon to review them"
