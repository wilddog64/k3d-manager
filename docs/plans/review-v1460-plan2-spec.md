# Review: v1.46.0 plan 2 — Cloud-request Slack notification routing (blind spec review)

**Filed:** 2026-11-26
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review the specification [`docs/plans/v1.46.0-cloud-request-slack-notification-routing.md`](v1.46.0-cloud-request-slack-notification-routing.md) against the code on this branch. You get the spec and the repository,
not any other discussion. The spec was drafted on 2026-11-12 and has not been reviewed; code has landed since. Do not edit
any file; write your review as your final answer.

Answer:

- Is the problem real today, and does the design solve it? Cite file:line for every claim about current behaviour.
- What is stale: anything the spec assumes that the code on this branch no longer matches.
- Security: request data must never pick an arbitrary destination, credential or command; check every trust boundary the
  spec touches (A01 least privilege, A02 secrets in argv/logs, A03 injection).
- Answer the three "Open decisions" yourself, with reasons from the code (where the route aliases live; whether Slack `/k3dm` may pick a route; whether the default alias is separate from `SLACK_CHANNEL_ID`).
- Find every place a cloud-request Slack message is posted today (queued, running, progress, success, failure, approval card, cleanup) and say whether the design covers each one.
- Check how this interacts with the approval gate that landed on this branch (`docs/plans/v1.46.0-cloud-approval-*.md`, `docs/plans/v1.46.0-cloud-request-submitter-authentication.md`): can a route alias be set or changed by an unauthenticated or unapproved request, and does the approval card go to the routed channel or the default one?
- Contract readers and writers: list every reader and writer of each shared contract the spec changes (env var, config
  key, path, Slack channel, metric name), by grep with file:line.
- Acceptance: the spec has no `## Acceptance` YAML block yet. Propose one: `must`, `must_not` (each must be able to fail
  on the current code; say how), `evidence` items with what each proves and whether it is offline or live.
- Risk level (low / medium / high) and why.

## Output

A list of findings, most severe first, each tagged BLOCKER / MAJOR / MINOR, with file:line evidence and a concrete fix.
Then a verdict: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the report ends with a verdict and a proposed Acceptance block
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings, a proposed Acceptance block and a verdict
    intent: A second model checks this plan against today's code before it is rewritten for dispatch, so the plan you approve fixes what is really broken.
interface: none
```

**Intent approved:** operator, 2026-11-26
**Approval words and scope:** "can you have Fable/Neon review Plan2/Plan3 then have me review intents"
