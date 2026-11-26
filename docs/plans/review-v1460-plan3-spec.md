# Review: v1.46.0 plan 3 — Operator acceptance automation (blind spec review)

**Filed:** 2026-11-26
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review the specification [`docs/plans/v1.46.0-operator-acceptance-automation.md`](v1.46.0-operator-acceptance-automation.md) against the code on this branch. You get the spec and the repository,
not any other discussion. The spec was drafted on 2026-11-12 and has not been reviewed; code has landed since. Do not edit
any file; write your review as your final answer.

Answer:

- Is the problem real today, and does the design solve it? Cite file:line for every claim about current behaviour.
- What is stale: anything the spec assumes that the code on this branch no longer matches.
- Security: request data must never pick an arbitrary destination, credential or command; check every trust boundary the
  spec touches (A01 least privilege, A02 secrets in argv/logs, A03 injection).
- The plan is large. Propose a split into 2-3 child specs that can each be dispatched and verified alone (logic vs docs), with the order between them.
- Check each "Required pilot scenarios" item against the components that exist today (exporters, Pushgateway, Grafana dashboards, the cloud bridge, Slack cleanup help, the doc index) and say which oracles are real and which assume something that does not exist.
- Check the isolation section: can a default (non-live) run reach a real Slack endpoint, the real Pushgateway, production cleanup tools or the hub? Name the file:line that would stop it, or say it is missing.
- Contract readers and writers: list every reader and writer of each shared contract the spec changes (env var, config
  key, path, Slack channel, metric name), by grep with file:line.
- Acceptance: the spec has no `## Acceptance` YAML block yet. Propose one: `must`, `must_not` (each must be able to fail
  on the current code; say how), `evidence` items with what each proves and whether it is offline or live.
- Risk level (low / medium / high) and why.

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-operator-acceptance-automation.md` | read only (start here; read anything else you need) |
| `bin/k3dm-cloud-request` | read only (start here; read anything else you need) |
| `bin/k3dm-dispatch-metrics` | read only (start here; read anything else you need) |

## What NOT to Do

- Do not edit, create, stage or commit any file.

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
