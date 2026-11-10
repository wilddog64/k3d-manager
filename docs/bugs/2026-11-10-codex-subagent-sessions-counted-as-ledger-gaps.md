# Bug: Codex subagent sessions of a dispatch are counted as "Ledger gaps"

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-10
**Introduced by:** v1.43.15 (`docs/plans/v1.43.15-cost-attribution-coverage.md`: `_classify_session` re-parents only `guardian_review` sessions)
**Should have been caught by:** spec (the 2026-11-01 M4 capture the spec copied had no `thread_source: subagent` session)
**Prior art:** `make find-similar-docs` unavailable (vector store unreachable from the M4: `context "k3d-k3d-cluster" does not exist`, 2026-11-10); exact-slug glob: none
**Severity:** metric misattribution. Agent Cost "Ledger gaps" (30d) reads $1.86 / 15 sessions; $1.31 / 7 of it is dispatch work. "Dispatch coverage (by cost)" reads lower than it is.
**Approval:** operator, 2026-11-10 ("yes, please" to finding which sessions make up the ledger gap)
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "go with your suggestion"
**Dispatch:** operator go 2026-11-10 ("go with your suggestion"), `--agent codex --model gpt-6-luna`, slug `codex-subagent-ledger-gaps`; queued behind control-node-linux (WIP limit 3)
**Filed:** 2026-11-10
**Detected by:** Claude, 2026-11-10, during the cost-attribution live E3 check (operator screenshots, 30d)
**Branch:** `k3d-manager-v1.43.15`
**Release:** P3 batch

## Symptom

Local `bin/k3dm-dispatch-metrics --dry-run` on the M4, 2026-11-10, values equal to the hub dashboard. The 30d
`dispatch_unrecorded` sessions split as:

| thread_source | parent | sessions | cost |
|---|---|---|---|
| `subagent` | a ledgered dispatch session | 7 | $1.31 |
| `user` | none | 8 | $0.57 |

All 7 subagent sessions sit in the `v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust` worktree, mode `exec`,
`parent_thread_id` = the task's ledgered session `01a19c31…` (24 `codex_usage` events). The remaining $0.57 is close to
the plan's forecast of about $0.50, so the forecast held and the classifier is what drifted.

## Root cause

`bin/k3dm-dispatch-metrics:778-791` `_classify_session` handles `thread_source == "guardian_review"` first and
otherwise falls through to the worktree-cwd test, so a Codex subagent session (its own session file, its own
session ID, never written to the ledger) lands in `dispatch_unrecorded`. The guardian re-parenting at `:1882` does not
apply to it.

## Fix

A session with `thread_source == "subagent"` takes its parent's category: resolve `parent_thread_id` in the scanned
sessions (`all_scanned`), classify the parent, and count the child's sessions and cost there. A subagent whose parent is
not found keeps today's classification. Guardian handling is unchanged.

## Files

| File | Change |
|---|---|
| `bin/k3dm-dispatch-metrics` | subagent sessions inherit the parent's category |
| `scripts/tests/bin/test_dispatch_metrics.py` | cases below |

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` Ledger gaps, Dispatch coverage, Codex spend by category | No: same metric names and labels; values move between categories |
| `k3dm_dispatch_codex_sessions`, `k3dm_dispatch_unledgered_api_cost_usd` (deprecated) | No: computed from the ledger set, not from `_classify_session` |

Writers: none (the exporter is the only writer of these series). Found by `git grep -n "k3dm_codex_api_cost_usd\|k3dm_codex_sessions\|_classify_session"`, 2026-11-10.

## Acceptance

```yaml
must:
  - id: M1
    text: "A subagent session whose parent is a ledgered dispatch session adds its session and priced cost to category=dispatch, not dispatch_unrecorded."
  - id: M2
    text: "A subagent session whose parent is interactive adds to interactive (paired with M1)."
must_not:
  - id: N1
    text: "A subagent session whose parent is not among the scanned sessions is never counted as dispatch; it keeps today's category."
  - id: N2
    text: "Category costs still sum to the total priced cost; no subagent cost is counted twice."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, intent: "You will see test_dispatch_metrics.py build a temp CODEX_HOME (asserted not to be ~/.codex) with a ledgered parent, a subagent child in its worktree, a subagent of an interactive session and an orphan subagent, and check each category's count and cost and the sum; the M1 test fails on today's code."}
  - {id: E2, proves: [M1], kind: live, intent: "After the fix lands and the exporter runs on the M4, you see 30d Ledger gaps near $0.57 (8 sessions) instead of $1.86 (15), and Dispatch coverage up by the same $1.31."}
interface:
  - "bin/k3dm-dispatch-metrics --dry-run (CODEX_HOME, K3DM_WORKTREE_ROOT, --prices)"
  - "Prometheus metrics k3dm_codex_sessions{window,category}, k3dm_codex_api_cost_usd{window,category}"
```

## Worker definition of done

- Fixture `session_meta` lines copied in shape from a real subagent session file (`thread_source: subagent`,
  `parent_thread_id`), with the capture host and date in a comment; no real session ID or path.
- Show M1 red on today's code; mutants shown red: (a) classify the child without the parent lookup, (b) count the child
  under both categories.
- Run `pytest scripts/tests/bin/test_dispatch_metrics.py`; paste command, rc and proving lines. Leave changes
  uncommitted; Claude reviews and lands. Nothing against the hub or Pushgateway (`K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`).
